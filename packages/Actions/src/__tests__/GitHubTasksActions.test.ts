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

        const badJsonRes = await syncAction.Run({
            Action: {} as RunActionParams['Action'],
            ContextUser: testUser,
            Filters: [],
            Params: [{ Name: 'ItemsJSON', Type: 'Input', Value: '{not-an-array}' }],
        });
        expect(badJsonRes.Success).toBe(false);
        expect(badJsonRes.ResultCode).toBe('VALIDATION_ERROR');

        const webhookAction = new HandleGitHubWebhookAction();
        const badSigRes = await webhookAction.Run({
            Action: {} as RunActionParams['Action'],
            ContextUser: testUser,
            Filters: [],
            Params: [
                { Name: 'EventName', Type: 'Input', Value: 'issues' },
                { Name: 'SignatureHeader', Type: 'Input', Value: 'sha256=deadbeef' },
                { Name: 'RawPayload', Type: 'Input', Value: '{}' },
                { Name: 'WebhookSecret', Type: 'Input', Value: 'my-secret' },
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
});
