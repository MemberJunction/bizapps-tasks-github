import { BaseEntity, EntitySaveOptions, EntityDeleteOptions, CompositeKey, ValidationResult, ValidationErrorInfo, ValidationErrorType, Metadata, ProviderType, DatabaseProviderBase, RunView } from "@memberjunction/core";
import { RegisterClass } from "@memberjunction/global";
import { z } from "zod";

     
 
/**
 * zod schema definition for the entity MJ_BizApps_Tasks_GitHub: Git Hub Identities
 */
export const mjBizAppsTasksGitHubGitHubIdentitySchema = z.object({
    ID: z.string().describe(`
        * * Field Name: ID
        * * Display Name: ID
        * * SQL Data Type: uniqueidentifier
        * * Default Value: newsequentialid()`),
    GitHubLogin: z.string().describe(`
        * * Field Name: GitHubLogin
        * * Display Name: GitHub Login
        * * SQL Data Type: nvarchar(100)
        * * Description: Case-insensitive GitHub username / handle (e.g. octocat).`),
    PersonID: z.string().describe(`
        * * Field Name: PersonID
        * * Display Name: Person
        * * SQL Data Type: uniqueidentifier
        * * Related Entity/Foreign Key: MJ_BizApps_Common: People (vwPeople.ID)
        * * Description: Target BizApps Common Person record associated with this GitHub login.`),
    GitHubUserID: z.string().nullable().describe(`
        * * Field Name: GitHubUserID
        * * Display Name: GitHub User ID
        * * SQL Data Type: nvarchar(64)
        * * Description: Optional numeric or GraphQL node identifier for the GitHub user account.`),
    IsActive: z.boolean().describe(`
        * * Field Name: IsActive
        * * Display Name: Is Active
        * * SQL Data Type: bit
        * * Default Value: 1
        * * Description: Whether this login mapping is currently active for task import and assignment resolution.`),
    __mj_CreatedAt: z.date().describe(`
        * * Field Name: __mj_CreatedAt
        * * Display Name: Created At
        * * SQL Data Type: datetimeoffset
        * * Default Value: getutcdate()`),
    __mj_UpdatedAt: z.date().describe(`
        * * Field Name: __mj_UpdatedAt
        * * Display Name: Updated At
        * * SQL Data Type: datetimeoffset
        * * Default Value: getutcdate()`),
    Person: z.string().nullable().describe(`
        * * Field Name: Person
        * * Display Name: Person Name
        * * SQL Data Type: nvarchar(250)`),
});

export type mjBizAppsTasksGitHubGitHubIdentityEntityType = z.infer<typeof mjBizAppsTasksGitHubGitHubIdentitySchema>;

/**
 * zod schema definition for the entity MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks
 */
export const mjBizAppsTasksGitHubGitHubIssueTaskSchema = z.object({
    ID: z.string().describe(`
        * * Field Name: ID
        * * Display Name: ID
        * * SQL Data Type: uniqueidentifier
        * * Related Entity/Foreign Key: MJ_BizApps_Tasks: Tasks (vwTasks.ID)
        * * Description: Shared primary key referencing __mj_BizAppsTasks.Task(ID).`),
    RepositoryID: z.string().nullable().describe(`
        * * Field Name: RepositoryID
        * * Display Name: Repository ID
        * * SQL Data Type: uniqueidentifier
        * * Related Entity/Foreign Key: MJ_BizApps_Tasks_GitHub: Git Hub Repositories (vwGitHubRepositories.ID)
        * * Description: GitHubRepository to which this issue belongs.`),
    Number: z.number().nullable().describe(`
        * * Field Name: Number
        * * Display Name: Issue Number
        * * SQL Data Type: int
        * * Description: Repository-scoped GitHub issue number (#N). Unique per RepositoryID when populated.`),
    NodeID: z.string().nullable().describe(`
        * * Field Name: NodeID
        * * Display Name: Node ID
        * * SQL Data Type: nvarchar(128)
        * * Description: Global GitHub GraphQL node identifier for idempotent cross-rename sync.`),
    HtmlURL: z.string().nullable().describe(`
        * * Field Name: HtmlURL
        * * Display Name: HTML URL
        * * SQL Data Type: nvarchar(1000)
        * * Description: Canonical browser URL to view or edit the issue on GitHub.`),
    State: z.union([z.literal('closed'), z.literal('open')]).describe(`
        * * Field Name: State
        * * Display Name: State
        * * SQL Data Type: nvarchar(20)
        * * Default Value: open
    * * Value List Type: List
    * * Possible Values 
    *   * closed
    *   * open
        * * Description: GitHub issue state (open or closed).`),
    StateReason: z.union([z.literal('completed'), z.literal('duplicate'), z.literal('not_planned'), z.literal('reopened')]).nullable().describe(`
        * * Field Name: StateReason
        * * Display Name: State Reason
        * * SQL Data Type: nvarchar(40)
    * * Value List Type: List
    * * Possible Values 
    *   * completed
    *   * duplicate
    *   * not_planned
    *   * reopened
        * * Description: Optional GitHub issue state_reason (completed, not_planned, reopened, duplicate).`),
    Labels: z.string().nullable().describe(`
        * * Field Name: Labels
        * * Display Name: Labels
        * * SQL Data Type: nvarchar(MAX)
        * * Description: JSON array of GitHub label names applied to the issue.`),
    Milestone: z.string().nullable().describe(`
        * * Field Name: Milestone
        * * Display Name: Milestone
        * * SQL Data Type: nvarchar(255)
        * * Description: GitHub milestone title when assigned.`),
    MilestoneDueAt: z.date().nullable().describe(`
        * * Field Name: MilestoneDueAt
        * * Display Name: Milestone Due At
        * * SQL Data Type: datetimeoffset
        * * Description: Due timestamp of the GitHub milestone; supersedes pending inferred DueAt Field Suggestions.`),
    AuthorLogin: z.string().nullable().describe(`
        * * Field Name: AuthorLogin
        * * Display Name: Author Login
        * * SQL Data Type: nvarchar(100)
        * * Description: GitHub login of the user who opened the issue.`),
    BodyHash: z.string().nullable().describe(`
        * * Field Name: BodyHash
        * * Display Name: Body Hash
        * * SQL Data Type: nvarchar(64)
        * * Description: SHA-256 hash of the last synced issue body used to detect text edits and trigger Field Suggestion re-inference.`),
    GitHubUpdatedAt: z.date().nullable().describe(`
        * * Field Name: GitHubUpdatedAt
        * * Display Name: GitHub Updated At
        * * SQL Data Type: datetimeoffset
        * * Description: Upstream updated_at timestamp reported by GitHub.`),
    LastSyncedAt: z.date().nullable().describe(`
        * * Field Name: LastSyncedAt
        * * Display Name: Last Synced At
        * * SQL Data Type: datetimeoffset
        * * Description: Timestamp when BizApps Tasks GitHub sync last reconciled this issue.`),
    __mj_CreatedAt: z.date().describe(`
        * * Field Name: __mj_CreatedAt
        * * Display Name: Created At
        * * SQL Data Type: datetimeoffset
        * * Default Value: getutcdate()`),
    __mj_UpdatedAt: z.date().describe(`
        * * Field Name: __mj_UpdatedAt
        * * Display Name: Updated At
        * * SQL Data Type: datetimeoffset
        * * Default Value: getutcdate()`),
    Name: z.string().describe(`
        * * Field Name: Name
        * * Display Name: Name
        * * SQL Data Type: nvarchar(255)`),
    Description: z.string().nullable().describe(`
        * * Field Name: Description
        * * Display Name: Description
        * * SQL Data Type: nvarchar(MAX)`),
    TypeID: z.string().describe(`
        * * Field Name: TypeID
        * * Display Name: Task Type
        * * SQL Data Type: uniqueidentifier
        * * Related Entity/Foreign Key: MJ_BizApps_Tasks: Task Types (vwTaskTypes.ID)`),
    CategoryID: z.string().nullable().describe(`
        * * Field Name: CategoryID
        * * Display Name: Category
        * * SQL Data Type: uniqueidentifier
        * * Related Entity/Foreign Key: MJ_BizApps_Tasks: Task Categories (vwTaskCategories.ID)`),
    ParentID: z.string().nullable().describe(`
        * * Field Name: ParentID
        * * Display Name: Parent Task
        * * SQL Data Type: uniqueidentifier
        * * Related Entity/Foreign Key: MJ_BizApps_Tasks: Tasks (vwTasks.ID)`),
    Status: z.string().describe(`
        * * Field Name: Status
        * * Display Name: Status
        * * SQL Data Type: nvarchar(50)`),
    Priority: z.string().describe(`
        * * Field Name: Priority
        * * Display Name: Priority
        * * SQL Data Type: nvarchar(20)`),
    StartedAt: z.date().nullable().describe(`
        * * Field Name: StartedAt
        * * Display Name: Started At
        * * SQL Data Type: datetimeoffset`),
    DueAt: z.date().nullable().describe(`
        * * Field Name: DueAt
        * * Display Name: Due At
        * * SQL Data Type: datetimeoffset`),
    CompletedAt: z.date().nullable().describe(`
        * * Field Name: CompletedAt
        * * Display Name: Completed At
        * * SQL Data Type: datetimeoffset`),
    HoursEstimated: z.number().nullable().describe(`
        * * Field Name: HoursEstimated
        * * Display Name: Hours Estimated
        * * SQL Data Type: decimal(8, 2)`),
    HoursActual: z.number().nullable().describe(`
        * * Field Name: HoursActual
        * * Display Name: Hours Actual
        * * SQL Data Type: decimal(8, 2)`),
    PercentComplete: z.number().describe(`
        * * Field Name: PercentComplete
        * * Display Name: Percent Complete
        * * SQL Data Type: int`),
    Sequence: z.number().describe(`
        * * Field Name: Sequence
        * * Display Name: Sequence
        * * SQL Data Type: int`),
    BlockedReason: z.string().nullable().describe(`
        * * Field Name: BlockedReason
        * * Display Name: Blocked Reason
        * * SQL Data Type: nvarchar(MAX)`),
    CompletionNotes: z.string().nullable().describe(`
        * * Field Name: CompletionNotes
        * * Display Name: Completion Notes
        * * SQL Data Type: nvarchar(MAX)`),
    CreatedByPersonID: z.string().nullable().describe(`
        * * Field Name: CreatedByPersonID
        * * Display Name: Created By Person
        * * SQL Data Type: uniqueidentifier
        * * Related Entity/Foreign Key: MJ_BizApps_Common: People (vwPeople.ID)`),
    OverdueNotifiedAt: z.date().nullable().describe(`
        * * Field Name: OverdueNotifiedAt
        * * Display Name: Overdue Notified At
        * * SQL Data Type: datetimeoffset`),
    TaskTypeStatusID: z.string().nullable().describe(`
        * * Field Name: TaskTypeStatusID
        * * Display Name: Task Type Status
        * * SQL Data Type: uniqueidentifier
        * * Related Entity/Foreign Key: MJ_BizApps_Tasks: Task Type Status (vwTaskTypeStatus.ID)`),
    PredictedSLABreachProbability: z.number().nullable().describe(`
        * * Field Name: PredictedSLABreachProbability
        * * Display Name: Predicted SLA Breach Probability
        * * SQL Data Type: decimal(5, 4)`),
    PredictedSLARiskBand: z.string().nullable().describe(`
        * * Field Name: PredictedSLARiskBand
        * * Display Name: Predicted SLA Risk Band
        * * SQL Data Type: nvarchar(20)`),
    PredictedSLAScoredAt: z.date().nullable().describe(`
        * * Field Name: PredictedSLAScoredAt
        * * Display Name: Predicted SLA Scored At
        * * SQL Data Type: datetimeoffset`),
    HealthStatus: z.string().nullable().describe(`
        * * Field Name: HealthStatus
        * * Display Name: Health Status
        * * SQL Data Type: nvarchar(20)`),
    ConfidenceScore: z.number().nullable().describe(`
        * * Field Name: ConfidenceScore
        * * Display Name: Confidence Score
        * * SQL Data Type: int`),
    BaselineValue: z.number().nullable().describe(`
        * * Field Name: BaselineValue
        * * Display Name: Baseline Value
        * * SQL Data Type: decimal(18, 4)`),
    TargetValue: z.number().nullable().describe(`
        * * Field Name: TargetValue
        * * Display Name: Target Value
        * * SQL Data Type: decimal(18, 4)`),
    CurrentValue: z.number().nullable().describe(`
        * * Field Name: CurrentValue
        * * Display Name: Current Value
        * * SQL Data Type: decimal(18, 4)`),
    UnitOfMeasure: z.string().nullable().describe(`
        * * Field Name: UnitOfMeasure
        * * Display Name: Unit Of Measure
        * * SQL Data Type: nvarchar(50)`),
    MetricDirection: z.string().nullable().describe(`
        * * Field Name: MetricDirection
        * * Display Name: Metric Direction
        * * SQL Data Type: nvarchar(20)`),
    RollupWeight: z.number().describe(`
        * * Field Name: RollupWeight
        * * Display Name: Rollup Weight
        * * SQL Data Type: decimal(8, 2)`),
    PlanningPeriod: z.string().nullable().describe(`
        * * Field Name: PlanningPeriod
        * * Display Name: Planning Period
        * * SQL Data Type: nvarchar(50)`),
    CheckInCadence: z.string().nullable().describe(`
        * * Field Name: CheckInCadence
        * * Display Name: Check-In Cadence
        * * SQL Data Type: nvarchar(20)`),
    LastCheckInAt: z.date().nullable().describe(`
        * * Field Name: LastCheckInAt
        * * Display Name: Last Check-In At
        * * SQL Data Type: datetimeoffset`),
    NextCheckInDueAt: z.date().nullable().describe(`
        * * Field Name: NextCheckInDueAt
        * * Display Name: Next Check-In Due At
        * * SQL Data Type: datetimeoffset`),
    Repository: z.string().nullable().describe(`
        * * Field Name: Repository
        * * Display Name: Repository
        * * SQL Data Type: nvarchar(200)`),
});

