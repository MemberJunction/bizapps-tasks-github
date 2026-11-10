import { LogError, type IMetadataProvider, type IRunViewProvider, type UserInfo } from '@memberjunction/core';
import { RegisterClass } from '@memberjunction/global';
import {
    ApiRoute,
    BaseServerExtension,
    ResolveConfiguredPrincipal,
    type ExtensionHealthResult,
    type ExtensionInitResult,
    type ServerExtensionConfig,
    type ServerExtensionInitContext,
    type ServerExtensionPhase,
} from '@memberjunction/server';
import { UserCache } from '@memberjunction/sqlserver-dataprovider';
import { GitHubWebhookService } from '@mj-biz-apps/tasks-github-core';

export const DEFAULT_GITHUB_WEBHOOK_SUBPATH = '/webhooks/github/tasks';
export const GITHUB_TASKS_WEBHOOK_DRIVER_CLASS = 'GitHubTasksWebhookServerExtension';

const MAX_WEBHOOK_BODY_BYTES = 10 * 1024 * 1024; // 10 MB

export interface GitHubWebhookHttpRequest {
    headers: Record<string, string | string[] | undefined>;
    rawBody?: string | Buffer;
    body?: string | Buffer | Record<string, string | number | boolean | null>;
    readable?: boolean;
    readableEnded?: boolean;
    on?: (event: 'data' | 'end' | 'error', listener: (arg?: Buffer | Error) => void) => void;
}

export interface GitHubWebhookHttpResponse {
    status(code: number): GitHubWebhookHttpResponse;
    json(payload: Record<string, string | boolean | null | undefined>): void;
}

export interface ExpressLikeWebhookApp {
    post(
        path: string,
        ...handlers: Array<(req: GitHubWebhookHttpRequest, res: GitHubWebhookHttpResponse) => void | Promise<void>>
    ): void;
}

export interface CreateGitHubTasksWebhookHandlerOptions {
    resolveContextUser?: () => UserInfo | undefined | Promise<UserInfo | undefined>;
    configuredUserEmail?: string;
    webhookSecret?: string;
    queueInference?: boolean;
    provider?: IMetadataProvider & IRunViewProvider;
}

export interface RegisterGitHubTasksWebhookRouteOptions extends CreateGitHubTasksWebhookHandlerOptions {
    /**
     * Subpath relative to MJAPI's base path (passed to `ApiRoute(subpath)`).
     * Defaults to `'/webhooks/github/tasks'`.
     */
    subpath?: string;
}

function readHeader(headers: Record<string, string | string[] | undefined>, key: string): string {
    const lowerKey = key.toLowerCase();
    for (const [k, v] of Object.entries(headers)) {
        if (k.toLowerCase() === lowerKey) {
            if (Array.isArray(v)) return v[0] ?? '';
            return v ?? '';
        }
    }
    return '';
}

/**
 * `express.json({ verify: captureRawBodyVerify })` hook that preserves the unparsed request buffer
 * on `req.rawBody` so `X-Hub-Signature-256` HMAC verification succeeds even when global `express.json()`
 * runs ahead of the webhook handler.
 */
export function captureRawBodyVerify(
    req: GitHubWebhookHttpRequest,
    _res: GitHubWebhookHttpResponse,
    buf: Buffer,
): void {
    if (Buffer.isBuffer(buf) && buf.length > 0) {
        req.rawBody = Buffer.from(buf);
    }
}

async function readStreamRawBody(req: GitHubWebhookHttpRequest): Promise<string> {
    if (typeof req.on !== 'function' || req.readable === false || req.readableEnded === true) {
        return '';
    }
    return new Promise<string>((resolve, reject) => {
        const chunks: Buffer[] = [];
        let totalBytes = 0;
        req.on!('data', (chunk?: Buffer | Error) => {
            if (!chunk || chunk instanceof Error) return;
            const buf = Buffer.isBuffer(chunk) ? chunk : Buffer.from(String(chunk));
            totalBytes += buf.length;
            if (totalBytes > MAX_WEBHOOK_BODY_BYTES) {
                reject(new Error('Webhook payload exceeds maximum allowed size'));
                return;
            }
            chunks.push(buf);
        });
        req.on!('end', () => {
            resolve(Buffer.concat(chunks).toString('utf8'));
        });
        req.on!('error', (err?: Buffer | Error) => {
            reject(err instanceof Error ? err : new Error(String(err)));
        });
    });
}

