import { BaseAction } from '@memberjunction/actions';
import { ActionParam, ActionResultSimple, RunActionParams } from '@memberjunction/actions-base';
import { IMetadataProvider, IRunViewProvider, LogError, Metadata, RunView } from '@memberjunction/core';
import { IsValidUUID, RegisterClass } from '@memberjunction/global';
import type { mjBizAppsTasksTaskEntity } from '@mj-biz-apps/tasks-entities';
import type {
    mjBizAppsTasksGitHubGitHubIssueTaskEntity,
    mjBizAppsTasksGitHubGitHubPullRequestTaskEntity,
    mjBizAppsTasksGitHubGitHubRepositoryEntity,
} from '@mj-biz-apps/tasks-github-entities';
import {
    AssertValidUUID,
    GITHUB_ISSUE_TASKS_ENTITY,
    GITHUB_PR_TASKS_ENTITY,
    GITHUB_REPOSITORIES_ENTITY,
    GitHubTaskInferenceService,
    GitHubTaskSyncService,
    GitHubWebhookService,
    ResolveGitHubWebhookSecret,
    TASKS_ENTITY_NAME,
    type GitHubSyncSourceMode,
} from '@mj-biz-apps/tasks-github-core';

function getStringParam(params: ActionParam[], name: string): string | null {
    const match = params.find((p) => p.Name.toLowerCase() === name.toLowerCase());
    if (!match || match.Value == null) return null;
    const str = String(match.Value).trim();
    return str.length > 0 ? str : null;
}

/**
 * Returns the exact untrimmed string parameter value (used for `RawPayload` so
 * trailing newlines or whitespace in a webhook body are preserved for HMAC verification).
 */
function getRawStringParam(params: ActionParam[], name: string): string | null {
    const match = params.find((p) => p.Name.toLowerCase() === name.toLowerCase());
    if (!match || match.Value == null) return null;
    const str = String(match.Value);
    return str.length > 0 ? str : null;
}

function getBooleanParam(params: ActionParam[], name: string, defaultVal: boolean): boolean {
    const match = params.find((p) => p.Name.toLowerCase() === name.toLowerCase());
    if (!match || match.Value == null) return defaultVal;
    if (typeof match.Value === 'boolean') return match.Value;
    const lower = String(match.Value).trim().toLowerCase();
    if (lower === 'true' || lower === '1') return true;
    if (lower === 'false' || lower === '0') return false;
    return defaultVal;
}

function setOutputParam(params: ActionParam[], name: string, value: string | number): void {
    const existing = params.find((p) => p.Name.toLowerCase() === name.toLowerCase());
    if (existing) {
        existing.Value = value;
    } else {
        params.push({
            Name: name,
            Type: 'Output',
            Value: value,
        });
    }
}

@RegisterClass(BaseAction, 'TasksGitHub.SyncRepositoryTasks')
export class SyncGitHubRepositoryTasksAction extends BaseAction {
    protected async InternalRunAction(params: RunActionParams): Promise<ActionResultSimple> {
        try {
            const repositoryId = getStringParam(params.Params, 'RepositoryID');
            if (repositoryId && !IsValidUUID(repositoryId)) {
                return {
                    Success: false,
                    ResultCode: 'VALIDATION_ERROR',
                    Message: `Invalid RepositoryID UUID: '${repositoryId}'`,
                };
            }

            // Security: The agent-facing action never accepts caller-supplied ItemsJSON payloads.
            // Items are always fetched server-side from GitHub via the configured IGitHubRepositoryFetcher.
            const rawItemsParam = getRawStringParam(params.Params, 'ItemsJSON');
            if (rawItemsParam !== null) {
                return {
                    Success: false,
                    ResultCode: 'VALIDATION_ERROR',
                    Message:
                        'ItemsJSON is not accepted by Sync GitHub Repository Tasks; items are always fetched from GitHub server-side.',
                };
            }

            const credentialId = getStringParam(params.Params, 'CredentialID');
            if (credentialId && !IsValidUUID(credentialId)) {
                return {
                    Success: false,
                    ResultCode: 'VALIDATION_ERROR',
                    Message: `Invalid CredentialID UUID: '${credentialId}'`,
                };
            }

            const companyId = getStringParam(params.Params, 'CompanyID');
            if (companyId && !IsValidUUID(companyId)) {
                return {
                    Success: false,
                    ResultCode: 'VALIDATION_ERROR',
                    Message: `Invalid CompanyID UUID: '${companyId}'`,
                };
            }

            const rawSourceMode = getStringParam(params.Params, 'SourceMode');
            let sourceMode: GitHubSyncSourceMode = 'GitHubREST';
            if (rawSourceMode !== null) {
                if (
                    rawSourceMode !== 'GitHubREST'
                    && rawSourceMode !== 'ConnectorMirror'
                    && rawSourceMode !== 'Auto'
                ) {
                    return {
                        Success: false,
                        ResultCode: 'VALIDATION_ERROR',
                        Message: `Invalid SourceMode '${rawSourceMode}'; expected 'GitHubREST', 'ConnectorMirror', or 'Auto'.`,
                    };
                }
                sourceMode = rawSourceMode;
            }

            const runInference = getBooleanParam(params.Params, 'RunInference', false);
            const provider = params.Provider as (IMetadataProvider & IRunViewProvider) | undefined;

            const summaries = await GitHubTaskSyncService.Instance.SyncRepositories({
                repositoryId,
                runInference,
                sourceMode,
                credentialId,
                companyId,
                contextUser: params.ContextUser,
                provider,
            });

            const summaryJson = JSON.stringify(summaries);
            setOutputParam(params.Params, 'SummaryJSON', summaryJson);

            return {
                Success: true,
                ResultCode: 'SUCCESS',
                Message: `Synchronized ${summaries.length} repository(ies).`,
                Params: params.Params,
            };
        } catch (error) {
            const message = error instanceof Error ? error.message : String(error);
            if (message.includes('not found')) {
                return {
                    Success: false,
                    ResultCode: 'NOT_FOUND',
                    Message: message,
                };
            }
            if (
                message.includes('Invalid sync item')
                || message.includes('Sync item ')
                || message.includes('does not belong to repository')
            ) {
                return {
                    Success: false,
                    ResultCode: 'VALIDATION_ERROR',
                    Message: message,
                };
            }
            LogError(error instanceof Error ? error : new Error(message));
            return {
                Success: false,
                ResultCode: 'FAILED',
                Message: message,
            };
        }
    }
}

