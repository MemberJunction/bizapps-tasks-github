import { BaseAction } from '@memberjunction/actions';
import { ActionParam, ActionResultSimple, RunActionParams } from '@memberjunction/actions-base';
import { TypedActionPolicyGuard } from '@memberjunction/ai-core-plus';
import { IMetadataProvider, LogError, Metadata, RunView, UserInfo } from '@memberjunction/core';
import {
    EscapeSQLString,
    IndexByUUID,
    IsValidUUID,
    NormalizeUUID,
    RegisterClass,
    UUIDsEqual,
} from '@memberjunction/global';
import type {
    mjBizAppsTasksTaskAssignmentEntity,
    mjBizAppsTasksTaskEntity,
    mjBizAppsTasksTaskRoleEntity,
} from '@mj-biz-apps/tasks-entities';
import type {
    mjBizAppsTasksGitHubGitHubIdentityEntity,
    mjBizAppsTasksGitHubGitHubIssueTaskEntity,
    mjBizAppsTasksGitHubGitHubPullRequestTaskEntity,
    mjBizAppsTasksGitHubGitHubRepositoryEntity,
} from '@mj-biz-apps/tasks-github-entities';
import {
    AssertValidUUID,
    GITHUB_IDENTITIES_ENTITY,
    GITHUB_ISSUE_TASKS_ENTITY,
    GITHUB_PR_TASKS_ENTITY,
    GITHUB_REPOSITORIES_ENTITY,
    PEOPLE_ENTITY,
    TASK_ASSIGNMENTS_ENTITY,
    TASK_ROLES_ENTITY,
    TASKS_ENTITY_NAME,
} from '@mj-biz-apps/tasks-github-core';

const MS_PER_HOUR = 3_600_000;
const MS_PER_DAY = 86_400_000;
const STALE_REVIEW_THRESHOLD_HOURS = 24;
const DEFAULT_PR_LIMIT = 25;
const MAX_PR_LIMIT = 100;
const DEFAULT_BRIEFING_HORIZON_DAYS = 7;
const MAX_BRIEFING_HORIZON_DAYS = 90;
const DEFAULT_BRIEFING_LIMIT = 10;
const MAX_BRIEFING_LIMIT = 50;

export type GitHubPRStateFilter = 'Open' | 'Draft' | 'Merged' | 'Closed' | 'All';
export type GitHubPRStateValue = mjBizAppsTasksGitHubGitHubPullRequestTaskEntity['State'];
export type GitHubPRReviewDecisionValue = mjBizAppsTasksGitHubGitHubPullRequestTaskEntity['ReviewDecision'];
export type GitHubPRChecksStatusValue = mjBizAppsTasksGitHubGitHubPullRequestTaskEntity['ChecksStatus'];
export type CoreTaskStatusValue = mjBizAppsTasksTaskEntity['Status'];
export type CoreTaskPriorityValue = mjBizAppsTasksTaskEntity['Priority'];
export type TaskAssignmentStatusValue = mjBizAppsTasksTaskAssignmentEntity['Status'];

export type MyGitHubPRRow = {
    TaskID: string;
    PRNumber: number | null;
    Title: string;
    Repository: string;
    State: GitHubPRStateValue;
    IsDraft: boolean;
    ReviewDecision: GitHubPRReviewDecisionValue;
    CIStatus: GitHubPRChecksStatusValue;
    URL: string | null;
    UpdatedAt: string | null;
    AgeHours: number;
    AuthorLogin: string | null;
    HeadBranch: string | null;
    BaseBranch: string | null;
    TaskStatus: CoreTaskStatusValue;
    Priority: CoreTaskPriorityValue;
    Involvement: 'Author' | 'Assignee' | 'Both';
};

export type GitHubReviewWaitingRow = {
    TaskID: string;
    PRNumber: number | null;
    Title: string;
    Author: string | null;
    Repository: string;
    URL: string | null;
    WaitingHours: number;
    IsStale: boolean;
    IsDraft: boolean;
    ReviewDecision: GitHubPRReviewDecisionValue;
    CIStatus: GitHubPRChecksStatusValue;
    AssignedAt: string | null;
    AssignmentStatus: TaskAssignmentStatusValue;
};

export type GitHubBlockedOrFailingRow = {
    TaskID: string;
    Kind: 'PullRequest' | 'Issue';
    Number: number | null;
    Title: string;
    Repository: string;
    URL: string | null;
    TaskStatus: CoreTaskStatusValue;
    Priority: CoreTaskPriorityValue;
    BlockedReason: string | null;
    CIStatus: GitHubPRChecksStatusValue;
    ReviewDecision: GitHubPRReviewDecisionValue;
    Flags: string;
    UpdatedAt: string | null;
};

export type GitHubUpcomingDeadlineRow = {
    TaskID: string;
    Kind: 'PullRequest' | 'Issue';
    Number: number | null;
    Title: string;
    Repository: string;
    URL: string | null;
    DueAt: string;
    IsOverdue: boolean;
    TaskStatus: CoreTaskStatusValue;
    Priority: CoreTaskPriorityValue;
};

interface PersonLookupRow {
    ID: string;
    FirstName?: string | null;
    LastName?: string | null;
    DisplayName?: string | null;
    Email?: string | null;
    LinkedUserID?: string | null;
    Status?: string | null;
}

interface RepositoryLookupRow {
    ID: string;
    Owner: string;
    Name: string;
}

interface CallerGitHubIdentity {
    PersonID: string;
    DisplayName: string;
    Email: string | null;
    GitHubLogins: string[];
    GitHubLoginsLower: Set<string>;
}

interface CombinedPolicyGuardOutcome {
    Allowed: boolean;
    DeniedFieldPatterns: string[];
    Failure?: ActionResultSimple;
}

interface CallerAssignmentContext {
    OwnedTaskIds: Set<string>;
    OwnedTaskRawIds: string[];
    PendingReviewsByTaskId: Map<string, mjBizAppsTasksTaskAssignmentEntity>;
    ReposById: ReturnType<typeof IndexByUUID<RepositoryLookupRow>>;
}

function getStringParam(params: ActionParam[], name: string, ...aliases: string[]): string | null {
    const targets = [name, ...aliases].map((n) => n.toLowerCase());
    for (const target of targets) {
        const match = params.find((p) => p.Name.toLowerCase() === target);
        if (match && match.Value != null) {
            const str = String(match.Value).trim();
            if (str.length > 0) {
                return str;
            }
        }
    }
    return null;
}

function parseOptionalIntParam(
    params: ActionParam[],
    name: string,
    defaultValue: number,
    min: number,
    max: number,
    ...aliases: string[]
): { value: number; error?: string } {
    const raw = getStringParam(params, name, ...aliases);
    if (raw === null) {
        return { value: defaultValue };
    }
    const parsed = Number(raw);
    if (!Number.isFinite(parsed) || !Number.isInteger(parsed) || parsed < min || parsed > max) {
        return {
            value: defaultValue,
            error: `Invalid ${name} '${raw}'; expected an integer between ${min} and ${max}.`,
        };
    }
    return { value: parsed };
}

