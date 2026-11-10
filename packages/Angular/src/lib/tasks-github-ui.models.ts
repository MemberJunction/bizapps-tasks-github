import type {
    MJCompanyIntegrationEntityMapEntityType,
    MJCompanyIntegrationEntityType,
} from '@memberjunction/core-entities';
import type {
    mjBizAppsTasksGitHubGitHubIdentityEntity,
    mjBizAppsTasksGitHubGitHubIdentityEntityType,
    mjBizAppsTasksGitHubGitHubIssueTaskEntity,
    mjBizAppsTasksGitHubGitHubIssueTaskEntityType,
    mjBizAppsTasksGitHubGitHubPullRequestTaskEntity,
    mjBizAppsTasksGitHubGitHubPullRequestTaskEntityType,
    mjBizAppsTasksGitHubGitHubRepositoryEntity,
    mjBizAppsTasksGitHubGitHubRepositoryEntityType,
} from '@mj-biz-apps/tasks-github-entities';

// ============================================================================
// Entity & Action Constants
// ============================================================================

export const PEOPLE_ENTITY_NAME = 'MJ_BizApps_Common: People';
export const GITHUB_IDENTITIES_ENTITY_NAME = 'MJ_BizApps_Tasks_GitHub: Git Hub Identities';
export const GITHUB_REPOSITORIES_ENTITY_NAME = 'MJ_BizApps_Tasks_GitHub: Git Hub Repositories';
export const GITHUB_ISSUE_TASKS_ENTITY_NAME = 'MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks';
export const GITHUB_PR_TASKS_ENTITY_NAME = 'MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks';
export const GITHUB_WEBHOOK_DELIVERIES_ENTITY_CANDIDATES: readonly string[] = [
    'MJ_BizApps_Tasks_GitHub: GitHub Webhook Deliveries',
    'MJ_BizApps_Tasks_GitHub: Git Hub Webhook Deliveries',
];
export const COMPANY_INTEGRATIONS_ENTITY_NAME = 'MJ: Company Integrations';
export const COMPANY_INTEGRATION_ENTITY_MAPS_ENTITY_NAME = 'MJ: Company Integration Entity Maps';
export const ACTION_EXECUTION_LOGS_ENTITY_NAME = 'MJ: Action Execution Logs';

export const SYNC_GITHUB_REPOSITORY_TASKS_ACTION_ID = '79C7406B-08C9-4CEC-8080-895A936B08AF';
export const HANDLE_GITHUB_TASKS_WEBHOOK_ACTION_ID = '0425697D-175C-4CD2-9036-A9030E65417D';
export const INFER_GITHUB_TASK_PLANNING_FIELDS_ACTION_ID = 'FF789162-F980-4905-934D-48C1D2B53AE0';

export const TASKS_GITHUB_ADMIN_ACTIVE_TAB_SETTING_KEY = 'TasksGitHub.Admin.ActiveTab';

/**
 * Canonical GitHub handle format:
 * - 1 to 39 characters
 * - Alphanumeric ASCII characters or single internal hyphens (`-`)
 * - Cannot begin or end with a hyphen or contain consecutive hyphens
 */
export const GITHUB_USERNAME_REGEX = /^[a-zA-Z0-9](?:[a-zA-Z0-9]|-(?=[a-zA-Z0-9])){0,38}$/;

export const PULL_OWNED_FIELD_LOCK_NOTICE =
    'Title, Description, Status, and Assignees/Reviewers sync from GitHub (edit upstream on GitHub). Priority, Due Date, Estimate, Category, and Parent remain editable in Tasks.';

export const GITHUB_PULL_OWNED_TASK_FIELDS: readonly string[] = [
    'Name',
    'Description',
    'Status',
    'Assignees',
    'Reviewers',
];

export const TASKS_OWNED_PLANNING_FIELDS: readonly string[] = [
    'Priority',
    'DueAt',
    'HoursEstimated',
    'CategoryID',
    'ParentID',
];

// ============================================================================
// Entity-Derived Value-List Unions (Rule 2c — NEVER hand-copy literal unions)
// ============================================================================

