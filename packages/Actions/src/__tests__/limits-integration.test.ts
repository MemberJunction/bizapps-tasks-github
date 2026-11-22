import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import type { ActionParam, RunActionParams } from '@memberjunction/actions-base';
import { LimitsConfigResolver, RunView, type RunViewParams, type RunViewResult, type UserInfo } from '@memberjunction/core';
import {
    GITHUB_IDENTITIES_ENTITY,
    GITHUB_ISSUE_TASKS_ENTITY,
    GITHUB_PR_TASKS_ENTITY,
    GITHUB_REPOSITORIES_ENTITY,
    GitHubTasksLimitsResolver,
    PEOPLE_ENTITY,
    TASK_ASSIGNMENTS_ENTITY,
    TASK_ROLES_ENTITY,
} from '@mj-biz-apps/tasks-github-core';
import {
    GetGitHubReviewsWaitingOnMeAction,
    GetMyGitHubBriefingAction,
    GetMyGitHubPRsAction,
} from '../index.js';

const USER_ID = '10000000-0000-4000-8000-000000000011';
const PERSON_ID = '20000000-0000-4000-8000-000000000011';
const ROLE_REVIEWER_ID = '30000000-0000-4000-8000-000000000012';
const REPO_ID = '40000000-0000-4000-8000-000000000011';

function makeUser(): UserInfo {
    return {
        ID: USER_ID,
        Name: 'CoS Tester',
        Email: 'cos-tester@example.com',
        IsActive: true,
    } as UserInfo;
}