function parseOptionalNonNegativeNumberParam(
    params: ActionParam[],
    name: string,
    defaultValue: number,
): { value: number; error?: string } {
    const raw = getStringParam(params, name);
    if (raw === null) {
        return { value: defaultValue };
    }
    const parsed = Number(raw);
    if (!Number.isFinite(parsed) || parsed < 0) {
        return {
            value: defaultValue,
            error: `Invalid ${name} '${raw}'; expected a non-negative number.`,
        };
    }
    return { value: parsed };
}

function parseOptionalBooleanParam(
    params: ActionParam[],
    name: string,
    defaultValue: boolean,
): { value: boolean; error?: string } {
    const match = params.find((p) => p.Name.toLowerCase() === name.toLowerCase());
    if (!match || match.Value == null) {
        return { value: defaultValue };
    }
    if (typeof match.Value === 'boolean') {
        return { value: match.Value };
    }
    const normalized = String(match.Value).trim().toLowerCase();
    if (normalized === '') {
        return { value: defaultValue };
    }
    if (normalized === 'true' || normalized === '1' || normalized === 'yes') {
        return { value: true };
    }
    if (normalized === 'false' || normalized === '0' || normalized === 'no') {
        return { value: false };
    }
    return {
        value: defaultValue,
        error: `Invalid ${name} '${String(match.Value)}'; expected a boolean ('true' or 'false').`,
    };
}

function parsePRStateFilter(raw: string | null): { value: GitHubPRStateFilter; error?: string } {
    if (raw === null) {
        return { value: 'Open' };
    }
    switch (raw.trim().toLowerCase()) {
        case 'open':
            return { value: 'Open' };
        case 'draft':
            return { value: 'Draft' };
        case 'merged':
            return { value: 'Merged' };
        case 'closed':
            return { value: 'Closed' };
        case 'all':
            return { value: 'All' };
        default:
            return {
                value: 'Open',
                error: `Invalid State '${raw}'; expected 'Open', 'Draft', 'Merged', 'Closed', or 'All'.`,
            };
    }
}

function setOutputParam(params: ActionParam[], name: string, value: string): void {
    const existing = params.find((p) => p.Name.toLowerCase() === name.toLowerCase() && p.Type === 'Output');
    if (existing) {
        existing.Value = value;
        return;
    }
    const anyExisting = params.find((p) => p.Name.toLowerCase() === name.toLowerCase());
    if (anyExisting) {
        anyExisting.Value = value;
        return;
    }
    params.push({
        Name: name,
        Type: 'Output',
        Value: value,
    });
}

function toDateOrNull(value: Date | string | null | undefined): Date | null {
    if (value == null) {
        return null;
    }
    const parsed = value instanceof Date ? value : new Date(value);
    return Number.isNaN(parsed.getTime()) ? null : parsed;
}

function toIsoOrNull(value: Date | string | null | undefined): string | null {
    const d = toDateOrNull(value);
    return d ? d.toISOString() : null;
}

function computeHoursSince(reference: Date | string | null | undefined, nowMs: number): number {
    const d = toDateOrNull(reference);
    if (!d) {
        return 0;
    }
    const diffHours = Math.max(0, (nowMs - d.getTime()) / MS_PER_HOUR);
    return Math.round(diffHours * 10) / 10;
}

function createRunView(provider: IMetadataProvider | undefined): RunView {
    return provider ? RunView.FromMetadataProvider(provider) : new RunView();
}

function formatPersonDisplayName(row: PersonLookupRow): string {
    if (row.DisplayName && row.DisplayName.trim().length > 0) {
        return row.DisplayName.trim();
    }
    const parts = [row.FirstName?.trim(), row.LastName?.trim()].filter((s): s is string => Boolean(s));
    return parts.length > 0 ? parts.join(' ') : row.Email?.trim() || row.ID;
}

function formatRepositoryName(
    repositoryId: string | null | undefined,
    fallbackRepository: string | null | undefined,
    reposById: ReturnType<typeof IndexByUUID<RepositoryLookupRow>>,
): string {
    if (repositoryId) {
        const repo = reposById.Get(repositoryId);
        if (repo) {
            return `${repo.Owner}/${repo.Name}`;
        }
    }
    const trimmedFallback = fallbackRepository?.trim();
    return trimmedFallback && trimmedFallback.length > 0 ? trimmedFallback : 'unknown';
}

function matchesRepositoryFilter(
    repositoryId: string | null | undefined,
    fallbackRepository: string | null | undefined,
    reposById: ReturnType<typeof IndexByUUID<RepositoryLookupRow>>,
    repoFilter: string | null,
): boolean {
    if (!repoFilter) {
        return true;
    }
    const needle = repoFilter.trim().toLowerCase();
    if (repositoryId) {
        const repo = reposById.Get(repositoryId);
        if (repo) {
            const fullName = `${repo.Owner}/${repo.Name}`.toLowerCase();
            if (repo.Name.toLowerCase() === needle || fullName === needle) {
                return true;
            }
        }
    }
    const fallback = (fallbackRepository ?? '').trim().toLowerCase();
    return fallback.length > 0 && fallback === needle;
}

function isReviewerAssignment(
    assignment: mjBizAppsTasksTaskAssignmentEntity,
    reviewerRoleId: string | null,
): boolean {
    if (assignment.Role && assignment.Role.trim().toLowerCase() === 'reviewer') {
        return true;
    }
    if (reviewerRoleId && assignment.RoleID && UUIDsEqual(assignment.RoleID, reviewerRoleId)) {
        return true;
    }
    return false;
}

async function checkGitHubCoSEntityAccess(
    params: RunActionParams,
    entityNames: readonly string[],
): Promise<CombinedPolicyGuardOutcome> {
    const deniedPatterns = new Set<string>();
    for (const entityName of entityNames) {
        const outcome = await TypedActionPolicyGuard.CheckEntityAccess({
            entityName,
            operation: 'Read',
            contextUser: params.ContextUser,
            actionContext: params.Context,
            provider: params.Provider,
        });
        if (!outcome.Allowed) {
            return {
                Allowed: false,
                DeniedFieldPatterns: [],
                Failure: {
                    Success: false,
                    ResultCode: outcome.ResultCode ?? 'POLICY_DENIED',
                    Message:
                        outcome.Message ??
                        `Read access to '${entityName}' was blocked by agent user policy.`,
                    Params: params.Params,
                },
            };
        }
        for (const pattern of outcome.DeniedFieldPatterns) {
            deniedPatterns.add(pattern);
        }
    }
    return {
        Allowed: true,
        DeniedFieldPatterns: Array.from(deniedPatterns),
    };
}

