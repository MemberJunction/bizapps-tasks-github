import { LogError, type IMetadataProvider, type IRunViewProvider, type UserInfo } from '@memberjunction/core';
import {
    GitHubWebhookService,
    HasConfiguredGitHubWebhookSecret,
    ResolveGitHubWebhookSecret,
} from '@mj-biz-apps/tasks-github-core';
import { resolveDefaultWebhookContextUser } from './webhookMiddleware.js';

export const DEFAULT_PILOT_GITHUB_WEBHOOK_PATH = '/webhooks/github';
export const DEFAULT_PILOT_MAX_WEBHOOK_BODY_BYTES = 10 * 1024 * 1024; // 10 MiB

export interface GitHubWebhookHealthPayload {
    status: 'ok';
    endpoint: string;
    secretConfigured: boolean;
}

export interface GitHubWebhookDeliveryResponsePayload {
    ok: boolean;
    status?: 'synced' | 'ignored' | 'accepted' | 'invalid_signature' | 'validation_error';
    deliveryId?: string | null;
    taskId?: string | null;
    error?: string;
}

export type GitHubWebhookBootstrapJsonPayload =
    | GitHubWebhookHealthPayload
    | GitHubWebhookDeliveryResponsePayload
    | Record<string, string | number | boolean | null | undefined>;

export interface IGitHubWebhookRequest {
    headers: Record<string, string | string[] | undefined>;
    rawBody?: Buffer | string;
    body?: Buffer | string | Record<string, string | number | boolean | null>;
    readable?: boolean;
    readableEnded?: boolean;
    on?: (event: 'data' | 'end' | 'error', listener: (arg?: Buffer | string | Error) => void) => void;
}

export interface IGitHubWebhookResponse {
    status(code: number): IGitHubWebhookResponse;
    json(payload: GitHubWebhookBootstrapJsonPayload): void;
}

export type GitHubWebhookRouteHandler = (
    req: IGitHubWebhookRequest,
    res: IGitHubWebhookResponse,
) => void | Promise<void>;

/**
 * Minimal structural Express-compatible application surface required by
 * {@link MountGitHubWebhookEndpoint}. Compatible with `express.Application` and `express.Router`
 * without requiring `@types/express` in consumer packages.
 */
export interface IGitHubWebhookHostApp {
    get(path: string, ...handlers: GitHubWebhookRouteHandler[]): void;
    post(path: string, ...handlers: GitHubWebhookRouteHandler[]): void;
}

export interface GitHubWebhookMountOptions {
    /**
     * Base webhook route path to mount on `app`.
     * Registers `POST <path>` for GitHub webhook deliveries and `GET <path>/health` for readiness checks.
     * Defaults to `'/webhooks/github'`.
     */
    path?: string;
    /**
     * Explicit HMAC-SHA256 webhook secret. Falls back to `GITHUB_WEBHOOK_SECRET` or MJ Vault
     * (`credentialId` / `GitHub Webhook` credential) when omitted.
     */
    webhookSecret?: string;
    /**
     * Optional MJ Vault `MJ: Credentials` ID containing `webhookSecret`.
     */
    credentialId?: string;
    /**
     * Maximum allowed raw UTF-8 webhook payload size in bytes. Defaults to 10 MiB (`10_485_760`).
     * Requests exceeding this byte limit are rejected with HTTP `413` before HMAC/JSON processing.
     */
    maxBodyBytes?: number;
    /**
     * Resolves the acting MemberJunction `UserInfo` for `RunView` and entity saves during webhook sync.
     * Defaults to `resolveDefaultWebhookContextUser` (`GITHUB_WEBHOOK_USER_EMAIL` or system user).
     */
    resolveContextUser?: () => UserInfo | undefined | Promise<UserInfo | undefined>;
    /**
     * Optional email override passed to `resolveDefaultWebhookContextUser` when `resolveContextUser` is omitted.
     */
    configuredUserEmail?: string;
    /**
     * When `true` (default), verified deliveries are immediately processed through
     * `GitHubWebhookService.Instance.HandleWebhook`. When `false`, verifies HMAC-SHA256 signature and JSON
     * envelope and responds `{ ok: true, status: 'accepted' }` without executing task sync.
     */
    autoProcessDelivery?: boolean;
    /**
     * When `true`, queues debounced background planning field inference for mapped contributors.
     */
    queueInference?: boolean;
    /**
     * Optional custom metadata / `RunView` provider for isolated server hosts or tests.
     */
    provider?: IMetadataProvider & IRunViewProvider;
}

