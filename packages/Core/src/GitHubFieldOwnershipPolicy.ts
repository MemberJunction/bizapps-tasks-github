import { createHash } from 'node:crypto';
import type {
    CoreTaskStatus,
    GitHubIssueState,
    GitHubIssueStateReason,
    GitHubIssueTypeStatusCode,
    GitHubPullRequestChecksStatus,
    GitHubPullRequestReviewDecision,
    GitHubPullRequestState,
    GitHubPullRequestTypeStatusCode,
    NormalizedGitHubIssueInput,
    NormalizedGitHubPullRequestInput,
    NormalizedGitHubSyncItem,
    NormalizedGitHubUserRef,
    TasksOwnedPlanningFieldName,
} from './types.js';

export type FieldOwnerSystem = 'GitHub' | 'Tasks';
export type FieldSyncDirection = 'Pull' | 'NeverPushed' | 'NotSynced';

export interface SyncItemValidationResult {
    valid: boolean;
    error?: string;
    item?: NormalizedGitHubSyncItem;
}

export type CandidateSyncItemInput =
    | NormalizedGitHubSyncItem
    | Record<
          string,
          | string
          | number
          | boolean
          | null
          | undefined
          | Date
          | string[]
          | NormalizedGitHubUserRef[]
      >;

export interface FieldOwnershipRule {
    readonly fieldKey: string;
    readonly owner: FieldOwnerSystem;
    readonly direction: FieldSyncDirection;
    readonly description: string;
}

const TASKS_OWNED_PLANNING_FIELDS: readonly TasksOwnedPlanningFieldName[] = [
    'DueAt',
    'HoursEstimated',
    'ParentID',
    'Priority',
    'CategoryID',
] as const;

const GITHUB_OWNED_TASK_FIELDS: readonly string[] = [
    'Name',
    'Description',
    'Status',
    'TaskTypeStatusID',
    'CompletedAt',
] as const;

export const GITHUB_FIELD_OWNERSHIP_RULES: readonly FieldOwnershipRule[] = [
    {
        fieldKey: 'Name',
        owner: 'GitHub',
        direction: 'Pull',
        description: 'Issue/PR title pulls from GitHub into Task.Name; read-only in Tasks.',
    },
    {
        fieldKey: 'Description',
        owner: 'GitHub',
        direction: 'Pull',
        description: 'Issue/PR body pulls from GitHub into Task.Description; Task links to HtmlURL for upstream edits.',
    },
    {
        fieldKey: 'Status',
        owner: 'GitHub',
        direction: 'Pull',
        description: 'State, draft, review decision, CI checks, and merge timestamps drive TaskTypeStatusID and Task.Status.',
    },
    {
        fieldKey: 'PrimaryAssignments',
        owner: 'GitHub',
        direction: 'Pull',
        description: 'GitHub assignees map through GitHubIdentity to Primary TaskAssignment rows.',
    },
    {
        fieldKey: 'ReviewerAssignments',
        owner: 'GitHub',
        direction: 'Pull',
        description: 'GitHub requested reviewers map through GitHubIdentity to Reviewer TaskAssignment rows.',
    },
    {
        fieldKey: 'LabelsAndMilestone',
        owner: 'GitHub',
        direction: 'Pull',
        description: 'Labels, Milestone, and MilestoneDueAt pull into extension tables; MilestoneDueAt supersedes pending DueAt Field Suggestions.',
    },
    {
        fieldKey: 'Priority',
        owner: 'Tasks',
        direction: 'NeverPushed',
        description: 'Planning priority stays owned by BizApps Tasks and is never overwritten on GitHub re-sync.',
    },
    {
        fieldKey: 'DueAt',
        owner: 'Tasks',
        direction: 'NeverPushed',
        description: 'Planning due date stays owned by BizApps Tasks; inferred values remain Field Suggestions until accepted.',
    },
    {
        fieldKey: 'HoursEstimated',
        owner: 'Tasks',
        direction: 'NeverPushed',
        description: 'Effort estimate stays owned by BizApps Tasks.',
    },
    {
        fieldKey: 'ParentID',
        owner: 'Tasks',
        direction: 'NeverPushed',
        description: 'Parent OKR / objective rollup stays owned by BizApps Tasks.',
    },
    {
        fieldKey: 'CategoryID',
        owner: 'Tasks',
        direction: 'NeverPushed',
        description: 'Task category classification stays owned by BizApps Tasks.',
    },
    {
        fieldKey: 'Comments',
        owner: 'GitHub',
        direction: 'NotSynced',
        description: 'GitHub comments stay linked on GitHub rather than copied into Tasks.',
    },
] as const;

