import { createHmac } from 'node:crypto';
import { EventEmitter } from 'node:events';
import { afterEach, describe, expect, it, vi } from 'vitest';
import type { UserInfo } from '@memberjunction/core';
import { GitHubWebhookService } from '@mj-biz-apps/tasks-github-core';

vi.mock('../generated/generated.js', () => ({}));

vi.mock('@memberjunction/server', () => ({
    ApiRoute: (subpath: string) => subpath,
    ResolveConfiguredPrincipal: () => undefined,
    BaseServerExtension: class BaseServerExtension {},
}));

vi.mock('@memberjunction/sqlserver-dataprovider', () => ({
    UserCache: {
        Instance: {
            FindUser: async () => undefined,
            GetSystemUser: () => undefined,
        },
    },
}));

import {
    DEFAULT_PILOT_GITHUB_WEBHOOK_PATH,
    MountGitHubWebhookEndpoint,
    type GitHubWebhookBootstrapJsonPayload,
    type GitHubWebhookRouteHandler,
    type IGitHubWebhookHostApp,
    type IGitHubWebhookRequest,
    type IGitHubWebhookResponse,
} from '../index.js';

interface CapturedResponse {
    statusCode: number;
    body: GitHubWebhookBootstrapJsonPayload | null;
    res: IGitHubWebhookResponse;
}

function createMockResponse(): CapturedResponse {
    const captured: CapturedResponse = {
        statusCode: 0,
        body: null,
        res: {
            status(code: number): IGitHubWebhookResponse {
                captured.statusCode = code;
                return captured.res;
            },
            json(payload: GitHubWebhookBootstrapJsonPayload): void {
                captured.body = payload;
            },
        },
    };
    return captured;
}

class MockHostApp implements IGitHubWebhookHostApp {
    public readonly getRoutes = new Map<string, GitHubWebhookRouteHandler>();
    public readonly postRoutes = new Map<string, GitHubWebhookRouteHandler>();

    public get(path: string, ...handlers: GitHubWebhookRouteHandler[]): void {
        const last = handlers[handlers.length - 1];
        if (last) {
            this.getRoutes.set(path, last);
        }
    }

    public post(path: string, ...handlers: GitHubWebhookRouteHandler[]): void {
        const last = handlers[handlers.length - 1];
        if (last) {
            this.postRoutes.set(path, last);
        }
    }
}

function signPayload(rawPayload: string, secret: string): string {
    return `sha256=${createHmac('sha256', secret).update(rawPayload, 'utf8').digest('hex')}`;
}

function createChunkedStreamRequest(
    headers: Record<string, string>,
    chunks: Buffer[],
): IGitHubWebhookRequest {
    const emitter = new EventEmitter();
    const req: IGitHubWebhookRequest = {
        headers,
        readable: true,
        readableEnded: false,
        on(event: 'data' | 'end' | 'error', listener: (arg?: Buffer | string | Error) => void): void {
            emitter.on(event, listener);
        },
    };

    queueMicrotask(() => {
        for (const chunk of chunks) {
            emitter.emit('data', chunk);
        }
        req.readableEnded = true;
        emitter.emit('end');
    });

    return req;
}

const TEST_CONTEXT_USER = {
    ID: '99999999-9999-4999-8999-000000000099',
    Email: 'webhook-bot@example.com',
    IsActive: true,
} as UserInfo;

