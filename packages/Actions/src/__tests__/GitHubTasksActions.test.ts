import { createHmac } from 'node:crypto';
import { describe, expect, it } from 'vitest';
import { MJGlobal } from '@memberjunction/global';
import { BaseAction } from '@memberjunction/actions';
import type { RunActionParams } from '@memberjunction/actions-base';
import type { UserInfo } from '@memberjunction/core';
import {
    HandleGitHubWebhookAction,
    InferGitHubTaskFieldsAction,
    LoadTasksGitHubActions,
    SyncGitHubRepositoryTasksAction,
} from '../index.js';

const testUser = { ID: '99999999-9999-4999-8999-000000000001', Name: 'System' } as UserInfo;

describe('BizApps Tasks GitHub Actions', () => {
    it('registers all three GitHub Tasks actions with ClassFactory', () => {
        LoadTasksGitHubActions();
        const factory = MJGlobal.Instance.ClassFactory;

        expect(factory.GetRegistration(BaseAction, 'TasksGitHub.SyncRepositoryTasks')?.SubClass)
            .toBe(SyncGitHubRepositoryTasksAction);
        expect(factory.GetRegistration(BaseAction, 'TasksGitHub.HandleWebhook')?.SubClass)
            .toBe(HandleGitHubWebhookAction);
        expect(factory.GetRegistration(BaseAction, 'TasksGitHub.InferTaskFields')?.SubClass)
            .toBe(InferGitHubTaskFieldsAction);
    });

    it('validates invalid UUIDs, malformed JSON, and missing webhook signatures cleanly', async () => {
        const syncAction = new SyncGitHubRepositoryTasksAction();
        const badUuidRes = await syncAction.Run({
            Action: {} as RunActionParams['Action'],
            ContextUser: testUser,
            Filters: [],
            Params: [{ Name: 'RepositoryID', Type: 'Input', Value: 'invalid-uuid' }],
        });
        expect(badUuidRes.Success).toBe(false);
        expect(badUuidRes.ResultCode).toBe('VALIDATION_ERROR');

        // ItemsJSON is rejected on the agent-facing action so untrusted content cannot forge repository items
        const rejectedItemsJsonRes = await syncAction.Run({
            Action: {} as RunActionParams['Action'],
            ContextUser: testUser,
            Filters: [],
            Params: [
                { Name: 'RepositoryID', Type: 'Input', Value: '55555555-5555-4555-8555-000000000001' },
                { Name: 'ItemsJSON', Type: 'Input', Value: '[]' },
            ],
        });
        expect(rejectedItemsJsonRes.Success).toBe(false);
        expect(rejectedItemsJsonRes.ResultCode).toBe('VALIDATION_ERROR');
        expect(rejectedItemsJsonRes.Message).toContain('ItemsJSON is not accepted');

        const webhookAction = new HandleGitHubWebhookAction();
        const badSigRes = await webhookAction.Run({
            Action: {} as RunActionParams['Action'],
            ContextUser: testUser,
            Filters: [],
            Params: [
                { Name: 'EventName', Type: 'Input', Value: 'issues' },
                { Name: 'SignatureHeader', Type: 'Input', Value: 'sha256=deadbeef' },
                { Name: 'RawPayload', Type: 'Input', Value: '{}' },
            ],
        });
        expect(badSigRes.Success).toBe(false);
        expect(badSigRes.ResultCode).toBe('INVALID_SIGNATURE');

        const inferAction = new InferGitHubTaskFieldsAction();
        const badTaskIdRes = await inferAction.Run({
            Action: {} as RunActionParams['Action'],
            ContextUser: testUser,
            Filters: [],
            Params: [{ Name: 'TaskID', Type: 'Input', Value: 'bad-id' }],
        });
        expect(badTaskIdRes.Success).toBe(false);
        expect(badTaskIdRes.ResultCode).toBe('VALIDATION_ERROR');
    });

    it('ignores caller-supplied WebhookSecret parameter and verifies HMAC exclusively against server configuration', async () => {
        const previousSecret = process.env.GITHUB_WEBHOOK_SECRET;
        process.env.GITHUB_WEBHOOK_SECRET = 'server-configured-secret';
        try {
            const forgedSecret = 'attacker-forged-secret';
            const rawPayload = JSON.stringify({ zen: 'Attempted forged signature' });
            const forgedSig = `sha256=${createHmac('sha256', forgedSecret).update(rawPayload, 'utf8').digest('hex')}`;

            const webhookAction = new HandleGitHubWebhookAction();
            const forgedRes = await webhookAction.Run({
                Action: {} as RunActionParams['Action'],
                ContextUser: testUser,
                Filters: [],
                Params: [
                    { Name: 'EventName', Type: 'Input', Value: 'ping' },
                    { Name: 'SignatureHeader', Type: 'Input', Value: forgedSig },
                    { Name: 'RawPayload', Type: 'Input', Value: rawPayload },
                    { Name: 'WebhookSecret', Type: 'Input', Value: forgedSecret },
                ],
            });
            expect(forgedRes.Success).toBe(false);
            expect(forgedRes.ResultCode).toBe('INVALID_SIGNATURE');

            // Signing a RawPayload that ends with trailing newline/whitespace succeeds without trimming
            const rawWithTrailingNewline = `${JSON.stringify({ zen: 'Preserve trailing newline' })}\n`;
            const validSig = `sha256=${createHmac('sha256', 'server-configured-secret').update(rawWithTrailingNewline, 'utf8').digest('hex')}`;
            const validRes = await webhookAction.Run({
                Action: {} as RunActionParams['Action'],
                ContextUser: testUser,
                Filters: [],
                Params: [
                    { Name: 'EventName', Type: 'Input', Value: 'ping' },
                    { Name: 'SignatureHeader', Type: 'Input', Value: validSig },
                    { Name: 'RawPayload', Type: 'Input', Value: rawWithTrailingNewline },
                ],
            });
            expect(validRes.Success).toBe(true);
            expect(validRes.ResultCode).toBe('IGNORED');
        } finally {
            if (previousSecret === undefined) {
                delete process.env.GITHUB_WEBHOOK_SECRET;
            } else {
                process.env.GITHUB_WEBHOOK_SECRET = previousSecret;
            }
        }
    });
});