export interface MountedGitHubWebhookEndpoint {
    endpoint: string;
    healthEndpoint: string;
    maxBodyBytes: number;
    healthHandler: GitHubWebhookRouteHandler;
    deliveryHandler: GitHubWebhookRouteHandler;
}

class WebhookPayloadTooLargeError extends Error {
    public constructor(maxBodyBytes: number) {
        super(`Webhook payload exceeds maximum allowed size of ${maxBodyBytes} bytes`);
        this.name = 'WebhookPayloadTooLargeError';
    }
}

function normalizeWebhookMountPath(rawPath: string | undefined): string {
    const trimmed = (rawPath ?? '').trim();
    if (!trimmed) {
        return DEFAULT_PILOT_GITHUB_WEBHOOK_PATH;
    }
    const withLeadingSlash = trimmed.startsWith('/') ? trimmed : `/${trimmed}`;
    if (withLeadingSlash === '/') {
        return '/';
    }
    let end = withLeadingSlash.length;
    while (end > 1 && withLeadingSlash.charCodeAt(end - 1) === 47 /* / */) {
        end -= 1;
    }
    return end === withLeadingSlash.length ? withLeadingSlash : withLeadingSlash.slice(0, end);
}

function readHeaderValue(headers: Record<string, string | string[] | undefined>, headerName: string): string {
    const lowerTarget = headerName.toLowerCase();
    for (const [key, value] of Object.entries(headers)) {
        if (key.toLowerCase() === lowerTarget) {
            if (Array.isArray(value)) {
                return value[0] ?? '';
            }
            return value ?? '';
        }
    }
    return '';
}

async function readRawRequestBuffer(req: IGitHubWebhookRequest, maxBodyBytes: number): Promise<Buffer | null> {
    if (Buffer.isBuffer(req.rawBody)) {
        if (req.rawBody.byteLength > maxBodyBytes) {
            throw new WebhookPayloadTooLargeError(maxBodyBytes);
        }
        return req.rawBody;
    }
    if (typeof req.rawBody === 'string') {
        const buf = Buffer.from(req.rawBody, 'utf8');
        if (buf.byteLength > maxBodyBytes) {
            throw new WebhookPayloadTooLargeError(maxBodyBytes);
        }
        return buf;
    }
    if (Buffer.isBuffer(req.body)) {
        if (req.body.byteLength > maxBodyBytes) {
            throw new WebhookPayloadTooLargeError(maxBodyBytes);
        }
        return req.body;
    }
    if (typeof req.body === 'string') {
        const buf = Buffer.from(req.body, 'utf8');
        if (buf.byteLength > maxBodyBytes) {
            throw new WebhookPayloadTooLargeError(maxBodyBytes);
        }
        return buf;
    }

    if (typeof req.on !== 'function' || req.readable === false || req.readableEnded === true) {
        return null;
    }

    return new Promise<Buffer>((resolve, reject) => {
        const chunks: Buffer[] = [];
        let totalBytes = 0;
        let settled = false;

        req.on!('data', (chunk?: Buffer | string | Error) => {
            if (settled || chunk === undefined || chunk instanceof Error) {
                return;
            }
            const buf = Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk, 'utf8');
            totalBytes += buf.byteLength;
            if (totalBytes > maxBodyBytes) {
                settled = true;
                reject(new WebhookPayloadTooLargeError(maxBodyBytes));
                return;
            }
            chunks.push(buf);
        });

        req.on!('end', () => {
            if (settled) {
                return;
            }
            settled = true;
            resolve(Buffer.concat(chunks));
        });

        req.on!('error', (err?: Buffer | string | Error) => {
            if (settled) {
                return;
            }
            settled = true;
            reject(err instanceof Error ? err : new Error(String(err ?? 'Webhook stream error')));
        });
    });
}