async function resolveCallerPerson(
    contextUser: UserInfo | undefined,
    rv: RunView,
    provider: IMetadataProvider | undefined,
): Promise<PersonLookupRow | null> {
    if (!contextUser?.ID) {
        return null;
    }

    const md: IMetadataProvider | undefined = provider ?? Metadata.Provider;
    const peopleEntityId =
        md && typeof md.EntityByName === 'function' ? md.EntityByName(PEOPLE_ENTITY)?.ID : undefined;

    if (
        contextUser.LinkedEntityID &&
        contextUser.LinkedEntityRecordID &&
        peopleEntityId &&
        UUIDsEqual(contextUser.LinkedEntityID, peopleEntityId) &&
        IsValidUUID(contextUser.LinkedEntityRecordID)
    ) {
        const linkedRes = await rv.RunView<PersonLookupRow>(
            {
                EntityName: PEOPLE_ENTITY,
                ExtraFilter: `ID = '${contextUser.LinkedEntityRecordID.trim()}'`,
                Fields: ['ID', 'FirstName', 'LastName', 'DisplayName', 'Email', 'LinkedUserID', 'Status'],
                MaxRows: 1,
                ResultType: 'simple',
            },
            contextUser,
        );
        if (linkedRes.Success && (linkedRes.Results?.length ?? 0) === 1) {
            return linkedRes.Results[0];
        }
    }

    if (IsValidUUID(contextUser.ID)) {
        const safeUserId = contextUser.ID.trim();
        const byUserRes = await rv.RunView<PersonLookupRow>(
            {
                EntityName: PEOPLE_ENTITY,
                ExtraFilter: `LinkedUserID = '${safeUserId}' AND Status = 'Active'`,
                Fields: ['ID', 'FirstName', 'LastName', 'DisplayName', 'Email', 'LinkedUserID', 'Status'],
                MaxRows: 2,
                ResultType: 'simple',
            },
            contextUser,
        );
        if (byUserRes.Success && (byUserRes.Results?.length ?? 0) === 1) {
            return byUserRes.Results[0];
        }
    }

    if (contextUser.Email && contextUser.Email.trim().length > 0) {
        const safeEmail = EscapeSQLString(contextUser.Email.trim());
        const byEmailRes = await rv.RunView<PersonLookupRow>(
            {
                EntityName: PEOPLE_ENTITY,
                ExtraFilter: `LOWER(Email) = LOWER('${safeEmail}') AND Status = 'Active'`,
                Fields: ['ID', 'FirstName', 'LastName', 'DisplayName', 'Email', 'LinkedUserID', 'Status'],
                MaxRows: 5,
                ResultType: 'simple',
            },
            contextUser,
        );
        if (byEmailRes.Success && (byEmailRes.Results?.length ?? 0) > 0) {
            const candidates = byEmailRes.Results;
            const preferred =
                candidates.find((c) => c.LinkedUserID && UUIDsEqual(c.LinkedUserID, contextUser.ID)) ??
                candidates.find((c) => !c.LinkedUserID) ??
                (candidates.length === 1 ? candidates[0] : undefined);
            if (preferred) {
                return preferred;
            }
        }
    }

    return null;
}

async function resolveCallerGitHubIdentity(
    contextUser: UserInfo | undefined,
    rv: RunView,
    provider: IMetadataProvider | undefined,
): Promise<CallerGitHubIdentity | null> {
    const person = await resolveCallerPerson(contextUser, rv, provider);
    if (!person || !IsValidUUID(person.ID)) {
        return null;
    }

    const safePersonId = AssertValidUUID(person.ID, 'Person.ID');
    const identitiesRes = await rv.RunView<mjBizAppsTasksGitHubGitHubIdentityEntity>(
        {
            EntityName: GITHUB_IDENTITIES_ENTITY,
            ExtraFilter: `PersonID = '${safePersonId}' AND IsActive = 1`,
            Fields: ['ID', 'GitHubLogin', 'PersonID', 'IsActive'],
            ResultType: 'simple',
        },
        contextUser,
    );

    if (!identitiesRes.Success) {
        throw new Error(
            `Failed querying '${GITHUB_IDENTITIES_ENTITY}': ${identitiesRes.ErrorMessage ?? 'unknown error'}`,
        );
    }

    const logins: string[] = [];
    const loginsLower = new Set<string>();
    for (const row of identitiesRes.Results ?? []) {
        if (row.IsActive === false) {
            continue;
        }
        if (row.PersonID && !UUIDsEqual(row.PersonID, person.ID)) {
            continue;
        }
        const trimmed = (row.GitHubLogin ?? '').trim();
        if (trimmed.length > 0 && !loginsLower.has(trimmed.toLowerCase())) {
            logins.push(trimmed);
            loginsLower.add(trimmed.toLowerCase());
        }
    }

    return {
        PersonID: person.ID,
        DisplayName: formatPersonDisplayName(person),
        Email: person.Email ?? null,
        GitHubLogins: logins,
        GitHubLoginsLower: loginsLower,
    };
}

async function loadCallerAssignmentContext(
    caller: CallerGitHubIdentity,
    rv: RunView,
    contextUser: UserInfo,
    provider: IMetadataProvider | undefined,
): Promise<CallerAssignmentContext> {
    const safePersonId = AssertValidUUID(caller.PersonID, 'Caller.PersonID');
    const md: IMetadataProvider | undefined = provider ?? Metadata.Provider;
    const peopleEntityId =
        md && typeof md.EntityByName === 'function' ? md.EntityByName(PEOPLE_ENTITY)?.ID : undefined;

    const [rolesRes, assignmentsRes, reposRes] = await rv.RunViews(
        [
            {
                EntityName: TASK_ROLES_ENTITY,
                ExtraFilter: `Name IN ('Primary', 'Reviewer')`,
                Fields: ['ID', 'Name'],
                ResultType: 'simple',
            },
            {
                EntityName: TASK_ASSIGNMENTS_ENTITY,
                ExtraFilter: `AssigneeRecordID = '${safePersonId}'`,
                Fields: ['ID', 'TaskID', 'AssigneeEntityID', 'AssigneeRecordID', 'RoleID', 'Role', 'Status', 'AssignedAt'],
                ResultType: 'simple',
            },
            {
                EntityName: GITHUB_REPOSITORIES_ENTITY,
                Fields: ['ID', 'Owner', 'Name'],
                ResultType: 'simple',
            },
        ],
        contextUser,
    );

    if (!rolesRes?.Success || !assignmentsRes?.Success || !reposRes?.Success) {
        const errMsg =
            rolesRes?.ErrorMessage ||
            assignmentsRes?.ErrorMessage ||
            reposRes?.ErrorMessage ||
            'Failed loading GitHub task reference context';
        throw new Error(errMsg);
    }

    const roles = (rolesRes.Results as mjBizAppsTasksTaskRoleEntity[] | undefined) ?? [];
    const reviewerRoleId = roles.find((r) => r.Name.trim().toLowerCase() === 'reviewer')?.ID ?? null;

    const assignments = (assignmentsRes.Results as mjBizAppsTasksTaskAssignmentEntity[] | undefined) ?? [];
    const ownedTaskIds = new Set<string>();
    const ownedTaskRawIds: string[] = [];
    const pendingReviewsByTaskId = new Map<string, mjBizAppsTasksTaskAssignmentEntity>();

    for (const assignment of assignments) {
        if (!assignment.TaskID || !assignment.AssigneeRecordID) {
            continue;
        }
        if (!UUIDsEqual(assignment.AssigneeRecordID, caller.PersonID)) {
            continue;
        }
        if (peopleEntityId && assignment.AssigneeEntityID && !UUIDsEqual(assignment.AssigneeEntityID, peopleEntityId)) {
            continue;
        }

        const normTaskId = NormalizeUUID(assignment.TaskID);
        if (isReviewerAssignment(assignment, reviewerRoleId)) {
            if (assignment.Status !== 'Completed') {
                const existing = pendingReviewsByTaskId.get(normTaskId);
                if (!existing) {
                    pendingReviewsByTaskId.set(normTaskId, assignment);
                } else {
                    const existingTime = toDateOrNull(existing.AssignedAt)?.getTime() ?? Number.MAX_SAFE_INTEGER;
                    const candidateTime = toDateOrNull(assignment.AssignedAt)?.getTime() ?? Number.MAX_SAFE_INTEGER;
                    if (candidateTime < existingTime) {
                        pendingReviewsByTaskId.set(normTaskId, assignment);
                    }
                }
            }
        } else {
            if (!ownedTaskIds.has(normTaskId)) {
                ownedTaskIds.add(normTaskId);
                ownedTaskRawIds.push(assignment.TaskID);
            }
        }
    }

    const repos = (reposRes.Results as RepositoryLookupRow[] | undefined) ?? [];
    const reposById = IndexByUUID(repos, (r) => r.ID);

    return {
        OwnedTaskIds: ownedTaskIds,
        OwnedTaskRawIds: ownedTaskRawIds,
        PendingReviewsByTaskId: pendingReviewsByTaskId,
        ReposById: reposById,
    };
}

