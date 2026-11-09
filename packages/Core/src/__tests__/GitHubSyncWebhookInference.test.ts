import { createHmac } from 'node:crypto';
import { beforeEach, describe, expect, it } from 'vitest';
import type {
    EntityInfo,
    IMetadataProvider,
    IRunViewProvider,
    RunViewParams,
    RunViewResult,
    UserInfo,
} from '@memberjunction/core';
import {
    COMMENT_TYPES_ENTITY_NAME,
    CONVERSATION_TYPES_ENTITY_NAME,
    ENVIRONMENTS_ENTITY_NAME,
    FIELD_SUGGESTIONS_ENTITY_NAME,
    GITHUB_IDENTITIES_ENTITY,
    GITHUB_ISSUE_TASKS_ENTITY,
    GITHUB_PR_TASKS_ENTITY,
    GITHUB_REPOSITORIES_ENTITY,
    GitHubTaskInferenceService,
    GitHubTaskSyncService,
    GitHubWebhookService,
    PEOPLE_ENTITY,
    TASK_ASSIGNMENTS_ENTITY,
    TASK_ROLES_ENTITY,
    TASK_TYPE_STATUS_ENTITY,
    TASK_TYPES_ENTITY,
    TASKS_ENTITY_NAME,
} from '../index.js';

interface InMemoryRecord {
    ID: string;
    [key: string]: string | number | boolean | Date | null | undefined;
}

class FakeEntityObject {
    public ID = '';
    public LatestResult = { CompleteMessage: '' };
    private readonly _store: Map<string, InMemoryRecord>;
    private readonly _onSave?: (rec: InMemoryRecord) => void;
    [key: string]: string | number | boolean | Date | null | undefined | { CompleteMessage: string } | Map<string, InMemoryRecord> | ((rec: InMemoryRecord) => void) | (() => void) | ((id: string) => Promise<boolean>) | (() => Promise<boolean>);

    public constructor(
        store: Map<string, InMemoryRecord>,
        private readonly _idPrefix: string,
        private readonly _counter: { next: number },
        onSave?: (rec: InMemoryRecord) => void,
    ) {
        this._store = store;
        this._onSave = onSave;
    }

    public NewRecord(): void {
        const seq = String(this._counter.next++).padStart(12, '0');
        this.ID = `00000000-0000-4000-8000-${seq}`;
    }

    public async Load(id: string): Promise<boolean> {
        const found = this._store.get(id.toLowerCase());
        if (!found) return false;
        Object.assign(this, found);
        return true;
    }

    public async Save(): Promise<boolean> {
        if (!this.ID) this.NewRecord();
        const snapshot: InMemoryRecord = { ID: this.ID };
        for (const [k, v] of Object.entries(this)) {
            if (!k.startsWith('_') && k !== 'LatestResult') {
                snapshot[k] = v as string | number | boolean | Date | null | undefined;
            }
        }
        this._store.set(this.ID.toLowerCase(), snapshot);
        this._onSave?.(snapshot);
        return true;
    }

    public async Delete(): Promise<boolean> {
        return this._store.delete(this.ID.toLowerCase());
    }
}