export type mjBizAppsTasksGitHubGitHubIssueTaskEntityType = z.infer<typeof mjBizAppsTasksGitHubGitHubIssueTaskSchema>;

/**
 * zod schema definition for the entity MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks
 */
export const mjBizAppsTasksGitHubGitHubPullRequestTaskSchema = z.object({
    ID: z.string().describe(`
        * * Field Name: ID
        * * Display Name: ID
        * * SQL Data Type: uniqueidentifier
        * * Related Entity/Foreign Key: MJ_BizApps_Tasks: Tasks (vwTasks.ID)
        * * Description: Shared primary key referencing __mj_BizAppsTasks.Task(ID).`),
    RepositoryID: z.string().nullable().describe(`
        * * Field Name: RepositoryID
        * * Display Name: Repository ID
        * * SQL Data Type: uniqueidentifier
        * * Related Entity/Foreign Key: MJ_BizApps_Tasks_GitHub: Git Hub Repositories (vwGitHubRepositories.ID)
        * * Description: GitHubRepository to which this pull request belongs.`),
    Number: z.number().nullable().describe(`
        * * Field Name: Number
        * * Display Name: Number
        * * SQL Data Type: int
        * * Description: Repository-scoped GitHub pull request number (#N). Unique per RepositoryID when populated.`),
    NodeID: z.string().nullable().describe(`
        * * Field Name: NodeID
        * * Display Name: Node ID
        * * SQL Data Type: nvarchar(128)
        * * Description: Global GitHub GraphQL node identifier for idempotent sync.`),
    HtmlURL: z.string().nullable().describe(`
        * * Field Name: HtmlURL
        * * Display Name: HTML URL
        * * SQL Data Type: nvarchar(1000)
        * * Description: Canonical browser URL to view or review the pull request on GitHub.`),
    State: z.union([z.literal('closed'), z.literal('merged'), z.literal('open')]).describe(`
        * * Field Name: State
        * * Display Name: State
        * * SQL Data Type: nvarchar(20)
        * * Default Value: open
    * * Value List Type: List
    * * Possible Values 
    *   * closed
    *   * merged
    *   * open
        * * Description: Pull request lifecycle state on GitHub (open, closed, or merged).`),
    IsDraft: z.boolean().describe(`
        * * Field Name: IsDraft
        * * Display Name: Is Draft
        * * SQL Data Type: bit
        * * Default Value: 0
        * * Description: Whether the pull request is currently marked as a Draft on GitHub.`),
    HeadBranch: z.string().nullable().describe(`
        * * Field Name: HeadBranch
        * * Display Name: Head Branch
        * * SQL Data Type: nvarchar(255)
        * * Description: Source branch ref of the pull request (head.ref).`),
    HeadSha: z.string().nullable().describe(`
        * * Field Name: HeadSha
        * * Display Name: Head SHA
        * * SQL Data Type: nvarchar(64)
        * * Description: Commit SHA at the tip of HeadBranch (head.sha), verified by Software Factory merge gates.`),
    BaseBranch: z.string().nullable().describe(`
        * * Field Name: BaseBranch
        * * Display Name: Base Branch
        * * SQL Data Type: nvarchar(255)
        * * Description: Target branch ref into which the pull request merges (base.ref).`),
    AuthorLogin: z.string().nullable().describe(`
        * * Field Name: AuthorLogin
        * * Display Name: Author Login
        * * SQL Data Type: nvarchar(100)
        * * Description: GitHub login of the pull request author.`),
    ReviewDecision: z.union([z.literal('APPROVED'), z.literal('CHANGES_REQUESTED'), z.literal('REVIEW_REQUIRED')]).nullable().describe(`
        * * Field Name: ReviewDecision
        * * Display Name: Review Decision
        * * SQL Data Type: nvarchar(40)
    * * Value List Type: List
    * * Possible Values 
    *   * APPROVED
    *   * CHANGES_REQUESTED
    *   * REVIEW_REQUIRED
        * * Description: Aggregated GitHub review decision (APPROVED, CHANGES_REQUESTED, or REVIEW_REQUIRED).`),
    ChecksStatus: z.union([z.literal('Failing'), z.literal('Neutral'), z.literal('Passing'), z.literal('Pending')]).nullable().describe(`
        * * Field Name: ChecksStatus
        * * Display Name: Checks Status
        * * SQL Data Type: nvarchar(30)
    * * Value List Type: List
    * * Possible Values 
    *   * Failing
    *   * Neutral
    *   * Passing
    *   * Pending
        * * Description: Aggregated status of required GitHub CI checks on HeadSha (Pending, Passing, Failing, Neutral).`),
    ChangedFiles: z.number().nullable().describe(`
        * * Field Name: ChangedFiles
        * * Display Name: Changed Files
        * * SQL Data Type: int
        * * Description: Number of files touched in the pull request diff.`),
    Additions: z.number().nullable().describe(`
        * * Field Name: Additions
        * * Display Name: Additions
        * * SQL Data Type: int
        * * Description: Lines added in the pull request diff.`),
    Deletions: z.number().nullable().describe(`
        * * Field Name: Deletions
        * * Display Name: Deletions
        * * SQL Data Type: int
        * * Description: Lines deleted in the pull request diff.`),
    Labels: z.string().nullable().describe(`
        * * Field Name: Labels
        * * Display Name: Labels
        * * SQL Data Type: nvarchar(MAX)
        * * Description: JSON array of GitHub label names applied to the pull request.`),
    Milestone: z.string().nullable().describe(`
        * * Field Name: Milestone
        * * Display Name: Milestone
        * * SQL Data Type: nvarchar(255)
        * * Description: GitHub milestone title when assigned.`),
    MilestoneDueAt: z.date().nullable().describe(`
        * * Field Name: MilestoneDueAt
        * * Display Name: Milestone Due At
        * * SQL Data Type: datetimeoffset
        * * Description: Due timestamp of the GitHub milestone; supersedes pending inferred DueAt Field Suggestions.`),
    MergedAt: z.date().nullable().describe(`
        * * Field Name: MergedAt
        * * Display Name: Merged At
        * * SQL Data Type: datetimeoffset
        * * Description: Timestamp when the pull request was merged on GitHub.`),
    LinkedIssueTaskID: z.string().nullable().describe(`
        * * Field Name: LinkedIssueTaskID
        * * Display Name: Linked Issue Task ID
        * * SQL Data Type: uniqueidentifier
        * * Related Entity/Foreign Key: MJ_BizApps_Tasks: Tasks (vwTasks.ID)
        * * Description: Optional reference to the Task (e.g. GITHUB_ISSUE or FACTORY_WORK) that this pull request implements or closes.`),
    BodyHash: z.string().nullable().describe(`
        * * Field Name: BodyHash
        * * Display Name: Body Hash
        * * SQL Data Type: nvarchar(64)
        * * Description: SHA-256 hash of the last synced pull request body used to detect text edits and trigger Field Suggestion re-inference.`),
    GitHubUpdatedAt: z.date().nullable().describe(`
        * * Field Name: GitHubUpdatedAt
        * * Display Name: GitHub Updated At
        * * SQL Data Type: datetimeoffset
        * * Description: Upstream updated_at timestamp reported by GitHub.`),
    LastSyncedAt: z.date().nullable().describe(`
        * * Field Name: LastSyncedAt
        * * Display Name: Last Synced At
        * * SQL Data Type: datetimeoffset
        * * Description: Timestamp when BizApps Tasks GitHub sync last reconciled this pull request.`),
    __mj_CreatedAt: z.date().describe(`
        * * Field Name: __mj_CreatedAt
        * * Display Name: Created At
        * * SQL Data Type: datetimeoffset
        * * Default Value: getutcdate()`),
    __mj_UpdatedAt: z.date().describe(`
        * * Field Name: __mj_UpdatedAt
        * * Display Name: Updated At
        * * SQL Data Type: datetimeoffset
        * * Default Value: getutcdate()`),
    Name: z.string().describe(`
        * * Field Name: Name
        * * Display Name: Name
        * * SQL Data Type: nvarchar(255)`),
    Description: z.string().nullable().describe(`
        * * Field Name: Description
        * * Display Name: Description
        * * SQL Data Type: nvarchar(MAX)`),
    TypeID: z.string().describe(`
        * * Field Name: TypeID
        * * Display Name: Type
        * * SQL Data Type: uniqueidentifier
        * * Related Entity/Foreign Key: MJ_BizApps_Tasks: Task Types (vwTaskTypes.ID)`),
    CategoryID: z.string().nullable().describe(`
        * * Field Name: CategoryID
        * * Display Name: Category
        * * SQL Data Type: uniqueidentifier
        * * Related Entity/Foreign Key: MJ_BizApps_Tasks: Task Categories (vwTaskCategories.ID)`),
    ParentID: z.string().nullable().describe(`
        * * Field Name: ParentID
        * * Display Name: Parent Task
        * * SQL Data Type: uniqueidentifier
        * * Related Entity/Foreign Key: MJ_BizApps_Tasks: Tasks (vwTasks.ID)`),
    Status: z.string().describe(`
        * * Field Name: Status
        * * Display Name: Status
        * * SQL Data Type: nvarchar(50)`),
    Priority: z.string().describe(`
        * * Field Name: Priority
        * * Display Name: Priority
        * * SQL Data Type: nvarchar(20)`),
    StartedAt: z.date().nullable().describe(`
        * * Field Name: StartedAt
        * * Display Name: Started At
        * * SQL Data Type: datetimeoffset`),
    DueAt: z.date().nullable().describe(`
        * * Field Name: DueAt
        * * Display Name: Due At
        * * SQL Data Type: datetimeoffset`),
    CompletedAt: z.date().nullable().describe(`
        * * Field Name: CompletedAt
        * * Display Name: Completed At
        * * SQL Data Type: datetimeoffset`),
    HoursEstimated: z.number().nullable().describe(`
        * * Field Name: HoursEstimated
        * * Display Name: Hours Estimated
        * * SQL Data Type: decimal(8, 2)`),
    HoursActual: z.number().nullable().describe(`
        * * Field Name: HoursActual
        * * Display Name: Hours Actual
        * * SQL Data Type: decimal(8, 2)`),
    PercentComplete: z.number().describe(`
        * * Field Name: PercentComplete
        * * Display Name: Percent Complete
        * * SQL Data Type: int`),
    Sequence: z.number().describe(`
        * * Field Name: Sequence
        * * Display Name: Sequence
        * * SQL Data Type: int`),
    BlockedReason: z.string().nullable().describe(`
        * * Field Name: BlockedReason
        * * Display Name: Blocked Reason
        * * SQL Data Type: nvarchar(MAX)`),
    CompletionNotes: z.string().nullable().describe(`
        * * Field Name: CompletionNotes
        * * Display Name: Completion Notes
        * * SQL Data Type: nvarchar(MAX)`),
    CreatedByPersonID: z.string().nullable().describe(`
        * * Field Name: CreatedByPersonID
        * * Display Name: Created By Person
        * * SQL Data Type: uniqueidentifier
        * * Related Entity/Foreign Key: MJ_BizApps_Common: People (vwPeople.ID)`),
    OverdueNotifiedAt: z.date().nullable().describe(`
        * * Field Name: OverdueNotifiedAt
        * * Display Name: Overdue Notified At
        * * SQL Data Type: datetimeoffset`),
    TaskTypeStatusID: z.string().nullable().describe(`
        * * Field Name: TaskTypeStatusID
        * * Display Name: Task Type Status
        * * SQL Data Type: uniqueidentifier
        * * Related Entity/Foreign Key: MJ_BizApps_Tasks: Task Type Status (vwTaskTypeStatus.ID)`),
    PredictedSLABreachProbability: z.number().nullable().describe(`
        * * Field Name: PredictedSLABreachProbability
        * * Display Name: Predicted SLA Breach Probability
        * * SQL Data Type: decimal(5, 4)`),
    PredictedSLARiskBand: z.string().nullable().describe(`
        * * Field Name: PredictedSLARiskBand
        * * Display Name: Predicted SLA Risk Band
        * * SQL Data Type: nvarchar(20)`),
    PredictedSLAScoredAt: z.date().nullable().describe(`
        * * Field Name: PredictedSLAScoredAt
        * * Display Name: Predicted SLA Scored At
        * * SQL Data Type: datetimeoffset`),
    HealthStatus: z.string().nullable().describe(`
        * * Field Name: HealthStatus
        * * Display Name: Health Status
        * * SQL Data Type: nvarchar(20)`),
    ConfidenceScore: z.number().nullable().describe(`
        * * Field Name: ConfidenceScore
        * * Display Name: Confidence Score
        * * SQL Data Type: int`),
    BaselineValue: z.number().nullable().describe(`
        * * Field Name: BaselineValue
        * * Display Name: Baseline Value
        * * SQL Data Type: decimal(18, 4)`),
    TargetValue: z.number().nullable().describe(`
        * * Field Name: TargetValue
        * * Display Name: Target Value
        * * SQL Data Type: decimal(18, 4)`),
    CurrentValue: z.number().nullable().describe(`
        * * Field Name: CurrentValue
        * * Display Name: Current Value
        * * SQL Data Type: decimal(18, 4)`),
    UnitOfMeasure: z.string().nullable().describe(`
        * * Field Name: UnitOfMeasure
        * * Display Name: Unit Of Measure
        * * SQL Data Type: nvarchar(50)`),
    MetricDirection: z.string().nullable().describe(`
        * * Field Name: MetricDirection
        * * Display Name: Metric Direction
        * * SQL Data Type: nvarchar(20)`),
    RollupWeight: z.number().describe(`
        * * Field Name: RollupWeight
        * * Display Name: Rollup Weight
        * * SQL Data Type: decimal(8, 2)`),
    PlanningPeriod: z.string().nullable().describe(`
        * * Field Name: PlanningPeriod
        * * Display Name: Planning Period
        * * SQL Data Type: nvarchar(50)`),
    CheckInCadence: z.string().nullable().describe(`
        * * Field Name: CheckInCadence
        * * Display Name: Check In Cadence
        * * SQL Data Type: nvarchar(20)`),
    LastCheckInAt: z.date().nullable().describe(`
        * * Field Name: LastCheckInAt
        * * Display Name: Last Check In At
        * * SQL Data Type: datetimeoffset`),
    NextCheckInDueAt: z.date().nullable().describe(`
        * * Field Name: NextCheckInDueAt
        * * Display Name: Next Check In Due At
        * * SQL Data Type: datetimeoffset`),
    Repository: z.string().nullable().describe(`
        * * Field Name: Repository
        * * Display Name: Repository
        * * SQL Data Type: nvarchar(200)`),
    LinkedIssueTask: z.string().nullable().describe(`
        * * Field Name: LinkedIssueTask
        * * Display Name: Linked Issue Task
        * * SQL Data Type: nvarchar(255)`),
});