async function resolveOptionalContextUser(options: GitHubWebhookMountOptions): Promise<UserInfo | undefined> {
    if (options.resolveContextUser) {
        return options.resolveContextUser();
    }
    try {
        return await resolveDefaultWebhookContextUser(options.configuredUserEmail);
    } catch {
        return undefined;
    }
}

async function resolveEffectiveWebhookSecret(
    options: GitHubWebhookMountOptions,
    contextUser: UserInfo | undefined,
): Promise<string | null> {
    const immediate = (options.webhookSecret ?? process.env.GITHUB_WEBHOOK_SECRET ?? '').trim();
    if (immediate.length > 0) {
        return immediate;
    }
    return ResolveGitHubWebhookSecret({
        credentialId: options.credentialId,
        contextUser,
        provider: options.provider,
    });
}

/**
 * One-line Express host bootstrap helper for mounting the GitHub Tasks webhook endpoint on MJAPI
 * without requiring host-level `express.json({ verify })` boilerplate when mounted ahead of body parsers
 * (while remaining 100% compatible with pre-buffered `req.rawBody` / `Buffer` / `string` bodies).
 *
 * Exposes:
 * - `GET <path>/health` -> `{ status: 'ok', endpoint, secretConfigured }`
 * - `POST <path>` -> fail-closed HMAC-SHA256 verification over exact UTF-8 payload bytes + delivery processing
 */