function buildOwnershipSqlFilter(
    caller: CallerGitHubIdentity,
    taskIds: readonly string[],
): string {
    const safePersonId = AssertValidUUID(caller.PersonID, 'Caller.PersonID');
    const clauses: string[] = [`CreatedByPersonID = '${safePersonId}'`];

    const validTaskIds = taskIds.filter((id) => IsValidUUID(id)).map((id) => `'${id.trim()}'`);
    if (validTaskIds.length > 0) {
        clauses.push(`ID IN (${validTaskIds.join(', ')})`);
    }
    if (caller.GitHubLogins.length > 0) {
        const loginList = caller.GitHubLogins
            .map((login) => `LOWER('${EscapeSQLString(login)}')`)
            .join(', ');
        clauses.push(`LOWER(AuthorLogin) IN (${loginList})`);
    }

    return `(${clauses.join(' OR ')})`;
}

function isCallerAuthoredItem(
    authorLogin: string | null | undefined,
    createdByPersonId: string | null | undefined,
    caller: CallerGitHubIdentity,
): boolean {
    if (authorLogin && caller.GitHubLoginsLower.has(authorLogin.trim().toLowerCase())) {
        return true;
    }
    if (createdByPersonId && UUIDsEqual(createdByPersonId, caller.PersonID)) {
        return true;
    }
    return false;
}

function toMyGitHubPRRow(
    pr: mjBizAppsTasksGitHubGitHubPullRequestTaskEntity,
    reposById: ReturnType<typeof IndexByUUID<RepositoryLookupRow>>,
    isAuthored: boolean,
    isAssigned: boolean,
    nowMs: number,
): MyGitHubPRRow {
    const updatedAtIso = toIsoOrNull(pr.GitHubUpdatedAt ?? pr.__mj_UpdatedAt ?? pr.__mj_CreatedAt);
    const ageAnchor = pr.__mj_CreatedAt ?? pr.GitHubUpdatedAt ?? pr.__mj_UpdatedAt;
    const involvement: MyGitHubPRRow['Involvement'] =
        isAuthored && isAssigned ? 'Both' : isAuthored ? 'Author' : 'Assignee';

    return {
        TaskID: pr.ID,
        PRNumber: pr.Number ?? null,
        Title: pr.Name,
        Repository: formatRepositoryName(pr.RepositoryID, pr.Repository, reposById),
        State: pr.State,
        IsDraft: Boolean(pr.IsDraft),
        ReviewDecision: pr.ReviewDecision ?? null,
        CIStatus: pr.ChecksStatus ?? null,
        URL: pr.HtmlURL ?? null,
        UpdatedAt: updatedAtIso,
        AgeHours: computeHoursSince(ageAnchor, nowMs),
        AuthorLogin: pr.AuthorLogin ?? null,
        HeadBranch: pr.HeadBranch ?? null,
        BaseBranch: pr.BaseBranch ?? null,
        TaskStatus: pr.Status as CoreTaskStatusValue,
        Priority: pr.Priority as CoreTaskPriorityValue,
        Involvement: involvement,
    };
}

function toReviewWaitingRow(
    pr: mjBizAppsTasksGitHubGitHubPullRequestTaskEntity,
    assignment: mjBizAppsTasksTaskAssignmentEntity,
    reposById: ReturnType<typeof IndexByUUID<RepositoryLookupRow>>,
    nowMs: number,
): GitHubReviewWaitingRow {
    const waitingAnchor = assignment.AssignedAt ?? pr.GitHubUpdatedAt ?? pr.__mj_CreatedAt ?? pr.__mj_UpdatedAt;
    const waitingHours = computeHoursSince(waitingAnchor, nowMs);
    return {
        TaskID: pr.ID,
        PRNumber: pr.Number ?? null,
        Title: pr.Name,
        Author: pr.AuthorLogin ?? null,
        Repository: formatRepositoryName(pr.RepositoryID, pr.Repository, reposById),
        URL: pr.HtmlURL ?? null,
        WaitingHours: waitingHours,
        IsStale: waitingHours > STALE_REVIEW_THRESHOLD_HOURS,
        IsDraft: Boolean(pr.IsDraft),
        ReviewDecision: pr.ReviewDecision ?? null,
        CIStatus: pr.ChecksStatus ?? null,
        AssignedAt: toIsoOrNull(assignment.AssignedAt),
        AssignmentStatus: assignment.Status,
    };
}

/**
 * Strongly-typed, policy-guarded Chief of Staff action listing GitHub Pull Request tasks
 * authored by or assigned to the calling user.
 */
@RegisterClass(BaseAction, 'GetMyGitHubPRsAction')
export class GetMyGitHubPRsAction extends BaseAction {
    public static override readonly AuthorizesCaller = true;

