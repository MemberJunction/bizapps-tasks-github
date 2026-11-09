import { createHmac } from 'node:crypto';
import { describe, expect, it } from 'vitest';
import type { UserInfo } from '@memberjunction/core';
import { createGitHubTasksWebhookHandler } from '../webhookMiddleware.js';

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
});