export type GitHubRepositoryImportRule = mjBizAppsTasksGitHubGitHubRepositoryEntity['ImportRule'];
export type GitHubIssueState = mjBizAppsTasksGitHubGitHubIssueTaskEntity['State'];
export type GitHubIssueStateReason = mjBizAppsTasksGitHubGitHubIssueTaskEntity['StateReason'];
export type GitHubPullRequestState = mjBizAppsTasksGitHubGitHubPullRequestTaskEntity['State'];
export type GitHubPullRequestReviewDecision = mjBizAppsTasksGitHubGitHubPullRequestTaskEntity['ReviewDecision'];
export type GitHubPullRequestChecksStatus = mjBizAppsTasksGitHubGitHubPullRequestTaskEntity['ChecksStatus'];

// ============================================================================
// Admin Resource Navigation & Filter Types
// ============================================================================

export type GitHubTasksAdminTab = 'repositories' | 'identity' | 'webhooks';
export type RepositoryTrackingFilter = 'all' | 'tracked' | 'untracked';
export type RepositorySyncSourceBadge = 'ConnectorMirror' | 'GitHubREST';

// ============================================================================
// 1. Self-Service Identity Mapping View-Model Types
// ============================================================================

export type IdentityLinkStatus = 'Linked' | 'Unlinked' | 'PersonNotFound';
export type IdentityVaultAuthStatus = 'OAuth3LO' | 'AppFallback';

export interface CurrentUserIdentityInput {
    ID?: string | null;
    Email?: string | null;
    Name?: string | null;
    FirstLast?: string | null;
    LinkedEntityID?: string | number | null;
    LinkedEntityRecordID?: string | number | null;
}

export interface PersonIdentityRecordInput {
    ID: string;
    FirstName?: string | null;
    LastName?: string | null;
    DisplayName?: string | null;
    Email?: string | null;
    LinkedUserID?: string | null;
    Status?: string | null;
}

export type GitHubIdentityRecordInput = Pick<
    mjBizAppsTasksGitHubGitHubIdentityEntityType,
    'ID' | 'PersonID' | 'GitHubLogin' | 'IsActive'
> & {
    GitHubUserID?: mjBizAppsTasksGitHubGitHubIdentityEntityType['GitHubUserID'];
    Person?: mjBizAppsTasksGitHubGitHubIdentityEntityType['Person'];
    __mj_UpdatedAt?: Date | string | null;
    /**
     * Optional MJ Vault 3LO OAuth credential reference when surfaced by host projection or vault lookup.
     */
    OAuthTokenCredentialID?: string | null;
};

export interface GitHubUsernameValidationResult {
    IsValid: boolean;
    NormalizedLogin: string;
    ErrorMessage: string | null;
}

export interface IdentityMappingViewModel {
    UserEmail: string | null;
    UserDisplayName: string;
    PersonID: string | null;
    PersonDisplayName: string | null;
    IdentityID: string | null;
    GitHubLogin: string | null;
    GitHubUserID: string | null;
    IsActive: boolean;
    LinkStatus: IdentityLinkStatus;
    OAuthTokenCredentialID: string | null;
    VaultAuthStatus: IdentityVaultAuthStatus;
    VaultAuthLabel: string;
    StatusSummary: string;
}

export interface BuildIdentityMappingOptions {
    currentUser: CurrentUserIdentityInput | null | undefined;
    people: readonly PersonIdentityRecordInput[];
    identities: readonly GitHubIdentityRecordInput[];
    /**
     * Optional pre-resolved Person ID (e.g. from `ResolvePersonIDForUser` IS-A lookup).
     */
    resolvedPersonID?: string | null;
    /**
     * Optional MJ Vault user-delegated 3LO OAuth credential ID resolved for the signed-in user.
     */
    delegatedOAuthCredentialID?: string | null;
}

// ============================================================================
// 2. Tracked Repository & Connector Mirror Console View-Model Types
// ============================================================================

export type GitHubRepositoryCardInput = Pick<
    mjBizAppsTasksGitHubGitHubRepositoryEntityType,
    'ID' | 'Owner' | 'Name' | 'DefaultBranch' | 'IsTracked' | 'ImportRule'
> & {
    InstallationID?: mjBizAppsTasksGitHubGitHubRepositoryEntityType['InstallationID'];
    OrganizationID?: mjBizAppsTasksGitHubGitHubRepositoryEntityType['OrganizationID'];
    Organization?: mjBizAppsTasksGitHubGitHubRepositoryEntityType['Organization'];
    DeliveryPolicyID?: mjBizAppsTasksGitHubGitHubRepositoryEntityType['DeliveryPolicyID'];
    DefaultProjectID?: string | null;
    CompanyIntegrationID?: string | null;
    LastSyncedAt?: Date | string | null;
};