export type mjBizAppsTasksGitHubGitHubPullRequestTaskEntityType = z.infer<typeof mjBizAppsTasksGitHubGitHubPullRequestTaskSchema>;

/**
 * zod schema definition for the entity MJ_BizApps_Tasks_GitHub: Git Hub Repositories
 */
export const mjBizAppsTasksGitHubGitHubRepositorySchema = z.object({
    ID: z.string().describe(`
        * * Field Name: ID
        * * Display Name: ID
        * * SQL Data Type: uniqueidentifier
        * * Default Value: newsequentialid()`),
    Owner: z.string().describe(`
        * * Field Name: Owner
        * * Display Name: Owner
        * * SQL Data Type: nvarchar(150)
        * * Description: GitHub organization or user login that owns the repository (e.g. MemberJunction).`),
    Name: z.string().describe(`
        * * Field Name: Name
        * * Display Name: Name
        * * SQL Data Type: nvarchar(200)
        * * Description: Repository slug within the owner namespace (e.g. MJ, bizapps-tasks).`),
    DefaultBranch: z.string().describe(`
        * * Field Name: DefaultBranch
        * * Display Name: Default Branch
        * * SQL Data Type: nvarchar(120)
        * * Default Value: main
        * * Description: Default target branch name on GitHub (typically main or next).`),
    IsTracked: z.boolean().describe(`
        * * Field Name: IsTracked
        * * Display Name: Is Tracked
        * * SQL Data Type: bit
        * * Default Value: 1
        * * Description: When 1, periodic sync and incoming webhooks import eligible issues and pull requests into BizApps Tasks.`),
    ImportRule: z.union([z.literal('All'), z.literal('AssignedOnly')]).describe(`
        * * Field Name: ImportRule
        * * Display Name: Import Rule
        * * SQL Data Type: nvarchar(20)
        * * Default Value: AssignedOnly
    * * Value List Type: List
    * * Possible Values 
    *   * All
    *   * AssignedOnly
        * * Description: Controls which issues and PRs become Tasks: AssignedOnly imports items assigned to or requesting review from a mapped GitHubIdentity; All imports every issue and PR in the repository.`),
    InstallationID: z.string().nullable().describe(`
        * * Field Name: InstallationID
        * * Display Name: Installation ID
        * * SQL Data Type: nvarchar(100)
        * * Description: GitHub App installation identifier scoped to this repository or organization.`),
    OrganizationID: z.string().nullable().describe(`
        * * Field Name: OrganizationID
        * * Display Name: Organization ID
        * * SQL Data Type: uniqueidentifier
        * * Related Entity/Foreign Key: MJ_BizApps_Common: Organizations (vwOrganizations.ID)
        * * Description: Optional client Organization in BizApps Common. Null denotes an internal repository; non-null enables Client-layer DeliveryPolicy inheritance.`),
    DeliveryPolicyID: z.string().nullable().describe(`
        * * Field Name: DeliveryPolicyID
        * * Display Name: Delivery Policy ID
        * * SQL Data Type: uniqueidentifier
        * * Description: Optional UUID of the repository-level DeliveryPolicy in bizapps-software-factory when installed.`),
    __mj_CreatedAt: z.date().describe(`
        * * Field Name: __mj_CreatedAt
        * * Display Name: Created At
        * * SQL Data Type: datetimeoffset
        * * Default Value: getutcdate()`),
    __mj_UpdatedAt: z.date().describe(`
        * * Field Name: __mj_UpdatedAt
        * * Display Name: Updated At
        * * SQL Data Type: datetimeoffset
        * * Default Value: getutcdate()`),
    Organization: z.string().nullable().describe(`
        * * Field Name: Organization
        * * Display Name: Organization
        * * SQL Data Type: nvarchar(255)`),
});

export type mjBizAppsTasksGitHubGitHubRepositoryEntityType = z.infer<typeof mjBizAppsTasksGitHubGitHubRepositorySchema>;
 
 

/**
 * MJ_BizApps_Tasks_GitHub: Git Hub Identities - strongly typed entity sub-class
 * * Schema: __mj_BizAppsTasksGitHub
 * * Base Table: GitHubIdentity
 * * Base View: vwGitHubIdentities
 * * @description Maps GitHub user logins to BizApps Common Person records so GitHub issue/PR assignees and requested reviewers synchronize into Primary and Reviewer TaskAssignment rows.
 * * Primary Key: ID
 * @extends {BaseEntity}
 * @class
 * @public
 */
@RegisterClass(BaseEntity, 'MJ_BizApps_Tasks_GitHub: Git Hub Identities')
export class mjBizAppsTasksGitHubGitHubIdentityEntity extends BaseEntity<mjBizAppsTasksGitHubGitHubIdentityEntityType> {
    /**
    * Loads the MJ_BizApps_Tasks_GitHub: Git Hub Identities record from the database
    * @param ID: string - primary key value to load the MJ_BizApps_Tasks_GitHub: Git Hub Identities record.
    * @param EntityRelationshipsToLoad - (optional) the relationships to load
    * @returns {Promise<boolean>} - true if successful, false otherwise
    * @public
    * @async
    * @memberof mjBizAppsTasksGitHubGitHubIdentityEntity
    * @method
    * @override
    */
    public async Load(ID: string, EntityRelationshipsToLoad?: string[]) : Promise<boolean> {
        const compositeKey: CompositeKey = new CompositeKey();
        compositeKey.KeyValuePairs.push({ FieldName: 'ID', Value: ID });
        return await super.InnerLoad(compositeKey, EntityRelationshipsToLoad);
    }

    /**
    * * Field Name: ID
    * * Display Name: ID
    * * SQL Data Type: uniqueidentifier
    * * Default Value: newsequentialid()
    */
    get ID(): string {
        return this.Get('ID');
    }
    set ID(value: string) {
        this.Set('ID', value);
    }

