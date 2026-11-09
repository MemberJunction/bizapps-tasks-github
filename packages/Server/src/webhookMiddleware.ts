import type { IMetadataProvider, IRunViewProvider, UserInfo } from '@memberjunction/core';
import { GitHubWebhookService } from '@mj-biz-apps/tasks-github-core';

export interface GitHubWebhookHttpRequest {
    headers: Record<string, string | string[] | undefined>;
    rawBody?: string | Buffer;
    body?: string | Record<string, string | number | boolean | null>;
}

export interface GitHubWebhookHttpResponse {
    status(code: number): GitHubWebhookHttpResponse;
    json(payload: Record<string, string | boolean | null | undefined>): void;
}

export interface CreateGitHubTasksWebhookHandlerOptions {
    resolveContextUser: () => UserInfo | undefined | Promise<UserInfo | undefined>;
    webhookSecret?: string;
    provider?: IMetadataProvider & IRunViewProvider;
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
 * Creates an Express-compatible HTTP POST handler for GitHub webhooks (`issues`, `pull_request`,
 * `pull_request_review`) with fail-closed `X-Hub-Signature-256` verification.
 */
export function createGitHubTasksWebhookHandler(
    options: CreateGitHubTasksWebhookHandlerOptions,
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
        } else if (typeof req.body === 'string') {
            rawPayload = req.body;
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
            const contextUser = await options.resolveContextUser();
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
            res.status(500).json({
                ok: false,
                error: err instanceof Error ? err.message : String(err),
            });
        }
    };
}