export class GitHubFieldOwnershipPolicy {
    public static AllowedInferenceAnchorKeys(): readonly TasksOwnedPlanningFieldName[] {
        return TASKS_OWNED_PLANNING_FIELDS;
    }

    public static IsTasksOwnedPlanningField(fieldName: string): fieldName is TasksOwnedPlanningFieldName {
        return (TASKS_OWNED_PLANNING_FIELDS as readonly string[]).includes(fieldName);
    }

    public static IsGitHubOwnedTaskField(fieldName: string): boolean {
        return GITHUB_OWNED_TASK_FIELDS.includes(fieldName);
    }

    public static MapIssueTypeStatusCode(issue: NormalizedGitHubIssueInput): GitHubIssueTypeStatusCode {
        if (issue.state === 'closed') {
            if (issue.stateReason === 'not_planned' || issue.stateReason === 'duplicate') {
                return 'NOT_PLANNED';
            }
            return 'COMPLETED';
        }
        const hasAssignees = (issue.assigneeLogins?.length ?? 0) > 0 || (issue.assignees?.length ?? 0) > 0;
        return hasAssignees ? 'IN_PROGRESS' : 'OPEN';
    }

    public static MapPullRequestTypeStatusCode(pr: NormalizedGitHubPullRequestInput): GitHubPullRequestTypeStatusCode {
        if (pr.state === 'merged' || pr.mergedAt != null) {
            return 'MERGED';
        }
        if (pr.state === 'closed') {
            return 'CLOSED';
        }
        if (pr.isDraft) {
            return 'DRAFT';
        }
        if (pr.reviewDecision === 'CHANGES_REQUESTED') {
            return 'CHANGES_REQUESTED';
        }
        if (pr.reviewDecision === 'APPROVED') {
            return 'APPROVED';
        }
        const hasReviewers =
            (pr.requestedReviewerLogins?.length ?? 0) > 0
            || (pr.requestedReviewers?.length ?? 0) > 0;
        if (pr.reviewDecision === 'REVIEW_REQUIRED' || hasReviewers) {
            return 'REVIEW_REQUIRED';
        }
        return 'OPEN';
    }

