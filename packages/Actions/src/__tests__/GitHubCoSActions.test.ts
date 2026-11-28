import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { BaseAction } from '@memberjunction/actions';
import type { ActionParam, RunActionParams } from '@memberjunction/actions-base';
import { TypedActionPolicyGuard } from '@memberjunction/ai-core-plus';
import { RunView, type RunViewParams, type RunViewResult, type UserInfo } from '@memberjunction/core';
import { IsValidUUID, MJGlobal } from '@memberjunction/global';
import type {
    mjBizAppsTasksTaskAssignmentEntity,
    mjBizAppsTasksTaskRoleEntity,
} from '@mj-biz-apps/tasks-entities';
import {
    GitHubTasksEngineBase,
    type mjBizAppsTasksGitHubGitHubIdentityEntity,
    type mjBizAppsTasksGitHubGitHubIssueTaskEntity,
    type mjBizAppsTasksGitHubGitHubPullRequestTaskEntity,
    type mjBizAppsTasksGitHubGitHubRepositoryEntity,
} from '@mj-biz-apps/tasks-github-entities';
import {
    GITHUB_IDENTITIES_ENTITY,
    GITHUB_ISSUE_TASKS_ENTITY,
    GITHUB_PR_TASKS_ENTITY,
    GITHUB_REPOSITORIES_ENTITY,
    PEOPLE_ENTITY,
    TASK_ASSIGNMENTS_ENTITY,
    TASK_ROLES_ENTITY,
} from '@mj-biz-apps/tasks-github-core';
import {
    GetGitHubReviewsWaitingOnMeAction,
    GetMyGitHubBriefingAction,
    GetMyGitHubPRsAction,
    LoadTasksGitHubActions,
    type GitHubBlockedOrFailingRow,
    type GitHubReviewWaitingRow,
    type GitHubUpcomingDeadlineRow,
    type MyGitHubPRRow,
} from '../index.js';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = path.resolve(__dirname, '../../../..');

const USER_ALICE_ID = '10000000-0000-4000-8000-000000000001';
const PERSON_ALICE_ID = '20000000-0000-4000-8000-000000000001';
const PERSON_BOB_ID = '20000000-0000-4000-8000-000000000002';
const ROLE_PRIMARY_ID = '30000000-0000-4000-8000-000000000001';
const ROLE_REVIEWER_ID = '30000000-0000-4000-8000-000000000002';
const REPO_MJ_ID = '40000000-0000-4000-8000-000000000001';
const REPO_TASKS_ID = '40000000-0000-4000-8000-000000000002';
const PR_TASK_1 = '50000000-0000-4000-8000-000000000001';
const PR_TASK_2 = '50000000-0000-4000-8000-000000000002';
const PR_TASK_3 = '50000000-0000-4000-8000-000000000003';
const PR_TASK_4 = '50000000-0000-4000-8000-000000000004';
const PR_TASK_5 = '50000000-0000-4000-8000-000000000005';
const PR_TASK_6 = '50000000-0000-4000-8000-000000000006';
const ISSUE_TASK_1 = '60000000-0000-4000-8000-000000000001';
const ISSUE_TASK_2 = '60000000-0000-4000-8000-000000000002';

const HOUR_MS = 3_600_000;
const DAY_MS = 86_400_000;

interface MockPersonRow {
    ID: string;
    FirstName: string;
    LastName: string;
    DisplayName: string;
    Email: string;
    LinkedUserID: string | null;
    Status: string;
}

interface MockGitHubFixtures {
    people?: MockPersonRow[];
    identities?: Partial<mjBizAppsTasksGitHubGitHubIdentityEntity>[];
    roles?: Partial<mjBizAppsTasksTaskRoleEntity>[];
    assignments?: Partial<mjBizAppsTasksTaskAssignmentEntity>[];
    repositories?: Partial<mjBizAppsTasksGitHubGitHubRepositoryEntity>[];
    prs?: Partial<mjBizAppsTasksGitHubGitHubPullRequestTaskEntity>[];
    issues?: Partial<mjBizAppsTasksGitHubGitHubIssueTaskEntity>[];
}

interface PRsActionPayload {
    PersonID: string;
    GitHubLogins: string[];
    StateFilter: string;
    RepositoryFilter: string | null;
    IncludeDrafts: boolean;
    TotalCount: number;
    ReturnedCount: number;
    PullRequests: Array<Partial<MyGitHubPRRow>>;
}

interface ReviewsActionPayload {
    PersonID: string;
    GitHubLogins: string[];
    RepositoryFilter: string | null;
    MinAgeHours: number;
    StaleThresholdHours: number;
    TotalWaiting: number;
    StaleCount: number;
    ReturnedCount: number;
    Reviews: Array<Partial<GitHubReviewWaitingRow>>;
}

interface BriefingActionPayload {
    GeneratedAt: string;
    HorizonDays: number;
    HorizonEnd: string;
    PersonID: string;
    GitHubLogins: string[];
    Summary: string;
    Counts: {
        OpenPRs: number;
        DraftPRs: number;
        RecentlyUpdatedPRs: number;
        FailingCIPRs: number;
        ChangesRequestedPRs: number;
        ReviewsWaiting: number;
        StaleReviews: number;
        BlockedOrFailingTasks: number;
        UpcomingDeadlines: number;
    };
    OpenPRs: Array<Partial<MyGitHubPRRow>>;
    ReviewsWaitingOnMe: Array<Partial<GitHubReviewWaitingRow>>;
    BlockedOrFailingTasks: Array<Partial<GitHubBlockedOrFailingRow>>;
    UpcomingDeadlines: Array<Partial<GitHubUpcomingDeadlineRow>>;
}

function makeUser(id = USER_ALICE_ID, email = 'alice@example.com'): UserInfo {
    return {
        ID: id,
        Name: 'Alice Developer',
        Email: email,
        IsActive: true,
    } as UserInfo;
}

function makeRunParams(
    inputParams: Array<{ Name: string; Value: ActionParam['Value'] }> = [],
    user: UserInfo = makeUser(),
    agentId?: string,
): RunActionParams {
    const params: ActionParam[] = inputParams.map((p) => ({
        Name: p.Name,
        Type: 'Input',
        Value: p.Value,
    }));
    return {
        Action: {} as RunActionParams['Action'],
        ContextUser: user,
        Filters: [],
        Params: params,
        Context: agentId ? { AgentID: agentId } : undefined,
    };
}

function getOutputParam(params: RunActionParams, name: string): ActionParam['Value'] {
    return params.Params.find((p) => p.Name === name && p.Type === 'Output')?.Value;
}

function makeSuccessViewResult<T>(rows: T[]): RunViewResult<T> {
    return {
        Success: true,
        Results: rows,
        RowCount: rows.length,
        TotalRowCount: rows.length,
        ExecutionTime: 1,
        ErrorMessage: '',
        UserViewRunID: '',
    };
}

function installMockRunView(fixtures: MockGitHubFixtures): void {
    const resolveEntityRows = (req: RunViewParams): RunViewResult => {
        switch (req.EntityName) {
            case PEOPLE_ENTITY:
                return makeSuccessViewResult(fixtures.people ?? []);
            case GITHUB_IDENTITIES_ENTITY:
                return makeSuccessViewResult(fixtures.identities ?? []);
            case TASK_ROLES_ENTITY:
                return makeSuccessViewResult(
                    fixtures.roles ?? [
                        { ID: ROLE_PRIMARY_ID, Name: 'Primary' },
                        { ID: ROLE_REVIEWER_ID, Name: 'Reviewer' },
                    ],
                );
            case TASK_ASSIGNMENTS_ENTITY:
                return makeSuccessViewResult(fixtures.assignments ?? []);
            case GITHUB_REPOSITORIES_ENTITY:
                return makeSuccessViewResult(
                    fixtures.repositories ?? [
                        { ID: REPO_MJ_ID, Owner: 'MemberJunction', Name: 'MJ' },
                        { ID: REPO_TASKS_ID, Owner: 'MemberJunction', Name: 'bizapps-tasks' },
                    ],
                );
            case GITHUB_PR_TASKS_ENTITY:
                return makeSuccessViewResult(fixtures.prs ?? []);
            case GITHUB_ISSUE_TASKS_ENTITY:
                return makeSuccessViewResult(fixtures.issues ?? []);
            default:
                return makeSuccessViewResult([]);
        }
    };

    vi.spyOn(RunView.prototype, 'RunView').mockImplementation((async (req: RunViewParams) =>
        resolveEntityRows(req)) as RunView['RunView']);
    vi.spyOn(RunView.prototype, 'RunViews').mockImplementation((async (reqs: RunViewParams[]) =>
        reqs.map((r) => resolveEntityRows(r))) as RunView['RunViews']);
}

