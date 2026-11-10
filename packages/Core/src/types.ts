import type { BaseEntity, IMetadataProvider, UserInfo } from '@memberjunction/core';
import type { mjBizAppsTasksTaskEntity } from '@mj-biz-apps/tasks-entities';
import type {
    mjBizAppsTasksGitHubGitHubIssueTaskEntity,
    mjBizAppsTasksGitHubGitHubPullRequestTaskEntity,
    mjBizAppsTasksGitHubGitHubRepositoryEntity,
} from '@mj-biz-apps/tasks-github-entities';

export type GitHubImportRule = mjBizAppsTasksGitHubGitHubRepositoryEntity['ImportRule'];
export type GitHubIssueState = mjBizAppsTasksGitHubGitHubIssueTaskEntity['State'];
export type GitHubIssueStateReason = NonNullable<mjBizAppsTasksGitHubGitHubIssueTaskEntity['StateReason']>;
export type GitHubPullRequestState = mjBizAppsTasksGitHubGitHubPullRequestTaskEntity['State'];
export type GitHubPullRequestReviewDecision = NonNullable<mjBizAppsTasksGitHubGitHubPullRequestTaskEntity['ReviewDecision']>;
export type GitHubPullRequestChecksStatus = NonNullable<mjBizAppsTasksGitHubGitHubPullRequestTaskEntity['ChecksStatus']>;
export type CoreTaskStatus = mjBizAppsTasksTaskEntity['Status'];
export type CoreTaskPriority = mjBizAppsTasksTaskEntity['Priority'];

export type GitHubIssueTypeStatusCode =
    | 'OPEN'
    | 'IN_PROGRESS'
    | 'READY_FOR_FACTORY'
    | 'COMPLETED'
    | 'NOT_PLANNED';

export type GitHubPullRequestTypeStatusCode =
    | 'DRAFT'
    | 'OPEN'
    | 'REVIEW_REQUIRED'
    | 'CHANGES_REQUESTED'
    | 'APPROVED'
    | 'READY_FOR_FACTORY'
    | 'MERGED'
    | 'CLOSED';

export type TasksOwnedPlanningFieldName =
    | 'DueAt'
    | 'HoursEstimated'
    | 'ParentID'
    | 'Priority'
    | 'CategoryID';

export interface NormalizedGitHubUserRef {
    login: string;
    userId?: string | null;
}

export interface NormalizedGitHubIssueInput {
    kind: 'issue';
    number: number;
    nodeId: string;
    title: string;
    body: string | null;
    htmlUrl: string;
    state: GitHubIssueState;
    stateReason?: GitHubIssueStateReason | null;
    labels?: string[];
    milestoneTitle?: string | null;
    milestoneDueAt?: string | Date | null;
    authorLogin?: string | null;
    authorUserId?: string | null;
    assigneeLogins?: string[];
    assignees?: NormalizedGitHubUserRef[];
    updatedAt?: string | Date | null;
}

export interface NormalizedGitHubPullRequestInput {
    kind: 'pull_request';
    number: number;
    nodeId: string;
    title: string;
    body: string | null;
    htmlUrl: string;
    state: GitHubPullRequestState;
    isDraft?: boolean;
    headBranch?: string | null;
    headSha?: string | null;
    baseBranch?: string | null;
    authorLogin?: string | null;
    authorUserId?: string | null;
    assigneeLogins?: string[];
    assignees?: NormalizedGitHubUserRef[];
    requestedReviewerLogins?: string[];
    requestedReviewers?: NormalizedGitHubUserRef[];
    reviewDecision?: GitHubPullRequestReviewDecision | null;
    checksStatus?: GitHubPullRequestChecksStatus | null;
    changedFiles?: number | null;
    additions?: number | null;
    deletions?: number | null;
    labels?: string[];
    milestoneTitle?: string | null;
    milestoneDueAt?: string | Date | null;
    mergedAt?: string | Date | null;
    linkedIssueNumber?: number | null;
    updatedAt?: string | Date | null;
}