describe('MountGitHubWebhookEndpoint (Pilot Express Webhook Bootstrap)', () => {
    afterEach(() => {
        vi.restoreAllMocks();
        GitHubWebhookService.Instance.ClearProcessedDeliveries();
    });

    it('exposes GET <path>/health readiness JSON on default and custom paths', async () => {
        const prevSecret = process.env.GITHUB_WEBHOOK_SECRET;
        try {
            delete process.env.GITHUB_WEBHOOK_SECRET;

            const unconfiguredApp = new MockHostApp();
            const mountedDefault = MountGitHubWebhookEndpoint(unconfiguredApp);
            expect(mountedDefault.endpoint).toBe(DEFAULT_PILOT_GITHUB_WEBHOOK_PATH);
            expect(mountedDefault.healthEndpoint).toBe('/webhooks/github/health');

            const healthHandler = unconfiguredApp.getRoutes.get('/webhooks/github/health');
            expect(healthHandler).toBeDefined();

            const unconfiguredRes = createMockResponse();
            await healthHandler!({ headers: {} }, unconfiguredRes.res);
            expect(unconfiguredRes.statusCode).toBe(200);
            expect(unconfiguredRes.body).toEqual({
                status: 'ok',
                endpoint: '/webhooks/github',
                secretConfigured: false,
            });

            const configuredApp = new MockHostApp();
            const mountedCustom = MountGitHubWebhookEndpoint(configuredApp, {
                path: 'custom/github-webhook///',
                webhookSecret: 'pilot-secret-xyz',
            });
            expect(mountedCustom.endpoint).toBe('/custom/github-webhook');
            expect(mountedCustom.healthEndpoint).toBe('/custom/github-webhook/health');

            const customHealthHandler = configuredApp.getRoutes.get('/custom/github-webhook/health');
            const configuredRes = createMockResponse();
            await customHealthHandler!({ headers: {} }, configuredRes.res);
            expect(configuredRes.statusCode).toBe(200);
            expect(configuredRes.body).toEqual({
                status: 'ok',
                endpoint: '/custom/github-webhook',
                secretConfigured: true,
            });
        } finally {
            if (prevSecret === undefined) {
                delete process.env.GITHUB_WEBHOOK_SECRET;
            } else {
                process.env.GITHUB_WEBHOOK_SECRET = prevSecret;
            }
        }
    });

    it('verifies HMAC-SHA256 over chunked multi-byte UTF-8 streams and pre-buffered payloads, delegating to HandleWebhook', async () => {
        const handleSpy = vi
            .spyOn(GitHubWebhookService.Instance, 'HandleWebhook')
            .mockResolvedValue({
                status: 'synced',
                syncResult: {
                    action: 'created',
                    taskId: '11111111-2222-4333-8444-555555555555',
                    kind: 'issue',
                    number: 42,
                },
            });

        const app = new MockHostApp();
        const secret = 'super-secret-hmac-key';
        MountGitHubWebhookEndpoint(app, {
            webhookSecret: secret,
            resolveContextUser: () => TEST_CONTEXT_USER,
        });

        const postHandler = app.postRoutes.get('/webhooks/github')!;
        expect(postHandler).toBeDefined();

        // Payload containing multi-byte UTF-8 characters ("🚀 — café") split mid-codepoint across chunks!
        const rawJson = JSON.stringify({
            action: 'opened',
            repository: { name: 'bizapps-tasks-github', owner: { login: 'MemberJunction' } },
            issue: {
                number: 42,
                node_id: 'I_kwDO12345',
                title: 'Ship pilot 🚀 — café sync',
                html_url: 'https://github.com/MemberJunction/bizapps-tasks-github/issues/42',
                state: 'open',
            },
        });
        const fullBuf = Buffer.from(rawJson, 'utf8');
        const rocketOffset = rawJson.indexOf('🚀');
        const byteSplitIndex = Buffer.byteLength(rawJson.slice(0, rocketOffset), 'utf8') + 2; // split inside 4-byte emoji
        const chunk1 = fullBuf.subarray(0, byteSplitIndex);
        const chunk2 = fullBuf.subarray(byteSplitIndex);

        const streamReq = createChunkedStreamRequest(
            {
                'X-GitHub-Event': 'issues',
                'X-GitHub-Delivery': 'delivery-stream-42',
                'X-Hub-Signature-256': signPayload(rawJson, secret),
            },
            [chunk1, chunk2],
        );

        const streamRes = createMockResponse();
        await postHandler(streamReq, streamRes.res);

        expect(streamRes.statusCode).toBe(200);
        expect(streamRes.body).toEqual({
            ok: true,
            status: 'synced',
            deliveryId: 'delivery-stream-42',
            taskId: '11111111-2222-4333-8444-555555555555',
        });
        expect(handleSpy).toHaveBeenCalledTimes(1);
        expect(handleSpy.mock.calls[0]?.[0]?.rawPayload).toBe(rawJson);

        // Also verify pre-buffered Buffer rawBody and autoProcessDelivery: false mode
        const nonAutoApp = new MockHostApp();
        MountGitHubWebhookEndpoint(nonAutoApp, {
            webhookSecret: secret,
            autoProcessDelivery: false,
        });
        const nonAutoPost = nonAutoApp.postRoutes.get('/webhooks/github')!;
        const preBufferedRes = createMockResponse();
        await nonAutoPost(
            {
                headers: {
                    'x-github-event': 'pull_request',
                    'x-github-delivery': 'delivery-buffered-99',
                    'x-hub-signature-256': signPayload(rawJson, secret),
                },
                rawBody: Buffer.from(rawJson, 'utf8'),
            },
            preBufferedRes.res,
        );
        expect(preBufferedRes.statusCode).toBe(200);
        expect(preBufferedRes.body).toEqual({
            ok: true,
            status: 'accepted',
            deliveryId: 'delivery-buffered-99',
            taskId: null,
        });
        expect(handleSpy).toHaveBeenCalledTimes(1);
    });

    it('rejects invalid or missing HMAC-SHA256 signatures with HTTP 401', async () => {
        const handleSpy = vi.spyOn(GitHubWebhookService.Instance, 'HandleWebhook');
        const app = new MockHostApp();
        MountGitHubWebhookEndpoint(app, {
            webhookSecret: 'correct-secret',
            resolveContextUser: () => TEST_CONTEXT_USER,
        });
        const postHandler = app.postRoutes.get('/webhooks/github')!;

        // 1. Missing X-Hub-Signature-256 header
        const missingSigRes = createMockResponse();
        await postHandler(
            {
                headers: { 'x-github-event': 'issues' },
                rawBody: '{"action":"opened"}',
            },
            missingSigRes.res,
        );
        expect(missingSigRes.statusCode).toBe(401);
        expect(missingSigRes.body).toMatchObject({ ok: false });

        // 2. Signed with wrong secret
        const wrongSecretRes = createMockResponse();
        const payload = '{"action":"opened"}';
        await postHandler(
            {
                headers: {
                    'x-github-event': 'issues',
                    'x-hub-signature-256': signPayload(payload, 'wrong-secret'),
                },
                rawBody: payload,
            },
            wrongSecretRes.res,
        );
        expect(wrongSecretRes.statusCode).toBe(401);
        expect(wrongSecretRes.body).toMatchObject({ ok: false });

        // 3. Tampered payload (whitespace mutation invalidates raw HMAC)
        const tamperedRes = createMockResponse();
        await postHandler(
            {
                headers: {
                    'x-github-event': 'issues',
                    'x-hub-signature-256': signPayload(payload, 'correct-secret'),
                },
                rawBody: `${payload} `,
            },
            tamperedRes.res,
        );
        expect(tamperedRes.statusCode).toBe(401);
        expect(tamperedRes.body).toMatchObject({ ok: false });
        expect(handleSpy).not.toHaveBeenCalled();
    });

    it('rejects oversized payloads exceeding maxBodyBytes with HTTP 413 for both buffered and streamed requests', async () => {
        const handleSpy = vi.spyOn(GitHubWebhookService.Instance, 'HandleWebhook');
        const app = new MockHostApp();
        MountGitHubWebhookEndpoint(app, {
            webhookSecret: 'limit-secret',
            maxBodyBytes: 64,
            resolveContextUser: () => TEST_CONTEXT_USER,
        });
        const postHandler = app.postRoutes.get('/webhooks/github')!;

        const oversizedJson = JSON.stringify({ padding: 'x'.repeat(120) });
        const validSig = signPayload(oversizedJson, 'limit-secret');

        // 1. Pre-buffered oversized Buffer
        const bufferedRes = createMockResponse();
        await postHandler(
            {
                headers: {
                    'x-github-event': 'issues',
                    'x-hub-signature-256': validSig,
                },
                rawBody: Buffer.from(oversizedJson, 'utf8'),
            },
            bufferedRes.res,
        );
        expect(bufferedRes.statusCode).toBe(413);
        expect(bufferedRes.body).toMatchObject({ ok: false });

        // 2. Streaming chunks exceeding maxBodyBytes
        const streamedReq = createChunkedStreamRequest(
            {
                'x-github-event': 'issues',
                'x-hub-signature-256': validSig,
            },
            [Buffer.from(oversizedJson.slice(0, 40), 'utf8'), Buffer.from(oversizedJson.slice(40), 'utf8')],
        );
        const streamedRes = createMockResponse();
        await postHandler(streamedReq, streamedRes.res);
        expect(streamedRes.statusCode).toBe(413);
        expect(streamedRes.body).toMatchObject({ ok: false });

        // 3. Declared Content-Length header exceeding maxBodyBytes
        const headerRes = createMockResponse();
        await postHandler(
            {
                headers: {
                    'content-length': '2048',
                    'x-github-event': 'issues',
                    'x-hub-signature-256': validSig,
                },
                rawBody: '{}',
            },
            headerRes.res,
        );
        expect(headerRes.statusCode).toBe(413);
        expect(headerRes.body).toMatchObject({ ok: false });
        expect(handleSpy).not.toHaveBeenCalled();
    });

    it('fails closed with HTTP 401 when no webhook secret is configured', async () => {
        const prevSecret = process.env.GITHUB_WEBHOOK_SECRET;
        try {
            delete process.env.GITHUB_WEBHOOK_SECRET;

            const handleSpy = vi.spyOn(GitHubWebhookService.Instance, 'HandleWebhook');
            const app = new MockHostApp();
            MountGitHubWebhookEndpoint(app, {
                resolveContextUser: () => TEST_CONTEXT_USER,
            });
            const postHandler = app.postRoutes.get('/webhooks/github')!;

            const rawPayload = '{"zen":"Keep it logically awesome."}';
            const res = createMockResponse();
            await postHandler(
                {
                    headers: {
                        'x-github-event': 'ping',
                        'x-github-delivery': 'delivery-missing-secret',
                        'x-hub-signature-256': signPayload(rawPayload, 'any-caller-secret'),
                    },
                    rawBody: rawPayload,
                },
                res.res,
            );

            expect(res.statusCode).toBe(401);
            expect(res.body).toEqual({
                ok: false,
                error: 'Webhook secret is not configured; refusing unverified delivery (fail-closed)',
            });
            expect(handleSpy).not.toHaveBeenCalled();
        } finally {
            if (prevSecret === undefined) {
                delete process.env.GITHUB_WEBHOOK_SECRET;
            } else {
                process.env.GITHUB_WEBHOOK_SECRET = prevSecret;
            }
        }
    });
});