    /**
    * * Field Name: GitHubLogin
    * * Display Name: GitHub Login
    * * SQL Data Type: nvarchar(100)
    * * Description: Case-insensitive GitHub username / handle (e.g. octocat).
    */
    get GitHubLogin(): string {
        return this.Get('GitHubLogin');
    }
    set GitHubLogin(value: string) {
        this.Set('GitHubLogin', value);
    }

    /**
    * * Field Name: PersonID
    * * Display Name: Person
    * * SQL Data Type: uniqueidentifier
    * * Related Entity/Foreign Key: MJ_BizApps_Common: People (vwPeople.ID)
    * * Description: Target BizApps Common Person record associated with this GitHub login.
    */
    get PersonID(): string {
        return this.Get('PersonID');
    }
    set PersonID(value: string) {
        this.Set('PersonID', value);
    }

    /**
    * * Field Name: GitHubUserID
    * * Display Name: GitHub User ID
    * * SQL Data Type: nvarchar(64)
    * * Description: Optional numeric or GraphQL node identifier for the GitHub user account.
    */
    get GitHubUserID(): string | null {
        return this.Get('GitHubUserID');
    }
    set GitHubUserID(value: string | null) {
        this.Set('GitHubUserID', value);
    }

    /**
    * * Field Name: IsActive
    * * Display Name: Is Active
    * * SQL Data Type: bit
    * * Default Value: 1
    * * Description: Whether this login mapping is currently active for task import and assignment resolution.
    */
    get IsActive(): boolean {
        return this.Get('IsActive');
    }
    set IsActive(value: boolean) {
        this.Set('IsActive', value);
    }

    /**
    * * Field Name: __mj_CreatedAt
    * * Display Name: Created At
    * * SQL Data Type: datetimeoffset
    * * Default Value: getutcdate()
    */
    get __mj_CreatedAt(): Date {
        return this.Get('__mj_CreatedAt');
    }

    /**
    * * Field Name: __mj_UpdatedAt
    * * Display Name: Updated At
    * * SQL Data Type: datetimeoffset
    * * Default Value: getutcdate()
    */
    get __mj_UpdatedAt(): Date {
        return this.Get('__mj_UpdatedAt');
    }

    /**
    * * Field Name: Person
    * * Display Name: Person Name
    * * SQL Data Type: nvarchar(250)
    */
    get Person(): string | null {
        return this.Get('Person');
    }
}


/**
 * MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks - strongly typed entity sub-class
 * * Schema: __mj_BizAppsTasksGitHub
 * * Base Table: GitHubIssueTask
 * * Base View: vwGitHubIssueTasks
 * * @description Disjoint IS-A child of MJ_BizApps_Tasks: Tasks for GITHUB_ISSUE tasks, storing GitHub-owned issue metadata, milestone dates, and idempotent external sync keys.
 * * Primary Key: ID
 * @extends {BaseEntity}
 * @class
 * @public
 */
@RegisterClass(BaseEntity, 'MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks')
export class mjBizAppsTasksGitHubGitHubIssueTaskEntity extends BaseEntity<mjBizAppsTasksGitHubGitHubIssueTaskEntityType> {
    /**
    * Loads the MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks record from the database
    * @param ID: string - primary key value to load the MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks record.
    * @param EntityRelationshipsToLoad - (optional) the relationships to load
    * @returns {Promise<boolean>} - true if successful, false otherwise
    * @public
    * @async
    * @memberof mjBizAppsTasksGitHubGitHubIssueTaskEntity
    * @method
    * @override
    */
    public async Load(ID: string, EntityRelationshipsToLoad?: string[]) : Promise<boolean> {
        const compositeKey: CompositeKey = new CompositeKey();
        compositeKey.KeyValuePairs.push({ FieldName: 'ID', Value: ID });
        return await super.InnerLoad(compositeKey, EntityRelationshipsToLoad);
    }

    /**
    * * Field Name: ID
    * * Display Name: ID
    * * SQL Data Type: uniqueidentifier
    * * Related Entity/Foreign Key: MJ_BizApps_Tasks: Tasks (vwTasks.ID)
    * * Description: Shared primary key referencing __mj_BizAppsTasks.Task(ID).
    */
    get ID(): string {
        return this.Get('ID');
    }
    set ID(value: string) {
        this.Set('ID', value);
    }

    /**
    * * Field Name: RepositoryID
    * * Display Name: Repository ID
    * * SQL Data Type: uniqueidentifier
    * * Related Entity/Foreign Key: MJ_BizApps_Tasks_GitHub: Git Hub Repositories (vwGitHubRepositories.ID)
    * * Description: GitHubRepository to which this issue belongs.
    */
    get RepositoryID(): string | null {
        return this.Get('RepositoryID');
    }
    set RepositoryID(value: string | null) {
        this.Set('RepositoryID', value);
    }

    /**
    * * Field Name: Number
    * * Display Name: Issue Number
    * * SQL Data Type: int
    * * Description: Repository-scoped GitHub issue number (#N). Unique per RepositoryID when populated.
    */
    get Number(): number | null {
        return this.Get('Number');
    }
    set Number(value: number | null) {
        this.Set('Number', value);
    }

    /**
    * * Field Name: NodeID
    * * Display Name: Node ID
    * * SQL Data Type: nvarchar(128)
    * * Description: Global GitHub GraphQL node identifier for idempotent cross-rename sync.
    */
    get NodeID(): string | null {
        return this.Get('NodeID');
    }
    set NodeID(value: string | null) {
        this.Set('NodeID', value);
    }

    /**
    * * Field Name: HtmlURL
    * * Display Name: HTML URL
    * * SQL Data Type: nvarchar(1000)
    * * Description: Canonical browser URL to view or edit the issue on GitHub.
    */
    get HtmlURL(): string | null {
        return this.Get('HtmlURL');
    }
    set HtmlURL(value: string | null) {
        this.Set('HtmlURL', value);
    }

    /**
    * * Field Name: State
    * * Display Name: State
    * * SQL Data Type: nvarchar(20)
    * * Default Value: open
    * * Value List Type: List
    * * Possible Values 
    *   * closed
    *   * open
    * * Description: GitHub issue state (open or closed).
    */
    get State(): 'closed' | 'open' {
        return this.Get('State');
    }
    set State(value: 'closed' | 'open') {
        this.Set('State', value);
    }

    /**
    * * Field Name: StateReason
    * * Display Name: State Reason
    * * SQL Data Type: nvarchar(40)
    * * Value List Type: List
    * * Possible Values 
    *   * completed
    *   * duplicate
    *   * not_planned
    *   * reopened
    * * Description: Optional GitHub issue state_reason (completed, not_planned, reopened, duplicate).
    */
    get StateReason(): 'completed' | 'duplicate' | 'not_planned' | 'reopened' | null {
        return this.Get('StateReason');
    }
    set StateReason(value: 'completed' | 'duplicate' | 'not_planned' | 'reopened' | null) {
        this.Set('StateReason', value);
    }

    /**
    * * Field Name: Labels
    * * Display Name: Labels
    * * SQL Data Type: nvarchar(MAX)
    * * Description: JSON array of GitHub label names applied to the issue.
    */
    get Labels(): string | null {
        return this.Get('Labels');
    }
    set Labels(value: string | null) {
        this.Set('Labels', value);
    }

    /**
    * * Field Name: Milestone
    * * Display Name: Milestone
    * * SQL Data Type: nvarchar(255)
    * * Description: GitHub milestone title when assigned.
    */
    get Milestone(): string | null {
        return this.Get('Milestone');
    }
    set Milestone(value: string | null) {
        this.Set('Milestone', value);
    }

    /**
    * * Field Name: MilestoneDueAt
    * * Display Name: Milestone Due At
    * * SQL Data Type: datetimeoffset
    * * Description: Due timestamp of the GitHub milestone; supersedes pending inferred DueAt Field Suggestions.
    */
    get MilestoneDueAt(): Date | null {
        return this.Get('MilestoneDueAt');
    }
    set MilestoneDueAt(value: Date | null) {
        this.Set('MilestoneDueAt', value);
    }

    /**
    * * Field Name: AuthorLogin
    * * Display Name: Author Login
    * * SQL Data Type: nvarchar(100)
    * * Description: GitHub login of the user who opened the issue.
    */
    get AuthorLogin(): string | null {
        return this.Get('AuthorLogin');
    }
    set AuthorLogin(value: string | null) {
        this.Set('AuthorLogin', value);
    }

    /**
    * * Field Name: BodyHash
    * * Display Name: Body Hash
    * * SQL Data Type: nvarchar(64)
    * * Description: SHA-256 hash of the last synced issue body used to detect text edits and trigger Field Suggestion re-inference.
    */
    get BodyHash(): string | null {
        return this.Get('BodyHash');
    }
    set BodyHash(value: string | null) {
        this.Set('BodyHash', value);
    }

    /**
    * * Field Name: GitHubUpdatedAt
    * * Display Name: GitHub Updated At
    * * SQL Data Type: datetimeoffset
    * * Description: Upstream updated_at timestamp reported by GitHub.
    */
    get GitHubUpdatedAt(): Date | null {
        return this.Get('GitHubUpdatedAt');
    }
    set GitHubUpdatedAt(value: Date | null) {
        this.Set('GitHubUpdatedAt', value);
    }

    /**
    * * Field Name: LastSyncedAt
    * * Display Name: Last Synced At
    * * SQL Data Type: datetimeoffset
    * * Description: Timestamp when BizApps Tasks GitHub sync last reconciled this issue.
    */
    get LastSyncedAt(): Date | null {
        return this.Get('LastSyncedAt');
    }
    set LastSyncedAt(value: Date | null) {
        this.Set('LastSyncedAt', value);
    }

    /**
    * * Field Name: __mj_CreatedAt
    * * Display Name: Created At
    * * SQL Data Type: datetimeoffset
    * * Default Value: getutcdate()
    */
    get __mj_CreatedAt(): Date {
        return this.Get('__mj_CreatedAt');
    }

    /**
    * * Field Name: __mj_UpdatedAt
    * * Display Name: Updated At
    * * SQL Data Type: datetimeoffset
    * * Default Value: getutcdate()
    */
    get __mj_UpdatedAt(): Date {
        return this.Get('__mj_UpdatedAt');
    }

    /**
    * * Field Name: Name
    * * Display Name: Name
    * * SQL Data Type: nvarchar(255)
    * * IS-A Source: Inherited from MJ_BizApps_Tasks: Tasks
    */
    get Name(): string {
        return this.Get('Name');
    }
    set Name(value: string) {
        this.Set('Name', value);
    }

    /**
    * * Field Name: Description
    * * Display Name: Description
    * * SQL Data Type: nvarchar(MAX)
    * * IS-A Source: Inherited from MJ_BizApps_Tasks: Tasks
    */
    get Description(): string | null {
        return this.Get('Description');
    }
    set Description(value: string | null) {
        this.Set('Description', value);
    }

    /**
    * * Field Name: TypeID
    * * Display Name: Task Type
    * * SQL Data Type: uniqueidentifier
    * * Related Entity/Foreign Key: MJ_BizApps_Tasks: Task Types (vwTaskTypes.ID)
    * * IS-A Source: Inherited from MJ_BizApps_Tasks: Tasks
    */
    get TypeID(): string {
        return this.Get('TypeID');
    }
    set TypeID(value: string) {
        this.Set('TypeID', value);
    }