function makeRunParams(inputParams: Array<{ Name: string; Value: ActionParam['Value'] }> = []): RunActionParams {
    return {
        Action: {} as RunActionParams['Action'],
        ContextUser: makeUser(),
        Filters: [],
        Params: inputParams.map((p) => ({
            Name: p.Name,
            Type: 'Input',
            Value: p.Value,
        })),
    };
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

describe('GitHubCoSActions limits integration', () => {
    beforeEach(() => {
        GitHubTasksLimitsResolver.Instance.ClearConfigLimits();
        LimitsConfigResolver.Instance.ClearMjConfigLimits();
    });

    afterEach(() => {
        vi.restoreAllMocks();
        GitHubTasksLimitsResolver.Instance.ClearConfigLimits();
        LimitsConfigResolver.Instance.ClearMjConfigLimits();
    });

    it('routes DefaultPRLimit, MaxPRLimit, StaleReviewThresholdHours, DefaultBriefingHorizonDays, MaxBriefingHorizonDays, DefaultBriefingLimit, MaxBriefingLimit, and Person lookup MaxRows through GitHubTasksLimitsResolver', async () => {
        const capturedMaxRows: Record<string, number[]> = {};
        const now = Date.now();
        const tenHoursAgo = new Date(now - 10 * 3_600_000).toISOString();

        const manyPrs = Array.from({ length: 15 }, (_, idx) => ({
            ID: `50000000-0000-4000-8000-${String(idx + 1).padStart(12, '0')}`,
            Number: idx + 1,
            Name: `PR #${idx + 1}`,
            RepositoryID: REPO_ID,
            Repository: 'MemberJunction/MJ',
            State: 'open',
            IsDraft: false,
            AuthorLogin: 'cos-tester',
            CreatedByPersonID: PERSON_ID,
            Status: 'InProgress',
            Priority: 'Normal',
            GitHubUpdatedAt: tenHoursAgo,
        }));

        const resolveView = (req: RunViewParams): RunViewResult => {
            if (req.MaxRows !== undefined) {
                capturedMaxRows[req.EntityName] = capturedMaxRows[req.EntityName] ?? [];
                capturedMaxRows[req.EntityName].push(req.MaxRows);
            }
            switch (req.EntityName) {
                case PEOPLE_ENTITY:
                    return makeSuccessViewResult([
                        {
                            ID: PERSON_ID,
                            FirstName: 'CoS',
                            LastName: 'Tester',
                            DisplayName: 'CoS Tester',
                            Email: 'cos-tester@example.com',
                            LinkedUserID: USER_ID,
                            Status: 'Active',
                        },
                    ]);
                case GITHUB_IDENTITIES_ENTITY:
                    return makeSuccessViewResult([
                        {
                            ID: '70000000-0000-4000-8000-000000000011',
                            GitHubLogin: 'cos-tester',
                            PersonID: PERSON_ID,
                            IsActive: true,
                        },
                    ]);
                case TASK_ROLES_ENTITY:
                    return makeSuccessViewResult([{ ID: ROLE_REVIEWER_ID, Name: 'Reviewer' }]);
                case TASK_ASSIGNMENTS_ENTITY:
                    return makeSuccessViewResult([
                        {
                            ID: '80000000-0000-4000-8000-000000000011',
                            TaskID: manyPrs[0].ID,
                            AssigneeRecordID: PERSON_ID,
                            RoleID: ROLE_REVIEWER_ID,
                            Role: 'Reviewer',
                            Status: 'Pending',
                            AssignedAt: tenHoursAgo,
                        },
                    ]);
                case GITHUB_REPOSITORIES_ENTITY:
                    return makeSuccessViewResult([{ ID: REPO_ID, Owner: 'MemberJunction', Name: 'MJ' }]);
                case GITHUB_PR_TASKS_ENTITY:
                    return makeSuccessViewResult(manyPrs);
                case GITHUB_ISSUE_TASKS_ENTITY:
                    return makeSuccessViewResult([]);
                default:
                    return makeSuccessViewResult([]);
            }
        };

        vi.spyOn(RunView.prototype, 'RunView').mockImplementation((async (req: RunViewParams) =>
            resolveView(req)) as RunView['RunView']);
        vi.spyOn(RunView.prototype, 'RunViews').mockImplementation((async (reqs: RunViewParams[]) =>
            reqs.map((r) => resolveView(r))) as RunView['RunViews']);

        GitHubTasksLimitsResolver.Instance.RegisterConfigLimits({
            CoS: {
                StaleReviewThresholdHours: 6,
                DefaultPRLimit: 4,
                MaxPRLimit: 8,
                DefaultBriefingHorizonDays: 3,
                MaxBriefingHorizonDays: 10,
                DefaultBriefingLimit: 2,
                MaxBriefingLimit: 5,
                PersonUserLookupMaxRows: 3,
                PersonEmailLookupMaxRows: 7,
            },
        });

        // 1. GetMyGitHubPRsAction uses DefaultPRLimit=4 and rejects Limit > MaxPRLimit=8
        const prsAction = new GetMyGitHubPRsAction();
        const prsDefaultRes = await prsAction.Run(makeRunParams());
        expect(prsDefaultRes.Success).toBe(true);
        const prsPayload = JSON.parse(prsDefaultRes.Message!) as { ReturnedCount: number };
        expect(prsPayload.ReturnedCount).toBe(4);
        expect(capturedMaxRows[PEOPLE_ENTITY]).toContain(3);

        const prsOverLimitRes = await prsAction.Run(makeRunParams([{ Name: 'Limit', Value: 9 }]));
        expect(prsOverLimitRes.Success).toBe(false);
        expect(prsOverLimitRes.ResultCode).toBe('INVALID_PARAMS');

        // 2. GetGitHubReviewsWaitingOnMeAction uses StaleReviewThresholdHours=6 (10h waiting -> stale)
        const reviewsAction = new GetGitHubReviewsWaitingOnMeAction();
        const reviewsRes = await reviewsAction.Run(makeRunParams());
        expect(reviewsRes.Success).toBe(true);
        const reviewsPayload = JSON.parse(reviewsRes.Message!) as {
            StaleThresholdHours: number;
            StaleCount: number;
        };
        expect(reviewsPayload.StaleThresholdHours).toBe(6);
        expect(reviewsPayload.StaleCount).toBe(1);

        // 3. GetMyGitHubBriefingAction uses DefaultBriefingHorizonDays=3, DefaultBriefingLimit=2, and rejects HorizonDays > 10 / Limit > 5
        const briefingAction = new GetMyGitHubBriefingAction();
        const briefingRes = await briefingAction.Run(makeRunParams());
        expect(briefingRes.Success).toBe(true);
        const briefingPayload = JSON.parse(briefingRes.Message!) as {
            HorizonDays: number;
            OpenPRs: Array<{ TaskID: string }>;
        };
        expect(briefingPayload.HorizonDays).toBe(3);
        expect(briefingPayload.OpenPRs).toHaveLength(2);

        const briefingOverHorizonRes = await briefingAction.Run(makeRunParams([{ Name: 'HorizonDays', Value: 11 }]));
        expect(briefingOverHorizonRes.Success).toBe(false);
        expect(briefingOverHorizonRes.ResultCode).toBe('INVALID_PARAMS');

        const briefingOverLimitRes = await briefingAction.Run(makeRunParams([{ Name: 'Limit', Value: 6 }]));
        expect(briefingOverLimitRes.Success).toBe(false);
        expect(briefingOverLimitRes.ResultCode).toBe('INVALID_PARAMS');
    });
});