    protected async InternalRunAction(params: RunActionParams): Promise<ActionResultSimple> {
        try {
            const stateParam = parsePRStateFilter(getStringParam(params.Params, 'State'));
            if (stateParam.error) {
                return {
                    Success: false,
                    ResultCode: 'INVALID_PARAMS',
                    Message: stateParam.error,
                    Params: params.Params,
                };
            }

            const includeDraftsParam = parseOptionalBooleanParam(params.Params, 'IncludeDrafts', true);
            if (includeDraftsParam.error) {
                return {
                    Success: false,
                    ResultCode: 'INVALID_PARAMS',
                    Message: includeDraftsParam.error,
                    Params: params.Params,
                };
            }

            const limitParam = parseOptionalIntParam(
                params.Params,
                'Limit',
                DEFAULT_PR_LIMIT,
                1,
                MAX_PR_LIMIT,
            );
            if (limitParam.error) {
                return {
                    Success: false,
                    ResultCode: 'INVALID_PARAMS',
                    Message: limitParam.error,
                    Params: params.Params,
                };
            }

            const repoFilter = getStringParam(params.Params, 'RepositoryName');

            const guard = await checkGitHubCoSEntityAccess(params, [
                GITHUB_PR_TASKS_ENTITY,
                GITHUB_REPOSITORIES_ENTITY,
                GITHUB_IDENTITIES_ENTITY,
                TASKS_ENTITY_NAME,
                TASK_ASSIGNMENTS_ENTITY,
            ]);
            if (!guard.Allowed) {
                return guard.Failure!;
            }

            const contextUser = params.ContextUser;
            if (!contextUser?.ID) {
                return {
                    Success: false,
                    ResultCode: 'NO_PERSON_RECORD',
                    Message: 'Get My GitHub PRs requires an authenticated user linked to a Person record.',
                    Params: params.Params,
                };
            }

            const rv = createRunView(params.Provider);
            const caller = await resolveCallerGitHubIdentity(contextUser, rv, params.Provider);
            if (!caller) {
                return {
                    Success: false,
                    ResultCode: 'NO_PERSON_RECORD',
                    Message: 'No active BizApps Common Person record is linked to the calling user.',
                    Params: params.Params,
                };
            }

            const ctx = await loadCallerAssignmentContext(caller, rv, contextUser, params.Provider);

            const filterClauses: string[] = [buildOwnershipSqlFilter(caller, ctx.OwnedTaskRawIds)];
            if (stateParam.value === 'Draft') {
                filterClauses.push(`State = 'open' AND IsDraft = 1`);
            } else if (stateParam.value === 'Open') {
                filterClauses.push(includeDraftsParam.value ? `State = 'open'` : `State = 'open' AND IsDraft = 0`);
            } else if (stateParam.value === 'Merged') {
                filterClauses.push(`State = 'merged'`);
            } else if (stateParam.value === 'Closed') {
                filterClauses.push(`State = 'closed'`);
            } else if (!includeDraftsParam.value) {
                filterClauses.push(`IsDraft = 0`);
            }

            const prsRes = await rv.RunView<mjBizAppsTasksGitHubGitHubPullRequestTaskEntity>(
                {
                    EntityName: GITHUB_PR_TASKS_ENTITY,
                    ExtraFilter: filterClauses.join(' AND '),
                    OrderBy: 'GitHubUpdatedAt DESC, __mj_UpdatedAt DESC',
                    ResultType: 'simple',
                },
                contextUser,
            );
            if (!prsRes.Success) {
                const errMsg = prsRes.ErrorMessage || `Failed querying '${GITHUB_PR_TASKS_ENTITY}'.`;
                LogError(new Error(`[GetMyGitHubPRsAction] ${errMsg}`));
                return {
                    Success: false,
                    ResultCode: 'FAILED',
                    Message: errMsg,
                    Params: params.Params,
                };
            }

            const nowMs = Date.now();
            const matchedRows: MyGitHubPRRow[] = [];

            for (const pr of prsRes.Results ?? []) {
                const isAuthored = isCallerAuthoredItem(pr.AuthorLogin, pr.CreatedByPersonID, caller);
                const isAssigned = ctx.OwnedTaskIds.has(NormalizeUUID(pr.ID));
                if (!isAuthored && !isAssigned) {
                    continue;
                }

                if (stateParam.value === 'Draft') {
                    if (pr.State !== 'open' || !pr.IsDraft) continue;
                } else if (stateParam.value === 'Open') {
                    if (pr.State !== 'open') continue;
                    if (!includeDraftsParam.value && pr.IsDraft) continue;
                } else if (stateParam.value === 'Merged') {
                    if (pr.State !== 'merged') continue;
                } else if (stateParam.value === 'Closed') {
                    if (pr.State !== 'closed') continue;
                } else if (!includeDraftsParam.value && pr.IsDraft) {
                    continue;
                }

                if (!matchesRepositoryFilter(pr.RepositoryID, pr.Repository, ctx.ReposById, repoFilter)) {
                    continue;
                }

                matchedRows.push(toMyGitHubPRRow(pr, ctx.ReposById, isAuthored, isAssigned, nowMs));
            }

            matchedRows.sort((a, b) => {
                const timeA = a.UpdatedAt ? new Date(a.UpdatedAt).getTime() : 0;
                const timeB = b.UpdatedAt ? new Date(b.UpdatedAt).getTime() : 0;
                if (timeB !== timeA) return timeB - timeA;
                return a.TaskID.localeCompare(b.TaskID);
            });

            const limited = matchedRows.slice(0, limitParam.value);
            const maskedRows = TypedActionPolicyGuard.MaskRows(limited, guard.DeniedFieldPatterns);

            const payload = {
                PersonID: caller.PersonID,
                GitHubLogins: caller.GitHubLogins,
                StateFilter: stateParam.value,
                RepositoryFilter: repoFilter,
                IncludeDrafts: includeDraftsParam.value,
                TotalCount: matchedRows.length,
                ReturnedCount: maskedRows.length,
                PullRequests: maskedRows,
            };

            const json = JSON.stringify(payload);
            setOutputParam(params.Params, 'PullRequestsJSON', json);
            return {
                Success: true,
                ResultCode: 'SUCCESS',
                Message: json,
                Params: params.Params,
            };
        } catch (error) {
            const msg = error instanceof Error ? error.message : String(error);
            LogError(error instanceof Error ? error : new Error(msg));
            return {
                Success: false,
                ResultCode: 'FAILED',
                Message: msg,
                Params: params.Params,
            };
        }
    }
}

/**
 * Strongly-typed, policy-guarded Chief of Staff action listing open GitHub Pull Request tasks
 * waiting on the calling user's review, sorted oldest/most-stale first.
 */
@RegisterClass(BaseAction, 'GetGitHubReviewsWaitingOnMeAction')
export class GetGitHubReviewsWaitingOnMeAction extends BaseAction {
    public static override readonly AuthorizesCaller = true;