    /**
    * * Field Name: CategoryID
    * * Display Name: Category
    * * SQL Data Type: uniqueidentifier
    * * Related Entity/Foreign Key: MJ_BizApps_Tasks: Task Categories (vwTaskCategories.ID)
    * * IS-A Source: Inherited from MJ_BizApps_Tasks: Tasks
    */
    get CategoryID(): string | null {
        return this.Get('CategoryID');
    }
    set CategoryID(value: string | null) {
        this.Set('CategoryID', value);
    }

    /**
    * * Field Name: ParentID
    * * Display Name: Parent Task
    * * SQL Data Type: uniqueidentifier
    * * Related Entity/Foreign Key: MJ_BizApps_Tasks: Tasks (vwTasks.ID)
    * * IS-A Source: Inherited from MJ_BizApps_Tasks: Tasks
    */
    get ParentID(): string | null {
        return this.Get('ParentID');
    }
    set ParentID(value: string | null) {
        this.Set('ParentID', value);
    }

    /**
    * * Field Name: Status
    * * Display Name: Status
    * * SQL Data Type: nvarchar(50)
    * * IS-A Source: Inherited from MJ_BizApps_Tasks: Tasks
    */
    get Status(): string {
        return this.Get('Status');
    }
    set Status(value: string) {
        this.Set('Status', value);
    }

    /**
    * * Field Name: Priority
    * * Display Name: Priority
    * * SQL Data Type: nvarchar(20)
    * * IS-A Source: Inherited from MJ_BizApps_Tasks: Tasks
    */
    get Priority(): string {
        return this.Get('Priority');
    }
    set Priority(value: string) {
        this.Set('Priority', value);
    }

    /**
    * * Field Name: StartedAt
    * * Display Name: Started At
    * * SQL Data Type: datetimeoffset
    * * IS-A Source: Inherited from MJ_BizApps_Tasks: Tasks
    */
    get StartedAt(): Date | null {
        return this.Get('StartedAt');
    }
    set StartedAt(value: Date | null) {
        this.Set('StartedAt', value);
    }

    /**
    * * Field Name: DueAt
    * * Display Name: Due At
    * * SQL Data Type: datetimeoffset
    * * IS-A Source: Inherited from MJ_BizApps_Tasks: Tasks
    */
    get DueAt(): Date | null {
        return this.Get('DueAt');
    }
    set DueAt(value: Date | null) {
        this.Set('DueAt', value);
    }

    /**
    * * Field Name: CompletedAt
    * * Display Name: Completed At
    * * SQL Data Type: datetimeoffset
    * * IS-A Source: Inherited from MJ_BizApps_Tasks: Tasks
    */
    get CompletedAt(): Date | null {
        return this.Get('CompletedAt');
    }
    set CompletedAt(value: Date | null) {
        this.Set('CompletedAt', value);
    }

    /**
    * * Field Name: HoursEstimated
    * * Display Name: Hours Estimated
    * * SQL Data Type: decimal(8, 2)
    * * IS-A Source: Inherited from MJ_BizApps_Tasks: Tasks
    */
    get HoursEstimated(): number | null {
        return this.Get('HoursEstimated');
    }
    set HoursEstimated(value: number | null) {
        this.Set('HoursEstimated', value);
    }

    /**
    * * Field Name: HoursActual
    * * Display Name: Hours Actual
    * * SQL Data Type: decimal(8, 2)
    * * IS-A Source: Inherited from MJ_BizApps_Tasks: Tasks
    */
    get HoursActual(): number | null {
        return this.Get('HoursActual');
    }
    set HoursActual(value: number | null) {
        this.Set('HoursActual', value);
    }

    /**
    * * Field Name: PercentComplete
    * * Display Name: Percent Complete
    * * SQL Data Type: int
    * * IS-A Source: Inherited from MJ_BizApps_Tasks: Tasks
    */
    get PercentComplete(): number {
        return this.Get('PercentComplete');
    }
    set PercentComplete(value: number) {
        this.Set('PercentComplete', value);
    }

    /**
    * * Field Name: Sequence
    * * Display Name: Sequence
    * * SQL Data Type: int
    * * IS-A Source: Inherited from MJ_BizApps_Tasks: Tasks
    */
    get Sequence(): number {
        return this.Get('Sequence');
    }
    set Sequence(value: number) {
        this.Set('Sequence', value);
    }

    /**
    * * Field Name: BlockedReason
    * * Display Name: Blocked Reason
    * * SQL Data Type: nvarchar(MAX)
    * * IS-A Source: Inherited from MJ_BizApps_Tasks: Tasks
    */
    get BlockedReason(): string | null {
        return this.Get('BlockedReason');
    }
    set BlockedReason(value: string | null) {
        this.Set('BlockedReason', value);
    }

    /**
    * * Field Name: CompletionNotes
    * * Display Name: Completion Notes
    * * SQL Data Type: nvarchar(MAX)
    * * IS-A Source: Inherited from MJ_BizApps_Tasks: Tasks
    */
    get CompletionNotes(): string | null {
        return this.Get('CompletionNotes');
    }
    set CompletionNotes(value: string | null) {
        this.Set('CompletionNotes', value);
    }

    /**
    * * Field Name: CreatedByPersonID
    * * Display Name: Created By Person
    * * SQL Data Type: uniqueidentifier
    * * Related Entity/Foreign Key: MJ_BizApps_Common: People (vwPeople.ID)
    * * IS-A Source: Inherited from MJ_BizApps_Tasks: Tasks
    */
    get CreatedByPersonID(): string | null {
        return this.Get('CreatedByPersonID');
    }
    set CreatedByPersonID(value: string | null) {
        this.Set('CreatedByPersonID', value);
    }

    /**
    * * Field Name: OverdueNotifiedAt
    * * Display Name: Overdue Notified At
    * * SQL Data Type: datetimeoffset
    * * IS-A Source: Inherited from MJ_BizApps_Tasks: Tasks
    */
    get OverdueNotifiedAt(): Date | null {
        return this.Get('OverdueNotifiedAt');
    }
    set OverdueNotifiedAt(value: Date | null) {
        this.Set('OverdueNotifiedAt', value);
    }

    /**
    * * Field Name: TaskTypeStatusID
    * * Display Name: Task Type Status
    * * SQL Data Type: uniqueidentifier
    * * Related Entity/Foreign Key: MJ_BizApps_Tasks: Task Type Status (vwTaskTypeStatus.ID)
    * * IS-A Source: Inherited from MJ_BizApps_Tasks: Tasks
    */
    get TaskTypeStatusID(): string | null {
        return this.Get('TaskTypeStatusID');
    }
    set TaskTypeStatusID(value: string | null) {
        this.Set('TaskTypeStatusID', value);
    }

    /**
    * * Field Name: PredictedSLABreachProbability
    * * Display Name: Predicted SLA Breach Probability
    * * SQL Data Type: decimal(5, 4)
    * * IS-A Source: Inherited from MJ_BizApps_Tasks: Tasks
    */
    get PredictedSLABreachProbability(): number | null {
        return this.Get('PredictedSLABreachProbability');
    }
    set PredictedSLABreachProbability(value: number | null) {
        this.Set('PredictedSLABreachProbability', value);
    }

    /**
    * * Field Name: PredictedSLARiskBand
    * * Display Name: Predicted SLA Risk Band
    * * SQL Data Type: nvarchar(20)
    * * IS-A Source: Inherited from MJ_BizApps_Tasks: Tasks
    */
    get PredictedSLARiskBand(): string | null {
        return this.Get('PredictedSLARiskBand');
    }
    set PredictedSLARiskBand(value: string | null) {
        this.Set('PredictedSLARiskBand', value);
    }

    /**
    * * Field Name: PredictedSLAScoredAt
    * * Display Name: Predicted SLA Scored At
    * * SQL Data Type: datetimeoffset
    * * IS-A Source: Inherited from MJ_BizApps_Tasks: Tasks
    */
    get PredictedSLAScoredAt(): Date | null {
        return this.Get('PredictedSLAScoredAt');
    }
    set PredictedSLAScoredAt(value: Date | null) {
        this.Set('PredictedSLAScoredAt', value);
    }

    /**
    * * Field Name: HealthStatus
    * * Display Name: Health Status
    * * SQL Data Type: nvarchar(20)
    * * IS-A Source: Inherited from MJ_BizApps_Tasks: Tasks
    */
    get HealthStatus(): string | null {
        return this.Get('HealthStatus');
    }
    set HealthStatus(value: string | null) {
        this.Set('HealthStatus', value);
    }

    /**
    * * Field Name: ConfidenceScore
    * * Display Name: Confidence Score
    * * SQL Data Type: int
    * * IS-A Source: Inherited from MJ_BizApps_Tasks: Tasks
    */
    get ConfidenceScore(): number | null {
        return this.Get('ConfidenceScore');
    }
    set ConfidenceScore(value: number | null) {
        this.Set('ConfidenceScore', value);
    }

    /**
    * * Field Name: BaselineValue
    * * Display Name: Baseline Value
    * * SQL Data Type: decimal(18, 4)
    * * IS-A Source: Inherited from MJ_BizApps_Tasks: Tasks
    */
    get BaselineValue(): number | null {
        return this.Get('BaselineValue');
    }
    set BaselineValue(value: number | null) {
        this.Set('BaselineValue', value);
    }

    /**
    * * Field Name: TargetValue
    * * Display Name: Target Value
    * * SQL Data Type: decimal(18, 4)
    * * IS-A Source: Inherited from MJ_BizApps_Tasks: Tasks
    */
    get TargetValue(): number | null {
        return this.Get('TargetValue');
    }
    set TargetValue(value: number | null) {
        this.Set('TargetValue', value);
    }

    /**
    * * Field Name: CurrentValue
    * * Display Name: Current Value
    * * SQL Data Type: decimal(18, 4)
    * * IS-A Source: Inherited from MJ_BizApps_Tasks: Tasks
    */
    get CurrentValue(): number | null {
        return this.Get('CurrentValue');
    }
    set CurrentValue(value: number | null) {
        this.Set('CurrentValue', value);
    }

    /**
    * * Field Name: UnitOfMeasure
    * * Display Name: Unit Of Measure
    * * SQL Data Type: nvarchar(50)
    * * IS-A Source: Inherited from MJ_BizApps_Tasks: Tasks
    */
    get UnitOfMeasure(): string | null {
        return this.Get('UnitOfMeasure');
    }
    set UnitOfMeasure(value: string | null) {
        this.Set('UnitOfMeasure', value);
    }

    /**
    * * Field Name: MetricDirection
    * * Display Name: Metric Direction
    * * SQL Data Type: nvarchar(20)
    * * IS-A Source: Inherited from MJ_BizApps_Tasks: Tasks
    */
    get MetricDirection(): string | null {
        return this.Get('MetricDirection');
    }
    set MetricDirection(value: string | null) {
        this.Set('MetricDirection', value);
    }

    /**
    * * Field Name: RollupWeight
    * * Display Name: Rollup Weight
    * * SQL Data Type: decimal(8, 2)
    * * IS-A Source: Inherited from MJ_BizApps_Tasks: Tasks
    */
    get RollupWeight(): number {
        return this.Get('RollupWeight');
    }
    set RollupWeight(value: number) {
        this.Set('RollupWeight', value);
    }

    /**
    * * Field Name: PlanningPeriod
    * * Display Name: Planning Period
    * * SQL Data Type: nvarchar(50)
    * * IS-A Source: Inherited from MJ_BizApps_Tasks: Tasks
    */
    get PlanningPeriod(): string | null {
        return this.Get('PlanningPeriod');
    }
    set PlanningPeriod(value: string | null) {
        this.Set('PlanningPeriod', value);
    }