export function MountGitHubWebhookEndpoint(
    app: IGitHubWebhookHostApp,
    options: GitHubWebhookMountOptions = {},
): MountedGitHubWebhookEndpoint {
    const endpoint = normalizeWebhookMountPath(options.path);
    const healthEndpoint = endpoint === '/' ? '/health' : `${endpoint}/health`;
    const maxBodyBytes =
        typeof options.maxBodyBytes === 'number' && Number.isFinite(options.maxBodyBytes) && options.maxBodyBytes > 0
            ? Math.floor(options.maxBodyBytes)
            : DEFAULT_PILOT_MAX_WEBHOOK_BODY_BYTES;
    const autoProcessDelivery = options.autoProcessDelivery !== false;

    const healthHandler: GitHubWebhookRouteHandler = async (_req, res) => {
        const immediateConfigured = (options.webhookSecret ?? process.env.GITHUB_WEBHOOK_SECRET ?? '').trim().length > 0;
        let secretConfigured = immediateConfigured;
        if (!secretConfigured) {
            try {
                const contextUser = await resolveOptionalContextUser(options);
                secretConfigured = await HasConfiguredGitHubWebhookSecret({
                    credentialId: options.credentialId,
                    contextUser,
                    provider: options.provider,
                });
            } catch {
                secretConfigured = false;
            }
        }
        res.status(200).json({
            status: 'ok',
            endpoint,
            secretConfigured,
        });
    };

    const deliveryHandler: GitHubWebhookRouteHandler = async (req, res) => {
        const eventName = readHeaderValue(req.headers, 'x-github-event');
        const signatureHeader = readHeaderValue(req.headers, 'x-hub-signature-256');
        const deliveryId = readHeaderValue(req.headers, 'x-github-delivery').trim();

        const contentLengthHeader = readHeaderValue(req.headers, 'content-length').trim();
        if (contentLengthHeader.length > 0) {
            const declaredBytes = Number.parseInt(contentLengthHeader, 10);
            if (Number.isFinite(declaredBytes) && declaredBytes > maxBodyBytes) {
                res.status(413).json({
                    ok: false,
                    error: `Webhook payload exceeds maximum allowed size of ${maxBodyBytes} bytes`,
                });
                return;
            }
        }

        let rawBuffer: Buffer | null = null;
        try {
            rawBuffer = await readRawRequestBuffer(req, maxBodyBytes);
        } catch (err) {
            if (err instanceof WebhookPayloadTooLargeError) {
                res.status(413).json({
                    ok: false,
                    error: err.message,
                });
                return;
            }
            LogError(err instanceof Error ? err : new Error(String(err)));
            res.status(400).json({
                ok: false,
                error: 'Unreadable raw webhook request stream',
            });
            return;
        }

        if (!rawBuffer || rawBuffer.byteLength === 0) {
            res.status(400).json({
                ok: false,
                error: 'Missing raw webhook body',
            });
            return;
        }

        const rawPayload = rawBuffer.toString('utf8');

        if (!signatureHeader || !signatureHeader.startsWith('sha256=')) {
            res.status(401).json({
                ok: false,
                error: 'X-Hub-Signature-256 HMAC-SHA256 verification failed',
            });
            return;
        }

        try {
            const immediateSecret = (options.webhookSecret ?? process.env.GITHUB_WEBHOOK_SECRET ?? '').trim();
            let contextUser: UserInfo | undefined = undefined;
            let resolvedContextUser = false;

            let effectiveSecret: string | null = immediateSecret.length > 0 ? immediateSecret : null;
            if (!effectiveSecret) {
                contextUser = options.resolveContextUser
                    ? await options.resolveContextUser()
                    : await resolveDefaultWebhookContextUser(options.configuredUserEmail);
                resolvedContextUser = true;
                effectiveSecret = await resolveEffectiveWebhookSecret(options, contextUser);
            }

            if (!effectiveSecret) {
                res.status(401).json({
                    ok: false,
                    error: 'Webhook secret is not configured; refusing unverified delivery (fail-closed)',
                });
                return;
            }

            if (!GitHubWebhookService.Instance.VerifySignature(rawPayload, signatureHeader, effectiveSecret)) {
                res.status(401).json({
                    ok: false,
                    error: 'X-Hub-Signature-256 HMAC-SHA256 verification failed',
                });
                return;
            }

            if (!autoProcessDelivery) {
                try {
                    const parsed: Record<string, object | string | number | boolean | null> | null = JSON.parse(rawPayload);
                    if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) {
                        res.status(400).json({
                            ok: false,
                            error: 'Webhook payload must be a JSON object',
                        });
                        return;
                    }
                } catch {
                    res.status(400).json({
                        ok: false,
                        error: 'Webhook payload is not valid JSON',
                    });
                    return;
                }

                res.status(200).json({
                    ok: true,
                    status: 'accepted',
                    deliveryId: deliveryId || null,
                    taskId: null,
                });
                return;
            }

            if (!resolvedContextUser) {
                contextUser = options.resolveContextUser
                    ? await options.resolveContextUser()
                    : await resolveDefaultWebhookContextUser(options.configuredUserEmail);
            }

            if (!contextUser) {
                res.status(503).json({
                    ok: false,
                    error: 'System context user unavailable',
                });
                return;
            }

            const outcome = await GitHubWebhookService.Instance.HandleWebhook({
                eventName,
                deliveryId: deliveryId || undefined,
                signatureHeader,
                rawPayload,
                webhookSecret: effectiveSecret,
                runInference: false,
                queueInference: options.queueInference === true,
                contextUser,
                provider: options.provider,
            });

            if (outcome.status === 'invalid_signature') {
                res.status(401).json({
                    ok: false,
                    error: outcome.reason ?? 'X-Hub-Signature-256 HMAC-SHA256 verification failed',
                });
                return;
            }

            if (outcome.status === 'validation_error') {
                res.status(400).json({
                    ok: false,
                    error: outcome.reason ?? 'Validation error',
                });
                return;
            }

            res.status(200).json({
                ok: true,
                status: outcome.status,
                deliveryId: deliveryId || null,
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

    app.get(healthEndpoint, healthHandler);
    app.post(endpoint, deliveryHandler);

    return {
        endpoint,
        healthEndpoint,
        maxBodyBytes,
        healthHandler,
        deliveryHandler,
    };
}