export type NormalizedGitHubSyncItem = NormalizedGitHubIssueInput | NormalizedGitHubPullRequestInput;

export interface SingleItemSyncResult {
    action: 'created' | 'updated' | 'skipped';
    reason?: string;
    taskId?: string;
    bodyChanged?: boolean;
    supersededDueAtSuggestions?: number;
    inferredSuggestionsCreated?: number;
}

export interface RepositorySyncSummary {
    repositoryId: string;
    repositoryFullName: string;
    created: number;
    updated: number;
    skipped: number;
    supersededDueAtSuggestions: number;
    inferredSuggestionsCreated: number;
    taskIds: string[];
}

export interface InferredPlanningSuggestionCandidate {
    field: TasksOwnedPlanningFieldName;
    value: string | number;
    confidence: number;
    rationale: string;
}

export interface InferenceExtractionResult {
    suggestions: InferredPlanningSuggestionCandidate[];
    mentionedLogins: string[];
    promptRunId?: string | null;
}

export interface InferenceContextInput {
    repositoryFullName: string;
    itemKind: 'issue' | 'pull_request';
    number: number;
    title: string;
    body: string;
    milestoneDueAt: string | null;
    structuredLogins: string[];
    candidateObjectives: Array<{ id: string; name: string }>;
    candidateCategories: Array<{ id: string; name: string }>;
}

export interface IGitHubInferenceExtractor {
    ExtractPlanningSuggestions(
        input: InferenceContextInput,
        contextUser: UserInfo,
        provider?: IMetadataProvider,
    ): Promise<InferenceExtractionResult>;
}

export interface IGitHubRepositoryFetcher {
    FetchRepositoryItems(
        owner: string,
        name: string,
        contextUser: UserInfo,
        provider?: IMetadataProvider,
    ): Promise<NormalizedGitHubSyncItem[]>;
}

/**
 * Queries authoritative check-run/commit-status and pull-request review state directly from GitHub
 * when processing webhook triggers, ensuring durability across server restarts and multi-instance deployments.
 */
export interface IGitHubLiveStateFetcher {
    FetchCommitChecksStatus(
        owner: string,
        repo: string,
        headSha: string,
    ): Promise<GitHubPullRequestChecksStatus | null>;

    FetchPullRequestReviewDecision(
        owner: string,
        repo: string,
        pullNumber: number,
        hasRequestedReviewers: boolean,
    ): Promise<GitHubPullRequestReviewDecision | null | undefined>;
}

/**
 * Strongly-typed shape of `MJ: Field Suggestions` (IS-A `MJ: Comments` -> `MJ: Conversations`)
 * introduced in MJ 6.3, enabling compile-time safe property access across both standalone 6.2.x CI
 * and 6.3+ host runtimes.
 */
export interface IFieldSuggestionEntityRecord extends BaseEntity {
    ID: string;
    UserID: string;
    EnvironmentID: string;
    TypeID: string;
    CommentTypeID: string;
    Name: string | null;
    Description: string | null;
    Status: 'Available' | 'Processing';
    ApplicationScope: 'Global' | 'Specific';
    IsArchived: boolean;
    IsPinned: boolean;
    LinkedEntityID: string | null;
    LinkedRecordID: string | null;
    AnchorType: 'Record' | 'Field' | 'TextRange' | null;
    AnchorKey: string | null;
    IsResolved: boolean;
    ResolvedByUserID: string | null;
    ResolvedAt: Date | null;
    SuggestedValue: string | null;
    Confidence: number | null;
    Source: 'LLM' | 'Integration' | 'Agent' | 'Person';
    Outcome: 'Accepted' | 'Rejected' | 'Superseded' | null;
    AIPromptRunID: string | null;
    Load(ID: string, EntityRelationshipsToLoad?: string[]): Promise<boolean>;
}