    public static ValidateNormalizedGitHubSyncItem(
        candidate: CandidateSyncItemInput | null | undefined,
        expectedRepoFullName?: string,
    ): SyncItemValidationResult {
        if (!candidate || typeof candidate !== 'object' || Array.isArray(candidate)) {
            return { valid: false, error: 'Sync item must be a non-null JSON object' };
        }
        const raw = candidate as Record<
            string,
            string | number | boolean | null | undefined | Date | string[] | NormalizedGitHubUserRef[]
        >;
        const kind = raw.kind;
        if (kind !== 'issue' && kind !== 'pull_request') {
            return {
                valid: false,
                error: `Invalid sync item kind '${String(kind)}'; must be 'issue' or 'pull_request'`,
            };
        }
        if (typeof raw.number !== 'number' || !Number.isInteger(raw.number) || raw.number <= 0) {
            return { valid: false, error: 'Sync item number must be a positive integer' };
        }
        if (typeof raw.nodeId !== 'string' || raw.nodeId.trim().length === 0) {
            return { valid: false, error: 'Sync item nodeId must be a non-empty string' };
        }
        if (typeof raw.title !== 'string' || raw.title.trim().length === 0) {
            return { valid: false, error: 'Sync item title must be a non-empty string' };
        }
        if (raw.body != null && typeof raw.body !== 'string') {
            return { valid: false, error: 'Sync item body must be a string or null' };
        }
        if (typeof raw.htmlUrl !== 'string' || !/^https?:\/\//i.test(raw.htmlUrl.trim())) {
            return { valid: false, error: 'Sync item htmlUrl must be an HTTP(S) URL' };
        }
        if (expectedRepoFullName && expectedRepoFullName.trim().length > 0) {
            const expectedPrefix = `https://github.com/${expectedRepoFullName.trim().toLowerCase()}/`;
            if (!raw.htmlUrl.trim().toLowerCase().startsWith(expectedPrefix)) {
                return {
                    valid: false,
                    error: `Sync item htmlUrl '${raw.htmlUrl}' does not belong to repository '${expectedRepoFullName}'`,
                };
            }
        }

        const validateUserRefs = (
            input: string | number | boolean | null | undefined | Date | string[] | NormalizedGitHubUserRef[],
            fieldLabel: string,
        ): { valid: boolean; error?: string; refs?: NormalizedGitHubUserRef[] } => {
            if (input === undefined || input === null) {
                return { valid: true, refs: undefined };
            }
            if (!Array.isArray(input)) {
                return { valid: false, error: `Sync item ${fieldLabel} must be an array` };
            }
            const normalized: NormalizedGitHubUserRef[] = [];
            for (let i = 0; i < input.length; i += 1) {
                const entry = input[i];
                if (!entry || typeof entry !== 'object') {
                    return { valid: false, error: `Invalid ${fieldLabel}[${i}]: must be an object with login` };
                }
                const refObj = entry as { login?: string | number | boolean | null; userId?: string | number | null };
                if (typeof refObj.login !== 'string' || refObj.login.trim().length === 0) {
                    return {
                        valid: false,
                        error: `Invalid ${fieldLabel}[${i}]: login must be a non-empty string`,
                    };
                }
                const userIdVal =
                    refObj.userId == null
                        ? null
                        : typeof refObj.userId === 'string' || typeof refObj.userId === 'number'
                          ? String(refObj.userId).trim() || null
                          : null;
                normalized.push({ login: refObj.login.trim(), userId: userIdVal });
            }
            return { valid: true, refs: normalized };
        };

        const assigneesCheck = validateUserRefs(raw.assignees, 'assignees');
        if (!assigneesCheck.valid) {
            return { valid: false, error: assigneesCheck.error };
        }

        if (kind === 'issue') {
            const state = raw.state;
            if (state !== 'open' && state !== 'closed') {
                return {
                    valid: false,
                    error: `Invalid issue state '${String(state)}'; must be 'open' or 'closed'`,
                };
            }
            const stateReason = raw.stateReason;
            if (
                stateReason != null
                && stateReason !== 'completed'
                && stateReason !== 'not_planned'
                && stateReason !== 'reopened'
                && stateReason !== 'duplicate'
            ) {
                return {
                    valid: false,
                    error: `Invalid issue stateReason '${String(stateReason)}'`,
                };
            }
            const issueItem: NormalizedGitHubIssueInput = {
                kind: 'issue',
                number: raw.number,
                nodeId: raw.nodeId.trim(),
                title: raw.title,
                body: typeof raw.body === 'string' ? raw.body : null,
                htmlUrl: raw.htmlUrl.trim(),
                state: state as GitHubIssueState,
                stateReason: (stateReason ?? null) as GitHubIssueStateReason | null,
                labels: Array.isArray(raw.labels)
                    ? raw.labels.filter((l): l is string => typeof l === 'string')
                    : undefined,
                milestoneTitle: typeof raw.milestoneTitle === 'string' ? raw.milestoneTitle : null,
                milestoneDueAt:
                    typeof raw.milestoneDueAt === 'string' || raw.milestoneDueAt instanceof Date
                        ? raw.milestoneDueAt
                        : null,
                authorLogin: typeof raw.authorLogin === 'string' ? raw.authorLogin : null,
                authorUserId: typeof raw.authorUserId === 'string' ? raw.authorUserId : null,
                assigneeLogins: Array.isArray(raw.assigneeLogins)
                    ? raw.assigneeLogins.filter((l): l is string => typeof l === 'string')
                    : undefined,
                assignees: assigneesCheck.refs,
                updatedAt:
                    typeof raw.updatedAt === 'string' || raw.updatedAt instanceof Date
                        ? raw.updatedAt
                        : null,
            };
            return { valid: true, item: issueItem };
        }

        const reviewersCheck = validateUserRefs(raw.requestedReviewers, 'requestedReviewers');
        if (!reviewersCheck.valid) {
            return { valid: false, error: reviewersCheck.error };
        }

        const prState = raw.state;
        if (prState !== 'open' && prState !== 'closed' && prState !== 'merged') {
            return {
                valid: false,
                error: `Invalid pull_request state '${String(prState)}'; must be 'open', 'closed', or 'merged'`,
            };
        }
        const reviewDecision = raw.reviewDecision;
        if (
            reviewDecision !== undefined
            && reviewDecision !== null
            && reviewDecision !== 'APPROVED'
            && reviewDecision !== 'CHANGES_REQUESTED'
            && reviewDecision !== 'REVIEW_REQUIRED'
        ) {
            return {
                valid: false,
                error: `Invalid pull_request reviewDecision '${String(reviewDecision)}'`,
            };
        }
        const checksStatus = raw.checksStatus;
        if (
            checksStatus !== undefined
            && checksStatus !== null
            && checksStatus !== 'Pending'
            && checksStatus !== 'Passing'
            && checksStatus !== 'Failing'
            && checksStatus !== 'Neutral'
        ) {
            return {
                valid: false,
                error: `Invalid pull_request checksStatus '${String(checksStatus)}'`,
            };
        }
        const prItem: NormalizedGitHubPullRequestInput = {
            kind: 'pull_request',
            number: raw.number,
            nodeId: raw.nodeId.trim(),
            title: raw.title,
            body: typeof raw.body === 'string' ? raw.body : null,
            htmlUrl: raw.htmlUrl.trim(),
            state: prState as GitHubPullRequestState,
            isDraft: typeof raw.isDraft === 'boolean' ? raw.isDraft : undefined,
            headBranch: typeof raw.headBranch === 'string' ? raw.headBranch : null,
            headSha: typeof raw.headSha === 'string' ? raw.headSha : null,
            baseBranch: typeof raw.baseBranch === 'string' ? raw.baseBranch : null,
            authorLogin: typeof raw.authorLogin === 'string' ? raw.authorLogin : null,
            authorUserId: typeof raw.authorUserId === 'string' ? raw.authorUserId : null,
            assigneeLogins: Array.isArray(raw.assigneeLogins)
                ? raw.assigneeLogins.filter((l): l is string => typeof l === 'string')
                : undefined,
            assignees: assigneesCheck.refs,
            requestedReviewerLogins: Array.isArray(raw.requestedReviewerLogins)
                ? raw.requestedReviewerLogins.filter((l): l is string => typeof l === 'string')
                : undefined,
            requestedReviewers: reviewersCheck.refs,
            reviewDecision:
                reviewDecision === undefined
                    ? undefined
                    : ((reviewDecision ?? null) as GitHubPullRequestReviewDecision | null),
            checksStatus:
                checksStatus === undefined
                    ? undefined
                    : ((checksStatus ?? null) as GitHubPullRequestChecksStatus | null),
            changedFiles:
                raw.changedFiles === undefined
                    ? undefined
                    : typeof raw.changedFiles === 'number'
                      ? raw.changedFiles
                      : null,
            additions:
                raw.additions === undefined
                    ? undefined
                    : typeof raw.additions === 'number'
                      ? raw.additions
                      : null,
            deletions:
                raw.deletions === undefined
                    ? undefined
                    : typeof raw.deletions === 'number'
                      ? raw.deletions
                      : null,
            labels: Array.isArray(raw.labels)
                ? raw.labels.filter((l): l is string => typeof l === 'string')
                : undefined,
            milestoneTitle: typeof raw.milestoneTitle === 'string' ? raw.milestoneTitle : null,
            milestoneDueAt:
                typeof raw.milestoneDueAt === 'string' || raw.milestoneDueAt instanceof Date
                    ? raw.milestoneDueAt
                    : null,
            mergedAt:
                typeof raw.mergedAt === 'string' || raw.mergedAt instanceof Date
                    ? raw.mergedAt
                    : null,
            linkedIssueNumber: typeof raw.linkedIssueNumber === 'number' ? raw.linkedIssueNumber : null,
            updatedAt:
                typeof raw.updatedAt === 'string' || raw.updatedAt instanceof Date
                    ? raw.updatedAt
                    : null,
        };
        return { valid: true, item: prItem };
    }

    public static MapTypeStatusCodeToCoreStatus(
        code: GitHubIssueTypeStatusCode | GitHubPullRequestTypeStatusCode,
    ): CoreTaskStatus {
        switch (code) {
            case 'OPEN':
            case 'READY_FOR_FACTORY':
                return 'Open';
            case 'IN_PROGRESS':
            case 'DRAFT':
            case 'REVIEW_REQUIRED':
            case 'APPROVED':
                return 'InProgress';
            case 'CHANGES_REQUESTED':
                return 'Blocked';
            case 'COMPLETED':
            case 'MERGED':
                return 'Completed';
            case 'NOT_PLANNED':
            case 'CLOSED':
                return 'Cancelled';
            default: {
                const _exhaustive: never = code;
                return _exhaustive;
            }
        }
    }

    public static ComputeBodyHash(title: string, body: string | null | undefined): string {
        const normalized = `${title.trim()}\n---\n${(body ?? '').trim()}`;
        return createHash('sha256').update(normalized, 'utf8').digest('hex');
    }
}