    /**
    * * Field Name: CheckInCadence
    * * Display Name: Check-In Cadence
    * * SQL Data Type: nvarchar(20)
    * * IS-A Source: Inherited from MJ_BizApps_Tasks: Tasks
    */
    get CheckInCadence(): string | null {
        return this.Get('CheckInCadence');
    }
    set CheckInCadence(value: string | null) {
        this.Set('CheckInCadence', value);
    }

    /**
    * * Field Name: LastCheckInAt
    * * Display Name: Last Check-In At
    * * SQL Data Type: datetimeoffset
    * * IS-A Source: Inherited from MJ_BizApps_Tasks: Tasks
    */
    get LastCheckInAt(): Date | null {
        return this.Get('LastCheckInAt');
    }
    set LastCheckInAt(value: Date | null) {
        this.Set('LastCheckInAt', value);
    }

    /**
    * * Field Name: NextCheckInDueAt
    * * Display Name: Next Check-In Due At
    * * SQL Data Type: datetimeoffset
    * * IS-A Source: Inherited from MJ_BizApps_Tasks: Tasks
    */
    get NextCheckInDueAt(): Date | null {
        return this.Get('NextCheckInDueAt');
    }
    set NextCheckInDueAt(value: Date | null) {
        this.Set('NextCheckInDueAt', value);
    }

    /**
    * * Field Name: Repository
    * * Display Name: Repository
    * * SQL Data Type: nvarchar(200)
    */
    get Repository(): string | null {
        return this.Get('Repository');
    }
}


/**
 * MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks - strongly typed entity sub-class
 * * Schema: __mj_BizAppsTasksGitHub
 * * Base Table: GitHubPullRequestTask
 * * Base View: vwGitHubPullRequestTasks
 * * @description Disjoint IS-A child of MJ_BizApps_Tasks: Tasks for GITHUB_PR tasks, storing pull request branches, head SHA, review decision, CI checks status, diff metrics, and linked issue Task.
 * * Primary Key: ID
 * @extends {BaseEntity}
 * @class
 * @public
 */
@RegisterClass(BaseEntity, 'MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks')
export class mjBizAppsTasksGitHubGitHubPullRequestTaskEntity extends BaseEntity<mjBizAppsTasksGitHubGitHubPullRequestTaskEntityType> {
    /**
    * Loads the MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks record from the database
    * @param ID: string - primary key value to load the MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks record.
    * @param EntityRelationshipsToLoad - (optional) the relationships to load
    * @returns {Promise<boolean>} - true if successful, false otherwise
    * @public
    * @async
    * @memberof mjBizAppsTasksGitHubGitHubPullRequestTaskEntity
    * @method
    * @override
    */
    public async Load(ID: string, EntityRelationshipsToLoad?: string[]) : Promise<boolean> {
        const compositeKey: CompositeKey = new CompositeKey();
        compositeKey.KeyValuePairs.push({ FieldName: 'ID', Value: ID });
        return await super.InnerLoad(compositeKey, EntityRelationshipsToLoad);
    }

    /**
    * * Field Name: ID
    * * Display Name: ID
    * * SQL Data Type: uniqueidentifier
    * * Related Entity/Foreign Key: MJ_BizApps_Tasks: Tasks (vwTasks.ID)
    * * Description: Shared primary key referencing __mj_BizAppsTasks.Task(ID).
    */
    get ID(): string {
        return this.Get('ID');
    }
    set ID(value: string) {
        this.Set('ID', value);
    }

    /**
    * * Field Name: RepositoryID
    * * Display Name: Repository ID
    * * SQL Data Type: uniqueidentifier
    * * Related Entity/Foreign Key: MJ_BizApps_Tasks_GitHub: Git Hub Repositories (vwGitHubRepositories.ID)
    * * Description: GitHubRepository to which this pull request belongs.
    */
    get RepositoryID(): string | null {
        return this.Get('RepositoryID');
    }
    set RepositoryID(value: string | null) {
        this.Set('RepositoryID', value);
    }

    /**
    * * Field Name: Number
    * * Display Name: Number
    * * SQL Data Type: int
    * * Description: Repository-scoped GitHub pull request number (#N). Unique per RepositoryID when populated.
    */
    get Number(): number | null {
        return this.Get('Number');
    }
    set Number(value: number | null) {
        this.Set('Number', value);
    }

    /**
    * * Field Name: NodeID
    * * Display Name: Node ID
    * * SQL Data Type: nvarchar(128)
    * * Description: Global GitHub GraphQL node identifier for idempotent sync.
    */
    get NodeID(): string | null {
        return this.Get('NodeID');
    }
    set NodeID(value: string | null) {
        this.Set('NodeID', value);
    }

    /**
    * * Field Name: HtmlURL
    * * Display Name: HTML URL
    * * SQL Data Type: nvarchar(1000)
    * * Description: Canonical browser URL to view or review the pull request on GitHub.
    */
    get HtmlURL(): string | null {
        return this.Get('HtmlURL');
    }
    set HtmlURL(value: string | null) {
        this.Set('HtmlURL', value);
    }

    /**
    * * Field Name: State
    * * Display Name: State
    * * SQL Data Type: nvarchar(20)
    * * Default Value: open
    * * Value List Type: List
    * * Possible Values 
    *   * closed
    *   * merged
    *   * open
    * * Description: Pull request lifecycle state on GitHub (open, closed, or merged).
    */
    get State(): 'closed' | 'merged' | 'open' {
        return this.Get('State');
    }
    set State(value: 'closed' | 'merged' | 'open') {
        this.Set('State', value);
    }

    /**
    * * Field Name: IsDraft
    * * Display Name: Is Draft
    * * SQL Data Type: bit
    * * Default Value: 0
    * * Description: Whether the pull request is currently marked as a Draft on GitHub.
    */
    get IsDraft(): boolean {
        return this.Get('IsDraft');
    }
    set IsDraft(value: boolean) {
        this.Set('IsDraft', value);
    }

    /**
    * * Field Name: HeadBranch
    * * Display Name: Head Branch
    * * SQL Data Type: nvarchar(255)
    * * Description: Source branch ref of the pull request (head.ref).
    */
    get HeadBranch(): string | null {
        return this.Get('HeadBranch');
    }
    set HeadBranch(value: string | null) {
        this.Set('HeadBranch', value);
    }

    /**
    * * Field Name: HeadSha
    * * Display Name: Head SHA
    * * SQL Data Type: nvarchar(64)
    * * Description: Commit SHA at the tip of HeadBranch (head.sha), verified by Software Factory merge gates.
    */
    get HeadSha(): string | null {
        return this.Get('HeadSha');
    }
    set HeadSha(value: string | null) {
        this.Set('HeadSha', value);
    }

    /**
    * * Field Name: BaseBranch
    * * Display Name: Base Branch
    * * SQL Data Type: nvarchar(255)
    * * Description: Target branch ref into which the pull request merges (base.ref).
    */
    get BaseBranch(): string | null {
        return this.Get('BaseBranch');
    }
    set BaseBranch(value: string | null) {
        this.Set('BaseBranch', value);
    }

    /**
    * * Field Name: AuthorLogin
    * * Display Name: Author Login
    * * SQL Data Type: nvarchar(100)
    * * Description: GitHub login of the pull request author.
    */
    get AuthorLogin(): string | null {
        return this.Get('AuthorLogin');
    }
    set AuthorLogin(value: string | null) {
        this.Set('AuthorLogin', value);
    }

    /**
    * * Field Name: ReviewDecision
    * * Display Name: Review Decision
    * * SQL Data Type: nvarchar(40)
    * * Value List Type: List
    * * Possible Values 
    *   * APPROVED
    *   * CHANGES_REQUESTED
    *   * REVIEW_REQUIRED
    * * Description: Aggregated GitHub review decision (APPROVED, CHANGES_REQUESTED, or REVIEW_REQUIRED).
    */
    get ReviewDecision(): 'APPROVED' | 'CHANGES_REQUESTED' | 'REVIEW_REQUIRED' | null {
        return this.Get('ReviewDecision');
    }
    set ReviewDecision(value: 'APPROVED' | 'CHANGES_REQUESTED' | 'REVIEW_REQUIRED' | null) {
        this.Set('ReviewDecision', value);
    }

    /**
    * * Field Name: ChecksStatus
    * * Display Name: Checks Status
    * * SQL Data Type: nvarchar(30)
    * * Value List Type: List
    * * Possible Values 
    *   * Failing
    *   * Neutral
    *   * Passing
    *   * Pending
    * * Description: Aggregated status of required GitHub CI checks on HeadSha (Pending, Passing, Failing, Neutral).
    */
    get ChecksStatus(): 'Failing' | 'Neutral' | 'Passing' | 'Pending' | null {
        return this.Get('ChecksStatus');
    }
    set ChecksStatus(value: 'Failing' | 'Neutral' | 'Passing' | 'Pending' | null) {
        this.Set('ChecksStatus', value);
    }

    /**
    * * Field Name: ChangedFiles
    * * Display Name: Changed Files
    * * SQL Data Type: int
    * * Description: Number of files touched in the pull request diff.
    */
    get ChangedFiles(): number | null {
        return this.Get('ChangedFiles');
    }
    set ChangedFiles(value: number | null) {
        this.Set('ChangedFiles', value);
    }

    /**
    * * Field Name: Additions
    * * Display Name: Additions
    * * SQL Data Type: int
    * * Description: Lines added in the pull request diff.
    */
    get Additions(): number | null {
        return this.Get('Additions');
    }
    set Additions(value: number | null) {
        this.Set('Additions', value);
    }

    /**
    * * Field Name: Deletions
    * * Display Name: Deletions
    * * SQL Data Type: int
    * * Description: Lines deleted in the pull request diff.
    */
    get Deletions(): number | null {
        return this.Get('Deletions');
    }
    set Deletions(value: number | null) {
        this.Set('Deletions', value);
    }

    /**
    * * Field Name: Labels
    * * Display Name: Labels
    * * SQL Data Type: nvarchar(MAX)
    * * Description: JSON array of GitHub label names applied to the pull request.
    */
    get Labels(): string | null {
        return this.Get('Labels');
    }
    set Labels(value: string | null) {
        this.Set('Labels', value);
    }

    /**
    * * Field Name: Milestone
    * * Display Name: Milestone
    * * SQL Data Type: nvarchar(255)
    * * Description: GitHub milestone title when assigned.
    */
    get Milestone(): string | null {
        return this.Get('Milestone');
    }
    set Milestone(value: string | null) {
        this.Set('Milestone', value);
    }

    /**
    * * Field Name: MilestoneDueAt
    * * Display Name: Milestone Due At
    * * SQL Data Type: datetimeoffset
    * * Description: Due timestamp of the GitHub milestone; supersedes pending inferred DueAt Field Suggestions.
    */
    get MilestoneDueAt(): Date | null {
        return this.Get('MilestoneDueAt');
    }
    set MilestoneDueAt(value: Date | null) {
        this.Set('MilestoneDueAt', value);
    }

    /**
    * * Field Name: MergedAt
    * * Display Name: Merged At
    * * SQL Data Type: datetimeoffset
    * * Description: Timestamp when the pull request was merged on GitHub.
    */
    get MergedAt(): Date | null {
        return this.Get('MergedAt');
    }
    set MergedAt(value: Date | null) {
        this.Set('MergedAt', value);
    }