/**
 * Resolves the acting `UserInfo` for GitHub webhook processing:
 * 1. Dedicated integration user configured via `configuredUserEmail` or `GITHUB_WEBHOOK_USER_EMAIL`
 * 2. Explicit system user via `UserCache.Instance.GetSystemUser()`
 *
 * Never falls back to an arbitrary index in `UserCache.Instance.Users`.
 */
export async function resolveDefaultWebhookContextUser(
    configuredUserEmail?: string,
): Promise<UserInfo | undefined> {
    const candidate = (configuredUserEmail ?? process.env.GITHUB_WEBHOOK_USER_EMAIL ?? '').trim();
    if (candidate.length > 0) {
        const resolved = ResolveConfiguredPrincipal(candidate, 'GitHubTasksWebhook');
        if (resolved) {
            return resolved;
        }
        const byEmail = await UserCache.Instance.FindUser({ Email: candidate });
        if (byEmail && byEmail.IsActive) {
            return byEmail;
        }
    }
    return UserCache.Instance.GetSystemUser();
}

/**
 * Creates an Express-compatible HTTP POST handler for GitHub webhooks (`issues`, `pull_request`,
 * `pull_request_review`) with fail-closed `X-Hub-Signature-256` verification.
 */
export function createGitHubTasksWebhookHandler(
    options: CreateGitHubTasksWebhookHandlerOptions = {},
): (req: GitHubWebhookHttpRequest, res: GitHubWebhookHttpResponse) => Promise<void> {
    return async (req: GitHubWebhookHttpRequest, res: GitHubWebhookHttpResponse): Promise<void> => {
        const eventName = readHeader(req.headers, 'x-github-event');
        const signatureHeader = readHeader(req.headers, 'x-hub-signature-256');
        const deliveryId = readHeader(req.headers, 'x-github-delivery');
        const secret = options.webhookSecret ?? process.env.GITHUB_WEBHOOK_SECRET ?? '';

        let rawPayload = '';
        if (Buffer.isBuffer(req.rawBody)) {
            rawPayload = req.rawBody.toString('utf8');
        } else if (typeof req.rawBody === 'string') {
            rawPayload = req.rawBody;
        } else if (Buffer.isBuffer(req.body)) {
            rawPayload = req.body.toString('utf8');
        } else if (typeof req.body === 'string') {
            rawPayload = req.body;
        } else {
            try {
                rawPayload = await readStreamRawBody(req);
            } catch (streamErr) {
                LogError(streamErr instanceof Error ? streamErr : new Error(String(streamErr)));
                res.status(413).json({ ok: false, error: 'Webhook payload too large or unreadable' });
                return;
            }
        }

        if (!rawPayload) {
            res.status(400).json({ ok: false, error: 'Missing raw webhook body' });
            return;
        }

        if (!secret || !GitHubWebhookService.Instance.VerifySignature(rawPayload, signatureHeader, secret)) {
            res.status(401).json({ ok: false, error: 'X-Hub-Signature-256 HMAC-SHA256 verification failed' });
            return;
        }

        try {
            const contextUser = options.resolveContextUser
                ? await options.resolveContextUser()
                : await resolveDefaultWebhookContextUser(options.configuredUserEmail);
            if (!contextUser) {
                res.status(503).json({ ok: false, error: 'System context user unavailable' });
                return;
            }
            const outcome = await GitHubWebhookService.Instance.HandleWebhook({
                eventName,
                deliveryId,
                signatureHeader,
                rawPayload,
                webhookSecret: secret,
                runInference: false,
                queueInference: options.queueInference === true,
                contextUser,
                provider: options.provider,
            });

            if (outcome.status === 'invalid_signature') {
                res.status(401).json({ ok: false, error: outcome.reason ?? 'Invalid signature' });
                return;
            }
            if (outcome.status === 'validation_error') {
                res.status(400).json({ ok: false, error: outcome.reason ?? 'Validation error' });
                return;
            }
            res.status(200).json({
                ok: true,
                status: outcome.status,
                taskId: outcome.syncResult?.taskId ?? null,
            });
        } catch (err) {
            LogError(err instanceof Error ? err : new Error(String(err)));
            res.status(500).json({
                ok: false,
                error: 'Internal webhook processing error',
            });
        }
    };
}