function buildTestHarness() {
    const counter = { next: 1 };
    const stores = new Map<string, Map<string, InMemoryRecord>>();
    const getStore = (entityName: string): Map<string, InMemoryRecord> => {
        let s = stores.get(entityName);
        if (!s) {
            s = new Map<string, InMemoryRecord>();
            stores.set(entityName, s);
        }
        return s;
    };

    const TASKS_ENTITY_ID = '11111111-1111-4111-8111-000000000001';
    const PEOPLE_ENTITY_ID = '11111111-1111-4111-8111-000000000002';
    const ISSUE_TYPE_ID = '22222222-2222-4222-8222-000000000001';
    const PR_TYPE_ID = '22222222-2222-4222-8222-000000000002';
    const PRIMARY_ROLE_ID = '33333333-3333-4333-8333-000000000001';
    const REVIEWER_ROLE_ID = '33333333-3333-4333-8333-000000000002';
    const ALICE_PERSON_ID = '44444444-4444-4444-8444-000000000001';
    const BOB_PERSON_ID = '44444444-4444-4444-8444-000000000002';
    const REPO_ASSIGNED_ID = '55555555-5555-4555-8555-000000000001';
    const REPO_ALL_ID = '55555555-5555-4555-8555-000000000002';

    getStore(ENVIRONMENTS_ENTITY_NAME).set('env', { ID: '66666666-6666-4666-8666-000000000001' });
    getStore(CONVERSATION_TYPES_ENTITY_NAME).set('c', { ID: '66666666-6666-4666-8666-000000000002', Code: 'COMMENT' });
    getStore(COMMENT_TYPES_ENTITY_NAME).set('fs', { ID: '66666666-6666-4666-8666-000000000003', Code: 'FIELD_SUGGESTION' });

    getStore(TASK_TYPES_ENTITY).set(ISSUE_TYPE_ID.toLowerCase(), { ID: ISSUE_TYPE_ID, Code: 'GITHUB_ISSUE' });
    getStore(TASK_TYPES_ENTITY).set(PR_TYPE_ID.toLowerCase(), { ID: PR_TYPE_ID, Code: 'GITHUB_PR' });

    const seedStatus = (id: string, taskTypeId: string, code: string) => {
        getStore(TASK_TYPE_STATUS_ENTITY).set(id.toLowerCase(), {
            ID: id,
            TaskTypeID: taskTypeId,
            Code: code,
            IsActive: true,
        });
    };
    seedStatus('77777777-7777-4777-8777-000000000001', ISSUE_TYPE_ID, 'OPEN');
    seedStatus('77777777-7777-4777-8777-000000000002', ISSUE_TYPE_ID, 'IN_PROGRESS');
    seedStatus('77777777-7777-4777-8777-000000000003', ISSUE_TYPE_ID, 'READY_FOR_FACTORY');
    seedStatus('77777777-7777-4777-8777-000000000004', ISSUE_TYPE_ID, 'COMPLETED');
    seedStatus('77777777-7777-4777-8777-000000000005', ISSUE_TYPE_ID, 'NOT_PLANNED');
    seedStatus('77777777-7777-4777-8777-000000000011', PR_TYPE_ID, 'DRAFT');
    seedStatus('77777777-7777-4777-8777-000000000012', PR_TYPE_ID, 'OPEN');
    seedStatus('77777777-7777-4777-8777-000000000013', PR_TYPE_ID, 'REVIEW_REQUIRED');
    seedStatus('77777777-7777-4777-8777-000000000014', PR_TYPE_ID, 'CHANGES_REQUESTED');
    seedStatus('77777777-7777-4777-8777-000000000015', PR_TYPE_ID, 'APPROVED');
    seedStatus('77777777-7777-4777-8777-000000000016', PR_TYPE_ID, 'MERGED');
    seedStatus('77777777-7777-4777-8777-000000000017', PR_TYPE_ID, 'CLOSED');

    getStore(TASK_ROLES_ENTITY).set(PRIMARY_ROLE_ID.toLowerCase(), { ID: PRIMARY_ROLE_ID, Name: 'Primary' });
    getStore(TASK_ROLES_ENTITY).set(REVIEWER_ROLE_ID.toLowerCase(), { ID: REVIEWER_ROLE_ID, Name: 'Reviewer' });

    getStore(GITHUB_IDENTITIES_ENTITY).set('alice', {
        ID: '88888888-8888-4888-8888-000000000001',
        GitHubLogin: 'alice-dev',
        PersonID: ALICE_PERSON_ID,
        IsActive: true,
    });
    getStore(GITHUB_IDENTITIES_ENTITY).set('bob', {
        ID: '88888888-8888-4888-8888-000000000002',
        GitHubLogin: 'bob-reviewer',
        PersonID: BOB_PERSON_ID,
        IsActive: true,
    });

    getStore(GITHUB_REPOSITORIES_ENTITY).set(REPO_ASSIGNED_ID.toLowerCase(), {
        ID: REPO_ASSIGNED_ID,
        Owner: 'MemberJunction',
        Name: 'MJ',
        DefaultBranch: 'next',
        IsTracked: true,
        ImportRule: 'AssignedOnly',
    });
    getStore(GITHUB_REPOSITORIES_ENTITY).set(REPO_ALL_ID.toLowerCase(), {
        ID: REPO_ALL_ID,
        Owner: 'MemberJunction',
        Name: 'bizapps-tasks',
        DefaultBranch: 'next',
        IsTracked: true,
        ImportRule: 'All',
    });

    const makeEntity = (entityName: string, initial?: InMemoryRecord): FakeEntityObject => {
        const obj = new FakeEntityObject(getStore(entityName), entityName, counter, (saved) => {
            // Simulate SubtypeSelector AutoEnsureOnSave on Task save
            if (entityName === TASKS_ENTITY_NAME) {
                if (saved.TypeID === ISSUE_TYPE_ID && !getStore(GITHUB_ISSUE_TASKS_ENTITY).has(saved.ID.toLowerCase())) {
                    getStore(GITHUB_ISSUE_TASKS_ENTITY).set(saved.ID.toLowerCase(), { ID: saved.ID, State: 'open' });
                } else if (saved.TypeID === PR_TYPE_ID && !getStore(GITHUB_PR_TASKS_ENTITY).has(saved.ID.toLowerCase())) {
                    getStore(GITHUB_PR_TASKS_ENTITY).set(saved.ID.toLowerCase(), { ID: saved.ID, State: 'open', IsDraft: false });
                }
            }
        });
        if (initial) {
            Object.assign(obj, initial);
        }
        return obj;
    };

    const filterRecords = (
        entityName: string,
        extraFilter?: string,
        resultType?: string,
    ): Array<FakeEntityObject | InMemoryRecord> => {
        const all = Array.from(getStore(entityName).values());
        const filtered = all.filter((rec) => {
            if (!extraFilter) return true;
            if (entityName === GITHUB_REPOSITORIES_ENTITY) {
                const idMatch = /ID = '([^']+)'/.exec(extraFilter);
                if (idMatch) return rec.ID.toLowerCase() === idMatch[1].toLowerCase();
                const ownerMatch = /Owner = '([^']+)' AND Name = '([^']+)'/.exec(extraFilter);
                if (ownerMatch) return rec.Owner === ownerMatch[1] && rec.Name === ownerMatch[2];
                if (extraFilter.includes('IsTracked = 1')) return Boolean(rec.IsTracked);
            }
            if (entityName === GITHUB_ISSUE_TASKS_ENTITY || entityName === GITHUB_PR_TASKS_ENTITY) {
                const repoNum = /RepositoryID = '([^']+)' AND Number = (\d+)/.exec(extraFilter);
                const nodeMatch = /NodeID = '([^']+)'/.exec(extraFilter);
                if (repoNum) {
                    const byRepoNum =
                        String(rec.RepositoryID ?? '').toLowerCase() === repoNum[1].toLowerCase()
                        && rec.Number === Number(repoNum[2]);
                    const byNode = nodeMatch ? rec.NodeID === nodeMatch[1] : false;
                    return byRepoNum || byNode;
                }
                const idOnly = /^ID = '([^']+)'$/.exec(extraFilter);
                if (idOnly) return rec.ID.toLowerCase() === idOnly[1].toLowerCase();
            }
            if (entityName === TASK_ASSIGNMENTS_ENTITY) {
                const taskMatch = /TaskID = '([^']+)'/.exec(extraFilter);
                if (taskMatch) return String(rec.TaskID ?? '').toLowerCase() === taskMatch[1].toLowerCase();
            }
            if (entityName === FIELD_SUGGESTIONS_ENTITY_NAME) {
                const recMatch = /LinkedRecordID = '([^']+)'/.exec(extraFilter);
                const keyMatch = /AnchorKey = '([^']+)'/.exec(extraFilter);
                if (recMatch && keyMatch) {
                    return (
                        String(rec.LinkedRecordID ?? '').toLowerCase() === recMatch[1].toLowerCase()
                        && rec.AnchorKey === keyMatch[1]
                        && rec.Outcome == null
                        && rec.IsResolved === false
                    );
                }
            }
            return true;
        });

        if (resultType === 'entity_object') {
            return filtered.map((r) => makeEntity(entityName, r));
        }
        return filtered;
    };

    const runSingleView = async (params: RunViewParams): Promise<RunViewResult> => ({
        Success: true,
        Results: filterRecords(params.EntityName, params.ExtraFilter, params.ResultType),
        RowCount: 0,
        TotalRowCount: 0,
        ExecutionTime: 1,
        ErrorMessage: '',
    });

    const provider = {
        Entities: [
            { ID: TASKS_ENTITY_ID, Name: TASKS_ENTITY_NAME } as EntityInfo,
            { ID: PEOPLE_ENTITY_ID, Name: PEOPLE_ENTITY } as EntityInfo,
        ],
        GetEntityObject: async (entityName: string) => makeEntity(entityName),
        RunView: runSingleView,
        RunViews: async (views: RunViewParams[]) => Promise.all(views.map((v) => runSingleView(v))),
    } as Partial<IMetadataProvider & IRunViewProvider> as IMetadataProvider & IRunViewProvider;

    const contextUser = { ID: '99999999-9999-4999-8999-000000000001', Name: 'System' } as UserInfo;

    return {
        provider,
        contextUser,
        getStore,
        ids: {
            REPO_ASSIGNED_ID,
            REPO_ALL_ID,
            ALICE_PERSON_ID,
            BOB_PERSON_ID,
            PRIMARY_ROLE_ID,
            REVIEWER_ROLE_ID,
            READY_ISSUE_STATUS_ID: '77777777-7777-4777-8777-000000000003',
        },
    };
}