@RegisterClass(BaseAction, 'TasksGitHub.HandleWebhook')
export class HandleGitHubWebhookAction extends BaseAction {
    protected async InternalRunAction(params: RunActionParams): Promise<ActionResultSimple> {
        try {
            const eventName = getStringParam(params.Params, 'EventName');
            const signatureHeader = getStringParam(params.Params, 'SignatureHeader');
            const rawPayload = getRawStringParam(params.Params, 'RawPayload');
            const deliveryId = getStringParam(params.Params, 'DeliveryID');

            if (!eventName || !signatureHeader || !rawPayload) {
                return {
                    Success: false,
                    ResultCode: 'VALIDATION_ERROR',
                    Message: 'EventName, SignatureHeader, and RawPayload are required',
                };
            }

            const provider = params.Provider as (IMetadataProvider & IRunViewProvider) | undefined;
            // Security: always read the HMAC secret exclusively from server Vault or environment, never from caller params.
            const webhookSecret = await ResolveGitHubWebhookSecret({
                contextUser: params.ContextUser,
                provider,
            });
            const res = await GitHubWebhookService.Instance.HandleWebhook({
                eventName,
                deliveryId,
                signatureHeader,
                rawPayload,
                webhookSecret,
                contextUser: params.ContextUser,
                provider,
            });

            if (res.status === 'invalid_signature') {
                return {
                    Success: false,
                    ResultCode: 'INVALID_SIGNATURE',
                    Message: res.reason ?? 'Invalid webhook signature',
                };
            }
            if (res.status === 'validation_error') {
                return {
                    Success: false,
                    ResultCode: 'VALIDATION_ERROR',
                    Message: res.reason ?? 'Invalid webhook payload',
                };
            }
            if (res.status === 'ignored') {
                return {
                    Success: true,
                    ResultCode: 'IGNORED',
                    Message: res.reason ?? 'Webhook ignored',
                    Params: params.Params,
                };
            }

            if (res.syncResult?.taskId) {
                setOutputParam(params.Params, 'TaskID', res.syncResult.taskId);
            }
            return {
                Success: true,
                ResultCode: 'SUCCESS',
                Message: `Webhook '${eventName}' synchronized Task '${res.syncResult?.taskId ?? ''}'.`,
                Params: params.Params,
            };
        } catch (error) {
            LogError(error instanceof Error ? error : new Error(String(error)));
            return {
                Success: false,
                ResultCode: 'FAILED',
                Message: error instanceof Error ? error.message : String(error),
            };
        }
    }
}