/**
 * Registers the GitHub Tasks webhook POST route under MJAPI's base path via `ApiRoute()`.
 * Returns the mounted route path (e.g., `'/webhooks/github/tasks'` or `'/api/webhooks/github/tasks'`).
 */
export function registerGitHubTasksWebhookRoute(
    app: ExpressLikeWebhookApp,
    options: RegisterGitHubTasksWebhookRouteOptions = {},
): string {
    const subpath = options.subpath ?? DEFAULT_GITHUB_WEBHOOK_SUBPATH;
    const mountedPath = ApiRoute(subpath);
    const handler = createGitHubTasksWebhookHandler(options);
    app.post(mountedPath, handler);
    return mountedPath;
}

/**
 * Pre-auth MJServer extension that automatically mounts the GitHub Tasks webhook endpoint
 * when `@mj-biz-apps/tasks-github-server` is loaded as an Open App server package.
 */
@RegisterClass(BaseServerExtension, GITHUB_TASKS_WEBHOOK_DRIVER_CLASS)
export class GitHubTasksWebhookServerExtension extends BaseServerExtension {
    private _mountedRoute: string | null = null;

    public override get DefaultPhase(): ServerExtensionPhase {
        return 'pre-auth';
    }

    public async Initialize(
        contextOrApp: ServerExtensionInitContext | ExpressLikeWebhookApp,
        legacyConfig?: ServerExtensionConfig,
    ): Promise<ExtensionInitResult> {
        const isContext = 'app' in contextOrApp && 'config' in contextOrApp;
        const app: ExpressLikeWebhookApp = isContext
            ? (contextOrApp as { app: ExpressLikeWebhookApp }).app
            : (contextOrApp as ExpressLikeWebhookApp);
        const config = isContext ? (contextOrApp as ServerExtensionInitContext).config : legacyConfig;
        const rootPath = config?.RootPath ?? ApiRoute(DEFAULT_GITHUB_WEBHOOK_SUBPATH);
        const settings = (config?.Settings ?? {}) as Record<string, string | boolean | undefined>;
        const configuredUserEmail =
            typeof settings.WebhookUserEmail === 'string'
                ? settings.WebhookUserEmail
                : process.env.GITHUB_WEBHOOK_USER_EMAIL;
        const queueInference = settings.QueueInference === true;

        const handler = createGitHubTasksWebhookHandler({
            configuredUserEmail,
            queueInference,
        });
        app.post(rootPath, handler);
        this._mountedRoute = rootPath;

        return {
            Success: true,
            Message: `Mounted GitHub Tasks webhook endpoint at POST ${rootPath}`,
            RegisteredRoutes: [`POST ${rootPath}`],
        };
    }

    public async Shutdown(): Promise<void> {
        this._mountedRoute = null;
    }

    public async HealthCheck(): Promise<ExtensionHealthResult> {
        return {
            Healthy: this._mountedRoute != null,
            Name: GITHUB_TASKS_WEBHOOK_DRIVER_CLASS,
            Details: {
                route: this._mountedRoute,
                secretConfigured: Boolean(process.env.GITHUB_WEBHOOK_SECRET?.trim()),
            },
        };
    }
}

export const MJ_SERVER_EXTENSIONS: ServerExtensionConfig[] = [
    {
        Enabled: true,
        DriverClass: GITHUB_TASKS_WEBHOOK_DRIVER_CLASS,
        RootPath: DEFAULT_GITHUB_WEBHOOK_SUBPATH,
        Phase: 'pre-auth',
        Settings: {},
    },
];
