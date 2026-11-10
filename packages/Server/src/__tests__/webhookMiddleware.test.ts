import { createHmac } from 'node:crypto';
import { describe, expect, it, vi } from 'vitest';
import type { UserInfo } from '@memberjunction/core';

vi.mock('@memberjunction/server', () => ({
    ApiRoute: (subpath: string) => {
        const base = (process.env.MJAPI_BASE_PATH ?? '/').replace(/\/+$/, '');
        return base && base !== '/' ? `${base}${subpath}` : subpath;
    },
    ResolveConfiguredPrincipal: () => ({ ok: false, reason: 'not configured' }),
    BaseServerExtension: class BaseServerExtension {},
}));

import {
    captureRawBodyVerify,
    createGitHubTasksWebhookHandler,
    DEFAULT_GITHUB_WEBHOOK_SUBPATH,
    GitHubTasksWebhookServerExtension,
    registerGitHubTasksWebhookRoute,
} from '../webhookMiddleware.js';

describe('BizApps Tasks GitHub Server Webhook Middleware', () => {
    it('rejects missing context user with 503, empty bodies with 400, and invalid signatures with 401', async () => {
        const noUserHandler = createGitHubTasksWebhookHandler({
            resolveContextUser: () => undefined,
            webhookSecret: 'secret-123',
        });

        let statusCode = 0;
        let responseBody: Record<string, string | boolean | null | undefined> = {};
        const mockRes = {
            status(code: number) {
                statusCode = code;
                return mockRes;
            },
            json(payload: Record<string, string | boolean | null | undefined>) {
                responseBody = payload;
            },
        };

        const rawEmptyObj = '{}';
        const validEmptySig = `sha256=${createHmac('sha256', 'secret-123').update(rawEmptyObj, 'utf8').digest('hex')}`;
        await noUserHandler(
            {
                headers: { 'x-hub-signature-256': validEmptySig, 'x-github-event': 'ping' },
                rawBody: rawEmptyObj,
            },
            mockRes,
        );
        expect(statusCode).toBe(503);
        expect(responseBody.ok).toBe(false);

        const handler = createGitHubTasksWebhookHandler({
            resolveContextUser: () => ({ ID: '99999999-9999-4999-8999-000000000001' } as UserInfo),
            webhookSecret: 'secret-123',
        });

        await handler({ headers: {} }, mockRes);
        expect(statusCode).toBe(400);
        expect(responseBody.ok).toBe(false);

        await handler(
            {
                headers: {
                    'x-github-event': 'issues',
                    'x-hub-signature-256': 'sha256=0000',
                },
                rawBody: '{"action":"opened"}',
            },
            mockRes,
        );
        expect(statusCode).toBe(401);
        expect(responseBody.ok).toBe(false);

        // Validly signed ping event returns 200 ok
        const pingBody = JSON.stringify({ zen: 'Non-blocking is better than blocking.' });
        const pingSig = `sha256=${createHmac('sha256', 'secret-123').update(pingBody, 'utf8').digest('hex')}`;
        await handler(
            {
                headers: {
                    'x-github-event': 'ping',
                    'x-hub-signature-256': pingSig,
                    'x-github-delivery': 'delivery-ping-1',
                },
                rawBody: Buffer.from(pingBody, 'utf8'),
            },
            mockRes,
        );
        expect(statusCode).toBe(200);
        expect(responseBody.ok).toBe(true);
        expect(responseBody.status).toBe('ignored');
    });

    it('registers webhook route via ApiRoute(), captures rawBody in verify callback, and masks internal error details on 500', async () => {
        const mountedPaths: string[] = [];
        const fakeApp = {
            post(path: string) {
                mountedPaths.push(path);
            },
        };
        registerGitHubTasksWebhookRoute(fakeApp, {
            resolveContextUser: () => ({ ID: '99999999-9999-4999-8999-000000000001' } as UserInfo),
            webhookSecret: 'secret-123',
        });
        expect(mountedPaths).toContain(DEFAULT_GITHUB_WEBHOOK_SUBPATH);

        // captureRawBodyVerify preserves exact buffer on req.rawBody
        const reqWithRaw: { headers: Record<string, string>; rawBody?: Buffer | string } = { headers: {} };
        const sampleBuf = Buffer.from('{"hello":"world"}', 'utf8');
        captureRawBodyVerify(reqWithRaw, {}, sampleBuf);
        expect(Buffer.isBuffer(reqWithRaw.rawBody)).toBe(true);
        expect((reqWithRaw.rawBody as Buffer).toString('utf8')).toBe('{"hello":"world"}');

        // Internal error during resolveContextUser returns generic 500 message instead of leaking raw err.message
        const throwingHandler = createGitHubTasksWebhookHandler({
            resolveContextUser: async () => {
                throw new Error('Sensitive database connection string failure');
            },
            webhookSecret: 'secret-123',
        });
        let statusCode = 0;
        let responseBody: Record<string, string | boolean | null | undefined> = {};
        const mockRes = {
            status(code: number) {
                statusCode = code;
                return mockRes;
            },
            json(payload: Record<string, string | boolean | null | undefined>) {
                responseBody = payload;
            },
        };
        const validSig = `sha256=${createHmac('sha256', 'secret-123').update('{}', 'utf8').digest('hex')}`;
        await throwingHandler(
            {
                headers: { 'x-github-event': 'ping', 'x-hub-signature-256': validSig },
                rawBody: '{}',
            },
            mockRes,
        );
        expect(statusCode).toBe(500);
        expect(responseBody.ok).toBe(false);
        expect(responseBody.error).toBe('Internal webhook processing error');
        expect(responseBody.error).not.toContain('Sensitive database');
    });

    it('mounts GitHubTasksWebhookServerExtension via ApiRoute() and reports unhealthy when GITHUB_WEBHOOK_SECRET is missing', async () => {
        const prevSecret = process.env.GITHUB_WEBHOOK_SECRET;
        const prevBasePath = process.env.MJAPI_BASE_PATH;
        try {
            delete process.env.GITHUB_WEBHOOK_SECRET;
            process.env.MJAPI_BASE_PATH = '/api';

            const mountedPaths: string[] = [];
            const fakeApp = {
                post(path: string) {
                    mountedPaths.push(path);
                },
            };

            const ext = new GitHubTasksWebhookServerExtension();
            const initRes = await ext.Initialize(
                fakeApp as Parameters<GitHubTasksWebhookServerExtension['Initialize']>[0],
                { Enabled: true, RootPath: '/webhooks/github/tasks' },
            );
            expect(initRes.Success).toBe(true);
            expect(initRes.RegisteredRoutes).toEqual(['POST /api/webhooks/github/tasks']);
            expect(mountedPaths).toEqual(['/api/webhooks/github/tasks']);

            // Without GITHUB_WEBHOOK_SECRET, HealthCheck reports Healthy: false
            const unhealthy = await ext.HealthCheck();
            expect(unhealthy.Healthy).toBe(false);
            expect(unhealthy.Details?.secretConfigured).toBe(false);

            // With GITHUB_WEBHOOK_SECRET configured, HealthCheck reports Healthy: true
            process.env.GITHUB_WEBHOOK_SECRET = 'configured-secret';
            const healthy = await ext.HealthCheck();
            expect(healthy.Healthy).toBe(true);
            expect(healthy.Details?.secretConfigured).toBe(true);
        } finally {
            if (prevSecret === undefined) {
                delete process.env.GITHUB_WEBHOOK_SECRET;
            } else {
                process.env.GITHUB_WEBHOOK_SECRET = prevSecret;
            }
            if (prevBasePath === undefined) {
                delete process.env.MJAPI_BASE_PATH;
            } else {
                process.env.MJAPI_BASE_PATH = prevBasePath;
            }
        }
    });
});