@RegisterClass(BaseAction, 'TasksGitHub.InferTaskFields')
export class InferGitHubTaskFieldsAction extends BaseAction {
    protected async InternalRunAction(params: RunActionParams): Promise<ActionResultSimple> {
        try {
            const rawTaskId = getStringParam(params.Params, 'TaskID');
            if (!rawTaskId || !IsValidUUID(rawTaskId)) {
                return {
                    Success: false,
                    ResultCode: 'VALIDATION_ERROR',
                    Message: 'A valid TaskID UUID is required',
                };
            }
            const cleanTaskId = AssertValidUUID(rawTaskId, 'TaskID');

            const customProvider = params.Provider as (IMetadataProvider & IRunViewProvider) | undefined;
            const md: IMetadataProvider = customProvider ?? Metadata.Provider;
            const rv = customProvider ? RunView.FromMetadataProvider(customProvider) : new RunView();

            const task = await md.GetEntityObject<mjBizAppsTasksTaskEntity>(TASKS_ENTITY_NAME, params.ContextUser);
            const loaded = await task.Load(cleanTaskId);
            if (!loaded) {
                return {
                    Success: false,
                    ResultCode: 'NOT_FOUND',
                    Message: `Task '${cleanTaskId}' not found`,
                };
            }

            const [issueRes, prRes] = await rv.RunViews([
                {
                    EntityName: GITHUB_ISSUE_TASKS_ENTITY,
                    ExtraFilter: `ID = '${cleanTaskId}'`,
                    MaxRows: 1,
                    ResultType: 'simple',
                },
                {
                    EntityName: GITHUB_PR_TASKS_ENTITY,
                    ExtraFilter: `ID = '${cleanTaskId}'`,
                    MaxRows: 1,
                    ResultType: 'simple',
                },
            ], params.ContextUser);

            if (!issueRes?.Success || !prRes?.Success) {
                const errMsg = issueRes?.ErrorMessage || prRes?.ErrorMessage || 'Failed to query GitHub extension rows';
                LogError(new Error(`[InferGitHubTaskFieldsAction] ${errMsg}`));
                return {
                    Success: false,
                    ResultCode: 'FAILED',
                    Message: errMsg,
                };
            }

            const issueRow = ((issueRes.Results as mjBizAppsTasksGitHubGitHubIssueTaskEntity[] | undefined) ?? [])[0] ?? null;
            const prRow = ((prRes.Results as mjBizAppsTasksGitHubGitHubPullRequestTaskEntity[] | undefined) ?? [])[0] ?? null;
            const extRow = issueRow ?? prRow;
            if (!extRow || !extRow.RepositoryID) {
                return {
                    Success: true,
                    ResultCode: 'SKIPPED',
                    Message: `Task '${cleanTaskId}' is not linked to a synced GitHub issue or pull request`,
                };
            }

            const repoRes = await rv.RunView<mjBizAppsTasksGitHubGitHubRepositoryEntity>(
                {
                    EntityName: GITHUB_REPOSITORIES_ENTITY,
                    ExtraFilter: `ID = '${AssertValidUUID(extRow.RepositoryID, 'RepositoryID')}'`,
                    MaxRows: 1,
                    ResultType: 'simple',
                },
                params.ContextUser,
            );
            if (!repoRes.Success) {
                const errMsg = repoRes.ErrorMessage || `Failed to load repository '${extRow.RepositoryID}'`;
                LogError(new Error(`[InferGitHubTaskFieldsAction] ${errMsg}`));
                return {
                    Success: false,
                    ResultCode: 'FAILED',
                    Message: errMsg,
                };
            }
            const repo = repoRes.Results?.[0] ?? null;
            const repoFullName = repo ? `${repo.Owner}/${repo.Name}` : 'unknown/unknown';

            const infRes = await GitHubTaskInferenceService.Instance.InferTaskPlanningFields({
                task,
                repositoryId: extRow.RepositoryID,
                repositoryFullName: repoFullName,
                itemKind: issueRow ? 'issue' : 'pull_request',
                number: extRow.Number ?? 0,
                title: task.Name,
                body: task.Description,
                milestoneDueAt: extRow.MilestoneDueAt,
                structuredLogins: [],
                contextUser: params.ContextUser,
                provider: customProvider,
            });

            setOutputParam(params.Params, 'SuggestionsCount', infRes.createdCount);

            return {
                Success: true,
                ResultCode: infRes.createdCount > 0 ? 'SUCCESS' : 'SKIPPED',
                Message: `Created ${infRes.createdCount} Field Suggestion(s) for Task '${cleanTaskId}'.`,
                Params: params.Params,
            };
        } catch (error) {
            LogError(error instanceof Error ? error : new Error(String(error)));
            return {
                Success: false,
                ResultCode: 'FAILED',
                Message: error instanceof Error ? error.message : String(error),
            };
        }
    }
}