    protected async InternalRunAction(params: RunActionParams): Promise<ActionResultSimple> {
        try {
            const minAgeParam = parseOptionalNonNegativeNumberParam(params.Params, 'MinAgeHours', 0);
            if (minAgeParam.error) {
                return {
                    Success: false,
                    ResultCode: 'INVALID_PARAMS',
                    Message: minAgeParam.error,
                    Params: params.Params,
                };
            }

            const limitParam = parseOptionalIntParam(
                params.Params,
                'Limit',
                DEFAULT_PR_LIMIT,
                1,
                MAX_PR_LIMIT,
            );
            if (limitParam.error) {
                return {
                    Success: false,
                    ResultCode: 'INVALID_PARAMS',
                    Message: limitParam.error,
                    Params: params.Params,
                };
            }

            const repoFilter = getStringParam(params.Params, 'RepositoryName');

            const guard = await checkGitHubCoSEntityAccess(params, [
                GITHUB_PR_TASKS_ENTITY,
                GITHUB_REPOSITORIES_ENTITY,
                GITHUB_IDENTITIES_ENTITY,
                TASKS_ENTITY_NAME,
                TASK_ASSIGNMENTS_ENTITY,
            ]);
            if (!guard.Allowed) {
                return guard.Failure!;
            }

            const contextUser = params.ContextUser;
            if (!contextUser?.ID) {
                return {
                    Success: false,
                    ResultCode: 'NO_PERSON_RECORD',
                    Message: 'Get GitHub Reviews Waiting On Me requires an authenticated user linked to a Person record.',
                    Params: params.Params,
                };
            }

            const rv = createRunView(params.Provider);
            const caller = await resolveCallerGitHubIdentity(contextUser, rv, params.Provider);
            if (!caller) {
                return {
                    Success: false,
                    ResultCode: 'NO_PERSON_RECORD',
                    Message: 'No active BizApps Common Person record is linked to the calling user.',
                    Params: params.Params,
                };
            }

            const ctx = await loadCallerAssignmentContext(caller, rv, contextUser, params.Provider);
            const pendingTaskIds = Array.from(ctx.PendingReviewsByTaskId.values())
                .map((a) => a.TaskID)
                .filter((id) => IsValidUUID(id));

            const nowMs = Date.now();
            const waitingRows: GitHubReviewWaitingRow[] = [];

            if (pendingTaskIds.length > 0) {
                const inClause = pendingTaskIds.map((id) => `'${id.trim()}'`).join(', ');
                const prsRes = await rv.RunView<mjBizAppsTasksGitHubGitHubPullRequestTaskEntity>(
                    {
                        EntityName: GITHUB_PR_TASKS_ENTITY,
                        ExtraFilter: `ID IN (${inClause}) AND State = 'open'`,
                        ResultType: 'simple',
                    },
                    contextUser,
                );
                if (!prsRes.Success) {
                    const errMsg = prsRes.ErrorMessage || `Failed querying '${GITHUB_PR_TASKS_ENTITY}'.`;
                    LogError(new Error(`[GetGitHubReviewsWaitingOnMeAction] ${errMsg}`));
                    return {
                        Success: false,
                        ResultCode: 'FAILED',
                        Message: errMsg,
                        Params: params.Params,
                    };
                }

                for (const pr of prsRes.Results ?? []) {
                    if (pr.State !== 'open') {
                        continue;
                    }
                    if (pr.Status === 'Completed' || pr.Status === 'Cancelled') {
                        continue;
                    }
                    const assignment = ctx.PendingReviewsByTaskId.get(NormalizeUUID(pr.ID));
                    if (!assignment || assignment.Status === 'Completed') {
                        continue;
                    }
                    if (!matchesRepositoryFilter(pr.RepositoryID, pr.Repository, ctx.ReposById, repoFilter)) {
                        continue;
                    }

                    const row = toReviewWaitingRow(pr, assignment, ctx.ReposById, nowMs);
                    if (row.WaitingHours < minAgeParam.value) {
                        continue;
                    }
                    waitingRows.push(row);
                }
            }

            // Oldest / most-stale review requests first
            waitingRows.sort((a, b) => {
                if (b.WaitingHours !== a.WaitingHours) {
                    return b.WaitingHours - a.WaitingHours;
                }
                return a.TaskID.localeCompare(b.TaskID);
            });

            const totalWaiting = waitingRows.length;
            const staleCount = waitingRows.filter((r) => r.IsStale).length;
            const limited = waitingRows.slice(0, limitParam.value);
            const maskedRows = TypedActionPolicyGuard.MaskRows(limited, guard.DeniedFieldPatterns);

            const payload = {
                PersonID: caller.PersonID,
                GitHubLogins: caller.GitHubLogins,
                RepositoryFilter: repoFilter,
                MinAgeHours: minAgeParam.value,
                StaleThresholdHours: STALE_REVIEW_THRESHOLD_HOURS,
                TotalWaiting: totalWaiting,
                StaleCount: staleCount,
                ReturnedCount: maskedRows.length,
                Reviews: maskedRows,
            };

            const json = JSON.stringify(payload);
            setOutputParam(params.Params, 'ReviewsJSON', json);
            return {
                Success: true,
                ResultCode: 'SUCCESS',
                Message: json,
                Params: params.Params,
            };
        } catch (error) {
            const msg = error instanceof Error ? error.message : String(error);
            LogError(error instanceof Error ? error : new Error(msg));
            return {
                Success: false,
                ResultCode: 'FAILED',
                Message: msg,
                Params: params.Params,
            };
        }
    }
}

function getPRUrgencyScore(row: MyGitHubPRRow): number {
    let score = 0;
    if (row.CIStatus === 'Failing') score += 100;
    if (row.TaskStatus === 'Blocked') score += 80;
    if (row.ReviewDecision === 'CHANGES_REQUESTED') score += 60;
    if (!row.IsDraft && row.ReviewDecision === 'APPROVED') score += 20;
    if (row.IsDraft) score -= 10;
    return score;
}

/**
 * Deterministic `Role = 'Briefing'` (`ExposeToModel = false`) contributor for `Assemble My Briefing`,
 * returning a compact executive summary of the caller's open PRs, pending PR reviews (highlighting >24h stale),
 * blocked/failing GitHub-linked tasks, and upcoming GitHub deadlines within `HorizonDays`.
 */
@RegisterClass(BaseAction, 'GetMyGitHubBriefingAction')
export class GetMyGitHubBriefingAction extends BaseAction {
    public static override readonly AuthorizesCaller = true;

