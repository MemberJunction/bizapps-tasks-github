import { createHmac } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import type {
    EntityInfo,
    EntityTransactionScope,
    IMetadataProvider,
    IRunViewProvider,
    RunViewParams,
    RunViewResult,
    UserInfo,
} from '@memberjunction/core';
import {
    GitHubTasksEngineBase,
    type mjBizAppsTasksGitHubGitHubRepositoryEntity,
} from '@mj-biz-apps/tasks-github-entities';
import type { mjBizAppsTasksTaskAssignmentEntity } from '@mj-biz-apps/tasks-entities';
import {
    COMMENT_TYPES_ENTITY_NAME,
    CONVERSATION_TYPES_ENTITY_NAME,
    ENVIRONMENTS_ENTITY_NAME,
    FIELD_SUGGESTIONS_ENTITY_NAME,
    GITHUB_IDENTITIES_ENTITY,
    GITHUB_ISSUE_TASKS_ENTITY,
    GITHUB_PR_TASKS_ENTITY,
    GITHUB_REPOSITORIES_ENTITY,
    GitHubFieldOwnershipPolicy,
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

const INHERITED_TASK_FIELDS = [
    'Name',
    'Description',
    'TypeID',
    'CategoryID',
    'ParentID',
    'Status',
    'Priority',
    'StartedAt',
    'DueAt',
    'CompletedAt',
    'HoursEstimated',
    'HoursActual',
    'PercentComplete',
    'Sequence',
    'BlockedReason',
    'CompletionNotes',
    'CreatedByPersonID',
    'OverdueNotifiedAt',
    'TaskTypeStatusID',
] as const;

type FakeEntityFieldValue =
    | string
    | number
    | boolean
    | Date
    | null
    | undefined
    | { CompleteMessage: string }
    | Map<string, InMemoryRecord>
    | ((rec: InMemoryRecord) => void)
    | ((id: string) => void)
    | ((id: string) => InMemoryRecord | undefined)
    | (() => void)
    | ((id: string) => Promise<boolean>)
    | (() => Promise<boolean>);

class FakeEntityObject {
    public ID = '';
    public LatestResult = { CompleteMessage: '' };
    private readonly _store: Map<string, InMemoryRecord>;
    private readonly _onSave?: (rec: InMemoryRecord) => void;
    private readonly _onDelete?: (id: string) => void;
    private readonly _onLoadParent?: (id: string) => InMemoryRecord | undefined;
    [key: string]: FakeEntityFieldValue;

    public constructor(
        store: Map<string, InMemoryRecord>,
        private readonly _idPrefix: string,
        private readonly _counter: { next: number },
        onSave?: (rec: InMemoryRecord) => void,
        onDelete?: (id: string) => void,
        onLoadParent?: (id: string) => InMemoryRecord | undefined,
    ) {
        this._store = store;
        this._onSave = onSave;
        this._onDelete = onDelete;
        this._onLoadParent = onLoadParent;
    }

    public NewRecord(): void {
        const seq = String(this._counter.next++).padStart(12, '0');
        this.ID = `00000000-0000-4000-8000-${seq}`;
    }

    public async Load(id: string): Promise<boolean> {
        const found = this._store.get(id.toLowerCase());
        if (!found) return false;
        const parentRow = this._onLoadParent?.(id.toLowerCase());
        if (parentRow) {
            Object.assign(this, parentRow);
        }
        Object.assign(this, found);
        if (parentRow) {
            // Parent Task fields (e.g. human edits to Priority/HoursEstimated/ParentID/TaskTypeStatusID) take precedence
            for (const field of INHERITED_TASK_FIELDS) {
                if (field in parentRow) {
                    this[field] = parentRow[field];
                }
            }
        }
        return true;
    }

    public async Save(): Promise<boolean> {
        if (!this.ID) this.NewRecord();
        if (
            (this._idPrefix === GITHUB_ISSUE_TASKS_ENTITY || this._idPrefix === GITHUB_PR_TASKS_ENTITY)
            && this.RepositoryID != null
            && this.Number != null
        ) {
            for (const existing of this._store.values()) {
                if (
                    existing.ID.toLowerCase() !== this.ID.toLowerCase()
                    && String(existing.RepositoryID ?? '').toLowerCase() === String(this.RepositoryID).toLowerCase()
                    && existing.Number === this.Number
                ) {
                    this.LatestResult = {
                        CompleteMessage: 'Violation of UNIQUE KEY constraint UX_GitHubIssueTask_Repo_Number',
                    };
                    return false;
                }
            }
        }
        const snapshot: InMemoryRecord = { ID: this.ID };
        for (const [k, v] of Object.entries(this)) {
            if (!k.startsWith('_') && k !== 'LatestResult' && typeof v !== 'function') {
                snapshot[k] = v as string | number | boolean | Date | null | undefined;
            }
        }
        this._store.set(this.ID.toLowerCase(), snapshot);
        this._onSave?.(snapshot);
        return true;
    }

    public async Delete(): Promise<boolean> {
        const existed = this._store.delete(this.ID.toLowerCase());
        if (existed) {
            this._onDelete?.(this.ID.toLowerCase());
        }
        return existed;
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

    const saveCounts = new Map<string, number>();
    const txStats = { began: 0, committed: 0, rolledBack: 0 };
    let activeTxDepth = 0;

    const cloneStores = (): Map<string, Map<string, InMemoryRecord>> => {
        const copy = new Map<string, Map<string, InMemoryRecord>>();
        for (const [entityName, store] of stores.entries()) {
            const inner = new Map<string, InMemoryRecord>();
            for (const [key, rec] of store.entries()) {
                inner.set(key, { ...rec });
            }
            copy.set(entityName, inner);
        }
        return copy;
    };

    const restoreStores = (snapshot: Map<string, Map<string, InMemoryRecord>>): void => {
        stores.clear();
        for (const [entityName, inner] of snapshot.entries()) {
            stores.set(entityName, inner);
        }
    };

    const makeEntity = (entityName: string, initial?: InMemoryRecord): FakeEntityObject => {
        const isIsaLeaf = entityName === GITHUB_ISSUE_TASKS_ENTITY || entityName === GITHUB_PR_TASKS_ENTITY;
        const obj = new FakeEntityObject(
            getStore(entityName),
            entityName,
            counter,
            (saved) => {
                saveCounts.set(entityName, (saveCounts.get(entityName) ?? 0) + 1);
                // Simulate MJ IS-A leaf save: saving GitHubIssueTask / GitHubPullRequestTask atomically writes parent Task row
                if (isIsaLeaf) {
                    const existingTask = getStore(TASKS_ENTITY_NAME).get(saved.ID.toLowerCase()) ?? { ID: saved.ID };
                    const mergedTask: InMemoryRecord = { ...existingTask, ID: saved.ID };
                    for (const field of INHERITED_TASK_FIELDS) {
                        if (field in saved) {
                            mergedTask[field] = saved[field];
                        }
                    }
                    getStore(TASKS_ENTITY_NAME).set(saved.ID.toLowerCase(), mergedTask);
                }
                // Simulate SubtypeSelector AutoEnsureOnSave when saving Task directly
                if (entityName === TASKS_ENTITY_NAME) {
                    if (saved.TypeID === ISSUE_TYPE_ID && !getStore(GITHUB_ISSUE_TASKS_ENTITY).has(saved.ID.toLowerCase())) {
                        getStore(GITHUB_ISSUE_TASKS_ENTITY).set(saved.ID.toLowerCase(), { ID: saved.ID, State: 'open' });
                    } else if (saved.TypeID === PR_TYPE_ID && !getStore(GITHUB_PR_TASKS_ENTITY).has(saved.ID.toLowerCase())) {
                        getStore(GITHUB_PR_TASKS_ENTITY).set(saved.ID.toLowerCase(), { ID: saved.ID, State: 'open', IsDraft: false });
                    }
                }
            },
            (deletedId) => {
                // Simulate MJ IS-A chain delete: deleting an IS-A child also deletes its parent Task row
                if (isIsaLeaf) {
                    getStore(TASKS_ENTITY_NAME).delete(deletedId);
                }
            },
            isIsaLeaf ? (id) => getStore(TASKS_ENTITY_NAME).get(id) : undefined,
        );
        if (initial) {
            if (isIsaLeaf) {
                const parentRow = getStore(TASKS_ENTITY_NAME).get(initial.ID.toLowerCase());
                if (parentRow) {
                    Object.assign(obj, parentRow);
                }
            }
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
                const headShaMatch = /HeadSha = '([^']+)'/.exec(extraFilter);
                if (repoNum || headShaMatch) {
                    const byRepoNum = repoNum
                        ? String(rec.RepositoryID ?? '').toLowerCase() === repoNum[1].toLowerCase()
                            && rec.Number === Number(repoNum[2])
                        : false;
                    const byNode = nodeMatch ? rec.NodeID === nodeMatch[1] : false;
                    const byHeadSha = headShaMatch ? rec.HeadSha === headShaMatch[1] : false;
                    return byRepoNum || byNode || byHeadSha;
                }
                const repoOpenMatch = /^RepositoryID = '([^']+)' AND Status IN \('Open', 'InProgress'\)$/.exec(extraFilter);
                if (repoOpenMatch) {
                    if (String(rec.RepositoryID ?? '').toLowerCase() !== repoOpenMatch[1].toLowerCase()) {
                        return false;
                    }
                    const parentTask = getStore(TASKS_ENTITY_NAME).get(rec.ID.toLowerCase());
                    if (!parentTask) return false;
                    const status = String(parentTask.Status ?? 'Open');
                    if (status !== 'Open' && status !== 'InProgress') return false;
                    rec.Name = parentTask.Name;
                    rec.Status = status;
                    return true;
                }
                const repoOnly = /^RepositoryID = '([^']+)'$/.exec(extraFilter);
                if (repoOnly) {
                    return String(rec.RepositoryID ?? '').toLowerCase() === repoOnly[1].toLowerCase();
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
                    if (!extraFilter.includes("AnchorType = 'Field'")) {
                        return false;
                    }
                    return (
                        String(rec.LinkedRecordID ?? '').toLowerCase() === recMatch[1].toLowerCase()
                        && rec.AnchorType === 'Field'
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

    const allowAllPerms = () => ({ CanRead: true, CanCreate: true, CanUpdate: true, CanDelete: true });
    const entitiesList = [
        { ID: TASKS_ENTITY_ID, Name: TASKS_ENTITY_NAME, PrimaryKeys: [{ Name: 'ID', IsUniqueIdentifier: true }], GetUserPermisions: allowAllPerms } as EntityInfo,
        { ID: PEOPLE_ENTITY_ID, Name: PEOPLE_ENTITY, PrimaryKeys: [{ Name: 'ID', IsUniqueIdentifier: true }], GetUserPermisions: allowAllPerms } as EntityInfo,
        { ID: '11111111-1111-4111-8111-000000000003', Name: GITHUB_REPOSITORIES_ENTITY, PrimaryKeys: [{ Name: 'ID', IsUniqueIdentifier: true }], GetUserPermisions: allowAllPerms } as EntityInfo,
        { ID: '11111111-1111-4111-8111-000000000004', Name: GITHUB_IDENTITIES_ENTITY, PrimaryKeys: [{ Name: 'ID', IsUniqueIdentifier: true }], GetUserPermisions: allowAllPerms } as EntityInfo,
    ];
    const beginEntityTransaction = async (): Promise<EntityTransactionScope> => {
        txStats.began += 1;
        const isNested = activeTxDepth > 0;
        activeTxDepth += 1;
        const snapshot = cloneStores();
        let settled = false;
        return {
            IsNested: isNested,
            Commit: async () => {
                if (settled) return;
                settled = true;
                activeTxDepth = Math.max(0, activeTxDepth - 1);
                txStats.committed += 1;
            },
            Rollback: async () => {
                if (settled) return;
                settled = true;
                activeTxDepth = Math.max(0, activeTxDepth - 1);
                txStats.rolledBack += 1;
                restoreStores(snapshot);
            },
        };
    };

    const provider = {
        Entities: entitiesList,
        EntityByName: (name: string) => entitiesList.find((e) => e.Name === name),
        GetEntityObject: async (entityName: string) => makeEntity(entityName),
        RunView: runSingleView,
        RunViews: async (views: RunViewParams[]) => Promise.all(views.map((v) => runSingleView(v))),
        SupportsEntityTransactions: true,
        BeginEntityTransaction: beginEntityTransaction,
    } as Partial<IMetadataProvider & IRunViewProvider> as IMetadataProvider & IRunViewProvider;

    const contextUser = { ID: '99999999-9999-4999-8999-000000000001', Name: 'System' } as UserInfo;

    return {
        provider,
        contextUser,
        getStore,
        saveCounts,
        txStats,
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
    const savedGitHubToken = process.env.GITHUB_TOKEN;
    const savedGhToken = process.env.GH_TOKEN;

    beforeEach(() => {
        delete process.env.GITHUB_TOKEN;
        delete process.env.GH_TOKEN;
        GitHubTasksEngineBase.Instance.ResetCaches();
        GitHubWebhookService.Instance.ClearProcessedDeliveries();
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

    afterEach(() => {
        if (savedGitHubToken === undefined) {
            delete process.env.GITHUB_TOKEN;
        } else {
            process.env.GITHUB_TOKEN = savedGitHubToken;
        }
        if (savedGhToken === undefined) {
            delete process.env.GH_TOKEN;
        } else {
            process.env.GH_TOKEN = savedGhToken;
        }
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
        savedTask.Priority = 'Critical';
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
        expect(updatedTask.Priority).toBe('Critical');
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

    it('serializes concurrent opened/assigned deliveries for the same issue without creating duplicate or orphan Tasks', async () => {
        const h = buildTestHarness();
        const secret = 'concurrent-secret';

        const makeIssueWebhook = (
            action: string,
            title: string,
            assignees: Array<{ login: string }>,
            updatedAt = '2026-11-10T10:00:00.000Z',
        ) => {
            const payload = JSON.stringify({
                action,
                repository: { name: 'bizapps-tasks', owner: { login: 'MemberJunction' } },
                issue: {
                    number: 88,
                    node_id: 'I_88',
                    title,
                    body: 'Concurrent delivery test',
                    html_url: 'https://github.com/MemberJunction/bizapps-tasks/issues/88',
                    state: 'open',
                    assignees,
                    updated_at: updatedAt,
                },
            });
            const sig = `sha256=${createHmac('sha256', secret).update(payload, 'utf8').digest('hex')}`;
            return { payload, sig };
        };

        const d1 = makeIssueWebhook('opened', 'Race Issue #88', [], '2026-11-10T10:00:00.000Z');
        const d2 = makeIssueWebhook('assigned', 'Race Issue #88', [{ login: 'alice-dev' }], '2026-11-10T10:00:01.000Z');

        const [res1, res2] = await Promise.all([
            GitHubWebhookService.Instance.HandleWebhook({
                eventName: 'issues',
                deliveryId: 'deliv-88-1',
                signatureHeader: d1.sig,
                rawPayload: d1.payload,
                webhookSecret: secret,
                contextUser: h.contextUser,
                provider: h.provider,
            }),
            GitHubWebhookService.Instance.HandleWebhook({
                eventName: 'issues',
                deliveryId: 'deliv-88-2',
                signatureHeader: d2.sig,
                rawPayload: d2.payload,
                webhookSecret: secret,
                contextUser: h.contextUser,
                provider: h.provider,
            }),
        ]);

        expect(res1.status).toBe('synced');
        expect(res2.status).toBe('synced');
        expect(h.getStore(TASKS_ENTITY_NAME).size).toBe(1);
        expect(h.getStore(GITHUB_ISSUE_TASKS_ENTITY).size).toBe(1);
        expect(Array.from(h.getStore(TASK_ASSIGNMENTS_ENTITY).values())).toHaveLength(1);
    });

    it('deduplicates replayed X-GitHub-Delivery IDs and skips out-of-order deliveries older than stored GitHubUpdatedAt', async () => {
        const h = buildTestHarness();
        const secret = 'ordering-secret';

        const makePayload = (title: string, updatedAt: string) => {
            const rawPayload = JSON.stringify({
                action: 'edited',
                repository: { name: 'bizapps-tasks', owner: { login: 'MemberJunction' } },
                issue: {
                    number: 91,
                    node_id: 'I_91',
                    title,
                    body: 'Ordering test',
                    html_url: 'https://github.com/MemberJunction/bizapps-tasks/issues/91',
                    state: 'open',
                    updated_at: updatedAt,
                },
            });
            const signatureHeader = `sha256=${createHmac('sha256', secret).update(rawPayload, 'utf8').digest('hex')}`;
            return { rawPayload, signatureHeader };
        };

        const newer = makePayload('Newer Title (v2)', '2026-11-10T12:00:00.000Z');
        const firstRes = await GitHubWebhookService.Instance.HandleWebhook({
            eventName: 'issues',
            deliveryId: 'delivery-91-newer',
            signatureHeader: newer.signatureHeader,
            rawPayload: newer.rawPayload,
            webhookSecret: secret,
            contextUser: h.contextUser,
            provider: h.provider,
        });
        expect(firstRes.status).toBe('synced');
        expect(firstRes.syncResult?.action).toBe('created');

        // Replaying the exact same deliveryId is ignored
        const replayRes = await GitHubWebhookService.Instance.HandleWebhook({
            eventName: 'issues',
            deliveryId: 'delivery-91-newer',
            signatureHeader: newer.signatureHeader,
            rawPayload: newer.rawPayload,
            webhookSecret: secret,
            contextUser: h.contextUser,
            provider: h.provider,
        });
        expect(replayRes.status).toBe('ignored');
        expect(replayRes.reason).toContain('Duplicate delivery ID');

        // Out-of-order older delivery arrives with a fresh deliveryId -> skipped without overwriting title
        const older = makePayload('Stale Older Title (v1)', '2026-11-10T11:00:00.000Z');
        const staleRes = await GitHubWebhookService.Instance.HandleWebhook({
            eventName: 'issues',
            deliveryId: 'delivery-91-older',
            signatureHeader: older.signatureHeader,
            rawPayload: older.rawPayload,
            webhookSecret: secret,
            contextUser: h.contextUser,
            provider: h.provider,
        });
        expect(staleRes.status).toBe('ignored');
        expect(staleRes.syncResult?.action).toBe('skipped');

        const savedTask = Array.from(h.getStore(TASKS_ENTITY_NAME).values())[0];
        expect(savedTask.Name).toBe('Newer Title (v2)');
    });

    it('preserves PR ReviewDecision and diff stats across partial webhook events and commented reviews', async () => {
        const h = buildTestHarness();
        const secret = 'pr-preserve-secret';

        // 1. Initial pull_request opened event carries diff stats (changed_files, additions, deletions)
        const openedRaw = JSON.stringify({
            action: 'opened',
            repository: { name: 'bizapps-tasks', owner: { login: 'MemberJunction' } },
            pull_request: {
                number: 105,
                node_id: 'PR_105',
                title: 'feat: preserve PR fields',
                body: 'Initial PR',
                html_url: 'https://github.com/MemberJunction/bizapps-tasks/pull/105',
                state: 'open',
                draft: false,
                head: { ref: 'feat/pr-preserve', sha: 'sha-111' },
                base: { ref: 'next' },
                changed_files: 7,
                additions: 140,
                deletions: 25,
                updated_at: '2026-11-10T10:00:00.000Z',
            },
        });
        await GitHubWebhookService.Instance.HandleWebhook({
            eventName: 'pull_request',
            deliveryId: 'pr-105-open',
            signatureHeader: `sha256=${createHmac('sha256', secret).update(openedRaw, 'utf8').digest('hex')}`,
            rawPayload: openedRaw,
            webhookSecret: secret,
            contextUser: h.contextUser,
            provider: h.provider,
        });

        // 2. pull_request_review approved event (lacks diff metrics) sets ReviewDecision='APPROVED' and preserves diff stats
        const approvedRaw = JSON.stringify({
            action: 'submitted',
            repository: { name: 'bizapps-tasks', owner: { login: 'MemberJunction' } },
            pull_request: {
                number: 105,
                node_id: 'PR_105',
                title: 'feat: preserve PR fields',
                body: 'Initial PR',
                html_url: 'https://github.com/MemberJunction/bizapps-tasks/pull/105',
                state: 'open',
                draft: false,
                head: { ref: 'feat/pr-preserve', sha: 'sha-111' },
                base: { ref: 'next' },
                updated_at: '2026-11-10T10:05:00.000Z',
            },
            review: { state: 'approved' },
        });
        await GitHubWebhookService.Instance.HandleWebhook({
            eventName: 'pull_request_review',
            deliveryId: 'pr-105-approve',
            signatureHeader: `sha256=${createHmac('sha256', secret).update(approvedRaw, 'utf8').digest('hex')}`,
            rawPayload: approvedRaw,
            webhookSecret: secret,
            contextUser: h.contextUser,
            provider: h.provider,
        });

        let prExt = Array.from(h.getStore(GITHUB_PR_TASKS_ENTITY).values())[0];
        expect(prExt.ReviewDecision).toBe('APPROVED');
        expect(prExt.ChangedFiles).toBe(7);
        expect(prExt.Additions).toBe(140);
        expect(prExt.Deletions).toBe(25);

        // 3. A 'commented' review does not overwrite APPROVED with REVIEW_REQUIRED
        const commentedRaw = JSON.stringify({
            action: 'submitted',
            repository: { name: 'bizapps-tasks', owner: { login: 'MemberJunction' } },
            pull_request: {
                number: 105,
                node_id: 'PR_105',
                title: 'feat: preserve PR fields',
                body: 'Initial PR',
                html_url: 'https://github.com/MemberJunction/bizapps-tasks/pull/105',
                state: 'open',
                draft: false,
                head: { ref: 'feat/pr-preserve', sha: 'sha-111' },
                base: { ref: 'next' },
                updated_at: '2026-11-10T10:06:00.000Z',
            },
            review: { state: 'commented' },
        });
        await GitHubWebhookService.Instance.HandleWebhook({
            eventName: 'pull_request_review',
            deliveryId: 'pr-105-comment',
            signatureHeader: `sha256=${createHmac('sha256', secret).update(commentedRaw, 'utf8').digest('hex')}`,
            rawPayload: commentedRaw,
            webhookSecret: secret,
            contextUser: h.contextUser,
            provider: h.provider,
        });

        prExt = Array.from(h.getStore(GITHUB_PR_TASKS_ENTITY).values())[0];
        expect(prExt.ReviewDecision).toBe('APPROVED');

        // 4. Subsequent pull_request synchronize push updates HeadSha and sets ChecksStatus='Pending' without wiping ReviewDecision
        const syncRaw = JSON.stringify({
            action: 'synchronize',
            repository: { name: 'bizapps-tasks', owner: { login: 'MemberJunction' } },
            pull_request: {
                number: 105,
                node_id: 'PR_105',
                title: 'feat: preserve PR fields',
                body: 'Initial PR',
                html_url: 'https://github.com/MemberJunction/bizapps-tasks/pull/105',
                state: 'open',
                draft: false,
                head: { ref: 'feat/pr-preserve', sha: 'sha-222' },
                base: { ref: 'next' },
                changed_files: 8,
                additions: 155,
                deletions: 25,
                updated_at: '2026-11-10T10:10:00.000Z',
            },
        });
        await GitHubWebhookService.Instance.HandleWebhook({
            eventName: 'pull_request',
            deliveryId: 'pr-105-sync',
            signatureHeader: `sha256=${createHmac('sha256', secret).update(syncRaw, 'utf8').digest('hex')}`,
            rawPayload: syncRaw,
            webhookSecret: secret,
            contextUser: h.contextUser,
            provider: h.provider,
        });

        prExt = Array.from(h.getStore(GITHUB_PR_TASKS_ENTITY).values())[0];
        expect(prExt.HeadSha).toBe('sha-222');
        expect(prExt.ReviewDecision).toBe('APPROVED');
        expect(prExt.ChecksStatus).toBe('Pending');
        expect(prExt.ChangedFiles).toBe(8);
    });

    it('matches GitHubUserID across login renames and blocks recycled-login impersonation', async () => {
        const h = buildTestHarness();
        h.getStore(GITHUB_IDENTITIES_ENTITY).set('alice', {
            ID: '88888888-8888-4888-8888-000000000001',
            GitHubLogin: 'alice-old-handle',
            GitHubUserID: '10001',
            PersonID: h.ids.ALICE_PERSON_ID,
            IsActive: true,
        });

        // 1. Alice renamed her GitHub login to 'alice-new-handle', but her GitHubUserID is still '10001' -> matches Alice
        const renamedSync = await GitHubTaskSyncService.Instance.SyncRepositories({
            repositoryId: h.ids.REPO_ASSIGNED_ID,
            items: [
                {
                    kind: 'issue',
                    number: 201,
                    nodeId: 'I_201',
                    title: 'Assigned to renamed Alice',
                    body: '',
                    htmlUrl: 'https://github.com/MemberJunction/MJ/issues/201',
                    state: 'open',
                    assigneeLogins: ['alice-new-handle'],
                    assignees: [{ login: 'alice-new-handle', userId: '10001' }],
                },
            ],
            contextUser: h.contextUser,
            provider: h.provider,
        });
        expect(renamedSync[0].created).toBe(1);

        // 2. Outsider claims 'alice-old-handle' with a different GitHubUserID ('99999') -> rejected under AssignedOnly!
        const recycledSync = await GitHubTaskSyncService.Instance.SyncRepositories({
            repositoryId: h.ids.REPO_ASSIGNED_ID,
            items: [
                {
                    kind: 'issue',
                    number: 202,
                    nodeId: 'I_202',
                    title: 'Assigned to recycled handle',
                    body: '',
                    htmlUrl: 'https://github.com/MemberJunction/MJ/issues/202',
                    state: 'open',
                    assigneeLogins: ['alice-old-handle'],
                    assignees: [{ login: 'alice-old-handle', userId: '99999' }],
                },
            ],
            contextUser: h.contextUser,
            provider: h.provider,
        });
        expect(recycledSync[0].created).toBe(0);
        expect(recycledSync[0].skipped).toBe(1);
    });

    it('validates LLM ParentID/CategoryID against candidates, skips Priority when already set, and scopes objectives to repository', async () => {
        const h = buildTestHarness();
        let capturedObjectives: Array<{ id: string; name: string }> = [];

        // Create an open task in REPO_ASSIGNED_ID and an open task in REPO_ALL_ID
        const repo1Sync = await GitHubTaskSyncService.Instance.SyncRepositories({
            repositoryId: h.ids.REPO_ASSIGNED_ID,
            items: [
                {
                    kind: 'issue',
                    number: 301,
                    nodeId: 'I_301',
                    title: 'Repo 1 Parent Objective',
                    body: 'Objective in repo 1',
                    htmlUrl: 'https://github.com/MemberJunction/MJ/issues/301',
                    state: 'open',
                    assigneeLogins: ['alice-dev'],
                },
            ],
            contextUser: h.contextUser,
            provider: h.provider,
            runInference: false,
        });
        const validParentId = repo1Sync[0].taskIds[0];

        await GitHubTaskSyncService.Instance.SyncRepositories({
            repositoryId: h.ids.REPO_ALL_ID,
            items: [
                {
                    kind: 'issue',
                    number: 302,
                    nodeId: 'I_302',
                    title: 'Other Repo Unrelated Objective',
                    body: 'Objective in repo 2',
                    htmlUrl: 'https://github.com/MemberJunction/bizapps-tasks/issues/302',
                    state: 'open',
                },
            ],
            contextUser: h.contextUser,
            provider: h.provider,
            runInference: false,
        });

        GitHubTaskInferenceService.Instance.SetExtractor({
            ExtractPlanningSuggestions: async (ctx) => {
                capturedObjectives = ctx.candidateObjectives;
                return {
                    suggestions: [
                        {
                            field: 'ParentID',
                            value: 'dddddddd-dddd-4ddd-8ddd-000000000999', // Hallucinated UUID not in candidates
                            confidence: 0.95,
                            rationale: 'Hallucinated parent',
                        },
                        {
                            field: 'CategoryID',
                            value: 'eeeeeeee-eeee-4eee-8eee-000000000999', // Hallucinated CategoryID not in candidates
                            confidence: 0.95,
                            rationale: 'Hallucinated category',
                        },
                        {
                            field: 'Priority',
                            value: 'High', // Should be skipped because Task.Priority is already set by sync
                            confidence: 0.91,
                            rationale: 'Priority already set',
                        },
                        {
                            field: 'ParentID',
                            value: validParentId, // Valid candidate objective in same repo
                            confidence: 0.89,
                            rationale: 'Matches Repo 1 Parent Objective',
                        },
                    ],
                    mentionedLogins: [],
                    promptRunId: 'cccccccc-cccc-4ccc-8ccc-000000000003',
                };
            },
        });

        const childSync = await GitHubTaskSyncService.Instance.SyncRepositories({
            repositoryId: h.ids.REPO_ASSIGNED_ID,
            items: [
                {
                    kind: 'issue',
                    number: 303,
                    nodeId: 'I_303',
                    title: 'Child issue in Repo 1',
                    body: 'Part of Repo 1 Parent Objective',
                    htmlUrl: 'https://github.com/MemberJunction/MJ/issues/303',
                    state: 'open',
                    assigneeLogins: ['alice-dev'],
                },
            ],
            contextUser: h.contextUser,
            provider: h.provider,
            runInference: true,
        });

        // Candidate objectives sent to the model only include open tasks from REPO_ASSIGNED_ID
        expect(capturedObjectives.some((o) => o.id === validParentId)).toBe(true);
        expect(capturedObjectives.some((o) => o.name === 'Other Repo Unrelated Objective')).toBe(false);

        // Hallucinated ParentID, hallucinated CategoryID, and already-populated Priority were all rejected; only validParentId was written
        expect(childSync[0].inferredSuggestionsCreated).toBe(1);
        const childTaskId = childSync[0].taskIds[0];
        const childSuggestions = Array.from(h.getStore(FIELD_SUGGESTIONS_ENTITY_NAME).values()).filter(
            (s) => String(s.LinkedRecordID ?? '').toLowerCase() === childTaskId.toLowerCase(),
        );
        expect(childSuggestions).toHaveLength(1);
        expect(childSuggestions[0].AnchorKey).toBe('ParentID');
        expect(childSuggestions[0].SuggestedValue).toBe(JSON.stringify(validParentId));
    });

    it('aggregates check_suite and check_run events per head_sha, ignores stale SHAs and fork PRs, maps stale conclusion to Neutral, and updates all matching PRs', async () => {
        const h = buildTestHarness();
        const secret = 'checks-webhook-secret';

        // 1. Open and synchronize PR #500 and PR #501 sharing HeadSha 'sha-checks-500' -> ChecksStatus starts at 'Pending'
        for (const num of [500, 501]) {
            const syncPrRaw = JSON.stringify({
                action: 'synchronize',
                repository: { name: 'bizapps-tasks', owner: { login: 'MemberJunction' } },
                pull_request: {
                    number: num,
                    node_id: `PR_${num}`,
                    title: `feat: software factory gate checks #${num}`,
                    body: 'Wait on CI checks',
                    html_url: `https://github.com/MemberJunction/bizapps-tasks/pull/${num}`,
                    state: 'open',
                    draft: false,
                    head: { ref: 'feat/checks-gate', sha: 'sha-checks-500' },
                    base: { ref: 'next' },
                    updated_at: '2026-11-10T14:00:00.000Z',
                },
            });
            await GitHubWebhookService.Instance.HandleWebhook({
                eventName: 'pull_request',
                deliveryId: `pr-${num}-sync`,
                signatureHeader: `sha256=${createHmac('sha256', secret).update(syncPrRaw, 'utf8').digest('hex')}`,
                rawPayload: syncPrRaw,
                webhookSecret: secret,
                contextUser: h.contextUser,
                provider: h.provider,
            });
        }

        // 2. check_run with conclusion='stale' maps to 'Neutral' (never 'Failing') and updates both PR #500 and PR #501
        const staleRunRaw = JSON.stringify({
            action: 'completed',
            repository: { name: 'bizapps-tasks', owner: { login: 'MemberJunction' } },
            check_run: {
                id: 1,
                name: 'obsolete-job',
                status: 'completed',
                conclusion: 'stale',
                head_sha: 'sha-checks-500',
                pull_requests: [{ number: 500 }, { number: 501 }],
            },
        });
        await GitHubWebhookService.Instance.HandleWebhook({
            eventName: 'check_run',
            deliveryId: 'pr-500-run-stale',
            signatureHeader: `sha256=${createHmac('sha256', secret).update(staleRunRaw, 'utf8').digest('hex')}`,
            rawPayload: staleRunRaw,
            webhookSecret: secret,
            contextUser: h.contextUser,
            provider: h.provider,
        });
        for (const prExt of h.getStore(GITHUB_PR_TASKS_ENTITY).values()) {
            expect(prExt.ChecksStatus).toBe('Neutral');
        }

        // 3. Job A fails ('lint') and Job B succeeds ('build') -> aggregate remains 'Failing' (not overwritten by last event)
        const jobAFailRaw = JSON.stringify({
            action: 'completed',
            repository: { name: 'bizapps-tasks', owner: { login: 'MemberJunction' } },
            check_run: {
                id: 2,
                name: 'lint',
                status: 'completed',
                conclusion: 'failure',
                head_sha: 'sha-checks-500',
                pull_requests: [],
            },
        });
        await GitHubWebhookService.Instance.HandleWebhook({
            eventName: 'check_run',
            deliveryId: 'pr-500-job-a-fail',
            signatureHeader: `sha256=${createHmac('sha256', secret).update(jobAFailRaw, 'utf8').digest('hex')}`,
            rawPayload: jobAFailRaw,
            webhookSecret: secret,
            contextUser: h.contextUser,
            provider: h.provider,
        });

        const jobBPassRaw = JSON.stringify({
            action: 'completed',
            repository: { name: 'bizapps-tasks', owner: { login: 'MemberJunction' } },
            check_run: {
                id: 3,
                name: 'build',
                status: 'completed',
                conclusion: 'success',
                head_sha: 'sha-checks-500',
                pull_requests: [],
            },
        });
        await GitHubWebhookService.Instance.HandleWebhook({
            eventName: 'check_run',
            deliveryId: 'pr-500-job-b-pass',
            signatureHeader: `sha256=${createHmac('sha256', secret).update(jobBPassRaw, 'utf8').digest('hex')}`,
            rawPayload: jobBPassRaw,
            webhookSecret: secret,
            contextUser: h.contextUser,
            provider: h.provider,
        });
        for (const prExt of h.getStore(GITHUB_PR_TASKS_ENTITY).values()) {
            expect(prExt.ChecksStatus).toBe('Failing');
        }

        // 4. Job A ('lint') is re-run and succeeds -> aggregate transitions to 'Passing'
        const jobARerunPassRaw = JSON.stringify({
            action: 'completed',
            repository: { name: 'bizapps-tasks', owner: { login: 'MemberJunction' } },
            check_run: {
                id: 4,
                name: 'lint',
                status: 'completed',
                conclusion: 'success',
                head_sha: 'sha-checks-500',
                pull_requests: [],
            },
        });
        await GitHubWebhookService.Instance.HandleWebhook({
            eventName: 'check_run',
            deliveryId: 'pr-500-job-a-pass',
            signatureHeader: `sha256=${createHmac('sha256', secret).update(jobARerunPassRaw, 'utf8').digest('hex')}`,
            rawPayload: jobARerunPassRaw,
            webhookSecret: secret,
            contextUser: h.contextUser,
            provider: h.provider,
        });
        for (const prExt of h.getStore(GITHUB_PR_TASKS_ENTITY).values()) {
            expect(prExt.ChecksStatus).toBe('Passing');
        }

        // 5. Old commit SHA ('sha-old-499') check_suite failure citing pull_requests: [{ number: 500 }] is ignored and does NOT overwrite 'sha-checks-500'
        const staleShaFailRaw = JSON.stringify({
            action: 'completed',
            repository: { name: 'bizapps-tasks', owner: { login: 'MemberJunction' } },
            check_suite: {
                id: 99,
                status: 'completed',
                conclusion: 'failure',
                head_sha: 'sha-old-499',
                pull_requests: [{ number: 500 }],
            },
        });
        const staleShaRes = await GitHubWebhookService.Instance.HandleWebhook({
            eventName: 'check_suite',
            deliveryId: 'pr-500-stale-sha',
            signatureHeader: `sha256=${createHmac('sha256', secret).update(staleShaFailRaw, 'utf8').digest('hex')}`,
            rawPayload: staleShaFailRaw,
            webhookSecret: secret,
            contextUser: h.contextUser,
            provider: h.provider,
        });
        expect(staleShaRes.status).toBe('ignored');
        for (const prExt of h.getStore(GITHUB_PR_TASKS_ENTITY).values()) {
            expect(prExt.ChecksStatus).toBe('Passing');
        }

        // 6. Fork PR in pull_requests with a different base.repo.full_name is ignored
        const forkPrRaw = JSON.stringify({
            action: 'completed',
            repository: { name: 'bizapps-tasks', owner: { login: 'MemberJunction' } },
            check_suite: {
                id: 100,
                status: 'completed',
                conclusion: 'failure',
                head_sha: 'sha-checks-500',
                pull_requests: [
                    {
                        number: 500,
                        base: { repo: { full_name: 'other-org/forked-repo' } },
                    },
                ],
            },
        });
        const forkRes = await GitHubWebhookService.Instance.HandleWebhook({
            eventName: 'check_suite',
            deliveryId: 'pr-500-fork-pr',
            signatureHeader: `sha256=${createHmac('sha256', secret).update(forkPrRaw, 'utf8').digest('hex')}`,
            rawPayload: forkPrRaw,
            webhookSecret: secret,
            contextUser: h.contextUser,
            provider: h.provider,
        });
        expect(forkRes.status).toBe('ignored');
        for (const prExt of h.getStore(GITHUB_PR_TASKS_ENTITY).values()) {
            expect(prExt.ChecksStatus).toBe('Passing');
        }
    });

    it('applies same-second updates when GitHub-owned content changes, skips identical same-second payloads, and aggregates multi-reviewer decisions', async () => {
        const h = buildTestHarness();
        const secret = 'same-second-secret';

        await GitHubTaskSyncService.Instance.SyncRepositories({
            repositoryId: h.ids.REPO_ALL_ID,
            items: [
                {
                    kind: 'issue',
                    number: 601,
                    nodeId: 'I_601',
                    title: 'Original Title at T0',
                    body: 'Body at T0',
                    htmlUrl: 'https://github.com/MemberJunction/bizapps-tasks/issues/601',
                    state: 'open',
                    updatedAt: '2026-11-10T15:00:00.000Z',
                },
            ],
            contextUser: h.contextUser,
            provider: h.provider,
            runInference: false,
        });

        // 1. Re-sync with the exact same updatedAt timestamp and identical content -> skipped
        const identicalSync = await GitHubTaskSyncService.Instance.SyncRepositories({
            repositoryId: h.ids.REPO_ALL_ID,
            items: [
                {
                    kind: 'issue',
                    number: 601,
                    nodeId: 'I_601',
                    title: 'Original Title at T0',
                    body: 'Body at T0',
                    htmlUrl: 'https://github.com/MemberJunction/bizapps-tasks/issues/601',
                    state: 'open',
                    updatedAt: '2026-11-10T15:00:00.000Z',
                },
            ],
            contextUser: h.contextUser,
            provider: h.provider,
            runInference: false,
        });
        expect(identicalSync[0].skipped).toBe(1);
        expect(identicalSync[0].updated).toBe(0);

        // 2. Same-second update (updatedAt equal to T0) that assigns Alice and adds a label -> applied!
        const sameSecondAssigned = await GitHubTaskSyncService.Instance.SyncRepositories({
            repositoryId: h.ids.REPO_ALL_ID,
            items: [
                {
                    kind: 'issue',
                    number: 601,
                    nodeId: 'I_601',
                    title: 'Retitled in Same Second at T0',
                    body: 'Body at T0',
                    htmlUrl: 'https://github.com/MemberJunction/bizapps-tasks/issues/601',
                    state: 'open',
                    labels: ['bug'],
                    assignees: [{ login: 'alice-dev' }],
                    assigneeLogins: ['alice-dev'],
                    updatedAt: '2026-11-10T15:00:00.000Z',
                },
            ],
            contextUser: h.contextUser,
            provider: h.provider,
            runInference: false,
        });
        expect(sameSecondAssigned[0].updated).toBe(1);
        expect(sameSecondAssigned[0].skipped).toBe(0);
        const savedTask = Array.from(h.getStore(TASKS_ENTITY_NAME).values())[0];
        expect(savedTask.Name).toBe('Retitled in Same Second at T0');
        expect(Array.from(h.getStore(TASK_ASSIGNMENTS_ENTITY).values())).toHaveLength(1);

        // 3. Multi-reviewer aggregation: reviewer 1 requests changes, reviewer 2 approves -> remains CHANGES_REQUESTED
        const makeReviewWebhook = (reviewerLogin: string, state: string, deliveryId: string) => {
            const rawPayload = JSON.stringify({
                action: 'submitted',
                repository: { name: 'bizapps-tasks', owner: { login: 'MemberJunction' } },
                pull_request: {
                    number: 602,
                    node_id: 'PR_602',
                    title: 'feat: multi-reviewer PR',
                    body: '',
                    html_url: 'https://github.com/MemberJunction/bizapps-tasks/pull/602',
                    state: 'open',
                    draft: false,
                    head: { ref: 'feat/rev', sha: 'sha-602' },
                    base: { ref: 'next' },
                    updated_at: '2026-11-10T15:05:00.000Z',
                },
                review: {
                    state,
                    user: { login: reviewerLogin },
                },
            });
            const signatureHeader = `sha256=${createHmac('sha256', secret).update(rawPayload, 'utf8').digest('hex')}`;
            return GitHubWebhookService.Instance.HandleWebhook({
                eventName: 'pull_request_review',
                deliveryId,
                signatureHeader,
                rawPayload,
                webhookSecret: secret,
                contextUser: h.contextUser,
                provider: h.provider,
            });
        };

        await makeReviewWebhook('alice-dev', 'changes_requested', 'rev-602-1');
        await makeReviewWebhook('bob-reviewer', 'approved', 'rev-602-2');
        let pr602 = Array.from(h.getStore(GITHUB_PR_TASKS_ENTITY).values())[0];
        expect(pr602.ReviewDecision).toBe('CHANGES_REQUESTED');

        // Once alice-dev approves as well, ReviewDecision transitions to APPROVED
        await makeReviewWebhook('alice-dev', 'approved', 'rev-602-3');
        pr602 = Array.from(h.getStore(GITHUB_PR_TASKS_ENTITY).values())[0];
        expect(pr602.ReviewDecision).toBe('APPROVED');

        // ValidateNormalizedGitHubSyncItem rejects assignees: [{}] cleanly without throwing TypeError
        const badAssigneesValidation = GitHubFieldOwnershipPolicy.ValidateNormalizedGitHubSyncItem(
            {
                kind: 'issue',
                number: 1,
                nodeId: 'I_1',
                title: 'Bad assignees',
                htmlUrl: 'https://github.com/MemberJunction/MJ/issues/1',
                state: 'open',
                assignees: [{}],
            },
            'MemberJunction/MJ',
        );
        expect(badAssigneesValidation.valid).toBe(false);
        expect(badAssigneesValidation.error).toContain('Invalid assignees[0]: login must be a non-empty string');
    });

    it('recovers from cross-process unique-key collision via transactional rollback and re-query without orphan Tasks', async () => {
        const h = buildTestHarness();

        // Simulate another process having committed Issue #700 right after preloadRepositoryExtensions ran
        const winningTaskId = '00000000-0000-4000-8000-000000000700';
        const originalGetEntityObject = h.provider.GetEntityObject.bind(h.provider);
        const txProvider = h.provider as { BeginEntityTransaction: () => Promise<EntityTransactionScope> };
        const origBegin = txProvider.BeginEntityTransaction;
        let injectedConcurrentWinner = false;

        txProvider.BeginEntityTransaction = async () => {
            const scope = await origBegin();
            if (!injectedConcurrentWinner) {
                injectedConcurrentWinner = true;
                const origRollback = scope.Rollback;
                return {
                    ...scope,
                    Rollback: async () => {
                        await origRollback();
                        // Concurrent winner committed outside our rolled-back transaction
                        h.getStore(TASKS_ENTITY_NAME).set(winningTaskId, {
                            ID: winningTaskId,
                            Name: 'Winner Issue #700',
                            Status: 'Open',
                        });
                        h.getStore(GITHUB_ISSUE_TASKS_ENTITY).set(winningTaskId, {
                            ID: winningTaskId,
                            RepositoryID: h.ids.REPO_ALL_ID,
                            Number: 700,
                            NodeID: 'I_700',
                            HtmlURL: 'https://github.com/MemberJunction/bizapps-tasks/issues/700',
                            State: 'open',
                        });
                        txProvider.BeginEntityTransaction = origBegin;
                    },
                };
            }
            return scope;
        };

        let failedFirstLeafSave = false;
        h.provider.GetEntityObject = async (entityName: string) => {
            const entity = await originalGetEntityObject(entityName);
            if (entityName === GITHUB_ISSUE_TASKS_ENTITY && !failedFirstLeafSave) {
                failedFirstLeafSave = true;
                entity.Save = async () => {
                    entity.LatestResult = {
                        CompleteMessage: 'Violation of UNIQUE KEY constraint UX_GitHubIssueTask_Repo_Number',
                    };
                    return false;
                };
            }
            return entity;
        };

        const recoverySync = await GitHubTaskSyncService.Instance.SyncRepositories({
            repositoryId: h.ids.REPO_ALL_ID,
            items: [
                {
                    kind: 'issue',
                    number: 700,
                    nodeId: 'I_700',
                    title: 'Recovered Title #700',
                    body: 'Recovered body',
                    htmlUrl: 'https://github.com/MemberJunction/bizapps-tasks/issues/700',
                    state: 'open',
                },
            ],
            contextUser: h.contextUser,
            provider: h.provider,
            runInference: false,
        });

        expect(recoverySync[0].updated).toBe(1);
        expect(h.txStats.rolledBack).toBe(1);
        expect(h.txStats.committed).toBe(1);
        // Only the winning Task and its extension row remain; zero separate Task.Save() calls occurred
        expect(h.saveCounts.get(TASKS_ENTITY_NAME) ?? 0).toBe(0);
        expect(h.getStore(TASKS_ENTITY_NAME).size).toBe(1);
        expect(h.getStore(GITHUB_ISSUE_TASKS_ENTITY).size).toBe(1);
        expect(h.getStore(TASKS_ENTITY_NAME).get(winningTaskId)?.Name).toBe('Recovered Title #700');

        // Unrecoverable leaf save failure (no concurrent winner) rolls back cleanly and surfaces the error
        h.provider.GetEntityObject = async (entityName: string) => {
            const entity = await originalGetEntityObject(entityName);
            if (entityName === GITHUB_ISSUE_TASKS_ENTITY) {
                entity.Save = async () => {
                    entity.LatestResult = { CompleteMessage: 'Simulated database constraint error on GitHubIssueTask' };
                    return false;
                };
            }
            return entity;
        };

        await expect(
            GitHubTaskSyncService.Instance.SyncRepositories({
                repositoryId: h.ids.REPO_ALL_ID,
                items: [
                    {
                        kind: 'issue',
                        number: 701,
                        nodeId: 'I_701',
                        title: 'Unrecoverable save failure test',
                        body: '',
                        htmlUrl: 'https://github.com/MemberJunction/bizapps-tasks/issues/701',
                        state: 'open',
                    },
                ],
                contextUser: h.contextUser,
                provider: h.provider,
                runInference: false,
            }),
        ).rejects.toThrow(/Simulated database constraint error on GitHubIssueTask/);
        expect(h.txStats.rolledBack).toBe(2);
        expect(h.getStore(TASKS_ENTITY_NAME).size).toBe(1);
    });

    it('verifies SQL Server and PostgreSQL teardown scripts contain valid schema and column references', () => {
        const sqlServerTeardownPath = resolve(
            import.meta.dirname,
            '../../../../teardown/V1__Remove_GitHub_Tasks_Extension.sql',
        );
        const pgTeardownPath = resolve(
            import.meta.dirname,
            '../../../../teardown-pg/V1__Remove_GitHub_Tasks_Extension.pg.sql',
        );
        const sqlServerTeardown = readFileSync(sqlServerTeardownPath, 'utf8');
        const pgTeardown = readFileSync(pgTeardownPath, 'utf8');

        // Must not contain non-existent columns or unsubstituted flyway placeholders
        for (const script of [sqlServerTeardown, pgTeardown]) {
            expect(script).not.toContain('OriginalPromptRunID');
            expect(script).toContain('RerunFromPromptRunID');
            expect(script).toContain('AIPromptRunMedia');
            expect(script).toContain('AIResultCache');
            expect(script).not.toContain('DecidedForTaskID');
            expect(script).not.toContain('ParentCommentID');
            expect(script).not.toContain('${flyway:defaultSchema}');
            expect(script).toContain('ConversationDetail');
            expect(script).toContain('ConversationArtifact');
            expect(script).toContain('ConversationDetailRating');
            expect(script).toContain('ConversationDetailAttachment');
            expect(script).toContain('ConversationDetailArtifact');
            expect(script).toContain('TaskTemplateItem');
            expect(script).toContain('TemplateContent');
            expect(script).toContain('RubricEvaluation');
            expect(script).toContain('ProcessRunDetail');
            expect(script).toContain('UserRoutineRun');
        }
        expect(sqlServerTeardown).toContain('[__mj_BizAppsTasksGitHub].[GitHubPullRequestTask]');
        expect(sqlServerTeardown).toContain('[__mj_BizAppsTasksGitHub].[GitHubIssueTask]');
        // PG teardown must use folded lowercase __mj_bizappstasks (never quoted "__mj_BizAppsTasks") and to_regclass guards
        expect(pgTeardown).not.toContain('"__mj_BizAppsTasks"');
        expect(pgTeardown).toContain('__mj_bizappstasks."Task"');
        expect(pgTeardown).toContain("to_regclass('__mj_bizappstasksgithub.\"GitHubPullRequestTask\"')");
    });

    it('queries authoritative GitHub live state across MJAPI restarts/instances and bounds fallback LRU maps', async () => {
        const h = buildTestHarness();
        const secret = 'live-state-secret';

        // Seed PR #800 with HeadSha 'sha-live-800'
        const openRaw = JSON.stringify({
            action: 'opened',
            repository: { name: 'bizapps-tasks', owner: { login: 'MemberJunction' } },
            pull_request: {
                number: 800,
                node_id: 'PR_800',
                title: 'feat: durable check and review state across restarts',
                body: 'Verifies live state fetcher',
                html_url: 'https://github.com/MemberJunction/bizapps-tasks/pull/800',
                state: 'open',
                draft: false,
                head: { ref: 'feat/durable-state', sha: 'sha-live-800' },
                base: { ref: 'next' },
                updated_at: '2026-11-10T16:00:00.000Z',
            },
        });
        await GitHubWebhookService.Instance.HandleWebhook({
            eventName: 'pull_request',
            deliveryId: 'pr-800-open',
            signatureHeader: `sha256=${createHmac('sha256', secret).update(openRaw, 'utf8').digest('hex')}`,
            rawPayload: openRaw,
            webhookSecret: secret,
            contextUser: h.contextUser,
            provider: h.provider,
        });

        // Simulate MJAPI process restart (wipes in-memory _checkStatesBySha and _reviewStatesByPr)
        // where check A failed and alice-dev requested changes BEFORE the restart,
        // and now check B succeeds and bob-reviewer approves AFTER the restart on a fresh instance.
        GitHubWebhookService.Instance.ClearProcessedDeliveries();

        let authoritativeChecksStatus: 'Failing' | 'Passing' = 'Failing';
        let authoritativeReviewDecision: 'CHANGES_REQUESTED' | 'APPROVED' = 'CHANGES_REQUESTED';

        GitHubWebhookService.Instance.SetLiveStateFetcher({
            FetchCommitChecksStatus: async (owner, repo, headSha) => {
                expect(owner).toBe('MemberJunction');
                expect(repo).toBe('bizapps-tasks');
                expect(headSha).toBe('sha-live-800');
                return authoritativeChecksStatus;
            },
            FetchPullRequestReviewDecision: async (owner, repo, pullNumber) => {
                expect(owner).toBe('MemberJunction');
                expect(repo).toBe('bizapps-tasks');
                expect(pullNumber).toBe(800);
                return authoritativeReviewDecision;
            },
        });

        // 1. Even though the webhook event arriving after restart is check B succeeding,
        // the authoritative live state fetcher reports 'Failing' (because check A failed before restart)
        const checkBPassRaw = JSON.stringify({
            action: 'completed',
            repository: { name: 'bizapps-tasks', owner: { login: 'MemberJunction' } },
            check_run: {
                id: 801,
                name: 'check-b',
                status: 'completed',
                conclusion: 'success',
                head_sha: 'sha-live-800',
                pull_requests: [{ number: 800 }],
            },
        });
        await GitHubWebhookService.Instance.HandleWebhook({
            eventName: 'check_run',
            deliveryId: 'pr-800-check-b-pass',
            signatureHeader: `sha256=${createHmac('sha256', secret).update(checkBPassRaw, 'utf8').digest('hex')}`,
            rawPayload: checkBPassRaw,
            webhookSecret: secret,
            contextUser: h.contextUser,
            provider: h.provider,
        });

        let pr800 = Array.from(h.getStore(GITHUB_PR_TASKS_ENTITY).values())[0];
        expect(pr800.ChecksStatus).toBe('Failing');

        // 2. Even though the webhook event arriving after restart is bob-reviewer approving,
        // the authoritative live state fetcher reports 'CHANGES_REQUESTED' (because alice-dev requested changes before restart)
        const bobApproveRaw = JSON.stringify({
            action: 'submitted',
            repository: { name: 'bizapps-tasks', owner: { login: 'MemberJunction' } },
            pull_request: {
                number: 800,
                node_id: 'PR_800',
                title: 'feat: durable check and review state across restarts',
                body: 'Verifies live state fetcher',
                html_url: 'https://github.com/MemberJunction/bizapps-tasks/pull/800',
                state: 'open',
                draft: false,
                head: { ref: 'feat/durable-state', sha: 'sha-live-800' },
                base: { ref: 'next' },
                updated_at: '2026-11-10T16:05:00.000Z',
            },
            review: {
                state: 'approved',
                user: { login: 'bob-reviewer' },
            },
        });
        await GitHubWebhookService.Instance.HandleWebhook({
            eventName: 'pull_request_review',
            deliveryId: 'pr-800-bob-approve',
            signatureHeader: `sha256=${createHmac('sha256', secret).update(bobApproveRaw, 'utf8').digest('hex')}`,
            rawPayload: bobApproveRaw,
            webhookSecret: secret,
            contextUser: h.contextUser,
            provider: h.provider,
        });

        pr800 = Array.from(h.getStore(GITHUB_PR_TASKS_ENTITY).values())[0];
        expect(pr800.ReviewDecision).toBe('CHANGES_REQUESTED');

        // 3. Once check A is re-run and alice-dev approves on GitHub, the next events store 'Passing' and 'APPROVED'
        authoritativeChecksStatus = 'Passing';
        authoritativeReviewDecision = 'APPROVED';

        await GitHubWebhookService.Instance.HandleWebhook({
            eventName: 'check_run',
            deliveryId: 'pr-800-check-a-rerun-pass',
            signatureHeader: `sha256=${createHmac('sha256', secret).update(checkBPassRaw, 'utf8').digest('hex')}`,
            rawPayload: checkBPassRaw,
            webhookSecret: secret,
            contextUser: h.contextUser,
            provider: h.provider,
        });
        await GitHubWebhookService.Instance.HandleWebhook({
            eventName: 'pull_request_review',
            deliveryId: 'pr-800-alice-approve',
            signatureHeader: `sha256=${createHmac('sha256', secret).update(bobApproveRaw, 'utf8').digest('hex')}`,
            rawPayload: bobApproveRaw,
            webhookSecret: secret,
            contextUser: h.contextUser,
            provider: h.provider,
        });

        pr800 = Array.from(h.getStore(GITHUB_PR_TASKS_ENTITY).values())[0];
        expect(pr800.ChecksStatus).toBe('Passing');
        expect(pr800.ReviewDecision).toBe('APPROVED');
        expect(GitHubWebhookService.Instance.GetTrackedCheckShaCount()).toBe(1);
        expect(GitHubWebhookService.Instance.GetTrackedPrReviewCount()).toBe(1);
    });

    it('persists IS-A leaf in a single Save() inside BeginEntityTransaction and rolls back both Task and extension if TaskAssignment save fails', async () => {
        const h = buildTestHarness();
        const originalGetEntityObject = h.provider.GetEntityObject.bind(h.provider);

        // 1. Happy path: single IS-A leaf Save() + assignment reconciliation commit atomically
        const okSummary = await GitHubTaskSyncService.Instance.SyncRepositories({
            repositoryId: h.ids.REPO_ALL_ID,
            items: [
                {
                    kind: 'issue',
                    number: 901,
                    nodeId: 'I_901',
                    title: 'Atomic IS-A leaf save',
                    body: 'Single-save persistence',
                    htmlUrl: 'https://github.com/MemberJunction/bizapps-tasks/issues/901',
                    state: 'open',
                    assigneeLogins: ['alice-dev'],
                },
            ],
            contextUser: h.contextUser,
            provider: h.provider,
            runInference: false,
        });

        expect(okSummary[0].created).toBe(1);
        expect(h.saveCounts.get(TASKS_ENTITY_NAME) ?? 0).toBe(0);
        expect(h.saveCounts.get(GITHUB_ISSUE_TASKS_ENTITY)).toBe(1);
        expect(h.saveCounts.get(TASK_ASSIGNMENTS_ENTITY)).toBe(1);
        expect(h.txStats.began).toBe(1);
        expect(h.txStats.committed).toBe(1);
        expect(h.txStats.rolledBack).toBe(0);
        expect(h.getStore(TASKS_ENTITY_NAME).size).toBe(1);
        expect(h.getStore(GITHUB_ISSUE_TASKS_ENTITY).size).toBe(1);
        expect(h.getStore(TASK_ASSIGNMENTS_ENTITY).size).toBe(1);

        // 2. Failure path: if TaskAssignment.Save() fails, the entire transaction rolls back (no orphan Task/Issue row)
        h.provider.GetEntityObject = async (entityName: string) => {
            const entity = await originalGetEntityObject(entityName);
            if (entityName === TASK_ASSIGNMENTS_ENTITY) {
                entity.Save = async () => {
                    entity.LatestResult = { CompleteMessage: 'Simulated TaskAssignment failure' };
                    return false;
                };
            }
            return entity;
        };

        await expect(
            GitHubTaskSyncService.Instance.SyncRepositories({
                repositoryId: h.ids.REPO_ALL_ID,
                items: [
                    {
                        kind: 'issue',
                        number: 902,
                        nodeId: 'I_902',
                        title: 'Should roll back completely',
                        body: 'Assignment failure triggers rollback',
                        htmlUrl: 'https://github.com/MemberJunction/bizapps-tasks/issues/902',
                        state: 'open',
                        assigneeLogins: ['alice-dev'],
                    },
                ],
                contextUser: h.contextUser,
                provider: h.provider,
                runInference: false,
            }),
        ).rejects.toThrow(/Simulated TaskAssignment failure/);

        expect(h.txStats.rolledBack).toBe(1);
        // Only issue #901 remains; #902 left zero orphan Task or GitHubIssueTask rows
        expect(h.getStore(TASKS_ENTITY_NAME).size).toBe(1);
        expect(h.getStore(GITHUB_ISSUE_TASKS_ENTITY).size).toBe(1);
        expect(h.getStore(TASK_ASSIGNMENTS_ENTITY).size).toBe(1);
    });

    it('reconciles TaskAssignments via parent Task Assignments RelatedRecordCollection companion when available', async () => {
        const h = buildTestHarness();
        const originalGetEntityObject = h.provider.GetEntityObject.bind(h.provider);

        let companionCreates = 0;
        let companionRemoves = 0;
        let parentSaves = 0;

        h.provider.GetEntityObject = async (entityName: string) => {
            const entity = await originalGetEntityObject(entityName);
            if (entityName === GITHUB_ISSUE_TASKS_ENTITY) {
                const items: mjBizAppsTasksTaskAssignmentEntity[] = [];
                const removed: mjBizAppsTasksTaskAssignmentEntity[] = [];
                let loaded = false;
                let dirty = false;

                const fakeCollection = {
                    IsReadOnly: false,
                    get IsLoaded() {
                        return loaded;
                    },
                    get Dirty() {
                        return dirty;
                    },
                    get Items() {
                        return items;
                    },
                    Load: async () => {
                        loaded = true;
                        items.length = 0;
                        for (const rec of h.getStore(TASK_ASSIGNMENTS_ENTITY).values()) {
                            if (String(rec.TaskID ?? '').toLowerCase() === entity.ID.toLowerCase()) {
                                const row = await originalGetEntityObject<mjBizAppsTasksTaskAssignmentEntity>(
                                    TASK_ASSIGNMENTS_ENTITY,
                                    h.contextUser,
                                );
                                Object.assign(row, rec);
                                items.push(row);
                            }
                        }
                    },
                    Create: async () => {
                        companionCreates += 1;
                        dirty = true;
                        const row = await originalGetEntityObject<mjBizAppsTasksTaskAssignmentEntity>(
                            TASK_ASSIGNMENTS_ENTITY,
                            h.contextUser,
                        );
                        row.NewRecord();
                        items.push(row);
                        return row;
                    },
                    Remove: (row: mjBizAppsTasksTaskAssignmentEntity) => {
                        companionRemoves += 1;
                        dirty = true;
                        const idx = items.indexOf(row);
                        if (idx >= 0) {
                            items.splice(idx, 1);
                            removed.push(row);
                        }
                    },
                };

                const fakeParent = {
                    GetCompanion: (name: string) => (name === 'Assignments' ? fakeCollection : undefined),
                    Save: async () => {
                        parentSaves += 1;
                        for (const item of items) {
                            await item.Save();
                        }
                        for (const rem of removed) {
                            await rem.Delete();
                        }
                        removed.length = 0;
                        dirty = false;
                        return true;
                    },
                };

                Object.defineProperty(entity, 'ISAParent', {
                    value: fakeParent,
                    enumerable: false,
                });
            }
            return entity;
        };

        // Create with alice-dev via companion
        await GitHubTaskSyncService.Instance.SyncRepositories({
            repositoryId: h.ids.REPO_ALL_ID,
            items: [
                {
                    kind: 'issue',
                    number: 910,
                    nodeId: 'I_910',
                    title: 'Companion assignment sync',
                    body: 'Uses Assignments collection',
                    htmlUrl: 'https://github.com/MemberJunction/bizapps-tasks/issues/910',
                    state: 'open',
                    assigneeLogins: ['alice-dev'],
                },
            ],
            contextUser: h.contextUser,
            provider: h.provider,
            runInference: false,
        });

        expect(companionCreates).toBe(1);
        expect(parentSaves).toBe(1);
        expect(h.getStore(TASK_ASSIGNMENTS_ENTITY).size).toBe(1);

        // Update swapping alice-dev -> bob-reviewer via companion
        await GitHubTaskSyncService.Instance.SyncRepositories({
            repositoryId: h.ids.REPO_ALL_ID,
            items: [
                {
                    kind: 'issue',
                    number: 910,
                    nodeId: 'I_910',
                    title: 'Companion assignment sync',
                    body: 'Swapped assignee',
                    htmlUrl: 'https://github.com/MemberJunction/bizapps-tasks/issues/910',
                    state: 'open',
                    assigneeLogins: ['bob-reviewer'],
                },
            ],
            contextUser: h.contextUser,
            provider: h.provider,
            runInference: false,
        });

        expect(companionCreates).toBe(2);
        expect(companionRemoves).toBe(1);
        expect(parentSaves).toBe(2);
        const storedAssignments = Array.from(h.getStore(TASK_ASSIGNMENTS_ENTITY).values());
        expect(storedAssignments).toHaveLength(1);
        expect(storedAssignments[0].AssigneeRecordID).toBe(h.ids.BOB_PERSON_ID);
    });

    it('wraps multi-PR UpdatePullRequestChecksStatus saves in BeginEntityTransaction and rolls back on partial failure', async () => {
        const h = buildTestHarness();
        const sha = 'deadbeef1234567890';

        // Seed two PRs sharing the same HeadSha
        await GitHubTaskSyncService.Instance.SyncRepositories({
            repositoryId: h.ids.REPO_ALL_ID,
            items: [
                {
                    kind: 'pull_request',
                    number: 920,
                    nodeId: 'PR_920',
                    title: 'PR 1 on shared SHA',
                    body: '',
                    htmlUrl: 'https://github.com/MemberJunction/bizapps-tasks/pull/920',
                    state: 'open',
                    headSha: sha,
                    checksStatus: 'Pending',
                },
                {
                    kind: 'pull_request',
                    number: 921,
                    nodeId: 'PR_921',
                    title: 'PR 2 on shared SHA',
                    body: '',
                    htmlUrl: 'https://github.com/MemberJunction/bizapps-tasks/pull/921',
                    state: 'open',
                    headSha: sha,
                    checksStatus: 'Pending',
                },
            ],
            contextUser: h.contextUser,
            provider: h.provider,
            runInference: false,
        });

        const repo = await h.provider.GetEntityObject<mjBizAppsTasksGitHubGitHubRepositoryEntity>(
            GITHUB_REPOSITORIES_ENTITY,
            h.contextUser,
        );
        await repo.Load(h.ids.REPO_ALL_ID);

        // Fail the second PR save inside UpdatePullRequestChecksStatus
        const origRunView = h.provider.RunView.bind(h.provider);
        h.provider.RunView = async (params: RunViewParams) => {
            const res = await origRunView(params);
            if (params.EntityName === GITHUB_PR_TASKS_ENTITY && Array.isArray(res.Results) && res.Results.length === 2) {
                const second = res.Results[1] as { Save: () => Promise<boolean>; LatestResult: { CompleteMessage: string } };
                second.Save = async () => {
                    second.LatestResult = { CompleteMessage: 'Simulated second PR save error' };
                    return false;
                };
            }
            return res;
        };

        const rollbacksBefore = h.txStats.rolledBack;
        await expect(
            GitHubTaskSyncService.Instance.UpdatePullRequestChecksStatus({
                repository: repo,
                headSha: sha,
                checksStatus: 'Passing',
                contextUser: h.contextUser,
                provider: h.provider,
            }),
        ).rejects.toThrow(/Simulated second PR save error/);

        expect(h.txStats.rolledBack).toBe(rollbacksBefore + 1);
        // Both PRs must still have 'Pending' because the transaction rolled back atomically
        const prs = Array.from(h.getStore(GITHUB_PR_TASKS_ENTITY).values());
        expect(prs.every((p) => p.ChecksStatus === 'Pending')).toBe(true);
    });

    it('accepts Critical and rejects Urgent in GitHubTaskInferenceService (Rule 2c) and wraps supersede+create in BeginEntityTransaction', async () => {
        const h = buildTestHarness();
        const taskId = '11111111-2222-4333-8444-555555555555';

        // Seed an existing pending Priority suggestion that should be superseded only if new suggestion commits
        const priorSuggestionId = '99999999-8888-4777-8666-555555555551';
        h.getStore(FIELD_SUGGESTIONS_ENTITY_NAME).set(priorSuggestionId, {
            ID: priorSuggestionId,
            LinkedEntityID: '11111111-1111-4111-8111-000000000001',
            LinkedRecordID: taskId,
            AnchorType: 'Field',
            AnchorKey: 'Priority',
            SuggestedValue: '"High"',
            Outcome: null,
            IsResolved: false,
        });

        // 1. 'Urgent' must be rejected (violates CK_Task_Priority)
        GitHubTaskInferenceService.Instance.SetExtractor({
            ExtractPlanningSuggestions: async () => ({
                suggestions: [
                    {
                        field: 'Priority',
                        value: 'Urgent',
                        confidence: 0.95,
                        rationale: 'Legacy invalid priority value',
                    },
                ],
                mentionedLogins: [],
                promptRunId: null,
            }),
        });

        const urgentRes = await GitHubTaskInferenceService.Instance.InferTaskPlanningFields({
            task: {
                ID: taskId,
                DueAt: null,
                HoursEstimated: null,
                ParentID: null,
                CategoryID: null,
                Priority: null,
            },
            repositoryId: h.ids.REPO_ALL_ID,
            repositoryFullName: 'MemberJunction/bizapps-tasks',
            itemKind: 'issue',
            number: 950,
            title: 'Production outage',
            body: 'Needs immediate attention',
            milestoneDueAt: null,
            structuredLogins: [],
            contextUser: h.contextUser,
            provider: h.provider,
        });

        expect(urgentRes.createdCount).toBe(0);
        expect(urgentRes.skippedFields).toEqual(['Priority']);
        expect(h.getStore(FIELD_SUGGESTIONS_ENTITY_NAME).get(priorSuggestionId)?.Outcome).toBeNull();

        // 2. 'Critical' must be accepted and supersede+create must run atomically in a transaction
        GitHubTaskInferenceService.Instance.SetExtractor({
            ExtractPlanningSuggestions: async () => ({
                suggestions: [
                    {
                        field: 'Priority',
                        value: 'Critical',
                        confidence: 0.96,
                        rationale: 'Matches CK_Task_Priority Critical value',
                    },
                ],
                mentionedLogins: [],
                promptRunId: null,
            }),
        });

        const originalGetEntityObject = h.provider.GetEntityObject.bind(h.provider);
        // First simulate a failure on creating the new Field Suggestion -> supersede must roll back!
        h.provider.GetEntityObject = async (entityName: string) => {
            const entity = await originalGetEntityObject(entityName);
            if (entityName === FIELD_SUGGESTIONS_ENTITY_NAME) {
                entity.Save = async () => {
                    entity.LatestResult = { CompleteMessage: 'Simulated suggestion insert failure' };
                    return false;
                };
            }
            return entity;
        };

        const rollbacksBefore = h.txStats.rolledBack;
        await expect(
            GitHubTaskInferenceService.Instance.InferTaskPlanningFields({
                task: {
                    ID: taskId,
                    DueAt: null,
                    HoursEstimated: null,
                    ParentID: null,
                    CategoryID: null,
                    Priority: null,
                },
                repositoryId: h.ids.REPO_ALL_ID,
                repositoryFullName: 'MemberJunction/bizapps-tasks',
                itemKind: 'issue',
                number: 950,
                title: 'Production outage',
                body: 'Needs immediate attention',
                milestoneDueAt: null,
                structuredLogins: [],
                contextUser: h.contextUser,
                provider: h.provider,
            }),
        ).rejects.toThrow(/Simulated suggestion insert failure/);

        expect(h.txStats.rolledBack).toBe(rollbacksBefore + 1);
        // Prior suggestion must STILL be pending because supersede rolled back!
        expect(h.getStore(FIELD_SUGGESTIONS_ENTITY_NAME).get(priorSuggestionId)?.Outcome).toBeNull();
        expect(h.getStore(FIELD_SUGGESTIONS_ENTITY_NAME).get(priorSuggestionId)?.IsResolved).toBe(false);

        // Now allow save to succeed -> prior superseded, new 'Critical' suggestion created atomically
        h.provider.GetEntityObject = originalGetEntityObject;
        const criticalRes = await GitHubTaskInferenceService.Instance.InferTaskPlanningFields({
            task: {
                ID: taskId,
                DueAt: null,
                HoursEstimated: null,
                ParentID: null,
                CategoryID: null,
                Priority: null,
            },
            repositoryId: h.ids.REPO_ALL_ID,
            repositoryFullName: 'MemberJunction/bizapps-tasks',
            itemKind: 'issue',
            number: 950,
            title: 'Production outage',
            body: 'Needs immediate attention',
            milestoneDueAt: null,
            structuredLogins: [],
            contextUser: h.contextUser,
            provider: h.provider,
        });

        expect(criticalRes.createdCount).toBe(1);
        expect(criticalRes.supersededCount).toBe(1);
        expect(h.getStore(FIELD_SUGGESTIONS_ENTITY_NAME).get(priorSuggestionId)?.Outcome).toBe('Superseded');
        const created = h.getStore(FIELD_SUGGESTIONS_ENTITY_NAME).get(criticalRes.createdSuggestionIds[0].toLowerCase());
        expect(created?.SuggestedValue).toBe('"Critical"');
    });
});