describe('GitHubTaskSyncService, GitHubTaskInferenceService & GitHubWebhookService', () => {
    beforeEach(() => {
        GitHubTaskInferenceService.Instance.SetExtractor({
            ExtractPlanningSuggestions: async () => ({
                suggestions: [
                    {
                        field: 'DueAt',
                        value: '2026-12-15T00:00:00.000Z',
                        confidence: 0.88,
                        rationale: 'Issue body targets Dec 15 release',
                    },
                    {
                        field: 'HoursEstimated',
                        value: 6,
                        confidence: 0.79,
                        rationale: 'Medium migration + unit test scope',
                    },
                ],
                mentionedLogins: ['@alice-dev', '@charlie-pm'],
                promptRunId: 'aaaaaaaa-aaaa-4aaa-8aaa-000000000001',
            }),
        });
    });

    it('enforces ImportRule=AssignedOnly vs All and maps Primary + Reviewer TaskAssignments', async () => {
        const h = buildTestHarness();

        const summaries = await GitHubTaskSyncService.Instance.SyncRepositories({
            repositoryId: h.ids.REPO_ASSIGNED_ID,
            items: [
                {
                    kind: 'issue',
                    number: 10,
                    nodeId: 'I_unassigned',
                    title: 'Unassigned community issue',
                    body: 'Should be skipped under AssignedOnly',
                    htmlUrl: 'https://github.com/MemberJunction/MJ/issues/10',
                    state: 'open',
                    assigneeLogins: ['external-contributor'],
                },
                {
                    kind: 'pull_request',
                    number: 11,
                    nodeId: 'PR_assigned',
                    title: 'Implement SubtypeSelector',
                    body: 'Target Dec 15',
                    htmlUrl: 'https://github.com/MemberJunction/MJ/pull/11',
                    state: 'open',
                    assigneeLogins: ['alice-dev'],
                    requestedReviewerLogins: ['bob-reviewer'],
                    headBranch: 'feat/subtype',
                    headSha: 'abc1234',
                    baseBranch: 'next',
                },
            ],
            contextUser: h.contextUser,
            provider: h.provider,
        });

        expect(summaries).toHaveLength(1);
        expect(summaries[0].skipped).toBe(1);
        expect(summaries[0].created).toBe(1);
        expect(summaries[0].inferredSuggestionsCreated).toBe(2);

        const assignments = Array.from(h.getStore(TASK_ASSIGNMENTS_ENTITY).values());
        expect(assignments).toHaveLength(2);
        expect(assignments.some((a) => a.AssigneeRecordID === h.ids.ALICE_PERSON_ID && a.RoleID === h.ids.PRIMARY_ROLE_ID)).toBe(true);
        expect(assignments.some((a) => a.AssigneeRecordID === h.ids.BOB_PERSON_ID && a.RoleID === h.ids.REVIEWER_ROLE_ID)).toBe(true);

        // ImportRule=All imports unassigned items too
        const allSummary = await GitHubTaskSyncService.Instance.SyncRepositories({
            repositoryId: h.ids.REPO_ALL_ID,
            items: [
                {
                    kind: 'issue',
                    number: 1,
                    nodeId: 'I_all_1',
                    title: 'Backlog item with no assignee',
                    body: 'Imported because ImportRule=All',
                    htmlUrl: 'https://github.com/MemberJunction/bizapps-tasks/issues/1',
                    state: 'open',
                    assigneeLogins: [],
                },
            ],
            contextUser: h.contextUser,
            provider: h.provider,
        });
        expect(allSummary[0].created).toBe(1);
    });

    it('is strictly idempotent on re-sync, preserves Tasks-owned planning fields & READY_FOR_FACTORY, and supersedes DueAt Field Suggestions when MilestoneDueAt arrives', async () => {
        const h = buildTestHarness();

        const firstSync = await GitHubTaskSyncService.Instance.SyncRepositories({
            repositoryId: h.ids.REPO_ASSIGNED_ID,
            items: [
                {
                    kind: 'issue',
                    number: 77,
                    nodeId: 'I_77',
                    title: 'Initial Title',
                    body: 'Need this by Dec 15',
                    htmlUrl: 'https://github.com/MemberJunction/MJ/issues/77',
                    state: 'open',
                    assigneeLogins: ['alice-dev'],
                },
            ],
            contextUser: h.contextUser,
            provider: h.provider,
        });

        const taskId = firstSync[0].taskIds[0];
        const taskStore = h.getStore(TASKS_ENTITY_NAME);
        const savedTask = taskStore.get(taskId.toLowerCase())!;

        // Human edits Tasks-owned planning fields and moves status to READY_FOR_FACTORY
        savedTask.Priority = 'Urgent';
        savedTask.HoursEstimated = 12;
        savedTask.ParentID = 'cccccccc-cccc-4ccc-8ccc-000000000099';
        savedTask.TaskTypeStatusID = h.ids.READY_ISSUE_STATUS_ID;

        // Re-sync with updated title + MilestoneDueAt from GitHub
        const secondSync = await GitHubTaskSyncService.Instance.SyncRepositories({
            repositoryId: h.ids.REPO_ASSIGNED_ID,
            items: [
                {
                    kind: 'issue',
                    number: 77,
                    nodeId: 'I_77',
                    title: 'Updated GitHub Title',
                    body: 'Need this by Dec 15',
                    htmlUrl: 'https://github.com/MemberJunction/MJ/issues/77',
                    state: 'open',
                    milestoneTitle: 'MJ 6.3',
                    milestoneDueAt: '2026-12-31T00:00:00.000Z',
                    assigneeLogins: ['alice-dev'],
                },
            ],
            contextUser: h.contextUser,
            provider: h.provider,
        });

        expect(secondSync[0].created).toBe(0);
        expect(secondSync[0].updated).toBe(1);
        expect(secondSync[0].supersededDueAtSuggestions).toBe(1);
        expect(taskStore.size).toBe(1);

        const updatedTask = taskStore.get(taskId.toLowerCase())!;
        expect(updatedTask.Name).toBe('Updated GitHub Title');
        expect(updatedTask.Priority).toBe('Urgent');
        expect(updatedTask.HoursEstimated).toBe(12);
        expect(updatedTask.ParentID).toBe('cccccccc-cccc-4ccc-8ccc-000000000099');
        expect(updatedTask.TaskTypeStatusID).toBe(h.ids.READY_ISSUE_STATUS_ID);

        const suggestions = Array.from(h.getStore(FIELD_SUGGESTIONS_ENTITY_NAME).values());
        const dueAtSuggestion = suggestions.find((s) => s.AnchorKey === 'DueAt')!;
        expect(dueAtSuggestion.Outcome).toBe('Superseded');
        expect(dueAtSuggestion.IsResolved).toBe(true);
    });

    it('verifies webhook HMAC-SHA256 fail-closed and syncs pull_request_review immediately', async () => {
        const h = buildTestHarness();
        const secret = 'top-secret-webhook-key';
        const payloadObj = {
            action: 'submitted',
            repository: {
                name: 'MJ',
                owner: { login: 'MemberJunction' },
            },
            pull_request: {
                number: 6491,
                node_id: 'PR_6491',
                title: 'feat(core): Work Bus & Software Factory foundation',
                body: 'Closes #77',
                html_url: 'https://github.com/MemberJunction/MJ/pull/6491',
                state: 'open',
                draft: false,
                head: { ref: 'feat/work-bus', sha: 'aa4b1c538c' },
                base: { ref: 'next' },
                assignees: [{ login: 'alice-dev' }],
                requested_reviewers: [{ login: 'bob-reviewer' }],
            },
            review: {
                state: 'approved',
            },
        };
        const rawPayload = JSON.stringify(payloadObj);
        const validSig = `sha256=${createHmac('sha256', secret).update(rawPayload, 'utf8').digest('hex')}`;

        // Missing secret fails closed
        const noSecret = await GitHubWebhookService.Instance.HandleWebhook({
            eventName: 'pull_request_review',
            signatureHeader: validSig,
            rawPayload,
            webhookSecret: '',
            contextUser: h.contextUser,
            provider: h.provider,
        });
        expect(noSecret.status).toBe('invalid_signature');

        // Tampered payload fails closed
        const tampered = await GitHubWebhookService.Instance.HandleWebhook({
            eventName: 'pull_request_review',
            signatureHeader: validSig,
            rawPayload: `${rawPayload} `,
            webhookSecret: secret,
            contextUser: h.contextUser,
            provider: h.provider,
        });
        expect(tampered.status).toBe('invalid_signature');

        // Valid signed delivery syncs immediately
        const ok = await GitHubWebhookService.Instance.HandleWebhook({
            eventName: 'pull_request_review',
            signatureHeader: validSig,
            rawPayload,
            webhookSecret: secret,
            contextUser: h.contextUser,
            provider: h.provider,
        });
        expect(ok.status).toBe('synced');
        expect(ok.syncResult?.action).toBe('created');

        const prExt = Array.from(h.getStore(GITHUB_PR_TASKS_ENTITY).values())[0];
        expect(prExt.ReviewDecision).toBe('APPROVED');
        expect(prExt.HeadSha).toBe('aa4b1c538c');

        // Ping delivery returns ignored cleanly
        const pingPayload = JSON.stringify({ zen: 'Keep it logically awesome.' });
        const pingSig = `sha256=${createHmac('sha256', secret).update(pingPayload, 'utf8').digest('hex')}`;
        const pingRes = await GitHubWebhookService.Instance.HandleWebhook({
            eventName: 'ping',
            signatureHeader: pingSig,
            rawPayload: pingPayload,
            webhookSecret: secret,
            contextUser: h.contextUser,
            provider: h.provider,
        });
        expect(pingRes.status).toBe('ignored');

        // Untracked repository delivery returns untracked_repository
        const untrackedPayload = JSON.stringify({
            action: 'opened',
            repository: { name: 'untracked-repo', owner: { login: 'MemberJunction' } },
            issue: {
                number: 1,
                node_id: 'I_u1',
                title: 'Test',
                body: '',
                html_url: 'https://github.com/MemberJunction/untracked-repo/issues/1',
                state: 'open',
            },
        });
        const untrackedSig = `sha256=${createHmac('sha256', secret).update(untrackedPayload, 'utf8').digest('hex')}`;
        const untrackedRes = await GitHubWebhookService.Instance.HandleWebhook({
            eventName: 'issues',
            signatureHeader: untrackedSig,
            rawPayload: untrackedPayload,
            webhookSecret: secret,
            contextUser: h.contextUser,
            provider: h.provider,
        });
        expect(untrackedRes.status).toBe('ignored');
        expect(untrackedRes.reason).toContain('not registered or not tracked');
    });

    it('auto-links LinkedIssueTaskID from Closes #N and supersedes prior Field Suggestions when issue body changes', async () => {
        const h = buildTestHarness();

        // First sync issue #42 + PR #43 referencing Closes #42
        const sync1 = await GitHubTaskSyncService.Instance.SyncRepositories({
            repositoryId: h.ids.REPO_ALL_ID,
            items: [
                {
                    kind: 'issue',
                    number: 42,
                    nodeId: 'I_42',
                    title: 'Support cross-vendor review',
                    body: 'Target Dec 15; ~6h',
                    htmlUrl: 'https://github.com/MemberJunction/bizapps-tasks/issues/42',
                    state: 'open',
                },
                {
                    kind: 'pull_request',
                    number: 43,
                    nodeId: 'PR_43',
                    title: 'feat: cross-vendor review',
                    body: 'Closes #42',
                    htmlUrl: 'https://github.com/MemberJunction/bizapps-tasks/pull/43',
                    state: 'open',
                },
            ],
            contextUser: h.contextUser,
            provider: h.provider,
        });

        expect(sync1[0].created).toBe(2);
        const issueTaskId = sync1[0].taskIds[0];
        const prTaskId = sync1[0].taskIds[1];
        const prExt = h.getStore(GITHUB_PR_TASKS_ENTITY).get(prTaskId.toLowerCase())!;
        expect(prExt.LinkedIssueTaskID).toBe(issueTaskId);

        // Re-sync issue #42 with identical body -> bodyChanged=false, no new suggestions
        const syncSameBody = await GitHubTaskSyncService.Instance.SyncRepositories({
            repositoryId: h.ids.REPO_ALL_ID,
            items: [
                {
                    kind: 'issue',
                    number: 42,
                    nodeId: 'I_42',
                    title: 'Support cross-vendor review',
                    body: 'Target Dec 15; ~6h',
                    htmlUrl: 'https://github.com/MemberJunction/bizapps-tasks/issues/42',
                    state: 'open',
                },
            ],
            contextUser: h.contextUser,
            provider: h.provider,
        });
        expect(syncSameBody[0].inferredSuggestionsCreated).toBe(0);

        // Now change extractor output + edit issue body -> prior pending suggestions superseded and new ones created
        GitHubTaskInferenceService.Instance.SetExtractor({
            ExtractPlanningSuggestions: async () => ({
                suggestions: [
                    {
                        field: 'DueAt',
                        value: '2026-12-22T00:00:00.000Z',
                        confidence: 0.93,
                        rationale: 'Updated target Dec 22',
                    },
                ],
                mentionedLogins: [],
                promptRunId: 'bbbbbbbb-bbbb-4bbb-8bbb-000000000002',
            }),
        });

        const syncEditedBody = await GitHubTaskSyncService.Instance.SyncRepositories({
            repositoryId: h.ids.REPO_ALL_ID,
            items: [
                {
                    kind: 'issue',
                    number: 42,
                    nodeId: 'I_42',
                    title: 'Support cross-vendor review',
                    body: 'Updated target Dec 22 after scope review',
                    htmlUrl: 'https://github.com/MemberJunction/bizapps-tasks/issues/42',
                    state: 'open',
                },
            ],
            contextUser: h.contextUser,
            provider: h.provider,
        });
        expect(syncEditedBody[0].inferredSuggestionsCreated).toBe(1);

        const issueDueSuggestions = Array.from(h.getStore(FIELD_SUGGESTIONS_ENTITY_NAME).values()).filter(
            (s) => String(s.LinkedRecordID ?? '').toLowerCase() === issueTaskId.toLowerCase() && s.AnchorKey === 'DueAt',
        );
        expect(issueDueSuggestions.some((s) => s.Outcome === 'Superseded')).toBe(true);
        expect(issueDueSuggestions.some((s) => s.Outcome == null && s.SuggestedValue === '"2026-12-22T00:00:00.000Z"')).toBe(true);
    });
});