    protected async InternalRunAction(params: RunActionParams): Promise<ActionResultSimple> {
        try {
            const horizonParam = parseOptionalIntParam(
                params.Params,
                'HorizonDays',
                DEFAULT_BRIEFING_HORIZON_DAYS,
                1,
                MAX_BRIEFING_HORIZON_DAYS,
            );
            if (horizonParam.error) {
                return {
                    Success: false,
                    ResultCode: 'INVALID_PARAMS',
                    Message: horizonParam.error,
                    Params: params.Params,
                };
            }

            const limitParam = parseOptionalIntParam(
                params.Params,
                'Limit',
                DEFAULT_BRIEFING_LIMIT,
                1,
                MAX_BRIEFING_LIMIT,
                'MaxItems',
            );
            if (limitParam.error) {
                return {
                    Success: false,
                    ResultCode: 'INVALID_PARAMS',
                    Message: limitParam.error,
                    Params: params.Params,
                };
            }

            const guard = await checkGitHubCoSEntityAccess(params, [
                GITHUB_PR_TASKS_ENTITY,
                GITHUB_ISSUE_TASKS_ENTITY,
                GITHUB_REPOSITORIES_ENTITY,
                GITHUB_IDENTITIES_ENTITY,
                TASKS_ENTITY_NAME,
                TASK_ASSIGNMENTS_ENTITY,
            ]);
            if (!guard.Allowed) {
                return guard.Failure!;
            }

            const contextUser = params.ContextUser;
            if (!contextUser?.ID) {
                return {
                    Success: false,
                    ResultCode: 'NO_PERSON_RECORD',
                    Message: 'Get My GitHub Briefing requires an authenticated user linked to a Person record.',
                    Params: params.Params,
                };
            }

            const rv = createRunView(params.Provider);
            const caller = await resolveCallerGitHubIdentity(contextUser, rv, params.Provider);
            if (!caller) {
                return {
                    Success: false,
                    ResultCode: 'NO_PERSON_RECORD',
                    Message: 'No active BizApps Common Person record is linked to the calling user.',
                    Params: params.Params,
                };
            }

            const ctx = await loadCallerAssignmentContext(caller, rv, contextUser, params.Provider);

            const allRelevantTaskIds = Array.from(
                new Set([
                    ...ctx.OwnedTaskRawIds,
                    ...Array.from(ctx.PendingReviewsByTaskId.values()).map((a) => a.TaskID),
                ]),
            );

            const prFilter = `${buildOwnershipSqlFilter(caller, allRelevantTaskIds)} AND State = 'open'`;
            const issueFilter = `${buildOwnershipSqlFilter(caller, ctx.OwnedTaskRawIds)} AND State = 'open'`;

            const [prsRes, issuesRes] = await rv.RunViews(
                [
                    {
                        EntityName: GITHUB_PR_TASKS_ENTITY,
                        ExtraFilter: prFilter,
                        OrderBy: 'GitHubUpdatedAt DESC, __mj_UpdatedAt DESC',
                        ResultType: 'simple',
                    },
                    {
                        EntityName: GITHUB_ISSUE_TASKS_ENTITY,
                        ExtraFilter: issueFilter,
                        OrderBy: 'DueAt ASC, MilestoneDueAt ASC, __mj_UpdatedAt DESC',
                        ResultType: 'simple',
                    },
                ],
                contextUser,
            );

            if (!prsRes?.Success || !issuesRes?.Success) {
                const errMsg =
                    prsRes?.ErrorMessage ||
                    issuesRes?.ErrorMessage ||
                    'Failed querying GitHub PR and Issue tasks for briefing.';
                LogError(new Error(`[GetMyGitHubBriefingAction] ${errMsg}`));
                return {
                    Success: false,
                    ResultCode: 'FAILED',
                    Message: errMsg,
                    Params: params.Params,
                };
            }

            const now = new Date();
            const nowMs = now.getTime();
            const horizonDays = horizonParam.value;
            const horizonEndMs = nowMs + horizonDays * MS_PER_DAY;
            const horizonStartMs = nowMs - horizonDays * MS_PER_DAY;

            const prs = (prsRes.Results as mjBizAppsTasksGitHubGitHubPullRequestTaskEntity[] | undefined) ?? [];
            const issues = (issuesRes.Results as mjBizAppsTasksGitHubGitHubIssueTaskEntity[] | undefined) ?? [];

            const myOpenPRs: MyGitHubPRRow[] = [];
            const waitingReviews: GitHubReviewWaitingRow[] = [];
            const blockedOrFailing: GitHubBlockedOrFailingRow[] = [];
            const upcomingDeadlines: GitHubUpcomingDeadlineRow[] = [];

            for (const pr of prs) {
                if (pr.State !== 'open' || pr.Status === 'Completed' || pr.Status === 'Cancelled') {
                    continue;
                }
                const normId = NormalizeUUID(pr.ID);
                const isAuthored = isCallerAuthoredItem(pr.AuthorLogin, pr.CreatedByPersonID, caller);
                const isAssigned = ctx.OwnedTaskIds.has(normId);
                const pendingReview = ctx.PendingReviewsByTaskId.get(normId);

                if (isAuthored || isAssigned) {
                    const prRow = toMyGitHubPRRow(pr, ctx.ReposById, isAuthored, isAssigned, nowMs);
                    myOpenPRs.push(prRow);

                    const flags: string[] = [];
                    if (pr.Status === 'Blocked' || (pr.BlockedReason && pr.BlockedReason.trim().length > 0)) {
                        flags.push('Blocked');
                    }
                    if (pr.ChecksStatus === 'Failing') {
                        flags.push('FailingCI');
                    }
                    if (pr.ReviewDecision === 'CHANGES_REQUESTED') {
                        flags.push('ChangesRequested');
                    }
                    if (flags.length > 0) {
                        blockedOrFailing.push({
                            TaskID: pr.ID,
                            Kind: 'PullRequest',
                            Number: pr.Number ?? null,
                            Title: pr.Name,
                            Repository: prRow.Repository,
                            URL: pr.HtmlURL ?? null,
                            TaskStatus: pr.Status as CoreTaskStatusValue,
                            Priority: pr.Priority as CoreTaskPriorityValue,
                            BlockedReason: pr.BlockedReason ?? null,
                            CIStatus: pr.ChecksStatus ?? null,
                            ReviewDecision: pr.ReviewDecision ?? null,
                            Flags: flags.join(','),
                            UpdatedAt: prRow.UpdatedAt,
                        });
                    }

                    const effectiveDue = toDateOrNull(pr.DueAt ?? pr.MilestoneDueAt);
                    if (effectiveDue && effectiveDue.getTime() <= horizonEndMs) {
                        upcomingDeadlines.push({
                            TaskID: pr.ID,
                            Kind: 'PullRequest',
                            Number: pr.Number ?? null,
                            Title: pr.Name,
                            Repository: prRow.Repository,
                            URL: pr.HtmlURL ?? null,
                            DueAt: effectiveDue.toISOString(),
                            IsOverdue: effectiveDue.getTime() < nowMs,
                            TaskStatus: pr.Status as CoreTaskStatusValue,
                            Priority: pr.Priority as CoreTaskPriorityValue,
                        });
                    }
                }

                if (pendingReview && pendingReview.Status !== 'Completed') {
                    waitingReviews.push(toReviewWaitingRow(pr, pendingReview, ctx.ReposById, nowMs));
                }
            }

            for (const issue of issues) {
                if (issue.State !== 'open' || issue.Status === 'Completed' || issue.Status === 'Cancelled') {
                    continue;
                }
                const normId = NormalizeUUID(issue.ID);
                const isAuthored = isCallerAuthoredItem(issue.AuthorLogin, issue.CreatedByPersonID, caller);
                const isAssigned = ctx.OwnedTaskIds.has(normId);
                if (!isAuthored && !isAssigned) {
                    continue;
                }

                const repoName = formatRepositoryName(issue.RepositoryID, issue.Repository, ctx.ReposById);
                if (issue.Status === 'Blocked' || (issue.BlockedReason && issue.BlockedReason.trim().length > 0)) {
                    blockedOrFailing.push({
                        TaskID: issue.ID,
                        Kind: 'Issue',
                        Number: issue.Number ?? null,
                        Title: issue.Name,
                        Repository: repoName,
                        URL: issue.HtmlURL ?? null,
                        TaskStatus: issue.Status as CoreTaskStatusValue,
                        Priority: issue.Priority as CoreTaskPriorityValue,
                        BlockedReason: issue.BlockedReason ?? null,
                        CIStatus: null,
                        ReviewDecision: null,
                        Flags: 'Blocked',
                        UpdatedAt: toIsoOrNull(issue.GitHubUpdatedAt ?? issue.__mj_UpdatedAt ?? issue.__mj_CreatedAt),
                    });
                }

                const effectiveDue = toDateOrNull(issue.DueAt ?? issue.MilestoneDueAt);
                if (effectiveDue && effectiveDue.getTime() <= horizonEndMs) {
                    upcomingDeadlines.push({
                        TaskID: issue.ID,
                        Kind: 'Issue',
                        Number: issue.Number ?? null,
                        Title: issue.Name,
                        Repository: repoName,
                        URL: issue.HtmlURL ?? null,
                        DueAt: effectiveDue.toISOString(),
                        IsOverdue: effectiveDue.getTime() < nowMs,
                        TaskStatus: issue.Status as CoreTaskStatusValue,
                        Priority: issue.Priority as CoreTaskPriorityValue,
                    });
                }
            }

            // Sort open PRs by urgency first, then most recently updated
            myOpenPRs.sort((a, b) => {
                const urgencyDiff = getPRUrgencyScore(b) - getPRUrgencyScore(a);
                if (urgencyDiff !== 0) return urgencyDiff;
                const timeA = a.UpdatedAt ? new Date(a.UpdatedAt).getTime() : 0;
                const timeB = b.UpdatedAt ? new Date(b.UpdatedAt).getTime() : 0;
                if (timeB !== timeA) return timeB - timeA;
                return a.TaskID.localeCompare(b.TaskID);
            });

            // Sort reviews waiting on caller oldest / most-stale first
            waitingReviews.sort((a, b) => {
                if (b.WaitingHours !== a.WaitingHours) return b.WaitingHours - a.WaitingHours;
                return a.TaskID.localeCompare(b.TaskID);
            });

            // Sort blocked/failing tasks: FailingCI & Blocked first, then PRs before Issues
            blockedOrFailing.sort((a, b) => {
                const scoreA =
                    (a.CIStatus === 'Failing' ? 10 : 0) +
                    (a.TaskStatus === 'Blocked' ? 5 : 0) +
                    (a.ReviewDecision === 'CHANGES_REQUESTED' ? 3 : 0);
                const scoreB =
                    (b.CIStatus === 'Failing' ? 10 : 0) +
                    (b.TaskStatus === 'Blocked' ? 5 : 0) +
                    (b.ReviewDecision === 'CHANGES_REQUESTED' ? 3 : 0);
                if (scoreB !== scoreA) return scoreB - scoreA;
                return a.TaskID.localeCompare(b.TaskID);
            });

            // Sort deadlines earliest first (overdue at top)
            upcomingDeadlines.sort((a, b) => {
                const timeA = new Date(a.DueAt).getTime();
                const timeB = new Date(b.DueAt).getTime();
                if (timeA !== timeB) return timeA - timeB;
                return a.TaskID.localeCompare(b.TaskID);
            });

            const draftPRCount = myOpenPRs.filter((r) => r.IsDraft).length;
            const failingCIPRCount = myOpenPRs.filter((r) => r.CIStatus === 'Failing').length;
            const changesRequestedPRCount = myOpenPRs.filter((r) => r.ReviewDecision === 'CHANGES_REQUESTED').length;
            const recentlyUpdatedPRCount = myOpenPRs.filter((r) => {
                const ts = r.UpdatedAt ? new Date(r.UpdatedAt).getTime() : 0;
                return ts >= horizonStartMs;
            }).length;
            const staleReviewsCount = waitingReviews.filter((r) => r.IsStale).length;

            const limit = limitParam.value;
            const maskedOpenPRs = TypedActionPolicyGuard.MaskRows(
                myOpenPRs.slice(0, limit),
                guard.DeniedFieldPatterns,
            );
            const maskedReviews = TypedActionPolicyGuard.MaskRows(
                waitingReviews.slice(0, limit),
                guard.DeniedFieldPatterns,
            );
            const maskedBlocked = TypedActionPolicyGuard.MaskRows(
                blockedOrFailing.slice(0, limit),
                guard.DeniedFieldPatterns,
            );
            const maskedDeadlines = TypedActionPolicyGuard.MaskRows(
                upcomingDeadlines.slice(0, limit),
                guard.DeniedFieldPatterns,
            );

            const summary =
                `GitHub briefing (${horizonDays}d horizon): ${myOpenPRs.length} open PR(s)` +
                (failingCIPRCount > 0 ? ` (${failingCIPRCount} failing CI)` : '') +
                `, ${waitingReviews.length} review(s) waiting on you` +
                (staleReviewsCount > 0 ? ` (${staleReviewsCount} stale >${STALE_REVIEW_THRESHOLD_HOURS}h)` : '') +
                `, ${blockedOrFailing.length} blocked/failing GitHub task(s)` +
                `, ${upcomingDeadlines.length} upcoming deadline(s).`;

            const payload = {
                GeneratedAt: now.toISOString(),
                HorizonDays: horizonDays,
                HorizonEnd: new Date(horizonEndMs).toISOString(),
                PersonID: caller.PersonID,
                GitHubLogins: caller.GitHubLogins,
                Summary: summary,
                Counts: {
                    OpenPRs: myOpenPRs.length,
                    DraftPRs: draftPRCount,
                    RecentlyUpdatedPRs: recentlyUpdatedPRCount,
                    FailingCIPRs: failingCIPRCount,
                    ChangesRequestedPRs: changesRequestedPRCount,
                    ReviewsWaiting: waitingReviews.length,
                    StaleReviews: staleReviewsCount,
                    BlockedOrFailingTasks: blockedOrFailing.length,
                    UpcomingDeadlines: upcomingDeadlines.length,
                },
                OpenPRs: maskedOpenPRs,
                ReviewsWaitingOnMe: maskedReviews,
                BlockedOrFailingTasks: maskedBlocked,
                UpcomingDeadlines: maskedDeadlines,
            };

            const json = JSON.stringify(payload);
            setOutputParam(params.Params, 'BriefingJSON', json);
            return {
                Success: true,
                ResultCode: 'SUCCESS',
                Message: json,
                Params: params.Params,
            };
        } catch (error) {
            const msg = error instanceof Error ? error.message : String(error);
            LogError(error instanceof Error ? error : new Error(msg));
            return {
                Success: false,
                ResultCode: 'FAILED',
                Message: msg,
                Params: params.Params,
            };
        }
    }
}
