import { createHash } from 'node:crypto';
import type {
    CoreTaskStatus,
    GitHubIssueTypeStatusCode,
    GitHubPullRequestTypeStatusCode,
    NormalizedGitHubIssueInput,
    NormalizedGitHubPullRequestInput,
    TasksOwnedPlanningFieldName,
} from './types.js';

export type FieldOwnerSystem = 'GitHub' | 'Tasks';
export type FieldSyncDirection = 'Pull' | 'NeverPushed' | 'NotSynced';

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
        const hasAssignees = (issue.assigneeLogins?.length ?? 0) > 0;
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
        if (pr.reviewDecision === 'REVIEW_REQUIRED' || (pr.requestedReviewerLogins?.length ?? 0) > 0) {
            return 'REVIEW_REQUIRED';
        }
        return 'OPEN';
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