    /**
    * * Field Name: LinkedIssueTaskID
    * * Display Name: Linked Issue Task ID
    * * SQL Data Type: uniqueidentifier
    * * Related Entity/Foreign Key: MJ_BizApps_Tasks: Tasks (vwTasks.ID)
    * * Description: Optional reference to the Task (e.g. GITHUB_ISSUE or FACTORY_WORK) that this pull request implements or closes.
    */
    get LinkedIssueTaskID(): string | null {
        return this.Get('LinkedIssueTaskID');
    }
    set LinkedIssueTaskID(value: string | null) {
        this.Set('LinkedIssueTaskID', value);
    }

    /**
    * * Field Name: BodyHash
    * * Display Name: Body Hash
    * * SQL Data Type: nvarchar(64)
    * * Description: SHA-256 hash of the last synced pull request body used to detect text edits and trigger Field Suggestion re-inference.
    */
    get BodyHash(): string | null {
        return this.Get('BodyHash');
    }
    set BodyHash(value: string | null) {
        this.Set('BodyHash', value);
    }

    /**
    * * Field Name: GitHubUpdatedAt
    * * Display Name: GitHub Updated At
    * * SQL Data Type: datetimeoffset
    * * Description: Upstream updated_at timestamp reported by GitHub.
    */
    get GitHubUpdatedAt(): Date | null {
        return this.Get('GitHubUpdatedAt');
    }
    set GitHubUpdatedAt(value: Date | null) {
        this.Set('GitHubUpdatedAt', value);
    }

    /**
    * * Field Name: LastSyncedAt
    * * Display Name: Last Synced At
    * * SQL Data Type: datetimeoffset
    * * Description: Timestamp when BizApps Tasks GitHub sync last reconciled this pull request.
    */
    get LastSyncedAt(): Date | null {
        return this.Get('LastSyncedAt');
    }
    set LastSyncedAt(value: Date | null) {
        this.Set('LastSyncedAt', value);
    }

    /**
    * * Field Name: __mj_CreatedAt
    * * Display Name: Created At
    * * SQL Data Type: datetimeoffset
    * * Default Value: getutcdate()
    */
    get __mj_CreatedAt(): Date {
        return this.Get('__mj_CreatedAt');
    }

    /**
    * * Field Name: __mj_UpdatedAt
    * * Display Name: Updated At
    * * SQL Data Type: datetimeoffset
    * * Default Value: getutcdate()
    */
    get __mj_UpdatedAt(): Date {
        return this.Get('__mj_UpdatedAt');
    }

    /**
    * * Field Name: Name
    * * Display Name: Name
    * * SQL Data Type: nvarchar(255)
    * * IS-A Source: Inherited from MJ_BizApps_Tasks: Tasks
    */
    get Name(): string {
        return this.Get('Name');
    }
    set Name(value: string) {
        this.Set('Name', value);
    }

    /**
    * * Field Name: Description
    * * Display Name: Description
    * * SQL Data Type: nvarchar(MAX)
    * * IS-A Source: Inherited from MJ_BizApps_Tasks: Tasks
    */
    get Description(): string | null {
        return this.Get('Description');
    }
    set Description(value: string | null) {
        this.Set('Description', value);
    }

    /**
    * * Field Name: TypeID
    * * Display Name: Type
    * * SQL Data Type: uniqueidentifier
    * * Related Entity/Foreign Key: MJ_BizApps_Tasks: Task Types (vwTaskTypes.ID)
    * * IS-A Source: Inherited from MJ_BizApps_Tasks: Tasks
    */
    get TypeID(): string {
        return this.Get('TypeID');
    }
    set TypeID(value: string) {
        this.Set('TypeID', value);
    }

    /**
    * * Field Name: CategoryID
    * * Display Name: Category
    * * SQL Data Type: uniqueidentifier
    * * Related Entity/Foreign Key: MJ_BizApps_Tasks: Task Categories (vwTaskCategories.ID)
    * * IS-A Source: Inherited from MJ_BizApps_Tasks: Tasks
    */
    get CategoryID(): string | null {
        return this.Get('CategoryID');
    }
    set CategoryID(value: string | null) {
        this.Set('CategoryID', value);
    }

    /**
    * * Field Name: ParentID
    * * Display Name: Parent Task
    * * SQL Data Type: uniqueidentifier
    * * Related Entity/Foreign Key: MJ_BizApps_Tasks: Tasks (vwTasks.ID)
    * * IS-A Source: Inherited from MJ_BizApps_Tasks: Tasks
    */
    get ParentID(): string | null {
        return this.Get('ParentID');
    }
    set ParentID(value: string | null) {
        this.Set('ParentID', value);
    }

    /**
    * * Field Name: Status
    * * Display Name: Status
    * * SQL Data Type: nvarchar(50)
    * * IS-A Source: Inherited from MJ_BizApps_Tasks: Tasks
    */
    get Status(): string {
        return this.Get('Status');
    }
    set Status(value: string) {
        this.Set('Status', value);
    }

    /**
    * * Field Name: Priority
    * * Display Name: Priority
    * * SQL Data Type: nvarchar(20)
    * * IS-A Source: Inherited from MJ_BizApps_Tasks: Tasks
    */
    get Priority(): string {
        return this.Get('Priority');
    }
    set Priority(value: string) {
        this.Set('Priority', value);
    }

    /**
    * * Field Name: StartedAt
    * * Display Name: Started At
    * * SQL Data Type: datetimeoffset
    * * IS-A Source: Inherited from MJ_BizApps_Tasks: Tasks
    */
    get StartedAt(): Date | null {
        return this.Get('StartedAt');
    }
    set StartedAt(value: Date | null) {
        this.Set('StartedAt', value);
    }

    /**
    * * Field Name: DueAt
    * * Display Name: Due At
    * * SQL Data Type: datetimeoffset
    * * IS-A Source: Inherited from MJ_BizApps_Tasks: Tasks
    */
    get DueAt(): Date | null {
        return this.Get('DueAt');
    }
    set DueAt(value: Date | null) {
        this.Set('DueAt', value);
    }

    /**
    * * Field Name: CompletedAt
    * * Display Name: Completed At
    * * SQL Data Type: datetimeoffset
    * * IS-A Source: Inherited from MJ_BizApps_Tasks: Tasks
    */
    get CompletedAt(): Date | null {
        return this.Get('CompletedAt');
    }
    set CompletedAt(value: Date | null) {
        this.Set('CompletedAt', value);
    }

    /**
    * * Field Name: HoursEstimated
    * * Display Name: Hours Estimated
    * * SQL Data Type: decimal(8, 2)
    * * IS-A Source: Inherited from MJ_BizApps_Tasks: Tasks
    */
    get HoursEstimated(): number | null {
        return this.Get('HoursEstimated');
    }
    set HoursEstimated(value: number | null) {
        this.Set('HoursEstimated', value);
    }

    /**
    * * Field Name: HoursActual
    * * Display Name: Hours Actual
    * * SQL Data Type: decimal(8, 2)
    * * IS-A Source: Inherited from MJ_BizApps_Tasks: Tasks
    */
    get HoursActual(): number | null {
        return this.Get('HoursActual');
    }
    set HoursActual(value: number | null) {
        this.Set('HoursActual', value);
    }

    /**
    * * Field Name: PercentComplete
    * * Display Name: Percent Complete
    * * SQL Data Type: int
    * * IS-A Source: Inherited from MJ_BizApps_Tasks: Tasks
    */
    get PercentComplete(): number {
        return this.Get('PercentComplete');
    }
    set PercentComplete(value: number) {
        this.Set('PercentComplete', value);
    }

    /**
    * * Field Name: Sequence
    * * Display Name: Sequence
    * * SQL Data Type: int
    * * IS-A Source: Inherited from MJ_BizApps_Tasks: Tasks
    */
    get Sequence(): number {
        return this.Get('Sequence');
    }
    set Sequence(value: number) {
        this.Set('Sequence', value);
    }

    /**
    * * Field Name: BlockedReason
    * * Display Name: Blocked Reason
    * * SQL Data Type: nvarchar(MAX)
    * * IS-A Source: Inherited from MJ_BizApps_Tasks: Tasks
    */
    get BlockedReason(): string | null {
        return this.Get('BlockedReason');
    }
    set BlockedReason(value: string | null) {
        this.Set('BlockedReason', value);
    }

    /**
    * * Field Name: CompletionNotes
    * * Display Name: Completion Notes
    * * SQL Data Type: nvarchar(MAX)
    * * IS-A Source: Inherited from MJ_BizApps_Tasks: Tasks
    */
    get CompletionNotes(): string | null {
        return this.Get('CompletionNotes');
    }
    set CompletionNotes(value: string | null) {
        this.Set('CompletionNotes', value);
    }

    /**
    * * Field Name: CreatedByPersonID
    * * Display Name: Created By Person
    * * SQL Data Type: uniqueidentifier
    * * Related Entity/Foreign Key: MJ_BizApps_Common: People (vwPeople.ID)
    * * IS-A Source: Inherited from MJ_BizApps_Tasks: Tasks
    */
    get CreatedByPersonID(): string | null {
        return this.Get('CreatedByPersonID');
    }
    set CreatedByPersonID(value: string | null) {
        this.Set('CreatedByPersonID', value);
    }

    /**
    * * Field Name: OverdueNotifiedAt
    * * Display Name: Overdue Notified At
    * * SQL Data Type: datetimeoffset
    * * IS-A Source: Inherited from MJ_BizApps_Tasks: Tasks
    */
    get OverdueNotifiedAt(): Date | null {
        return this.Get('OverdueNotifiedAt');
    }
    set OverdueNotifiedAt(value: Date | null) {
        this.Set('OverdueNotifiedAt', value);
    }

    /**
    * * Field Name: TaskTypeStatusID
    * * Display Name: Task Type Status
    * * SQL Data Type: uniqueidentifier
    * * Related Entity/Foreign Key: MJ_BizApps_Tasks: Task Type Status (vwTaskTypeStatus.ID)
    * * IS-A Source: Inherited from MJ_BizApps_Tasks: Tasks
    */
    get TaskTypeStatusID(): string | null {
        return this.Get('TaskTypeStatusID');
    }
    set TaskTypeStatusID(value: string | null) {
        this.Set('TaskTypeStatusID', value);
    }

    /**
    * * Field Name: PredictedSLABreachProbability
    * * Display Name: Predicted SLA Breach Probability
    * * SQL Data Type: decimal(5, 4)
    * * IS-A Source: Inherited from MJ_BizApps_Tasks: Tasks
    */
    get PredictedSLABreachProbability(): number | null {
        return this.Get('PredictedSLABreachProbability');
    }
    set PredictedSLABreachProbability(value: number | null) {
        this.Set('PredictedSLABreachProbability', value);
    }

    /**
    * * Field Name: PredictedSLARiskBand
    * * Display Name: Predicted SLA Risk Band
    * * SQL Data Type: nvarchar(20)
    * * IS-A Source: Inherited from MJ_BizApps_Tasks: Tasks
    */
    get PredictedSLARiskBand(): string | null {
        return this.Get('PredictedSLARiskBand');
    }
    set PredictedSLARiskBand(value: string | null) {
        this.Set('PredictedSLARiskBand', value);
    }

    /**
    * * Field Name: PredictedSLAScoredAt
    * * Display Name: Predicted SLA Scored At
    * * SQL Data Type: datetimeoffset
    * * IS-A Source: Inherited from MJ_BizApps_Tasks: Tasks
    */
    get PredictedSLAScoredAt(): Date | null {
        return this.Get('PredictedSLAScoredAt');
    }
    set PredictedSLAScoredAt(value: Date | null) {
        this.Set('PredictedSLAScoredAt', value);
    }