function defaultPeopleAndIdentities(): Pick<MockGitHubFixtures, 'people' | 'identities'> {
    return {
        people: [
            {
                ID: PERSON_ALICE_ID,
                FirstName: 'Alice',
                LastName: 'Developer',
                DisplayName: 'Alice Developer',
                Email: 'alice@example.com',
                LinkedUserID: USER_ALICE_ID,
                Status: 'Active',
            },
        ],
        identities: [
            {
                ID: '70000000-0000-4000-8000-000000000001',
                GitHubLogin: 'AliceDev',
                PersonID: PERSON_ALICE_ID,
                IsActive: true,
            },
        ],
    };
}

describe('Chief of Staff GitHub Extensible Skills Actions', () => {
    afterEach(() => {
        GitHubTasksEngineBase.Instance.ResetCaches();
        vi.restoreAllMocks();
    });

    it('registers all 3 CoS GitHub actions with ClassFactory and enforces AuthorizesCaller = true', () => {
        LoadTasksGitHubActions();
        const factory = MJGlobal.Instance.ClassFactory;

        expect(factory.GetRegistration(BaseAction, 'GetMyGitHubPRsAction')?.SubClass).toBe(
            GetMyGitHubPRsAction,
        );
        expect(factory.GetRegistration(BaseAction, 'GetGitHubReviewsWaitingOnMeAction')?.SubClass).toBe(
            GetGitHubReviewsWaitingOnMeAction,
        );
        expect(factory.GetRegistration(BaseAction, 'GetMyGitHubBriefingAction')?.SubClass).toBe(
            GetMyGitHubBriefingAction,
        );

        expect(GetMyGitHubPRsAction.AuthorizesCaller).toBe(true);
        expect(GetGitHubReviewsWaitingOnMeAction.AuthorizesCaller).toBe(true);
        expect(GetMyGitHubBriefingAction.AuthorizesCaller).toBe(true);
    });

    describe('GetMyGitHubPRsAction', () => {
        it('returns authored and non-reviewer assigned PRs with state, draft, repository, and limit filters', async () => {
            const now = Date.now();
            installMockRunView({
                ...defaultPeopleAndIdentities(),
                assignments: [
                    // Primary assignee on PR #2 (authored by Bob)
                    {
                        ID: 'a1',
                        TaskID: PR_TASK_2,
                        AssigneeRecordID: PERSON_ALICE_ID,
                        RoleID: ROLE_PRIMARY_ID,
                        Role: 'Primary',
                        Status: 'InProgress',
                        AssignedAt: new Date(now - 5 * HOUR_MS),
                    },
                    // Reviewer-only assignment on PR #6 (must NOT appear in Get My GitHub PRs)
                    {
                        ID: 'a2',
                        TaskID: PR_TASK_6,
                        AssigneeRecordID: PERSON_ALICE_ID,
                        RoleID: ROLE_REVIEWER_ID,
                        Role: 'Reviewer',
                        Status: 'Pending',
                        AssignedAt: new Date(now - 30 * HOUR_MS),
                    },
                ],
                prs: [
                    {
                        ID: PR_TASK_1,
                        RepositoryID: REPO_MJ_ID,
                        Repository: 'MJ',
                        Number: 4101,
                        Name: 'feat: policy-guarded CoS actions',
                        State: 'open',
                        IsDraft: false,
                        AuthorLogin: 'alicedev', // case-insensitive match to AliceDev
                        ReviewDecision: 'APPROVED',
                        ChecksStatus: 'Passing',
                        HtmlURL: 'https://github.com/MemberJunction/MJ/pull/4101',
                        Status: 'InProgress',
                        Priority: 'High',
                        GitHubUpdatedAt: new Date(now - 2 * HOUR_MS),
                        __mj_CreatedAt: new Date(now - 10 * HOUR_MS),
                    },
                    {
                        ID: PR_TASK_2,
                        RepositoryID: REPO_TASKS_ID,
                        Repository: 'bizapps-tasks',
                        Number: 205,
                        Name: 'fix: task assignment rollup',
                        State: 'open',
                        IsDraft: false,
                        AuthorLogin: 'bobdev',
                        ReviewDecision: 'CHANGES_REQUESTED',
                        ChecksStatus: 'Failing',
                        HtmlURL: 'https://github.com/MemberJunction/bizapps-tasks/pull/205',
                        Status: 'Blocked',
                        Priority: 'Critical',
                        GitHubUpdatedAt: new Date(now - 4 * HOUR_MS),
                        __mj_CreatedAt: new Date(now - 20 * HOUR_MS),
                    },
                    {
                        ID: PR_TASK_3,
                        RepositoryID: REPO_MJ_ID,
                        Repository: 'MJ',
                        Number: 4102,
                        Name: 'wip: draft schema cleanup',
                        State: 'open',
                        IsDraft: true,
                        AuthorLogin: 'AliceDev',
                        ReviewDecision: null,
                        ChecksStatus: 'Pending',
                        HtmlURL: 'https://github.com/MemberJunction/MJ/pull/4102',
                        Status: 'Open',
                        Priority: 'Medium',
                        GitHubUpdatedAt: new Date(now - 1 * HOUR_MS),
                        __mj_CreatedAt: new Date(now - 3 * HOUR_MS),
                    },
                    {
                        ID: PR_TASK_4,
                        RepositoryID: REPO_MJ_ID,
                        Repository: 'MJ',
                        Number: 4090,
                        Name: 'chore: merged telemetry update',
                        State: 'merged',
                        IsDraft: false,
                        AuthorLogin: 'AliceDev',
                        ReviewDecision: 'APPROVED',
                        ChecksStatus: 'Passing',
                        HtmlURL: 'https://github.com/MemberJunction/MJ/pull/4090',
                        Status: 'Completed',
                        Priority: 'Low',
                        GitHubUpdatedAt: new Date(now - 48 * HOUR_MS),
                        __mj_CreatedAt: new Date(now - 72 * HOUR_MS),
                    },
                    {
                        ID: PR_TASK_5,
                        RepositoryID: REPO_MJ_ID,
                        Repository: 'MJ',
                        Number: 4088,
                        Name: 'chore: closed experiment',
                        State: 'closed',
                        IsDraft: false,
                        AuthorLogin: 'AliceDev',
                        ReviewDecision: null,
                        ChecksStatus: 'Neutral',
                        HtmlURL: 'https://github.com/MemberJunction/MJ/pull/4088',
                        Status: 'Cancelled',
                        Priority: 'Low',
                        GitHubUpdatedAt: new Date(now - 96 * HOUR_MS),
                        __mj_CreatedAt: new Date(now - 100 * HOUR_MS),
                    },
                    {
                        ID: PR_TASK_6,
                        RepositoryID: REPO_MJ_ID,
                        Repository: 'MJ',
                        Number: 4099,
                        Name: 'feat: bob PR waiting on alice review',
                        State: 'open',
                        IsDraft: false,
                        AuthorLogin: 'bobdev',
                        CreatedByPersonID: PERSON_BOB_ID,
                        ReviewDecision: 'REVIEW_REQUIRED',
                        ChecksStatus: 'Passing',
                        HtmlURL: 'https://github.com/MemberJunction/MJ/pull/4099',
                        Status: 'Open',
                        Priority: 'Medium',
                        GitHubUpdatedAt: new Date(now - 30 * HOUR_MS),
                        __mj_CreatedAt: new Date(now - 32 * HOUR_MS),
                    },
                ],
            });

            const action = new GetMyGitHubPRsAction();

            // 1. Default Open state includes open + draft authored/assigned PRs, excludes merged/closed/reviewer-only
            const openParams = makeRunParams();
            const openRes = await action.Run(openParams);
            expect(openRes.Success).toBe(true);
            expect(openRes.ResultCode).toBe('SUCCESS');

            const outJson = getOutputParam(openParams, 'PullRequestsJSON') as string;
            expect(outJson).toBe(openRes.Message);
            const openPayload = JSON.parse(outJson) as PRsActionPayload;
            expect(openPayload.TotalCount).toBe(3);
            expect(openPayload.PullRequests.map((p) => p.PRNumber)).toEqual([4102, 4101, 205]);

            const pr4101 = openPayload.PullRequests.find((p) => p.PRNumber === 4101)!;
            expect(pr4101).toMatchObject({
                TaskID: PR_TASK_1,
                PRNumber: 4101,
                Title: 'feat: policy-guarded CoS actions',
                Repository: 'MemberJunction/MJ',
                State: 'open',
                IsDraft: false,
                ReviewDecision: 'APPROVED',
                CIStatus: 'Passing',
                URL: 'https://github.com/MemberJunction/MJ/pull/4101',
                Involvement: 'Author',
            });
            expect(pr4101.UpdatedAt).toBeTruthy();
            expect(pr4101.AgeHours).toBeGreaterThanOrEqual(9.5);

            const pr205 = openPayload.PullRequests.find((p) => p.PRNumber === 205)!;
            expect(pr205.Repository).toBe('MemberJunction/bizapps-tasks');
            expect(pr205.Involvement).toBe('Assignee');

            // 2. IncludeDrafts = false excludes draft PR #4102
            const noDraftsParams = makeRunParams([{ Name: 'IncludeDrafts', Value: false }]);
            const noDraftsRes = await action.Run(noDraftsParams);
            const noDraftsPayload = JSON.parse(noDraftsRes.Message!) as PRsActionPayload;
            expect(noDraftsPayload.PullRequests.map((p) => p.PRNumber)).toEqual([4101, 205]);

            // 3. State = 'Draft' returns strictly drafts
            const draftParams = makeRunParams([{ Name: 'State', Value: 'Draft' }]);
            const draftRes = await action.Run(draftParams);
            const draftPayload = JSON.parse(draftRes.Message!) as PRsActionPayload;
            expect(draftPayload.PullRequests.map((p) => p.PRNumber)).toEqual([4102]);

            // 4. State = 'Merged' & 'Closed' & 'All'
            const mergedRes = await action.Run(makeRunParams([{ Name: 'State', Value: 'Merged' }]));
            expect((JSON.parse(mergedRes.Message!) as PRsActionPayload).PullRequests.map((p) => p.PRNumber)).toEqual([4090]);

            const closedRes = await action.Run(makeRunParams([{ Name: 'State', Value: 'Closed' }]));
            expect((JSON.parse(closedRes.Message!) as PRsActionPayload).PullRequests.map((p) => p.PRNumber)).toEqual([4088]);

            const allRes = await action.Run(makeRunParams([{ Name: 'State', Value: 'All' }]));
            expect((JSON.parse(allRes.Message!) as PRsActionPayload).TotalCount).toBe(5);

            // 5. RepositoryName slug filter + Limit
            const repoParams = makeRunParams([
                { Name: 'State', Value: 'Open' },
                { Name: 'RepositoryName', Value: 'bizapps-tasks' },
            ]);
            const repoRes = await action.Run(repoParams);
            expect((JSON.parse(repoRes.Message!) as PRsActionPayload).PullRequests.map((p) => p.PRNumber)).toEqual([205]);

            const limitRes = await action.Run(makeRunParams([{ Name: 'Limit', Value: 1 }]));
            const limitPayload = JSON.parse(limitRes.Message!) as PRsActionPayload;
            expect(limitPayload.TotalCount).toBe(3);
            expect(limitPayload.ReturnedCount).toBe(1);
            expect(limitPayload.PullRequests).toHaveLength(1);
        });

        it('returns NO_PERSON_RECORD when caller has no linked Person and INVALID_PARAMS on invalid filters', async () => {
            installMockRunView({ people: [] });
            const action = new GetMyGitHubPRsAction();

            const noPersonRes = await action.Run(makeRunParams());
            expect(noPersonRes.Success).toBe(false);
            expect(noPersonRes.ResultCode).toBe('NO_PERSON_RECORD');

            const badStateRes = await action.Run(makeRunParams([{ Name: 'State', Value: 'InvalidState' }]));
            expect(badStateRes.Success).toBe(false);
            expect(badStateRes.ResultCode).toBe('INVALID_PARAMS');

            const badLimitRes = await action.Run(makeRunParams([{ Name: 'Limit', Value: 0 }]));
            expect(badLimitRes.Success).toBe(false);
            expect(badLimitRes.ResultCode).toBe('INVALID_PARAMS');
        });

        it('enforces TypedActionPolicyGuard denial and field masking', async () => {
            const now = Date.now();
            installMockRunView({
                ...defaultPeopleAndIdentities(),
                prs: [
                    {
                        ID: PR_TASK_1,
                        RepositoryID: REPO_MJ_ID,
                        Number: 4101,
                        Name: 'feat: sensitive PR',
                        State: 'open',
                        IsDraft: false,
                        AuthorLogin: 'AliceDev',
                        ReviewDecision: 'APPROVED',
                        ChecksStatus: 'Passing',
                        HtmlURL: 'https://github.com/MemberJunction/MJ/pull/4101',
                        Status: 'Open',
                        Priority: 'High',
                        GitHubUpdatedAt: new Date(now - HOUR_MS),
                        __mj_CreatedAt: new Date(now - 2 * HOUR_MS),
                    },
                ],
            });

            // 1. Policy allows read with DeniedFieldPatterns (e.g. ReadOnly policy masking URL)
            const guardSpy = vi.spyOn(TypedActionPolicyGuard, 'CheckEntityAccess').mockResolvedValue({
                Allowed: true,
                Active: true,
                DeniedFieldPatterns: ['URL'],
            });

            const action = new GetMyGitHubPRsAction();
            const maskedRes = await action.Run(makeRunParams([], makeUser(), 'agent-cos-1'));
            expect(maskedRes.Success).toBe(true);
            const maskedPayload = JSON.parse(maskedRes.Message!) as PRsActionPayload;
            expect(maskedPayload.PullRequests).toHaveLength(1);
            expect(maskedPayload.PullRequests[0].URL).toBeUndefined();
            expect(maskedPayload.PullRequests[0].Title).toBe('feat: sensitive PR');

            // 2. Policy denies read
            guardSpy.mockResolvedValue({
                Allowed: false,
                Active: true,
                DeniedFieldPatterns: [],
                ResultCode: 'POLICY_DENIED',
                Message: 'DefaultDataAccessMode Deny blocks reading GitHub PR tasks.',
            });

            const deniedRes = await action.Run(makeRunParams([], makeUser(), 'agent-cos-1'));
            expect(deniedRes.Success).toBe(false);
            expect(deniedRes.ResultCode).toBe('POLICY_DENIED');
            expect(deniedRes.Message).toContain('DefaultDataAccessMode Deny');
        });
    });

    describe('GetGitHubReviewsWaitingOnMeAction', () => {
        it('returns open PR reviews waiting on caller sorted oldest-first with >24h stale flagging and filters', async () => {
            const now = Date.now();
            installMockRunView({
                ...defaultPeopleAndIdentities(),
                assignments: [
                    // 48h stale pending review in MemberJunction/MJ
                    {
                        ID: 'rev-1',
                        TaskID: PR_TASK_1,
                        AssigneeRecordID: PERSON_ALICE_ID,
                        RoleID: ROLE_REVIEWER_ID,
                        Role: 'Reviewer',
                        Status: 'Pending',
                        AssignedAt: new Date(now - 48 * HOUR_MS),
                    },
                    // 30h stale in-progress review in MemberJunction/bizapps-tasks
                    {
                        ID: 'rev-2',
                        TaskID: PR_TASK_2,
                        AssigneeRecordID: PERSON_ALICE_ID,
                        RoleID: ROLE_REVIEWER_ID,
                        Role: 'Reviewer',
                        Status: 'InProgress',
                        AssignedAt: new Date(now - 30 * HOUR_MS),
                    },
                    // 6h fresh pending review (not stale)
                    {
                        ID: 'rev-3',
                        TaskID: PR_TASK_3,
                        AssigneeRecordID: PERSON_ALICE_ID,
                        RoleID: ROLE_REVIEWER_ID,
                        Role: 'Reviewer',
                        Status: 'Pending',
                        AssignedAt: new Date(now - 6 * HOUR_MS),
                    },
                    // Completed review (must be excluded)
                    {
                        ID: 'rev-4',
                        TaskID: PR_TASK_4,
                        AssigneeRecordID: PERSON_ALICE_ID,
                        RoleID: ROLE_REVIEWER_ID,
                        Role: 'Reviewer',
                        Status: 'Completed',
                        AssignedAt: new Date(now - 72 * HOUR_MS),
                    },
                    // Merged PR with pending reviewer row (must be excluded)
                    {
                        ID: 'rev-5',
                        TaskID: PR_TASK_5,
                        AssigneeRecordID: PERSON_ALICE_ID,
                        RoleID: ROLE_REVIEWER_ID,
                        Role: 'Reviewer',
                        Status: 'Pending',
                        AssignedAt: new Date(now - 60 * HOUR_MS),
                    },
                    // Primary assignment (not a reviewer request; must be excluded)
                    {
                        ID: 'pri-1',
                        TaskID: PR_TASK_6,
                        AssigneeRecordID: PERSON_ALICE_ID,
                        RoleID: ROLE_PRIMARY_ID,
                        Role: 'Primary',
                        Status: 'InProgress',
                        AssignedAt: new Date(now - 50 * HOUR_MS),
                    },
                ],
                prs: [
                    {
                        ID: PR_TASK_1,
                        RepositoryID: REPO_MJ_ID,
                        Number: 501,
                        Name: 'feat: oldest waiting review',
                        AuthorLogin: 'carol',
                        State: 'open',
                        IsDraft: false,
                        ReviewDecision: 'REVIEW_REQUIRED',
                        ChecksStatus: 'Passing',
                        HtmlURL: 'https://github.com/MemberJunction/MJ/pull/501',
                        Status: 'Open',
                    },
                    {
                        ID: PR_TASK_2,
                        RepositoryID: REPO_TASKS_ID,
                        Number: 310,
                        Name: 'fix: second oldest waiting review',
                        AuthorLogin: 'dave',
                        State: 'open',
                        IsDraft: false,
                        ReviewDecision: 'REVIEW_REQUIRED',
                        ChecksStatus: 'Failing',
                        HtmlURL: 'https://github.com/MemberJunction/bizapps-tasks/pull/310',
                        Status: 'Open',
                    },
                    {
                        ID: PR_TASK_3,
                        RepositoryID: REPO_MJ_ID,
                        Number: 502,
                        Name: 'docs: fresh review request',
                        AuthorLogin: 'eve',
                        State: 'open',
                        IsDraft: false,
                        ReviewDecision: 'REVIEW_REQUIRED',
                        ChecksStatus: 'Passing',
                        HtmlURL: 'https://github.com/MemberJunction/MJ/pull/502',
                        Status: 'Open',
                    },
                    {
                        ID: PR_TASK_4,
                        RepositoryID: REPO_MJ_ID,
                        Number: 499,
                        Name: 'feat: already reviewed by alice',
                        AuthorLogin: 'frank',
                        State: 'open',
                        IsDraft: false,
                        ReviewDecision: 'APPROVED',
                        ChecksStatus: 'Passing',
                        HtmlURL: 'https://github.com/MemberJunction/MJ/pull/499',
                        Status: 'Open',
                    },
                    {
                        ID: PR_TASK_5,
                        RepositoryID: REPO_MJ_ID,
                        Number: 498,
                        Name: 'feat: already merged PR',
                        AuthorLogin: 'grace',
                        State: 'merged',
                        IsDraft: false,
                        ReviewDecision: 'APPROVED',
                        ChecksStatus: 'Passing',
                        HtmlURL: 'https://github.com/MemberJunction/MJ/pull/498',
                        Status: 'Completed',
                    },
                    {
                        ID: PR_TASK_6,
                        RepositoryID: REPO_MJ_ID,
                        Number: 503,
                        Name: 'feat: alice primary task',
                        AuthorLogin: 'AliceDev',
                        State: 'open',
                        IsDraft: false,
                        ReviewDecision: null,
                        ChecksStatus: 'Pending',
                        HtmlURL: 'https://github.com/MemberJunction/MJ/pull/503',
                        Status: 'InProgress',
                    },
                ],
            });

            const action = new GetGitHubReviewsWaitingOnMeAction();
            const runParams = makeRunParams();
            const res = await action.Run(runParams);

            expect(res.Success).toBe(true);
            expect(res.ResultCode).toBe('SUCCESS');
            const outJson = getOutputParam(runParams, 'ReviewsJSON') as string;
            expect(outJson).toBe(res.Message);

            const payload = JSON.parse(outJson) as ReviewsActionPayload;
            expect(payload.TotalWaiting).toBe(3);
            expect(payload.StaleCount).toBe(2);
            expect(payload.Reviews.map((r) => r.PRNumber)).toEqual([501, 310, 502]);
            expect(payload.Reviews[0]).toMatchObject({
                TaskID: PR_TASK_1,
                PRNumber: 501,
                Title: 'feat: oldest waiting review',
                Author: 'carol',
                Repository: 'MemberJunction/MJ',
                URL: 'https://github.com/MemberJunction/MJ/pull/501',
                IsStale: true,
            });
            expect(payload.Reviews[0].WaitingHours).toBeGreaterThanOrEqual(47.5);
            expect(payload.Reviews[1].IsStale).toBe(true);
            expect(payload.Reviews[2].IsStale).toBe(false);

            // MinAgeHours = 24 filters down to strictly stale items
            const staleOnlyRes = await action.Run(makeRunParams([{ Name: 'MinAgeHours', Value: 24 }]));
            const stalePayload = JSON.parse(staleOnlyRes.Message!) as ReviewsActionPayload;
            expect(stalePayload.TotalWaiting).toBe(2);
            expect(stalePayload.StaleCount).toBe(2);
            expect(stalePayload.Reviews.map((r) => r.PRNumber)).toEqual([501, 310]);

            // RepositoryName full name filter
            const repoRes = await action.Run(
                makeRunParams([{ Name: 'RepositoryName', Value: 'MemberJunction/bizapps-tasks' }]),
            );
            const repoPayload = JSON.parse(repoRes.Message!) as ReviewsActionPayload;
            expect(repoPayload.Reviews.map((r) => r.PRNumber)).toEqual([310]);

            // Limit preserves full TotalWaiting and StaleCount counts
            const limitedRes = await action.Run(makeRunParams([{ Name: 'Limit', Value: 1 }]));
            const limitedPayload = JSON.parse(limitedRes.Message!) as ReviewsActionPayload;
            expect(limitedPayload.TotalWaiting).toBe(3);
            expect(limitedPayload.StaleCount).toBe(2);
            expect(limitedPayload.ReturnedCount).toBe(1);
            expect(limitedPayload.Reviews).toHaveLength(1);
        });

        it('enforces TypedActionPolicyGuard denial and returns NO_PERSON_RECORD when unlinked', async () => {
            const action = new GetGitHubReviewsWaitingOnMeAction();

            installMockRunView({ people: [] });
            const unlinkedRes = await action.Run(makeRunParams());
            expect(unlinkedRes.Success).toBe(false);
            expect(unlinkedRes.ResultCode).toBe('NO_PERSON_RECORD');

            vi.spyOn(TypedActionPolicyGuard, 'CheckEntityAccess').mockResolvedValue({
                Allowed: false,
                Active: true,
                DeniedFieldPatterns: [],
                ResultCode: 'POLICY_DENIED',
                Message: 'EntityAccessRules denies Git Hub Pull Request Tasks.',
            });
            const deniedRes = await action.Run(makeRunParams([], makeUser(), 'agent-cos-1'));
            expect(deniedRes.Success).toBe(false);
            expect(deniedRes.ResultCode).toBe('POLICY_DENIED');
        });
    });

    describe('GetMyGitHubBriefingAction', () => {
        it('aggregates open PRs, waiting/stale reviews, blocked/failing GitHub tasks, and respects HorizonDays', async () => {
            const now = Date.now();
            installMockRunView({
                ...defaultPeopleAndIdentities(),
                assignments: [
                    {
                        ID: 'b-rev-1',
                        TaskID: PR_TASK_3,
                        AssigneeRecordID: PERSON_ALICE_ID,
                        RoleID: ROLE_REVIEWER_ID,
                        Role: 'Reviewer',
                        Status: 'Pending',
                        AssignedAt: new Date(now - 36 * HOUR_MS),
                    },
                    {
                        ID: 'b-pri-issue-1',
                        TaskID: ISSUE_TASK_1,
                        AssigneeRecordID: PERSON_ALICE_ID,
                        RoleID: ROLE_PRIMARY_ID,
                        Role: 'Primary',
                        Status: 'InProgress',
                        AssignedAt: new Date(now - 12 * HOUR_MS),
                    },
                    {
                        ID: 'b-pri-issue-2',
                        TaskID: ISSUE_TASK_2,
                        AssigneeRecordID: PERSON_ALICE_ID,
                        RoleID: ROLE_PRIMARY_ID,
                        Role: 'Primary',
                        Status: 'Pending',
                        AssignedAt: new Date(now - 2 * HOUR_MS),
                    },
                ],
                prs: [
                    // Caller's open PR with failing CI and due in 2 days
                    {
                        ID: PR_TASK_1,
                        RepositoryID: REPO_MJ_ID,
                        Number: 610,
                        Name: 'feat: failing CI PR',
                        AuthorLogin: 'AliceDev',
                        State: 'open',
                        IsDraft: false,
                        ReviewDecision: 'CHANGES_REQUESTED',
                        ChecksStatus: 'Failing',
                        HtmlURL: 'https://github.com/MemberJunction/MJ/pull/610',
                        Status: 'InProgress',
                        Priority: 'High',
                        DueAt: new Date(now + 2 * DAY_MS),
                        GitHubUpdatedAt: new Date(now - 3 * HOUR_MS),
                        __mj_CreatedAt: new Date(now - 15 * HOUR_MS),
                    },
                    // Caller's clean open draft PR
                    {
                        ID: PR_TASK_2,
                        RepositoryID: REPO_TASKS_ID,
                        Number: 611,
                        Name: 'wip: healthy draft PR',
                        AuthorLogin: 'AliceDev',
                        State: 'open',
                        IsDraft: true,
                        ReviewDecision: null,
                        ChecksStatus: 'Passing',
                        HtmlURL: 'https://github.com/MemberJunction/bizapps-tasks/pull/611',
                        Status: 'Open',
                        Priority: 'Medium',
                        GitHubUpdatedAt: new Date(now - 1 * HOUR_MS),
                        __mj_CreatedAt: new Date(now - 4 * HOUR_MS),
                    },
                    // Stale review waiting on caller
                    {
                        ID: PR_TASK_3,
                        RepositoryID: REPO_MJ_ID,
                        Number: 612,
                        Name: 'fix: needs alice review urgently',
                        AuthorLogin: 'bobdev',
                        State: 'open',
                        IsDraft: false,
                        ReviewDecision: 'REVIEW_REQUIRED',
                        ChecksStatus: 'Passing',
                        HtmlURL: 'https://github.com/MemberJunction/MJ/pull/612',
                        Status: 'Open',
                        Priority: 'High',
                        GitHubUpdatedAt: new Date(now - 36 * HOUR_MS),
                        __mj_CreatedAt: new Date(now - 40 * HOUR_MS),
                    },
                ],
                issues: [
                    // Blocked GitHub issue due in 1 day
                    {
                        ID: ISSUE_TASK_1,
                        RepositoryID: REPO_MJ_ID,
                        Number: 9001,
                        Name: 'Investigate OAuth token refresh timeout',
                        AuthorLogin: 'carol',
                        State: 'open',
                        HtmlURL: 'https://github.com/MemberJunction/MJ/issues/9001',
                        Status: 'Blocked',
                        Priority: 'Critical',
                        BlockedReason: 'Waiting on IdP sandbox credentials',
                        MilestoneDueAt: new Date(now + 1 * DAY_MS),
                        GitHubUpdatedAt: new Date(now - 5 * HOUR_MS),
                    },
                    // Non-blocked issue due in 10 days (excluded at HorizonDays=3, included at HorizonDays=14)
                    {
                        ID: ISSUE_TASK_2,
                        RepositoryID: REPO_TASKS_ID,
                        Number: 9002,
                        Name: 'Polish GitHub webhook retry metrics',
                        AuthorLogin: 'AliceDev',
                        State: 'open',
                        HtmlURL: 'https://github.com/MemberJunction/bizapps-tasks/issues/9002',
                        Status: 'Open',
                        Priority: 'Medium',
                        DueAt: new Date(now + 10 * DAY_MS),
                        GitHubUpdatedAt: new Date(now - 2 * HOUR_MS),
                    },
                ],
            });

            const action = new GetMyGitHubBriefingAction();

            // 1. Short 3-day horizon
            const shortParams = makeRunParams([{ Name: 'HorizonDays', Value: 3 }]);
            const shortRes = await action.Run(shortParams);
            expect(shortRes.Success).toBe(true);
            expect(shortRes.ResultCode).toBe('SUCCESS');

            const outJson = getOutputParam(shortParams, 'BriefingJSON') as string;
            expect(outJson).toBe(shortRes.Message);

            const shortBrief = JSON.parse(outJson) as BriefingActionPayload;
            expect(shortBrief.HorizonDays).toBe(3);
            expect(shortBrief.Counts).toMatchObject({
                OpenPRs: 2,
                DraftPRs: 1,
                FailingCIPRs: 1,
                ChangesRequestedPRs: 1,
                ReviewsWaiting: 1,
                StaleReviews: 1,
                BlockedOrFailingTasks: 2,
                UpcomingDeadlines: 2, // Issue #9001 (1d) + PR #610 (2d); Issue #9002 (10d) outside 3d horizon
            });
            expect(shortBrief.OpenPRs[0].PRNumber).toBe(610); // Failing CI prioritized first
            expect(shortBrief.ReviewsWaitingOnMe[0].IsStale).toBe(true);
            expect(shortBrief.BlockedOrFailingTasks.map((t) => t.Number)).toEqual([610, 9001]);
            expect(shortBrief.UpcomingDeadlines.map((d) => d.Number)).toEqual([9001, 610]);
            expect(shortBrief.Summary).toContain('2 open PR(s)');
            expect(shortBrief.Summary).toContain('1 stale >24h');

            // 2. Wider 14-day horizon includes Issue #9002 (due in 10d)
            const wideRes = await action.Run(makeRunParams([{ Name: 'HorizonDays', Value: 14 }]));
            const wideBrief = JSON.parse(wideRes.Message!) as BriefingActionPayload;
            expect(wideBrief.Counts.UpcomingDeadlines).toBe(3);
            expect(wideBrief.UpcomingDeadlines.map((d) => d.Number)).toEqual([9001, 610, 9002]);
        });

        it('handles empty state cleanly and enforces TypedActionPolicyGuard denial / deferral', async () => {
            installMockRunView({
                ...defaultPeopleAndIdentities(),
                assignments: [],
                prs: [],
                issues: [],
            });

            const action = new GetMyGitHubBriefingAction();
            const emptyParams = makeRunParams();
            const emptyRes = await action.Run(emptyParams);
            expect(emptyRes.Success).toBe(true);
            expect(emptyRes.ResultCode).toBe('SUCCESS');

            const emptyBrief = JSON.parse(emptyRes.Message!) as BriefingActionPayload;
            expect(emptyBrief.HorizonDays).toBe(7);
            expect(emptyBrief.Counts).toMatchObject({
                OpenPRs: 0,
                ReviewsWaiting: 0,
                StaleReviews: 0,
                BlockedOrFailingTasks: 0,
                UpcomingDeadlines: 0,
            });
            expect(emptyBrief.OpenPRs).toEqual([]);
            expect(emptyBrief.ReviewsWaitingOnMe).toEqual([]);
            expect(emptyBrief.BlockedOrFailingTasks).toEqual([]);

            // Invalid HorizonDays rejected
            const badHorizonRes = await action.Run(makeRunParams([{ Name: 'HorizonDays', Value: 0 }]));
            expect(badHorizonRes.Success).toBe(false);
            expect(badHorizonRes.ResultCode).toBe('INVALID_PARAMS');

            // Policy deferral enforced
            vi.spyOn(TypedActionPolicyGuard, 'CheckEntityAccess').mockResolvedValue({
                Allowed: false,
                Active: true,
                DeniedFieldPatterns: [],
                ResultCode: 'POLICY_DEFERRED',
                Message: 'Outside user quiet-hours time window.',
            });
            const deferredRes = await action.Run(makeRunParams([], makeUser(), 'agent-cos-1'));
            expect(deferredRes.Success).toBe(false);
            expect(deferredRes.ResultCode).toBe('POLICY_DEFERRED');
        });
    });

    describe('Chief of Staff Extensible Skills Metadata Contract', () => {
        interface SyncActionRecord {
            fields: {
                Name: string;
                DriverClass: string;
                Status: string;
            };
            primaryKey: { ID: string };
            relatedEntities: {
                'MJ: Action Params': Array<{
                    fields: { Name: string; Type: string };
                    primaryKey: { ID: string };
                }>;
                'MJ: Action Result Codes': Array<{
                    fields: { ResultCode: string; IsSuccess: boolean };
                    primaryKey: { ID: string };
                }>;
            };
        }

        interface SyncSkillRecord {
            fields: {
                Name: string;
                Instructions: string;
                Status: string;
                ActivationMode: string;
            };
            primaryKey: { ID: string };
            relatedEntities: {
                'MJ: AI Agent Skills': Array<{
                    fields: {
                        AgentID: string;
                        SkillID: string;
                        Status: string;
                        AllowMetadataSyncUpdate?: boolean;
                    };
                    primaryKey: { ID: string };
                }>;
                'MJ: AI Skill Actions': Array<{
                    fields: {
                        SkillID: string;
                        ActionID: string;
                        Role?: string;
                        ExposeToModel?: boolean;
                    };
                    primaryKey: { ID: string };
                }>;
            };
        }

        interface SyncRhythmTemplateRecord {
            fields: {
                AgentID: string;
                SkillID: string;
                Name: string;
                WorkstreamKey: string;
                DefaultCronExpression: string;
                DefaultWakeGate: string;
                WakeReason: string;
                OfferAt: string;
                Status: string;
            };
            primaryKey: { ID: string };
        }

        it('declares all 3 CoS actions with canonical result codes and unique valid UUIDs', () => {
            const actionsPath = path.join(REPO_ROOT, 'metadata/actions/.tasks-github-actions.json');
            const actions = JSON.parse(fs.readFileSync(actionsPath, 'utf8')) as SyncActionRecord[];

            const canonicalCodes = [
                'SUCCESS',
                'FAILED',
                'INVALID_PARAMS',
                'NOT_FOUND',
                'NO_PERSON_RECORD',
                'POLICY_DENIED',
                'POLICY_DEFERRED',
            ];

            const expectedActions: Array<{ name: string; driverClass: string; outputParam: string }> = [
                {
                    name: 'Get My GitHub PRs',
                    driverClass: 'GetMyGitHubPRsAction',
                    outputParam: 'PullRequestsJSON',
                },
                {
                    name: 'Get GitHub Reviews Waiting On Me',
                    driverClass: 'GetGitHubReviewsWaitingOnMeAction',
                    outputParam: 'ReviewsJSON',
                },
                {
                    name: 'Get My GitHub Briefing',
                    driverClass: 'GetMyGitHubBriefingAction',
                    outputParam: 'BriefingJSON',
                },
            ];

            const allIds = new Set<string>();
            for (const act of actions) {
                expect(IsValidUUID(act.primaryKey.ID)).toBe(true);
                expect(allIds.has(act.primaryKey.ID)).toBe(false);
                allIds.add(act.primaryKey.ID);
                for (const p of act.relatedEntities['MJ: Action Params']) {
                    expect(IsValidUUID(p.primaryKey.ID)).toBe(true);
                    expect(allIds.has(p.primaryKey.ID)).toBe(false);
                    allIds.add(p.primaryKey.ID);
                }
                for (const rc of act.relatedEntities['MJ: Action Result Codes']) {
                    expect(IsValidUUID(rc.primaryKey.ID)).toBe(true);
                    expect(allIds.has(rc.primaryKey.ID)).toBe(false);
                    allIds.add(rc.primaryKey.ID);
                }
            }

            for (const expected of expectedActions) {
                const found = actions.find((a) => a.fields.Name === expected.name);
                expect(found, `Missing action metadata '${expected.name}'`).toBeDefined();
                expect(found!.fields.DriverClass).toBe(expected.driverClass);
                expect(found!.fields.Status).toBe('Active');

                const outputNames = found!.relatedEntities['MJ: Action Params']
                    .filter((p) => p.fields.Type === 'Output')
                    .map((p) => p.fields.Name);
                expect(outputNames).toContain(expected.outputParam);

                const resultCodes = found!.relatedEntities['MJ: Action Result Codes'].map(
                    (rc) => rc.fields.ResultCode,
                );
                for (const code of canonicalCodes) {
                    expect(resultCodes).toContain(code);
                }
            }
        });

        it('grants GitHub skill to Chief of Staff in metadata/chief-of-staff-skills with AllowMetadataSyncUpdate, Role=Briefing/ExposeToModel=false, zero sync blocks, and non-exposed operator actions', () => {
            const appManifest = JSON.parse(
                fs.readFileSync(path.join(REPO_ROOT, 'mj-app.json'), 'utf8'),
            ) as { metadata?: { directory?: string } };
            expect(appManifest.metadata?.directory).toBe('metadata');

            const skillDirSync = JSON.parse(
                fs.readFileSync(path.join(REPO_ROOT, 'metadata/chief-of-staff-skills/.mj-sync.json'), 'utf8'),
            ) as { entity: string };
            expect(skillDirSync.entity).toBe('MJ: AI Skills');

            const skillPath = path.join(REPO_ROOT, 'metadata/chief-of-staff-skills/.github-tasks-skill.json');
            const rawSkillJson = fs.readFileSync(skillPath, 'utf8');
            expect(rawSkillJson).not.toContain('"sync"');
            const skills = JSON.parse(rawSkillJson) as SyncSkillRecord[];
            expect(skills).toHaveLength(1);

            const skill = skills[0];
            expect(IsValidUUID(skill.primaryKey.ID)).toBe(true);
            expect(skill.primaryKey.ID).toBe('85258800-163B-4409-BA2F-2F3B8AF556C0');
            expect(skill.fields.Name).toBe('GitHub Tasks & Pull Requests');
            expect(skill.fields.Status).toBe('Active');

            const cosGrant = skill.relatedEntities['MJ: AI Agent Skills'].find(
                (g) => g.fields.AgentID === '@lookup:MJ: AI Agents.Name=Chief of Staff',
            );
            expect(cosGrant).toBeDefined();
            expect(IsValidUUID(cosGrant!.primaryKey.ID)).toBe(true);
            expect(cosGrant!.fields.Status).toBe('Active');
            expect(cosGrant!.fields.AllowMetadataSyncUpdate).toBe(true);

            // Personal Chief of Staff instances (e.g. BaseAgentID = Chief of Staff) inherit active template skills
            const resolveInheritedSkills = (
                templateGrants: Array<{ agentLookup: string; skillId: string; status: string }>,
                personalInstance: { BaseAgentLookup: string },
            ): string[] =>
                templateGrants
                    .filter((g) => g.status === 'Active' && g.agentLookup === personalInstance.BaseAgentLookup)
                    .map((g) => g.skillId);

            const inherited = resolveInheritedSkills(
                skill.relatedEntities['MJ: AI Agent Skills'].map((g) => ({
                    agentLookup: g.fields.AgentID,
                    skillId: skill.primaryKey.ID,
                    status: g.fields.Status,
                })),
                { BaseAgentLookup: '@lookup:MJ: AI Agents.Name=Chief of Staff' },
            );
            expect(inherited).toContain(skill.primaryKey.ID);

            const bindings = skill.relatedEntities['MJ: AI Skill Actions'];
            const findBinding = (actionName: string) =>
                bindings.find((b) => b.fields.ActionID === `@lookup:MJ: Actions.Name=${actionName}`);

            expect(findBinding('Get My GitHub PRs')?.fields).toMatchObject({
                Role: 'Tool',
                ExposeToModel: true,
            });
            expect(findBinding('Get GitHub Reviews Waiting On Me')?.fields).toMatchObject({
                Role: 'Tool',
                ExposeToModel: true,
            });
            expect(findBinding('Get My GitHub Briefing')?.fields).toMatchObject({
                Role: 'Briefing',
                ExposeToModel: false,
            });
            // Operator actions kept out of default CoS model exposure
            expect(findBinding('Sync GitHub Repository Tasks')?.fields.ExposeToModel).toBe(false);
            expect(findBinding('Infer GitHub Task Planning Fields')?.fields.ExposeToModel).toBe(false);

            const templatePath = path.join(REPO_ROOT, 'metadata/chief-of-staff-skills/templates/github-tasks.skill.md');
            const templateContent = fs.readFileSync(templatePath, 'utf8');
            expect(templateContent).toContain('Get My GitHub PRs');
            expect(templateContent).toContain('Get GitHub Reviews Waiting On Me');
            expect(templateContent).toContain('Get My GitHub Briefing');
            expect(templateContent).toContain('PRs Waiting On You');

            // Verify bound CoS actions contain zero raw SQL execution
            const actionsSource = fs.readFileSync(
                path.join(REPO_ROOT, 'packages/Actions/src/GitHubCoSActions.ts'),
                'utf8',
            );
            expect(actionsSource).not.toMatch(/\bExecuteSQL\b|\bsql\.query\b|\brequest\.query\b/);
        });

        it('enforces two-user RLS isolation so User A and User B receive strictly different PRs and review queues from the same skill', async () => {
            const USER_BOB_ID = '10000000-0000-4000-8000-000000000002';
            const userAlice = makeUser(USER_ALICE_ID, 'alice@example.com');
            const userBob = makeUser(USER_BOB_ID, 'bob@example.com');
            userBob.Name = 'Bob Reviewer';

            const allPeople: MockPersonRow[] = [
                {
                    ID: PERSON_ALICE_ID,
                    FirstName: 'Alice',
                    LastName: 'Developer',
                    DisplayName: 'Alice Developer',
                    Email: 'alice@example.com',
                    LinkedUserID: USER_ALICE_ID,
                    Status: 'Active',
                },
                {
                    ID: PERSON_BOB_ID,
                    FirstName: 'Bob',
                    LastName: 'Reviewer',
                    DisplayName: 'Bob Reviewer',
                    Email: 'bob@example.com',
                    LinkedUserID: USER_BOB_ID,
                    Status: 'Active',
                },
            ];

            const allIdentities: Partial<mjBizAppsTasksGitHubGitHubIdentityEntity>[] = [
                { ID: '70000000-0000-4000-8000-000000000001', GitHubLogin: 'AliceDev', PersonID: PERSON_ALICE_ID, IsActive: true },
                { ID: '70000000-0000-4000-8000-000000000002', GitHubLogin: 'BobRev', PersonID: PERSON_BOB_ID, IsActive: true },
            ];

            const now = Date.now();
            // Simulate tenant/repo RLS: Alice can only access REPO_MJ_ID; Bob can only access REPO_TASKS_ID
            const allowedRepoByUser = new Map<string, Set<string>>([
                [USER_ALICE_ID, new Set([REPO_MJ_ID])],
                [USER_BOB_ID, new Set([REPO_TASKS_ID])],
            ]);

            const allPrs: Partial<mjBizAppsTasksGitHubGitHubPullRequestTaskEntity>[] = [
                {
                    ID: PR_TASK_1,
                    Name: 'Alice secret MJ PR',
                    RepositoryID: REPO_MJ_ID,
                    Repository: 'MJ',
                    Number: 101,
                    State: 'open',
                    IsDraft: false,
                    AuthorLogin: 'AliceDev',
                    ChecksStatus: 'Passing',
                    ReviewDecision: 'APPROVED',
                    Status: 'InProgress',
                    Priority: 'High',
                    HtmlURL: 'https://github.com/MemberJunction/MJ/pull/101',
                    GitHubUpdatedAt: new Date(now - 2 * HOUR_MS),
                    __mj_CreatedAt: new Date(now - 36 * HOUR_MS),
                },
                {
                    ID: PR_TASK_2,
                    Name: 'Bob confidential Tasks PR',
                    RepositoryID: REPO_TASKS_ID,
                    Repository: 'bizapps-tasks',
                    Number: 202,
                    State: 'open',
                    IsDraft: false,
                    AuthorLogin: 'BobRev',
                    ChecksStatus: 'Failing',
                    ReviewDecision: 'CHANGES_REQUESTED',
                    Status: 'Blocked',
                    Priority: 'Critical',
                    HtmlURL: 'https://github.com/MemberJunction/bizapps-tasks/pull/202',
                    GitHubUpdatedAt: new Date(now - 1 * HOUR_MS),
                    __mj_CreatedAt: new Date(now - 48 * HOUR_MS),
                },
            ];

            const allAssignments: Partial<mjBizAppsTasksTaskAssignmentEntity>[] = [
                {
                    ID: '80000000-0000-4000-8000-000000000001',
                    TaskID: PR_TASK_1,
                    AssigneeRecordID: PERSON_ALICE_ID,
                    RoleID: ROLE_PRIMARY_ID,
                    Role: 'Primary',
                    Status: 'InProgress',
                    AssignedAt: new Date(now - 5 * HOUR_MS),
                },
                {
                    ID: '80000000-0000-4000-8000-000000000002',
                    TaskID: PR_TASK_2,
                    AssigneeRecordID: PERSON_BOB_ID,
                    RoleID: ROLE_PRIMARY_ID,
                    Role: 'Primary',
                    Status: 'InProgress',
                    AssignedAt: new Date(now - 5 * HOUR_MS),
                },
            ];

            const resolveRlsRows = (req: RunViewParams, caller?: UserInfo): RunViewResult => {
                const callerId = caller?.ID ?? '';
                const allowedRepos = allowedRepoByUser.get(callerId) ?? new Set<string>();
                switch (req.EntityName) {
                    case PEOPLE_ENTITY:
                        return makeSuccessViewResult(allPeople.filter((p) => p.LinkedUserID === callerId));
                    case GITHUB_IDENTITIES_ENTITY:
                        return makeSuccessViewResult(allIdentities);
                    case TASK_ROLES_ENTITY:
                        return makeSuccessViewResult([
                            { ID: ROLE_PRIMARY_ID, Name: 'Primary' },
                            { ID: ROLE_REVIEWER_ID, Name: 'Reviewer' },
                        ]);
                    case TASK_ASSIGNMENTS_ENTITY:
                        return makeSuccessViewResult(
                            allAssignments.filter((a) => {
                                const pr = allPrs.find((p) => p.ID === a.TaskID);
                                return pr?.RepositoryID != null && allowedRepos.has(pr.RepositoryID);
                            }),
                        );
                    case GITHUB_REPOSITORIES_ENTITY:
                        return makeSuccessViewResult([
                            { ID: REPO_MJ_ID, Owner: 'MemberJunction', Name: 'MJ' },
                            { ID: REPO_TASKS_ID, Owner: 'MemberJunction', Name: 'bizapps-tasks' },
                        ]);
                    case GITHUB_PR_TASKS_ENTITY:
                        return makeSuccessViewResult(
                            allPrs.filter((pr) => pr.RepositoryID != null && allowedRepos.has(pr.RepositoryID)),
                        );
                    default:
                        return makeSuccessViewResult([]);
                }
            };

            vi.spyOn(RunView.prototype, 'RunView').mockImplementation((async (req: RunViewParams, caller?: UserInfo) =>
                resolveRlsRows(req, caller)) as RunView['RunView']);
            vi.spyOn(RunView.prototype, 'RunViews').mockImplementation((async (reqs: RunViewParams[], caller?: UserInfo) =>
                reqs.map((r) => resolveRlsRows(r, caller))) as RunView['RunViews']);

            const prsAction = new GetMyGitHubPRsAction();

            const aliceParams = makeRunParams([], userAlice);
            const aliceRes = await prsAction.Run(aliceParams);
            expect(aliceRes.Success).toBe(true);
            const alicePayload = JSON.parse(String(getOutputParam(aliceParams, 'PullRequestsJSON'))) as PRsActionPayload;
            expect(alicePayload.PersonID).toBe(PERSON_ALICE_ID);
            expect(alicePayload.PullRequests.map((p) => p.PRNumber)).toEqual([101]);
            expect(alicePayload.PullRequests.map((p) => p.Title)).not.toContain('Bob confidential Tasks PR');

            const bobParams = makeRunParams([], userBob);
            const bobRes = await prsAction.Run(bobParams);
            expect(bobRes.Success).toBe(true);
            const bobPayload = JSON.parse(String(getOutputParam(bobParams, 'PullRequestsJSON'))) as PRsActionPayload;
            expect(bobPayload.PersonID).toBe(PERSON_BOB_ID);
            expect(bobPayload.PullRequests.map((p) => p.PRNumber)).toEqual([202]);
            expect(bobPayload.PullRequests.map((p) => p.Title)).not.toContain('Alice secret MJ PR');
        });

        it('registers the PRs Waiting On You rhythm template in metadata and cleans it up in both teardown scripts', () => {
            const rootSync = JSON.parse(
                fs.readFileSync(path.join(REPO_ROOT, 'metadata/.mj-sync.json'), 'utf8'),
            ) as { directoryOrder: string[] };
            expect(rootSync.directoryOrder).toContain('rhythm-templates');
            expect(rootSync.directoryOrder.indexOf('rhythm-templates')).toBeGreaterThan(
                rootSync.directoryOrder.indexOf('chief-of-staff-skills'),
            );

            const rhythmSync = JSON.parse(
                fs.readFileSync(path.join(REPO_ROOT, 'metadata/rhythm-templates/.mj-sync.json'), 'utf8'),
            ) as { entity: string };
            expect(rhythmSync.entity).toBe('MJ: AI Agent Rhythm Templates');

            const rhythms = JSON.parse(
                fs.readFileSync(
                    path.join(REPO_ROOT, 'metadata/rhythm-templates/.github-rhythm-templates.json'),
                    'utf8',
                ),
            ) as SyncRhythmTemplateRecord[];
            expect(rhythms).toHaveLength(1);

            const prQueue = rhythms[0];
            expect(IsValidUUID(prQueue.primaryKey.ID)).toBe(true);
            expect(prQueue.fields).toMatchObject({
                AgentID: '@lookup:MJ: AI Agents.Name=Chief of Staff',
                // By the skill's fixed primaryKey, as the metadata writes it: a rename cannot break the link.
                SkillID: '@lookup:MJ: AI Skills.ID=85258800-163B-4409-BA2F-2F3B8AF556C0',
                Name: 'PRs Waiting On You',
                WorkstreamKey: 'github-review-queue',
                DefaultCronExpression: '45 8 * * 1-5',
                OfferAt: 'Both',
                Status: 'Active',
            });
            expect(prQueue.fields.WakeReason.length).toBeGreaterThan(20);
            expect(() => JSON.parse(prQueue.fields.DefaultWakeGate)).not.toThrow();

            const mssqlTeardown = fs.readFileSync(
                path.join(REPO_ROOT, 'teardown/V1__Remove_GitHub_Tasks_Extension.sql'),
                'utf8',
            );
            const pgTeardown = fs.readFileSync(
                path.join(REPO_ROOT, 'teardown-pg/V1__Remove_GitHub_Tasks_Extension.pg.sql'),
                'utf8',
            );

            for (const script of [mssqlTeardown, pgTeardown]) {
                expect(script).toContain('github-review-queue');
                expect(script).toContain('AIAgentRhythmTemplate');
                expect(script).toContain('AIAgentSuggestion');
                expect(script).toContain('Get My GitHub PRs');
                expect(script).toContain('Get GitHub Reviews Waiting On Me');
                expect(script).toContain('Get My GitHub Briefing');
            }
        });
    });

    describe('Performance: GitHubTasksEngineBase caching & RunViews batching', () => {
        it('batches People lookups into a single RunViews call and reuses warm GitHubTasksEngineBase cache across CoS action invocations', async () => {
            const batchEntities: string[][] = [];
            const singleEntities: string[] = [];

            const resolveEntityRows = (req: RunViewParams): RunViewResult => {
                switch (req.EntityName) {
                    case PEOPLE_ENTITY:
                        return makeSuccessViewResult(defaultPeopleAndIdentities().people ?? []);
                    case GITHUB_IDENTITIES_ENTITY:
                        return makeSuccessViewResult(defaultPeopleAndIdentities().identities ?? []);
                    case TASK_ROLES_ENTITY:
                        return makeSuccessViewResult([
                            { ID: ROLE_PRIMARY_ID, Name: 'Primary' },
                            { ID: ROLE_REVIEWER_ID, Name: 'Reviewer' },
                        ]);
                    case TASK_ASSIGNMENTS_ENTITY:
                        return makeSuccessViewResult([]);
                    case GITHUB_REPOSITORIES_ENTITY:
                        return makeSuccessViewResult([
                            { ID: REPO_MJ_ID, Owner: 'MemberJunction', Name: 'MJ', IsTracked: true },
                        ]);
                    case GITHUB_PR_TASKS_ENTITY:
                    case GITHUB_ISSUE_TASKS_ENTITY:
                    default:
                        return makeSuccessViewResult([]);
                }
            };

            vi.spyOn(RunView.prototype, 'RunView').mockImplementation((async (req: RunViewParams) => {
                singleEntities.push(req.EntityName);
                return resolveEntityRows(req);
            }) as RunView['RunView']);
            vi.spyOn(RunView.prototype, 'RunViews').mockImplementation((async (reqs: RunViewParams[]) => {
                batchEntities.push(reqs.map((r) => r.EntityName));
                return reqs.map((r) => resolveEntityRows(r));
            }) as RunView['RunViews']);

            const prsAction = new GetMyGitHubPRsAction();
            const firstRes = await prsAction.Run(makeRunParams());
            expect(firstRes.Success).toBe(true);

            // People lookup ran via batched RunViews (never sequential RunView)
            expect(singleEntities.filter((e) => e === PEOPLE_ENTITY)).toHaveLength(0);
            expect(batchEntities.some((batch) => batch.every((e) => e === PEOPLE_ENTITY) && batch.length >= 2)).toBe(true);

            // Second invocation reuses warm GitHubTasksEngineBase cache -> zero repeat repo/identity queries!
            batchEntities.length = 0;
            singleEntities.length = 0;

            const briefingAction = new GetMyGitHubBriefingAction();
            const secondRes = await briefingAction.Run(makeRunParams());
            expect(secondRes.Success).toBe(true);

            const allQueriedOnSecond = [...singleEntities, ...batchEntities.flat()];
            expect(allQueriedOnSecond).not.toContain(GITHUB_REPOSITORIES_ENTITY);
            expect(allQueriedOnSecond).not.toContain(GITHUB_IDENTITIES_ENTITY);
        });
    });
});