export type CompanyIntegrationSummaryInput = Pick<MJCompanyIntegrationEntityType, 'ID'> & {
    Integration?: MJCompanyIntegrationEntityType['Integration'] | null;
    IsActive?: MJCompanyIntegrationEntityType['IsActive'] | null;
    ExternalSystemID?: MJCompanyIntegrationEntityType['ExternalSystemID'];
    Configuration?: MJCompanyIntegrationEntityType['Configuration'];
};

export type CompanyIntegrationEntityMapSummaryInput = Pick<
    MJCompanyIntegrationEntityMapEntityType,
    'ID' | 'CompanyIntegrationID'
> & {
    ExternalObjectName?: MJCompanyIntegrationEntityMapEntityType['ExternalObjectName'] | null;
    SyncEnabled?: MJCompanyIntegrationEntityMapEntityType['SyncEnabled'] | null;
    Status?: MJCompanyIntegrationEntityMapEntityType['Status'] | null;
    Integration?: string | null;
};

export interface TrackedRepositoryCardViewModel {
    ID: string;
    Owner: string;
    Name: string;
    FullName: string;
    DefaultBranch: string;
    IsTracked: boolean;
    ImportRule: GitHubRepositoryImportRule;
    ImportRuleLabel: string;
    DefaultProjectID: string | null;
    CompanyIntegrationID: string | null;
    InstallationID: string | null;
    OrganizationName: string | null;
    LastSyncedAt: string | null;
    LastSyncedDisplay: string;
    SyncSourceBadge: RepositorySyncSourceBadge;
    SyncSourceLabel: string;
    GitHubUrl: string;
}

export interface BuildTrackedRepositoryCardsOptions {
    repositories: readonly GitHubRepositoryCardInput[];
    entityMaps?: readonly CompanyIntegrationEntityMapSummaryInput[];
    companyIntegrations?: readonly CompanyIntegrationSummaryInput[];
    lastSyncedByRepositoryID?: ReadonlyMap<string, Date | string | null> | Record<string, Date | string | null>;
}

// ============================================================================
// 3. GitHub Task Detail Badge View-Model Types
// ============================================================================

export type GitHubIssueTaskBadgeInput = Pick<
    mjBizAppsTasksGitHubGitHubIssueTaskEntityType,
    'ID' | 'Number' | 'HtmlURL' | 'State'
> & {
    StateReason?: GitHubIssueStateReason;
    Labels?: mjBizAppsTasksGitHubGitHubIssueTaskEntityType['Labels'];
    Milestone?: mjBizAppsTasksGitHubGitHubIssueTaskEntityType['Milestone'];
    AuthorLogin?: mjBizAppsTasksGitHubGitHubIssueTaskEntityType['AuthorLogin'];
    Repository?: mjBizAppsTasksGitHubGitHubIssueTaskEntityType['Repository'];
    LastSyncedAt?: Date | string | null;
};

export type GitHubPullRequestTaskBadgeInput = Pick<
    mjBizAppsTasksGitHubGitHubPullRequestTaskEntityType,
    'ID' | 'Number' | 'HtmlURL' | 'State' | 'IsDraft'
> & {
    ReviewDecision?: GitHubPullRequestReviewDecision;
    ChecksStatus?: GitHubPullRequestChecksStatus;
    Additions?: mjBizAppsTasksGitHubGitHubPullRequestTaskEntityType['Additions'];
    Deletions?: mjBizAppsTasksGitHubGitHubPullRequestTaskEntityType['Deletions'];
    ChangedFiles?: mjBizAppsTasksGitHubGitHubPullRequestTaskEntityType['ChangedFiles'];
    HeadBranch?: mjBizAppsTasksGitHubGitHubPullRequestTaskEntityType['HeadBranch'];
    BaseBranch?: mjBizAppsTasksGitHubGitHubPullRequestTaskEntityType['BaseBranch'];
    Labels?: mjBizAppsTasksGitHubGitHubPullRequestTaskEntityType['Labels'];
    Milestone?: mjBizAppsTasksGitHubGitHubPullRequestTaskEntityType['Milestone'];
    AuthorLogin?: mjBizAppsTasksGitHubGitHubPullRequestTaskEntityType['AuthorLogin'];
    Repository?: mjBizAppsTasksGitHubGitHubPullRequestTaskEntityType['Repository'];
    LinkedIssueTaskID?: mjBizAppsTasksGitHubGitHubPullRequestTaskEntityType['LinkedIssueTaskID'];
    MergedAt?: Date | string | null;
    LastSyncedAt?: Date | string | null;
};