    /**
    * * Field Name: HealthStatus
    * * Display Name: Health Status
    * * SQL Data Type: nvarchar(20)
    * * IS-A Source: Inherited from MJ_BizApps_Tasks: Tasks
    */
    get HealthStatus(): string | null {
        return this.Get('HealthStatus');
    }
    set HealthStatus(value: string | null) {
        this.Set('HealthStatus', value);
    }

    /**
    * * Field Name: ConfidenceScore
    * * Display Name: Confidence Score
    * * SQL Data Type: int
    * * IS-A Source: Inherited from MJ_BizApps_Tasks: Tasks
    */
    get ConfidenceScore(): number | null {
        return this.Get('ConfidenceScore');
    }
    set ConfidenceScore(value: number | null) {
        this.Set('ConfidenceScore', value);
    }

    /**
    * * Field Name: BaselineValue
    * * Display Name: Baseline Value
    * * SQL Data Type: decimal(18, 4)
    * * IS-A Source: Inherited from MJ_BizApps_Tasks: Tasks
    */
    get BaselineValue(): number | null {
        return this.Get('BaselineValue');
    }
    set BaselineValue(value: number | null) {
        this.Set('BaselineValue', value);
    }

    /**
    * * Field Name: TargetValue
    * * Display Name: Target Value
    * * SQL Data Type: decimal(18, 4)
    * * IS-A Source: Inherited from MJ_BizApps_Tasks: Tasks
    */
    get TargetValue(): number | null {
        return this.Get('TargetValue');
    }
    set TargetValue(value: number | null) {
        this.Set('TargetValue', value);
    }

    /**
    * * Field Name: CurrentValue
    * * Display Name: Current Value
    * * SQL Data Type: decimal(18, 4)
    * * IS-A Source: Inherited from MJ_BizApps_Tasks: Tasks
    */
    get CurrentValue(): number | null {
        return this.Get('CurrentValue');
    }
    set CurrentValue(value: number | null) {
        this.Set('CurrentValue', value);
    }

    /**
    * * Field Name: UnitOfMeasure
    * * Display Name: Unit Of Measure
    * * SQL Data Type: nvarchar(50)
    * * IS-A Source: Inherited from MJ_BizApps_Tasks: Tasks
    */
    get UnitOfMeasure(): string | null {
        return this.Get('UnitOfMeasure');
    }
    set UnitOfMeasure(value: string | null) {
        this.Set('UnitOfMeasure', value);
    }

    /**
    * * Field Name: MetricDirection
    * * Display Name: Metric Direction
    * * SQL Data Type: nvarchar(20)
    * * IS-A Source: Inherited from MJ_BizApps_Tasks: Tasks
    */
    get MetricDirection(): string | null {
        return this.Get('MetricDirection');
    }
    set MetricDirection(value: string | null) {
        this.Set('MetricDirection', value);
    }

    /**
    * * Field Name: RollupWeight
    * * Display Name: Rollup Weight
    * * SQL Data Type: decimal(8, 2)
    * * IS-A Source: Inherited from MJ_BizApps_Tasks: Tasks
    */
    get RollupWeight(): number {
        return this.Get('RollupWeight');
    }
    set RollupWeight(value: number) {
        this.Set('RollupWeight', value);
    }

    /**
    * * Field Name: PlanningPeriod
    * * Display Name: Planning Period
    * * SQL Data Type: nvarchar(50)
    * * IS-A Source: Inherited from MJ_BizApps_Tasks: Tasks
    */
    get PlanningPeriod(): string | null {
        return this.Get('PlanningPeriod');
    }
    set PlanningPeriod(value: string | null) {
        this.Set('PlanningPeriod', value);
    }

    /**
    * * Field Name: CheckInCadence
    * * Display Name: Check In Cadence
    * * SQL Data Type: nvarchar(20)
    * * IS-A Source: Inherited from MJ_BizApps_Tasks: Tasks
    */
    get CheckInCadence(): string | null {
        return this.Get('CheckInCadence');
    }
    set CheckInCadence(value: string | null) {
        this.Set('CheckInCadence', value);
    }

    /**
    * * Field Name: LastCheckInAt
    * * Display Name: Last Check In At
    * * SQL Data Type: datetimeoffset
    * * IS-A Source: Inherited from MJ_BizApps_Tasks: Tasks
    */
    get LastCheckInAt(): Date | null {
        return this.Get('LastCheckInAt');
    }
    set LastCheckInAt(value: Date | null) {
        this.Set('LastCheckInAt', value);
    }

    /**
    * * Field Name: NextCheckInDueAt
    * * Display Name: Next Check In Due At
    * * SQL Data Type: datetimeoffset
    * * IS-A Source: Inherited from MJ_BizApps_Tasks: Tasks
    */
    get NextCheckInDueAt(): Date | null {
        return this.Get('NextCheckInDueAt');
    }
    set NextCheckInDueAt(value: Date | null) {
        this.Set('NextCheckInDueAt', value);
    }

    /**
    * * Field Name: Repository
    * * Display Name: Repository
    * * SQL Data Type: nvarchar(200)
    */
    get Repository(): string | null {
        return this.Get('Repository');
    }

    /**
    * * Field Name: LinkedIssueTask
    * * Display Name: Linked Issue Task
    * * SQL Data Type: nvarchar(255)
    */
    get LinkedIssueTask(): string | null {
        return this.Get('LinkedIssueTask');
    }
}


/**
 * MJ_BizApps_Tasks_GitHub: Git Hub Repositories - strongly typed entity sub-class
 * * Schema: __mj_BizAppsTasksGitHub
 * * Base Table: GitHubRepository
 * * Base View: vwGitHubRepositories
 * * @description GitHub repositories connected to BizApps Tasks, storing tracking controls, import filtering rules (AssignedOnly vs All), GitHub App installation IDs, client organization link, and optional Software Factory delivery policy reference.
 * * Primary Key: ID
 * @extends {BaseEntity}
 * @class
 * @public
 */
@RegisterClass(BaseEntity, 'MJ_BizApps_Tasks_GitHub: Git Hub Repositories')
export class mjBizAppsTasksGitHubGitHubRepositoryEntity extends BaseEntity<mjBizAppsTasksGitHubGitHubRepositoryEntityType> {
    /**
    * Loads the MJ_BizApps_Tasks_GitHub: Git Hub Repositories record from the database
    * @param ID: string - primary key value to load the MJ_BizApps_Tasks_GitHub: Git Hub Repositories record.
    * @param EntityRelationshipsToLoad - (optional) the relationships to load
    * @returns {Promise<boolean>} - true if successful, false otherwise
    * @public
    * @async
    * @memberof mjBizAppsTasksGitHubGitHubRepositoryEntity
    * @method
    * @override
    */
    public async Load(ID: string, EntityRelationshipsToLoad?: string[]) : Promise<boolean> {
        const compositeKey: CompositeKey = new CompositeKey();
        compositeKey.KeyValuePairs.push({ FieldName: 'ID', Value: ID });
        return await super.InnerLoad(compositeKey, EntityRelationshipsToLoad);
    }

    /**
    * * Field Name: ID
    * * Display Name: ID
    * * SQL Data Type: uniqueidentifier
    * * Default Value: newsequentialid()
    */
    get ID(): string {
        return this.Get('ID');
    }
    set ID(value: string) {
        this.Set('ID', value);
    }

    /**
    * * Field Name: Owner
    * * Display Name: Owner
    * * SQL Data Type: nvarchar(150)
    * * Description: GitHub organization or user login that owns the repository (e.g. MemberJunction).
    */
    get Owner(): string {
        return this.Get('Owner');
    }
    set Owner(value: string) {
        this.Set('Owner', value);
    }

    /**
    * * Field Name: Name
    * * Display Name: Name
    * * SQL Data Type: nvarchar(200)
    * * Description: Repository slug within the owner namespace (e.g. MJ, bizapps-tasks).
    */
    get Name(): string {
        return this.Get('Name');
    }
    set Name(value: string) {
        this.Set('Name', value);
    }

    /**
    * * Field Name: DefaultBranch
    * * Display Name: Default Branch
    * * SQL Data Type: nvarchar(120)
    * * Default Value: main
    * * Description: Default target branch name on GitHub (typically main or next).
    */
    get DefaultBranch(): string {
        return this.Get('DefaultBranch');
    }
    set DefaultBranch(value: string) {
        this.Set('DefaultBranch', value);
    }

    /**
    * * Field Name: IsTracked
    * * Display Name: Is Tracked
    * * SQL Data Type: bit
    * * Default Value: 1
    * * Description: When 1, periodic sync and incoming webhooks import eligible issues and pull requests into BizApps Tasks.
    */
    get IsTracked(): boolean {
        return this.Get('IsTracked');
    }
    set IsTracked(value: boolean) {
        this.Set('IsTracked', value);
    }

    /**
    * * Field Name: ImportRule
    * * Display Name: Import Rule
    * * SQL Data Type: nvarchar(20)
    * * Default Value: AssignedOnly
    * * Value List Type: List
    * * Possible Values 
    *   * All
    *   * AssignedOnly
    * * Description: Controls which issues and PRs become Tasks: AssignedOnly imports items assigned to or requesting review from a mapped GitHubIdentity; All imports every issue and PR in the repository.
    */
    get ImportRule(): 'All' | 'AssignedOnly' {
        return this.Get('ImportRule');
    }
    set ImportRule(value: 'All' | 'AssignedOnly') {
        this.Set('ImportRule', value);
    }

    /**
    * * Field Name: InstallationID
    * * Display Name: Installation ID
    * * SQL Data Type: nvarchar(100)
    * * Description: GitHub App installation identifier scoped to this repository or organization.
    */
    get InstallationID(): string | null {
        return this.Get('InstallationID');
    }
    set InstallationID(value: string | null) {
        this.Set('InstallationID', value);
    }

    /**
    * * Field Name: OrganizationID
    * * Display Name: Organization ID
    * * SQL Data Type: uniqueidentifier
    * * Related Entity/Foreign Key: MJ_BizApps_Common: Organizations (vwOrganizations.ID)
    * * Description: Optional client Organization in BizApps Common. Null denotes an internal repository; non-null enables Client-layer DeliveryPolicy inheritance.
    */
    get OrganizationID(): string | null {
        return this.Get('OrganizationID');
    }
    set OrganizationID(value: string | null) {
        this.Set('OrganizationID', value);
    }

    /**
    * * Field Name: DeliveryPolicyID
    * * Display Name: Delivery Policy ID
    * * SQL Data Type: uniqueidentifier
    * * Description: Optional UUID of the repository-level DeliveryPolicy in bizapps-software-factory when installed.
    */
    get DeliveryPolicyID(): string | null {
        return this.Get('DeliveryPolicyID');
    }
    set DeliveryPolicyID(value: string | null) {
        this.Set('DeliveryPolicyID', value);
    }

    /**
    * * Field Name: __mj_CreatedAt
    * * Display Name: Created At
    * * SQL Data Type: datetimeoffset
    * * Default Value: getutcdate()
    */
    get __mj_CreatedAt(): Date {
        return this.Get('__mj_CreatedAt');
    }

    /**
    * * Field Name: __mj_UpdatedAt
    * * Display Name: Updated At
    * * SQL Data Type: datetimeoffset
    * * Default Value: getutcdate()
    */
    get __mj_UpdatedAt(): Date {
        return this.Get('__mj_UpdatedAt');
    }

    /**
    * * Field Name: Organization
    * * Display Name: Organization
    * * SQL Data Type: nvarchar(255)
    */
    get Organization(): string | null {
        return this.Get('Organization');
    }
}
