import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { LimitsConfigResolver, type UserInfo } from '@memberjunction/core';
import {
    DEFAULT_GITHUB_TASKS_LIMITS,
    GITHUB_WEBHOOK_MAX_PAYLOAD_BYTES,
    GitHubTasksLimitsResolver,
    GitHubWebhookService,
} from '@mj-biz-apps/tasks-github-core';

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
    createGitHubTasksWebhookHandler,
    MountGitHubWebhookEndpoint,
    type GitHubWebhookBootstrapJsonPayload,
    type GitHubWebhookRouteHandler,
    type IGitHubWebhookHostApp,
} from '../index.js';

class MockHostApp implements IGitHubWebhookHostApp {
    public readonly getRoutes = new Map<string, GitHubWebhookRouteHandler>();
    public readonly postRoutes = new Map<string, GitHubWebhookRouteHandler>();

    public get(path: string, ...handlers: GitHubWebhookRouteHandler[]): void {
        const last = handlers[handlers.length - 1];
        if (last) this.getRoutes.set(path, last);
    }

    public post(path: string, ...handlers: GitHubWebhookRouteHandler[]): void {
        const last = handlers[handlers.length - 1];
        if (last) this.postRoutes.set(path, last);
    }
}

describe('Server webhook limits integration', () => {
    beforeEach(() => {
        GitHubTasksLimitsResolver.Instance.ClearConfigLimits();
        LimitsConfigResolver.Instance.ClearMjConfigLimits();
    });

    afterEach(() => {
        vi.restoreAllMocks();
        GitHubTasksLimitsResolver.Instance.ClearConfigLimits();
        LimitsConfigResolver.Instance.ClearMjConfigLimits();
        GitHubWebhookService.Instance.ClearProcessedDeliveries();
    });

    it('MountGitHubWebhookEndpoint resolves Webhook.MaxBodyBytes from GitHubTasksLimitsResolver, clamps >25MiB, and falls back safely on invalid overrides', () => {
        const defaultMounted = MountGitHubWebhookEndpoint(new MockHostApp());
        expect(defaultMounted.maxBodyBytes).toBe(DEFAULT_GITHUB_TASKS_LIMITS.Webhook.MaxBodyBytes);

        GitHubTasksLimitsResolver.Instance.RegisterConfigLimits({
            Webhook: { MaxBodyBytes: 2048 },
        });
        const configuredMounted = MountGitHubWebhookEndpoint(new MockHostApp());
        expect(configuredMounted.maxBodyBytes).toBe(2048);

        // Passing >25MiB ProtocolLimit clamps to GITHUB_WEBHOOK_MAX_PAYLOAD_BYTES
        const clampedMounted = MountGitHubWebhookEndpoint(new MockHostApp(), {
            maxBodyBytes: 100 * 1024 * 1024,
        });
        expect(clampedMounted.maxBodyBytes).toBe(GITHUB_WEBHOOK_MAX_PAYLOAD_BYTES);

        // Passing invalid NaN/negative override falls back safely to configured/default MaxBodyBytes
        const invalidOverrideMounted = MountGitHubWebhookEndpoint(new MockHostApp(), {
            maxBodyBytes: Number.NaN,
        });
        expect(invalidOverrideMounted.maxBodyBytes).toBe(2048);
    });

    it('createGitHubTasksWebhookHandler enforces Webhook.MaxBodyBytes resolved via GitHubTasksLimitsResolver', async () => {
        GitHubTasksLimitsResolver.Instance.RegisterConfigLimits({
            Webhook: { MaxBodyBytes: 32 },
        });

        const handler = createGitHubTasksWebhookHandler({
            resolveContextUser: () => ({ ID: '99999999-9999-4999-8999-000000000001' } as UserInfo),
            webhookSecret: 'secret-xyz',
        });

        let statusCode = 0;
        let payload: GitHubWebhookBootstrapJsonPayload = {};
        const mockRes = {
            status(code: number) {
                statusCode = code;
                return mockRes;
            },
            json(body: Record<string, string | boolean | null | undefined>) {
                payload = body;
            },
        };

        await handler(
            {
                headers: {
                    'x-github-event': 'issues',
                    'x-hub-signature-256': 'sha256=abc',
                },
                rawBody: JSON.stringify({ oversized: 'x'.repeat(80) }),
            },
            mockRes,
        );

        expect(statusCode).toBe(413);
        expect(payload).toMatchObject({ ok: false });
    });

    it('MountGitHubWebhookEndpoint deliveryHandler re-evaluates GitHubTasksLimitsResolver dynamically per request', async () => {
        const app = new MockHostApp();
        const mounted = MountGitHubWebhookEndpoint(app, {
            webhookSecret: 'secret-dynamic',
        });
        expect(mounted.maxBodyBytes).toBe(DEFAULT_GITHUB_TASKS_LIMITS.Webhook.MaxBodyBytes);

        // Update configured Webhook.MaxBodyBytes after mount without remounting
        GitHubTasksLimitsResolver.Instance.RegisterConfigLimits({
            Webhook: { MaxBodyBytes: 40 },
        });

        let statusCode = 0;
        let payload: GitHubWebhookBootstrapJsonPayload = {};
        const mockRes = {
            status(code: number) {
                statusCode = code;
                return mockRes;
            },
            json(body: GitHubWebhookBootstrapJsonPayload) {
                payload = body;
            },
        };

        await mounted.deliveryHandler(
            {
                headers: {
                    'x-github-event': 'issues',
                    'x-hub-signature-256': 'sha256=abc',
                },
                rawBody: JSON.stringify({ oversized: 'x'.repeat(80) }),
            },
            mockRes,
        );

        expect(statusCode).toBe(413);
        expect(payload).toMatchObject({ ok: false });
    });
});