export interface GitHubIssueBadgeViewModel {
    TaskID: string;
    Number: number | null;
    NumberLabel: string;
    IssueState: GitHubIssueState;
    StateReason: GitHubIssueStateReason;
    StateLabel: string;
    HtmlUrl: string | null;
    RepositoryFullName: string | null;
    Labels: string[];
    Milestone: string | null;
    AuthorLogin: string | null;
    LastSyncedAt: string | null;
    PullOwnedFieldLockNotice: string;
}

export interface GitHubPullRequestBadgeViewModel {
    TaskID: string;
    Number: number | null;
    NumberLabel: string;
    PRState: GitHubPullRequestState;
    IsDraft: boolean;
    StateLabel: string;
    ReviewDecision: GitHubPullRequestReviewDecision;
    ReviewDecisionLabel: string | null;
    ChecksStatus: GitHubPullRequestChecksStatus;
    ChecksStatusLabel: string | null;
    Additions: number;
    Deletions: number;
    ChangedFiles: number | null;
    DiffStatLabel: string;
    HeadBranch: string | null;
    BaseBranch: string | null;
    BranchComparisonLabel: string | null;
    HtmlUrl: string | null;
    RepositoryFullName: string | null;
    Labels: string[];
    Milestone: string | null;
    AuthorLogin: string | null;
    LinkedIssueTaskID: string | null;
    LastSyncedAt: string | null;
    PullOwnedFieldLockNotice: string;
}

export interface GitHubTaskDetailBadgeViewModel {
    TaskID: string;
    HasGitHubLink: boolean;
    Issue: GitHubIssueBadgeViewModel | null;
    PullRequest: GitHubPullRequestBadgeViewModel | null;
    PrimaryHtmlUrl: string | null;
    PullOwnedFieldLockNotice: string;
    GitHubOwnedFields: readonly string[];
    TasksOwnedFields: readonly string[];
}

// ============================================================================
// 4. Webhook Delivery Row & Agent Context View-Model Types
// ============================================================================

export type WebhookDeliveryStatusTone = 'success' | 'warning' | 'error' | 'neutral';

export interface RawWebhookDeliveryRecordInput {
    ID: string;
    DeliveryID?: string | null;
    EventName?: string | null;
    Event?: string | null;
    RepositoryFullName?: string | null;
    Repository?: string | null;
    Status?: string | null;
    ResultCode?: string | null;
    Message?: string | null;
    ReceivedAt?: Date | string | null;
    StartedAt?: Date | string | null;
    __mj_CreatedAt?: Date | string | null;
}

export interface WebhookDeliveryRowViewModel {
    ID: string;
    DeliveryID: string;
    EventName: string;
    RepositoryFullName: string | null;
    StatusLabel: string;
    StatusTone: WebhookDeliveryStatusTone;
    Message: string | null;
    ReceivedAtIso: string | null;
    ReceivedAtDisplay: string;
}

export type GitHubTasksAdminAgentContext = {
    ActiveTab: GitHubTasksAdminTab;
    TrackingFilter: RepositoryTrackingFilter;
    SearchQuery: string;
    TotalRepositoryCount: number;
    TrackedRepositoryCount: number;
    ConnectorMirrorRepositoryCount: number;
    FilteredRepositoryCount: number;
    VisibleRepositories: Array<{
        ID: string;
        FullName: string;
        IsTracked: boolean;
        ImportRule: GitHubRepositoryImportRule;
        SyncSourceBadge: RepositorySyncSourceBadge;
        LastSyncedAt: string | null;
    }>;
    IdentityLinkStatus: IdentityLinkStatus;
    LinkedGitHubLogin: string | null;
    VaultAuthStatus: IdentityVaultAuthStatus;
    RecentWebhookDeliveryCount: number;
};
