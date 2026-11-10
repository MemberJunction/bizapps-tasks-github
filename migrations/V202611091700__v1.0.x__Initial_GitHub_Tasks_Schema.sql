-- =============================================================================
-- BizAppsTasksGitHub: Initial Schema & IS-A Task Subtype Tables
-- Provides:
--   1. GitHubRepository — tracked GitHub repositories, import rules, GitHub App
--      installation IDs, client Organization link, and optional DeliveryPolicyID.
--   2. GitHubIdentity   — maps GitHub logins to BizApps Common Person records so
--      assignees and requested reviewers become TaskAssignment rows.
--   3. GitHubIssueTask  — disjoint IS-A child of __mj_BizAppsTasks.Task for
--      GITHUB_ISSUE tasks with idempotent keys on (RepositoryID, Number) & NodeID.
--   4. GitHubPullRequestTask — disjoint IS-A child of __mj_BizAppsTasks.Task for
--      GITHUB_PR tasks with idempotent keys, review/checks status, & linked issue.
-- =============================================================================

---------------------------------------------------------------------------
-- 1. GitHubRepository
---------------------------------------------------------------------------
CREATE TABLE [${flyway:defaultSchema}].[GitHubRepository] (
    [ID] UNIQUEIDENTIFIER NOT NULL CONSTRAINT [DF_GitHubRepository_ID] DEFAULT (NEWSEQUENTIALID()),
    [Owner] NVARCHAR(150) NOT NULL,
    [Name] NVARCHAR(200) NOT NULL,
    [DefaultBranch] NVARCHAR(120) NOT NULL CONSTRAINT [DF_GitHubRepository_DefaultBranch] DEFAULT ('main'),
    [IsTracked] BIT NOT NULL CONSTRAINT [DF_GitHubRepository_IsTracked] DEFAULT (1),
    [ImportRule] NVARCHAR(20) NOT NULL CONSTRAINT [DF_GitHubRepository_ImportRule] DEFAULT ('AssignedOnly'),
    [InstallationID] NVARCHAR(100) NULL,
    [OrganizationID] UNIQUEIDENTIFIER NULL,
    [DeliveryPolicyID] UNIQUEIDENTIFIER NULL,
    CONSTRAINT [PK_GitHubRepository] PRIMARY KEY ([ID]),
    CONSTRAINT [UQ_GitHubRepository_Owner_Name] UNIQUE ([Owner], [Name]),
    CONSTRAINT [FK_GitHubRepository_Organization] FOREIGN KEY ([OrganizationID]) REFERENCES [__mj_BizAppsCommon].[Organization]([ID]),
    CONSTRAINT [CK_GitHubRepository_ImportRule] CHECK ([ImportRule] IN ('AssignedOnly', 'All'))
);
GO

CREATE INDEX [IX_GitHubRepository_IsTracked]
    ON [${flyway:defaultSchema}].[GitHubRepository] ([IsTracked]);
GO

EXEC sp_addextendedproperty
    @name = N'MS_Description',
    @value = N'GitHub repositories connected to BizApps Tasks, storing tracking controls, import filtering rules (AssignedOnly vs All), GitHub App installation IDs, client organization link, and optional Software Factory delivery policy reference.',
    @level0type = N'SCHEMA', @level0name = N'${flyway:defaultSchema}',
    @level1type = N'TABLE',  @level1name = N'GitHubRepository';
GO

EXEC sp_addextendedproperty
    @name = N'MS_Description',
    @value = N'GitHub organization or user login that owns the repository (e.g. MemberJunction).',
    @level0type = N'SCHEMA', @level0name = N'${flyway:defaultSchema}',
    @level1type = N'TABLE',  @level1name = N'GitHubRepository',
    @level2type = N'COLUMN', @level2name = N'Owner';
GO

EXEC sp_addextendedproperty
    @name = N'MS_Description',
    @value = N'Repository slug within the owner namespace (e.g. MJ, bizapps-tasks).',
    @level0type = N'SCHEMA', @level0name = N'${flyway:defaultSchema}',
    @level1type = N'TABLE',  @level1name = N'GitHubRepository',
    @level2type = N'COLUMN', @level2name = N'Name';
GO

EXEC sp_addextendedproperty
    @name = N'MS_Description',
    @value = N'Default target branch name on GitHub (typically main or next).',
    @level0type = N'SCHEMA', @level0name = N'${flyway:defaultSchema}',
    @level1type = N'TABLE',  @level1name = N'GitHubRepository',
    @level2type = N'COLUMN', @level2name = N'DefaultBranch';
GO

EXEC sp_addextendedproperty
    @name = N'MS_Description',
    @value = N'When 1, periodic sync and incoming webhooks import eligible issues and pull requests into BizApps Tasks.',
    @level0type = N'SCHEMA', @level0name = N'${flyway:defaultSchema}',
    @level1type = N'TABLE',  @level1name = N'GitHubRepository',
    @level2type = N'COLUMN', @level2name = N'IsTracked';
GO

EXEC sp_addextendedproperty
    @name = N'MS_Description',
    @value = N'Controls which issues and PRs become Tasks: AssignedOnly imports items assigned to or requesting review from a mapped GitHubIdentity; All imports every issue and PR in the repository.',
    @level0type = N'SCHEMA', @level0name = N'${flyway:defaultSchema}',
    @level1type = N'TABLE',  @level1name = N'GitHubRepository',
    @level2type = N'COLUMN', @level2name = N'ImportRule';
GO

EXEC sp_addextendedproperty
    @name = N'MS_Description',
    @value = N'GitHub App installation identifier scoped to this repository or organization.',
    @level0type = N'SCHEMA', @level0name = N'${flyway:defaultSchema}',
    @level1type = N'TABLE',  @level1name = N'GitHubRepository',
    @level2type = N'COLUMN', @level2name = N'InstallationID';
GO

EXEC sp_addextendedproperty
    @name = N'MS_Description',
    @value = N'Optional client Organization in BizApps Common. Null denotes an internal repository; non-null enables Client-layer DeliveryPolicy inheritance.',
    @level0type = N'SCHEMA', @level0name = N'${flyway:defaultSchema}',
    @level1type = N'TABLE',  @level1name = N'GitHubRepository',
    @level2type = N'COLUMN', @level2name = N'OrganizationID';
GO

EXEC sp_addextendedproperty
    @name = N'MS_Description',
    @value = N'Optional UUID of the repository-level DeliveryPolicy in bizapps-software-factory when installed.',
    @level0type = N'SCHEMA', @level0name = N'${flyway:defaultSchema}',
    @level1type = N'TABLE',  @level1name = N'GitHubRepository',
    @level2type = N'COLUMN', @level2name = N'DeliveryPolicyID';
GO

---------------------------------------------------------------------------
-- 2. GitHubIdentity
---------------------------------------------------------------------------
CREATE TABLE [${flyway:defaultSchema}].[GitHubIdentity] (
    [ID] UNIQUEIDENTIFIER NOT NULL CONSTRAINT [DF_GitHubIdentity_ID] DEFAULT (NEWSEQUENTIALID()),
    [GitHubLogin] NVARCHAR(100) NOT NULL,
    [PersonID] UNIQUEIDENTIFIER NOT NULL,
    [GitHubUserID] NVARCHAR(64) NULL,
    [IsActive] BIT NOT NULL CONSTRAINT [DF_GitHubIdentity_IsActive] DEFAULT (1),
    CONSTRAINT [PK_GitHubIdentity] PRIMARY KEY ([ID]),
    CONSTRAINT [UQ_GitHubIdentity_Login] UNIQUE ([GitHubLogin]),
    CONSTRAINT [FK_GitHubIdentity_Person] FOREIGN KEY ([PersonID]) REFERENCES [__mj_BizAppsCommon].[Person]([ID])
);
GO

EXEC sp_addextendedproperty
    @name = N'MS_Description',
    @value = N'Maps GitHub user logins to BizApps Common Person records so GitHub issue/PR assignees and requested reviewers synchronize into Primary and Reviewer TaskAssignment rows.',
    @level0type = N'SCHEMA', @level0name = N'${flyway:defaultSchema}',
    @level1type = N'TABLE',  @level1name = N'GitHubIdentity';
GO

EXEC sp_addextendedproperty
    @name = N'MS_Description',
    @value = N'Case-insensitive GitHub username / handle (e.g. octocat).',
    @level0type = N'SCHEMA', @level0name = N'${flyway:defaultSchema}',
    @level1type = N'TABLE',  @level1name = N'GitHubIdentity',
    @level2type = N'COLUMN', @level2name = N'GitHubLogin';
GO

EXEC sp_addextendedproperty
    @name = N'MS_Description',
    @value = N'Target BizApps Common Person record associated with this GitHub login.',
    @level0type = N'SCHEMA', @level0name = N'${flyway:defaultSchema}',
    @level1type = N'TABLE',  @level1name = N'GitHubIdentity',
    @level2type = N'COLUMN', @level2name = N'PersonID';
GO

EXEC sp_addextendedproperty
    @name = N'MS_Description',
    @value = N'Optional numeric or GraphQL node identifier for the GitHub user account.',
    @level0type = N'SCHEMA', @level0name = N'${flyway:defaultSchema}',
    @level1type = N'TABLE',  @level1name = N'GitHubIdentity',
    @level2type = N'COLUMN', @level2name = N'GitHubUserID';
GO

EXEC sp_addextendedproperty
    @name = N'MS_Description',
    @value = N'Whether this login mapping is currently active for task import and assignment resolution.',
    @level0type = N'SCHEMA', @level0name = N'${flyway:defaultSchema}',
    @level1type = N'TABLE',  @level1name = N'GitHubIdentity',
    @level2type = N'COLUMN', @level2name = N'IsActive';
GO

---------------------------------------------------------------------------
-- 3. GitHubIssueTask (IS-A Disjoint Child of __mj_BizAppsTasks.Task)
---------------------------------------------------------------------------
CREATE TABLE [${flyway:defaultSchema}].[GitHubIssueTask] (
    [ID] UNIQUEIDENTIFIER NOT NULL,
    [RepositoryID] UNIQUEIDENTIFIER NULL,
    [Number] INT NULL,
    [NodeID] NVARCHAR(128) NULL,
    [HtmlURL] NVARCHAR(1000) NULL,
    [State] NVARCHAR(20) NOT NULL CONSTRAINT [DF_GitHubIssueTask_State] DEFAULT ('open'),
    [StateReason] NVARCHAR(40) NULL,
    [Labels] NVARCHAR(MAX) NULL,
    [Milestone] NVARCHAR(255) NULL,
    [MilestoneDueAt] DATETIMEOFFSET NULL,
    [AuthorLogin] NVARCHAR(100) NULL,
    [BodyHash] NVARCHAR(64) NULL,
    [GitHubUpdatedAt] DATETIMEOFFSET NULL,
    [LastSyncedAt] DATETIMEOFFSET NULL,
    CONSTRAINT [PK_GitHubIssueTask] PRIMARY KEY ([ID]),
    CONSTRAINT [FK_GitHubIssueTask_Task] FOREIGN KEY ([ID]) REFERENCES [__mj_BizAppsTasks].[Task]([ID]),
    CONSTRAINT [FK_GitHubIssueTask_Repository] FOREIGN KEY ([RepositoryID]) REFERENCES [${flyway:defaultSchema}].[GitHubRepository]([ID]),
    CONSTRAINT [CK_GitHubIssueTask_State] CHECK ([State] IN ('open', 'closed')),
    CONSTRAINT [CK_GitHubIssueTask_StateReason] CHECK ([StateReason] IS NULL OR [StateReason] IN ('completed', 'not_planned', 'reopened', 'duplicate'))
);
GO

CREATE UNIQUE INDEX [UX_GitHubIssueTask_Repo_Number]
    ON [${flyway:defaultSchema}].[GitHubIssueTask] ([RepositoryID], [Number])
    WHERE [RepositoryID] IS NOT NULL AND [Number] IS NOT NULL;
GO

CREATE UNIQUE INDEX [UX_GitHubIssueTask_NodeID]
    ON [${flyway:defaultSchema}].[GitHubIssueTask] ([NodeID])
    WHERE [NodeID] IS NOT NULL;
GO

EXEC sp_addextendedproperty
    @name = N'MS_Description',
    @value = N'Disjoint IS-A child of MJ_BizApps_Tasks: Tasks for GITHUB_ISSUE tasks, storing GitHub-owned issue metadata, milestone dates, and idempotent external sync keys.',
    @level0type = N'SCHEMA', @level0name = N'${flyway:defaultSchema}',
    @level1type = N'TABLE',  @level1name = N'GitHubIssueTask';
GO

EXEC sp_addextendedproperty
    @name = N'MS_Description',
    @value = N'Shared primary key referencing __mj_BizAppsTasks.Task(ID).',
    @level0type = N'SCHEMA', @level0name = N'${flyway:defaultSchema}',
    @level1type = N'TABLE',  @level1name = N'GitHubIssueTask',
    @level2type = N'COLUMN', @level2name = N'ID';
GO

EXEC sp_addextendedproperty
    @name = N'MS_Description',
    @value = N'GitHubRepository to which this issue belongs.',
    @level0type = N'SCHEMA', @level0name = N'${flyway:defaultSchema}',
    @level1type = N'TABLE',  @level1name = N'GitHubIssueTask',
    @level2type = N'COLUMN', @level2name = N'RepositoryID';
GO

EXEC sp_addextendedproperty
    @name = N'MS_Description',
    @value = N'Repository-scoped GitHub issue number (#N). Unique per RepositoryID when populated.',
    @level0type = N'SCHEMA', @level0name = N'${flyway:defaultSchema}',
    @level1type = N'TABLE',  @level1name = N'GitHubIssueTask',
    @level2type = N'COLUMN', @level2name = N'Number';
GO

EXEC sp_addextendedproperty
    @name = N'MS_Description',
    @value = N'Global GitHub GraphQL node identifier for idempotent cross-rename sync.',
    @level0type = N'SCHEMA', @level0name = N'${flyway:defaultSchema}',
    @level1type = N'TABLE',  @level1name = N'GitHubIssueTask',
    @level2type = N'COLUMN', @level2name = N'NodeID';
GO

EXEC sp_addextendedproperty
    @name = N'MS_Description',
    @value = N'Canonical browser URL to view or edit the issue on GitHub.',
    @level0type = N'SCHEMA', @level0name = N'${flyway:defaultSchema}',
    @level1type = N'TABLE',  @level1name = N'GitHubIssueTask',
    @level2type = N'COLUMN', @level2name = N'HtmlURL';
GO

EXEC sp_addextendedproperty
    @name = N'MS_Description',
    @value = N'GitHub issue state (open or closed).',
    @level0type = N'SCHEMA', @level0name = N'${flyway:defaultSchema}',
    @level1type = N'TABLE',  @level1name = N'GitHubIssueTask',
    @level2type = N'COLUMN', @level2name = N'State';
GO

EXEC sp_addextendedproperty
    @name = N'MS_Description',
    @value = N'Optional GitHub issue state_reason (completed, not_planned, reopened, duplicate).',
    @level0type = N'SCHEMA', @level0name = N'${flyway:defaultSchema}',
    @level1type = N'TABLE',  @level1name = N'GitHubIssueTask',
    @level2type = N'COLUMN', @level2name = N'StateReason';
GO

EXEC sp_addextendedproperty
    @name = N'MS_Description',
    @value = N'JSON array of GitHub label names applied to the issue.',
    @level0type = N'SCHEMA', @level0name = N'${flyway:defaultSchema}',
    @level1type = N'TABLE',  @level1name = N'GitHubIssueTask',
    @level2type = N'COLUMN', @level2name = N'Labels';
GO

EXEC sp_addextendedproperty
    @name = N'MS_Description',
    @value = N'GitHub milestone title when assigned.',
    @level0type = N'SCHEMA', @level0name = N'${flyway:defaultSchema}',
    @level1type = N'TABLE',  @level1name = N'GitHubIssueTask',
    @level2type = N'COLUMN', @level2name = N'Milestone';
GO

EXEC sp_addextendedproperty
    @name = N'MS_Description',
    @value = N'Due timestamp of the GitHub milestone; supersedes pending inferred DueAt Field Suggestions.',
    @level0type = N'SCHEMA', @level0name = N'${flyway:defaultSchema}',
    @level1type = N'TABLE',  @level1name = N'GitHubIssueTask',
    @level2type = N'COLUMN', @level2name = N'MilestoneDueAt';
GO

EXEC sp_addextendedproperty
    @name = N'MS_Description',
    @value = N'GitHub login of the user who opened the issue.',
    @level0type = N'SCHEMA', @level0name = N'${flyway:defaultSchema}',
    @level1type = N'TABLE',  @level1name = N'GitHubIssueTask',
    @level2type = N'COLUMN', @level2name = N'AuthorLogin';
GO

EXEC sp_addextendedproperty
    @name = N'MS_Description',
    @value = N'SHA-256 hash of the last synced issue body used to detect text edits and trigger Field Suggestion re-inference.',
    @level0type = N'SCHEMA', @level0name = N'${flyway:defaultSchema}',
    @level1type = N'TABLE',  @level1name = N'GitHubIssueTask',
    @level2type = N'COLUMN', @level2name = N'BodyHash';
GO

EXEC sp_addextendedproperty
    @name = N'MS_Description',
    @value = N'Upstream updated_at timestamp reported by GitHub.',
    @level0type = N'SCHEMA', @level0name = N'${flyway:defaultSchema}',
    @level1type = N'TABLE',  @level1name = N'GitHubIssueTask',
    @level2type = N'COLUMN', @level2name = N'GitHubUpdatedAt';
GO

EXEC sp_addextendedproperty
    @name = N'MS_Description',
    @value = N'Timestamp when BizApps Tasks GitHub sync last reconciled this issue.',
    @level0type = N'SCHEMA', @level0name = N'${flyway:defaultSchema}',
    @level1type = N'TABLE',  @level1name = N'GitHubIssueTask',
    @level2type = N'COLUMN', @level2name = N'LastSyncedAt';
GO

---------------------------------------------------------------------------
-- 4. GitHubPullRequestTask (IS-A Disjoint Child of __mj_BizAppsTasks.Task)
---------------------------------------------------------------------------
CREATE TABLE [${flyway:defaultSchema}].[GitHubPullRequestTask] (
    [ID] UNIQUEIDENTIFIER NOT NULL,
    [RepositoryID] UNIQUEIDENTIFIER NULL,
    [Number] INT NULL,
    [NodeID] NVARCHAR(128) NULL,
    [HtmlURL] NVARCHAR(1000) NULL,
    [State] NVARCHAR(20) NOT NULL CONSTRAINT [DF_GitHubPRTask_State] DEFAULT ('open'),
    [IsDraft] BIT NOT NULL CONSTRAINT [DF_GitHubPRTask_IsDraft] DEFAULT (0),
    [HeadBranch] NVARCHAR(255) NULL,
    [HeadSha] NVARCHAR(64) NULL,
    [BaseBranch] NVARCHAR(255) NULL,
    [AuthorLogin] NVARCHAR(100) NULL,
    [ReviewDecision] NVARCHAR(40) NULL,
    [ChecksStatus] NVARCHAR(30) NULL,
    [ChangedFiles] INT NULL,
    [Additions] INT NULL,
    [Deletions] INT NULL,
    [Labels] NVARCHAR(MAX) NULL,
    [Milestone] NVARCHAR(255) NULL,
    [MilestoneDueAt] DATETIMEOFFSET NULL,
    [MergedAt] DATETIMEOFFSET NULL,
    [LinkedIssueTaskID] UNIQUEIDENTIFIER NULL,
    [BodyHash] NVARCHAR(64) NULL,
    [GitHubUpdatedAt] DATETIMEOFFSET NULL,
    [LastSyncedAt] DATETIMEOFFSET NULL,
    CONSTRAINT [PK_GitHubPullRequestTask] PRIMARY KEY ([ID]),
    CONSTRAINT [FK_GitHubPRTask_Task] FOREIGN KEY ([ID]) REFERENCES [__mj_BizAppsTasks].[Task]([ID]),
    CONSTRAINT [FK_GitHubPRTask_Repository] FOREIGN KEY ([RepositoryID]) REFERENCES [${flyway:defaultSchema}].[GitHubRepository]([ID]),
    CONSTRAINT [FK_GitHubPRTask_LinkedIssueTask] FOREIGN KEY ([LinkedIssueTaskID]) REFERENCES [__mj_BizAppsTasks].[Task]([ID]),
    CONSTRAINT [CK_GitHubPRTask_State] CHECK ([State] IN ('open', 'closed', 'merged')),
    CONSTRAINT [CK_GitHubPRTask_ReviewDecision] CHECK ([ReviewDecision] IS NULL OR [ReviewDecision] IN ('APPROVED', 'CHANGES_REQUESTED', 'REVIEW_REQUIRED')),
    CONSTRAINT [CK_GitHubPRTask_ChecksStatus] CHECK ([ChecksStatus] IS NULL OR [ChecksStatus] IN ('Pending', 'Passing', 'Failing', 'Neutral'))
);
GO

CREATE UNIQUE INDEX [UX_GitHubPRTask_Repo_Number]
    ON [${flyway:defaultSchema}].[GitHubPullRequestTask] ([RepositoryID], [Number])
    WHERE [RepositoryID] IS NOT NULL AND [Number] IS NOT NULL;
GO

CREATE UNIQUE INDEX [UX_GitHubPRTask_NodeID]
    ON [${flyway:defaultSchema}].[GitHubPullRequestTask] ([NodeID])
    WHERE [NodeID] IS NOT NULL;
GO

EXEC sp_addextendedproperty
    @name = N'MS_Description',
    @value = N'Disjoint IS-A child of MJ_BizApps_Tasks: Tasks for GITHUB_PR tasks, storing pull request branches, head SHA, review decision, CI checks status, diff metrics, and linked issue Task.',
    @level0type = N'SCHEMA', @level0name = N'${flyway:defaultSchema}',
    @level1type = N'TABLE',  @level1name = N'GitHubPullRequestTask';
GO

EXEC sp_addextendedproperty
    @name = N'MS_Description',
    @value = N'Shared primary key referencing __mj_BizAppsTasks.Task(ID).',
    @level0type = N'SCHEMA', @level0name = N'${flyway:defaultSchema}',
    @level1type = N'TABLE',  @level1name = N'GitHubPullRequestTask',
    @level2type = N'COLUMN', @level2name = N'ID';
GO

EXEC sp_addextendedproperty
    @name = N'MS_Description',
    @value = N'GitHubRepository to which this pull request belongs.',
    @level0type = N'SCHEMA', @level0name = N'${flyway:defaultSchema}',
    @level1type = N'TABLE',  @level1name = N'GitHubPullRequestTask',
    @level2type = N'COLUMN', @level2name = N'RepositoryID';
GO

EXEC sp_addextendedproperty
    @name = N'MS_Description',
    @value = N'Repository-scoped GitHub pull request number (#N). Unique per RepositoryID when populated.',
    @level0type = N'SCHEMA', @level0name = N'${flyway:defaultSchema}',
    @level1type = N'TABLE',  @level1name = N'GitHubPullRequestTask',
    @level2type = N'COLUMN', @level2name = N'Number';
GO

EXEC sp_addextendedproperty
    @name = N'MS_Description',
    @value = N'Global GitHub GraphQL node identifier for idempotent sync.',
    @level0type = N'SCHEMA', @level0name = N'${flyway:defaultSchema}',
    @level1type = N'TABLE',  @level1name = N'GitHubPullRequestTask',
    @level2type = N'COLUMN', @level2name = N'NodeID';
GO

EXEC sp_addextendedproperty
    @name = N'MS_Description',
    @value = N'Canonical browser URL to view or review the pull request on GitHub.',
    @level0type = N'SCHEMA', @level0name = N'${flyway:defaultSchema}',
    @level1type = N'TABLE',  @level1name = N'GitHubPullRequestTask',
    @level2type = N'COLUMN', @level2name = N'HtmlURL';
GO

EXEC sp_addextendedproperty
    @name = N'MS_Description',
    @value = N'Pull request lifecycle state on GitHub (open, closed, or merged).',
    @level0type = N'SCHEMA', @level0name = N'${flyway:defaultSchema}',
    @level1type = N'TABLE',  @level1name = N'GitHubPullRequestTask',
    @level2type = N'COLUMN', @level2name = N'State';
GO

EXEC sp_addextendedproperty
    @name = N'MS_Description',
    @value = N'Whether the pull request is currently marked as a Draft on GitHub.',
    @level0type = N'SCHEMA', @level0name = N'${flyway:defaultSchema}',
    @level1type = N'TABLE',  @level1name = N'GitHubPullRequestTask',
    @level2type = N'COLUMN', @level2name = N'IsDraft';
GO

EXEC sp_addextendedproperty
    @name = N'MS_Description',
    @value = N'Source branch ref of the pull request (head.ref).',
    @level0type = N'SCHEMA', @level0name = N'${flyway:defaultSchema}',
    @level1type = N'TABLE',  @level1name = N'GitHubPullRequestTask',
    @level2type = N'COLUMN', @level2name = N'HeadBranch';
GO

EXEC sp_addextendedproperty
    @name = N'MS_Description',
    @value = N'Commit SHA at the tip of HeadBranch (head.sha), verified by Software Factory merge gates.',
    @level0type = N'SCHEMA', @level0name = N'${flyway:defaultSchema}',
    @level1type = N'TABLE',  @level1name = N'GitHubPullRequestTask',
    @level2type = N'COLUMN', @level2name = N'HeadSha';
GO

EXEC sp_addextendedproperty
    @name = N'MS_Description',
    @value = N'Target branch ref into which the pull request merges (base.ref).',
    @level0type = N'SCHEMA', @level0name = N'${flyway:defaultSchema}',
    @level1type = N'TABLE',  @level1name = N'GitHubPullRequestTask',
    @level2type = N'COLUMN', @level2name = N'BaseBranch';
GO

EXEC sp_addextendedproperty
    @name = N'MS_Description',
    @value = N'GitHub login of the pull request author.',
    @level0type = N'SCHEMA', @level0name = N'${flyway:defaultSchema}',
    @level1type = N'TABLE',  @level1name = N'GitHubPullRequestTask',
    @level2type = N'COLUMN', @level2name = N'AuthorLogin';
GO

EXEC sp_addextendedproperty
    @name = N'MS_Description',
    @value = N'Aggregated GitHub review decision (APPROVED, CHANGES_REQUESTED, or REVIEW_REQUIRED).',
    @level0type = N'SCHEMA', @level0name = N'${flyway:defaultSchema}',
    @level1type = N'TABLE',  @level1name = N'GitHubPullRequestTask',
    @level2type = N'COLUMN', @level2name = N'ReviewDecision';
GO

EXEC sp_addextendedproperty
    @name = N'MS_Description',
    @value = N'Aggregated status of required GitHub CI checks on HeadSha (Pending, Passing, Failing, Neutral).',
    @level0type = N'SCHEMA', @level0name = N'${flyway:defaultSchema}',
    @level1type = N'TABLE',  @level1name = N'GitHubPullRequestTask',
    @level2type = N'COLUMN', @level2name = N'ChecksStatus';
GO

EXEC sp_addextendedproperty
    @name = N'MS_Description',
    @value = N'Number of files touched in the pull request diff.',
    @level0type = N'SCHEMA', @level0name = N'${flyway:defaultSchema}',
    @level1type = N'TABLE',  @level1name = N'GitHubPullRequestTask',
    @level2type = N'COLUMN', @level2name = N'ChangedFiles';
GO

EXEC sp_addextendedproperty
    @name = N'MS_Description',
    @value = N'Lines added in the pull request diff.',
    @level0type = N'SCHEMA', @level0name = N'${flyway:defaultSchema}',
    @level1type = N'TABLE',  @level1name = N'GitHubPullRequestTask',
    @level2type = N'COLUMN', @level2name = N'Additions';
GO

EXEC sp_addextendedproperty
    @name = N'MS_Description',
    @value = N'Lines deleted in the pull request diff.',
    @level0type = N'SCHEMA', @level0name = N'${flyway:defaultSchema}',
    @level1type = N'TABLE',  @level1name = N'GitHubPullRequestTask',
    @level2type = N'COLUMN', @level2name = N'Deletions';
GO

EXEC sp_addextendedproperty
    @name = N'MS_Description',
    @value = N'JSON array of GitHub label names applied to the pull request.',
    @level0type = N'SCHEMA', @level0name = N'${flyway:defaultSchema}',
    @level1type = N'TABLE',  @level1name = N'GitHubPullRequestTask',
    @level2type = N'COLUMN', @level2name = N'Labels';
GO

EXEC sp_addextendedproperty
    @name = N'MS_Description',
    @value = N'GitHub milestone title when assigned.',
    @level0type = N'SCHEMA', @level0name = N'${flyway:defaultSchema}',
    @level1type = N'TABLE',  @level1name = N'GitHubPullRequestTask',
    @level2type = N'COLUMN', @level2name = N'Milestone';
GO

EXEC sp_addextendedproperty
    @name = N'MS_Description',
    @value = N'Due timestamp of the GitHub milestone; supersedes pending inferred DueAt Field Suggestions.',
    @level0type = N'SCHEMA', @level0name = N'${flyway:defaultSchema}',
    @level1type = N'TABLE',  @level1name = N'GitHubPullRequestTask',
    @level2type = N'COLUMN', @level2name = N'MilestoneDueAt';
GO

EXEC sp_addextendedproperty
    @name = N'MS_Description',
    @value = N'Timestamp when the pull request was merged on GitHub.',
    @level0type = N'SCHEMA', @level0name = N'${flyway:defaultSchema}',
    @level1type = N'TABLE',  @level1name = N'GitHubPullRequestTask',
    @level2type = N'COLUMN', @level2name = N'MergedAt';
GO

EXEC sp_addextendedproperty
    @name = N'MS_Description',
    @value = N'Optional reference to the Task (e.g. GITHUB_ISSUE or FACTORY_WORK) that this pull request implements or closes.',
    @level0type = N'SCHEMA', @level0name = N'${flyway:defaultSchema}',
    @level1type = N'TABLE',  @level1name = N'GitHubPullRequestTask',
    @level2type = N'COLUMN', @level2name = N'LinkedIssueTaskID';
GO

EXEC sp_addextendedproperty
    @name = N'MS_Description',
    @value = N'SHA-256 hash of the last synced pull request body used to detect text edits and trigger Field Suggestion re-inference.',
    @level0type = N'SCHEMA', @level0name = N'${flyway:defaultSchema}',
    @level1type = N'TABLE',  @level1name = N'GitHubPullRequestTask',
    @level2type = N'COLUMN', @level2name = N'BodyHash';
GO

EXEC sp_addextendedproperty
    @name = N'MS_Description',
    @value = N'Upstream updated_at timestamp reported by GitHub.',
    @level0type = N'SCHEMA', @level0name = N'${flyway:defaultSchema}',
    @level1type = N'TABLE',  @level1name = N'GitHubPullRequestTask',
    @level2type = N'COLUMN', @level2name = N'GitHubUpdatedAt';
GO

EXEC sp_addextendedproperty
    @name = N'MS_Description',
    @value = N'Timestamp when BizApps Tasks GitHub sync last reconciled this pull request.',
    @level0type = N'SCHEMA', @level0name = N'${flyway:defaultSchema}',
    @level1type = N'TABLE',  @level1name = N'GitHubPullRequestTask',
    @level2type = N'COLUMN', @level2name = N'LastSyncedAt';
GO























































-- =============================================================================
-- GENERATED BY MemberJunction CodeGen — DO NOT EDIT BY HAND
-- =============================================================================

/* SQL generated to create new entity MJ_BizApps_Tasks_GitHub: Git Hub Repositories */

      INSERT INTO [${mjSchema}].[Entity] (
         [ID],
         [Name],
         [DisplayName],
         [Description],
         [NameSuffix],
         [BaseTable],
         [BaseView],
         [SchemaName],
         [IncludeInAPI],
         [AllowUserSearchAPI],
         [AllowCaching],
         [TrackRecordChanges],
         [AuditRecordAccess],
         [AuditViewRuns],
         [AllowAllRowsAPI],
         [AllowCreateAPI],
         [AllowUpdateAPI],
         [AllowDeleteAPI],
         [UserViewMaxRows]
         , [__mj_CreatedAt]
         , [__mj_UpdatedAt]
      )
      VALUES (
         '6b363236-31ab-477d-8188-08f5fa9942ef',
         'MJ_BizApps_Tasks_GitHub: Git Hub Repositories',
         'Git Hub Repositories',
         'GitHub repositories connected to BizApps Tasks, storing tracking controls, import filtering rules (AssignedOnly vs All), GitHub App installation IDs, client organization link, and optional Software Factory delivery policy reference.',
         NULL,
         'GitHubRepository',
         'vwGitHubRepositories',
         '${flyway:defaultSchema}',
         1,
         1,
         0,
         1,
         0,
         0,
         0,
         1,
         1,
         1,
         1000
         , GETUTCDATE()
         , GETUTCDATE()
      );

/* SQL generated to add new permission for entity MJ_BizApps_Tasks_GitHub: Git Hub Repositories for role UI */
INSERT INTO [${mjSchema}].[EntityPermission]
                ([EntityID], [RoleID], [Type], [CanRead], [CanCreate], [CanUpdate], [CanDelete], [__mj_CreatedAt], [__mj_UpdatedAt])
              SELECT CAST('6b363236-31ab-477d-8188-08f5fa9942ef' AS uniqueidentifier), CAST('E0AFCCEC-6A37-EF11-86D4-000D3A4E707E' AS uniqueidentifier), 'Allow', 1, 0, 0, 0, GETUTCDATE(), GETUTCDATE()
              WHERE NOT EXISTS (
                SELECT 1 FROM [${mjSchema}].[EntityPermission]
                WHERE [EntityID] = CAST('6b363236-31ab-477d-8188-08f5fa9942ef' AS uniqueidentifier) AND [RoleID] = CAST('E0AFCCEC-6A37-EF11-86D4-000D3A4E707E' AS uniqueidentifier) AND [Type] = 'Allow'
              );

/* SQL generated to add new permission for entity MJ_BizApps_Tasks_GitHub: Git Hub Repositories for role Developer */
INSERT INTO [${mjSchema}].[EntityPermission]
                ([EntityID], [RoleID], [Type], [CanRead], [CanCreate], [CanUpdate], [CanDelete], [__mj_CreatedAt], [__mj_UpdatedAt])
              SELECT CAST('6b363236-31ab-477d-8188-08f5fa9942ef' AS uniqueidentifier), CAST('DEAFCCEC-6A37-EF11-86D4-000D3A4E707E' AS uniqueidentifier), 'Allow', 1, 1, 1, 1, GETUTCDATE(), GETUTCDATE()
              WHERE NOT EXISTS (
                SELECT 1 FROM [${mjSchema}].[EntityPermission]
                WHERE [EntityID] = CAST('6b363236-31ab-477d-8188-08f5fa9942ef' AS uniqueidentifier) AND [RoleID] = CAST('DEAFCCEC-6A37-EF11-86D4-000D3A4E707E' AS uniqueidentifier) AND [Type] = 'Allow'
              );

/* SQL generated to add new permission for entity MJ_BizApps_Tasks_GitHub: Git Hub Repositories for role Integration */
INSERT INTO [${mjSchema}].[EntityPermission]
                ([EntityID], [RoleID], [Type], [CanRead], [CanCreate], [CanUpdate], [CanDelete], [__mj_CreatedAt], [__mj_UpdatedAt])
              SELECT CAST('6b363236-31ab-477d-8188-08f5fa9942ef' AS uniqueidentifier), CAST('DFAFCCEC-6A37-EF11-86D4-000D3A4E707E' AS uniqueidentifier), 'Allow', 1, 1, 1, 1, GETUTCDATE(), GETUTCDATE()
              WHERE NOT EXISTS (
                SELECT 1 FROM [${mjSchema}].[EntityPermission]
                WHERE [EntityID] = CAST('6b363236-31ab-477d-8188-08f5fa9942ef' AS uniqueidentifier) AND [RoleID] = CAST('DFAFCCEC-6A37-EF11-86D4-000D3A4E707E' AS uniqueidentifier) AND [Type] = 'Allow'
              );

/* SQL generated to create new entity MJ_BizApps_Tasks_GitHub: Git Hub Identities */

      INSERT INTO [${mjSchema}].[Entity] (
         [ID],
         [Name],
         [DisplayName],
         [Description],
         [NameSuffix],
         [BaseTable],
         [BaseView],
         [SchemaName],
         [IncludeInAPI],
         [AllowUserSearchAPI],
         [AllowCaching],
         [TrackRecordChanges],
         [AuditRecordAccess],
         [AuditViewRuns],
         [AllowAllRowsAPI],
         [AllowCreateAPI],
         [AllowUpdateAPI],
         [AllowDeleteAPI],
         [UserViewMaxRows]
         , [__mj_CreatedAt]
         , [__mj_UpdatedAt]
      )
      VALUES (
         'c7cc2bcf-090e-4832-89c7-a051f302c393',
         'MJ_BizApps_Tasks_GitHub: Git Hub Identities',
         'Git Hub Identities',
         'Maps GitHub user logins to BizApps Common Person records so GitHub issue/PR assignees and requested reviewers synchronize into Primary and Reviewer TaskAssignment rows.',
         NULL,
         'GitHubIdentity',
         'vwGitHubIdentities',
         '${flyway:defaultSchema}',
         1,
         1,
         0,
         1,
         0,
         0,
         0,
         1,
         1,
         1,
         1000
         , GETUTCDATE()
         , GETUTCDATE()
      );

/* SQL generated to add new permission for entity MJ_BizApps_Tasks_GitHub: Git Hub Identities for role UI */
INSERT INTO [${mjSchema}].[EntityPermission]
                ([EntityID], [RoleID], [Type], [CanRead], [CanCreate], [CanUpdate], [CanDelete], [__mj_CreatedAt], [__mj_UpdatedAt])
              SELECT CAST('c7cc2bcf-090e-4832-89c7-a051f302c393' AS uniqueidentifier), CAST('E0AFCCEC-6A37-EF11-86D4-000D3A4E707E' AS uniqueidentifier), 'Allow', 1, 0, 0, 0, GETUTCDATE(), GETUTCDATE()
              WHERE NOT EXISTS (
                SELECT 1 FROM [${mjSchema}].[EntityPermission]
                WHERE [EntityID] = CAST('c7cc2bcf-090e-4832-89c7-a051f302c393' AS uniqueidentifier) AND [RoleID] = CAST('E0AFCCEC-6A37-EF11-86D4-000D3A4E707E' AS uniqueidentifier) AND [Type] = 'Allow'
              );

/* SQL generated to add new permission for entity MJ_BizApps_Tasks_GitHub: Git Hub Identities for role Developer */
INSERT INTO [${mjSchema}].[EntityPermission]
                ([EntityID], [RoleID], [Type], [CanRead], [CanCreate], [CanUpdate], [CanDelete], [__mj_CreatedAt], [__mj_UpdatedAt])
              SELECT CAST('c7cc2bcf-090e-4832-89c7-a051f302c393' AS uniqueidentifier), CAST('DEAFCCEC-6A37-EF11-86D4-000D3A4E707E' AS uniqueidentifier), 'Allow', 1, 1, 1, 1, GETUTCDATE(), GETUTCDATE()
              WHERE NOT EXISTS (
                SELECT 1 FROM [${mjSchema}].[EntityPermission]
                WHERE [EntityID] = CAST('c7cc2bcf-090e-4832-89c7-a051f302c393' AS uniqueidentifier) AND [RoleID] = CAST('DEAFCCEC-6A37-EF11-86D4-000D3A4E707E' AS uniqueidentifier) AND [Type] = 'Allow'
              );

/* SQL generated to add new permission for entity MJ_BizApps_Tasks_GitHub: Git Hub Identities for role Integration */
INSERT INTO [${mjSchema}].[EntityPermission]
                ([EntityID], [RoleID], [Type], [CanRead], [CanCreate], [CanUpdate], [CanDelete], [__mj_CreatedAt], [__mj_UpdatedAt])
              SELECT CAST('c7cc2bcf-090e-4832-89c7-a051f302c393' AS uniqueidentifier), CAST('DFAFCCEC-6A37-EF11-86D4-000D3A4E707E' AS uniqueidentifier), 'Allow', 1, 1, 1, 1, GETUTCDATE(), GETUTCDATE()
              WHERE NOT EXISTS (
                SELECT 1 FROM [${mjSchema}].[EntityPermission]
                WHERE [EntityID] = CAST('c7cc2bcf-090e-4832-89c7-a051f302c393' AS uniqueidentifier) AND [RoleID] = CAST('DFAFCCEC-6A37-EF11-86D4-000D3A4E707E' AS uniqueidentifier) AND [Type] = 'Allow'
              );

/* SQL generated to create new entity MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks */

      INSERT INTO [${mjSchema}].[Entity] (
         [ID],
         [Name],
         [DisplayName],
         [Description],
         [NameSuffix],
         [BaseTable],
         [BaseView],
         [SchemaName],
         [IncludeInAPI],
         [AllowUserSearchAPI],
         [AllowCaching],
         [TrackRecordChanges],
         [AuditRecordAccess],
         [AuditViewRuns],
         [AllowAllRowsAPI],
         [AllowCreateAPI],
         [AllowUpdateAPI],
         [AllowDeleteAPI],
         [UserViewMaxRows]
         , [__mj_CreatedAt]
         , [__mj_UpdatedAt]
      )
      VALUES (
         'dc8e0f5b-e172-4fd5-b648-8b4544f8c605',
         'MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks',
         'Git Hub Issue Tasks',
         'Disjoint IS-A child of MJ_BizApps_Tasks: Tasks for GITHUB_ISSUE tasks, storing GitHub-owned issue metadata, milestone dates, and idempotent external sync keys.',
         NULL,
         'GitHubIssueTask',
         'vwGitHubIssueTasks',
         '${flyway:defaultSchema}',
         1,
         1,
         0,
         1,
         0,
         0,
         0,
         1,
         1,
         1,
         1000
         , GETUTCDATE()
         , GETUTCDATE()
      );

/* SQL generated to add new permission for entity MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks for role UI */
INSERT INTO [${mjSchema}].[EntityPermission]
                ([EntityID], [RoleID], [Type], [CanRead], [CanCreate], [CanUpdate], [CanDelete], [__mj_CreatedAt], [__mj_UpdatedAt])
              SELECT CAST('dc8e0f5b-e172-4fd5-b648-8b4544f8c605' AS uniqueidentifier), CAST('E0AFCCEC-6A37-EF11-86D4-000D3A4E707E' AS uniqueidentifier), 'Allow', 1, 0, 0, 0, GETUTCDATE(), GETUTCDATE()
              WHERE NOT EXISTS (
                SELECT 1 FROM [${mjSchema}].[EntityPermission]
                WHERE [EntityID] = CAST('dc8e0f5b-e172-4fd5-b648-8b4544f8c605' AS uniqueidentifier) AND [RoleID] = CAST('E0AFCCEC-6A37-EF11-86D4-000D3A4E707E' AS uniqueidentifier) AND [Type] = 'Allow'
              );

/* SQL generated to add new permission for entity MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks for role Developer */
INSERT INTO [${mjSchema}].[EntityPermission]
                ([EntityID], [RoleID], [Type], [CanRead], [CanCreate], [CanUpdate], [CanDelete], [__mj_CreatedAt], [__mj_UpdatedAt])
              SELECT CAST('dc8e0f5b-e172-4fd5-b648-8b4544f8c605' AS uniqueidentifier), CAST('DEAFCCEC-6A37-EF11-86D4-000D3A4E707E' AS uniqueidentifier), 'Allow', 1, 1, 1, 1, GETUTCDATE(), GETUTCDATE()
              WHERE NOT EXISTS (
                SELECT 1 FROM [${mjSchema}].[EntityPermission]
                WHERE [EntityID] = CAST('dc8e0f5b-e172-4fd5-b648-8b4544f8c605' AS uniqueidentifier) AND [RoleID] = CAST('DEAFCCEC-6A37-EF11-86D4-000D3A4E707E' AS uniqueidentifier) AND [Type] = 'Allow'
              );

/* SQL generated to add new permission for entity MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks for role Integration */
INSERT INTO [${mjSchema}].[EntityPermission]
                ([EntityID], [RoleID], [Type], [CanRead], [CanCreate], [CanUpdate], [CanDelete], [__mj_CreatedAt], [__mj_UpdatedAt])
              SELECT CAST('dc8e0f5b-e172-4fd5-b648-8b4544f8c605' AS uniqueidentifier), CAST('DFAFCCEC-6A37-EF11-86D4-000D3A4E707E' AS uniqueidentifier), 'Allow', 1, 1, 1, 1, GETUTCDATE(), GETUTCDATE()
              WHERE NOT EXISTS (
                SELECT 1 FROM [${mjSchema}].[EntityPermission]
                WHERE [EntityID] = CAST('dc8e0f5b-e172-4fd5-b648-8b4544f8c605' AS uniqueidentifier) AND [RoleID] = CAST('DFAFCCEC-6A37-EF11-86D4-000D3A4E707E' AS uniqueidentifier) AND [Type] = 'Allow'
              );

/* SQL generated to create new entity MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks */

      INSERT INTO [${mjSchema}].[Entity] (
         [ID],
         [Name],
         [DisplayName],
         [Description],
         [NameSuffix],
         [BaseTable],
         [BaseView],
         [SchemaName],
         [IncludeInAPI],
         [AllowUserSearchAPI],
         [AllowCaching],
         [TrackRecordChanges],
         [AuditRecordAccess],
         [AuditViewRuns],
         [AllowAllRowsAPI],
         [AllowCreateAPI],
         [AllowUpdateAPI],
         [AllowDeleteAPI],
         [UserViewMaxRows]
         , [__mj_CreatedAt]
         , [__mj_UpdatedAt]
      )
      VALUES (
         'a6b673f8-43bc-4875-aff6-ac620592822e',
         'MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks',
         'Git Hub Pull Request Tasks',
         'Disjoint IS-A child of MJ_BizApps_Tasks: Tasks for GITHUB_PR tasks, storing pull request branches, head SHA, review decision, CI checks status, diff metrics, and linked issue Task.',
         NULL,
         'GitHubPullRequestTask',
         'vwGitHubPullRequestTasks',
         '${flyway:defaultSchema}',
         1,
         1,
         0,
         1,
         0,
         0,
         0,
         1,
         1,
         1,
         1000
         , GETUTCDATE()
         , GETUTCDATE()
      );

/* SQL generated to add new permission for entity MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks for role UI */
INSERT INTO [${mjSchema}].[EntityPermission]
                ([EntityID], [RoleID], [Type], [CanRead], [CanCreate], [CanUpdate], [CanDelete], [__mj_CreatedAt], [__mj_UpdatedAt])
              SELECT CAST('a6b673f8-43bc-4875-aff6-ac620592822e' AS uniqueidentifier), CAST('E0AFCCEC-6A37-EF11-86D4-000D3A4E707E' AS uniqueidentifier), 'Allow', 1, 0, 0, 0, GETUTCDATE(), GETUTCDATE()
              WHERE NOT EXISTS (
                SELECT 1 FROM [${mjSchema}].[EntityPermission]
                WHERE [EntityID] = CAST('a6b673f8-43bc-4875-aff6-ac620592822e' AS uniqueidentifier) AND [RoleID] = CAST('E0AFCCEC-6A37-EF11-86D4-000D3A4E707E' AS uniqueidentifier) AND [Type] = 'Allow'
              );

/* SQL generated to add new permission for entity MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks for role Developer */
INSERT INTO [${mjSchema}].[EntityPermission]
                ([EntityID], [RoleID], [Type], [CanRead], [CanCreate], [CanUpdate], [CanDelete], [__mj_CreatedAt], [__mj_UpdatedAt])
              SELECT CAST('a6b673f8-43bc-4875-aff6-ac620592822e' AS uniqueidentifier), CAST('DEAFCCEC-6A37-EF11-86D4-000D3A4E707E' AS uniqueidentifier), 'Allow', 1, 1, 1, 1, GETUTCDATE(), GETUTCDATE()
              WHERE NOT EXISTS (
                SELECT 1 FROM [${mjSchema}].[EntityPermission]
                WHERE [EntityID] = CAST('a6b673f8-43bc-4875-aff6-ac620592822e' AS uniqueidentifier) AND [RoleID] = CAST('DEAFCCEC-6A37-EF11-86D4-000D3A4E707E' AS uniqueidentifier) AND [Type] = 'Allow'
              );

/* SQL generated to add new permission for entity MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks for role Integration */
INSERT INTO [${mjSchema}].[EntityPermission]
                ([EntityID], [RoleID], [Type], [CanRead], [CanCreate], [CanUpdate], [CanDelete], [__mj_CreatedAt], [__mj_UpdatedAt])
              SELECT CAST('a6b673f8-43bc-4875-aff6-ac620592822e' AS uniqueidentifier), CAST('DFAFCCEC-6A37-EF11-86D4-000D3A4E707E' AS uniqueidentifier), 'Allow', 1, 1, 1, 1, GETUTCDATE(), GETUTCDATE()
              WHERE NOT EXISTS (
                SELECT 1 FROM [${mjSchema}].[EntityPermission]
                WHERE [EntityID] = CAST('a6b673f8-43bc-4875-aff6-ac620592822e' AS uniqueidentifier) AND [RoleID] = CAST('DFAFCCEC-6A37-EF11-86D4-000D3A4E707E' AS uniqueidentifier) AND [Type] = 'Allow'
              );

/* SQL text to update existing entities from schema */
EXEC [${mjSchema}].[spUpdateExistingEntitiesFromSchema] @ExcludedSchemaNames='', @IncludedSchemaNames='${flyway:defaultSchema}';

/* SQL text to add special date field __mj_CreatedAt to entity ${flyway:defaultSchema}.GitHubRepository */
ALTER TABLE [${flyway:defaultSchema}].[GitHubRepository] ADD [__mj_CreatedAt] DATETIMEOFFSET NULL;
GO

/* SQL text to add special date field __mj_CreatedAt to entity ${flyway:defaultSchema}.GitHubRepository */
UPDATE [${flyway:defaultSchema}].[GitHubRepository] SET [__mj_CreatedAt] = GETUTCDATE() WHERE [__mj_CreatedAt] IS NULL;
GO

/* SQL text to add special date field __mj_CreatedAt to entity ${flyway:defaultSchema}.GitHubRepository */
ALTER TABLE [${flyway:defaultSchema}].[GitHubRepository] ALTER COLUMN [__mj_CreatedAt] DATETIMEOFFSET NOT NULL;
GO

/* SQL text to add special date field __mj_CreatedAt to entity ${flyway:defaultSchema}.GitHubRepository */
ALTER TABLE [${flyway:defaultSchema}].[GitHubRepository] ADD CONSTRAINT [DF___mj_BizAppsTasksGitHub_GitHubRepository___mj_CreatedAt] DEFAULT GETUTCDATE() FOR [__mj_CreatedAt];
GO

/* SQL text to add special date field __mj_UpdatedAt to entity ${flyway:defaultSchema}.GitHubRepository */
ALTER TABLE [${flyway:defaultSchema}].[GitHubRepository] ADD [__mj_UpdatedAt] DATETIMEOFFSET NULL;
GO

/* SQL text to add special date field __mj_UpdatedAt to entity ${flyway:defaultSchema}.GitHubRepository */
UPDATE [${flyway:defaultSchema}].[GitHubRepository] SET [__mj_UpdatedAt] = GETUTCDATE() WHERE [__mj_UpdatedAt] IS NULL;
GO

/* SQL text to add special date field __mj_UpdatedAt to entity ${flyway:defaultSchema}.GitHubRepository */
ALTER TABLE [${flyway:defaultSchema}].[GitHubRepository] ALTER COLUMN [__mj_UpdatedAt] DATETIMEOFFSET NOT NULL;
GO

/* SQL text to add special date field __mj_UpdatedAt to entity ${flyway:defaultSchema}.GitHubRepository */
ALTER TABLE [${flyway:defaultSchema}].[GitHubRepository] ADD CONSTRAINT [DF___mj_BizAppsTasksGitHub_GitHubRepository___mj_UpdatedAt] DEFAULT GETUTCDATE() FOR [__mj_UpdatedAt];
GO

/* SQL text to add special date field __mj_CreatedAt to entity ${flyway:defaultSchema}.GitHubIssueTask */
ALTER TABLE [${flyway:defaultSchema}].[GitHubIssueTask] ADD [__mj_CreatedAt] DATETIMEOFFSET NULL;
GO

/* SQL text to add special date field __mj_CreatedAt to entity ${flyway:defaultSchema}.GitHubIssueTask */
UPDATE [${flyway:defaultSchema}].[GitHubIssueTask] SET [__mj_CreatedAt] = GETUTCDATE() WHERE [__mj_CreatedAt] IS NULL;
GO

/* SQL text to add special date field __mj_CreatedAt to entity ${flyway:defaultSchema}.GitHubIssueTask */
ALTER TABLE [${flyway:defaultSchema}].[GitHubIssueTask] ALTER COLUMN [__mj_CreatedAt] DATETIMEOFFSET NOT NULL;
GO

/* SQL text to add special date field __mj_CreatedAt to entity ${flyway:defaultSchema}.GitHubIssueTask */
ALTER TABLE [${flyway:defaultSchema}].[GitHubIssueTask] ADD CONSTRAINT [DF___mj_BizAppsTasksGitHub_GitHubIssueTask___mj_CreatedAt] DEFAULT GETUTCDATE() FOR [__mj_CreatedAt];
GO

/* SQL text to add special date field __mj_UpdatedAt to entity ${flyway:defaultSchema}.GitHubIssueTask */
ALTER TABLE [${flyway:defaultSchema}].[GitHubIssueTask] ADD [__mj_UpdatedAt] DATETIMEOFFSET NULL;
GO

/* SQL text to add special date field __mj_UpdatedAt to entity ${flyway:defaultSchema}.GitHubIssueTask */
UPDATE [${flyway:defaultSchema}].[GitHubIssueTask] SET [__mj_UpdatedAt] = GETUTCDATE() WHERE [__mj_UpdatedAt] IS NULL;
GO

/* SQL text to add special date field __mj_UpdatedAt to entity ${flyway:defaultSchema}.GitHubIssueTask */
ALTER TABLE [${flyway:defaultSchema}].[GitHubIssueTask] ALTER COLUMN [__mj_UpdatedAt] DATETIMEOFFSET NOT NULL;
GO

/* SQL text to add special date field __mj_UpdatedAt to entity ${flyway:defaultSchema}.GitHubIssueTask */
ALTER TABLE [${flyway:defaultSchema}].[GitHubIssueTask] ADD CONSTRAINT [DF___mj_BizAppsTasksGitHub_GitHubIssueTask___mj_UpdatedAt] DEFAULT GETUTCDATE() FOR [__mj_UpdatedAt];
GO

/* SQL text to add special date field __mj_CreatedAt to entity ${flyway:defaultSchema}.GitHubIdentity */
ALTER TABLE [${flyway:defaultSchema}].[GitHubIdentity] ADD [__mj_CreatedAt] DATETIMEOFFSET NULL;
GO

/* SQL text to add special date field __mj_CreatedAt to entity ${flyway:defaultSchema}.GitHubIdentity */
UPDATE [${flyway:defaultSchema}].[GitHubIdentity] SET [__mj_CreatedAt] = GETUTCDATE() WHERE [__mj_CreatedAt] IS NULL;
GO

/* SQL text to add special date field __mj_CreatedAt to entity ${flyway:defaultSchema}.GitHubIdentity */
ALTER TABLE [${flyway:defaultSchema}].[GitHubIdentity] ALTER COLUMN [__mj_CreatedAt] DATETIMEOFFSET NOT NULL;
GO

/* SQL text to add special date field __mj_CreatedAt to entity ${flyway:defaultSchema}.GitHubIdentity */
ALTER TABLE [${flyway:defaultSchema}].[GitHubIdentity] ADD CONSTRAINT [DF___mj_BizAppsTasksGitHub_GitHubIdentity___mj_CreatedAt] DEFAULT GETUTCDATE() FOR [__mj_CreatedAt];
GO

/* SQL text to add special date field __mj_UpdatedAt to entity ${flyway:defaultSchema}.GitHubIdentity */
ALTER TABLE [${flyway:defaultSchema}].[GitHubIdentity] ADD [__mj_UpdatedAt] DATETIMEOFFSET NULL;
GO

/* SQL text to add special date field __mj_UpdatedAt to entity ${flyway:defaultSchema}.GitHubIdentity */
UPDATE [${flyway:defaultSchema}].[GitHubIdentity] SET [__mj_UpdatedAt] = GETUTCDATE() WHERE [__mj_UpdatedAt] IS NULL;
GO

/* SQL text to add special date field __mj_UpdatedAt to entity ${flyway:defaultSchema}.GitHubIdentity */
ALTER TABLE [${flyway:defaultSchema}].[GitHubIdentity] ALTER COLUMN [__mj_UpdatedAt] DATETIMEOFFSET NOT NULL;
GO

/* SQL text to add special date field __mj_UpdatedAt to entity ${flyway:defaultSchema}.GitHubIdentity */
ALTER TABLE [${flyway:defaultSchema}].[GitHubIdentity] ADD CONSTRAINT [DF___mj_BizAppsTasksGitHub_GitHubIdentity___mj_UpdatedAt] DEFAULT GETUTCDATE() FOR [__mj_UpdatedAt];
GO

/* SQL text to add special date field __mj_CreatedAt to entity ${flyway:defaultSchema}.GitHubPullRequestTask */
ALTER TABLE [${flyway:defaultSchema}].[GitHubPullRequestTask] ADD [__mj_CreatedAt] DATETIMEOFFSET NULL;
GO

/* SQL text to add special date field __mj_CreatedAt to entity ${flyway:defaultSchema}.GitHubPullRequestTask */
UPDATE [${flyway:defaultSchema}].[GitHubPullRequestTask] SET [__mj_CreatedAt] = GETUTCDATE() WHERE [__mj_CreatedAt] IS NULL;
GO

/* SQL text to add special date field __mj_CreatedAt to entity ${flyway:defaultSchema}.GitHubPullRequestTask */
ALTER TABLE [${flyway:defaultSchema}].[GitHubPullRequestTask] ALTER COLUMN [__mj_CreatedAt] DATETIMEOFFSET NOT NULL;
GO

/* SQL text to add special date field __mj_CreatedAt to entity ${flyway:defaultSchema}.GitHubPullRequestTask */
ALTER TABLE [${flyway:defaultSchema}].[GitHubPullRequestTask] ADD CONSTRAINT [DF___mj_BizAppsTasksGitHub_GitHubPullRequestTask___mj_CreatedAt] DEFAULT GETUTCDATE() FOR [__mj_CreatedAt];
GO

/* SQL text to add special date field __mj_UpdatedAt to entity ${flyway:defaultSchema}.GitHubPullRequestTask */
ALTER TABLE [${flyway:defaultSchema}].[GitHubPullRequestTask] ADD [__mj_UpdatedAt] DATETIMEOFFSET NULL;
GO

/* SQL text to add special date field __mj_UpdatedAt to entity ${flyway:defaultSchema}.GitHubPullRequestTask */
UPDATE [${flyway:defaultSchema}].[GitHubPullRequestTask] SET [__mj_UpdatedAt] = GETUTCDATE() WHERE [__mj_UpdatedAt] IS NULL;
GO

/* SQL text to add special date field __mj_UpdatedAt to entity ${flyway:defaultSchema}.GitHubPullRequestTask */
ALTER TABLE [${flyway:defaultSchema}].[GitHubPullRequestTask] ALTER COLUMN [__mj_UpdatedAt] DATETIMEOFFSET NOT NULL;
GO

/* SQL text to add special date field __mj_UpdatedAt to entity ${flyway:defaultSchema}.GitHubPullRequestTask */
ALTER TABLE [${flyway:defaultSchema}].[GitHubPullRequestTask] ADD CONSTRAINT [DF___mj_BizAppsTasksGitHub_GitHubPullRequestTask___mj_UpdatedAt] DEFAULT GETUTCDATE() FOR [__mj_UpdatedAt];
GO

/* SQL text to insert 60 new entity field(s) */

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = 'd38e3c3f-3676-439b-9111-df4565789c9f' OR (EntityID = '6B363236-31AB-477D-8188-08F5FA9942EF' AND Name = 'ID')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            'd38e3c3f-3676-439b-9111-df4565789c9f',
            '6B363236-31AB-477D-8188-08F5FA9942EF', -- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Repositories
            (SELECT COALESCE(MAX([Sequence]), 0) + 1 FROM [${mjSchema}].[EntityField] WHERE [EntityID] = '6B363236-31AB-477D-8188-08F5FA9942EF'),
            'ID',
            'ID',
            NULL,
            'uniqueidentifier',
            16,
            0,
            0,
            0,
            'newsequentialid()',
            0,
            0,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            1,
            1,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '16994c95-2791-47c6-b378-4af1eace655f' OR (EntityID = '6B363236-31AB-477D-8188-08F5FA9942EF' AND Name = 'Owner')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '16994c95-2791-47c6-b378-4af1eace655f',
            '6B363236-31AB-477D-8188-08F5FA9942EF', -- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Repositories
            (SELECT COALESCE(MAX([Sequence]), 0) + 1 FROM [${mjSchema}].[EntityField] WHERE [EntityID] = '6B363236-31AB-477D-8188-08F5FA9942EF'),
            'Owner',
            'Owner',
            'GitHub organization or user login that owns the repository (e.g. MemberJunction).',
            'nvarchar',
            300,
            0,
            0,
            0,
            NULL,
            0,
            1,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            1,
            0,
            1,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '8cfc093f-2135-437e-93a8-493a64dfa174' OR (EntityID = '6B363236-31AB-477D-8188-08F5FA9942EF' AND Name = 'Name')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '8cfc093f-2135-437e-93a8-493a64dfa174',
            '6B363236-31AB-477D-8188-08F5FA9942EF', -- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Repositories
            (SELECT COALESCE(MAX([Sequence]), 0) + 1 FROM [${mjSchema}].[EntityField] WHERE [EntityID] = '6B363236-31AB-477D-8188-08F5FA9942EF'),
            'Name',
            'Name',
            'Repository slug within the owner namespace (e.g. MJ, bizapps-tasks).',
            'nvarchar',
            400,
            0,
            0,
            0,
            NULL,
            0,
            1,
            0,
            0,
            NULL,
            NULL,
            1,
            1,
            0,
            1,
            0,
            1,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '8231446a-482b-4d5f-a1ed-ae1a717f50a0' OR (EntityID = '6B363236-31AB-477D-8188-08F5FA9942EF' AND Name = 'DefaultBranch')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '8231446a-482b-4d5f-a1ed-ae1a717f50a0',
            '6B363236-31AB-477D-8188-08F5FA9942EF', -- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Repositories
            (SELECT COALESCE(MAX([Sequence]), 0) + 1 FROM [${mjSchema}].[EntityField] WHERE [EntityID] = '6B363236-31AB-477D-8188-08F5FA9942EF'),
            'DefaultBranch',
            'Default Branch',
            'Default target branch name on GitHub (typically main or next).',
            'nvarchar',
            240,
            0,
            0,
            0,
            'main',
            0,
            1,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            1,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '89c19524-c1fb-441e-a66c-577ddc5d41c3' OR (EntityID = '6B363236-31AB-477D-8188-08F5FA9942EF' AND Name = 'IsTracked')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '89c19524-c1fb-441e-a66c-577ddc5d41c3',
            '6B363236-31AB-477D-8188-08F5FA9942EF', -- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Repositories
            (SELECT COALESCE(MAX([Sequence]), 0) + 1 FROM [${mjSchema}].[EntityField] WHERE [EntityID] = '6B363236-31AB-477D-8188-08F5FA9942EF'),
            'IsTracked',
            'Is Tracked',
            'When 1, periodic sync and incoming webhooks import eligible issues and pull requests into BizApps Tasks.',
            'bit',
            1,
            1,
            0,
            0,
            '(1)',
            0,
            1,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            1,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = 'd09cc770-1cbb-4078-8186-bf3ed875f03c' OR (EntityID = '6B363236-31AB-477D-8188-08F5FA9942EF' AND Name = 'ImportRule')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            'd09cc770-1cbb-4078-8186-bf3ed875f03c',
            '6B363236-31AB-477D-8188-08F5FA9942EF', -- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Repositories
            (SELECT COALESCE(MAX([Sequence]), 0) + 1 FROM [${mjSchema}].[EntityField] WHERE [EntityID] = '6B363236-31AB-477D-8188-08F5FA9942EF'),
            'ImportRule',
            'Import Rule',
            'Controls which issues and PRs become Tasks: AssignedOnly imports items assigned to or requesting review from a mapped GitHubIdentity; All imports every issue and PR in the repository.',
            'nvarchar',
            40,
            0,
            0,
            0,
            'AssignedOnly',
            0,
            1,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = 'f6397e85-2f8b-4b39-a42f-4063209b7c3e' OR (EntityID = '6B363236-31AB-477D-8188-08F5FA9942EF' AND Name = 'InstallationID')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            'f6397e85-2f8b-4b39-a42f-4063209b7c3e',
            '6B363236-31AB-477D-8188-08F5FA9942EF', -- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Repositories
            (SELECT COALESCE(MAX([Sequence]), 0) + 1 FROM [${mjSchema}].[EntityField] WHERE [EntityID] = '6B363236-31AB-477D-8188-08F5FA9942EF'),
            'InstallationID',
            'Installation ID',
            'GitHub App installation identifier scoped to this repository or organization.',
            'nvarchar',
            200,
            0,
            0,
            1,
            NULL,
            0,
            1,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '507961d4-497e-4b22-9cff-c6506f32b45c' OR (EntityID = '6B363236-31AB-477D-8188-08F5FA9942EF' AND Name = 'OrganizationID')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '507961d4-497e-4b22-9cff-c6506f32b45c',
            '6B363236-31AB-477D-8188-08F5FA9942EF', -- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Repositories
            (SELECT COALESCE(MAX([Sequence]), 0) + 1 FROM [${mjSchema}].[EntityField] WHERE [EntityID] = '6B363236-31AB-477D-8188-08F5FA9942EF'),
            'OrganizationID',
            'Organization ID',
            'Optional client Organization in BizApps Common. Null denotes an internal repository; non-null enables Client-layer DeliveryPolicy inheritance.',
            'uniqueidentifier',
            16,
            0,
            0,
            1,
            NULL,
            0,
            1,
            0,
            0,
            'C70448F9-9792-41D7-A82C-784B66429D54',
            'ID',
            0,
            0,
            1,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '2685c802-43ea-4389-b1cc-5d007755dcd6' OR (EntityID = '6B363236-31AB-477D-8188-08F5FA9942EF' AND Name = 'DeliveryPolicyID')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '2685c802-43ea-4389-b1cc-5d007755dcd6',
            '6B363236-31AB-477D-8188-08F5FA9942EF', -- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Repositories
            (SELECT COALESCE(MAX([Sequence]), 0) + 1 FROM [${mjSchema}].[EntityField] WHERE [EntityID] = '6B363236-31AB-477D-8188-08F5FA9942EF'),
            'DeliveryPolicyID',
            'Delivery Policy ID',
            'Optional UUID of the repository-level DeliveryPolicy in bizapps-software-factory when installed.',
            'uniqueidentifier',
            16,
            0,
            0,
            1,
            NULL,
            0,
            1,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = 'f9323407-463f-4ef0-8e56-800d98360b4a' OR (EntityID = '6B363236-31AB-477D-8188-08F5FA9942EF' AND Name = '__mj_CreatedAt')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            'f9323407-463f-4ef0-8e56-800d98360b4a',
            '6B363236-31AB-477D-8188-08F5FA9942EF', -- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Repositories
            (SELECT COALESCE(MAX([Sequence]), 0) + 1 FROM [${mjSchema}].[EntityField] WHERE [EntityID] = '6B363236-31AB-477D-8188-08F5FA9942EF'),
            '__mj_CreatedAt',
            'Created At',
            NULL,
            'datetimeoffset',
            10,
            34,
            7,
            0,
            'getutcdate()',
            0,
            0,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '1e25cf76-141f-4848-8a29-c47a7a522297' OR (EntityID = '6B363236-31AB-477D-8188-08F5FA9942EF' AND Name = '__mj_UpdatedAt')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '1e25cf76-141f-4848-8a29-c47a7a522297',
            '6B363236-31AB-477D-8188-08F5FA9942EF', -- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Repositories
            (SELECT COALESCE(MAX([Sequence]), 0) + 1 FROM [${mjSchema}].[EntityField] WHERE [EntityID] = '6B363236-31AB-477D-8188-08F5FA9942EF'),
            '__mj_UpdatedAt',
            'Updated At',
            NULL,
            'datetimeoffset',
            10,
            34,
            7,
            0,
            'getutcdate()',
            0,
            0,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = 'f041d734-2d08-48f3-baa4-c29f45bfb5de' OR (EntityID = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605' AND Name = 'ID')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            'f041d734-2d08-48f3-baa4-c29f45bfb5de',
            'DC8E0F5B-E172-4FD5-B648-8B4544F8C605', -- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks
            (SELECT COALESCE(MAX([Sequence]), 0) + 1 FROM [${mjSchema}].[EntityField] WHERE [EntityID] = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605'),
            'ID',
            'ID',
            'Shared primary key referencing __mj_BizAppsTasks.Task(ID).',
            'uniqueidentifier',
            16,
            0,
            0,
            0,
            NULL,
            0,
            0,
            0,
            0,
            'B348FFA2-B1A7-4AC2-B6FD-F4E0C0697466',
            'ID',
            0,
            0,
            1,
            0,
            1,
            1,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '54442a79-cead-408b-82aa-4119053fe27e' OR (EntityID = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605' AND Name = 'RepositoryID')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '54442a79-cead-408b-82aa-4119053fe27e',
            'DC8E0F5B-E172-4FD5-B648-8B4544F8C605', -- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks
            (SELECT COALESCE(MAX([Sequence]), 0) + 1 FROM [${mjSchema}].[EntityField] WHERE [EntityID] = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605'),
            'RepositoryID',
            'Repository ID',
            'GitHubRepository to which this issue belongs.',
            'uniqueidentifier',
            16,
            0,
            0,
            1,
            NULL,
            0,
            1,
            0,
            0,
            '6B363236-31AB-477D-8188-08F5FA9942EF',
            'ID',
            0,
            0,
            1,
            0,
            0,
            1,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = 'a97ca445-668e-4763-a2c6-74de67a33925' OR (EntityID = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605' AND Name = 'Number')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            'a97ca445-668e-4763-a2c6-74de67a33925',
            'DC8E0F5B-E172-4FD5-B648-8B4544F8C605', -- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks
            (SELECT COALESCE(MAX([Sequence]), 0) + 1 FROM [${mjSchema}].[EntityField] WHERE [EntityID] = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605'),
            'Number',
            'Number',
            'Repository-scoped GitHub issue number (#N). Unique per RepositoryID when populated.',
            'int',
            4,
            10,
            0,
            1,
            NULL,
            0,
            1,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            1,
            0,
            1,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = 'b0c058e3-ba70-4f2a-9b84-21ab522e8e6d' OR (EntityID = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605' AND Name = 'NodeID')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            'b0c058e3-ba70-4f2a-9b84-21ab522e8e6d',
            'DC8E0F5B-E172-4FD5-B648-8B4544F8C605', -- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks
            (SELECT COALESCE(MAX([Sequence]), 0) + 1 FROM [${mjSchema}].[EntityField] WHERE [EntityID] = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605'),
            'NodeID',
            'Node ID',
            'Global GitHub GraphQL node identifier for idempotent cross-rename sync.',
            'nvarchar',
            256,
            0,
            0,
            1,
            NULL,
            0,
            1,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            1,
            0,
            1,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '6b287fde-cf5a-4381-84a1-96a45d3e58c4' OR (EntityID = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605' AND Name = 'HtmlURL')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '6b287fde-cf5a-4381-84a1-96a45d3e58c4',
            'DC8E0F5B-E172-4FD5-B648-8B4544F8C605', -- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks
            (SELECT COALESCE(MAX([Sequence]), 0) + 1 FROM [${mjSchema}].[EntityField] WHERE [EntityID] = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605'),
            'HtmlURL',
            'Html URL',
            'Canonical browser URL to view or edit the issue on GitHub.',
            'nvarchar',
            2000,
            0,
            0,
            1,
            NULL,
            0,
            1,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            1,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '54cd3bc9-e3df-4b33-9413-b2f137eb2452' OR (EntityID = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605' AND Name = 'State')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '54cd3bc9-e3df-4b33-9413-b2f137eb2452',
            'DC8E0F5B-E172-4FD5-B648-8B4544F8C605', -- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks
            (SELECT COALESCE(MAX([Sequence]), 0) + 1 FROM [${mjSchema}].[EntityField] WHERE [EntityID] = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605'),
            'State',
            'State',
            'GitHub issue state (open or closed).',
            'nvarchar',
            40,
            0,
            0,
            0,
            'open',
            0,
            1,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = 'ac27eb42-f18d-4444-99a2-9e454dbaeb49' OR (EntityID = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605' AND Name = 'StateReason')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            'ac27eb42-f18d-4444-99a2-9e454dbaeb49',
            'DC8E0F5B-E172-4FD5-B648-8B4544F8C605', -- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks
            (SELECT COALESCE(MAX([Sequence]), 0) + 1 FROM [${mjSchema}].[EntityField] WHERE [EntityID] = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605'),
            'StateReason',
            'State Reason',
            'Optional GitHub issue state_reason (completed, not_planned, reopened, duplicate).',
            'nvarchar',
            80,
            0,
            0,
            1,
            NULL,
            0,
            1,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '9f961e3c-910b-44c2-a78f-e0ac03ed963f' OR (EntityID = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605' AND Name = 'Labels')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '9f961e3c-910b-44c2-a78f-e0ac03ed963f',
            'DC8E0F5B-E172-4FD5-B648-8B4544F8C605', -- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks
            (SELECT COALESCE(MAX([Sequence]), 0) + 1 FROM [${mjSchema}].[EntityField] WHERE [EntityID] = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605'),
            'Labels',
            'Labels',
            'JSON array of GitHub label names applied to the issue.',
            'nvarchar',
            -1,
            0,
            0,
            1,
            NULL,
            0,
            1,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '8a9b093f-91d1-4991-9069-4f2f36ad9181' OR (EntityID = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605' AND Name = 'Milestone')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '8a9b093f-91d1-4991-9069-4f2f36ad9181',
            'DC8E0F5B-E172-4FD5-B648-8B4544F8C605', -- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks
            (SELECT COALESCE(MAX([Sequence]), 0) + 1 FROM [${mjSchema}].[EntityField] WHERE [EntityID] = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605'),
            'Milestone',
            'Milestone',
            'GitHub milestone title when assigned.',
            'nvarchar',
            510,
            0,
            0,
            1,
            NULL,
            0,
            1,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '9a88e775-dca4-46ed-b580-cc79394b5b69' OR (EntityID = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605' AND Name = 'MilestoneDueAt')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '9a88e775-dca4-46ed-b580-cc79394b5b69',
            'DC8E0F5B-E172-4FD5-B648-8B4544F8C605', -- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks
            (SELECT COALESCE(MAX([Sequence]), 0) + 1 FROM [${mjSchema}].[EntityField] WHERE [EntityID] = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605'),
            'MilestoneDueAt',
            'Milestone Due At',
            'Due timestamp of the GitHub milestone; supersedes pending inferred DueAt Field Suggestions.',
            'datetimeoffset',
            10,
            34,
            7,
            1,
            NULL,
            0,
            1,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '47f2bc8c-baa7-4720-8425-3f982edfd315' OR (EntityID = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605' AND Name = 'AuthorLogin')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '47f2bc8c-baa7-4720-8425-3f982edfd315',
            'DC8E0F5B-E172-4FD5-B648-8B4544F8C605', -- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks
            (SELECT COALESCE(MAX([Sequence]), 0) + 1 FROM [${mjSchema}].[EntityField] WHERE [EntityID] = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605'),
            'AuthorLogin',
            'Author Login',
            'GitHub login of the user who opened the issue.',
            'nvarchar',
            200,
            0,
            0,
            1,
            NULL,
            0,
            1,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '0b5ed37c-d3ab-4c8a-a484-f0e12dbd9744' OR (EntityID = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605' AND Name = 'BodyHash')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '0b5ed37c-d3ab-4c8a-a484-f0e12dbd9744',
            'DC8E0F5B-E172-4FD5-B648-8B4544F8C605', -- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks
            (SELECT COALESCE(MAX([Sequence]), 0) + 1 FROM [${mjSchema}].[EntityField] WHERE [EntityID] = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605'),
            'BodyHash',
            'Body Hash',
            'SHA-256 hash of the last synced issue body used to detect text edits and trigger Field Suggestion re-inference.',
            'nvarchar',
            128,
            0,
            0,
            1,
            NULL,
            0,
            1,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = 'ff322d0f-97cb-4cee-9c1e-c347a4c145ae' OR (EntityID = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605' AND Name = 'GitHubUpdatedAt')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            'ff322d0f-97cb-4cee-9c1e-c347a4c145ae',
            'DC8E0F5B-E172-4FD5-B648-8B4544F8C605', -- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks
            (SELECT COALESCE(MAX([Sequence]), 0) + 1 FROM [${mjSchema}].[EntityField] WHERE [EntityID] = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605'),
            'GitHubUpdatedAt',
            'Git Hub Updated At',
            'Upstream updated_at timestamp reported by GitHub.',
            'datetimeoffset',
            10,
            34,
            7,
            1,
            NULL,
            0,
            1,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '8d123f90-1cd8-42e3-a8bf-c121be46401b' OR (EntityID = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605' AND Name = 'LastSyncedAt')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '8d123f90-1cd8-42e3-a8bf-c121be46401b',
            'DC8E0F5B-E172-4FD5-B648-8B4544F8C605', -- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks
            (SELECT COALESCE(MAX([Sequence]), 0) + 1 FROM [${mjSchema}].[EntityField] WHERE [EntityID] = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605'),
            'LastSyncedAt',
            'Last Synced At',
            'Timestamp when BizApps Tasks GitHub sync last reconciled this issue.',
            'datetimeoffset',
            10,
            34,
            7,
            1,
            NULL,
            0,
            1,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = 'dec034d1-627f-4099-84d9-71ebd162acbd' OR (EntityID = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605' AND Name = '__mj_CreatedAt')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            'dec034d1-627f-4099-84d9-71ebd162acbd',
            'DC8E0F5B-E172-4FD5-B648-8B4544F8C605', -- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks
            (SELECT COALESCE(MAX([Sequence]), 0) + 1 FROM [${mjSchema}].[EntityField] WHERE [EntityID] = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605'),
            '__mj_CreatedAt',
            'Created At',
            NULL,
            'datetimeoffset',
            10,
            34,
            7,
            0,
            'getutcdate()',
            0,
            0,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = 'f846083a-3f9a-4728-86d8-6772a47ac54e' OR (EntityID = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605' AND Name = '__mj_UpdatedAt')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            'f846083a-3f9a-4728-86d8-6772a47ac54e',
            'DC8E0F5B-E172-4FD5-B648-8B4544F8C605', -- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks
            (SELECT COALESCE(MAX([Sequence]), 0) + 1 FROM [${mjSchema}].[EntityField] WHERE [EntityID] = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605'),
            '__mj_UpdatedAt',
            'Updated At',
            NULL,
            'datetimeoffset',
            10,
            34,
            7,
            0,
            'getutcdate()',
            0,
            0,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '14420024-8d4c-43fb-b3c2-c335cfdca13f' OR (EntityID = 'C7CC2BCF-090E-4832-89C7-A051F302C393' AND Name = 'ID')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '14420024-8d4c-43fb-b3c2-c335cfdca13f',
            'C7CC2BCF-090E-4832-89C7-A051F302C393', -- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Identities
            (SELECT COALESCE(MAX([Sequence]), 0) + 1 FROM [${mjSchema}].[EntityField] WHERE [EntityID] = 'C7CC2BCF-090E-4832-89C7-A051F302C393'),
            'ID',
            'ID',
            NULL,
            'uniqueidentifier',
            16,
            0,
            0,
            0,
            'newsequentialid()',
            0,
            0,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            1,
            1,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '2680087d-c275-43f1-8a02-eb2fac64624c' OR (EntityID = 'C7CC2BCF-090E-4832-89C7-A051F302C393' AND Name = 'GitHubLogin')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '2680087d-c275-43f1-8a02-eb2fac64624c',
            'C7CC2BCF-090E-4832-89C7-A051F302C393', -- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Identities
            (SELECT COALESCE(MAX([Sequence]), 0) + 1 FROM [${mjSchema}].[EntityField] WHERE [EntityID] = 'C7CC2BCF-090E-4832-89C7-A051F302C393'),
            'GitHubLogin',
            'Git Hub Login',
            'Case-insensitive GitHub username / handle (e.g. octocat).',
            'nvarchar',
            200,
            0,
            0,
            0,
            NULL,
            0,
            1,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            1,
            0,
            1,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '86923f31-a619-4171-9700-360d0f84eaee' OR (EntityID = 'C7CC2BCF-090E-4832-89C7-A051F302C393' AND Name = 'PersonID')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '86923f31-a619-4171-9700-360d0f84eaee',
            'C7CC2BCF-090E-4832-89C7-A051F302C393', -- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Identities
            (SELECT COALESCE(MAX([Sequence]), 0) + 1 FROM [${mjSchema}].[EntityField] WHERE [EntityID] = 'C7CC2BCF-090E-4832-89C7-A051F302C393'),
            'PersonID',
            'Person ID',
            'Target BizApps Common Person record associated with this GitHub login.',
            'uniqueidentifier',
            16,
            0,
            0,
            0,
            NULL,
            0,
            1,
            0,
            0,
            '7A94ADA9-7880-4FAE-97D8-DB0E934C3F5F',
            'ID',
            0,
            0,
            1,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = 'da3ff8e3-9102-4bdc-9747-2c1b92282829' OR (EntityID = 'C7CC2BCF-090E-4832-89C7-A051F302C393' AND Name = 'GitHubUserID')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            'da3ff8e3-9102-4bdc-9747-2c1b92282829',
            'C7CC2BCF-090E-4832-89C7-A051F302C393', -- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Identities
            (SELECT COALESCE(MAX([Sequence]), 0) + 1 FROM [${mjSchema}].[EntityField] WHERE [EntityID] = 'C7CC2BCF-090E-4832-89C7-A051F302C393'),
            'GitHubUserID',
            'Git Hub User ID',
            'Optional numeric or GraphQL node identifier for the GitHub user account.',
            'nvarchar',
            128,
            0,
            0,
            1,
            NULL,
            0,
            1,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            1,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '859b1d57-888e-4f5e-9394-11927fcde8ca' OR (EntityID = 'C7CC2BCF-090E-4832-89C7-A051F302C393' AND Name = 'IsActive')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '859b1d57-888e-4f5e-9394-11927fcde8ca',
            'C7CC2BCF-090E-4832-89C7-A051F302C393', -- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Identities
            (SELECT COALESCE(MAX([Sequence]), 0) + 1 FROM [${mjSchema}].[EntityField] WHERE [EntityID] = 'C7CC2BCF-090E-4832-89C7-A051F302C393'),
            'IsActive',
            'Is Active',
            'Whether this login mapping is currently active for task import and assignment resolution.',
            'bit',
            1,
            1,
            0,
            0,
            '(1)',
            0,
            1,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            1,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '0f52c847-41b4-44f5-9ff7-83df5bfc74d9' OR (EntityID = 'C7CC2BCF-090E-4832-89C7-A051F302C393' AND Name = '__mj_CreatedAt')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '0f52c847-41b4-44f5-9ff7-83df5bfc74d9',
            'C7CC2BCF-090E-4832-89C7-A051F302C393', -- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Identities
            (SELECT COALESCE(MAX([Sequence]), 0) + 1 FROM [${mjSchema}].[EntityField] WHERE [EntityID] = 'C7CC2BCF-090E-4832-89C7-A051F302C393'),
            '__mj_CreatedAt',
            'Created At',
            NULL,
            'datetimeoffset',
            10,
            34,
            7,
            0,
            'getutcdate()',
            0,
            0,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '168eed29-3b45-4398-973f-71a7da22e916' OR (EntityID = 'C7CC2BCF-090E-4832-89C7-A051F302C393' AND Name = '__mj_UpdatedAt')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '168eed29-3b45-4398-973f-71a7da22e916',
            'C7CC2BCF-090E-4832-89C7-A051F302C393', -- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Identities
            (SELECT COALESCE(MAX([Sequence]), 0) + 1 FROM [${mjSchema}].[EntityField] WHERE [EntityID] = 'C7CC2BCF-090E-4832-89C7-A051F302C393'),
            '__mj_UpdatedAt',
            'Updated At',
            NULL,
            'datetimeoffset',
            10,
            34,
            7,
            0,
            'getutcdate()',
            0,
            0,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '4afbf1a3-202b-4657-938b-652ef047768f' OR (EntityID = 'A6B673F8-43BC-4875-AFF6-AC620592822E' AND Name = 'ID')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '4afbf1a3-202b-4657-938b-652ef047768f',
            'A6B673F8-43BC-4875-AFF6-AC620592822E', -- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks
            (SELECT COALESCE(MAX([Sequence]), 0) + 1 FROM [${mjSchema}].[EntityField] WHERE [EntityID] = 'A6B673F8-43BC-4875-AFF6-AC620592822E'),
            'ID',
            'ID',
            'Shared primary key referencing __mj_BizAppsTasks.Task(ID).',
            'uniqueidentifier',
            16,
            0,
            0,
            0,
            NULL,
            0,
            0,
            0,
            0,
            'B348FFA2-B1A7-4AC2-B6FD-F4E0C0697466',
            'ID',
            0,
            0,
            1,
            0,
            1,
            1,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '80c22b8d-1383-4ac3-bc9d-6540c3fded78' OR (EntityID = 'A6B673F8-43BC-4875-AFF6-AC620592822E' AND Name = 'RepositoryID')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '80c22b8d-1383-4ac3-bc9d-6540c3fded78',
            'A6B673F8-43BC-4875-AFF6-AC620592822E', -- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks
            (SELECT COALESCE(MAX([Sequence]), 0) + 1 FROM [${mjSchema}].[EntityField] WHERE [EntityID] = 'A6B673F8-43BC-4875-AFF6-AC620592822E'),
            'RepositoryID',
            'Repository ID',
            'GitHubRepository to which this pull request belongs.',
            'uniqueidentifier',
            16,
            0,
            0,
            1,
            NULL,
            0,
            1,
            0,
            0,
            '6B363236-31AB-477D-8188-08F5FA9942EF',
            'ID',
            0,
            0,
            1,
            0,
            0,
            1,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = 'd0157ce0-e6ee-41d6-828d-f774b96ab24c' OR (EntityID = 'A6B673F8-43BC-4875-AFF6-AC620592822E' AND Name = 'Number')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            'd0157ce0-e6ee-41d6-828d-f774b96ab24c',
            'A6B673F8-43BC-4875-AFF6-AC620592822E', -- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks
            (SELECT COALESCE(MAX([Sequence]), 0) + 1 FROM [${mjSchema}].[EntityField] WHERE [EntityID] = 'A6B673F8-43BC-4875-AFF6-AC620592822E'),
            'Number',
            'Number',
            'Repository-scoped GitHub pull request number (#N). Unique per RepositoryID when populated.',
            'int',
            4,
            10,
            0,
            1,
            NULL,
            0,
            1,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            1,
            0,
            1,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '07679af9-e8a9-4aeb-ad5c-2cb9ba40a3f4' OR (EntityID = 'A6B673F8-43BC-4875-AFF6-AC620592822E' AND Name = 'NodeID')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '07679af9-e8a9-4aeb-ad5c-2cb9ba40a3f4',
            'A6B673F8-43BC-4875-AFF6-AC620592822E', -- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks
            (SELECT COALESCE(MAX([Sequence]), 0) + 1 FROM [${mjSchema}].[EntityField] WHERE [EntityID] = 'A6B673F8-43BC-4875-AFF6-AC620592822E'),
            'NodeID',
            'Node ID',
            'Global GitHub GraphQL node identifier for idempotent sync.',
            'nvarchar',
            256,
            0,
            0,
            1,
            NULL,
            0,
            1,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            1,
            0,
            1,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = 'f2598281-767d-423e-b92a-3000708efe1a' OR (EntityID = 'A6B673F8-43BC-4875-AFF6-AC620592822E' AND Name = 'HtmlURL')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            'f2598281-767d-423e-b92a-3000708efe1a',
            'A6B673F8-43BC-4875-AFF6-AC620592822E', -- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks
            (SELECT COALESCE(MAX([Sequence]), 0) + 1 FROM [${mjSchema}].[EntityField] WHERE [EntityID] = 'A6B673F8-43BC-4875-AFF6-AC620592822E'),
            'HtmlURL',
            'Html URL',
            'Canonical browser URL to view or review the pull request on GitHub.',
            'nvarchar',
            2000,
            0,
            0,
            1,
            NULL,
            0,
            1,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            1,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '5cbfaabd-0af2-4e67-91b1-f089e6c56c4d' OR (EntityID = 'A6B673F8-43BC-4875-AFF6-AC620592822E' AND Name = 'State')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '5cbfaabd-0af2-4e67-91b1-f089e6c56c4d',
            'A6B673F8-43BC-4875-AFF6-AC620592822E', -- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks
            (SELECT COALESCE(MAX([Sequence]), 0) + 1 FROM [${mjSchema}].[EntityField] WHERE [EntityID] = 'A6B673F8-43BC-4875-AFF6-AC620592822E'),
            'State',
            'State',
            'Pull request lifecycle state on GitHub (open, closed, or merged).',
            'nvarchar',
            40,
            0,
            0,
            0,
            'open',
            0,
            1,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '6702784e-ce7d-41dd-a906-6958e5415a5d' OR (EntityID = 'A6B673F8-43BC-4875-AFF6-AC620592822E' AND Name = 'IsDraft')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '6702784e-ce7d-41dd-a906-6958e5415a5d',
            'A6B673F8-43BC-4875-AFF6-AC620592822E', -- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks
            (SELECT COALESCE(MAX([Sequence]), 0) + 1 FROM [${mjSchema}].[EntityField] WHERE [EntityID] = 'A6B673F8-43BC-4875-AFF6-AC620592822E'),
            'IsDraft',
            'Is Draft',
            'Whether the pull request is currently marked as a Draft on GitHub.',
            'bit',
            1,
            1,
            0,
            0,
            '(0)',
            0,
            1,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '6a042282-8dc0-4158-b972-f2eff37c1387' OR (EntityID = 'A6B673F8-43BC-4875-AFF6-AC620592822E' AND Name = 'HeadBranch')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '6a042282-8dc0-4158-b972-f2eff37c1387',
            'A6B673F8-43BC-4875-AFF6-AC620592822E', -- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks
            (SELECT COALESCE(MAX([Sequence]), 0) + 1 FROM [${mjSchema}].[EntityField] WHERE [EntityID] = 'A6B673F8-43BC-4875-AFF6-AC620592822E'),
            'HeadBranch',
            'Head Branch',
            'Source branch ref of the pull request (head.ref).',
            'nvarchar',
            510,
            0,
            0,
            1,
            NULL,
            0,
            1,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '68d879e4-6123-482d-8637-a6b7e250b9cb' OR (EntityID = 'A6B673F8-43BC-4875-AFF6-AC620592822E' AND Name = 'HeadSha')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '68d879e4-6123-482d-8637-a6b7e250b9cb',
            'A6B673F8-43BC-4875-AFF6-AC620592822E', -- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks
            (SELECT COALESCE(MAX([Sequence]), 0) + 1 FROM [${mjSchema}].[EntityField] WHERE [EntityID] = 'A6B673F8-43BC-4875-AFF6-AC620592822E'),
            'HeadSha',
            'Head Sha',
            'Commit SHA at the tip of HeadBranch (head.sha), verified by Software Factory merge gates.',
            'nvarchar',
            128,
            0,
            0,
            1,
            NULL,
            0,
            1,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '8d2db26a-0621-4a94-a932-a4c1f47e1dcf' OR (EntityID = 'A6B673F8-43BC-4875-AFF6-AC620592822E' AND Name = 'BaseBranch')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '8d2db26a-0621-4a94-a932-a4c1f47e1dcf',
            'A6B673F8-43BC-4875-AFF6-AC620592822E', -- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks
            (SELECT COALESCE(MAX([Sequence]), 0) + 1 FROM [${mjSchema}].[EntityField] WHERE [EntityID] = 'A6B673F8-43BC-4875-AFF6-AC620592822E'),
            'BaseBranch',
            'Base Branch',
            'Target branch ref into which the pull request merges (base.ref).',
            'nvarchar',
            510,
            0,
            0,
            1,
            NULL,
            0,
            1,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = 'debaddf7-a747-400c-bec1-8a93fddf6193' OR (EntityID = 'A6B673F8-43BC-4875-AFF6-AC620592822E' AND Name = 'AuthorLogin')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            'debaddf7-a747-400c-bec1-8a93fddf6193',
            'A6B673F8-43BC-4875-AFF6-AC620592822E', -- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks
            (SELECT COALESCE(MAX([Sequence]), 0) + 1 FROM [${mjSchema}].[EntityField] WHERE [EntityID] = 'A6B673F8-43BC-4875-AFF6-AC620592822E'),
            'AuthorLogin',
            'Author Login',
            'GitHub login of the pull request author.',
            'nvarchar',
            200,
            0,
            0,
            1,
            NULL,
            0,
            1,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = 'd0242db3-acfc-4ad6-9b8a-7af48e27bbe4' OR (EntityID = 'A6B673F8-43BC-4875-AFF6-AC620592822E' AND Name = 'ReviewDecision')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            'd0242db3-acfc-4ad6-9b8a-7af48e27bbe4',
            'A6B673F8-43BC-4875-AFF6-AC620592822E', -- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks
            (SELECT COALESCE(MAX([Sequence]), 0) + 1 FROM [${mjSchema}].[EntityField] WHERE [EntityID] = 'A6B673F8-43BC-4875-AFF6-AC620592822E'),
            'ReviewDecision',
            'Review Decision',
            'Aggregated GitHub review decision (APPROVED, CHANGES_REQUESTED, or REVIEW_REQUIRED).',
            'nvarchar',
            80,
            0,
            0,
            1,
            NULL,
            0,
            1,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '57b97f3b-7437-49c3-a2a3-89f8f14f3224' OR (EntityID = 'A6B673F8-43BC-4875-AFF6-AC620592822E' AND Name = 'ChecksStatus')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '57b97f3b-7437-49c3-a2a3-89f8f14f3224',
            'A6B673F8-43BC-4875-AFF6-AC620592822E', -- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks
            (SELECT COALESCE(MAX([Sequence]), 0) + 1 FROM [${mjSchema}].[EntityField] WHERE [EntityID] = 'A6B673F8-43BC-4875-AFF6-AC620592822E'),
            'ChecksStatus',
            'Checks Status',
            'Aggregated status of required GitHub CI checks on HeadSha (Pending, Passing, Failing, Neutral).',
            'nvarchar',
            60,
            0,
            0,
            1,
            NULL,
            0,
            1,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = 'c43679af-0136-4312-bfc7-50a774a1df96' OR (EntityID = 'A6B673F8-43BC-4875-AFF6-AC620592822E' AND Name = 'ChangedFiles')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            'c43679af-0136-4312-bfc7-50a774a1df96',
            'A6B673F8-43BC-4875-AFF6-AC620592822E', -- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks
            (SELECT COALESCE(MAX([Sequence]), 0) + 1 FROM [${mjSchema}].[EntityField] WHERE [EntityID] = 'A6B673F8-43BC-4875-AFF6-AC620592822E'),
            'ChangedFiles',
            'Changed Files',
            'Number of files touched in the pull request diff.',
            'int',
            4,
            10,
            0,
            1,
            NULL,
            0,
            1,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = 'e7c6d6dd-3b2c-4d1f-854c-36ec48ea6541' OR (EntityID = 'A6B673F8-43BC-4875-AFF6-AC620592822E' AND Name = 'Additions')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            'e7c6d6dd-3b2c-4d1f-854c-36ec48ea6541',
            'A6B673F8-43BC-4875-AFF6-AC620592822E', -- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks
            (SELECT COALESCE(MAX([Sequence]), 0) + 1 FROM [${mjSchema}].[EntityField] WHERE [EntityID] = 'A6B673F8-43BC-4875-AFF6-AC620592822E'),
            'Additions',
            'Additions',
            'Lines added in the pull request diff.',
            'int',
            4,
            10,
            0,
            1,
            NULL,
            0,
            1,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '79a88aca-735f-4126-af8c-e84e0eab6dbe' OR (EntityID = 'A6B673F8-43BC-4875-AFF6-AC620592822E' AND Name = 'Deletions')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '79a88aca-735f-4126-af8c-e84e0eab6dbe',
            'A6B673F8-43BC-4875-AFF6-AC620592822E', -- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks
            (SELECT COALESCE(MAX([Sequence]), 0) + 1 FROM [${mjSchema}].[EntityField] WHERE [EntityID] = 'A6B673F8-43BC-4875-AFF6-AC620592822E'),
            'Deletions',
            'Deletions',
            'Lines deleted in the pull request diff.',
            'int',
            4,
            10,
            0,
            1,
            NULL,
            0,
            1,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '88926596-fb58-4ab7-aef8-3bcb7f927b0a' OR (EntityID = 'A6B673F8-43BC-4875-AFF6-AC620592822E' AND Name = 'Labels')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '88926596-fb58-4ab7-aef8-3bcb7f927b0a',
            'A6B673F8-43BC-4875-AFF6-AC620592822E', -- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks
            (SELECT COALESCE(MAX([Sequence]), 0) + 1 FROM [${mjSchema}].[EntityField] WHERE [EntityID] = 'A6B673F8-43BC-4875-AFF6-AC620592822E'),
            'Labels',
            'Labels',
            'JSON array of GitHub label names applied to the pull request.',
            'nvarchar',
            -1,
            0,
            0,
            1,
            NULL,
            0,
            1,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '3a7bdb54-1596-447c-b919-0dba77bf1988' OR (EntityID = 'A6B673F8-43BC-4875-AFF6-AC620592822E' AND Name = 'Milestone')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '3a7bdb54-1596-447c-b919-0dba77bf1988',
            'A6B673F8-43BC-4875-AFF6-AC620592822E', -- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks
            (SELECT COALESCE(MAX([Sequence]), 0) + 1 FROM [${mjSchema}].[EntityField] WHERE [EntityID] = 'A6B673F8-43BC-4875-AFF6-AC620592822E'),
            'Milestone',
            'Milestone',
            'GitHub milestone title when assigned.',
            'nvarchar',
            510,
            0,
            0,
            1,
            NULL,
            0,
            1,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '4ccf1bdd-f21d-4003-8499-9a1d6c9c02e2' OR (EntityID = 'A6B673F8-43BC-4875-AFF6-AC620592822E' AND Name = 'MilestoneDueAt')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '4ccf1bdd-f21d-4003-8499-9a1d6c9c02e2',
            'A6B673F8-43BC-4875-AFF6-AC620592822E', -- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks
            (SELECT COALESCE(MAX([Sequence]), 0) + 1 FROM [${mjSchema}].[EntityField] WHERE [EntityID] = 'A6B673F8-43BC-4875-AFF6-AC620592822E'),
            'MilestoneDueAt',
            'Milestone Due At',
            'Due timestamp of the GitHub milestone; supersedes pending inferred DueAt Field Suggestions.',
            'datetimeoffset',
            10,
            34,
            7,
            1,
            NULL,
            0,
            1,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '4801e8b7-847b-411d-b5f0-002551b4f237' OR (EntityID = 'A6B673F8-43BC-4875-AFF6-AC620592822E' AND Name = 'MergedAt')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '4801e8b7-847b-411d-b5f0-002551b4f237',
            'A6B673F8-43BC-4875-AFF6-AC620592822E', -- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks
            (SELECT COALESCE(MAX([Sequence]), 0) + 1 FROM [${mjSchema}].[EntityField] WHERE [EntityID] = 'A6B673F8-43BC-4875-AFF6-AC620592822E'),
            'MergedAt',
            'Merged At',
            'Timestamp when the pull request was merged on GitHub.',
            'datetimeoffset',
            10,
            34,
            7,
            1,
            NULL,
            0,
            1,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = 'af64dc8d-5285-46a8-a44b-145bda229838' OR (EntityID = 'A6B673F8-43BC-4875-AFF6-AC620592822E' AND Name = 'LinkedIssueTaskID')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            'af64dc8d-5285-46a8-a44b-145bda229838',
            'A6B673F8-43BC-4875-AFF6-AC620592822E', -- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks
            (SELECT COALESCE(MAX([Sequence]), 0) + 1 FROM [${mjSchema}].[EntityField] WHERE [EntityID] = 'A6B673F8-43BC-4875-AFF6-AC620592822E'),
            'LinkedIssueTaskID',
            'Linked Issue Task ID',
            'Optional reference to the Task (e.g. GITHUB_ISSUE or FACTORY_WORK) that this pull request implements or closes.',
            'uniqueidentifier',
            16,
            0,
            0,
            1,
            NULL,
            0,
            1,
            0,
            0,
            'B348FFA2-B1A7-4AC2-B6FD-F4E0C0697466',
            'ID',
            0,
            0,
            1,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '6e18bab8-7f3d-42c0-ac47-d1ccb685a2e0' OR (EntityID = 'A6B673F8-43BC-4875-AFF6-AC620592822E' AND Name = 'BodyHash')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '6e18bab8-7f3d-42c0-ac47-d1ccb685a2e0',
            'A6B673F8-43BC-4875-AFF6-AC620592822E', -- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks
            (SELECT COALESCE(MAX([Sequence]), 0) + 1 FROM [${mjSchema}].[EntityField] WHERE [EntityID] = 'A6B673F8-43BC-4875-AFF6-AC620592822E'),
            'BodyHash',
            'Body Hash',
            'SHA-256 hash of the last synced pull request body used to detect text edits and trigger Field Suggestion re-inference.',
            'nvarchar',
            128,
            0,
            0,
            1,
            NULL,
            0,
            1,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = 'cfa8847f-9404-4b62-810f-863dd426852b' OR (EntityID = 'A6B673F8-43BC-4875-AFF6-AC620592822E' AND Name = 'GitHubUpdatedAt')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            'cfa8847f-9404-4b62-810f-863dd426852b',
            'A6B673F8-43BC-4875-AFF6-AC620592822E', -- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks
            (SELECT COALESCE(MAX([Sequence]), 0) + 1 FROM [${mjSchema}].[EntityField] WHERE [EntityID] = 'A6B673F8-43BC-4875-AFF6-AC620592822E'),
            'GitHubUpdatedAt',
            'Git Hub Updated At',
            'Upstream updated_at timestamp reported by GitHub.',
            'datetimeoffset',
            10,
            34,
            7,
            1,
            NULL,
            0,
            1,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '4e1457ac-6957-44b9-baf9-93c09114807e' OR (EntityID = 'A6B673F8-43BC-4875-AFF6-AC620592822E' AND Name = 'LastSyncedAt')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '4e1457ac-6957-44b9-baf9-93c09114807e',
            'A6B673F8-43BC-4875-AFF6-AC620592822E', -- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks
            (SELECT COALESCE(MAX([Sequence]), 0) + 1 FROM [${mjSchema}].[EntityField] WHERE [EntityID] = 'A6B673F8-43BC-4875-AFF6-AC620592822E'),
            'LastSyncedAt',
            'Last Synced At',
            'Timestamp when BizApps Tasks GitHub sync last reconciled this pull request.',
            'datetimeoffset',
            10,
            34,
            7,
            1,
            NULL,
            0,
            1,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '5d5a0e69-1ed4-4863-a611-34bf239fa515' OR (EntityID = 'A6B673F8-43BC-4875-AFF6-AC620592822E' AND Name = '__mj_CreatedAt')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '5d5a0e69-1ed4-4863-a611-34bf239fa515',
            'A6B673F8-43BC-4875-AFF6-AC620592822E', -- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks
            (SELECT COALESCE(MAX([Sequence]), 0) + 1 FROM [${mjSchema}].[EntityField] WHERE [EntityID] = 'A6B673F8-43BC-4875-AFF6-AC620592822E'),
            '__mj_CreatedAt',
            'Created At',
            NULL,
            'datetimeoffset',
            10,
            34,
            7,
            0,
            'getutcdate()',
            0,
            0,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = 'f3a56a47-49d7-4e66-b762-aedc7f65dbdb' OR (EntityID = 'A6B673F8-43BC-4875-AFF6-AC620592822E' AND Name = '__mj_UpdatedAt')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            'f3a56a47-49d7-4e66-b762-aedc7f65dbdb',
            'A6B673F8-43BC-4875-AFF6-AC620592822E', -- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks
            (SELECT COALESCE(MAX([Sequence]), 0) + 1 FROM [${mjSchema}].[EntityField] WHERE [EntityID] = 'A6B673F8-43BC-4875-AFF6-AC620592822E'),
            '__mj_UpdatedAt',
            'Updated At',
            NULL,
            'datetimeoffset',
            10,
            34,
            7,
            0,
            'getutcdate()',
            0,
            0,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

/* SQL text to update existing entity fields from schema */
EXEC [${mjSchema}].[spUpdateExistingEntityFieldsFromSchema] @ExcludedSchemaNames='', @IncludedSchemaNames='${flyway:defaultSchema}';

/* SQL text to set default column width where needed */
EXEC [${mjSchema}].[spSetDefaultColumnWidthWhereNeeded] @ExcludedSchemaNames='', @IncludedSchemaNames='${flyway:defaultSchema}';

/* SQL text to insert entity field value with ID 8c8c3982-1b02-4d76-9c3f-61f557196fde */
INSERT INTO [${mjSchema}].[EntityFieldValue]
                                       ([ID], [EntityFieldID], [Sequence], [Value], [Code], [Source], [__mj_CreatedAt], [__mj_UpdatedAt])
                                    VALUES
                                       ('8c8c3982-1b02-4d76-9c3f-61f557196fde', 'D09CC770-1CBB-4078-8186-BF3ED875F03C', 1, 'All', 'All', 'Check', GETUTCDATE(), GETUTCDATE());

/* SQL text to insert entity field value with ID ba996e4d-b437-484f-9b69-0b2c5a335417 */
INSERT INTO [${mjSchema}].[EntityFieldValue]
                                       ([ID], [EntityFieldID], [Sequence], [Value], [Code], [Source], [__mj_CreatedAt], [__mj_UpdatedAt])
                                    VALUES
                                       ('ba996e4d-b437-484f-9b69-0b2c5a335417', 'D09CC770-1CBB-4078-8186-BF3ED875F03C', 2, 'AssignedOnly', 'AssignedOnly', 'Check', GETUTCDATE(), GETUTCDATE());

/* SQL text to update ValueListType for entity field ID D09CC770-1CBB-4078-8186-BF3ED875F03C */
UPDATE [${mjSchema}].[EntityField] SET ValueListType='List' WHERE ID='D09CC770-1CBB-4078-8186-BF3ED875F03C';

/* SQL text to insert entity field value with ID 1b5b4514-5903-4025-bbe6-429b39a20d88 */
INSERT INTO [${mjSchema}].[EntityFieldValue]
                                       ([ID], [EntityFieldID], [Sequence], [Value], [Code], [Source], [__mj_CreatedAt], [__mj_UpdatedAt])
                                    VALUES
                                       ('1b5b4514-5903-4025-bbe6-429b39a20d88', '54CD3BC9-E3DF-4B33-9413-B2F137EB2452', 1, 'closed', 'closed', 'Check', GETUTCDATE(), GETUTCDATE());

/* SQL text to insert entity field value with ID bc36d270-d78c-4704-8705-ee4ca7a1f4b9 */
INSERT INTO [${mjSchema}].[EntityFieldValue]
                                       ([ID], [EntityFieldID], [Sequence], [Value], [Code], [Source], [__mj_CreatedAt], [__mj_UpdatedAt])
                                    VALUES
                                       ('bc36d270-d78c-4704-8705-ee4ca7a1f4b9', '54CD3BC9-E3DF-4B33-9413-B2F137EB2452', 2, 'open', 'open', 'Check', GETUTCDATE(), GETUTCDATE());

/* SQL text to update ValueListType for entity field ID 54CD3BC9-E3DF-4B33-9413-B2F137EB2452 */
UPDATE [${mjSchema}].[EntityField] SET ValueListType='List' WHERE ID='54CD3BC9-E3DF-4B33-9413-B2F137EB2452';

/* SQL text to insert entity field value with ID d4d4b560-1b25-49cb-b29e-bd1281de3a90 */
INSERT INTO [${mjSchema}].[EntityFieldValue]
                                       ([ID], [EntityFieldID], [Sequence], [Value], [Code], [Source], [__mj_CreatedAt], [__mj_UpdatedAt])
                                    VALUES
                                       ('d4d4b560-1b25-49cb-b29e-bd1281de3a90', 'AC27EB42-F18D-4444-99A2-9E454DBAEB49', 1, 'completed', 'completed', 'Check', GETUTCDATE(), GETUTCDATE());

/* SQL text to insert entity field value with ID f9f7b77e-670b-450e-94d6-d5bc4750bc24 */
INSERT INTO [${mjSchema}].[EntityFieldValue]
                                       ([ID], [EntityFieldID], [Sequence], [Value], [Code], [Source], [__mj_CreatedAt], [__mj_UpdatedAt])
                                    VALUES
                                       ('f9f7b77e-670b-450e-94d6-d5bc4750bc24', 'AC27EB42-F18D-4444-99A2-9E454DBAEB49', 2, 'duplicate', 'duplicate', 'Check', GETUTCDATE(), GETUTCDATE());

/* SQL text to insert entity field value with ID 97b353b7-4df6-47e8-9e6a-657bd3c02695 */
INSERT INTO [${mjSchema}].[EntityFieldValue]
                                       ([ID], [EntityFieldID], [Sequence], [Value], [Code], [Source], [__mj_CreatedAt], [__mj_UpdatedAt])
                                    VALUES
                                       ('97b353b7-4df6-47e8-9e6a-657bd3c02695', 'AC27EB42-F18D-4444-99A2-9E454DBAEB49', 3, 'not_planned', 'not_planned', 'Check', GETUTCDATE(), GETUTCDATE());

/* SQL text to insert entity field value with ID 93d0898d-073f-4845-8ead-36ed4383899e */
INSERT INTO [${mjSchema}].[EntityFieldValue]
                                       ([ID], [EntityFieldID], [Sequence], [Value], [Code], [Source], [__mj_CreatedAt], [__mj_UpdatedAt])
                                    VALUES
                                       ('93d0898d-073f-4845-8ead-36ed4383899e', 'AC27EB42-F18D-4444-99A2-9E454DBAEB49', 4, 'reopened', 'reopened', 'Check', GETUTCDATE(), GETUTCDATE());

/* SQL text to update ValueListType for entity field ID AC27EB42-F18D-4444-99A2-9E454DBAEB49 */
UPDATE [${mjSchema}].[EntityField] SET ValueListType='List' WHERE ID='AC27EB42-F18D-4444-99A2-9E454DBAEB49';

/* SQL text to insert entity field value with ID 10d2ab58-e633-4bc9-a41d-defb3eac7ffd */
INSERT INTO [${mjSchema}].[EntityFieldValue]
                                       ([ID], [EntityFieldID], [Sequence], [Value], [Code], [Source], [__mj_CreatedAt], [__mj_UpdatedAt])
                                    VALUES
                                       ('10d2ab58-e633-4bc9-a41d-defb3eac7ffd', '5CBFAABD-0AF2-4E67-91B1-F089E6C56C4D', 1, 'closed', 'closed', 'Check', GETUTCDATE(), GETUTCDATE());

/* SQL text to insert entity field value with ID 7e5a5659-0e7b-4eac-b6b6-b0c32ad144f0 */
INSERT INTO [${mjSchema}].[EntityFieldValue]
                                       ([ID], [EntityFieldID], [Sequence], [Value], [Code], [Source], [__mj_CreatedAt], [__mj_UpdatedAt])
                                    VALUES
                                       ('7e5a5659-0e7b-4eac-b6b6-b0c32ad144f0', '5CBFAABD-0AF2-4E67-91B1-F089E6C56C4D', 2, 'merged', 'merged', 'Check', GETUTCDATE(), GETUTCDATE());

/* SQL text to insert entity field value with ID 9b11894a-bec6-4f7e-8e64-ce143b88276f */
INSERT INTO [${mjSchema}].[EntityFieldValue]
                                       ([ID], [EntityFieldID], [Sequence], [Value], [Code], [Source], [__mj_CreatedAt], [__mj_UpdatedAt])
                                    VALUES
                                       ('9b11894a-bec6-4f7e-8e64-ce143b88276f', '5CBFAABD-0AF2-4E67-91B1-F089E6C56C4D', 3, 'open', 'open', 'Check', GETUTCDATE(), GETUTCDATE());

/* SQL text to update ValueListType for entity field ID 5CBFAABD-0AF2-4E67-91B1-F089E6C56C4D */
UPDATE [${mjSchema}].[EntityField] SET ValueListType='List' WHERE ID='5CBFAABD-0AF2-4E67-91B1-F089E6C56C4D';

/* SQL text to insert entity field value with ID ed759dfa-1781-4f43-92b2-cc725ecf4a19 */
INSERT INTO [${mjSchema}].[EntityFieldValue]
                                       ([ID], [EntityFieldID], [Sequence], [Value], [Code], [Source], [__mj_CreatedAt], [__mj_UpdatedAt])
                                    VALUES
                                       ('ed759dfa-1781-4f43-92b2-cc725ecf4a19', 'D0242DB3-ACFC-4AD6-9B8A-7AF48E27BBE4', 1, 'APPROVED', 'APPROVED', 'Check', GETUTCDATE(), GETUTCDATE());

/* SQL text to insert entity field value with ID be4c345c-aa49-4bb2-a197-5541fa02a4d9 */
INSERT INTO [${mjSchema}].[EntityFieldValue]
                                       ([ID], [EntityFieldID], [Sequence], [Value], [Code], [Source], [__mj_CreatedAt], [__mj_UpdatedAt])
                                    VALUES
                                       ('be4c345c-aa49-4bb2-a197-5541fa02a4d9', 'D0242DB3-ACFC-4AD6-9B8A-7AF48E27BBE4', 2, 'CHANGES_REQUESTED', 'CHANGES_REQUESTED', 'Check', GETUTCDATE(), GETUTCDATE());

/* SQL text to insert entity field value with ID 78463bdd-98f6-4aab-b237-c1ea739f6ed4 */
INSERT INTO [${mjSchema}].[EntityFieldValue]
                                       ([ID], [EntityFieldID], [Sequence], [Value], [Code], [Source], [__mj_CreatedAt], [__mj_UpdatedAt])
                                    VALUES
                                       ('78463bdd-98f6-4aab-b237-c1ea739f6ed4', 'D0242DB3-ACFC-4AD6-9B8A-7AF48E27BBE4', 3, 'REVIEW_REQUIRED', 'REVIEW_REQUIRED', 'Check', GETUTCDATE(), GETUTCDATE());

/* SQL text to update ValueListType for entity field ID D0242DB3-ACFC-4AD6-9B8A-7AF48E27BBE4 */
UPDATE [${mjSchema}].[EntityField] SET ValueListType='List' WHERE ID='D0242DB3-ACFC-4AD6-9B8A-7AF48E27BBE4';

/* SQL text to insert entity field value with ID b22540b8-fe08-407d-9660-f3ea4c96d295 */
INSERT INTO [${mjSchema}].[EntityFieldValue]
                                       ([ID], [EntityFieldID], [Sequence], [Value], [Code], [Source], [__mj_CreatedAt], [__mj_UpdatedAt])
                                    VALUES
                                       ('b22540b8-fe08-407d-9660-f3ea4c96d295', '57B97F3B-7437-49C3-A2A3-89F8F14F3224', 1, 'Failing', 'Failing', 'Check', GETUTCDATE(), GETUTCDATE());

/* SQL text to insert entity field value with ID a61af79c-cbce-4957-b745-553788b8d3e9 */
INSERT INTO [${mjSchema}].[EntityFieldValue]
                                       ([ID], [EntityFieldID], [Sequence], [Value], [Code], [Source], [__mj_CreatedAt], [__mj_UpdatedAt])
                                    VALUES
                                       ('a61af79c-cbce-4957-b745-553788b8d3e9', '57B97F3B-7437-49C3-A2A3-89F8F14F3224', 2, 'Neutral', 'Neutral', 'Check', GETUTCDATE(), GETUTCDATE());

/* SQL text to insert entity field value with ID b1956394-c71c-4a3b-b69d-c1e19ea4f88e */
INSERT INTO [${mjSchema}].[EntityFieldValue]
                                       ([ID], [EntityFieldID], [Sequence], [Value], [Code], [Source], [__mj_CreatedAt], [__mj_UpdatedAt])
                                    VALUES
                                       ('b1956394-c71c-4a3b-b69d-c1e19ea4f88e', '57B97F3B-7437-49C3-A2A3-89F8F14F3224', 3, 'Passing', 'Passing', 'Check', GETUTCDATE(), GETUTCDATE());

/* SQL text to insert entity field value with ID 35bed740-35c8-4e45-a029-036731451086 */
INSERT INTO [${mjSchema}].[EntityFieldValue]
                                       ([ID], [EntityFieldID], [Sequence], [Value], [Code], [Source], [__mj_CreatedAt], [__mj_UpdatedAt])
                                    VALUES
                                       ('35bed740-35c8-4e45-a029-036731451086', '57B97F3B-7437-49C3-A2A3-89F8F14F3224', 4, 'Pending', 'Pending', 'Check', GETUTCDATE(), GETUTCDATE());

/* SQL text to update ValueListType for entity field ID 57B97F3B-7437-49C3-A2A3-89F8F14F3224 */
UPDATE [${mjSchema}].[EntityField] SET ValueListType='List' WHERE ID='57B97F3B-7437-49C3-A2A3-89F8F14F3224';

/* Deterministic search-flag hygiene — clear AllowUserSearchAPI */

         UPDATE [${mjSchema}].[Entity]
         SET [AllowUserSearchAPI] = 0
         WHERE [ID] IN (
            SELECT e.[ID]
            FROM [${mjSchema}].[Entity] e
            WHERE e.[AllowUserSearchAPI] = 1
              AND e.[AutoUpdateAllowUserSearchAPI] = 1
              AND e.[VirtualEntity] = 0
              AND ISNULL(e.[FullTextSearchEnabled], 0) = 0
              AND e.[SchemaName] NOT IN ('${mjSchema}','__mj_BizAppsAccounting','__mj_BizAppsCommon','__mj_BizAppsOrders','__mj_BizAppsTasks','sys')
              AND NOT EXISTS (
               SELECT 1 FROM [${mjSchema}].[EntityField] f2
               WHERE f2.[EntityID] = e.[ID]
                 AND f2.[IncludeInUserSearchAPI] = 1
            )
         );


/* Create Entity Relationship: MJ_BizApps_Tasks_GitHub: Git Hub Repositories -> MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks (One To Many via RepositoryID) */
   IF NOT EXISTS (
      SELECT 1 FROM [${mjSchema}].[EntityRelationship] WHERE [ID] = 'e3e49d6f-6251-4286-8024-4da8b4f074d9' OR ([EntityID] = '6B363236-31AB-477D-8188-08F5FA9942EF' AND [RelatedEntityID] = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605' AND [RelatedEntityJoinField] = 'RepositoryID')
   )
   BEGIN
      INSERT INTO [${mjSchema}].[EntityRelationship] ([ID], [EntityID], [RelatedEntityID], [RelatedEntityJoinField], [Type], [BundleInAPI], [DisplayInForm], [Sequence], [__mj_CreatedAt], [__mj_UpdatedAt])
                    VALUES ('e3e49d6f-6251-4286-8024-4da8b4f074d9', '6B363236-31AB-477D-8188-08F5FA9942EF', 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605', 'RepositoryID', 'One To Many', 1, 1, 1, GETUTCDATE(), GETUTCDATE())
   END;
                    
/* Create Entity Relationship: MJ_BizApps_Tasks_GitHub: Git Hub Repositories -> MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks (One To Many via RepositoryID) */
   IF NOT EXISTS (
      SELECT 1 FROM [${mjSchema}].[EntityRelationship] WHERE [ID] = '4557bdcd-cc5d-4d76-9570-d19af339c7be' OR ([EntityID] = '6B363236-31AB-477D-8188-08F5FA9942EF' AND [RelatedEntityID] = 'A6B673F8-43BC-4875-AFF6-AC620592822E' AND [RelatedEntityJoinField] = 'RepositoryID')
   )
   BEGIN
      INSERT INTO [${mjSchema}].[EntityRelationship] ([ID], [EntityID], [RelatedEntityID], [RelatedEntityJoinField], [Type], [BundleInAPI], [DisplayInForm], [Sequence], [__mj_CreatedAt], [__mj_UpdatedAt])
                    VALUES ('4557bdcd-cc5d-4d76-9570-d19af339c7be', '6B363236-31AB-477D-8188-08F5FA9942EF', 'A6B673F8-43BC-4875-AFF6-AC620592822E', 'RepositoryID', 'One To Many', 1, 1, 2, GETUTCDATE(), GETUTCDATE())
   END;
                    
/* Create Entity Relationship: MJ_BizApps_Common: Organizations -> MJ_BizApps_Tasks_GitHub: Git Hub Repositories (One To Many via OrganizationID) */
   IF NOT EXISTS (
      SELECT 1 FROM [${mjSchema}].[EntityRelationship] WHERE [ID] = '4a8f7207-f2e6-4099-a4bf-f9ecba2397b2' OR ([EntityID] = 'C70448F9-9792-41D7-A82C-784B66429D54' AND [RelatedEntityID] = '6B363236-31AB-477D-8188-08F5FA9942EF' AND [RelatedEntityJoinField] = 'OrganizationID')
   )
   BEGIN
      INSERT INTO [${mjSchema}].[EntityRelationship] ([ID], [EntityID], [RelatedEntityID], [RelatedEntityJoinField], [Type], [BundleInAPI], [DisplayInForm], [Sequence], [__mj_CreatedAt], [__mj_UpdatedAt])
                    VALUES ('4a8f7207-f2e6-4099-a4bf-f9ecba2397b2', 'C70448F9-9792-41D7-A82C-784B66429D54', '6B363236-31AB-477D-8188-08F5FA9942EF', 'OrganizationID', 'One To Many', 1, 1, 19, GETUTCDATE(), GETUTCDATE())
   END;
                    
/* Create Entity Relationship: MJ_BizApps_Common: People -> MJ_BizApps_Tasks_GitHub: Git Hub Identities (One To Many via PersonID) */
   IF NOT EXISTS (
      SELECT 1 FROM [${mjSchema}].[EntityRelationship] WHERE [ID] = 'aeb83264-4f5b-48b5-9b45-e3a0826045d0' OR ([EntityID] = '7A94ADA9-7880-4FAE-97D8-DB0E934C3F5F' AND [RelatedEntityID] = 'C7CC2BCF-090E-4832-89C7-A051F302C393' AND [RelatedEntityJoinField] = 'PersonID')
   )
   BEGIN
      INSERT INTO [${mjSchema}].[EntityRelationship] ([ID], [EntityID], [RelatedEntityID], [RelatedEntityJoinField], [Type], [BundleInAPI], [DisplayInForm], [Sequence], [__mj_CreatedAt], [__mj_UpdatedAt])
                    VALUES ('aeb83264-4f5b-48b5-9b45-e3a0826045d0', '7A94ADA9-7880-4FAE-97D8-DB0E934C3F5F', 'C7CC2BCF-090E-4832-89C7-A051F302C393', 'PersonID', 'One To Many', 1, 1, 29, GETUTCDATE(), GETUTCDATE())
   END;
                    
/* Create Entity Relationship: MJ_BizApps_Tasks: Tasks -> MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks (One To Many via ID) */
   IF NOT EXISTS (
      SELECT 1 FROM [${mjSchema}].[EntityRelationship] WHERE [ID] = '1a25a4ba-8160-4aa9-b9cc-16f9ddff33cb' OR ([EntityID] = 'B348FFA2-B1A7-4AC2-B6FD-F4E0C0697466' AND [RelatedEntityID] = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605' AND [RelatedEntityJoinField] = 'ID')
   )
   BEGIN
      INSERT INTO [${mjSchema}].[EntityRelationship] ([ID], [EntityID], [RelatedEntityID], [RelatedEntityJoinField], [Type], [BundleInAPI], [DisplayInForm], [Sequence], [__mj_CreatedAt], [__mj_UpdatedAt])
                    VALUES ('1a25a4ba-8160-4aa9-b9cc-16f9ddff33cb', 'B348FFA2-B1A7-4AC2-B6FD-F4E0C0697466', 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605', 'ID', 'One To Many', 1, 1, 17, GETUTCDATE(), GETUTCDATE())
   END;


/* Create Entity Relationship: MJ_BizApps_Tasks: Tasks -> MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks (One To Many via ID) */
   IF NOT EXISTS (
      SELECT 1 FROM [${mjSchema}].[EntityRelationship] WHERE [ID] = '5ed8b56d-29da-442d-81dd-2f7110a01b23' OR ([EntityID] = 'B348FFA2-B1A7-4AC2-B6FD-F4E0C0697466' AND [RelatedEntityID] = 'A6B673F8-43BC-4875-AFF6-AC620592822E' AND [RelatedEntityJoinField] = 'ID')
   )
   BEGIN
      INSERT INTO [${mjSchema}].[EntityRelationship] ([ID], [EntityID], [RelatedEntityID], [RelatedEntityJoinField], [Type], [BundleInAPI], [DisplayInForm], [Sequence], [__mj_CreatedAt], [__mj_UpdatedAt])
                    VALUES ('5ed8b56d-29da-442d-81dd-2f7110a01b23', 'B348FFA2-B1A7-4AC2-B6FD-F4E0C0697466', 'A6B673F8-43BC-4875-AFF6-AC620592822E', 'ID', 'One To Many', 1, 1, 18, GETUTCDATE(), GETUTCDATE())
   END;
                    
/* Create Entity Relationship: MJ_BizApps_Tasks: Tasks -> MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks (One To Many via LinkedIssueTaskID) */
   IF NOT EXISTS (
      SELECT 1 FROM [${mjSchema}].[EntityRelationship] WHERE [ID] = 'cb4e2dff-4613-4bd1-9e43-c6bebdac19bf' OR ([EntityID] = 'B348FFA2-B1A7-4AC2-B6FD-F4E0C0697466' AND [RelatedEntityID] = 'A6B673F8-43BC-4875-AFF6-AC620592822E' AND [RelatedEntityJoinField] = 'LinkedIssueTaskID')
   )
   BEGIN
      INSERT INTO [${mjSchema}].[EntityRelationship] ([ID], [EntityID], [RelatedEntityID], [RelatedEntityJoinField], [Type], [BundleInAPI], [DisplayInForm], [Sequence], [__mj_CreatedAt], [__mj_UpdatedAt])
                    VALUES ('cb4e2dff-4613-4bd1-9e43-c6bebdac19bf', 'B348FFA2-B1A7-4AC2-B6FD-F4E0C0697466', 'A6B673F8-43BC-4875-AFF6-AC620592822E', 'LinkedIssueTaskID', 'One To Many', 1, 1, 19, GETUTCDATE(), GETUTCDATE())
   END;

/* SQL text to sync schema info from database schemas */
EXEC [${mjSchema}].[spUpdateSchemaInfoFromDatabase] @ExcludedSchemaNames='', @IncludedSchemaNames='${flyway:defaultSchema}';

/* Index for Foreign Keys for GitHubIdentity */
-----------------------------------------------------------------
-- SQL Code Generation
-- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Identities
-- Item: Index for Foreign Keys
--
-- This was generated by the MemberJunction CodeGen tool.
-- This file should NOT be edited by hand.
-----------------------------------------------------------------
-- Index for foreign key PersonID in table GitHubIdentity
IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = 'IDX_AUTO_MJ_FKEY_GitHubIdentity_PersonID' 
    AND object_id = OBJECT_ID('[${flyway:defaultSchema}].[GitHubIdentity]')
)
CREATE INDEX IDX_AUTO_MJ_FKEY_GitHubIdentity_PersonID ON [${flyway:defaultSchema}].[GitHubIdentity] ([PersonID]);

/* SQL text to update entity field related entity name field map for entity field ID 86923F31-A619-4171-9700-360D0F84EAEE */
EXEC [${mjSchema}].[spUpdateEntityFieldRelatedEntityNameFieldMap] @EntityFieldID='86923F31-A619-4171-9700-360D0F84EAEE', @RelatedEntityNameFieldMap='Person';

/* Index for Foreign Keys for GitHubIssueTask */
-----------------------------------------------------------------
-- SQL Code Generation
-- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks
-- Item: Index for Foreign Keys
--
-- This was generated by the MemberJunction CodeGen tool.
-- This file should NOT be edited by hand.
-----------------------------------------------------------------
-- Index for foreign key RepositoryID in table GitHubIssueTask
IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = 'IDX_AUTO_MJ_FKEY_GitHubIssueTask_RepositoryID' 
    AND object_id = OBJECT_ID('[${flyway:defaultSchema}].[GitHubIssueTask]')
)
CREATE INDEX IDX_AUTO_MJ_FKEY_GitHubIssueTask_RepositoryID ON [${flyway:defaultSchema}].[GitHubIssueTask] ([RepositoryID]);

/* SQL text to update entity field related entity name field map for entity field ID 54442A79-CEAD-408B-82AA-4119053FE27E */
EXEC [${mjSchema}].[spUpdateEntityFieldRelatedEntityNameFieldMap] @EntityFieldID='54442A79-CEAD-408B-82AA-4119053FE27E', @RelatedEntityNameFieldMap='Repository';

/* Index for Foreign Keys for GitHubPullRequestTask */
-----------------------------------------------------------------
-- SQL Code Generation
-- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks
-- Item: Index for Foreign Keys
--
-- This was generated by the MemberJunction CodeGen tool.
-- This file should NOT be edited by hand.
-----------------------------------------------------------------
-- Index for foreign key RepositoryID in table GitHubPullRequestTask
IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = 'IDX_AUTO_MJ_FKEY_GitHubPullRequestTask_RepositoryID' 
    AND object_id = OBJECT_ID('[${flyway:defaultSchema}].[GitHubPullRequestTask]')
)
CREATE INDEX IDX_AUTO_MJ_FKEY_GitHubPullRequestTask_RepositoryID ON [${flyway:defaultSchema}].[GitHubPullRequestTask] ([RepositoryID]);

-- Index for foreign key LinkedIssueTaskID in table GitHubPullRequestTask
IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = 'IDX_AUTO_MJ_FKEY_GitHubPullRequestTask_LinkedIssueTaskID' 
    AND object_id = OBJECT_ID('[${flyway:defaultSchema}].[GitHubPullRequestTask]')
)
CREATE INDEX IDX_AUTO_MJ_FKEY_GitHubPullRequestTask_LinkedIssueTaskID ON [${flyway:defaultSchema}].[GitHubPullRequestTask] ([LinkedIssueTaskID]);

/* SQL text to update entity field related entity name field map for entity field ID 80C22B8D-1383-4AC3-BC9D-6540C3FDED78 */
EXEC [${mjSchema}].[spUpdateEntityFieldRelatedEntityNameFieldMap] @EntityFieldID='80C22B8D-1383-4AC3-BC9D-6540C3FDED78', @RelatedEntityNameFieldMap='Repository';

/* Index for Foreign Keys for GitHubRepository */
-----------------------------------------------------------------
-- SQL Code Generation
-- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Repositories
-- Item: Index for Foreign Keys
--
-- This was generated by the MemberJunction CodeGen tool.
-- This file should NOT be edited by hand.
-----------------------------------------------------------------
-- Index for foreign key OrganizationID in table GitHubRepository
IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = 'IDX_AUTO_MJ_FKEY_GitHubRepository_OrganizationID' 
    AND object_id = OBJECT_ID('[${flyway:defaultSchema}].[GitHubRepository]')
)
CREATE INDEX IDX_AUTO_MJ_FKEY_GitHubRepository_OrganizationID ON [${flyway:defaultSchema}].[GitHubRepository] ([OrganizationID]);

/* SQL text to update entity field related entity name field map for entity field ID 507961D4-497E-4B22-9CFF-C6506F32B45C */
EXEC [${mjSchema}].[spUpdateEntityFieldRelatedEntityNameFieldMap] @EntityFieldID='507961D4-497E-4B22-9CFF-C6506F32B45C', @RelatedEntityNameFieldMap='Organization';

/* Base View SQL for MJ_BizApps_Tasks_GitHub: Git Hub Identities */
-----------------------------------------------------------------
-- SQL Code Generation
-- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Identities
-- Item: vwGitHubIdentities
--
-- This was generated by the MemberJunction CodeGen tool.
-- This file should NOT be edited by hand.
-----------------------------------------------------------------

------------------------------------------------------------
----- BASE VIEW FOR ENTITY:      MJ_BizApps_Tasks_GitHub: Git Hub Identities
-----               SCHEMA:      ${flyway:defaultSchema}
-----               BASE TABLE:  GitHubIdentity
-----               PRIMARY KEY: ID
------------------------------------------------------------
IF OBJECT_ID('[${flyway:defaultSchema}].[vwGitHubIdentities]', 'V') IS NOT NULL
    DROP VIEW [${flyway:defaultSchema}].[vwGitHubIdentities];
GO

CREATE VIEW [${flyway:defaultSchema}].[vwGitHubIdentities]
AS
SELECT
    g.*,
    mjBizAppsCommonPerson_PersonID.[DisplayName] AS [Person]
FROM
    [${flyway:defaultSchema}].[GitHubIdentity] AS g
LEFT OUTER JOIN
    [__mj_BizAppsCommon].[Person] AS mjBizAppsCommonPerson_PersonID
  ON
    [g].[PersonID] = mjBizAppsCommonPerson_PersonID.[ID]
GO
GRANT SELECT ON [${flyway:defaultSchema}].[vwGitHubIdentities] TO [cdp_UI], [cdp_Developer], [cdp_Integration];

/* Base View Permissions SQL for MJ_BizApps_Tasks_GitHub: Git Hub Identities */
-----------------------------------------------------------------
-- SQL Code Generation
-- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Identities
-- Item: Permissions for vwGitHubIdentities
--
-- This was generated by the MemberJunction CodeGen tool.
-- This file should NOT be edited by hand.
-----------------------------------------------------------------

GRANT SELECT ON [${flyway:defaultSchema}].[vwGitHubIdentities] TO [cdp_UI], [cdp_Developer], [cdp_Integration];

/* spCreate SQL for MJ_BizApps_Tasks_GitHub: Git Hub Identities */
-----------------------------------------------------------------
-- SQL Code Generation
-- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Identities
-- Item: spCreateGitHubIdentity
--
-- This was generated by the MemberJunction CodeGen tool.
-- This file should NOT be edited by hand.
-----------------------------------------------------------------

------------------------------------------------------------
----- CREATE PROCEDURE FOR GitHubIdentity
------------------------------------------------------------
IF OBJECT_ID('[${flyway:defaultSchema}].[spCreateGitHubIdentity]', 'P') IS NOT NULL
    DROP PROCEDURE [${flyway:defaultSchema}].[spCreateGitHubIdentity];
GO

CREATE PROCEDURE [${flyway:defaultSchema}].[spCreateGitHubIdentity]
    @ID uniqueidentifier = NULL,
    @GitHubLogin nvarchar(100),
    @PersonID uniqueidentifier,
    @GitHubUserID_Clear bit = 0,
    @GitHubUserID nvarchar(64) = NULL,
    @IsActive bit = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @InsertedRow TABLE ([ID] UNIQUEIDENTIFIER)

    IF @ID IS NOT NULL
    BEGIN
        -- User provided a value, use it
        INSERT INTO [${flyway:defaultSchema}].[GitHubIdentity]
            (
                [ID],
                [GitHubLogin],
                [PersonID],
                [GitHubUserID],
                [IsActive]
            )
        OUTPUT INSERTED.[ID] INTO @InsertedRow
        VALUES
            (
                @ID,
                @GitHubLogin,
                @PersonID,
                CASE WHEN @GitHubUserID_Clear = 1 THEN NULL ELSE ISNULL(@GitHubUserID, NULL) END,
                ISNULL(@IsActive, 1)
            )
    END
    ELSE
    BEGIN
        -- No value provided, let database use its default (e.g., NEWSEQUENTIALID())
        INSERT INTO [${flyway:defaultSchema}].[GitHubIdentity]
            (
                [GitHubLogin],
                [PersonID],
                [GitHubUserID],
                [IsActive]
            )
        OUTPUT INSERTED.[ID] INTO @InsertedRow
        VALUES
            (
                @GitHubLogin,
                @PersonID,
                CASE WHEN @GitHubUserID_Clear = 1 THEN NULL ELSE ISNULL(@GitHubUserID, NULL) END,
                ISNULL(@IsActive, 1)
            )
    END
    -- return the new record from the base view, which might have some calculated fields
    SELECT * FROM [${flyway:defaultSchema}].[vwGitHubIdentities] WHERE [ID] = (SELECT [ID] FROM @InsertedRow)
END
GO
GRANT EXECUTE ON [${flyway:defaultSchema}].[spCreateGitHubIdentity] TO [cdp_Developer], [cdp_Integration];

/* spCreate Permissions for MJ_BizApps_Tasks_GitHub: Git Hub Identities */

GRANT EXECUTE ON [${flyway:defaultSchema}].[spCreateGitHubIdentity] TO [cdp_Developer], [cdp_Integration];

/* spUpdate SQL for MJ_BizApps_Tasks_GitHub: Git Hub Identities */
-----------------------------------------------------------------
-- SQL Code Generation
-- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Identities
-- Item: spUpdateGitHubIdentity
--
-- This was generated by the MemberJunction CodeGen tool.
-- This file should NOT be edited by hand.
-----------------------------------------------------------------

------------------------------------------------------------
----- UPDATE PROCEDURE FOR GitHubIdentity
------------------------------------------------------------
IF OBJECT_ID('[${flyway:defaultSchema}].[spUpdateGitHubIdentity]', 'P') IS NOT NULL
    DROP PROCEDURE [${flyway:defaultSchema}].[spUpdateGitHubIdentity];
GO

CREATE PROCEDURE [${flyway:defaultSchema}].[spUpdateGitHubIdentity]
    @ID uniqueidentifier,
    @GitHubLogin nvarchar(100) = NULL,
    @PersonID uniqueidentifier = NULL,
    @GitHubUserID_Clear bit = 0,
    @GitHubUserID nvarchar(64) = NULL,
    @IsActive bit = NULL
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE
        [${flyway:defaultSchema}].[GitHubIdentity]
    SET
        [GitHubLogin] = ISNULL(@GitHubLogin, [GitHubLogin]),
        [PersonID] = ISNULL(@PersonID, [PersonID]),
        [GitHubUserID] = CASE WHEN @GitHubUserID_Clear = 1 THEN NULL ELSE ISNULL(@GitHubUserID, [GitHubUserID]) END,
        [IsActive] = ISNULL(@IsActive, [IsActive])
    WHERE
        [ID] = @ID

    -- Check if the update was successful
    IF @@ROWCOUNT = 0
        -- Nothing was updated, return no rows, but column structure from base view intact, semantically correct this way.
        SELECT TOP 0 * FROM [${flyway:defaultSchema}].[vwGitHubIdentities] WHERE 1=0
    ELSE
        -- Return the updated record so the caller can see the updated values and any calculated fields
        SELECT
                                        *
                                    FROM
                                        [${flyway:defaultSchema}].[vwGitHubIdentities]
                                    WHERE
                                        [ID] = @ID
                                    
END
GO

GRANT EXECUTE ON [${flyway:defaultSchema}].[spUpdateGitHubIdentity] TO [cdp_Developer], [cdp_Integration]
GO

------------------------------------------------------------
----- TRIGGER FOR __mj_UpdatedAt field for the GitHubIdentity table
------------------------------------------------------------
IF OBJECT_ID('[${flyway:defaultSchema}].[trgUpdateGitHubIdentity]', 'TR') IS NOT NULL
    DROP TRIGGER [${flyway:defaultSchema}].[trgUpdateGitHubIdentity];
GO
CREATE TRIGGER [${flyway:defaultSchema}].trgUpdateGitHubIdentity
ON [${flyway:defaultSchema}].[GitHubIdentity]
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE
        [${flyway:defaultSchema}].[GitHubIdentity]
    SET
        __mj_UpdatedAt = GETUTCDATE()
    FROM
        [${flyway:defaultSchema}].[GitHubIdentity] AS _organicTable
    INNER JOIN
        INSERTED AS I ON
        _organicTable.[ID] = I.[ID];
END;
GO

/* spUpdate Permissions for MJ_BizApps_Tasks_GitHub: Git Hub Identities */

GRANT EXECUTE ON [${flyway:defaultSchema}].[spUpdateGitHubIdentity] TO [cdp_Developer], [cdp_Integration];

/* spDelete SQL for MJ_BizApps_Tasks_GitHub: Git Hub Identities */
-----------------------------------------------------------------
-- SQL Code Generation
-- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Identities
-- Item: spDeleteGitHubIdentity
--
-- This was generated by the MemberJunction CodeGen tool.
-- This file should NOT be edited by hand.
-----------------------------------------------------------------

------------------------------------------------------------
----- DELETE PROCEDURE FOR GitHubIdentity
------------------------------------------------------------
IF OBJECT_ID('[${flyway:defaultSchema}].[spDeleteGitHubIdentity]', 'P') IS NOT NULL
    DROP PROCEDURE [${flyway:defaultSchema}].[spDeleteGitHubIdentity];
GO

CREATE PROCEDURE [${flyway:defaultSchema}].[spDeleteGitHubIdentity]
    @ID uniqueidentifier
AS
BEGIN
    SET NOCOUNT ON;

    DELETE FROM
        [${flyway:defaultSchema}].[GitHubIdentity]
    WHERE
        [ID] = @ID


    -- Check if the delete was successful
    IF @@ROWCOUNT = 0
        SELECT NULL AS [ID] -- Return NULL for all primary key fields to indicate no record was deleted
    ELSE
        SELECT @ID AS [ID] -- Return the primary key values to indicate we successfully deleted the record
END
GO
GRANT EXECUTE ON [${flyway:defaultSchema}].[spDeleteGitHubIdentity] TO [cdp_Developer], [cdp_Integration];

/* spDelete Permissions for MJ_BizApps_Tasks_GitHub: Git Hub Identities */

GRANT EXECUTE ON [${flyway:defaultSchema}].[spDeleteGitHubIdentity] TO [cdp_Developer], [cdp_Integration];

/* SQL text to update entity field related entity name field map for entity field ID AF64DC8D-5285-46A8-A44B-145BDA229838 */
EXEC [${mjSchema}].[spUpdateEntityFieldRelatedEntityNameFieldMap] @EntityFieldID='AF64DC8D-5285-46A8-A44B-145BDA229838', @RelatedEntityNameFieldMap='LinkedIssueTask';

/* Base View SQL for MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks */
-----------------------------------------------------------------
-- SQL Code Generation
-- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks
-- Item: vwGitHubIssueTasks
--
-- This was generated by the MemberJunction CodeGen tool.
-- This file should NOT be edited by hand.
-----------------------------------------------------------------

------------------------------------------------------------
----- BASE VIEW FOR ENTITY:      MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks
-----               SCHEMA:      ${flyway:defaultSchema}
-----               BASE TABLE:  GitHubIssueTask
-----               PRIMARY KEY: ID
------------------------------------------------------------
IF OBJECT_ID('[${flyway:defaultSchema}].[vwGitHubIssueTasks]', 'V') IS NOT NULL
    DROP VIEW [${flyway:defaultSchema}].[vwGitHubIssueTasks];
GO

CREATE VIEW [${flyway:defaultSchema}].[vwGitHubIssueTasks]
AS
SELECT
    g.*,
    mjBizAppsTasksGitHubGitHubRepository_RepositoryID.[Name] AS [Repository]
FROM
    [${flyway:defaultSchema}].[GitHubIssueTask] AS g
LEFT OUTER JOIN
    [${flyway:defaultSchema}].[GitHubRepository] AS mjBizAppsTasksGitHubGitHubRepository_RepositoryID
  ON
    [g].[RepositoryID] = mjBizAppsTasksGitHubGitHubRepository_RepositoryID.[ID]
GO
GRANT SELECT ON [${flyway:defaultSchema}].[vwGitHubIssueTasks] TO [cdp_UI], [cdp_Developer], [cdp_Integration];

/* Base View Permissions SQL for MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks */
-----------------------------------------------------------------
-- SQL Code Generation
-- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks
-- Item: Permissions for vwGitHubIssueTasks
--
-- This was generated by the MemberJunction CodeGen tool.
-- This file should NOT be edited by hand.
-----------------------------------------------------------------

GRANT SELECT ON [${flyway:defaultSchema}].[vwGitHubIssueTasks] TO [cdp_UI], [cdp_Developer], [cdp_Integration];

/* spCreate SQL for MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks */
-----------------------------------------------------------------
-- SQL Code Generation
-- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks
-- Item: spCreateGitHubIssueTask
--
-- This was generated by the MemberJunction CodeGen tool.
-- This file should NOT be edited by hand.
-----------------------------------------------------------------

------------------------------------------------------------
----- CREATE PROCEDURE FOR GitHubIssueTask
------------------------------------------------------------
IF OBJECT_ID('[${flyway:defaultSchema}].[spCreateGitHubIssueTask]', 'P') IS NOT NULL
    DROP PROCEDURE [${flyway:defaultSchema}].[spCreateGitHubIssueTask];
GO

CREATE PROCEDURE [${flyway:defaultSchema}].[spCreateGitHubIssueTask]
    @ID uniqueidentifier = NULL,
    @RepositoryID_Clear bit = 0,
    @RepositoryID uniqueidentifier = NULL,
    @Number_Clear bit = 0,
    @Number int = NULL,
    @NodeID_Clear bit = 0,
    @NodeID nvarchar(128) = NULL,
    @HtmlURL_Clear bit = 0,
    @HtmlURL nvarchar(1000) = NULL,
    @State nvarchar(20) = NULL,
    @StateReason_Clear bit = 0,
    @StateReason nvarchar(40) = NULL,
    @Labels_Clear bit = 0,
    @Labels nvarchar(MAX) = NULL,
    @Milestone_Clear bit = 0,
    @Milestone nvarchar(255) = NULL,
    @MilestoneDueAt_Clear bit = 0,
    @MilestoneDueAt datetimeoffset = NULL,
    @AuthorLogin_Clear bit = 0,
    @AuthorLogin nvarchar(100) = NULL,
    @BodyHash_Clear bit = 0,
    @BodyHash nvarchar(64) = NULL,
    @GitHubUpdatedAt_Clear bit = 0,
    @GitHubUpdatedAt datetimeoffset = NULL,
    @LastSyncedAt_Clear bit = 0,
    @LastSyncedAt datetimeoffset = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @ActualID UNIQUEIDENTIFIER = ISNULL(@ID, NEWID())
    INSERT INTO
    [${flyway:defaultSchema}].[GitHubIssueTask]
        (
            [RepositoryID],
                [Number],
                [NodeID],
                [HtmlURL],
                [State],
                [StateReason],
                [Labels],
                [Milestone],
                [MilestoneDueAt],
                [AuthorLogin],
                [BodyHash],
                [GitHubUpdatedAt],
                [LastSyncedAt],
                [ID]
        )
    VALUES
        (
            CASE WHEN @RepositoryID_Clear = 1 THEN NULL ELSE ISNULL(@RepositoryID, NULL) END,
                CASE WHEN @Number_Clear = 1 THEN NULL ELSE ISNULL(@Number, NULL) END,
                CASE WHEN @NodeID_Clear = 1 THEN NULL ELSE ISNULL(@NodeID, NULL) END,
                CASE WHEN @HtmlURL_Clear = 1 THEN NULL ELSE ISNULL(@HtmlURL, NULL) END,
                ISNULL(@State, 'open'),
                CASE WHEN @StateReason_Clear = 1 THEN NULL ELSE ISNULL(@StateReason, NULL) END,
                CASE WHEN @Labels_Clear = 1 THEN NULL ELSE ISNULL(@Labels, NULL) END,
                CASE WHEN @Milestone_Clear = 1 THEN NULL ELSE ISNULL(@Milestone, NULL) END,
                CASE WHEN @MilestoneDueAt_Clear = 1 THEN NULL ELSE ISNULL(@MilestoneDueAt, NULL) END,
                CASE WHEN @AuthorLogin_Clear = 1 THEN NULL ELSE ISNULL(@AuthorLogin, NULL) END,
                CASE WHEN @BodyHash_Clear = 1 THEN NULL ELSE ISNULL(@BodyHash, NULL) END,
                CASE WHEN @GitHubUpdatedAt_Clear = 1 THEN NULL ELSE ISNULL(@GitHubUpdatedAt, NULL) END,
                CASE WHEN @LastSyncedAt_Clear = 1 THEN NULL ELSE ISNULL(@LastSyncedAt, NULL) END,
                @ActualID
        )
    -- return the new record from the base view, which might have some calculated fields
    SELECT * FROM [${flyway:defaultSchema}].[vwGitHubIssueTasks] WHERE [ID] = @ActualID
END
GO
GRANT EXECUTE ON [${flyway:defaultSchema}].[spCreateGitHubIssueTask] TO [cdp_Developer], [cdp_Integration];

/* spCreate Permissions for MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks */

GRANT EXECUTE ON [${flyway:defaultSchema}].[spCreateGitHubIssueTask] TO [cdp_Developer], [cdp_Integration];

/* spUpdate SQL for MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks */
-----------------------------------------------------------------
-- SQL Code Generation
-- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks
-- Item: spUpdateGitHubIssueTask
--
-- This was generated by the MemberJunction CodeGen tool.
-- This file should NOT be edited by hand.
-----------------------------------------------------------------

------------------------------------------------------------
----- UPDATE PROCEDURE FOR GitHubIssueTask
------------------------------------------------------------
IF OBJECT_ID('[${flyway:defaultSchema}].[spUpdateGitHubIssueTask]', 'P') IS NOT NULL
    DROP PROCEDURE [${flyway:defaultSchema}].[spUpdateGitHubIssueTask];
GO

CREATE PROCEDURE [${flyway:defaultSchema}].[spUpdateGitHubIssueTask]
    @ID uniqueidentifier,
    @RepositoryID_Clear bit = 0,
    @RepositoryID uniqueidentifier = NULL,
    @Number_Clear bit = 0,
    @Number int = NULL,
    @NodeID_Clear bit = 0,
    @NodeID nvarchar(128) = NULL,
    @HtmlURL_Clear bit = 0,
    @HtmlURL nvarchar(1000) = NULL,
    @State nvarchar(20) = NULL,
    @StateReason_Clear bit = 0,
    @StateReason nvarchar(40) = NULL,
    @Labels_Clear bit = 0,
    @Labels nvarchar(MAX) = NULL,
    @Milestone_Clear bit = 0,
    @Milestone nvarchar(255) = NULL,
    @MilestoneDueAt_Clear bit = 0,
    @MilestoneDueAt datetimeoffset = NULL,
    @AuthorLogin_Clear bit = 0,
    @AuthorLogin nvarchar(100) = NULL,
    @BodyHash_Clear bit = 0,
    @BodyHash nvarchar(64) = NULL,
    @GitHubUpdatedAt_Clear bit = 0,
    @GitHubUpdatedAt datetimeoffset = NULL,
    @LastSyncedAt_Clear bit = 0,
    @LastSyncedAt datetimeoffset = NULL
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE
        [${flyway:defaultSchema}].[GitHubIssueTask]
    SET
        [RepositoryID] = CASE WHEN @RepositoryID_Clear = 1 THEN NULL ELSE ISNULL(@RepositoryID, [RepositoryID]) END,
        [Number] = CASE WHEN @Number_Clear = 1 THEN NULL ELSE ISNULL(@Number, [Number]) END,
        [NodeID] = CASE WHEN @NodeID_Clear = 1 THEN NULL ELSE ISNULL(@NodeID, [NodeID]) END,
        [HtmlURL] = CASE WHEN @HtmlURL_Clear = 1 THEN NULL ELSE ISNULL(@HtmlURL, [HtmlURL]) END,
        [State] = ISNULL(@State, [State]),
        [StateReason] = CASE WHEN @StateReason_Clear = 1 THEN NULL ELSE ISNULL(@StateReason, [StateReason]) END,
        [Labels] = CASE WHEN @Labels_Clear = 1 THEN NULL ELSE ISNULL(@Labels, [Labels]) END,
        [Milestone] = CASE WHEN @Milestone_Clear = 1 THEN NULL ELSE ISNULL(@Milestone, [Milestone]) END,
        [MilestoneDueAt] = CASE WHEN @MilestoneDueAt_Clear = 1 THEN NULL ELSE ISNULL(@MilestoneDueAt, [MilestoneDueAt]) END,
        [AuthorLogin] = CASE WHEN @AuthorLogin_Clear = 1 THEN NULL ELSE ISNULL(@AuthorLogin, [AuthorLogin]) END,
        [BodyHash] = CASE WHEN @BodyHash_Clear = 1 THEN NULL ELSE ISNULL(@BodyHash, [BodyHash]) END,
        [GitHubUpdatedAt] = CASE WHEN @GitHubUpdatedAt_Clear = 1 THEN NULL ELSE ISNULL(@GitHubUpdatedAt, [GitHubUpdatedAt]) END,
        [LastSyncedAt] = CASE WHEN @LastSyncedAt_Clear = 1 THEN NULL ELSE ISNULL(@LastSyncedAt, [LastSyncedAt]) END
    WHERE
        [ID] = @ID

    -- Check if the update was successful
    IF @@ROWCOUNT = 0
        -- Nothing was updated, return no rows, but column structure from base view intact, semantically correct this way.
        SELECT TOP 0 * FROM [${flyway:defaultSchema}].[vwGitHubIssueTasks] WHERE 1=0
    ELSE
        -- Return the updated record so the caller can see the updated values and any calculated fields
        SELECT
                                        *
                                    FROM
                                        [${flyway:defaultSchema}].[vwGitHubIssueTasks]
                                    WHERE
                                        [ID] = @ID
                                    
END
GO

GRANT EXECUTE ON [${flyway:defaultSchema}].[spUpdateGitHubIssueTask] TO [cdp_Developer], [cdp_Integration]
GO

------------------------------------------------------------
----- TRIGGER FOR __mj_UpdatedAt field for the GitHubIssueTask table
------------------------------------------------------------
IF OBJECT_ID('[${flyway:defaultSchema}].[trgUpdateGitHubIssueTask]', 'TR') IS NOT NULL
    DROP TRIGGER [${flyway:defaultSchema}].[trgUpdateGitHubIssueTask];
GO
CREATE TRIGGER [${flyway:defaultSchema}].trgUpdateGitHubIssueTask
ON [${flyway:defaultSchema}].[GitHubIssueTask]
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE
        [${flyway:defaultSchema}].[GitHubIssueTask]
    SET
        __mj_UpdatedAt = GETUTCDATE()
    FROM
        [${flyway:defaultSchema}].[GitHubIssueTask] AS _organicTable
    INNER JOIN
        INSERTED AS I ON
        _organicTable.[ID] = I.[ID];
END;
GO

/* spUpdate Permissions for MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks */

GRANT EXECUTE ON [${flyway:defaultSchema}].[spUpdateGitHubIssueTask] TO [cdp_Developer], [cdp_Integration];

/* spDelete SQL for MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks */
-----------------------------------------------------------------
-- SQL Code Generation
-- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks
-- Item: spDeleteGitHubIssueTask
--
-- This was generated by the MemberJunction CodeGen tool.
-- This file should NOT be edited by hand.
-----------------------------------------------------------------

------------------------------------------------------------
----- DELETE PROCEDURE FOR GitHubIssueTask
------------------------------------------------------------
IF OBJECT_ID('[${flyway:defaultSchema}].[spDeleteGitHubIssueTask]', 'P') IS NOT NULL
    DROP PROCEDURE [${flyway:defaultSchema}].[spDeleteGitHubIssueTask];
GO

CREATE PROCEDURE [${flyway:defaultSchema}].[spDeleteGitHubIssueTask]
    @ID uniqueidentifier
AS
BEGIN
    SET NOCOUNT ON;

    DELETE FROM
        [${flyway:defaultSchema}].[GitHubIssueTask]
    WHERE
        [ID] = @ID


    -- Check if the delete was successful
    IF @@ROWCOUNT = 0
        SELECT NULL AS [ID] -- Return NULL for all primary key fields to indicate no record was deleted
    ELSE
        SELECT @ID AS [ID] -- Return the primary key values to indicate we successfully deleted the record
END
GO
GRANT EXECUTE ON [${flyway:defaultSchema}].[spDeleteGitHubIssueTask] TO [cdp_Developer], [cdp_Integration];

/* spDelete Permissions for MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks */

GRANT EXECUTE ON [${flyway:defaultSchema}].[spDeleteGitHubIssueTask] TO [cdp_Developer], [cdp_Integration];

/* Base View SQL for MJ_BizApps_Tasks_GitHub: Git Hub Repositories */
-----------------------------------------------------------------
-- SQL Code Generation
-- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Repositories
-- Item: vwGitHubRepositories
--
-- This was generated by the MemberJunction CodeGen tool.
-- This file should NOT be edited by hand.
-----------------------------------------------------------------

------------------------------------------------------------
----- BASE VIEW FOR ENTITY:      MJ_BizApps_Tasks_GitHub: Git Hub Repositories
-----               SCHEMA:      ${flyway:defaultSchema}
-----               BASE TABLE:  GitHubRepository
-----               PRIMARY KEY: ID
------------------------------------------------------------
IF OBJECT_ID('[${flyway:defaultSchema}].[vwGitHubRepositories]', 'V') IS NOT NULL
    DROP VIEW [${flyway:defaultSchema}].[vwGitHubRepositories];
GO

CREATE VIEW [${flyway:defaultSchema}].[vwGitHubRepositories]
AS
SELECT
    g.*,
    mjBizAppsCommonOrganization_OrganizationID.[Name] AS [Organization]
FROM
    [${flyway:defaultSchema}].[GitHubRepository] AS g
LEFT OUTER JOIN
    [__mj_BizAppsCommon].[Organization] AS mjBizAppsCommonOrganization_OrganizationID
  ON
    [g].[OrganizationID] = mjBizAppsCommonOrganization_OrganizationID.[ID]
GO
GRANT SELECT ON [${flyway:defaultSchema}].[vwGitHubRepositories] TO [cdp_UI], [cdp_Developer], [cdp_Integration];

/* Base View Permissions SQL for MJ_BizApps_Tasks_GitHub: Git Hub Repositories */
-----------------------------------------------------------------
-- SQL Code Generation
-- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Repositories
-- Item: Permissions for vwGitHubRepositories
--
-- This was generated by the MemberJunction CodeGen tool.
-- This file should NOT be edited by hand.
-----------------------------------------------------------------

GRANT SELECT ON [${flyway:defaultSchema}].[vwGitHubRepositories] TO [cdp_UI], [cdp_Developer], [cdp_Integration];

/* spCreate SQL for MJ_BizApps_Tasks_GitHub: Git Hub Repositories */
-----------------------------------------------------------------
-- SQL Code Generation
-- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Repositories
-- Item: spCreateGitHubRepository
--
-- This was generated by the MemberJunction CodeGen tool.
-- This file should NOT be edited by hand.
-----------------------------------------------------------------

------------------------------------------------------------
----- CREATE PROCEDURE FOR GitHubRepository
------------------------------------------------------------
IF OBJECT_ID('[${flyway:defaultSchema}].[spCreateGitHubRepository]', 'P') IS NOT NULL
    DROP PROCEDURE [${flyway:defaultSchema}].[spCreateGitHubRepository];
GO

CREATE PROCEDURE [${flyway:defaultSchema}].[spCreateGitHubRepository]
    @ID uniqueidentifier = NULL,
    @Owner nvarchar(150),
    @Name nvarchar(200),
    @DefaultBranch nvarchar(120) = NULL,
    @IsTracked bit = NULL,
    @ImportRule nvarchar(20) = NULL,
    @InstallationID_Clear bit = 0,
    @InstallationID nvarchar(100) = NULL,
    @OrganizationID_Clear bit = 0,
    @OrganizationID uniqueidentifier = NULL,
    @DeliveryPolicyID_Clear bit = 0,
    @DeliveryPolicyID uniqueidentifier = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @InsertedRow TABLE ([ID] UNIQUEIDENTIFIER)

    IF @ID IS NOT NULL
    BEGIN
        -- User provided a value, use it
        INSERT INTO [${flyway:defaultSchema}].[GitHubRepository]
            (
                [ID],
                [Owner],
                [Name],
                [DefaultBranch],
                [IsTracked],
                [ImportRule],
                [InstallationID],
                [OrganizationID],
                [DeliveryPolicyID]
            )
        OUTPUT INSERTED.[ID] INTO @InsertedRow
        VALUES
            (
                @ID,
                @Owner,
                @Name,
                ISNULL(@DefaultBranch, 'main'),
                ISNULL(@IsTracked, 1),
                ISNULL(@ImportRule, 'AssignedOnly'),
                CASE WHEN @InstallationID_Clear = 1 THEN NULL ELSE ISNULL(@InstallationID, NULL) END,
                CASE WHEN @OrganizationID_Clear = 1 THEN NULL ELSE ISNULL(@OrganizationID, NULL) END,
                CASE WHEN @DeliveryPolicyID_Clear = 1 THEN NULL ELSE ISNULL(@DeliveryPolicyID, NULL) END
            )
    END
    ELSE
    BEGIN
        -- No value provided, let database use its default (e.g., NEWSEQUENTIALID())
        INSERT INTO [${flyway:defaultSchema}].[GitHubRepository]
            (
                [Owner],
                [Name],
                [DefaultBranch],
                [IsTracked],
                [ImportRule],
                [InstallationID],
                [OrganizationID],
                [DeliveryPolicyID]
            )
        OUTPUT INSERTED.[ID] INTO @InsertedRow
        VALUES
            (
                @Owner,
                @Name,
                ISNULL(@DefaultBranch, 'main'),
                ISNULL(@IsTracked, 1),
                ISNULL(@ImportRule, 'AssignedOnly'),
                CASE WHEN @InstallationID_Clear = 1 THEN NULL ELSE ISNULL(@InstallationID, NULL) END,
                CASE WHEN @OrganizationID_Clear = 1 THEN NULL ELSE ISNULL(@OrganizationID, NULL) END,
                CASE WHEN @DeliveryPolicyID_Clear = 1 THEN NULL ELSE ISNULL(@DeliveryPolicyID, NULL) END
            )
    END
    -- return the new record from the base view, which might have some calculated fields
    SELECT * FROM [${flyway:defaultSchema}].[vwGitHubRepositories] WHERE [ID] = (SELECT [ID] FROM @InsertedRow)
END
GO
GRANT EXECUTE ON [${flyway:defaultSchema}].[spCreateGitHubRepository] TO [cdp_Developer], [cdp_Integration];

/* spCreate Permissions for MJ_BizApps_Tasks_GitHub: Git Hub Repositories */

GRANT EXECUTE ON [${flyway:defaultSchema}].[spCreateGitHubRepository] TO [cdp_Developer], [cdp_Integration];

/* spUpdate SQL for MJ_BizApps_Tasks_GitHub: Git Hub Repositories */
-----------------------------------------------------------------
-- SQL Code Generation
-- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Repositories
-- Item: spUpdateGitHubRepository
--
-- This was generated by the MemberJunction CodeGen tool.
-- This file should NOT be edited by hand.
-----------------------------------------------------------------

------------------------------------------------------------
----- UPDATE PROCEDURE FOR GitHubRepository
------------------------------------------------------------
IF OBJECT_ID('[${flyway:defaultSchema}].[spUpdateGitHubRepository]', 'P') IS NOT NULL
    DROP PROCEDURE [${flyway:defaultSchema}].[spUpdateGitHubRepository];
GO

CREATE PROCEDURE [${flyway:defaultSchema}].[spUpdateGitHubRepository]
    @ID uniqueidentifier,
    @Owner nvarchar(150) = NULL,
    @Name nvarchar(200) = NULL,
    @DefaultBranch nvarchar(120) = NULL,
    @IsTracked bit = NULL,
    @ImportRule nvarchar(20) = NULL,
    @InstallationID_Clear bit = 0,
    @InstallationID nvarchar(100) = NULL,
    @OrganizationID_Clear bit = 0,
    @OrganizationID uniqueidentifier = NULL,
    @DeliveryPolicyID_Clear bit = 0,
    @DeliveryPolicyID uniqueidentifier = NULL
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE
        [${flyway:defaultSchema}].[GitHubRepository]
    SET
        [Owner] = ISNULL(@Owner, [Owner]),
        [Name] = ISNULL(@Name, [Name]),
        [DefaultBranch] = ISNULL(@DefaultBranch, [DefaultBranch]),
        [IsTracked] = ISNULL(@IsTracked, [IsTracked]),
        [ImportRule] = ISNULL(@ImportRule, [ImportRule]),
        [InstallationID] = CASE WHEN @InstallationID_Clear = 1 THEN NULL ELSE ISNULL(@InstallationID, [InstallationID]) END,
        [OrganizationID] = CASE WHEN @OrganizationID_Clear = 1 THEN NULL ELSE ISNULL(@OrganizationID, [OrganizationID]) END,
        [DeliveryPolicyID] = CASE WHEN @DeliveryPolicyID_Clear = 1 THEN NULL ELSE ISNULL(@DeliveryPolicyID, [DeliveryPolicyID]) END
    WHERE
        [ID] = @ID

    -- Check if the update was successful
    IF @@ROWCOUNT = 0
        -- Nothing was updated, return no rows, but column structure from base view intact, semantically correct this way.
        SELECT TOP 0 * FROM [${flyway:defaultSchema}].[vwGitHubRepositories] WHERE 1=0
    ELSE
        -- Return the updated record so the caller can see the updated values and any calculated fields
        SELECT
                                        *
                                    FROM
                                        [${flyway:defaultSchema}].[vwGitHubRepositories]
                                    WHERE
                                        [ID] = @ID
                                    
END
GO

GRANT EXECUTE ON [${flyway:defaultSchema}].[spUpdateGitHubRepository] TO [cdp_Developer], [cdp_Integration]
GO

------------------------------------------------------------
----- TRIGGER FOR __mj_UpdatedAt field for the GitHubRepository table
------------------------------------------------------------
IF OBJECT_ID('[${flyway:defaultSchema}].[trgUpdateGitHubRepository]', 'TR') IS NOT NULL
    DROP TRIGGER [${flyway:defaultSchema}].[trgUpdateGitHubRepository];
GO
CREATE TRIGGER [${flyway:defaultSchema}].trgUpdateGitHubRepository
ON [${flyway:defaultSchema}].[GitHubRepository]
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE
        [${flyway:defaultSchema}].[GitHubRepository]
    SET
        __mj_UpdatedAt = GETUTCDATE()
    FROM
        [${flyway:defaultSchema}].[GitHubRepository] AS _organicTable
    INNER JOIN
        INSERTED AS I ON
        _organicTable.[ID] = I.[ID];
END;
GO

/* spUpdate Permissions for MJ_BizApps_Tasks_GitHub: Git Hub Repositories */

GRANT EXECUTE ON [${flyway:defaultSchema}].[spUpdateGitHubRepository] TO [cdp_Developer], [cdp_Integration];

/* spDelete SQL for MJ_BizApps_Tasks_GitHub: Git Hub Repositories */
-----------------------------------------------------------------
-- SQL Code Generation
-- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Repositories
-- Item: spDeleteGitHubRepository
--
-- This was generated by the MemberJunction CodeGen tool.
-- This file should NOT be edited by hand.
-----------------------------------------------------------------

------------------------------------------------------------
----- DELETE PROCEDURE FOR GitHubRepository
------------------------------------------------------------
IF OBJECT_ID('[${flyway:defaultSchema}].[spDeleteGitHubRepository]', 'P') IS NOT NULL
    DROP PROCEDURE [${flyway:defaultSchema}].[spDeleteGitHubRepository];
GO

CREATE PROCEDURE [${flyway:defaultSchema}].[spDeleteGitHubRepository]
    @ID uniqueidentifier
AS
BEGIN
    SET NOCOUNT ON;

    DELETE FROM
        [${flyway:defaultSchema}].[GitHubRepository]
    WHERE
        [ID] = @ID


    -- Check if the delete was successful
    IF @@ROWCOUNT = 0
        SELECT NULL AS [ID] -- Return NULL for all primary key fields to indicate no record was deleted
    ELSE
        SELECT @ID AS [ID] -- Return the primary key values to indicate we successfully deleted the record
END
GO
GRANT EXECUTE ON [${flyway:defaultSchema}].[spDeleteGitHubRepository] TO [cdp_Developer], [cdp_Integration];

/* spDelete Permissions for MJ_BizApps_Tasks_GitHub: Git Hub Repositories */

GRANT EXECUTE ON [${flyway:defaultSchema}].[spDeleteGitHubRepository] TO [cdp_Developer], [cdp_Integration];

/* Base View SQL for MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks */
-----------------------------------------------------------------
-- SQL Code Generation
-- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks
-- Item: vwGitHubPullRequestTasks
--
-- This was generated by the MemberJunction CodeGen tool.
-- This file should NOT be edited by hand.
-----------------------------------------------------------------

------------------------------------------------------------
----- BASE VIEW FOR ENTITY:      MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks
-----               SCHEMA:      ${flyway:defaultSchema}
-----               BASE TABLE:  GitHubPullRequestTask
-----               PRIMARY KEY: ID
------------------------------------------------------------
IF OBJECT_ID('[${flyway:defaultSchema}].[vwGitHubPullRequestTasks]', 'V') IS NOT NULL
    DROP VIEW [${flyway:defaultSchema}].[vwGitHubPullRequestTasks];
GO

CREATE VIEW [${flyway:defaultSchema}].[vwGitHubPullRequestTasks]
AS
SELECT
    g.*,
    mjBizAppsTasksGitHubGitHubRepository_RepositoryID.[Name] AS [Repository],
    mjBizAppsTasksTask_LinkedIssueTaskID.[Name] AS [LinkedIssueTask]
FROM
    [${flyway:defaultSchema}].[GitHubPullRequestTask] AS g
LEFT OUTER JOIN
    [${flyway:defaultSchema}].[GitHubRepository] AS mjBizAppsTasksGitHubGitHubRepository_RepositoryID
  ON
    [g].[RepositoryID] = mjBizAppsTasksGitHubGitHubRepository_RepositoryID.[ID]
LEFT OUTER JOIN
    [__mj_BizAppsTasks].[Task] AS mjBizAppsTasksTask_LinkedIssueTaskID
  ON
    [g].[LinkedIssueTaskID] = mjBizAppsTasksTask_LinkedIssueTaskID.[ID]
GO
GRANT SELECT ON [${flyway:defaultSchema}].[vwGitHubPullRequestTasks] TO [cdp_UI], [cdp_Developer], [cdp_Integration];

/* Base View Permissions SQL for MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks */
-----------------------------------------------------------------
-- SQL Code Generation
-- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks
-- Item: Permissions for vwGitHubPullRequestTasks
--
-- This was generated by the MemberJunction CodeGen tool.
-- This file should NOT be edited by hand.
-----------------------------------------------------------------

GRANT SELECT ON [${flyway:defaultSchema}].[vwGitHubPullRequestTasks] TO [cdp_UI], [cdp_Developer], [cdp_Integration];

/* spCreate SQL for MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks */
-----------------------------------------------------------------
-- SQL Code Generation
-- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks
-- Item: spCreateGitHubPullRequestTask
--
-- This was generated by the MemberJunction CodeGen tool.
-- This file should NOT be edited by hand.
-----------------------------------------------------------------

------------------------------------------------------------
----- CREATE PROCEDURE FOR GitHubPullRequestTask
------------------------------------------------------------
IF OBJECT_ID('[${flyway:defaultSchema}].[spCreateGitHubPullRequestTask]', 'P') IS NOT NULL
    DROP PROCEDURE [${flyway:defaultSchema}].[spCreateGitHubPullRequestTask];
GO

CREATE PROCEDURE [${flyway:defaultSchema}].[spCreateGitHubPullRequestTask]
    @ID uniqueidentifier = NULL,
    @RepositoryID_Clear bit = 0,
    @RepositoryID uniqueidentifier = NULL,
    @Number_Clear bit = 0,
    @Number int = NULL,
    @NodeID_Clear bit = 0,
    @NodeID nvarchar(128) = NULL,
    @HtmlURL_Clear bit = 0,
    @HtmlURL nvarchar(1000) = NULL,
    @State nvarchar(20) = NULL,
    @IsDraft bit = NULL,
    @HeadBranch_Clear bit = 0,
    @HeadBranch nvarchar(255) = NULL,
    @HeadSha_Clear bit = 0,
    @HeadSha nvarchar(64) = NULL,
    @BaseBranch_Clear bit = 0,
    @BaseBranch nvarchar(255) = NULL,
    @AuthorLogin_Clear bit = 0,
    @AuthorLogin nvarchar(100) = NULL,
    @ReviewDecision_Clear bit = 0,
    @ReviewDecision nvarchar(40) = NULL,
    @ChecksStatus_Clear bit = 0,
    @ChecksStatus nvarchar(30) = NULL,
    @ChangedFiles_Clear bit = 0,
    @ChangedFiles int = NULL,
    @Additions_Clear bit = 0,
    @Additions int = NULL,
    @Deletions_Clear bit = 0,
    @Deletions int = NULL,
    @Labels_Clear bit = 0,
    @Labels nvarchar(MAX) = NULL,
    @Milestone_Clear bit = 0,
    @Milestone nvarchar(255) = NULL,
    @MilestoneDueAt_Clear bit = 0,
    @MilestoneDueAt datetimeoffset = NULL,
    @MergedAt_Clear bit = 0,
    @MergedAt datetimeoffset = NULL,
    @LinkedIssueTaskID_Clear bit = 0,
    @LinkedIssueTaskID uniqueidentifier = NULL,
    @BodyHash_Clear bit = 0,
    @BodyHash nvarchar(64) = NULL,
    @GitHubUpdatedAt_Clear bit = 0,
    @GitHubUpdatedAt datetimeoffset = NULL,
    @LastSyncedAt_Clear bit = 0,
    @LastSyncedAt datetimeoffset = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @ActualID UNIQUEIDENTIFIER = ISNULL(@ID, NEWID())
    INSERT INTO
    [${flyway:defaultSchema}].[GitHubPullRequestTask]
        (
            [RepositoryID],
                [Number],
                [NodeID],
                [HtmlURL],
                [State],
                [IsDraft],
                [HeadBranch],
                [HeadSha],
                [BaseBranch],
                [AuthorLogin],
                [ReviewDecision],
                [ChecksStatus],
                [ChangedFiles],
                [Additions],
                [Deletions],
                [Labels],
                [Milestone],
                [MilestoneDueAt],
                [MergedAt],
                [LinkedIssueTaskID],
                [BodyHash],
                [GitHubUpdatedAt],
                [LastSyncedAt],
                [ID]
        )
    VALUES
        (
            CASE WHEN @RepositoryID_Clear = 1 THEN NULL ELSE ISNULL(@RepositoryID, NULL) END,
                CASE WHEN @Number_Clear = 1 THEN NULL ELSE ISNULL(@Number, NULL) END,
                CASE WHEN @NodeID_Clear = 1 THEN NULL ELSE ISNULL(@NodeID, NULL) END,
                CASE WHEN @HtmlURL_Clear = 1 THEN NULL ELSE ISNULL(@HtmlURL, NULL) END,
                ISNULL(@State, 'open'),
                ISNULL(@IsDraft, 0),
                CASE WHEN @HeadBranch_Clear = 1 THEN NULL ELSE ISNULL(@HeadBranch, NULL) END,
                CASE WHEN @HeadSha_Clear = 1 THEN NULL ELSE ISNULL(@HeadSha, NULL) END,
                CASE WHEN @BaseBranch_Clear = 1 THEN NULL ELSE ISNULL(@BaseBranch, NULL) END,
                CASE WHEN @AuthorLogin_Clear = 1 THEN NULL ELSE ISNULL(@AuthorLogin, NULL) END,
                CASE WHEN @ReviewDecision_Clear = 1 THEN NULL ELSE ISNULL(@ReviewDecision, NULL) END,
                CASE WHEN @ChecksStatus_Clear = 1 THEN NULL ELSE ISNULL(@ChecksStatus, NULL) END,
                CASE WHEN @ChangedFiles_Clear = 1 THEN NULL ELSE ISNULL(@ChangedFiles, NULL) END,
                CASE WHEN @Additions_Clear = 1 THEN NULL ELSE ISNULL(@Additions, NULL) END,
                CASE WHEN @Deletions_Clear = 1 THEN NULL ELSE ISNULL(@Deletions, NULL) END,
                CASE WHEN @Labels_Clear = 1 THEN NULL ELSE ISNULL(@Labels, NULL) END,
                CASE WHEN @Milestone_Clear = 1 THEN NULL ELSE ISNULL(@Milestone, NULL) END,
                CASE WHEN @MilestoneDueAt_Clear = 1 THEN NULL ELSE ISNULL(@MilestoneDueAt, NULL) END,
                CASE WHEN @MergedAt_Clear = 1 THEN NULL ELSE ISNULL(@MergedAt, NULL) END,
                CASE WHEN @LinkedIssueTaskID_Clear = 1 THEN NULL ELSE ISNULL(@LinkedIssueTaskID, NULL) END,
                CASE WHEN @BodyHash_Clear = 1 THEN NULL ELSE ISNULL(@BodyHash, NULL) END,
                CASE WHEN @GitHubUpdatedAt_Clear = 1 THEN NULL ELSE ISNULL(@GitHubUpdatedAt, NULL) END,
                CASE WHEN @LastSyncedAt_Clear = 1 THEN NULL ELSE ISNULL(@LastSyncedAt, NULL) END,
                @ActualID
        )
    -- return the new record from the base view, which might have some calculated fields
    SELECT * FROM [${flyway:defaultSchema}].[vwGitHubPullRequestTasks] WHERE [ID] = @ActualID
END
GO
GRANT EXECUTE ON [${flyway:defaultSchema}].[spCreateGitHubPullRequestTask] TO [cdp_Developer], [cdp_Integration];

/* spCreate Permissions for MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks */

GRANT EXECUTE ON [${flyway:defaultSchema}].[spCreateGitHubPullRequestTask] TO [cdp_Developer], [cdp_Integration];

/* spUpdate SQL for MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks */
-----------------------------------------------------------------
-- SQL Code Generation
-- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks
-- Item: spUpdateGitHubPullRequestTask
--
-- This was generated by the MemberJunction CodeGen tool.
-- This file should NOT be edited by hand.
-----------------------------------------------------------------

------------------------------------------------------------
----- UPDATE PROCEDURE FOR GitHubPullRequestTask
------------------------------------------------------------
IF OBJECT_ID('[${flyway:defaultSchema}].[spUpdateGitHubPullRequestTask]', 'P') IS NOT NULL
    DROP PROCEDURE [${flyway:defaultSchema}].[spUpdateGitHubPullRequestTask];
GO

CREATE PROCEDURE [${flyway:defaultSchema}].[spUpdateGitHubPullRequestTask]
    @ID uniqueidentifier,
    @RepositoryID_Clear bit = 0,
    @RepositoryID uniqueidentifier = NULL,
    @Number_Clear bit = 0,
    @Number int = NULL,
    @NodeID_Clear bit = 0,
    @NodeID nvarchar(128) = NULL,
    @HtmlURL_Clear bit = 0,
    @HtmlURL nvarchar(1000) = NULL,
    @State nvarchar(20) = NULL,
    @IsDraft bit = NULL,
    @HeadBranch_Clear bit = 0,
    @HeadBranch nvarchar(255) = NULL,
    @HeadSha_Clear bit = 0,
    @HeadSha nvarchar(64) = NULL,
    @BaseBranch_Clear bit = 0,
    @BaseBranch nvarchar(255) = NULL,
    @AuthorLogin_Clear bit = 0,
    @AuthorLogin nvarchar(100) = NULL,
    @ReviewDecision_Clear bit = 0,
    @ReviewDecision nvarchar(40) = NULL,
    @ChecksStatus_Clear bit = 0,
    @ChecksStatus nvarchar(30) = NULL,
    @ChangedFiles_Clear bit = 0,
    @ChangedFiles int = NULL,
    @Additions_Clear bit = 0,
    @Additions int = NULL,
    @Deletions_Clear bit = 0,
    @Deletions int = NULL,
    @Labels_Clear bit = 0,
    @Labels nvarchar(MAX) = NULL,
    @Milestone_Clear bit = 0,
    @Milestone nvarchar(255) = NULL,
    @MilestoneDueAt_Clear bit = 0,
    @MilestoneDueAt datetimeoffset = NULL,
    @MergedAt_Clear bit = 0,
    @MergedAt datetimeoffset = NULL,
    @LinkedIssueTaskID_Clear bit = 0,
    @LinkedIssueTaskID uniqueidentifier = NULL,
    @BodyHash_Clear bit = 0,
    @BodyHash nvarchar(64) = NULL,
    @GitHubUpdatedAt_Clear bit = 0,
    @GitHubUpdatedAt datetimeoffset = NULL,
    @LastSyncedAt_Clear bit = 0,
    @LastSyncedAt datetimeoffset = NULL
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE
        [${flyway:defaultSchema}].[GitHubPullRequestTask]
    SET
        [RepositoryID] = CASE WHEN @RepositoryID_Clear = 1 THEN NULL ELSE ISNULL(@RepositoryID, [RepositoryID]) END,
        [Number] = CASE WHEN @Number_Clear = 1 THEN NULL ELSE ISNULL(@Number, [Number]) END,
        [NodeID] = CASE WHEN @NodeID_Clear = 1 THEN NULL ELSE ISNULL(@NodeID, [NodeID]) END,
        [HtmlURL] = CASE WHEN @HtmlURL_Clear = 1 THEN NULL ELSE ISNULL(@HtmlURL, [HtmlURL]) END,
        [State] = ISNULL(@State, [State]),
        [IsDraft] = ISNULL(@IsDraft, [IsDraft]),
        [HeadBranch] = CASE WHEN @HeadBranch_Clear = 1 THEN NULL ELSE ISNULL(@HeadBranch, [HeadBranch]) END,
        [HeadSha] = CASE WHEN @HeadSha_Clear = 1 THEN NULL ELSE ISNULL(@HeadSha, [HeadSha]) END,
        [BaseBranch] = CASE WHEN @BaseBranch_Clear = 1 THEN NULL ELSE ISNULL(@BaseBranch, [BaseBranch]) END,
        [AuthorLogin] = CASE WHEN @AuthorLogin_Clear = 1 THEN NULL ELSE ISNULL(@AuthorLogin, [AuthorLogin]) END,
        [ReviewDecision] = CASE WHEN @ReviewDecision_Clear = 1 THEN NULL ELSE ISNULL(@ReviewDecision, [ReviewDecision]) END,
        [ChecksStatus] = CASE WHEN @ChecksStatus_Clear = 1 THEN NULL ELSE ISNULL(@ChecksStatus, [ChecksStatus]) END,
        [ChangedFiles] = CASE WHEN @ChangedFiles_Clear = 1 THEN NULL ELSE ISNULL(@ChangedFiles, [ChangedFiles]) END,
        [Additions] = CASE WHEN @Additions_Clear = 1 THEN NULL ELSE ISNULL(@Additions, [Additions]) END,
        [Deletions] = CASE WHEN @Deletions_Clear = 1 THEN NULL ELSE ISNULL(@Deletions, [Deletions]) END,
        [Labels] = CASE WHEN @Labels_Clear = 1 THEN NULL ELSE ISNULL(@Labels, [Labels]) END,
        [Milestone] = CASE WHEN @Milestone_Clear = 1 THEN NULL ELSE ISNULL(@Milestone, [Milestone]) END,
        [MilestoneDueAt] = CASE WHEN @MilestoneDueAt_Clear = 1 THEN NULL ELSE ISNULL(@MilestoneDueAt, [MilestoneDueAt]) END,
        [MergedAt] = CASE WHEN @MergedAt_Clear = 1 THEN NULL ELSE ISNULL(@MergedAt, [MergedAt]) END,
        [LinkedIssueTaskID] = CASE WHEN @LinkedIssueTaskID_Clear = 1 THEN NULL ELSE ISNULL(@LinkedIssueTaskID, [LinkedIssueTaskID]) END,
        [BodyHash] = CASE WHEN @BodyHash_Clear = 1 THEN NULL ELSE ISNULL(@BodyHash, [BodyHash]) END,
        [GitHubUpdatedAt] = CASE WHEN @GitHubUpdatedAt_Clear = 1 THEN NULL ELSE ISNULL(@GitHubUpdatedAt, [GitHubUpdatedAt]) END,
        [LastSyncedAt] = CASE WHEN @LastSyncedAt_Clear = 1 THEN NULL ELSE ISNULL(@LastSyncedAt, [LastSyncedAt]) END
    WHERE
        [ID] = @ID

    -- Check if the update was successful
    IF @@ROWCOUNT = 0
        -- Nothing was updated, return no rows, but column structure from base view intact, semantically correct this way.
        SELECT TOP 0 * FROM [${flyway:defaultSchema}].[vwGitHubPullRequestTasks] WHERE 1=0
    ELSE
        -- Return the updated record so the caller can see the updated values and any calculated fields
        SELECT
                                        *
                                    FROM
                                        [${flyway:defaultSchema}].[vwGitHubPullRequestTasks]
                                    WHERE
                                        [ID] = @ID
                                    
END
GO

GRANT EXECUTE ON [${flyway:defaultSchema}].[spUpdateGitHubPullRequestTask] TO [cdp_Developer], [cdp_Integration]
GO

------------------------------------------------------------
----- TRIGGER FOR __mj_UpdatedAt field for the GitHubPullRequestTask table
------------------------------------------------------------
IF OBJECT_ID('[${flyway:defaultSchema}].[trgUpdateGitHubPullRequestTask]', 'TR') IS NOT NULL
    DROP TRIGGER [${flyway:defaultSchema}].[trgUpdateGitHubPullRequestTask];
GO
CREATE TRIGGER [${flyway:defaultSchema}].trgUpdateGitHubPullRequestTask
ON [${flyway:defaultSchema}].[GitHubPullRequestTask]
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE
        [${flyway:defaultSchema}].[GitHubPullRequestTask]
    SET
        __mj_UpdatedAt = GETUTCDATE()
    FROM
        [${flyway:defaultSchema}].[GitHubPullRequestTask] AS _organicTable
    INNER JOIN
        INSERTED AS I ON
        _organicTable.[ID] = I.[ID];
END;
GO

/* spUpdate Permissions for MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks */

GRANT EXECUTE ON [${flyway:defaultSchema}].[spUpdateGitHubPullRequestTask] TO [cdp_Developer], [cdp_Integration];

/* spDelete SQL for MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks */
-----------------------------------------------------------------
-- SQL Code Generation
-- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks
-- Item: spDeleteGitHubPullRequestTask
--
-- This was generated by the MemberJunction CodeGen tool.
-- This file should NOT be edited by hand.
-----------------------------------------------------------------

------------------------------------------------------------
----- DELETE PROCEDURE FOR GitHubPullRequestTask
------------------------------------------------------------
IF OBJECT_ID('[${flyway:defaultSchema}].[spDeleteGitHubPullRequestTask]', 'P') IS NOT NULL
    DROP PROCEDURE [${flyway:defaultSchema}].[spDeleteGitHubPullRequestTask];
GO

CREATE PROCEDURE [${flyway:defaultSchema}].[spDeleteGitHubPullRequestTask]
    @ID uniqueidentifier
AS
BEGIN
    SET NOCOUNT ON;

    DELETE FROM
        [${flyway:defaultSchema}].[GitHubPullRequestTask]
    WHERE
        [ID] = @ID


    -- Check if the delete was successful
    IF @@ROWCOUNT = 0
        SELECT NULL AS [ID] -- Return NULL for all primary key fields to indicate no record was deleted
    ELSE
        SELECT @ID AS [ID] -- Return the primary key values to indicate we successfully deleted the record
END
GO
GRANT EXECUTE ON [${flyway:defaultSchema}].[spDeleteGitHubPullRequestTask] TO [cdp_Developer], [cdp_Integration];

/* spDelete Permissions for MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks */

GRANT EXECUTE ON [${flyway:defaultSchema}].[spDeleteGitHubPullRequestTask] TO [cdp_Developer], [cdp_Integration];


/* SQL text to insert 5 new entity field(s) */

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = 'fb25ea32-a752-4fa3-ad55-72034e18507b' OR (EntityID = '6B363236-31AB-477D-8188-08F5FA9942EF' AND Name = 'Organization')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            'fb25ea32-a752-4fa3-ad55-72034e18507b',
            '6B363236-31AB-477D-8188-08F5FA9942EF', -- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Repositories
            (SELECT COALESCE(MAX([Sequence]), 0) + 1 FROM [${mjSchema}].[EntityField] WHERE [EntityID] = '6B363236-31AB-477D-8188-08F5FA9942EF'),
            'Organization',
            'Organization',
            NULL,
            'nvarchar',
            510,
            0,
            0,
            1,
            NULL,
            0,
            0,
            1,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '7eacb6de-e83e-4d1e-9523-f035ac1c7547' OR (EntityID = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605' AND Name = 'Repository')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '7eacb6de-e83e-4d1e-9523-f035ac1c7547',
            'DC8E0F5B-E172-4FD5-B648-8B4544F8C605', -- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks
            (SELECT COALESCE(MAX([Sequence]), 0) + 1 FROM [${mjSchema}].[EntityField] WHERE [EntityID] = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605'),
            'Repository',
            'Repository',
            NULL,
            'nvarchar',
            400,
            0,
            0,
            1,
            NULL,
            0,
            0,
            1,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '60f671eb-d0b7-42ff-ad43-0a300001e37e' OR (EntityID = 'C7CC2BCF-090E-4832-89C7-A051F302C393' AND Name = 'Person')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '60f671eb-d0b7-42ff-ad43-0a300001e37e',
            'C7CC2BCF-090E-4832-89C7-A051F302C393', -- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Identities
            (SELECT COALESCE(MAX([Sequence]), 0) + 1 FROM [${mjSchema}].[EntityField] WHERE [EntityID] = 'C7CC2BCF-090E-4832-89C7-A051F302C393'),
            'Person',
            'Person',
            NULL,
            'nvarchar',
            500,
            0,
            0,
            1,
            NULL,
            0,
            0,
            1,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '4e32f6e1-bd8a-4f42-8f15-04093eaf9eb2' OR (EntityID = 'A6B673F8-43BC-4875-AFF6-AC620592822E' AND Name = 'Repository')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '4e32f6e1-bd8a-4f42-8f15-04093eaf9eb2',
            'A6B673F8-43BC-4875-AFF6-AC620592822E', -- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks
            (SELECT COALESCE(MAX([Sequence]), 0) + 1 FROM [${mjSchema}].[EntityField] WHERE [EntityID] = 'A6B673F8-43BC-4875-AFF6-AC620592822E'),
            'Repository',
            'Repository',
            NULL,
            'nvarchar',
            400,
            0,
            0,
            1,
            NULL,
            0,
            0,
            1,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '34645952-8ca4-4a7f-af70-1b782bd89c0b' OR (EntityID = 'A6B673F8-43BC-4875-AFF6-AC620592822E' AND Name = 'LinkedIssueTask')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '34645952-8ca4-4a7f-af70-1b782bd89c0b',
            'A6B673F8-43BC-4875-AFF6-AC620592822E', -- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks
            (SELECT COALESCE(MAX([Sequence]), 0) + 1 FROM [${mjSchema}].[EntityField] WHERE [EntityID] = 'A6B673F8-43BC-4875-AFF6-AC620592822E'),
            'LinkedIssueTask',
            'Linked Issue Task',
            NULL,
            'nvarchar',
            510,
            0,
            0,
            1,
            NULL,
            0,
            0,
            1,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

/* SQL text to update existing entity fields from schema (4 scoped entities) */
EXEC [${mjSchema}].[spUpdateExistingEntityFieldsFromSchema] @ExcludedSchemaNames='', @EntityIDs='6B363236-31AB-477D-8188-08F5FA9942EF,C7CC2BCF-090E-4832-89C7-A051F302C393,DC8E0F5B-E172-4FD5-B648-8B4544F8C605,A6B673F8-43BC-4875-AFF6-AC620592822E', @IncludedSchemaNames='${flyway:defaultSchema}';

/* SQL text to set default column width where needed */
EXEC [${mjSchema}].[spSetDefaultColumnWidthWhereNeeded] @ExcludedSchemaNames='', @IncludedSchemaNames='${flyway:defaultSchema}';

/* Set field properties for entity */

               UPDATE [${mjSchema}].[EntityField]
               SET DefaultInView = 1
               WHERE ID = 'D09CC770-1CBB-4078-8186-BF3ED875F03C'
               AND AutoUpdateDefaultInView = 1;

               UPDATE [${mjSchema}].[EntityField]
               SET IncludeInUserSearchAPI = 1
               WHERE ID = '16994C95-2791-47C6-B378-4AF1EACE655F'
               AND AutoUpdateIncludeInUserSearchAPI = 1;

               UPDATE [${mjSchema}].[EntityField]
               SET UserSearchPredicateAPI = 'BeginsWith'
               WHERE ID = '16994C95-2791-47C6-B378-4AF1EACE655F'
               AND AutoUpdateUserSearchPredicate = 1;

               UPDATE [${mjSchema}].[EntityField]
               SET UserSearchPredicateAPI = 'BeginsWith'
               WHERE ID = '8CFC093F-2135-437E-93A8-493A64DFA174'
               AND AutoUpdateUserSearchPredicate = 1;

/* Set field properties for entity */

               UPDATE [${mjSchema}].[EntityField]
               SET DefaultInView = 1
               WHERE ID = '5CBFAABD-0AF2-4E67-91B1-F089E6C56C4D'
               AND AutoUpdateDefaultInView = 1;

               UPDATE [${mjSchema}].[EntityField]
               SET DefaultInView = 1
               WHERE ID = '6A042282-8DC0-4158-B972-F2EFF37C1387'
               AND AutoUpdateDefaultInView = 1;

               UPDATE [${mjSchema}].[EntityField]
               SET DefaultInView = 1
               WHERE ID = '8D2DB26A-0621-4A94-A932-A4C1F47E1DCF'
               AND AutoUpdateDefaultInView = 1;

               UPDATE [${mjSchema}].[EntityField]
               SET DefaultInView = 1
               WHERE ID = 'DEBADDF7-A747-400C-BEC1-8A93FDDF6193'
               AND AutoUpdateDefaultInView = 1;

               UPDATE [${mjSchema}].[EntityField]
               SET DefaultInView = 1
               WHERE ID = 'D0242DB3-ACFC-4AD6-9B8A-7AF48E27BBE4'
               AND AutoUpdateDefaultInView = 1;

               UPDATE [${mjSchema}].[EntityField]
               SET DefaultInView = 1
               WHERE ID = '57B97F3B-7437-49C3-A2A3-89F8F14F3224'
               AND AutoUpdateDefaultInView = 1;

               UPDATE [${mjSchema}].[EntityField]
               SET IncludeInUserSearchAPI = 1
               WHERE ID = '6A042282-8DC0-4158-B972-F2EFF37C1387'
               AND AutoUpdateIncludeInUserSearchAPI = 1;

               UPDATE [${mjSchema}].[EntityField]
               SET IncludeInUserSearchAPI = 1
               WHERE ID = 'DEBADDF7-A747-400C-BEC1-8A93FDDF6193'
               AND AutoUpdateIncludeInUserSearchAPI = 1;

               UPDATE [${mjSchema}].[EntityField]
               SET UserSearchPredicateAPI = 'BeginsWith'
               WHERE ID = '6A042282-8DC0-4158-B972-F2EFF37C1387'
               AND AutoUpdateUserSearchPredicate = 1;

               UPDATE [${mjSchema}].[EntityField]
               SET UserSearchPredicateAPI = 'Exact'
               WHERE ID = 'DEBADDF7-A747-400C-BEC1-8A93FDDF6193'
               AND AutoUpdateUserSearchPredicate = 1;

            UPDATE [${mjSchema}].[Entity]
            SET AllowUserSearchAPI = 1
            WHERE ID = 'A6B673F8-43BC-4875-AFF6-AC620592822E'
            AND AutoUpdateAllowUserSearchAPI = 1;

/* Set field properties for entity */

               UPDATE [${mjSchema}].[EntityField]
               SET IsNameField = 1
               WHERE ID = '8A9B093F-91D1-4991-9069-4F2F36AD9181'
               AND AutoUpdateIsNameField = 1;

               UPDATE [${mjSchema}].[EntityField]
               SET DefaultInView = 1
               WHERE ID = '54CD3BC9-E3DF-4B33-9413-B2F137EB2452'
               AND AutoUpdateDefaultInView = 1;

               UPDATE [${mjSchema}].[EntityField]
               SET DefaultInView = 1
               WHERE ID = '8A9B093F-91D1-4991-9069-4F2F36AD9181'
               AND AutoUpdateDefaultInView = 1;

               UPDATE [${mjSchema}].[EntityField]
               SET DefaultInView = 1
               WHERE ID = '47F2BC8C-BAA7-4720-8425-3F982EDFD315'
               AND AutoUpdateDefaultInView = 1;

               UPDATE [${mjSchema}].[EntityField]
               SET DefaultInView = 1
               WHERE ID = 'FF322D0F-97CB-4CEE-9C1E-C347A4C145AE'
               AND AutoUpdateDefaultInView = 1;

               UPDATE [${mjSchema}].[EntityField]
               SET IncludeInUserSearchAPI = 1
               WHERE ID = '8A9B093F-91D1-4991-9069-4F2F36AD9181'
               AND AutoUpdateIncludeInUserSearchAPI = 1;

               UPDATE [${mjSchema}].[EntityField]
               SET IncludeInUserSearchAPI = 1
               WHERE ID = '47F2BC8C-BAA7-4720-8425-3F982EDFD315'
               AND AutoUpdateIncludeInUserSearchAPI = 1;

               UPDATE [${mjSchema}].[EntityField]
               SET UserSearchPredicateAPI = 'BeginsWith'
               WHERE ID = '8A9B093F-91D1-4991-9069-4F2F36AD9181'
               AND AutoUpdateUserSearchPredicate = 1;

               UPDATE [${mjSchema}].[EntityField]
               SET UserSearchPredicateAPI = 'Exact'
               WHERE ID = '47F2BC8C-BAA7-4720-8425-3F982EDFD315'
               AND AutoUpdateUserSearchPredicate = 1;

/* Set categories for 12 fields */

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Repositories.ID 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'System Metadata',
   GeneratedFormSection = 'Category'
WHERE 
   ID = 'D38E3C3F-3676-439B-9111-DF4565789C9F';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Repositories.Owner 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Repository Details',
   GeneratedFormSection = 'Category'
WHERE 
   ID = '16994C95-2791-47C6-B378-4AF1EACE655F';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Repositories.Name 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Repository Details',
   GeneratedFormSection = 'Category'
WHERE 
   ID = '8CFC093F-2135-437E-93A8-493A64DFA174';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Repositories.DefaultBranch 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Repository Details',
   GeneratedFormSection = 'Category'
WHERE 
   ID = '8231446A-482B-4D5F-A1ED-AE1A717F50A0';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Repositories.IsTracked 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Sync and Import Configuration',
   GeneratedFormSection = 'Category'
WHERE 
   ID = '89C19524-C1FB-441E-A66C-577DDC5D41C3';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Repositories.ImportRule 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Sync and Import Configuration',
   GeneratedFormSection = 'Category'
WHERE 
   ID = 'D09CC770-1CBB-4078-8186-BF3ED875F03C';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Repositories.InstallationID 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Integration and Links',
   GeneratedFormSection = 'Category'
WHERE 
   ID = 'F6397E85-2F8B-4B39-A42F-4063209B7C3E';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Repositories.OrganizationID 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Integration and Links',
   GeneratedFormSection = 'Category'
WHERE 
   ID = '507961D4-497E-4B22-9CFF-C6506F32B45C';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Repositories.DeliveryPolicyID 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Integration and Links',
   GeneratedFormSection = 'Category'
WHERE 
   ID = '2685C802-43EA-4389-B1CC-5D007755DCD6';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Repositories.__mj_CreatedAt 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'System Metadata',
   GeneratedFormSection = 'Category'
WHERE 
   ID = 'F9323407-463F-4EF0-8E56-800D98360B4A';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Repositories.__mj_UpdatedAt 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'System Metadata',
   GeneratedFormSection = 'Category'
WHERE 
   ID = '1E25CF76-141F-4848-8A29-C47A7A522297';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Repositories.Organization 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Integration and Links',
   GeneratedFormSection = 'Category'
WHERE 
   ID = 'FB25EA32-A752-4FA3-AD55-72034E18507B';

/* Set entity icon to fa fa-code-branch */

               UPDATE [${mjSchema}].[Entity]
               SET [Icon] = 'fa fa-code-branch', [__mj_UpdatedAt] = GETUTCDATE()
               WHERE [ID] = '6B363236-31AB-477D-8188-08F5FA9942EF';

/* Insert FieldCategoryInfo setting for entity */
IF NOT EXISTS (
      SELECT 1 FROM [${mjSchema}].[EntitySetting] WHERE [EntityID] = '6B363236-31AB-477D-8188-08F5FA9942EF' AND [Name] = 'FieldCategoryInfo'
   )
   BEGIN
      INSERT INTO [${mjSchema}].[EntitySetting] ([ID], [EntityID], [Name], [Value], [__mj_CreatedAt], [__mj_UpdatedAt])
               VALUES ('10dd11f1-5444-5fba-8141-e897ef1cb5b5', '6B363236-31AB-477D-8188-08F5FA9942EF', 'FieldCategoryInfo', '{
  "Integration and Links": {
    "description": "GitHub app installation and organization/policy links",
    "icon": "fa fa-link"
  },
  "Repository Details": {
    "description": "Core GitHub repository identification and branch configuration",
    "icon": "fa fa-code-branch"
  },
  "Sync and Import Configuration": {
    "description": "Rules and toggles for tracking and importing GitHub issues and pull requests",
    "icon": "fa fa-sliders-h"
  },
  "System Metadata": {
    "description": "System-managed audit and tracking fields",
    "icon": "fa fa-cog"
  }
}', GETUTCDATE(), GETUTCDATE())
   END;

/* Insert FieldCategoryIcons setting (legacy) */
IF NOT EXISTS (
      SELECT 1 FROM [${mjSchema}].[EntitySetting] WHERE [EntityID] = '6B363236-31AB-477D-8188-08F5FA9942EF' AND [Name] = 'FieldCategoryIcons'
   )
   BEGIN
      INSERT INTO [${mjSchema}].[EntitySetting] ([ID], [EntityID], [Name], [Value], [__mj_CreatedAt], [__mj_UpdatedAt])
               VALUES ('091ada65-bfce-5cb9-900b-0e1a1c46c0af', '6B363236-31AB-477D-8188-08F5FA9942EF', 'FieldCategoryIcons', '{
  "Integration and Links": "fa fa-link",
  "Repository Details": "fa fa-code-branch",
  "Sync and Import Configuration": "fa fa-sliders-h",
  "System Metadata": "fa fa-cog"
}', GETUTCDATE(), GETUTCDATE())
   END;

/* Set categories for 28 fields */

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks.ID 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'System Metadata',
   GeneratedFormSection = 'Category'
WHERE 
   ID = '4AFBF1A3-202B-4657-938B-652EF047768F';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks.RepositoryID 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Pull Request Details',
   GeneratedFormSection = 'Category'
WHERE 
   ID = '80C22B8D-1383-4AC3-BC9D-6540C3FDED78';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks.Number 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Pull Request Details',
   GeneratedFormSection = 'Category'
WHERE 
   ID = 'D0157CE0-E6EE-41D6-828D-F774B96AB24C';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks.NodeID 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Pull Request Details',
   GeneratedFormSection = 'Category'
WHERE 
   ID = '07679AF9-E8A9-4AEB-AD5C-2CB9BA40A3F4';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks.HtmlURL 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Pull Request Details',
   GeneratedFormSection = 'Category',
   DisplayName = 'HTML URL',
   ExtendedType = 'URL'
WHERE 
   ID = 'F2598281-767D-423E-B92A-3000708EFE1A';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks.State 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Status and Workflow',
   GeneratedFormSection = 'Category'
WHERE 
   ID = '5CBFAABD-0AF2-4E67-91B1-F089E6C56C4D';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks.IsDraft 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Status and Workflow',
   GeneratedFormSection = 'Category'
WHERE 
   ID = '6702784E-CE7D-41DD-A906-6958E5415A5D';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks.HeadBranch 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Branch and Commit Info',
   GeneratedFormSection = 'Category'
WHERE 
   ID = '6A042282-8DC0-4158-B972-F2EFF37C1387';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks.HeadSha 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Branch and Commit Info',
   GeneratedFormSection = 'Category',
   DisplayName = 'Head SHA'
WHERE 
   ID = '68D879E4-6123-482D-8637-A6B7E250B9CB';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks.BaseBranch 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Branch and Commit Info',
   GeneratedFormSection = 'Category'
WHERE 
   ID = '8D2DB26A-0621-4A94-A932-A4C1F47E1DCF';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks.AuthorLogin 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Pull Request Details',
   GeneratedFormSection = 'Category'
WHERE 
   ID = 'DEBADDF7-A747-400C-BEC1-8A93FDDF6193';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks.ReviewDecision 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Status and Workflow',
   GeneratedFormSection = 'Category'
WHERE 
   ID = 'D0242DB3-ACFC-4AD6-9B8A-7AF48E27BBE4';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks.ChecksStatus 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Status and Workflow',
   GeneratedFormSection = 'Category'
WHERE 
   ID = '57B97F3B-7437-49C3-A2A3-89F8F14F3224';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks.ChangedFiles 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Diff Metrics',
   GeneratedFormSection = 'Category'
WHERE 
   ID = 'C43679AF-0136-4312-BFC7-50A774A1DF96';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks.Additions 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Diff Metrics',
   GeneratedFormSection = 'Category'
WHERE 
   ID = 'E7C6D6DD-3B2C-4D1F-854C-36EC48EA6541';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks.Deletions 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Diff Metrics',
   GeneratedFormSection = 'Category'
WHERE 
   ID = '79A88ACA-735F-4126-AF8C-E84E0EAB6DBE';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks.Labels 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Pull Request Details',
   GeneratedFormSection = 'Category',
   ExtendedType = 'JSON'
WHERE 
   ID = '88926596-FB58-4AB7-AEF8-3BCB7F927B0A';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks.Milestone 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Pull Request Details',
   GeneratedFormSection = 'Category'
WHERE 
   ID = '3A7BDB54-1596-447C-B919-0DBA77BF1988';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks.MilestoneDueAt 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Dates and Timeline',
   GeneratedFormSection = 'Category'
WHERE 
   ID = '4CCF1BDD-F21D-4003-8499-9A1D6C9C02E2';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks.MergedAt 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Dates and Timeline',
   GeneratedFormSection = 'Category'
WHERE 
   ID = '4801E8B7-847B-411D-B5F0-002551B4F237';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks.LinkedIssueTaskID 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Pull Request Details',
   GeneratedFormSection = 'Category'
WHERE 
   ID = 'AF64DC8D-5285-46A8-A44B-145BDA229838';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks.BodyHash 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'System Metadata',
   GeneratedFormSection = 'Category'
WHERE 
   ID = '6E18BAB8-7F3D-42C0-AC47-D1CCB685A2E0';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks.GitHubUpdatedAt 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Dates and Timeline',
   GeneratedFormSection = 'Category',
   DisplayName = 'GitHub Updated At'
WHERE 
   ID = 'CFA8847F-9404-4B62-810F-863DD426852B';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks.LastSyncedAt 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Dates and Timeline',
   GeneratedFormSection = 'Category'
WHERE 
   ID = '4E1457AC-6957-44B9-BAF9-93C09114807E';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks.__mj_CreatedAt 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'System Metadata',
   GeneratedFormSection = 'Category'
WHERE 
   ID = '5D5A0E69-1ED4-4863-A611-34BF239FA515';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks.__mj_UpdatedAt 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'System Metadata',
   GeneratedFormSection = 'Category'
WHERE 
   ID = 'F3A56A47-49D7-4E66-B762-AEDC7F65DBDB';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks.Repository 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Pull Request Details',
   GeneratedFormSection = 'Category'
WHERE 
   ID = '4E32F6E1-BD8A-4F42-8F15-04093EAF9EB2';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks.LinkedIssueTask 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Pull Request Details',
   GeneratedFormSection = 'Category'
WHERE 
   ID = '34645952-8CA4-4A7F-AF70-1B782BD89C0B';

/* Set entity icon to fa fa-code-branch */

               UPDATE [${mjSchema}].[Entity]
               SET [Icon] = 'fa fa-code-branch', [__mj_UpdatedAt] = GETUTCDATE()
               WHERE [ID] = 'A6B673F8-43BC-4875-AFF6-AC620592822E';

/* Insert FieldCategoryInfo setting for entity */
IF NOT EXISTS (
      SELECT 1 FROM [${mjSchema}].[EntitySetting] WHERE [EntityID] = 'A6B673F8-43BC-4875-AFF6-AC620592822E' AND [Name] = 'FieldCategoryInfo'
   )
   BEGIN
      INSERT INTO [${mjSchema}].[EntitySetting] ([ID], [EntityID], [Name], [Value], [__mj_CreatedAt], [__mj_UpdatedAt])
               VALUES ('1a852e8b-0efa-544d-9498-b739c112e598', 'A6B673F8-43BC-4875-AFF6-AC620592822E', 'FieldCategoryInfo', '{
  "Branch and Commit Info": {
    "description": "Source and target branches alongside head commit information",
    "icon": "fa fa-code"
  },
  "Dates and Timeline": {
    "description": "Timestamps for milestones, merges, and synchronization events",
    "icon": "fa fa-calendar-alt"
  },
  "Diff Metrics": {
    "description": "Code diff metrics including changed files, additions, and deletions",
    "icon": "fa fa-chart-bar"
  },
  "Pull Request Details": {
    "description": "Core pull request metadata, identifiers, links, and relationships",
    "icon": "fa fa-code-branch"
  },
  "Status and Workflow": {
    "description": "Lifecycle state, draft status, review decisions, and CI check statuses",
    "icon": "fa fa-tasks"
  },
  "System Metadata": {
    "description": "System-managed audit trails and sync hashes",
    "icon": "fa fa-cog"
  }
}', GETUTCDATE(), GETUTCDATE())
   END;

/* Insert FieldCategoryIcons setting (legacy) */
IF NOT EXISTS (
      SELECT 1 FROM [${mjSchema}].[EntitySetting] WHERE [EntityID] = 'A6B673F8-43BC-4875-AFF6-AC620592822E' AND [Name] = 'FieldCategoryIcons'
   )
   BEGIN
      INSERT INTO [${mjSchema}].[EntitySetting] ([ID], [EntityID], [Name], [Value], [__mj_CreatedAt], [__mj_UpdatedAt])
               VALUES ('64509eb4-e40e-53f0-be3e-229cd8b216c9', 'A6B673F8-43BC-4875-AFF6-AC620592822E', 'FieldCategoryIcons', '{
  "Branch and Commit Info": "fa fa-code",
  "Dates and Timeline": "fa fa-calendar-alt",
  "Diff Metrics": "fa fa-chart-bar",
  "Pull Request Details": "fa fa-code-branch",
  "Status and Workflow": "fa fa-tasks",
  "System Metadata": "fa fa-cog"
}', GETUTCDATE(), GETUTCDATE())
   END;

/* Set field properties for entity */

               UPDATE [${mjSchema}].[EntityField]
               SET IsNameField = 1
               WHERE ID = '2680087D-C275-43F1-8A02-EB2FAC64624C'
               AND AutoUpdateIsNameField = 1;

               UPDATE [${mjSchema}].[EntityField]
               SET DefaultInView = 1
               WHERE ID = '60F671EB-D0B7-42FF-AD43-0A300001E37E'
               AND AutoUpdateDefaultInView = 1;

/* Set categories for 8 fields */

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Identities.ID 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'System Metadata',
   GeneratedFormSection = 'Category'
WHERE 
   ID = '14420024-8D4C-43FB-B3C2-C335CFDCA13F';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Identities.GitHubLogin 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'GitHub Identity Details',
   GeneratedFormSection = 'Category',
   DisplayName = 'GitHub Login'
WHERE 
   ID = '2680087D-C275-43F1-8A02-EB2FAC64624C';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Identities.PersonID 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'GitHub Identity Details',
   GeneratedFormSection = 'Category',
   DisplayName = 'Person'
WHERE 
   ID = '86923F31-A619-4171-9700-360D0F84EAEE';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Identities.GitHubUserID 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'GitHub Identity Details',
   GeneratedFormSection = 'Category',
   DisplayName = 'GitHub User ID'
WHERE 
   ID = 'DA3FF8E3-9102-4BDC-9747-2C1B92282829';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Identities.IsActive 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'GitHub Identity Details',
   GeneratedFormSection = 'Category'
WHERE 
   ID = '859B1D57-888E-4F5E-9394-11927FCDE8CA';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Identities.Person 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'GitHub Identity Details',
   GeneratedFormSection = 'Category',
   DisplayName = 'Person Name'
WHERE 
   ID = '60F671EB-D0B7-42FF-AD43-0A300001E37E';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Identities.__mj_CreatedAt 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'System Metadata',
   GeneratedFormSection = 'Category'
WHERE 
   ID = '0F52C847-41B4-44F5-9FF7-83DF5BFC74D9';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Identities.__mj_UpdatedAt 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'System Metadata',
   GeneratedFormSection = 'Category'
WHERE 
   ID = '168EED29-3B45-4398-973F-71A7DA22E916';

/* Set entity icon to fa fa-code-branch */

               UPDATE [${mjSchema}].[Entity]
               SET [Icon] = 'fa fa-code-branch', [__mj_UpdatedAt] = GETUTCDATE()
               WHERE [ID] = 'C7CC2BCF-090E-4832-89C7-A051F302C393';

/* Insert FieldCategoryInfo setting for entity */
IF NOT EXISTS (
      SELECT 1 FROM [${mjSchema}].[EntitySetting] WHERE [EntityID] = 'C7CC2BCF-090E-4832-89C7-A051F302C393' AND [Name] = 'FieldCategoryInfo'
   )
   BEGIN
      INSERT INTO [${mjSchema}].[EntitySetting] ([ID], [EntityID], [Name], [Value], [__mj_CreatedAt], [__mj_UpdatedAt])
               VALUES ('0c431937-6f04-5387-a30d-2da839924e63', 'C7CC2BCF-090E-4832-89C7-A051F302C393', 'FieldCategoryInfo', '{
  "GitHub Identity Details": {
    "description": "Mapping configuration between GitHub users and BizApps Person records",
    "icon": "fa fa-id-card"
  },
  "System Metadata": {
    "description": "System-managed audit and tracking fields",
    "icon": "fa fa-cog"
  }
}', GETUTCDATE(), GETUTCDATE())
   END;

/* Insert FieldCategoryIcons setting (legacy) */
IF NOT EXISTS (
      SELECT 1 FROM [${mjSchema}].[EntitySetting] WHERE [EntityID] = 'C7CC2BCF-090E-4832-89C7-A051F302C393' AND [Name] = 'FieldCategoryIcons'
   )
   BEGIN
      INSERT INTO [${mjSchema}].[EntitySetting] ([ID], [EntityID], [Name], [Value], [__mj_CreatedAt], [__mj_UpdatedAt])
               VALUES ('db0318b6-aeb2-5899-95a2-1355bc2675e7', 'C7CC2BCF-090E-4832-89C7-A051F302C393', 'FieldCategoryIcons', '{
  "GitHub Identity Details": "fa fa-id-card",
  "System Metadata": "fa fa-cog"
}', GETUTCDATE(), GETUTCDATE())
   END;

/* Set categories for 17 fields */

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks.ID 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'System Metadata',
   GeneratedFormSection = 'Category'
WHERE 
   ID = 'F041D734-2D08-48F3-BAA4-C29F45BFB5DE';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks.RepositoryID 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'GitHub Issue Details',
   GeneratedFormSection = 'Category'
WHERE 
   ID = '54442A79-CEAD-408B-82AA-4119053FE27E';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks.Number 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'GitHub Issue Details',
   GeneratedFormSection = 'Category',
   DisplayName = 'Issue Number'
WHERE 
   ID = 'A97CA445-668E-4763-A2C6-74DE67A33925';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks.NodeID 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'GitHub Issue Details',
   GeneratedFormSection = 'Category'
WHERE 
   ID = 'B0C058E3-BA70-4F2A-9B84-21AB522E8E6D';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks.HtmlURL 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'GitHub Issue Details',
   GeneratedFormSection = 'Category',
   DisplayName = 'HTML URL',
   ExtendedType = 'URL'
WHERE 
   ID = '6B287FDE-CF5A-4381-84A1-96A45D3E58C4';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks.State 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'GitHub Issue Details',
   GeneratedFormSection = 'Category'
WHERE 
   ID = '54CD3BC9-E3DF-4B33-9413-B2F137EB2452';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks.StateReason 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'GitHub Issue Details',
   GeneratedFormSection = 'Category'
WHERE 
   ID = 'AC27EB42-F18D-4444-99A2-9E454DBAEB49';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks.Labels 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'GitHub Issue Details',
   GeneratedFormSection = 'Category',
   ExtendedType = 'JSON'
WHERE 
   ID = '9F961E3C-910B-44C2-A78F-E0AC03ED963F';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks.AuthorLogin 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'GitHub Issue Details',
   GeneratedFormSection = 'Category'
WHERE 
   ID = '47F2BC8C-BAA7-4720-8425-3F982EDFD315';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks.Repository 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'GitHub Issue Details',
   GeneratedFormSection = 'Category'
WHERE 
   ID = '7EACB6DE-E83E-4D1E-9523-F035AC1C7547';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks.Milestone 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Milestone and Timeline',
   GeneratedFormSection = 'Category'
WHERE 
   ID = '8A9B093F-91D1-4991-9069-4F2F36AD9181';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks.MilestoneDueAt 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Milestone and Timeline',
   GeneratedFormSection = 'Category'
WHERE 
   ID = '9A88E775-DCA4-46ED-B580-CC79394B5B69';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks.BodyHash 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Sync and Audit Information',
   GeneratedFormSection = 'Category'
WHERE 
   ID = '0B5ED37C-D3AB-4C8A-A484-F0E12DBD9744';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks.GitHubUpdatedAt 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Sync and Audit Information',
   GeneratedFormSection = 'Category',
   DisplayName = 'GitHub Updated At'
WHERE 
   ID = 'FF322D0F-97CB-4CEE-9C1E-C347A4C145AE';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks.LastSyncedAt 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Sync and Audit Information',
   GeneratedFormSection = 'Category'
WHERE 
   ID = '8D123F90-1CD8-42E3-A8BF-C121BE46401B';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks.__mj_CreatedAt 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'System Metadata',
   GeneratedFormSection = 'Category'
WHERE 
   ID = 'DEC034D1-627F-4099-84D9-71EBD162ACBD';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks.__mj_UpdatedAt 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'System Metadata',
   GeneratedFormSection = 'Category'
WHERE 
   ID = 'F846083A-3F9A-4728-86D8-6772A47AC54E';

/* Set entity icon to fab fa-github */

               UPDATE [${mjSchema}].[Entity]
               SET [Icon] = 'fab fa-github', [__mj_UpdatedAt] = GETUTCDATE()
               WHERE [ID] = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605';

/* Insert FieldCategoryInfo setting for entity */
IF NOT EXISTS (
      SELECT 1 FROM [${mjSchema}].[EntitySetting] WHERE [EntityID] = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605' AND [Name] = 'FieldCategoryInfo'
   )
   BEGIN
      INSERT INTO [${mjSchema}].[EntitySetting] ([ID], [EntityID], [Name], [Value], [__mj_CreatedAt], [__mj_UpdatedAt])
               VALUES ('41f6983a-476f-592d-9eb8-52ee375ce6eb', 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605', 'FieldCategoryInfo', '{
  "GitHub Issue Details": {
    "description": "Core GitHub issue metadata, identifiers, URLs, state, and labels",
    "icon": "fab fa-github"
  },
  "Milestone and Timeline": {
    "description": "GitHub milestone assignments and associated target due dates",
    "icon": "fa fa-calendar-alt"
  },
  "Sync and Audit Information": {
    "description": "External synchronization tracking keys, content hashes, and upstream timestamps",
    "icon": "fa fa-sync"
  },
  "System Metadata": {
    "description": "System-managed audit and primary key fields",
    "icon": "fa fa-cog"
  }
}', GETUTCDATE(), GETUTCDATE())
   END;

/* Insert FieldCategoryIcons setting (legacy) */
IF NOT EXISTS (
      SELECT 1 FROM [${mjSchema}].[EntitySetting] WHERE [EntityID] = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605' AND [Name] = 'FieldCategoryIcons'
   )
   BEGIN
      INSERT INTO [${mjSchema}].[EntitySetting] ([ID], [EntityID], [Name], [Value], [__mj_CreatedAt], [__mj_UpdatedAt])
               VALUES ('3c7e42bf-7e88-50ae-a5c6-bf27303fe434', 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605', 'FieldCategoryIcons', '{
  "GitHub Issue Details": "fab fa-github",
  "Milestone and Timeline": "fa fa-calendar-alt",
  "Sync and Audit Information": "fa fa-sync",
  "System Metadata": "fa fa-cog"
}', GETUTCDATE(), GETUTCDATE())
   END;

/* SQL text to update existing entities from schema */
EXEC [${mjSchema}].[spUpdateExistingEntitiesFromSchema] @ExcludedSchemaNames='', @IncludedSchemaNames='${flyway:defaultSchema}';

/* SQL text to update existing entity fields from schema */
EXEC [${mjSchema}].[spUpdateExistingEntityFieldsFromSchema] @ExcludedSchemaNames='', @IncludedSchemaNames='${flyway:defaultSchema}';

/* SQL text to set default column width where needed */
EXEC [${mjSchema}].[spSetDefaultColumnWidthWhereNeeded] @ExcludedSchemaNames='', @IncludedSchemaNames='${flyway:defaultSchema}';

/* Set IS-A ParentID for "MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks" → "MJ_BizApps_Tasks: Tasks" */
UPDATE [${mjSchema}].[Entity]
                                  SET [__mj_UpdatedAt]=GETUTCDATE(),
                                      [ParentID] = 'B348FFA2-B1A7-4AC2-B6FD-F4E0C0697466'
                                  WHERE [ID] = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605';

/* Set IS-A ParentID for "MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks" → "MJ_BizApps_Tasks: Tasks" */
UPDATE [${mjSchema}].[Entity]
                                  SET [__mj_UpdatedAt]=GETUTCDATE(),
                                      [ParentID] = 'B348FFA2-B1A7-4AC2-B6FD-F4E0C0697466'
                                  WHERE [ID] = 'A6B673F8-43BC-4875-AFF6-AC620592822E';

/* Update attributes on "MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks" from additionalSchemaInfo */
UPDATE [${mjSchema}].[Entity]
                              SET [__mj_UpdatedAt] = GETUTCDATE(), [Configuration] = '{"Comments": {"Enabled": true, "AllowedCommentTypes": ["COMMENT", "FIELD_SUGGESTION"]}}'
                              WHERE [ID] = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605';

/* Update attributes on "MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks" from additionalSchemaInfo */
UPDATE [${mjSchema}].[Entity]
                              SET [__mj_UpdatedAt] = GETUTCDATE(), [Configuration] = '{"Comments": {"Enabled": true, "AllowedCommentTypes": ["COMMENT", "FIELD_SUGGESTION"]}}'
                              WHERE [ID] = 'A6B673F8-43BC-4875-AFF6-AC620592822E';

/* SQL text to sync schema info from database schemas */
EXEC [${mjSchema}].[spUpdateSchemaInfoFromDatabase] @ExcludedSchemaNames='', @IncludedSchemaNames='${flyway:defaultSchema}';

/* Base View SQL for MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks */
-----------------------------------------------------------------
-- SQL Code Generation
-- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks
-- Item: vwGitHubPullRequestTasks
--
-- This was generated by the MemberJunction CodeGen tool.
-- This file should NOT be edited by hand.
-----------------------------------------------------------------

------------------------------------------------------------
----- BASE VIEW FOR ENTITY:      MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks
-----               SCHEMA:      ${flyway:defaultSchema}
-----               BASE TABLE:  GitHubPullRequestTask
-----               PRIMARY KEY: ID
------------------------------------------------------------
IF OBJECT_ID('[${flyway:defaultSchema}].[vwGitHubPullRequestTasks]', 'V') IS NOT NULL
    DROP VIEW [${flyway:defaultSchema}].[vwGitHubPullRequestTasks];
GO

CREATE VIEW [${flyway:defaultSchema}].[vwGitHubPullRequestTasks]
AS
SELECT
    g.*,
    __mj_isa_p1.[Name],
    __mj_isa_p1.[Description],
    __mj_isa_p1.[TypeID],
    __mj_isa_p1.[CategoryID],
    __mj_isa_p1.[ParentID],
    __mj_isa_p1.[Status],
    __mj_isa_p1.[Priority],
    __mj_isa_p1.[StartedAt],
    __mj_isa_p1.[DueAt],
    __mj_isa_p1.[CompletedAt],
    __mj_isa_p1.[HoursEstimated],
    __mj_isa_p1.[HoursActual],
    __mj_isa_p1.[PercentComplete],
    __mj_isa_p1.[Sequence],
    __mj_isa_p1.[BlockedReason],
    __mj_isa_p1.[CompletionNotes],
    __mj_isa_p1.[CreatedByPersonID],
    __mj_isa_p1.[OverdueNotifiedAt],
    __mj_isa_p1.[TaskTypeStatusID],
    __mj_isa_p1.[PredictedSLABreachProbability],
    __mj_isa_p1.[PredictedSLARiskBand],
    __mj_isa_p1.[PredictedSLAScoredAt],
    __mj_isa_p1.[HealthStatus],
    __mj_isa_p1.[ConfidenceScore],
    __mj_isa_p1.[BaselineValue],
    __mj_isa_p1.[TargetValue],
    __mj_isa_p1.[CurrentValue],
    __mj_isa_p1.[UnitOfMeasure],
    __mj_isa_p1.[MetricDirection],
    __mj_isa_p1.[RollupWeight],
    __mj_isa_p1.[PlanningPeriod],
    __mj_isa_p1.[CheckInCadence],
    __mj_isa_p1.[LastCheckInAt],
    __mj_isa_p1.[NextCheckInDueAt],
    mjBizAppsTasksGitHubGitHubRepository_RepositoryID.[Name] AS [Repository],
    mjBizAppsTasksTask_LinkedIssueTaskID.[Name] AS [LinkedIssueTask]
FROM
    [${flyway:defaultSchema}].[GitHubPullRequestTask] AS g
INNER JOIN
    [__mj_BizAppsTasks].[Task] AS __mj_isa_p1
  ON
    [g].[ID] = __mj_isa_p1.[ID]
LEFT OUTER JOIN
    [${flyway:defaultSchema}].[GitHubRepository] AS mjBizAppsTasksGitHubGitHubRepository_RepositoryID
  ON
    [g].[RepositoryID] = mjBizAppsTasksGitHubGitHubRepository_RepositoryID.[ID]
LEFT OUTER JOIN
    [__mj_BizAppsTasks].[Task] AS mjBizAppsTasksTask_LinkedIssueTaskID
  ON
    [g].[LinkedIssueTaskID] = mjBizAppsTasksTask_LinkedIssueTaskID.[ID]
GO
REVOKE SELECT ON [${flyway:defaultSchema}].[vwGitHubPullRequestTasks] FROM [cdp_Developer]
REVOKE SELECT ON [${flyway:defaultSchema}].[vwGitHubPullRequestTasks] FROM [cdp_Integration]
REVOKE SELECT ON [${flyway:defaultSchema}].[vwGitHubPullRequestTasks] FROM [cdp_UI]
GRANT SELECT ON [${flyway:defaultSchema}].[vwGitHubPullRequestTasks] TO [cdp_UI], [cdp_Developer], [cdp_Integration];

/* Base View Permissions SQL for MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks */
-----------------------------------------------------------------
-- SQL Code Generation
-- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks
-- Item: Permissions for vwGitHubPullRequestTasks
--
-- This was generated by the MemberJunction CodeGen tool.
-- This file should NOT be edited by hand.
-----------------------------------------------------------------

REVOKE SELECT ON [${flyway:defaultSchema}].[vwGitHubPullRequestTasks] FROM [cdp_Developer]
REVOKE SELECT ON [${flyway:defaultSchema}].[vwGitHubPullRequestTasks] FROM [cdp_Integration]
REVOKE SELECT ON [${flyway:defaultSchema}].[vwGitHubPullRequestTasks] FROM [cdp_UI]
GRANT SELECT ON [${flyway:defaultSchema}].[vwGitHubPullRequestTasks] TO [cdp_UI], [cdp_Developer], [cdp_Integration];

/* spCreate SQL for MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks */
-----------------------------------------------------------------
-- SQL Code Generation
-- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks
-- Item: spCreateGitHubPullRequestTask
--
-- This was generated by the MemberJunction CodeGen tool.
-- This file should NOT be edited by hand.
-----------------------------------------------------------------

------------------------------------------------------------
----- CREATE PROCEDURE FOR GitHubPullRequestTask
------------------------------------------------------------
IF OBJECT_ID('[${flyway:defaultSchema}].[spCreateGitHubPullRequestTask]', 'P') IS NOT NULL
    DROP PROCEDURE [${flyway:defaultSchema}].[spCreateGitHubPullRequestTask];
GO

CREATE PROCEDURE [${flyway:defaultSchema}].[spCreateGitHubPullRequestTask]
    @ID uniqueidentifier = NULL,
    @RepositoryID_Clear bit = 0,
    @RepositoryID uniqueidentifier = NULL,
    @Number_Clear bit = 0,
    @Number int = NULL,
    @NodeID_Clear bit = 0,
    @NodeID nvarchar(128) = NULL,
    @HtmlURL_Clear bit = 0,
    @HtmlURL nvarchar(1000) = NULL,
    @State nvarchar(20) = NULL,
    @IsDraft bit = NULL,
    @HeadBranch_Clear bit = 0,
    @HeadBranch nvarchar(255) = NULL,
    @HeadSha_Clear bit = 0,
    @HeadSha nvarchar(64) = NULL,
    @BaseBranch_Clear bit = 0,
    @BaseBranch nvarchar(255) = NULL,
    @AuthorLogin_Clear bit = 0,
    @AuthorLogin nvarchar(100) = NULL,
    @ReviewDecision_Clear bit = 0,
    @ReviewDecision nvarchar(40) = NULL,
    @ChecksStatus_Clear bit = 0,
    @ChecksStatus nvarchar(30) = NULL,
    @ChangedFiles_Clear bit = 0,
    @ChangedFiles int = NULL,
    @Additions_Clear bit = 0,
    @Additions int = NULL,
    @Deletions_Clear bit = 0,
    @Deletions int = NULL,
    @Labels_Clear bit = 0,
    @Labels nvarchar(MAX) = NULL,
    @Milestone_Clear bit = 0,
    @Milestone nvarchar(255) = NULL,
    @MilestoneDueAt_Clear bit = 0,
    @MilestoneDueAt datetimeoffset = NULL,
    @MergedAt_Clear bit = 0,
    @MergedAt datetimeoffset = NULL,
    @LinkedIssueTaskID_Clear bit = 0,
    @LinkedIssueTaskID uniqueidentifier = NULL,
    @BodyHash_Clear bit = 0,
    @BodyHash nvarchar(64) = NULL,
    @GitHubUpdatedAt_Clear bit = 0,
    @GitHubUpdatedAt datetimeoffset = NULL,
    @LastSyncedAt_Clear bit = 0,
    @LastSyncedAt datetimeoffset = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @ActualID UNIQUEIDENTIFIER = ISNULL(@ID, NEWID())
    INSERT INTO
    [${flyway:defaultSchema}].[GitHubPullRequestTask]
        (
            [RepositoryID],
                [Number],
                [NodeID],
                [HtmlURL],
                [State],
                [IsDraft],
                [HeadBranch],
                [HeadSha],
                [BaseBranch],
                [AuthorLogin],
                [ReviewDecision],
                [ChecksStatus],
                [ChangedFiles],
                [Additions],
                [Deletions],
                [Labels],
                [Milestone],
                [MilestoneDueAt],
                [MergedAt],
                [LinkedIssueTaskID],
                [BodyHash],
                [GitHubUpdatedAt],
                [LastSyncedAt],
                [ID]
        )
    VALUES
        (
            CASE WHEN @RepositoryID_Clear = 1 THEN NULL ELSE ISNULL(@RepositoryID, NULL) END,
                CASE WHEN @Number_Clear = 1 THEN NULL ELSE ISNULL(@Number, NULL) END,
                CASE WHEN @NodeID_Clear = 1 THEN NULL ELSE ISNULL(@NodeID, NULL) END,
                CASE WHEN @HtmlURL_Clear = 1 THEN NULL ELSE ISNULL(@HtmlURL, NULL) END,
                ISNULL(@State, 'open'),
                ISNULL(@IsDraft, 0),
                CASE WHEN @HeadBranch_Clear = 1 THEN NULL ELSE ISNULL(@HeadBranch, NULL) END,
                CASE WHEN @HeadSha_Clear = 1 THEN NULL ELSE ISNULL(@HeadSha, NULL) END,
                CASE WHEN @BaseBranch_Clear = 1 THEN NULL ELSE ISNULL(@BaseBranch, NULL) END,
                CASE WHEN @AuthorLogin_Clear = 1 THEN NULL ELSE ISNULL(@AuthorLogin, NULL) END,
                CASE WHEN @ReviewDecision_Clear = 1 THEN NULL ELSE ISNULL(@ReviewDecision, NULL) END,
                CASE WHEN @ChecksStatus_Clear = 1 THEN NULL ELSE ISNULL(@ChecksStatus, NULL) END,
                CASE WHEN @ChangedFiles_Clear = 1 THEN NULL ELSE ISNULL(@ChangedFiles, NULL) END,
                CASE WHEN @Additions_Clear = 1 THEN NULL ELSE ISNULL(@Additions, NULL) END,
                CASE WHEN @Deletions_Clear = 1 THEN NULL ELSE ISNULL(@Deletions, NULL) END,
                CASE WHEN @Labels_Clear = 1 THEN NULL ELSE ISNULL(@Labels, NULL) END,
                CASE WHEN @Milestone_Clear = 1 THEN NULL ELSE ISNULL(@Milestone, NULL) END,
                CASE WHEN @MilestoneDueAt_Clear = 1 THEN NULL ELSE ISNULL(@MilestoneDueAt, NULL) END,
                CASE WHEN @MergedAt_Clear = 1 THEN NULL ELSE ISNULL(@MergedAt, NULL) END,
                CASE WHEN @LinkedIssueTaskID_Clear = 1 THEN NULL ELSE ISNULL(@LinkedIssueTaskID, NULL) END,
                CASE WHEN @BodyHash_Clear = 1 THEN NULL ELSE ISNULL(@BodyHash, NULL) END,
                CASE WHEN @GitHubUpdatedAt_Clear = 1 THEN NULL ELSE ISNULL(@GitHubUpdatedAt, NULL) END,
                CASE WHEN @LastSyncedAt_Clear = 1 THEN NULL ELSE ISNULL(@LastSyncedAt, NULL) END,
                @ActualID
        )
    -- return the new record from the base view, which might have some calculated fields
    SELECT * FROM [${flyway:defaultSchema}].[vwGitHubPullRequestTasks] WHERE [ID] = @ActualID
END
GO
REVOKE EXECUTE ON [${flyway:defaultSchema}].[spCreateGitHubPullRequestTask] FROM [cdp_Developer]
REVOKE EXECUTE ON [${flyway:defaultSchema}].[spCreateGitHubPullRequestTask] FROM [cdp_Integration]
GRANT EXECUTE ON [${flyway:defaultSchema}].[spCreateGitHubPullRequestTask] TO [cdp_Developer], [cdp_Integration];

/* spCreate Permissions for MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks */

REVOKE EXECUTE ON [${flyway:defaultSchema}].[spCreateGitHubPullRequestTask] FROM [cdp_Developer]
REVOKE EXECUTE ON [${flyway:defaultSchema}].[spCreateGitHubPullRequestTask] FROM [cdp_Integration]
GRANT EXECUTE ON [${flyway:defaultSchema}].[spCreateGitHubPullRequestTask] TO [cdp_Developer], [cdp_Integration];

/* spUpdate SQL for MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks */
-----------------------------------------------------------------
-- SQL Code Generation
-- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks
-- Item: spUpdateGitHubPullRequestTask
--
-- This was generated by the MemberJunction CodeGen tool.
-- This file should NOT be edited by hand.
-----------------------------------------------------------------

------------------------------------------------------------
----- UPDATE PROCEDURE FOR GitHubPullRequestTask
------------------------------------------------------------
IF OBJECT_ID('[${flyway:defaultSchema}].[spUpdateGitHubPullRequestTask]', 'P') IS NOT NULL
    DROP PROCEDURE [${flyway:defaultSchema}].[spUpdateGitHubPullRequestTask];
GO

CREATE PROCEDURE [${flyway:defaultSchema}].[spUpdateGitHubPullRequestTask]
    @ID uniqueidentifier,
    @RepositoryID_Clear bit = 0,
    @RepositoryID uniqueidentifier = NULL,
    @Number_Clear bit = 0,
    @Number int = NULL,
    @NodeID_Clear bit = 0,
    @NodeID nvarchar(128) = NULL,
    @HtmlURL_Clear bit = 0,
    @HtmlURL nvarchar(1000) = NULL,
    @State nvarchar(20) = NULL,
    @IsDraft bit = NULL,
    @HeadBranch_Clear bit = 0,
    @HeadBranch nvarchar(255) = NULL,
    @HeadSha_Clear bit = 0,
    @HeadSha nvarchar(64) = NULL,
    @BaseBranch_Clear bit = 0,
    @BaseBranch nvarchar(255) = NULL,
    @AuthorLogin_Clear bit = 0,
    @AuthorLogin nvarchar(100) = NULL,
    @ReviewDecision_Clear bit = 0,
    @ReviewDecision nvarchar(40) = NULL,
    @ChecksStatus_Clear bit = 0,
    @ChecksStatus nvarchar(30) = NULL,
    @ChangedFiles_Clear bit = 0,
    @ChangedFiles int = NULL,
    @Additions_Clear bit = 0,
    @Additions int = NULL,
    @Deletions_Clear bit = 0,
    @Deletions int = NULL,
    @Labels_Clear bit = 0,
    @Labels nvarchar(MAX) = NULL,
    @Milestone_Clear bit = 0,
    @Milestone nvarchar(255) = NULL,
    @MilestoneDueAt_Clear bit = 0,
    @MilestoneDueAt datetimeoffset = NULL,
    @MergedAt_Clear bit = 0,
    @MergedAt datetimeoffset = NULL,
    @LinkedIssueTaskID_Clear bit = 0,
    @LinkedIssueTaskID uniqueidentifier = NULL,
    @BodyHash_Clear bit = 0,
    @BodyHash nvarchar(64) = NULL,
    @GitHubUpdatedAt_Clear bit = 0,
    @GitHubUpdatedAt datetimeoffset = NULL,
    @LastSyncedAt_Clear bit = 0,
    @LastSyncedAt datetimeoffset = NULL
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE
        [${flyway:defaultSchema}].[GitHubPullRequestTask]
    SET
        [RepositoryID] = CASE WHEN @RepositoryID_Clear = 1 THEN NULL ELSE ISNULL(@RepositoryID, [RepositoryID]) END,
        [Number] = CASE WHEN @Number_Clear = 1 THEN NULL ELSE ISNULL(@Number, [Number]) END,
        [NodeID] = CASE WHEN @NodeID_Clear = 1 THEN NULL ELSE ISNULL(@NodeID, [NodeID]) END,
        [HtmlURL] = CASE WHEN @HtmlURL_Clear = 1 THEN NULL ELSE ISNULL(@HtmlURL, [HtmlURL]) END,
        [State] = ISNULL(@State, [State]),
        [IsDraft] = ISNULL(@IsDraft, [IsDraft]),
        [HeadBranch] = CASE WHEN @HeadBranch_Clear = 1 THEN NULL ELSE ISNULL(@HeadBranch, [HeadBranch]) END,
        [HeadSha] = CASE WHEN @HeadSha_Clear = 1 THEN NULL ELSE ISNULL(@HeadSha, [HeadSha]) END,
        [BaseBranch] = CASE WHEN @BaseBranch_Clear = 1 THEN NULL ELSE ISNULL(@BaseBranch, [BaseBranch]) END,
        [AuthorLogin] = CASE WHEN @AuthorLogin_Clear = 1 THEN NULL ELSE ISNULL(@AuthorLogin, [AuthorLogin]) END,
        [ReviewDecision] = CASE WHEN @ReviewDecision_Clear = 1 THEN NULL ELSE ISNULL(@ReviewDecision, [ReviewDecision]) END,
        [ChecksStatus] = CASE WHEN @ChecksStatus_Clear = 1 THEN NULL ELSE ISNULL(@ChecksStatus, [ChecksStatus]) END,
        [ChangedFiles] = CASE WHEN @ChangedFiles_Clear = 1 THEN NULL ELSE ISNULL(@ChangedFiles, [ChangedFiles]) END,
        [Additions] = CASE WHEN @Additions_Clear = 1 THEN NULL ELSE ISNULL(@Additions, [Additions]) END,
        [Deletions] = CASE WHEN @Deletions_Clear = 1 THEN NULL ELSE ISNULL(@Deletions, [Deletions]) END,
        [Labels] = CASE WHEN @Labels_Clear = 1 THEN NULL ELSE ISNULL(@Labels, [Labels]) END,
        [Milestone] = CASE WHEN @Milestone_Clear = 1 THEN NULL ELSE ISNULL(@Milestone, [Milestone]) END,
        [MilestoneDueAt] = CASE WHEN @MilestoneDueAt_Clear = 1 THEN NULL ELSE ISNULL(@MilestoneDueAt, [MilestoneDueAt]) END,
        [MergedAt] = CASE WHEN @MergedAt_Clear = 1 THEN NULL ELSE ISNULL(@MergedAt, [MergedAt]) END,
        [LinkedIssueTaskID] = CASE WHEN @LinkedIssueTaskID_Clear = 1 THEN NULL ELSE ISNULL(@LinkedIssueTaskID, [LinkedIssueTaskID]) END,
        [BodyHash] = CASE WHEN @BodyHash_Clear = 1 THEN NULL ELSE ISNULL(@BodyHash, [BodyHash]) END,
        [GitHubUpdatedAt] = CASE WHEN @GitHubUpdatedAt_Clear = 1 THEN NULL ELSE ISNULL(@GitHubUpdatedAt, [GitHubUpdatedAt]) END,
        [LastSyncedAt] = CASE WHEN @LastSyncedAt_Clear = 1 THEN NULL ELSE ISNULL(@LastSyncedAt, [LastSyncedAt]) END
    WHERE
        [ID] = @ID

    -- Check if the update was successful
    IF @@ROWCOUNT = 0
        -- Nothing was updated, return no rows, but column structure from base view intact, semantically correct this way.
        SELECT TOP 0 * FROM [${flyway:defaultSchema}].[vwGitHubPullRequestTasks] WHERE 1=0
    ELSE
        -- Return the updated record so the caller can see the updated values and any calculated fields
        SELECT
                                        *
                                    FROM
                                        [${flyway:defaultSchema}].[vwGitHubPullRequestTasks]
                                    WHERE
                                        [ID] = @ID
                                    
END
GO

REVOKE EXECUTE ON [${flyway:defaultSchema}].[spUpdateGitHubPullRequestTask] FROM [cdp_Developer]
REVOKE EXECUTE ON [${flyway:defaultSchema}].[spUpdateGitHubPullRequestTask] FROM [cdp_Integration]
GRANT EXECUTE ON [${flyway:defaultSchema}].[spUpdateGitHubPullRequestTask] TO [cdp_Developer], [cdp_Integration]
GO

------------------------------------------------------------
----- TRIGGER FOR __mj_UpdatedAt field for the GitHubPullRequestTask table
------------------------------------------------------------
IF OBJECT_ID('[${flyway:defaultSchema}].[trgUpdateGitHubPullRequestTask]', 'TR') IS NOT NULL
    DROP TRIGGER [${flyway:defaultSchema}].[trgUpdateGitHubPullRequestTask];
GO
CREATE TRIGGER [${flyway:defaultSchema}].trgUpdateGitHubPullRequestTask
ON [${flyway:defaultSchema}].[GitHubPullRequestTask]
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE
        [${flyway:defaultSchema}].[GitHubPullRequestTask]
    SET
        __mj_UpdatedAt = GETUTCDATE()
    FROM
        [${flyway:defaultSchema}].[GitHubPullRequestTask] AS _organicTable
    INNER JOIN
        INSERTED AS I ON
        _organicTable.[ID] = I.[ID];
END;
GO

/* spUpdate Permissions for MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks */

REVOKE EXECUTE ON [${flyway:defaultSchema}].[spUpdateGitHubPullRequestTask] FROM [cdp_Developer]
REVOKE EXECUTE ON [${flyway:defaultSchema}].[spUpdateGitHubPullRequestTask] FROM [cdp_Integration]
GRANT EXECUTE ON [${flyway:defaultSchema}].[spUpdateGitHubPullRequestTask] TO [cdp_Developer], [cdp_Integration];

/* spDelete SQL for MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks */
-----------------------------------------------------------------
-- SQL Code Generation
-- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks
-- Item: spDeleteGitHubPullRequestTask
--
-- This was generated by the MemberJunction CodeGen tool.
-- This file should NOT be edited by hand.
-----------------------------------------------------------------

------------------------------------------------------------
----- DELETE PROCEDURE FOR GitHubPullRequestTask
------------------------------------------------------------
IF OBJECT_ID('[${flyway:defaultSchema}].[spDeleteGitHubPullRequestTask]', 'P') IS NOT NULL
    DROP PROCEDURE [${flyway:defaultSchema}].[spDeleteGitHubPullRequestTask];
GO

CREATE PROCEDURE [${flyway:defaultSchema}].[spDeleteGitHubPullRequestTask]
    @ID uniqueidentifier
AS
BEGIN
    SET NOCOUNT ON;

    DELETE FROM
        [${flyway:defaultSchema}].[GitHubPullRequestTask]
    WHERE
        [ID] = @ID


    -- Check if the delete was successful
    IF @@ROWCOUNT = 0
        SELECT NULL AS [ID] -- Return NULL for all primary key fields to indicate no record was deleted
    ELSE
        SELECT @ID AS [ID] -- Return the primary key values to indicate we successfully deleted the record
END
GO
REVOKE EXECUTE ON [${flyway:defaultSchema}].[spDeleteGitHubPullRequestTask] FROM [cdp_Developer]
REVOKE EXECUTE ON [${flyway:defaultSchema}].[spDeleteGitHubPullRequestTask] FROM [cdp_Integration]
GRANT EXECUTE ON [${flyway:defaultSchema}].[spDeleteGitHubPullRequestTask] TO [cdp_Developer], [cdp_Integration];

/* spDelete Permissions for MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks */

REVOKE EXECUTE ON [${flyway:defaultSchema}].[spDeleteGitHubPullRequestTask] FROM [cdp_Developer]
REVOKE EXECUTE ON [${flyway:defaultSchema}].[spDeleteGitHubPullRequestTask] FROM [cdp_Integration]
GRANT EXECUTE ON [${flyway:defaultSchema}].[spDeleteGitHubPullRequestTask] TO [cdp_Developer], [cdp_Integration];

/* Base View SQL for MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks */
-----------------------------------------------------------------
-- SQL Code Generation
-- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks
-- Item: vwGitHubIssueTasks
--
-- This was generated by the MemberJunction CodeGen tool.
-- This file should NOT be edited by hand.
-----------------------------------------------------------------

------------------------------------------------------------
----- BASE VIEW FOR ENTITY:      MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks
-----               SCHEMA:      ${flyway:defaultSchema}
-----               BASE TABLE:  GitHubIssueTask
-----               PRIMARY KEY: ID
------------------------------------------------------------
IF OBJECT_ID('[${flyway:defaultSchema}].[vwGitHubIssueTasks]', 'V') IS NOT NULL
    DROP VIEW [${flyway:defaultSchema}].[vwGitHubIssueTasks];
GO

CREATE VIEW [${flyway:defaultSchema}].[vwGitHubIssueTasks]
AS
SELECT
    g.*,
    __mj_isa_p1.[Name],
    __mj_isa_p1.[Description],
    __mj_isa_p1.[TypeID],
    __mj_isa_p1.[CategoryID],
    __mj_isa_p1.[ParentID],
    __mj_isa_p1.[Status],
    __mj_isa_p1.[Priority],
    __mj_isa_p1.[StartedAt],
    __mj_isa_p1.[DueAt],
    __mj_isa_p1.[CompletedAt],
    __mj_isa_p1.[HoursEstimated],
    __mj_isa_p1.[HoursActual],
    __mj_isa_p1.[PercentComplete],
    __mj_isa_p1.[Sequence],
    __mj_isa_p1.[BlockedReason],
    __mj_isa_p1.[CompletionNotes],
    __mj_isa_p1.[CreatedByPersonID],
    __mj_isa_p1.[OverdueNotifiedAt],
    __mj_isa_p1.[TaskTypeStatusID],
    __mj_isa_p1.[PredictedSLABreachProbability],
    __mj_isa_p1.[PredictedSLARiskBand],
    __mj_isa_p1.[PredictedSLAScoredAt],
    __mj_isa_p1.[HealthStatus],
    __mj_isa_p1.[ConfidenceScore],
    __mj_isa_p1.[BaselineValue],
    __mj_isa_p1.[TargetValue],
    __mj_isa_p1.[CurrentValue],
    __mj_isa_p1.[UnitOfMeasure],
    __mj_isa_p1.[MetricDirection],
    __mj_isa_p1.[RollupWeight],
    __mj_isa_p1.[PlanningPeriod],
    __mj_isa_p1.[CheckInCadence],
    __mj_isa_p1.[LastCheckInAt],
    __mj_isa_p1.[NextCheckInDueAt],
    mjBizAppsTasksGitHubGitHubRepository_RepositoryID.[Name] AS [Repository]
FROM
    [${flyway:defaultSchema}].[GitHubIssueTask] AS g
INNER JOIN
    [__mj_BizAppsTasks].[Task] AS __mj_isa_p1
  ON
    [g].[ID] = __mj_isa_p1.[ID]
LEFT OUTER JOIN
    [${flyway:defaultSchema}].[GitHubRepository] AS mjBizAppsTasksGitHubGitHubRepository_RepositoryID
  ON
    [g].[RepositoryID] = mjBizAppsTasksGitHubGitHubRepository_RepositoryID.[ID]
GO
REVOKE SELECT ON [${flyway:defaultSchema}].[vwGitHubIssueTasks] FROM [cdp_Developer]
REVOKE SELECT ON [${flyway:defaultSchema}].[vwGitHubIssueTasks] FROM [cdp_Integration]
REVOKE SELECT ON [${flyway:defaultSchema}].[vwGitHubIssueTasks] FROM [cdp_UI]
GRANT SELECT ON [${flyway:defaultSchema}].[vwGitHubIssueTasks] TO [cdp_UI], [cdp_Developer], [cdp_Integration];

/* Base View Permissions SQL for MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks */
-----------------------------------------------------------------
-- SQL Code Generation
-- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks
-- Item: Permissions for vwGitHubIssueTasks
--
-- This was generated by the MemberJunction CodeGen tool.
-- This file should NOT be edited by hand.
-----------------------------------------------------------------

REVOKE SELECT ON [${flyway:defaultSchema}].[vwGitHubIssueTasks] FROM [cdp_Developer]
REVOKE SELECT ON [${flyway:defaultSchema}].[vwGitHubIssueTasks] FROM [cdp_Integration]
REVOKE SELECT ON [${flyway:defaultSchema}].[vwGitHubIssueTasks] FROM [cdp_UI]
GRANT SELECT ON [${flyway:defaultSchema}].[vwGitHubIssueTasks] TO [cdp_UI], [cdp_Developer], [cdp_Integration];

/* spCreate SQL for MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks */
-----------------------------------------------------------------
-- SQL Code Generation
-- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks
-- Item: spCreateGitHubIssueTask
--
-- This was generated by the MemberJunction CodeGen tool.
-- This file should NOT be edited by hand.
-----------------------------------------------------------------

------------------------------------------------------------
----- CREATE PROCEDURE FOR GitHubIssueTask
------------------------------------------------------------
IF OBJECT_ID('[${flyway:defaultSchema}].[spCreateGitHubIssueTask]', 'P') IS NOT NULL
    DROP PROCEDURE [${flyway:defaultSchema}].[spCreateGitHubIssueTask];
GO

CREATE PROCEDURE [${flyway:defaultSchema}].[spCreateGitHubIssueTask]
    @ID uniqueidentifier = NULL,
    @RepositoryID_Clear bit = 0,
    @RepositoryID uniqueidentifier = NULL,
    @Number_Clear bit = 0,
    @Number int = NULL,
    @NodeID_Clear bit = 0,
    @NodeID nvarchar(128) = NULL,
    @HtmlURL_Clear bit = 0,
    @HtmlURL nvarchar(1000) = NULL,
    @State nvarchar(20) = NULL,
    @StateReason_Clear bit = 0,
    @StateReason nvarchar(40) = NULL,
    @Labels_Clear bit = 0,
    @Labels nvarchar(MAX) = NULL,
    @Milestone_Clear bit = 0,
    @Milestone nvarchar(255) = NULL,
    @MilestoneDueAt_Clear bit = 0,
    @MilestoneDueAt datetimeoffset = NULL,
    @AuthorLogin_Clear bit = 0,
    @AuthorLogin nvarchar(100) = NULL,
    @BodyHash_Clear bit = 0,
    @BodyHash nvarchar(64) = NULL,
    @GitHubUpdatedAt_Clear bit = 0,
    @GitHubUpdatedAt datetimeoffset = NULL,
    @LastSyncedAt_Clear bit = 0,
    @LastSyncedAt datetimeoffset = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @ActualID UNIQUEIDENTIFIER = ISNULL(@ID, NEWID())
    INSERT INTO
    [${flyway:defaultSchema}].[GitHubIssueTask]
        (
            [RepositoryID],
                [Number],
                [NodeID],
                [HtmlURL],
                [State],
                [StateReason],
                [Labels],
                [Milestone],
                [MilestoneDueAt],
                [AuthorLogin],
                [BodyHash],
                [GitHubUpdatedAt],
                [LastSyncedAt],
                [ID]
        )
    VALUES
        (
            CASE WHEN @RepositoryID_Clear = 1 THEN NULL ELSE ISNULL(@RepositoryID, NULL) END,
                CASE WHEN @Number_Clear = 1 THEN NULL ELSE ISNULL(@Number, NULL) END,
                CASE WHEN @NodeID_Clear = 1 THEN NULL ELSE ISNULL(@NodeID, NULL) END,
                CASE WHEN @HtmlURL_Clear = 1 THEN NULL ELSE ISNULL(@HtmlURL, NULL) END,
                ISNULL(@State, 'open'),
                CASE WHEN @StateReason_Clear = 1 THEN NULL ELSE ISNULL(@StateReason, NULL) END,
                CASE WHEN @Labels_Clear = 1 THEN NULL ELSE ISNULL(@Labels, NULL) END,
                CASE WHEN @Milestone_Clear = 1 THEN NULL ELSE ISNULL(@Milestone, NULL) END,
                CASE WHEN @MilestoneDueAt_Clear = 1 THEN NULL ELSE ISNULL(@MilestoneDueAt, NULL) END,
                CASE WHEN @AuthorLogin_Clear = 1 THEN NULL ELSE ISNULL(@AuthorLogin, NULL) END,
                CASE WHEN @BodyHash_Clear = 1 THEN NULL ELSE ISNULL(@BodyHash, NULL) END,
                CASE WHEN @GitHubUpdatedAt_Clear = 1 THEN NULL ELSE ISNULL(@GitHubUpdatedAt, NULL) END,
                CASE WHEN @LastSyncedAt_Clear = 1 THEN NULL ELSE ISNULL(@LastSyncedAt, NULL) END,
                @ActualID
        )
    -- return the new record from the base view, which might have some calculated fields
    SELECT * FROM [${flyway:defaultSchema}].[vwGitHubIssueTasks] WHERE [ID] = @ActualID
END
GO
REVOKE EXECUTE ON [${flyway:defaultSchema}].[spCreateGitHubIssueTask] FROM [cdp_Developer]
REVOKE EXECUTE ON [${flyway:defaultSchema}].[spCreateGitHubIssueTask] FROM [cdp_Integration]
GRANT EXECUTE ON [${flyway:defaultSchema}].[spCreateGitHubIssueTask] TO [cdp_Developer], [cdp_Integration];

/* spCreate Permissions for MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks */

REVOKE EXECUTE ON [${flyway:defaultSchema}].[spCreateGitHubIssueTask] FROM [cdp_Developer]
REVOKE EXECUTE ON [${flyway:defaultSchema}].[spCreateGitHubIssueTask] FROM [cdp_Integration]
GRANT EXECUTE ON [${flyway:defaultSchema}].[spCreateGitHubIssueTask] TO [cdp_Developer], [cdp_Integration];

/* spUpdate SQL for MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks */
-----------------------------------------------------------------
-- SQL Code Generation
-- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks
-- Item: spUpdateGitHubIssueTask
--
-- This was generated by the MemberJunction CodeGen tool.
-- This file should NOT be edited by hand.
-----------------------------------------------------------------

------------------------------------------------------------
----- UPDATE PROCEDURE FOR GitHubIssueTask
------------------------------------------------------------
IF OBJECT_ID('[${flyway:defaultSchema}].[spUpdateGitHubIssueTask]', 'P') IS NOT NULL
    DROP PROCEDURE [${flyway:defaultSchema}].[spUpdateGitHubIssueTask];
GO

CREATE PROCEDURE [${flyway:defaultSchema}].[spUpdateGitHubIssueTask]
    @ID uniqueidentifier,
    @RepositoryID_Clear bit = 0,
    @RepositoryID uniqueidentifier = NULL,
    @Number_Clear bit = 0,
    @Number int = NULL,
    @NodeID_Clear bit = 0,
    @NodeID nvarchar(128) = NULL,
    @HtmlURL_Clear bit = 0,
    @HtmlURL nvarchar(1000) = NULL,
    @State nvarchar(20) = NULL,
    @StateReason_Clear bit = 0,
    @StateReason nvarchar(40) = NULL,
    @Labels_Clear bit = 0,
    @Labels nvarchar(MAX) = NULL,
    @Milestone_Clear bit = 0,
    @Milestone nvarchar(255) = NULL,
    @MilestoneDueAt_Clear bit = 0,
    @MilestoneDueAt datetimeoffset = NULL,
    @AuthorLogin_Clear bit = 0,
    @AuthorLogin nvarchar(100) = NULL,
    @BodyHash_Clear bit = 0,
    @BodyHash nvarchar(64) = NULL,
    @GitHubUpdatedAt_Clear bit = 0,
    @GitHubUpdatedAt datetimeoffset = NULL,
    @LastSyncedAt_Clear bit = 0,
    @LastSyncedAt datetimeoffset = NULL
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE
        [${flyway:defaultSchema}].[GitHubIssueTask]
    SET
        [RepositoryID] = CASE WHEN @RepositoryID_Clear = 1 THEN NULL ELSE ISNULL(@RepositoryID, [RepositoryID]) END,
        [Number] = CASE WHEN @Number_Clear = 1 THEN NULL ELSE ISNULL(@Number, [Number]) END,
        [NodeID] = CASE WHEN @NodeID_Clear = 1 THEN NULL ELSE ISNULL(@NodeID, [NodeID]) END,
        [HtmlURL] = CASE WHEN @HtmlURL_Clear = 1 THEN NULL ELSE ISNULL(@HtmlURL, [HtmlURL]) END,
        [State] = ISNULL(@State, [State]),
        [StateReason] = CASE WHEN @StateReason_Clear = 1 THEN NULL ELSE ISNULL(@StateReason, [StateReason]) END,
        [Labels] = CASE WHEN @Labels_Clear = 1 THEN NULL ELSE ISNULL(@Labels, [Labels]) END,
        [Milestone] = CASE WHEN @Milestone_Clear = 1 THEN NULL ELSE ISNULL(@Milestone, [Milestone]) END,
        [MilestoneDueAt] = CASE WHEN @MilestoneDueAt_Clear = 1 THEN NULL ELSE ISNULL(@MilestoneDueAt, [MilestoneDueAt]) END,
        [AuthorLogin] = CASE WHEN @AuthorLogin_Clear = 1 THEN NULL ELSE ISNULL(@AuthorLogin, [AuthorLogin]) END,
        [BodyHash] = CASE WHEN @BodyHash_Clear = 1 THEN NULL ELSE ISNULL(@BodyHash, [BodyHash]) END,
        [GitHubUpdatedAt] = CASE WHEN @GitHubUpdatedAt_Clear = 1 THEN NULL ELSE ISNULL(@GitHubUpdatedAt, [GitHubUpdatedAt]) END,
        [LastSyncedAt] = CASE WHEN @LastSyncedAt_Clear = 1 THEN NULL ELSE ISNULL(@LastSyncedAt, [LastSyncedAt]) END
    WHERE
        [ID] = @ID

    -- Check if the update was successful
    IF @@ROWCOUNT = 0
        -- Nothing was updated, return no rows, but column structure from base view intact, semantically correct this way.
        SELECT TOP 0 * FROM [${flyway:defaultSchema}].[vwGitHubIssueTasks] WHERE 1=0
    ELSE
        -- Return the updated record so the caller can see the updated values and any calculated fields
        SELECT
                                        *
                                    FROM
                                        [${flyway:defaultSchema}].[vwGitHubIssueTasks]
                                    WHERE
                                        [ID] = @ID
                                    
END
GO

REVOKE EXECUTE ON [${flyway:defaultSchema}].[spUpdateGitHubIssueTask] FROM [cdp_Developer]
REVOKE EXECUTE ON [${flyway:defaultSchema}].[spUpdateGitHubIssueTask] FROM [cdp_Integration]
GRANT EXECUTE ON [${flyway:defaultSchema}].[spUpdateGitHubIssueTask] TO [cdp_Developer], [cdp_Integration]
GO

------------------------------------------------------------
----- TRIGGER FOR __mj_UpdatedAt field for the GitHubIssueTask table
------------------------------------------------------------
IF OBJECT_ID('[${flyway:defaultSchema}].[trgUpdateGitHubIssueTask]', 'TR') IS NOT NULL
    DROP TRIGGER [${flyway:defaultSchema}].[trgUpdateGitHubIssueTask];
GO
CREATE TRIGGER [${flyway:defaultSchema}].trgUpdateGitHubIssueTask
ON [${flyway:defaultSchema}].[GitHubIssueTask]
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE
        [${flyway:defaultSchema}].[GitHubIssueTask]
    SET
        __mj_UpdatedAt = GETUTCDATE()
    FROM
        [${flyway:defaultSchema}].[GitHubIssueTask] AS _organicTable
    INNER JOIN
        INSERTED AS I ON
        _organicTable.[ID] = I.[ID];
END;
GO

/* spUpdate Permissions for MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks */

REVOKE EXECUTE ON [${flyway:defaultSchema}].[spUpdateGitHubIssueTask] FROM [cdp_Developer]
REVOKE EXECUTE ON [${flyway:defaultSchema}].[spUpdateGitHubIssueTask] FROM [cdp_Integration]
GRANT EXECUTE ON [${flyway:defaultSchema}].[spUpdateGitHubIssueTask] TO [cdp_Developer], [cdp_Integration];

/* spDelete SQL for MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks */
-----------------------------------------------------------------
-- SQL Code Generation
-- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks
-- Item: spDeleteGitHubIssueTask
--
-- This was generated by the MemberJunction CodeGen tool.
-- This file should NOT be edited by hand.
-----------------------------------------------------------------

------------------------------------------------------------
----- DELETE PROCEDURE FOR GitHubIssueTask
------------------------------------------------------------
IF OBJECT_ID('[${flyway:defaultSchema}].[spDeleteGitHubIssueTask]', 'P') IS NOT NULL
    DROP PROCEDURE [${flyway:defaultSchema}].[spDeleteGitHubIssueTask];
GO

CREATE PROCEDURE [${flyway:defaultSchema}].[spDeleteGitHubIssueTask]
    @ID uniqueidentifier
AS
BEGIN
    SET NOCOUNT ON;

    DELETE FROM
        [${flyway:defaultSchema}].[GitHubIssueTask]
    WHERE
        [ID] = @ID


    -- Check if the delete was successful
    IF @@ROWCOUNT = 0
        SELECT NULL AS [ID] -- Return NULL for all primary key fields to indicate no record was deleted
    ELSE
        SELECT @ID AS [ID] -- Return the primary key values to indicate we successfully deleted the record
END
GO
REVOKE EXECUTE ON [${flyway:defaultSchema}].[spDeleteGitHubIssueTask] FROM [cdp_Developer]
REVOKE EXECUTE ON [${flyway:defaultSchema}].[spDeleteGitHubIssueTask] FROM [cdp_Integration]
GRANT EXECUTE ON [${flyway:defaultSchema}].[spDeleteGitHubIssueTask] TO [cdp_Developer], [cdp_Integration];

/* spDelete Permissions for MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks */

REVOKE EXECUTE ON [${flyway:defaultSchema}].[spDeleteGitHubIssueTask] FROM [cdp_Developer]
REVOKE EXECUTE ON [${flyway:defaultSchema}].[spDeleteGitHubIssueTask] FROM [cdp_Integration]
GRANT EXECUTE ON [${flyway:defaultSchema}].[spDeleteGitHubIssueTask] TO [cdp_Developer], [cdp_Integration];


/* SQL text to insert 68 new entity field(s) */

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '5f177501-4505-4dfe-9813-9b930dfe80c5' OR (EntityID = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605' AND Name = 'Name')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '5f177501-4505-4dfe-9813-9b930dfe80c5',
            'DC8E0F5B-E172-4FD5-B648-8B4544F8C605', -- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks
            (SELECT COALESCE(MAX([Sequence]), 0) + 1 FROM [${mjSchema}].[EntityField] WHERE [EntityID] = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605'),
            'Name',
            'Name',
            NULL,
            'nvarchar',
            510,
            0,
            0,
            0,
            NULL,
            0,
            0,
            1,
            0,
            NULL,
            NULL,
            1,
            1,
            0,
            1,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = 'abc08616-bc3e-441f-8e7d-a4274959c326' OR (EntityID = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605' AND Name = 'Description')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            'abc08616-bc3e-441f-8e7d-a4274959c326',
            'DC8E0F5B-E172-4FD5-B648-8B4544F8C605', -- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks
            (SELECT COALESCE(MAX([Sequence]), 0) + 1 FROM [${mjSchema}].[EntityField] WHERE [EntityID] = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605'),
            'Description',
            'Description',
            NULL,
            'nvarchar',
            -1,
            0,
            0,
            1,
            NULL,
            0,
            0,
            1,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '104159ff-db47-414c-a573-22218c8e246e' OR (EntityID = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605' AND Name = 'TypeID')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '104159ff-db47-414c-a573-22218c8e246e',
            'DC8E0F5B-E172-4FD5-B648-8B4544F8C605', -- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks
            (SELECT COALESCE(MAX([Sequence]), 0) + 1 FROM [${mjSchema}].[EntityField] WHERE [EntityID] = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605'),
            'TypeID',
            'Type ID',
            NULL,
            'uniqueidentifier',
            16,
            0,
            0,
            0,
            NULL,
            0,
            0,
            1,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = 'bee37b1e-65c9-4b3b-8e1e-52307578d3f3' OR (EntityID = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605' AND Name = 'CategoryID')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            'bee37b1e-65c9-4b3b-8e1e-52307578d3f3',
            'DC8E0F5B-E172-4FD5-B648-8B4544F8C605', -- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks
            (SELECT COALESCE(MAX([Sequence]), 0) + 1 FROM [${mjSchema}].[EntityField] WHERE [EntityID] = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605'),
            'CategoryID',
            'Category ID',
            NULL,
            'uniqueidentifier',
            16,
            0,
            0,
            1,
            NULL,
            0,
            0,
            1,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = 'b3889303-f49f-4d92-853f-65ac124f359d' OR (EntityID = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605' AND Name = 'ParentID')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            'b3889303-f49f-4d92-853f-65ac124f359d',
            'DC8E0F5B-E172-4FD5-B648-8B4544F8C605', -- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks
            (SELECT COALESCE(MAX([Sequence]), 0) + 1 FROM [${mjSchema}].[EntityField] WHERE [EntityID] = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605'),
            'ParentID',
            'Parent ID',
            NULL,
            'uniqueidentifier',
            16,
            0,
            0,
            1,
            NULL,
            0,
            0,
            1,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = 'a65eda96-67f2-4c99-b96c-65388a906aac' OR (EntityID = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605' AND Name = 'Status')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            'a65eda96-67f2-4c99-b96c-65388a906aac',
            'DC8E0F5B-E172-4FD5-B648-8B4544F8C605', -- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks
            (SELECT COALESCE(MAX([Sequence]), 0) + 1 FROM [${mjSchema}].[EntityField] WHERE [EntityID] = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605'),
            'Status',
            'Status',
            NULL,
            'nvarchar',
            100,
            0,
            0,
            0,
            NULL,
            0,
            0,
            1,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = 'd70abd8c-2ac1-44e1-aea2-945d6daa9ed7' OR (EntityID = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605' AND Name = 'Priority')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            'd70abd8c-2ac1-44e1-aea2-945d6daa9ed7',
            'DC8E0F5B-E172-4FD5-B648-8B4544F8C605', -- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks
            (SELECT COALESCE(MAX([Sequence]), 0) + 1 FROM [${mjSchema}].[EntityField] WHERE [EntityID] = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605'),
            'Priority',
            'Priority',
            NULL,
            'nvarchar',
            40,
            0,
            0,
            0,
            NULL,
            0,
            0,
            1,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = 'e28af650-ab4a-45bb-a94d-814467a2536d' OR (EntityID = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605' AND Name = 'StartedAt')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            'e28af650-ab4a-45bb-a94d-814467a2536d',
            'DC8E0F5B-E172-4FD5-B648-8B4544F8C605', -- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks
            (SELECT COALESCE(MAX([Sequence]), 0) + 1 FROM [${mjSchema}].[EntityField] WHERE [EntityID] = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605'),
            'StartedAt',
            'Started At',
            NULL,
            'datetimeoffset',
            10,
            34,
            7,
            1,
            NULL,
            0,
            0,
            1,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = 'b83a675f-795c-47ed-81f4-cbbd5ff4d929' OR (EntityID = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605' AND Name = 'DueAt')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            'b83a675f-795c-47ed-81f4-cbbd5ff4d929',
            'DC8E0F5B-E172-4FD5-B648-8B4544F8C605', -- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks
            (SELECT COALESCE(MAX([Sequence]), 0) + 1 FROM [${mjSchema}].[EntityField] WHERE [EntityID] = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605'),
            'DueAt',
            'Due At',
            NULL,
            'datetimeoffset',
            10,
            34,
            7,
            1,
            NULL,
            0,
            0,
            1,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = 'cef54e7e-100c-432e-9d83-fe29b47c5f73' OR (EntityID = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605' AND Name = 'CompletedAt')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            'cef54e7e-100c-432e-9d83-fe29b47c5f73',
            'DC8E0F5B-E172-4FD5-B648-8B4544F8C605', -- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks
            (SELECT COALESCE(MAX([Sequence]), 0) + 1 FROM [${mjSchema}].[EntityField] WHERE [EntityID] = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605'),
            'CompletedAt',
            'Completed At',
            NULL,
            'datetimeoffset',
            10,
            34,
            7,
            1,
            NULL,
            0,
            0,
            1,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = 'c9363ae8-2c58-46c5-b437-c7d26a02c353' OR (EntityID = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605' AND Name = 'HoursEstimated')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            'c9363ae8-2c58-46c5-b437-c7d26a02c353',
            'DC8E0F5B-E172-4FD5-B648-8B4544F8C605', -- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks
            (SELECT COALESCE(MAX([Sequence]), 0) + 1 FROM [${mjSchema}].[EntityField] WHERE [EntityID] = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605'),
            'HoursEstimated',
            'Hours Estimated',
            NULL,
            'decimal',
            5,
            8,
            2,
            1,
            NULL,
            0,
            0,
            1,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '3f2f697f-56e2-450f-bf03-77dc470d5754' OR (EntityID = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605' AND Name = 'HoursActual')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '3f2f697f-56e2-450f-bf03-77dc470d5754',
            'DC8E0F5B-E172-4FD5-B648-8B4544F8C605', -- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks
            (SELECT COALESCE(MAX([Sequence]), 0) + 1 FROM [${mjSchema}].[EntityField] WHERE [EntityID] = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605'),
            'HoursActual',
            'Hours Actual',
            NULL,
            'decimal',
            5,
            8,
            2,
            1,
            NULL,
            0,
            0,
            1,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '732fa3a2-4e55-44c0-9f6b-fe50b894c27e' OR (EntityID = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605' AND Name = 'PercentComplete')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '732fa3a2-4e55-44c0-9f6b-fe50b894c27e',
            'DC8E0F5B-E172-4FD5-B648-8B4544F8C605', -- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks
            (SELECT COALESCE(MAX([Sequence]), 0) + 1 FROM [${mjSchema}].[EntityField] WHERE [EntityID] = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605'),
            'PercentComplete',
            'Percent Complete',
            NULL,
            'int',
            4,
            10,
            0,
            0,
            NULL,
            0,
            0,
            1,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '77ec9524-1745-4341-b0fd-ebe74e176e4a' OR (EntityID = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605' AND Name = 'Sequence')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '77ec9524-1745-4341-b0fd-ebe74e176e4a',
            'DC8E0F5B-E172-4FD5-B648-8B4544F8C605', -- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks
            (SELECT COALESCE(MAX([Sequence]), 0) + 1 FROM [${mjSchema}].[EntityField] WHERE [EntityID] = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605'),
            'Sequence',
            'Sequence',
            NULL,
            'int',
            4,
            10,
            0,
            0,
            NULL,
            0,
            0,
            1,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = 'eaf33611-eb3d-4621-bc57-292f137e43c4' OR (EntityID = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605' AND Name = 'BlockedReason')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            'eaf33611-eb3d-4621-bc57-292f137e43c4',
            'DC8E0F5B-E172-4FD5-B648-8B4544F8C605', -- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks
            (SELECT COALESCE(MAX([Sequence]), 0) + 1 FROM [${mjSchema}].[EntityField] WHERE [EntityID] = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605'),
            'BlockedReason',
            'Blocked Reason',
            NULL,
            'nvarchar',
            -1,
            0,
            0,
            1,
            NULL,
            0,
            0,
            1,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = 'e856766e-55a2-4de8-990e-86d7d1e7056a' OR (EntityID = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605' AND Name = 'CompletionNotes')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            'e856766e-55a2-4de8-990e-86d7d1e7056a',
            'DC8E0F5B-E172-4FD5-B648-8B4544F8C605', -- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks
            (SELECT COALESCE(MAX([Sequence]), 0) + 1 FROM [${mjSchema}].[EntityField] WHERE [EntityID] = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605'),
            'CompletionNotes',
            'Completion Notes',
            NULL,
            'nvarchar',
            -1,
            0,
            0,
            1,
            NULL,
            0,
            0,
            1,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '6199ac88-26d6-4320-8b59-952c0e1945ea' OR (EntityID = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605' AND Name = 'CreatedByPersonID')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '6199ac88-26d6-4320-8b59-952c0e1945ea',
            'DC8E0F5B-E172-4FD5-B648-8B4544F8C605', -- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks
            (SELECT COALESCE(MAX([Sequence]), 0) + 1 FROM [${mjSchema}].[EntityField] WHERE [EntityID] = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605'),
            'CreatedByPersonID',
            'Created By Person ID',
            NULL,
            'uniqueidentifier',
            16,
            0,
            0,
            1,
            NULL,
            0,
            0,
            1,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = 'ce26b855-64ac-45b7-9549-39ac48fa7fa8' OR (EntityID = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605' AND Name = 'OverdueNotifiedAt')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            'ce26b855-64ac-45b7-9549-39ac48fa7fa8',
            'DC8E0F5B-E172-4FD5-B648-8B4544F8C605', -- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks
            (SELECT COALESCE(MAX([Sequence]), 0) + 1 FROM [${mjSchema}].[EntityField] WHERE [EntityID] = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605'),
            'OverdueNotifiedAt',
            'Overdue Notified At',
            NULL,
            'datetimeoffset',
            10,
            34,
            7,
            1,
            NULL,
            0,
            0,
            1,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = 'f0abfe53-246f-41d8-b25a-e462fc412615' OR (EntityID = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605' AND Name = 'TaskTypeStatusID')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            'f0abfe53-246f-41d8-b25a-e462fc412615',
            'DC8E0F5B-E172-4FD5-B648-8B4544F8C605', -- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks
            (SELECT COALESCE(MAX([Sequence]), 0) + 1 FROM [${mjSchema}].[EntityField] WHERE [EntityID] = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605'),
            'TaskTypeStatusID',
            'Task Type Status ID',
            NULL,
            'uniqueidentifier',
            16,
            0,
            0,
            1,
            NULL,
            0,
            0,
            1,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = 'd1ab1a5c-a1ee-4ec5-95fe-4fd4c8ab7630' OR (EntityID = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605' AND Name = 'PredictedSLABreachProbability')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            'd1ab1a5c-a1ee-4ec5-95fe-4fd4c8ab7630',
            'DC8E0F5B-E172-4FD5-B648-8B4544F8C605', -- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks
            (SELECT COALESCE(MAX([Sequence]), 0) + 1 FROM [${mjSchema}].[EntityField] WHERE [EntityID] = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605'),
            'PredictedSLABreachProbability',
            'Predicted SLA Breach Probability',
            NULL,
            'decimal',
            5,
            5,
            4,
            1,
            NULL,
            0,
            0,
            1,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = 'd2574ddb-325f-473d-997a-66cc43309934' OR (EntityID = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605' AND Name = 'PredictedSLARiskBand')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            'd2574ddb-325f-473d-997a-66cc43309934',
            'DC8E0F5B-E172-4FD5-B648-8B4544F8C605', -- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks
            (SELECT COALESCE(MAX([Sequence]), 0) + 1 FROM [${mjSchema}].[EntityField] WHERE [EntityID] = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605'),
            'PredictedSLARiskBand',
            'Predicted SLA Risk Band',
            NULL,
            'nvarchar',
            40,
            0,
            0,
            1,
            NULL,
            0,
            0,
            1,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '947c6bae-94d3-4999-ac0f-dafe404e008f' OR (EntityID = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605' AND Name = 'PredictedSLAScoredAt')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '947c6bae-94d3-4999-ac0f-dafe404e008f',
            'DC8E0F5B-E172-4FD5-B648-8B4544F8C605', -- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks
            (SELECT COALESCE(MAX([Sequence]), 0) + 1 FROM [${mjSchema}].[EntityField] WHERE [EntityID] = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605'),
            'PredictedSLAScoredAt',
            'Predicted SLA Scored At',
            NULL,
            'datetimeoffset',
            10,
            34,
            7,
            1,
            NULL,
            0,
            0,
            1,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '8efe7eac-45db-4b89-9221-2b19b99068b9' OR (EntityID = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605' AND Name = 'HealthStatus')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '8efe7eac-45db-4b89-9221-2b19b99068b9',
            'DC8E0F5B-E172-4FD5-B648-8B4544F8C605', -- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks
            (SELECT COALESCE(MAX([Sequence]), 0) + 1 FROM [${mjSchema}].[EntityField] WHERE [EntityID] = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605'),
            'HealthStatus',
            'Health Status',
            NULL,
            'nvarchar',
            40,
            0,
            0,
            1,
            NULL,
            0,
            0,
            1,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = 'ea927e59-ffd9-4f5c-91bc-db57a268cb3f' OR (EntityID = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605' AND Name = 'ConfidenceScore')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            'ea927e59-ffd9-4f5c-91bc-db57a268cb3f',
            'DC8E0F5B-E172-4FD5-B648-8B4544F8C605', -- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks
            (SELECT COALESCE(MAX([Sequence]), 0) + 1 FROM [${mjSchema}].[EntityField] WHERE [EntityID] = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605'),
            'ConfidenceScore',
            'Confidence Score',
            NULL,
            'int',
            4,
            10,
            0,
            1,
            NULL,
            0,
            0,
            1,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '835e5643-810d-4b4e-8e83-e9595428437c' OR (EntityID = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605' AND Name = 'BaselineValue')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '835e5643-810d-4b4e-8e83-e9595428437c',
            'DC8E0F5B-E172-4FD5-B648-8B4544F8C605', -- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks
            (SELECT COALESCE(MAX([Sequence]), 0) + 1 FROM [${mjSchema}].[EntityField] WHERE [EntityID] = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605'),
            'BaselineValue',
            'Baseline Value',
            NULL,
            'decimal',
            9,
            18,
            4,
            1,
            NULL,
            0,
            0,
            1,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '77dd9516-90ef-4855-9cf7-ca0d81b59a8f' OR (EntityID = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605' AND Name = 'TargetValue')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '77dd9516-90ef-4855-9cf7-ca0d81b59a8f',
            'DC8E0F5B-E172-4FD5-B648-8B4544F8C605', -- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks
            (SELECT COALESCE(MAX([Sequence]), 0) + 1 FROM [${mjSchema}].[EntityField] WHERE [EntityID] = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605'),
            'TargetValue',
            'Target Value',
            NULL,
            'decimal',
            9,
            18,
            4,
            1,
            NULL,
            0,
            0,
            1,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = 'af810be2-ba61-46dd-adec-7f3fe7fb35e2' OR (EntityID = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605' AND Name = 'CurrentValue')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            'af810be2-ba61-46dd-adec-7f3fe7fb35e2',
            'DC8E0F5B-E172-4FD5-B648-8B4544F8C605', -- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks
            (SELECT COALESCE(MAX([Sequence]), 0) + 1 FROM [${mjSchema}].[EntityField] WHERE [EntityID] = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605'),
            'CurrentValue',
            'Current Value',
            NULL,
            'decimal',
            9,
            18,
            4,
            1,
            NULL,
            0,
            0,
            1,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = 'fd6fa1e2-da35-409a-9116-36640d818333' OR (EntityID = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605' AND Name = 'UnitOfMeasure')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            'fd6fa1e2-da35-409a-9116-36640d818333',
            'DC8E0F5B-E172-4FD5-B648-8B4544F8C605', -- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks
            (SELECT COALESCE(MAX([Sequence]), 0) + 1 FROM [${mjSchema}].[EntityField] WHERE [EntityID] = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605'),
            'UnitOfMeasure',
            'Unit Of Measure',
            NULL,
            'nvarchar',
            100,
            0,
            0,
            1,
            NULL,
            0,
            0,
            1,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '86b721d5-8aa2-4199-aef7-c933a6ba52ff' OR (EntityID = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605' AND Name = 'MetricDirection')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '86b721d5-8aa2-4199-aef7-c933a6ba52ff',
            'DC8E0F5B-E172-4FD5-B648-8B4544F8C605', -- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks
            (SELECT COALESCE(MAX([Sequence]), 0) + 1 FROM [${mjSchema}].[EntityField] WHERE [EntityID] = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605'),
            'MetricDirection',
            'Metric Direction',
            NULL,
            'nvarchar',
            40,
            0,
            0,
            1,
            NULL,
            0,
            0,
            1,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '03f75dad-73a6-4c9c-b473-50af0f4dfdbf' OR (EntityID = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605' AND Name = 'RollupWeight')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '03f75dad-73a6-4c9c-b473-50af0f4dfdbf',
            'DC8E0F5B-E172-4FD5-B648-8B4544F8C605', -- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks
            (SELECT COALESCE(MAX([Sequence]), 0) + 1 FROM [${mjSchema}].[EntityField] WHERE [EntityID] = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605'),
            'RollupWeight',
            'Rollup Weight',
            NULL,
            'decimal',
            5,
            8,
            2,
            0,
            NULL,
            0,
            0,
            1,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = 'e4a34b92-d140-405d-9ab7-1003eded8be8' OR (EntityID = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605' AND Name = 'PlanningPeriod')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            'e4a34b92-d140-405d-9ab7-1003eded8be8',
            'DC8E0F5B-E172-4FD5-B648-8B4544F8C605', -- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks
            (SELECT COALESCE(MAX([Sequence]), 0) + 1 FROM [${mjSchema}].[EntityField] WHERE [EntityID] = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605'),
            'PlanningPeriod',
            'Planning Period',
            NULL,
            'nvarchar',
            100,
            0,
            0,
            1,
            NULL,
            0,
            0,
            1,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = 'c652b089-04bd-4a3e-bbad-07d5d2474568' OR (EntityID = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605' AND Name = 'CheckInCadence')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            'c652b089-04bd-4a3e-bbad-07d5d2474568',
            'DC8E0F5B-E172-4FD5-B648-8B4544F8C605', -- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks
            (SELECT COALESCE(MAX([Sequence]), 0) + 1 FROM [${mjSchema}].[EntityField] WHERE [EntityID] = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605'),
            'CheckInCadence',
            'Check In Cadence',
            NULL,
            'nvarchar',
            40,
            0,
            0,
            1,
            NULL,
            0,
            0,
            1,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '6fe24c88-2e9c-49e9-afd2-4e0d428f7c50' OR (EntityID = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605' AND Name = 'LastCheckInAt')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '6fe24c88-2e9c-49e9-afd2-4e0d428f7c50',
            'DC8E0F5B-E172-4FD5-B648-8B4544F8C605', -- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks
            (SELECT COALESCE(MAX([Sequence]), 0) + 1 FROM [${mjSchema}].[EntityField] WHERE [EntityID] = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605'),
            'LastCheckInAt',
            'Last Check In At',
            NULL,
            'datetimeoffset',
            10,
            34,
            7,
            1,
            NULL,
            0,
            0,
            1,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = 'c4aa4959-c523-450d-95c7-f7c4119f6211' OR (EntityID = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605' AND Name = 'NextCheckInDueAt')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            'c4aa4959-c523-450d-95c7-f7c4119f6211',
            'DC8E0F5B-E172-4FD5-B648-8B4544F8C605', -- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks
            (SELECT COALESCE(MAX([Sequence]), 0) + 1 FROM [${mjSchema}].[EntityField] WHERE [EntityID] = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605'),
            'NextCheckInDueAt',
            'Next Check In Due At',
            NULL,
            'datetimeoffset',
            10,
            34,
            7,
            1,
            NULL,
            0,
            0,
            1,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '4ba1a1f6-223e-4e8d-99d0-16448913d993' OR (EntityID = 'A6B673F8-43BC-4875-AFF6-AC620592822E' AND Name = 'Name')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '4ba1a1f6-223e-4e8d-99d0-16448913d993',
            'A6B673F8-43BC-4875-AFF6-AC620592822E', -- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks
            (SELECT COALESCE(MAX([Sequence]), 0) + 1 FROM [${mjSchema}].[EntityField] WHERE [EntityID] = 'A6B673F8-43BC-4875-AFF6-AC620592822E'),
            'Name',
            'Name',
            NULL,
            'nvarchar',
            510,
            0,
            0,
            0,
            NULL,
            0,
            0,
            1,
            0,
            NULL,
            NULL,
            1,
            1,
            0,
            1,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '504ce539-0cc4-47d3-ad5d-120907a421ed' OR (EntityID = 'A6B673F8-43BC-4875-AFF6-AC620592822E' AND Name = 'Description')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '504ce539-0cc4-47d3-ad5d-120907a421ed',
            'A6B673F8-43BC-4875-AFF6-AC620592822E', -- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks
            (SELECT COALESCE(MAX([Sequence]), 0) + 1 FROM [${mjSchema}].[EntityField] WHERE [EntityID] = 'A6B673F8-43BC-4875-AFF6-AC620592822E'),
            'Description',
            'Description',
            NULL,
            'nvarchar',
            -1,
            0,
            0,
            1,
            NULL,
            0,
            0,
            1,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = 'a26a18fa-8f34-423e-ac94-3f3b47ac87c9' OR (EntityID = 'A6B673F8-43BC-4875-AFF6-AC620592822E' AND Name = 'TypeID')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            'a26a18fa-8f34-423e-ac94-3f3b47ac87c9',
            'A6B673F8-43BC-4875-AFF6-AC620592822E', -- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks
            (SELECT COALESCE(MAX([Sequence]), 0) + 1 FROM [${mjSchema}].[EntityField] WHERE [EntityID] = 'A6B673F8-43BC-4875-AFF6-AC620592822E'),
            'TypeID',
            'Type ID',
            NULL,
            'uniqueidentifier',
            16,
            0,
            0,
            0,
            NULL,
            0,
            0,
            1,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '2f5e2d1c-f10a-42f0-9ad0-71956d6ed9c5' OR (EntityID = 'A6B673F8-43BC-4875-AFF6-AC620592822E' AND Name = 'CategoryID')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '2f5e2d1c-f10a-42f0-9ad0-71956d6ed9c5',
            'A6B673F8-43BC-4875-AFF6-AC620592822E', -- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks
            (SELECT COALESCE(MAX([Sequence]), 0) + 1 FROM [${mjSchema}].[EntityField] WHERE [EntityID] = 'A6B673F8-43BC-4875-AFF6-AC620592822E'),
            'CategoryID',
            'Category ID',
            NULL,
            'uniqueidentifier',
            16,
            0,
            0,
            1,
            NULL,
            0,
            0,
            1,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '8a12d74a-f61c-4669-ab9a-f83fd4418679' OR (EntityID = 'A6B673F8-43BC-4875-AFF6-AC620592822E' AND Name = 'ParentID')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '8a12d74a-f61c-4669-ab9a-f83fd4418679',
            'A6B673F8-43BC-4875-AFF6-AC620592822E', -- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks
            (SELECT COALESCE(MAX([Sequence]), 0) + 1 FROM [${mjSchema}].[EntityField] WHERE [EntityID] = 'A6B673F8-43BC-4875-AFF6-AC620592822E'),
            'ParentID',
            'Parent ID',
            NULL,
            'uniqueidentifier',
            16,
            0,
            0,
            1,
            NULL,
            0,
            0,
            1,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = 'ccae381c-911d-407d-ba0b-05bdb95cabfb' OR (EntityID = 'A6B673F8-43BC-4875-AFF6-AC620592822E' AND Name = 'Status')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            'ccae381c-911d-407d-ba0b-05bdb95cabfb',
            'A6B673F8-43BC-4875-AFF6-AC620592822E', -- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks
            (SELECT COALESCE(MAX([Sequence]), 0) + 1 FROM [${mjSchema}].[EntityField] WHERE [EntityID] = 'A6B673F8-43BC-4875-AFF6-AC620592822E'),
            'Status',
            'Status',
            NULL,
            'nvarchar',
            100,
            0,
            0,
            0,
            NULL,
            0,
            0,
            1,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '10503f3a-eaad-4efa-aa23-ed42af9335f2' OR (EntityID = 'A6B673F8-43BC-4875-AFF6-AC620592822E' AND Name = 'Priority')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '10503f3a-eaad-4efa-aa23-ed42af9335f2',
            'A6B673F8-43BC-4875-AFF6-AC620592822E', -- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks
            (SELECT COALESCE(MAX([Sequence]), 0) + 1 FROM [${mjSchema}].[EntityField] WHERE [EntityID] = 'A6B673F8-43BC-4875-AFF6-AC620592822E'),
            'Priority',
            'Priority',
            NULL,
            'nvarchar',
            40,
            0,
            0,
            0,
            NULL,
            0,
            0,
            1,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = 'cfd64243-ad98-4583-9393-e2a86aa869fe' OR (EntityID = 'A6B673F8-43BC-4875-AFF6-AC620592822E' AND Name = 'StartedAt')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            'cfd64243-ad98-4583-9393-e2a86aa869fe',
            'A6B673F8-43BC-4875-AFF6-AC620592822E', -- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks
            (SELECT COALESCE(MAX([Sequence]), 0) + 1 FROM [${mjSchema}].[EntityField] WHERE [EntityID] = 'A6B673F8-43BC-4875-AFF6-AC620592822E'),
            'StartedAt',
            'Started At',
            NULL,
            'datetimeoffset',
            10,
            34,
            7,
            1,
            NULL,
            0,
            0,
            1,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = 'd6a809c0-b643-4045-bbbc-43420e9c4d9d' OR (EntityID = 'A6B673F8-43BC-4875-AFF6-AC620592822E' AND Name = 'DueAt')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            'd6a809c0-b643-4045-bbbc-43420e9c4d9d',
            'A6B673F8-43BC-4875-AFF6-AC620592822E', -- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks
            (SELECT COALESCE(MAX([Sequence]), 0) + 1 FROM [${mjSchema}].[EntityField] WHERE [EntityID] = 'A6B673F8-43BC-4875-AFF6-AC620592822E'),
            'DueAt',
            'Due At',
            NULL,
            'datetimeoffset',
            10,
            34,
            7,
            1,
            NULL,
            0,
            0,
            1,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = 'aeb061c9-c5b7-429c-bbfb-bfe7f0b9b8db' OR (EntityID = 'A6B673F8-43BC-4875-AFF6-AC620592822E' AND Name = 'CompletedAt')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            'aeb061c9-c5b7-429c-bbfb-bfe7f0b9b8db',
            'A6B673F8-43BC-4875-AFF6-AC620592822E', -- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks
            (SELECT COALESCE(MAX([Sequence]), 0) + 1 FROM [${mjSchema}].[EntityField] WHERE [EntityID] = 'A6B673F8-43BC-4875-AFF6-AC620592822E'),
            'CompletedAt',
            'Completed At',
            NULL,
            'datetimeoffset',
            10,
            34,
            7,
            1,
            NULL,
            0,
            0,
            1,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '05869a56-0e75-4721-8fdf-4969df401c85' OR (EntityID = 'A6B673F8-43BC-4875-AFF6-AC620592822E' AND Name = 'HoursEstimated')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '05869a56-0e75-4721-8fdf-4969df401c85',
            'A6B673F8-43BC-4875-AFF6-AC620592822E', -- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks
            (SELECT COALESCE(MAX([Sequence]), 0) + 1 FROM [${mjSchema}].[EntityField] WHERE [EntityID] = 'A6B673F8-43BC-4875-AFF6-AC620592822E'),
            'HoursEstimated',
            'Hours Estimated',
            NULL,
            'decimal',
            5,
            8,
            2,
            1,
            NULL,
            0,
            0,
            1,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '5025c924-87bc-4045-b5b2-af280b8bf9d5' OR (EntityID = 'A6B673F8-43BC-4875-AFF6-AC620592822E' AND Name = 'HoursActual')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '5025c924-87bc-4045-b5b2-af280b8bf9d5',
            'A6B673F8-43BC-4875-AFF6-AC620592822E', -- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks
            (SELECT COALESCE(MAX([Sequence]), 0) + 1 FROM [${mjSchema}].[EntityField] WHERE [EntityID] = 'A6B673F8-43BC-4875-AFF6-AC620592822E'),
            'HoursActual',
            'Hours Actual',
            NULL,
            'decimal',
            5,
            8,
            2,
            1,
            NULL,
            0,
            0,
            1,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = 'c0c67a45-f9f6-4962-a5dc-2176f8ef1f0a' OR (EntityID = 'A6B673F8-43BC-4875-AFF6-AC620592822E' AND Name = 'PercentComplete')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            'c0c67a45-f9f6-4962-a5dc-2176f8ef1f0a',
            'A6B673F8-43BC-4875-AFF6-AC620592822E', -- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks
            (SELECT COALESCE(MAX([Sequence]), 0) + 1 FROM [${mjSchema}].[EntityField] WHERE [EntityID] = 'A6B673F8-43BC-4875-AFF6-AC620592822E'),
            'PercentComplete',
            'Percent Complete',
            NULL,
            'int',
            4,
            10,
            0,
            0,
            NULL,
            0,
            0,
            1,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = 'c1d1eb47-d5af-42b7-926e-38440e14b0b0' OR (EntityID = 'A6B673F8-43BC-4875-AFF6-AC620592822E' AND Name = 'Sequence')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            'c1d1eb47-d5af-42b7-926e-38440e14b0b0',
            'A6B673F8-43BC-4875-AFF6-AC620592822E', -- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks
            (SELECT COALESCE(MAX([Sequence]), 0) + 1 FROM [${mjSchema}].[EntityField] WHERE [EntityID] = 'A6B673F8-43BC-4875-AFF6-AC620592822E'),
            'Sequence',
            'Sequence',
            NULL,
            'int',
            4,
            10,
            0,
            0,
            NULL,
            0,
            0,
            1,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '3365149d-db81-4d9d-bb29-2d491c6e86fa' OR (EntityID = 'A6B673F8-43BC-4875-AFF6-AC620592822E' AND Name = 'BlockedReason')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '3365149d-db81-4d9d-bb29-2d491c6e86fa',
            'A6B673F8-43BC-4875-AFF6-AC620592822E', -- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks
            (SELECT COALESCE(MAX([Sequence]), 0) + 1 FROM [${mjSchema}].[EntityField] WHERE [EntityID] = 'A6B673F8-43BC-4875-AFF6-AC620592822E'),
            'BlockedReason',
            'Blocked Reason',
            NULL,
            'nvarchar',
            -1,
            0,
            0,
            1,
            NULL,
            0,
            0,
            1,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '61b50ead-8c53-4c9f-96aa-76ecdedae434' OR (EntityID = 'A6B673F8-43BC-4875-AFF6-AC620592822E' AND Name = 'CompletionNotes')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '61b50ead-8c53-4c9f-96aa-76ecdedae434',
            'A6B673F8-43BC-4875-AFF6-AC620592822E', -- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks
            (SELECT COALESCE(MAX([Sequence]), 0) + 1 FROM [${mjSchema}].[EntityField] WHERE [EntityID] = 'A6B673F8-43BC-4875-AFF6-AC620592822E'),
            'CompletionNotes',
            'Completion Notes',
            NULL,
            'nvarchar',
            -1,
            0,
            0,
            1,
            NULL,
            0,
            0,
            1,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = 'fb407166-23f9-4bb3-98fb-599f619bb218' OR (EntityID = 'A6B673F8-43BC-4875-AFF6-AC620592822E' AND Name = 'CreatedByPersonID')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            'fb407166-23f9-4bb3-98fb-599f619bb218',
            'A6B673F8-43BC-4875-AFF6-AC620592822E', -- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks
            (SELECT COALESCE(MAX([Sequence]), 0) + 1 FROM [${mjSchema}].[EntityField] WHERE [EntityID] = 'A6B673F8-43BC-4875-AFF6-AC620592822E'),
            'CreatedByPersonID',
            'Created By Person ID',
            NULL,
            'uniqueidentifier',
            16,
            0,
            0,
            1,
            NULL,
            0,
            0,
            1,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '23302eb0-8c39-40d4-b309-faf86854aee2' OR (EntityID = 'A6B673F8-43BC-4875-AFF6-AC620592822E' AND Name = 'OverdueNotifiedAt')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '23302eb0-8c39-40d4-b309-faf86854aee2',
            'A6B673F8-43BC-4875-AFF6-AC620592822E', -- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks
            (SELECT COALESCE(MAX([Sequence]), 0) + 1 FROM [${mjSchema}].[EntityField] WHERE [EntityID] = 'A6B673F8-43BC-4875-AFF6-AC620592822E'),
            'OverdueNotifiedAt',
            'Overdue Notified At',
            NULL,
            'datetimeoffset',
            10,
            34,
            7,
            1,
            NULL,
            0,
            0,
            1,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '84a6f1cb-4453-4651-b20f-58f0a29789c8' OR (EntityID = 'A6B673F8-43BC-4875-AFF6-AC620592822E' AND Name = 'TaskTypeStatusID')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '84a6f1cb-4453-4651-b20f-58f0a29789c8',
            'A6B673F8-43BC-4875-AFF6-AC620592822E', -- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks
            (SELECT COALESCE(MAX([Sequence]), 0) + 1 FROM [${mjSchema}].[EntityField] WHERE [EntityID] = 'A6B673F8-43BC-4875-AFF6-AC620592822E'),
            'TaskTypeStatusID',
            'Task Type Status ID',
            NULL,
            'uniqueidentifier',
            16,
            0,
            0,
            1,
            NULL,
            0,
            0,
            1,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '9aaf8300-10b1-4c0c-8a05-ce90f22c22e4' OR (EntityID = 'A6B673F8-43BC-4875-AFF6-AC620592822E' AND Name = 'PredictedSLABreachProbability')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '9aaf8300-10b1-4c0c-8a05-ce90f22c22e4',
            'A6B673F8-43BC-4875-AFF6-AC620592822E', -- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks
            (SELECT COALESCE(MAX([Sequence]), 0) + 1 FROM [${mjSchema}].[EntityField] WHERE [EntityID] = 'A6B673F8-43BC-4875-AFF6-AC620592822E'),
            'PredictedSLABreachProbability',
            'Predicted SLA Breach Probability',
            NULL,
            'decimal',
            5,
            5,
            4,
            1,
            NULL,
            0,
            0,
            1,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '95d95cdc-aece-417e-a7eb-bb87a0197a3e' OR (EntityID = 'A6B673F8-43BC-4875-AFF6-AC620592822E' AND Name = 'PredictedSLARiskBand')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '95d95cdc-aece-417e-a7eb-bb87a0197a3e',
            'A6B673F8-43BC-4875-AFF6-AC620592822E', -- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks
            (SELECT COALESCE(MAX([Sequence]), 0) + 1 FROM [${mjSchema}].[EntityField] WHERE [EntityID] = 'A6B673F8-43BC-4875-AFF6-AC620592822E'),
            'PredictedSLARiskBand',
            'Predicted SLA Risk Band',
            NULL,
            'nvarchar',
            40,
            0,
            0,
            1,
            NULL,
            0,
            0,
            1,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '6ebf3400-38a4-4ce7-a1e8-76dfbb328821' OR (EntityID = 'A6B673F8-43BC-4875-AFF6-AC620592822E' AND Name = 'PredictedSLAScoredAt')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '6ebf3400-38a4-4ce7-a1e8-76dfbb328821',
            'A6B673F8-43BC-4875-AFF6-AC620592822E', -- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks
            (SELECT COALESCE(MAX([Sequence]), 0) + 1 FROM [${mjSchema}].[EntityField] WHERE [EntityID] = 'A6B673F8-43BC-4875-AFF6-AC620592822E'),
            'PredictedSLAScoredAt',
            'Predicted SLA Scored At',
            NULL,
            'datetimeoffset',
            10,
            34,
            7,
            1,
            NULL,
            0,
            0,
            1,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = 'ff834cc2-1fd6-438e-bd22-82f6bea0eaf2' OR (EntityID = 'A6B673F8-43BC-4875-AFF6-AC620592822E' AND Name = 'HealthStatus')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            'ff834cc2-1fd6-438e-bd22-82f6bea0eaf2',
            'A6B673F8-43BC-4875-AFF6-AC620592822E', -- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks
            (SELECT COALESCE(MAX([Sequence]), 0) + 1 FROM [${mjSchema}].[EntityField] WHERE [EntityID] = 'A6B673F8-43BC-4875-AFF6-AC620592822E'),
            'HealthStatus',
            'Health Status',
            NULL,
            'nvarchar',
            40,
            0,
            0,
            1,
            NULL,
            0,
            0,
            1,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '6b700581-9114-4d4d-87fd-7803e6990fe6' OR (EntityID = 'A6B673F8-43BC-4875-AFF6-AC620592822E' AND Name = 'ConfidenceScore')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '6b700581-9114-4d4d-87fd-7803e6990fe6',
            'A6B673F8-43BC-4875-AFF6-AC620592822E', -- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks
            (SELECT COALESCE(MAX([Sequence]), 0) + 1 FROM [${mjSchema}].[EntityField] WHERE [EntityID] = 'A6B673F8-43BC-4875-AFF6-AC620592822E'),
            'ConfidenceScore',
            'Confidence Score',
            NULL,
            'int',
            4,
            10,
            0,
            1,
            NULL,
            0,
            0,
            1,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '2fab02de-f972-461e-9b21-4387520af9b2' OR (EntityID = 'A6B673F8-43BC-4875-AFF6-AC620592822E' AND Name = 'BaselineValue')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '2fab02de-f972-461e-9b21-4387520af9b2',
            'A6B673F8-43BC-4875-AFF6-AC620592822E', -- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks
            (SELECT COALESCE(MAX([Sequence]), 0) + 1 FROM [${mjSchema}].[EntityField] WHERE [EntityID] = 'A6B673F8-43BC-4875-AFF6-AC620592822E'),
            'BaselineValue',
            'Baseline Value',
            NULL,
            'decimal',
            9,
            18,
            4,
            1,
            NULL,
            0,
            0,
            1,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = 'd9bda046-a66f-4965-b964-56a2833e4000' OR (EntityID = 'A6B673F8-43BC-4875-AFF6-AC620592822E' AND Name = 'TargetValue')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            'd9bda046-a66f-4965-b964-56a2833e4000',
            'A6B673F8-43BC-4875-AFF6-AC620592822E', -- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks
            (SELECT COALESCE(MAX([Sequence]), 0) + 1 FROM [${mjSchema}].[EntityField] WHERE [EntityID] = 'A6B673F8-43BC-4875-AFF6-AC620592822E'),
            'TargetValue',
            'Target Value',
            NULL,
            'decimal',
            9,
            18,
            4,
            1,
            NULL,
            0,
            0,
            1,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = 'd568f0df-cf9a-41d6-8ece-5ed935afff02' OR (EntityID = 'A6B673F8-43BC-4875-AFF6-AC620592822E' AND Name = 'CurrentValue')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            'd568f0df-cf9a-41d6-8ece-5ed935afff02',
            'A6B673F8-43BC-4875-AFF6-AC620592822E', -- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks
            (SELECT COALESCE(MAX([Sequence]), 0) + 1 FROM [${mjSchema}].[EntityField] WHERE [EntityID] = 'A6B673F8-43BC-4875-AFF6-AC620592822E'),
            'CurrentValue',
            'Current Value',
            NULL,
            'decimal',
            9,
            18,
            4,
            1,
            NULL,
            0,
            0,
            1,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = 'a15515ce-2505-4a75-909b-996d159bf8b3' OR (EntityID = 'A6B673F8-43BC-4875-AFF6-AC620592822E' AND Name = 'UnitOfMeasure')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            'a15515ce-2505-4a75-909b-996d159bf8b3',
            'A6B673F8-43BC-4875-AFF6-AC620592822E', -- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks
            (SELECT COALESCE(MAX([Sequence]), 0) + 1 FROM [${mjSchema}].[EntityField] WHERE [EntityID] = 'A6B673F8-43BC-4875-AFF6-AC620592822E'),
            'UnitOfMeasure',
            'Unit Of Measure',
            NULL,
            'nvarchar',
            100,
            0,
            0,
            1,
            NULL,
            0,
            0,
            1,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '72a1ace2-6bd6-4861-9de0-f617873736d7' OR (EntityID = 'A6B673F8-43BC-4875-AFF6-AC620592822E' AND Name = 'MetricDirection')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '72a1ace2-6bd6-4861-9de0-f617873736d7',
            'A6B673F8-43BC-4875-AFF6-AC620592822E', -- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks
            (SELECT COALESCE(MAX([Sequence]), 0) + 1 FROM [${mjSchema}].[EntityField] WHERE [EntityID] = 'A6B673F8-43BC-4875-AFF6-AC620592822E'),
            'MetricDirection',
            'Metric Direction',
            NULL,
            'nvarchar',
            40,
            0,
            0,
            1,
            NULL,
            0,
            0,
            1,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '32734bdb-ada6-4d79-b571-bb7a39e50808' OR (EntityID = 'A6B673F8-43BC-4875-AFF6-AC620592822E' AND Name = 'RollupWeight')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '32734bdb-ada6-4d79-b571-bb7a39e50808',
            'A6B673F8-43BC-4875-AFF6-AC620592822E', -- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks
            (SELECT COALESCE(MAX([Sequence]), 0) + 1 FROM [${mjSchema}].[EntityField] WHERE [EntityID] = 'A6B673F8-43BC-4875-AFF6-AC620592822E'),
            'RollupWeight',
            'Rollup Weight',
            NULL,
            'decimal',
            5,
            8,
            2,
            0,
            NULL,
            0,
            0,
            1,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '74340cb6-2cf9-4078-b056-bcec5ab63a3a' OR (EntityID = 'A6B673F8-43BC-4875-AFF6-AC620592822E' AND Name = 'PlanningPeriod')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '74340cb6-2cf9-4078-b056-bcec5ab63a3a',
            'A6B673F8-43BC-4875-AFF6-AC620592822E', -- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks
            (SELECT COALESCE(MAX([Sequence]), 0) + 1 FROM [${mjSchema}].[EntityField] WHERE [EntityID] = 'A6B673F8-43BC-4875-AFF6-AC620592822E'),
            'PlanningPeriod',
            'Planning Period',
            NULL,
            'nvarchar',
            100,
            0,
            0,
            1,
            NULL,
            0,
            0,
            1,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '74337fd7-6b08-4ee4-afe9-5c97ee684b19' OR (EntityID = 'A6B673F8-43BC-4875-AFF6-AC620592822E' AND Name = 'CheckInCadence')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '74337fd7-6b08-4ee4-afe9-5c97ee684b19',
            'A6B673F8-43BC-4875-AFF6-AC620592822E', -- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks
            (SELECT COALESCE(MAX([Sequence]), 0) + 1 FROM [${mjSchema}].[EntityField] WHERE [EntityID] = 'A6B673F8-43BC-4875-AFF6-AC620592822E'),
            'CheckInCadence',
            'Check In Cadence',
            NULL,
            'nvarchar',
            40,
            0,
            0,
            1,
            NULL,
            0,
            0,
            1,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '8caf3bc8-b357-4b60-ad0e-76b818806ccc' OR (EntityID = 'A6B673F8-43BC-4875-AFF6-AC620592822E' AND Name = 'LastCheckInAt')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '8caf3bc8-b357-4b60-ad0e-76b818806ccc',
            'A6B673F8-43BC-4875-AFF6-AC620592822E', -- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks
            (SELECT COALESCE(MAX([Sequence]), 0) + 1 FROM [${mjSchema}].[EntityField] WHERE [EntityID] = 'A6B673F8-43BC-4875-AFF6-AC620592822E'),
            'LastCheckInAt',
            'Last Check In At',
            NULL,
            'datetimeoffset',
            10,
            34,
            7,
            1,
            NULL,
            0,
            0,
            1,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '8db46a9c-8567-43d3-85e1-af3174f6628f' OR (EntityID = 'A6B673F8-43BC-4875-AFF6-AC620592822E' AND Name = 'NextCheckInDueAt')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '8db46a9c-8567-43d3-85e1-af3174f6628f',
            'A6B673F8-43BC-4875-AFF6-AC620592822E', -- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks
            (SELECT COALESCE(MAX([Sequence]), 0) + 1 FROM [${mjSchema}].[EntityField] WHERE [EntityID] = 'A6B673F8-43BC-4875-AFF6-AC620592822E'),
            'NextCheckInDueAt',
            'Next Check In Due At',
            NULL,
            'datetimeoffset',
            10,
            34,
            7,
            1,
            NULL,
            0,
            0,
            1,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

/* SQL text to update existing entity fields from schema (2 scoped entities) */
EXEC [${mjSchema}].[spUpdateExistingEntityFieldsFromSchema] @ExcludedSchemaNames='', @EntityIDs='DC8E0F5B-E172-4FD5-B648-8B4544F8C605,A6B673F8-43BC-4875-AFF6-AC620592822E', @IncludedSchemaNames='${flyway:defaultSchema}';

/* Update IS-A parent field Name on MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks */
UPDATE [${mjSchema}].[EntityField]
                  SET [IsVirtual]=1,
                      [Type]='nvarchar',
                      [Length]=510,
                      [Precision]=0,
                      [Scale]=0,
                      [AllowsNull]=0,
                      [AllowUpdateAPI]=1,
                      [IncludeRelatedEntityNameFieldInBaseView]=0,
                      [RelatedEntityID]=NULL,
                      [RelatedEntityFieldName]=NULL,
                      [RelatedEntityDisplayType]='Search'
                  WHERE [ID]='5F177501-4505-4DFE-9813-9B930DFE80C5';

/* Update IS-A parent field Description on MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks */
UPDATE [${mjSchema}].[EntityField]
                  SET [IsVirtual]=1,
                      [Type]='nvarchar',
                      [Length]=-1,
                      [Precision]=0,
                      [Scale]=0,
                      [AllowsNull]=1,
                      [AllowUpdateAPI]=1,
                      [IncludeRelatedEntityNameFieldInBaseView]=0,
                      [RelatedEntityID]=NULL,
                      [RelatedEntityFieldName]=NULL,
                      [RelatedEntityDisplayType]='Search'
                  WHERE [ID]='ABC08616-BC3E-441F-8E7D-A4274959C326';

/* Update IS-A parent field TypeID on MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks */
UPDATE [${mjSchema}].[EntityField]
                  SET [IsVirtual]=1,
                      [Type]='uniqueidentifier',
                      [Length]=16,
                      [Precision]=0,
                      [Scale]=0,
                      [AllowsNull]=0,
                      [AllowUpdateAPI]=1,
                      [IncludeRelatedEntityNameFieldInBaseView]=0,
                      [RelatedEntityID]='1E30141A-826F-4278-BAA9-BBE14D29E606',
                      [RelatedEntityFieldName]='ID',
                      [RelatedEntityDisplayType]='Search'
                  WHERE [ID]='104159FF-DB47-414C-A573-22218C8E246E';

/* Update IS-A parent field CategoryID on MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks */
UPDATE [${mjSchema}].[EntityField]
                  SET [IsVirtual]=1,
                      [Type]='uniqueidentifier',
                      [Length]=16,
                      [Precision]=0,
                      [Scale]=0,
                      [AllowsNull]=1,
                      [AllowUpdateAPI]=1,
                      [IncludeRelatedEntityNameFieldInBaseView]=0,
                      [RelatedEntityID]='06303FA3-48F0-45B7-BC6A-F3EBDFEE5CB6',
                      [RelatedEntityFieldName]='ID',
                      [RelatedEntityDisplayType]='Search'
                  WHERE [ID]='BEE37B1E-65C9-4B3B-8E1E-52307578D3F3';

/* Update IS-A parent field ParentID on MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks */
UPDATE [${mjSchema}].[EntityField]
                  SET [IsVirtual]=1,
                      [Type]='uniqueidentifier',
                      [Length]=16,
                      [Precision]=0,
                      [Scale]=0,
                      [AllowsNull]=1,
                      [AllowUpdateAPI]=1,
                      [IncludeRelatedEntityNameFieldInBaseView]=0,
                      [RelatedEntityID]='B348FFA2-B1A7-4AC2-B6FD-F4E0C0697466',
                      [RelatedEntityFieldName]='ID',
                      [RelatedEntityDisplayType]='Search'
                  WHERE [ID]='B3889303-F49F-4D92-853F-65AC124F359D';

/* Update IS-A parent field Status on MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks */
UPDATE [${mjSchema}].[EntityField]
                  SET [IsVirtual]=1,
                      [Type]='nvarchar',
                      [Length]=100,
                      [Precision]=0,
                      [Scale]=0,
                      [AllowsNull]=0,
                      [AllowUpdateAPI]=1,
                      [IncludeRelatedEntityNameFieldInBaseView]=0,
                      [RelatedEntityID]=NULL,
                      [RelatedEntityFieldName]=NULL,
                      [RelatedEntityDisplayType]='Search'
                  WHERE [ID]='A65EDA96-67F2-4C99-B96C-65388A906AAC';

/* Update IS-A parent field Priority on MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks */
UPDATE [${mjSchema}].[EntityField]
                  SET [IsVirtual]=1,
                      [Type]='nvarchar',
                      [Length]=40,
                      [Precision]=0,
                      [Scale]=0,
                      [AllowsNull]=0,
                      [AllowUpdateAPI]=1,
                      [IncludeRelatedEntityNameFieldInBaseView]=0,
                      [RelatedEntityID]=NULL,
                      [RelatedEntityFieldName]=NULL,
                      [RelatedEntityDisplayType]='Search'
                  WHERE [ID]='D70ABD8C-2AC1-44E1-AEA2-945D6DAA9ED7';

/* Update IS-A parent field StartedAt on MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks */
UPDATE [${mjSchema}].[EntityField]
                  SET [IsVirtual]=1,
                      [Type]='datetimeoffset',
                      [Length]=10,
                      [Precision]=34,
                      [Scale]=7,
                      [AllowsNull]=1,
                      [AllowUpdateAPI]=1,
                      [IncludeRelatedEntityNameFieldInBaseView]=0,
                      [RelatedEntityID]=NULL,
                      [RelatedEntityFieldName]=NULL,
                      [RelatedEntityDisplayType]='Search'
                  WHERE [ID]='E28AF650-AB4A-45BB-A94D-814467A2536D';

/* Update IS-A parent field DueAt on MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks */
UPDATE [${mjSchema}].[EntityField]
                  SET [IsVirtual]=1,
                      [Type]='datetimeoffset',
                      [Length]=10,
                      [Precision]=34,
                      [Scale]=7,
                      [AllowsNull]=1,
                      [AllowUpdateAPI]=1,
                      [IncludeRelatedEntityNameFieldInBaseView]=0,
                      [RelatedEntityID]=NULL,
                      [RelatedEntityFieldName]=NULL,
                      [RelatedEntityDisplayType]='Search'
                  WHERE [ID]='B83A675F-795C-47ED-81F4-CBBD5FF4D929';

/* Update IS-A parent field CompletedAt on MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks */
UPDATE [${mjSchema}].[EntityField]
                  SET [IsVirtual]=1,
                      [Type]='datetimeoffset',
                      [Length]=10,
                      [Precision]=34,
                      [Scale]=7,
                      [AllowsNull]=1,
                      [AllowUpdateAPI]=1,
                      [IncludeRelatedEntityNameFieldInBaseView]=0,
                      [RelatedEntityID]=NULL,
                      [RelatedEntityFieldName]=NULL,
                      [RelatedEntityDisplayType]='Search'
                  WHERE [ID]='CEF54E7E-100C-432E-9D83-FE29B47C5F73';

/* Update IS-A parent field HoursEstimated on MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks */
UPDATE [${mjSchema}].[EntityField]
                  SET [IsVirtual]=1,
                      [Type]='decimal',
                      [Length]=5,
                      [Precision]=8,
                      [Scale]=2,
                      [AllowsNull]=1,
                      [AllowUpdateAPI]=1,
                      [IncludeRelatedEntityNameFieldInBaseView]=0,
                      [RelatedEntityID]=NULL,
                      [RelatedEntityFieldName]=NULL,
                      [RelatedEntityDisplayType]='Search'
                  WHERE [ID]='C9363AE8-2C58-46C5-B437-C7D26A02C353';

/* Update IS-A parent field HoursActual on MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks */
UPDATE [${mjSchema}].[EntityField]
                  SET [IsVirtual]=1,
                      [Type]='decimal',
                      [Length]=5,
                      [Precision]=8,
                      [Scale]=2,
                      [AllowsNull]=1,
                      [AllowUpdateAPI]=1,
                      [IncludeRelatedEntityNameFieldInBaseView]=0,
                      [RelatedEntityID]=NULL,
                      [RelatedEntityFieldName]=NULL,
                      [RelatedEntityDisplayType]='Search'
                  WHERE [ID]='3F2F697F-56E2-450F-BF03-77DC470D5754';

/* Update IS-A parent field PercentComplete on MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks */
UPDATE [${mjSchema}].[EntityField]
                  SET [IsVirtual]=1,
                      [Type]='int',
                      [Length]=4,
                      [Precision]=10,
                      [Scale]=0,
                      [AllowsNull]=0,
                      [AllowUpdateAPI]=1,
                      [IncludeRelatedEntityNameFieldInBaseView]=0,
                      [RelatedEntityID]=NULL,
                      [RelatedEntityFieldName]=NULL,
                      [RelatedEntityDisplayType]='Search'
                  WHERE [ID]='732FA3A2-4E55-44C0-9F6B-FE50B894C27E';

/* Update IS-A parent field Sequence on MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks */
UPDATE [${mjSchema}].[EntityField]
                  SET [IsVirtual]=1,
                      [Type]='int',
                      [Length]=4,
                      [Precision]=10,
                      [Scale]=0,
                      [AllowsNull]=0,
                      [AllowUpdateAPI]=1,
                      [IncludeRelatedEntityNameFieldInBaseView]=0,
                      [RelatedEntityID]=NULL,
                      [RelatedEntityFieldName]=NULL,
                      [RelatedEntityDisplayType]='Search'
                  WHERE [ID]='77EC9524-1745-4341-B0FD-EBE74E176E4A';

/* Update IS-A parent field BlockedReason on MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks */
UPDATE [${mjSchema}].[EntityField]
                  SET [IsVirtual]=1,
                      [Type]='nvarchar',
                      [Length]=-1,
                      [Precision]=0,
                      [Scale]=0,
                      [AllowsNull]=1,
                      [AllowUpdateAPI]=1,
                      [IncludeRelatedEntityNameFieldInBaseView]=0,
                      [RelatedEntityID]=NULL,
                      [RelatedEntityFieldName]=NULL,
                      [RelatedEntityDisplayType]='Search'
                  WHERE [ID]='EAF33611-EB3D-4621-BC57-292F137E43C4';

/* Update IS-A parent field CompletionNotes on MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks */
UPDATE [${mjSchema}].[EntityField]
                  SET [IsVirtual]=1,
                      [Type]='nvarchar',
                      [Length]=-1,
                      [Precision]=0,
                      [Scale]=0,
                      [AllowsNull]=1,
                      [AllowUpdateAPI]=1,
                      [IncludeRelatedEntityNameFieldInBaseView]=0,
                      [RelatedEntityID]=NULL,
                      [RelatedEntityFieldName]=NULL,
                      [RelatedEntityDisplayType]='Search'
                  WHERE [ID]='E856766E-55A2-4DE8-990E-86D7D1E7056A';

/* Update IS-A parent field CreatedByPersonID on MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks */
UPDATE [${mjSchema}].[EntityField]
                  SET [IsVirtual]=1,
                      [Type]='uniqueidentifier',
                      [Length]=16,
                      [Precision]=0,
                      [Scale]=0,
                      [AllowsNull]=1,
                      [AllowUpdateAPI]=1,
                      [IncludeRelatedEntityNameFieldInBaseView]=0,
                      [RelatedEntityID]='7A94ADA9-7880-4FAE-97D8-DB0E934C3F5F',
                      [RelatedEntityFieldName]='ID',
                      [RelatedEntityDisplayType]='Search'
                  WHERE [ID]='6199AC88-26D6-4320-8B59-952C0E1945EA';

/* Update IS-A parent field OverdueNotifiedAt on MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks */
UPDATE [${mjSchema}].[EntityField]
                  SET [IsVirtual]=1,
                      [Type]='datetimeoffset',
                      [Length]=10,
                      [Precision]=34,
                      [Scale]=7,
                      [AllowsNull]=1,
                      [AllowUpdateAPI]=1,
                      [IncludeRelatedEntityNameFieldInBaseView]=0,
                      [RelatedEntityID]=NULL,
                      [RelatedEntityFieldName]=NULL,
                      [RelatedEntityDisplayType]='Search'
                  WHERE [ID]='CE26B855-64AC-45B7-9549-39AC48FA7FA8';

/* Update IS-A parent field TaskTypeStatusID on MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks */
UPDATE [${mjSchema}].[EntityField]
                  SET [IsVirtual]=1,
                      [Type]='uniqueidentifier',
                      [Length]=16,
                      [Precision]=0,
                      [Scale]=0,
                      [AllowsNull]=1,
                      [AllowUpdateAPI]=1,
                      [IncludeRelatedEntityNameFieldInBaseView]=0,
                      [RelatedEntityID]='6C8516B0-D87C-4B57-87F8-474D7FF6CDD9',
                      [RelatedEntityFieldName]='ID',
                      [RelatedEntityDisplayType]='Search'
                  WHERE [ID]='F0ABFE53-246F-41D8-B25A-E462FC412615';

/* Update IS-A parent field PredictedSLABreachProbability on MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks */
UPDATE [${mjSchema}].[EntityField]
                  SET [IsVirtual]=1,
                      [Type]='decimal',
                      [Length]=5,
                      [Precision]=5,
                      [Scale]=4,
                      [AllowsNull]=1,
                      [AllowUpdateAPI]=1,
                      [IncludeRelatedEntityNameFieldInBaseView]=0,
                      [RelatedEntityID]=NULL,
                      [RelatedEntityFieldName]=NULL,
                      [RelatedEntityDisplayType]='Search'
                  WHERE [ID]='D1AB1A5C-A1EE-4EC5-95FE-4FD4C8AB7630';

/* Update IS-A parent field PredictedSLARiskBand on MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks */
UPDATE [${mjSchema}].[EntityField]
                  SET [IsVirtual]=1,
                      [Type]='nvarchar',
                      [Length]=40,
                      [Precision]=0,
                      [Scale]=0,
                      [AllowsNull]=1,
                      [AllowUpdateAPI]=1,
                      [IncludeRelatedEntityNameFieldInBaseView]=0,
                      [RelatedEntityID]=NULL,
                      [RelatedEntityFieldName]=NULL,
                      [RelatedEntityDisplayType]='Search'
                  WHERE [ID]='D2574DDB-325F-473D-997A-66CC43309934';

/* Update IS-A parent field PredictedSLAScoredAt on MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks */
UPDATE [${mjSchema}].[EntityField]
                  SET [IsVirtual]=1,
                      [Type]='datetimeoffset',
                      [Length]=10,
                      [Precision]=34,
                      [Scale]=7,
                      [AllowsNull]=1,
                      [AllowUpdateAPI]=1,
                      [IncludeRelatedEntityNameFieldInBaseView]=0,
                      [RelatedEntityID]=NULL,
                      [RelatedEntityFieldName]=NULL,
                      [RelatedEntityDisplayType]='Search'
                  WHERE [ID]='947C6BAE-94D3-4999-AC0F-DAFE404E008F';

/* Update IS-A parent field HealthStatus on MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks */
UPDATE [${mjSchema}].[EntityField]
                  SET [IsVirtual]=1,
                      [Type]='nvarchar',
                      [Length]=40,
                      [Precision]=0,
                      [Scale]=0,
                      [AllowsNull]=1,
                      [AllowUpdateAPI]=1,
                      [IncludeRelatedEntityNameFieldInBaseView]=0,
                      [RelatedEntityID]=NULL,
                      [RelatedEntityFieldName]=NULL,
                      [RelatedEntityDisplayType]='Search'
                  WHERE [ID]='8EFE7EAC-45DB-4B89-9221-2B19B99068B9';

/* Update IS-A parent field ConfidenceScore on MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks */
UPDATE [${mjSchema}].[EntityField]
                  SET [IsVirtual]=1,
                      [Type]='int',
                      [Length]=4,
                      [Precision]=10,
                      [Scale]=0,
                      [AllowsNull]=1,
                      [AllowUpdateAPI]=1,
                      [IncludeRelatedEntityNameFieldInBaseView]=0,
                      [RelatedEntityID]=NULL,
                      [RelatedEntityFieldName]=NULL,
                      [RelatedEntityDisplayType]='Search'
                  WHERE [ID]='EA927E59-FFD9-4F5C-91BC-DB57A268CB3F';

/* Update IS-A parent field BaselineValue on MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks */
UPDATE [${mjSchema}].[EntityField]
                  SET [IsVirtual]=1,
                      [Type]='decimal',
                      [Length]=9,
                      [Precision]=18,
                      [Scale]=4,
                      [AllowsNull]=1,
                      [AllowUpdateAPI]=1,
                      [IncludeRelatedEntityNameFieldInBaseView]=0,
                      [RelatedEntityID]=NULL,
                      [RelatedEntityFieldName]=NULL,
                      [RelatedEntityDisplayType]='Search'
                  WHERE [ID]='835E5643-810D-4B4E-8E83-E9595428437C';

/* Update IS-A parent field TargetValue on MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks */
UPDATE [${mjSchema}].[EntityField]
                  SET [IsVirtual]=1,
                      [Type]='decimal',
                      [Length]=9,
                      [Precision]=18,
                      [Scale]=4,
                      [AllowsNull]=1,
                      [AllowUpdateAPI]=1,
                      [IncludeRelatedEntityNameFieldInBaseView]=0,
                      [RelatedEntityID]=NULL,
                      [RelatedEntityFieldName]=NULL,
                      [RelatedEntityDisplayType]='Search'
                  WHERE [ID]='77DD9516-90EF-4855-9CF7-CA0D81B59A8F';

/* Update IS-A parent field CurrentValue on MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks */
UPDATE [${mjSchema}].[EntityField]
                  SET [IsVirtual]=1,
                      [Type]='decimal',
                      [Length]=9,
                      [Precision]=18,
                      [Scale]=4,
                      [AllowsNull]=1,
                      [AllowUpdateAPI]=1,
                      [IncludeRelatedEntityNameFieldInBaseView]=0,
                      [RelatedEntityID]=NULL,
                      [RelatedEntityFieldName]=NULL,
                      [RelatedEntityDisplayType]='Search'
                  WHERE [ID]='AF810BE2-BA61-46DD-ADEC-7F3FE7FB35E2';

/* Update IS-A parent field UnitOfMeasure on MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks */
UPDATE [${mjSchema}].[EntityField]
                  SET [IsVirtual]=1,
                      [Type]='nvarchar',
                      [Length]=100,
                      [Precision]=0,
                      [Scale]=0,
                      [AllowsNull]=1,
                      [AllowUpdateAPI]=1,
                      [IncludeRelatedEntityNameFieldInBaseView]=0,
                      [RelatedEntityID]=NULL,
                      [RelatedEntityFieldName]=NULL,
                      [RelatedEntityDisplayType]='Search'
                  WHERE [ID]='FD6FA1E2-DA35-409A-9116-36640D818333';

/* Update IS-A parent field MetricDirection on MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks */
UPDATE [${mjSchema}].[EntityField]
                  SET [IsVirtual]=1,
                      [Type]='nvarchar',
                      [Length]=40,
                      [Precision]=0,
                      [Scale]=0,
                      [AllowsNull]=1,
                      [AllowUpdateAPI]=1,
                      [IncludeRelatedEntityNameFieldInBaseView]=0,
                      [RelatedEntityID]=NULL,
                      [RelatedEntityFieldName]=NULL,
                      [RelatedEntityDisplayType]='Search'
                  WHERE [ID]='86B721D5-8AA2-4199-AEF7-C933A6BA52FF';

/* Update IS-A parent field RollupWeight on MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks */
UPDATE [${mjSchema}].[EntityField]
                  SET [IsVirtual]=1,
                      [Type]='decimal',
                      [Length]=5,
                      [Precision]=8,
                      [Scale]=2,
                      [AllowsNull]=0,
                      [AllowUpdateAPI]=1,
                      [IncludeRelatedEntityNameFieldInBaseView]=0,
                      [RelatedEntityID]=NULL,
                      [RelatedEntityFieldName]=NULL,
                      [RelatedEntityDisplayType]='Search'
                  WHERE [ID]='03F75DAD-73A6-4C9C-B473-50AF0F4DFDBF';

/* Update IS-A parent field PlanningPeriod on MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks */
UPDATE [${mjSchema}].[EntityField]
                  SET [IsVirtual]=1,
                      [Type]='nvarchar',
                      [Length]=100,
                      [Precision]=0,
                      [Scale]=0,
                      [AllowsNull]=1,
                      [AllowUpdateAPI]=1,
                      [IncludeRelatedEntityNameFieldInBaseView]=0,
                      [RelatedEntityID]=NULL,
                      [RelatedEntityFieldName]=NULL,
                      [RelatedEntityDisplayType]='Search'
                  WHERE [ID]='E4A34B92-D140-405D-9AB7-1003EDED8BE8';

/* Update IS-A parent field CheckInCadence on MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks */
UPDATE [${mjSchema}].[EntityField]
                  SET [IsVirtual]=1,
                      [Type]='nvarchar',
                      [Length]=40,
                      [Precision]=0,
                      [Scale]=0,
                      [AllowsNull]=1,
                      [AllowUpdateAPI]=1,
                      [IncludeRelatedEntityNameFieldInBaseView]=0,
                      [RelatedEntityID]=NULL,
                      [RelatedEntityFieldName]=NULL,
                      [RelatedEntityDisplayType]='Search'
                  WHERE [ID]='C652B089-04BD-4A3E-BBAD-07D5D2474568';

/* Update IS-A parent field LastCheckInAt on MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks */
UPDATE [${mjSchema}].[EntityField]
                  SET [IsVirtual]=1,
                      [Type]='datetimeoffset',
                      [Length]=10,
                      [Precision]=34,
                      [Scale]=7,
                      [AllowsNull]=1,
                      [AllowUpdateAPI]=1,
                      [IncludeRelatedEntityNameFieldInBaseView]=0,
                      [RelatedEntityID]=NULL,
                      [RelatedEntityFieldName]=NULL,
                      [RelatedEntityDisplayType]='Search'
                  WHERE [ID]='6FE24C88-2E9C-49E9-AFD2-4E0D428F7C50';

/* Update IS-A parent field NextCheckInDueAt on MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks */
UPDATE [${mjSchema}].[EntityField]
                  SET [IsVirtual]=1,
                      [Type]='datetimeoffset',
                      [Length]=10,
                      [Precision]=34,
                      [Scale]=7,
                      [AllowsNull]=1,
                      [AllowUpdateAPI]=1,
                      [IncludeRelatedEntityNameFieldInBaseView]=0,
                      [RelatedEntityID]=NULL,
                      [RelatedEntityFieldName]=NULL,
                      [RelatedEntityDisplayType]='Search'
                  WHERE [ID]='C4AA4959-C523-450D-95C7-F7C4119F6211';

/* Update entity timestamp for MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks after IS-A field sync */
UPDATE [${mjSchema}].[Entity] SET [__mj_UpdatedAt]=GETUTCDATE() WHERE ID='DC8E0F5B-E172-4FD5-B648-8B4544F8C605';

/* Update IS-A parent field Name on MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks */
UPDATE [${mjSchema}].[EntityField]
                  SET [IsVirtual]=1,
                      [Type]='nvarchar',
                      [Length]=510,
                      [Precision]=0,
                      [Scale]=0,
                      [AllowsNull]=0,
                      [AllowUpdateAPI]=1,
                      [IncludeRelatedEntityNameFieldInBaseView]=0,
                      [RelatedEntityID]=NULL,
                      [RelatedEntityFieldName]=NULL,
                      [RelatedEntityDisplayType]='Search'
                  WHERE [ID]='4BA1A1F6-223E-4E8D-99D0-16448913D993';

/* Update IS-A parent field Description on MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks */
UPDATE [${mjSchema}].[EntityField]
                  SET [IsVirtual]=1,
                      [Type]='nvarchar',
                      [Length]=-1,
                      [Precision]=0,
                      [Scale]=0,
                      [AllowsNull]=1,
                      [AllowUpdateAPI]=1,
                      [IncludeRelatedEntityNameFieldInBaseView]=0,
                      [RelatedEntityID]=NULL,
                      [RelatedEntityFieldName]=NULL,
                      [RelatedEntityDisplayType]='Search'
                  WHERE [ID]='504CE539-0CC4-47D3-AD5D-120907A421ED';

/* Update IS-A parent field TypeID on MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks */
UPDATE [${mjSchema}].[EntityField]
                  SET [IsVirtual]=1,
                      [Type]='uniqueidentifier',
                      [Length]=16,
                      [Precision]=0,
                      [Scale]=0,
                      [AllowsNull]=0,
                      [AllowUpdateAPI]=1,
                      [IncludeRelatedEntityNameFieldInBaseView]=0,
                      [RelatedEntityID]='1E30141A-826F-4278-BAA9-BBE14D29E606',
                      [RelatedEntityFieldName]='ID',
                      [RelatedEntityDisplayType]='Search'
                  WHERE [ID]='A26A18FA-8F34-423E-AC94-3F3B47AC87C9';

/* Update IS-A parent field CategoryID on MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks */
UPDATE [${mjSchema}].[EntityField]
                  SET [IsVirtual]=1,
                      [Type]='uniqueidentifier',
                      [Length]=16,
                      [Precision]=0,
                      [Scale]=0,
                      [AllowsNull]=1,
                      [AllowUpdateAPI]=1,
                      [IncludeRelatedEntityNameFieldInBaseView]=0,
                      [RelatedEntityID]='06303FA3-48F0-45B7-BC6A-F3EBDFEE5CB6',
                      [RelatedEntityFieldName]='ID',
                      [RelatedEntityDisplayType]='Search'
                  WHERE [ID]='2F5E2D1C-F10A-42F0-9AD0-71956D6ED9C5';

/* Update IS-A parent field ParentID on MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks */
UPDATE [${mjSchema}].[EntityField]
                  SET [IsVirtual]=1,
                      [Type]='uniqueidentifier',
                      [Length]=16,
                      [Precision]=0,
                      [Scale]=0,
                      [AllowsNull]=1,
                      [AllowUpdateAPI]=1,
                      [IncludeRelatedEntityNameFieldInBaseView]=0,
                      [RelatedEntityID]='B348FFA2-B1A7-4AC2-B6FD-F4E0C0697466',
                      [RelatedEntityFieldName]='ID',
                      [RelatedEntityDisplayType]='Search'
                  WHERE [ID]='8A12D74A-F61C-4669-AB9A-F83FD4418679';

/* Update IS-A parent field Status on MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks */
UPDATE [${mjSchema}].[EntityField]
                  SET [IsVirtual]=1,
                      [Type]='nvarchar',
                      [Length]=100,
                      [Precision]=0,
                      [Scale]=0,
                      [AllowsNull]=0,
                      [AllowUpdateAPI]=1,
                      [IncludeRelatedEntityNameFieldInBaseView]=0,
                      [RelatedEntityID]=NULL,
                      [RelatedEntityFieldName]=NULL,
                      [RelatedEntityDisplayType]='Search'
                  WHERE [ID]='CCAE381C-911D-407D-BA0B-05BDB95CABFB';

/* Update IS-A parent field Priority on MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks */
UPDATE [${mjSchema}].[EntityField]
                  SET [IsVirtual]=1,
                      [Type]='nvarchar',
                      [Length]=40,
                      [Precision]=0,
                      [Scale]=0,
                      [AllowsNull]=0,
                      [AllowUpdateAPI]=1,
                      [IncludeRelatedEntityNameFieldInBaseView]=0,
                      [RelatedEntityID]=NULL,
                      [RelatedEntityFieldName]=NULL,
                      [RelatedEntityDisplayType]='Search'
                  WHERE [ID]='10503F3A-EAAD-4EFA-AA23-ED42AF9335F2';

/* Update IS-A parent field StartedAt on MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks */
UPDATE [${mjSchema}].[EntityField]
                  SET [IsVirtual]=1,
                      [Type]='datetimeoffset',
                      [Length]=10,
                      [Precision]=34,
                      [Scale]=7,
                      [AllowsNull]=1,
                      [AllowUpdateAPI]=1,
                      [IncludeRelatedEntityNameFieldInBaseView]=0,
                      [RelatedEntityID]=NULL,
                      [RelatedEntityFieldName]=NULL,
                      [RelatedEntityDisplayType]='Search'
                  WHERE [ID]='CFD64243-AD98-4583-9393-E2A86AA869FE';

/* Update IS-A parent field DueAt on MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks */
UPDATE [${mjSchema}].[EntityField]
                  SET [IsVirtual]=1,
                      [Type]='datetimeoffset',
                      [Length]=10,
                      [Precision]=34,
                      [Scale]=7,
                      [AllowsNull]=1,
                      [AllowUpdateAPI]=1,
                      [IncludeRelatedEntityNameFieldInBaseView]=0,
                      [RelatedEntityID]=NULL,
                      [RelatedEntityFieldName]=NULL,
                      [RelatedEntityDisplayType]='Search'
                  WHERE [ID]='D6A809C0-B643-4045-BBBC-43420E9C4D9D';

/* Update IS-A parent field CompletedAt on MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks */
UPDATE [${mjSchema}].[EntityField]
                  SET [IsVirtual]=1,
                      [Type]='datetimeoffset',
                      [Length]=10,
                      [Precision]=34,
                      [Scale]=7,
                      [AllowsNull]=1,
                      [AllowUpdateAPI]=1,
                      [IncludeRelatedEntityNameFieldInBaseView]=0,
                      [RelatedEntityID]=NULL,
                      [RelatedEntityFieldName]=NULL,
                      [RelatedEntityDisplayType]='Search'
                  WHERE [ID]='AEB061C9-C5B7-429C-BBFB-BFE7F0B9B8DB';

/* Update IS-A parent field HoursEstimated on MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks */
UPDATE [${mjSchema}].[EntityField]
                  SET [IsVirtual]=1,
                      [Type]='decimal',
                      [Length]=5,
                      [Precision]=8,
                      [Scale]=2,
                      [AllowsNull]=1,
                      [AllowUpdateAPI]=1,
                      [IncludeRelatedEntityNameFieldInBaseView]=0,
                      [RelatedEntityID]=NULL,
                      [RelatedEntityFieldName]=NULL,
                      [RelatedEntityDisplayType]='Search'
                  WHERE [ID]='05869A56-0E75-4721-8FDF-4969DF401C85';

/* Update IS-A parent field HoursActual on MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks */
UPDATE [${mjSchema}].[EntityField]
                  SET [IsVirtual]=1,
                      [Type]='decimal',
                      [Length]=5,
                      [Precision]=8,
                      [Scale]=2,
                      [AllowsNull]=1,
                      [AllowUpdateAPI]=1,
                      [IncludeRelatedEntityNameFieldInBaseView]=0,
                      [RelatedEntityID]=NULL,
                      [RelatedEntityFieldName]=NULL,
                      [RelatedEntityDisplayType]='Search'
                  WHERE [ID]='5025C924-87BC-4045-B5B2-AF280B8BF9D5';

/* Update IS-A parent field PercentComplete on MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks */
UPDATE [${mjSchema}].[EntityField]
                  SET [IsVirtual]=1,
                      [Type]='int',
                      [Length]=4,
                      [Precision]=10,
                      [Scale]=0,
                      [AllowsNull]=0,
                      [AllowUpdateAPI]=1,
                      [IncludeRelatedEntityNameFieldInBaseView]=0,
                      [RelatedEntityID]=NULL,
                      [RelatedEntityFieldName]=NULL,
                      [RelatedEntityDisplayType]='Search'
                  WHERE [ID]='C0C67A45-F9F6-4962-A5DC-2176F8EF1F0A';

/* Update IS-A parent field Sequence on MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks */
UPDATE [${mjSchema}].[EntityField]
                  SET [IsVirtual]=1,
                      [Type]='int',
                      [Length]=4,
                      [Precision]=10,
                      [Scale]=0,
                      [AllowsNull]=0,
                      [AllowUpdateAPI]=1,
                      [IncludeRelatedEntityNameFieldInBaseView]=0,
                      [RelatedEntityID]=NULL,
                      [RelatedEntityFieldName]=NULL,
                      [RelatedEntityDisplayType]='Search'
                  WHERE [ID]='C1D1EB47-D5AF-42B7-926E-38440E14B0B0';

/* Update IS-A parent field BlockedReason on MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks */
UPDATE [${mjSchema}].[EntityField]
                  SET [IsVirtual]=1,
                      [Type]='nvarchar',
                      [Length]=-1,
                      [Precision]=0,
                      [Scale]=0,
                      [AllowsNull]=1,
                      [AllowUpdateAPI]=1,
                      [IncludeRelatedEntityNameFieldInBaseView]=0,
                      [RelatedEntityID]=NULL,
                      [RelatedEntityFieldName]=NULL,
                      [RelatedEntityDisplayType]='Search'
                  WHERE [ID]='3365149D-DB81-4D9D-BB29-2D491C6E86FA';

/* Update IS-A parent field CompletionNotes on MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks */
UPDATE [${mjSchema}].[EntityField]
                  SET [IsVirtual]=1,
                      [Type]='nvarchar',
                      [Length]=-1,
                      [Precision]=0,
                      [Scale]=0,
                      [AllowsNull]=1,
                      [AllowUpdateAPI]=1,
                      [IncludeRelatedEntityNameFieldInBaseView]=0,
                      [RelatedEntityID]=NULL,
                      [RelatedEntityFieldName]=NULL,
                      [RelatedEntityDisplayType]='Search'
                  WHERE [ID]='61B50EAD-8C53-4C9F-96AA-76ECDEDAE434';

/* Update IS-A parent field CreatedByPersonID on MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks */
UPDATE [${mjSchema}].[EntityField]
                  SET [IsVirtual]=1,
                      [Type]='uniqueidentifier',
                      [Length]=16,
                      [Precision]=0,
                      [Scale]=0,
                      [AllowsNull]=1,
                      [AllowUpdateAPI]=1,
                      [IncludeRelatedEntityNameFieldInBaseView]=0,
                      [RelatedEntityID]='7A94ADA9-7880-4FAE-97D8-DB0E934C3F5F',
                      [RelatedEntityFieldName]='ID',
                      [RelatedEntityDisplayType]='Search'
                  WHERE [ID]='FB407166-23F9-4BB3-98FB-599F619BB218';

/* Update IS-A parent field OverdueNotifiedAt on MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks */
UPDATE [${mjSchema}].[EntityField]
                  SET [IsVirtual]=1,
                      [Type]='datetimeoffset',
                      [Length]=10,
                      [Precision]=34,
                      [Scale]=7,
                      [AllowsNull]=1,
                      [AllowUpdateAPI]=1,
                      [IncludeRelatedEntityNameFieldInBaseView]=0,
                      [RelatedEntityID]=NULL,
                      [RelatedEntityFieldName]=NULL,
                      [RelatedEntityDisplayType]='Search'
                  WHERE [ID]='23302EB0-8C39-40D4-B309-FAF86854AEE2';

/* Update IS-A parent field TaskTypeStatusID on MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks */
UPDATE [${mjSchema}].[EntityField]
                  SET [IsVirtual]=1,
                      [Type]='uniqueidentifier',
                      [Length]=16,
                      [Precision]=0,
                      [Scale]=0,
                      [AllowsNull]=1,
                      [AllowUpdateAPI]=1,
                      [IncludeRelatedEntityNameFieldInBaseView]=0,
                      [RelatedEntityID]='6C8516B0-D87C-4B57-87F8-474D7FF6CDD9',
                      [RelatedEntityFieldName]='ID',
                      [RelatedEntityDisplayType]='Search'
                  WHERE [ID]='84A6F1CB-4453-4651-B20F-58F0A29789C8';

/* Update IS-A parent field PredictedSLABreachProbability on MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks */
UPDATE [${mjSchema}].[EntityField]
                  SET [IsVirtual]=1,
                      [Type]='decimal',
                      [Length]=5,
                      [Precision]=5,
                      [Scale]=4,
                      [AllowsNull]=1,
                      [AllowUpdateAPI]=1,
                      [IncludeRelatedEntityNameFieldInBaseView]=0,
                      [RelatedEntityID]=NULL,
                      [RelatedEntityFieldName]=NULL,
                      [RelatedEntityDisplayType]='Search'
                  WHERE [ID]='9AAF8300-10B1-4C0C-8A05-CE90F22C22E4';

/* Update IS-A parent field PredictedSLARiskBand on MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks */
UPDATE [${mjSchema}].[EntityField]
                  SET [IsVirtual]=1,
                      [Type]='nvarchar',
                      [Length]=40,
                      [Precision]=0,
                      [Scale]=0,
                      [AllowsNull]=1,
                      [AllowUpdateAPI]=1,
                      [IncludeRelatedEntityNameFieldInBaseView]=0,
                      [RelatedEntityID]=NULL,
                      [RelatedEntityFieldName]=NULL,
                      [RelatedEntityDisplayType]='Search'
                  WHERE [ID]='95D95CDC-AECE-417E-A7EB-BB87A0197A3E';

/* Update IS-A parent field PredictedSLAScoredAt on MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks */
UPDATE [${mjSchema}].[EntityField]
                  SET [IsVirtual]=1,
                      [Type]='datetimeoffset',
                      [Length]=10,
                      [Precision]=34,
                      [Scale]=7,
                      [AllowsNull]=1,
                      [AllowUpdateAPI]=1,
                      [IncludeRelatedEntityNameFieldInBaseView]=0,
                      [RelatedEntityID]=NULL,
                      [RelatedEntityFieldName]=NULL,
                      [RelatedEntityDisplayType]='Search'
                  WHERE [ID]='6EBF3400-38A4-4CE7-A1E8-76DFBB328821';

/* Update IS-A parent field HealthStatus on MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks */
UPDATE [${mjSchema}].[EntityField]
                  SET [IsVirtual]=1,
                      [Type]='nvarchar',
                      [Length]=40,
                      [Precision]=0,
                      [Scale]=0,
                      [AllowsNull]=1,
                      [AllowUpdateAPI]=1,
                      [IncludeRelatedEntityNameFieldInBaseView]=0,
                      [RelatedEntityID]=NULL,
                      [RelatedEntityFieldName]=NULL,
                      [RelatedEntityDisplayType]='Search'
                  WHERE [ID]='FF834CC2-1FD6-438E-BD22-82F6BEA0EAF2';

/* Update IS-A parent field ConfidenceScore on MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks */
UPDATE [${mjSchema}].[EntityField]
                  SET [IsVirtual]=1,
                      [Type]='int',
                      [Length]=4,
                      [Precision]=10,
                      [Scale]=0,
                      [AllowsNull]=1,
                      [AllowUpdateAPI]=1,
                      [IncludeRelatedEntityNameFieldInBaseView]=0,
                      [RelatedEntityID]=NULL,
                      [RelatedEntityFieldName]=NULL,
                      [RelatedEntityDisplayType]='Search'
                  WHERE [ID]='6B700581-9114-4D4D-87FD-7803E6990FE6';

/* Update IS-A parent field BaselineValue on MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks */
UPDATE [${mjSchema}].[EntityField]
                  SET [IsVirtual]=1,
                      [Type]='decimal',
                      [Length]=9,
                      [Precision]=18,
                      [Scale]=4,
                      [AllowsNull]=1,
                      [AllowUpdateAPI]=1,
                      [IncludeRelatedEntityNameFieldInBaseView]=0,
                      [RelatedEntityID]=NULL,
                      [RelatedEntityFieldName]=NULL,
                      [RelatedEntityDisplayType]='Search'
                  WHERE [ID]='2FAB02DE-F972-461E-9B21-4387520AF9B2';

/* Update IS-A parent field TargetValue on MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks */
UPDATE [${mjSchema}].[EntityField]
                  SET [IsVirtual]=1,
                      [Type]='decimal',
                      [Length]=9,
                      [Precision]=18,
                      [Scale]=4,
                      [AllowsNull]=1,
                      [AllowUpdateAPI]=1,
                      [IncludeRelatedEntityNameFieldInBaseView]=0,
                      [RelatedEntityID]=NULL,
                      [RelatedEntityFieldName]=NULL,
                      [RelatedEntityDisplayType]='Search'
                  WHERE [ID]='D9BDA046-A66F-4965-B964-56A2833E4000';

/* Update IS-A parent field CurrentValue on MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks */
UPDATE [${mjSchema}].[EntityField]
                  SET [IsVirtual]=1,
                      [Type]='decimal',
                      [Length]=9,
                      [Precision]=18,
                      [Scale]=4,
                      [AllowsNull]=1,
                      [AllowUpdateAPI]=1,
                      [IncludeRelatedEntityNameFieldInBaseView]=0,
                      [RelatedEntityID]=NULL,
                      [RelatedEntityFieldName]=NULL,
                      [RelatedEntityDisplayType]='Search'
                  WHERE [ID]='D568F0DF-CF9A-41D6-8ECE-5ED935AFFF02';

/* Update IS-A parent field UnitOfMeasure on MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks */
UPDATE [${mjSchema}].[EntityField]
                  SET [IsVirtual]=1,
                      [Type]='nvarchar',
                      [Length]=100,
                      [Precision]=0,
                      [Scale]=0,
                      [AllowsNull]=1,
                      [AllowUpdateAPI]=1,
                      [IncludeRelatedEntityNameFieldInBaseView]=0,
                      [RelatedEntityID]=NULL,
                      [RelatedEntityFieldName]=NULL,
                      [RelatedEntityDisplayType]='Search'
                  WHERE [ID]='A15515CE-2505-4A75-909B-996D159BF8B3';

/* Update IS-A parent field MetricDirection on MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks */
UPDATE [${mjSchema}].[EntityField]
                  SET [IsVirtual]=1,
                      [Type]='nvarchar',
                      [Length]=40,
                      [Precision]=0,
                      [Scale]=0,
                      [AllowsNull]=1,
                      [AllowUpdateAPI]=1,
                      [IncludeRelatedEntityNameFieldInBaseView]=0,
                      [RelatedEntityID]=NULL,
                      [RelatedEntityFieldName]=NULL,
                      [RelatedEntityDisplayType]='Search'
                  WHERE [ID]='72A1ACE2-6BD6-4861-9DE0-F617873736D7';

/* Update IS-A parent field RollupWeight on MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks */
UPDATE [${mjSchema}].[EntityField]
                  SET [IsVirtual]=1,
                      [Type]='decimal',
                      [Length]=5,
                      [Precision]=8,
                      [Scale]=2,
                      [AllowsNull]=0,
                      [AllowUpdateAPI]=1,
                      [IncludeRelatedEntityNameFieldInBaseView]=0,
                      [RelatedEntityID]=NULL,
                      [RelatedEntityFieldName]=NULL,
                      [RelatedEntityDisplayType]='Search'
                  WHERE [ID]='32734BDB-ADA6-4D79-B571-BB7A39E50808';

/* Update IS-A parent field PlanningPeriod on MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks */
UPDATE [${mjSchema}].[EntityField]
                  SET [IsVirtual]=1,
                      [Type]='nvarchar',
                      [Length]=100,
                      [Precision]=0,
                      [Scale]=0,
                      [AllowsNull]=1,
                      [AllowUpdateAPI]=1,
                      [IncludeRelatedEntityNameFieldInBaseView]=0,
                      [RelatedEntityID]=NULL,
                      [RelatedEntityFieldName]=NULL,
                      [RelatedEntityDisplayType]='Search'
                  WHERE [ID]='74340CB6-2CF9-4078-B056-BCEC5AB63A3A';

/* Update IS-A parent field CheckInCadence on MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks */
UPDATE [${mjSchema}].[EntityField]
                  SET [IsVirtual]=1,
                      [Type]='nvarchar',
                      [Length]=40,
                      [Precision]=0,
                      [Scale]=0,
                      [AllowsNull]=1,
                      [AllowUpdateAPI]=1,
                      [IncludeRelatedEntityNameFieldInBaseView]=0,
                      [RelatedEntityID]=NULL,
                      [RelatedEntityFieldName]=NULL,
                      [RelatedEntityDisplayType]='Search'
                  WHERE [ID]='74337FD7-6B08-4EE4-AFE9-5C97EE684B19';

/* Update IS-A parent field LastCheckInAt on MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks */
UPDATE [${mjSchema}].[EntityField]
                  SET [IsVirtual]=1,
                      [Type]='datetimeoffset',
                      [Length]=10,
                      [Precision]=34,
                      [Scale]=7,
                      [AllowsNull]=1,
                      [AllowUpdateAPI]=1,
                      [IncludeRelatedEntityNameFieldInBaseView]=0,
                      [RelatedEntityID]=NULL,
                      [RelatedEntityFieldName]=NULL,
                      [RelatedEntityDisplayType]='Search'
                  WHERE [ID]='8CAF3BC8-B357-4B60-AD0E-76B818806CCC';

/* Update IS-A parent field NextCheckInDueAt on MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks */
UPDATE [${mjSchema}].[EntityField]
                  SET [IsVirtual]=1,
                      [Type]='datetimeoffset',
                      [Length]=10,
                      [Precision]=34,
                      [Scale]=7,
                      [AllowsNull]=1,
                      [AllowUpdateAPI]=1,
                      [IncludeRelatedEntityNameFieldInBaseView]=0,
                      [RelatedEntityID]=NULL,
                      [RelatedEntityFieldName]=NULL,
                      [RelatedEntityDisplayType]='Search'
                  WHERE [ID]='8DB46A9C-8567-43D3-85E1-AF3174F6628F';

/* Update entity timestamp for MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks after IS-A field sync */
UPDATE [${mjSchema}].[Entity] SET [__mj_UpdatedAt]=GETUTCDATE() WHERE ID='A6B673F8-43BC-4875-AFF6-AC620592822E';

/* SQL text to set default column width where needed */
EXEC [${mjSchema}].[spSetDefaultColumnWidthWhereNeeded] @ExcludedSchemaNames='', @IncludedSchemaNames='${flyway:defaultSchema}';

/* Set field properties for entity */

               UPDATE [${mjSchema}].[EntityField]
               SET IsNameField = 0
               WHERE ID = '8A9B093F-91D1-4991-9069-4F2F36AD9181'
               AND AutoUpdateIsNameField = 1;

               UPDATE [${mjSchema}].[EntityField]
               SET DefaultInView = 1
               WHERE ID = 'A65EDA96-67F2-4C99-B96C-65388A906AAC'
               AND AutoUpdateDefaultInView = 1;

               UPDATE [${mjSchema}].[EntityField]
               SET DefaultInView = 1
               WHERE ID = 'D70ABD8C-2AC1-44E1-AEA2-945D6DAA9ED7'
               AND AutoUpdateDefaultInView = 1;

               UPDATE [${mjSchema}].[EntityField]
               SET DefaultInView = 1
               WHERE ID = 'B83A675F-795C-47ED-81F4-CBBD5FF4D929'
               AND AutoUpdateDefaultInView = 1;

               UPDATE [${mjSchema}].[EntityField]
               SET UserSearchPredicateAPI = 'BeginsWith'
               WHERE ID = '5F177501-4505-4DFE-9813-9B930DFE80C5'
               AND AutoUpdateUserSearchPredicate = 1;

/* Set field properties for entity */

               UPDATE [${mjSchema}].[EntityField]
               SET DefaultInView = 1
               WHERE ID = 'CCAE381C-911D-407D-BA0B-05BDB95CABFB'
               AND AutoUpdateDefaultInView = 1;

               UPDATE [${mjSchema}].[EntityField]
               SET UserSearchPredicateAPI = 'BeginsWith'
               WHERE ID = '4BA1A1F6-223E-4E8D-99D0-16448913D993'
               AND AutoUpdateUserSearchPredicate = 1;

/* Set categories for 34 fields */

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks.Name 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Task Details',
   GeneratedFormSection = 'Category'
WHERE 
   ID = '5F177501-4505-4DFE-9813-9B930DFE80C5';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks.Description 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Task Details',
   GeneratedFormSection = 'Category'
WHERE 
   ID = 'ABC08616-BC3E-441F-8E7D-A4274959C326';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks.TypeID 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Task Details',
   GeneratedFormSection = 'Category',
   DisplayName = 'Task Type'
WHERE 
   ID = '104159FF-DB47-414C-A573-22218C8E246E';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks.CategoryID 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Task Details',
   GeneratedFormSection = 'Category',
   DisplayName = 'Category'
WHERE 
   ID = 'BEE37B1E-65C9-4B3B-8E1E-52307578D3F3';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks.ParentID 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Task Details',
   GeneratedFormSection = 'Category',
   DisplayName = 'Parent Task'
WHERE 
   ID = 'B3889303-F49F-4D92-853F-65AC124F359D';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks.Status 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Task Details',
   GeneratedFormSection = 'Category'
WHERE 
   ID = 'A65EDA96-67F2-4C99-B96C-65388A906AAC';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks.Priority 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Task Details',
   GeneratedFormSection = 'Category'
WHERE 
   ID = 'D70ABD8C-2AC1-44E1-AEA2-945D6DAA9ED7';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks.Sequence 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Task Details',
   GeneratedFormSection = 'Category'
WHERE 
   ID = '77EC9524-1745-4341-B0FD-EBE74E176E4A';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks.BlockedReason 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Task Details',
   GeneratedFormSection = 'Category'
WHERE 
   ID = 'EAF33611-EB3D-4621-BC57-292F137E43C4';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks.CompletionNotes 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Task Details',
   GeneratedFormSection = 'Category'
WHERE 
   ID = 'E856766E-55A2-4DE8-990E-86D7D1E7056A';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks.CreatedByPersonID 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Task Details',
   GeneratedFormSection = 'Category',
   DisplayName = 'Created By Person'
WHERE 
   ID = '6199AC88-26D6-4320-8B59-952C0E1945EA';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks.TaskTypeStatusID 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Task Details',
   GeneratedFormSection = 'Category',
   DisplayName = 'Task Type Status'
WHERE 
   ID = 'F0ABFE53-246F-41D8-B25A-E462FC412615';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks.HealthStatus 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Task Details',
   GeneratedFormSection = 'Category'
WHERE 
   ID = '8EFE7EAC-45DB-4B89-9221-2B19B99068B9';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks.ConfidenceScore 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Task Details',
   GeneratedFormSection = 'Category'
WHERE 
   ID = 'EA927E59-FFD9-4F5C-91BC-DB57A268CB3F';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks.PlanningPeriod 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Task Details',
   GeneratedFormSection = 'Category'
WHERE 
   ID = 'E4A34B92-D140-405D-9AB7-1003EDED8BE8';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks.CheckInCadence 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Task Details',
   GeneratedFormSection = 'Category',
   DisplayName = 'Check-In Cadence'
WHERE 
   ID = 'C652B089-04BD-4A3E-BBAD-07D5D2474568';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks.StartedAt 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Task Schedule and Metrics',
   GeneratedFormSection = 'Category'
WHERE 
   ID = 'E28AF650-AB4A-45BB-A94D-814467A2536D';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks.DueAt 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Task Schedule and Metrics',
   GeneratedFormSection = 'Category'
WHERE 
   ID = 'B83A675F-795C-47ED-81F4-CBBD5FF4D929';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks.CompletedAt 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Task Schedule and Metrics',
   GeneratedFormSection = 'Category'
WHERE 
   ID = 'CEF54E7E-100C-432E-9D83-FE29B47C5F73';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks.HoursEstimated 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Task Schedule and Metrics',
   GeneratedFormSection = 'Category'
WHERE 
   ID = 'C9363AE8-2C58-46C5-B437-C7D26A02C353';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks.HoursActual 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Task Schedule and Metrics',
   GeneratedFormSection = 'Category'
WHERE 
   ID = '3F2F697F-56E2-450F-BF03-77DC470D5754';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks.PercentComplete 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Task Schedule and Metrics',
   GeneratedFormSection = 'Category'
WHERE 
   ID = '732FA3A2-4E55-44C0-9F6B-FE50B894C27E';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks.OverdueNotifiedAt 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Task Schedule and Metrics',
   GeneratedFormSection = 'Category'
WHERE 
   ID = 'CE26B855-64AC-45B7-9549-39AC48FA7FA8';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks.PredictedSLABreachProbability 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Task Schedule and Metrics',
   GeneratedFormSection = 'Category'
WHERE 
   ID = 'D1AB1A5C-A1EE-4EC5-95FE-4FD4C8AB7630';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks.PredictedSLARiskBand 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Task Schedule and Metrics',
   GeneratedFormSection = 'Category'
WHERE 
   ID = 'D2574DDB-325F-473D-997A-66CC43309934';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks.PredictedSLAScoredAt 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Task Schedule and Metrics',
   GeneratedFormSection = 'Category'
WHERE 
   ID = '947C6BAE-94D3-4999-AC0F-DAFE404E008F';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks.BaselineValue 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Task Schedule and Metrics',
   GeneratedFormSection = 'Category'
WHERE 
   ID = '835E5643-810D-4B4E-8E83-E9595428437C';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks.TargetValue 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Task Schedule and Metrics',
   GeneratedFormSection = 'Category'
WHERE 
   ID = '77DD9516-90EF-4855-9CF7-CA0D81B59A8F';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks.CurrentValue 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Task Schedule and Metrics',
   GeneratedFormSection = 'Category'
WHERE 
   ID = 'AF810BE2-BA61-46DD-ADEC-7F3FE7FB35E2';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks.UnitOfMeasure 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Task Schedule and Metrics',
   GeneratedFormSection = 'Category'
WHERE 
   ID = 'FD6FA1E2-DA35-409A-9116-36640D818333';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks.MetricDirection 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Task Schedule and Metrics',
   GeneratedFormSection = 'Category'
WHERE 
   ID = '86B721D5-8AA2-4199-AEF7-C933A6BA52FF';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks.RollupWeight 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Task Schedule and Metrics',
   GeneratedFormSection = 'Category'
WHERE 
   ID = '03F75DAD-73A6-4C9C-B473-50AF0F4DFDBF';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks.LastCheckInAt 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Task Schedule and Metrics',
   GeneratedFormSection = 'Category',
   DisplayName = 'Last Check-In At'
WHERE 
   ID = '6FE24C88-2E9C-49E9-AFD2-4E0D428F7C50';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks.NextCheckInDueAt 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Task Schedule and Metrics',
   GeneratedFormSection = 'Category',
   DisplayName = 'Next Check-In Due At'
WHERE 
   ID = 'C4AA4959-C523-450D-95C7-F7C4119F6211';

/* Update FieldCategoryInfo setting for entity */

                  UPDATE [${mjSchema}].[EntitySetting]
                  SET [Value] = '{
  "GitHub Issue Details": {
    "description": "Core GitHub issue metadata, identifiers, URLs, state, and labels",
    "icon": "fab fa-github"
  },
  "Milestone and Timeline": {
    "description": "GitHub milestone assignments and associated target due dates",
    "icon": "fa fa-calendar-alt"
  },
  "Sync and Audit Information": {
    "description": "External synchronization tracking keys, content hashes, and upstream timestamps",
    "icon": "fa fa-sync"
  },
  "System Metadata": {
    "description": "System-managed audit and primary key fields",
    "icon": "fa fa-cog"
  },
  "Task Details": {
    "description": "Core task details inherited from the Tasks entity",
    "icon": "fa fa-tasks",
    "inheritedFromEntityID": "B348FFA2-B1A7-4AC2-B6FD-F4E0C0697466",
    "inheritedFromEntityName": "MJ_BizApps_Tasks: Tasks"
  },
  "Task Schedule and Metrics": {
    "description": "Schedule, progress metrics, and SLAs inherited from the Tasks entity",
    "icon": "fa fa-chart-line",
    "inheritedFromEntityID": "B348FFA2-B1A7-4AC2-B6FD-F4E0C0697466",
    "inheritedFromEntityName": "MJ_BizApps_Tasks: Tasks"
  }
}', [__mj_UpdatedAt] = GETUTCDATE()
                  WHERE [EntityID] = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605' AND [Name] = 'FieldCategoryInfo';

/* Update FieldCategoryIcons setting (legacy) */

                  UPDATE [${mjSchema}].[EntitySetting]
                  SET [Value] = '{
  "GitHub Issue Details": "fab fa-github",
  "Milestone and Timeline": "fa fa-calendar-alt",
  "Sync and Audit Information": "fa fa-sync",
  "System Metadata": "fa fa-cog",
  "Task Details": "fa fa-tasks",
  "Task Schedule and Metrics": "fa fa-chart-line"
}', [__mj_UpdatedAt] = GETUTCDATE()
                  WHERE [EntityID] = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605' AND [Name] = 'FieldCategoryIcons';

/* Set categories for 34 fields */

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks.Name 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Task Details',
   GeneratedFormSection = 'Category'
WHERE 
   ID = '4BA1A1F6-223E-4E8D-99D0-16448913D993';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks.Description 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Task Details',
   GeneratedFormSection = 'Category'
WHERE 
   ID = '504CE539-0CC4-47D3-AD5D-120907A421ED';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks.TypeID 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Task Details',
   GeneratedFormSection = 'Category',
   DisplayName = 'Type'
WHERE 
   ID = 'A26A18FA-8F34-423E-AC94-3F3B47AC87C9';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks.CategoryID 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Task Details',
   GeneratedFormSection = 'Category',
   DisplayName = 'Category'
WHERE 
   ID = '2F5E2D1C-F10A-42F0-9AD0-71956D6ED9C5';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks.ParentID 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Task Details',
   GeneratedFormSection = 'Category',
   DisplayName = 'Parent Task'
WHERE 
   ID = '8A12D74A-F61C-4669-AB9A-F83FD4418679';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks.Status 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Task Status and Workflow',
   GeneratedFormSection = 'Category'
WHERE 
   ID = 'CCAE381C-911D-407D-BA0B-05BDB95CABFB';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks.Priority 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Task Status and Workflow',
   GeneratedFormSection = 'Category'
WHERE 
   ID = '10503F3A-EAAD-4EFA-AA23-ED42AF9335F2';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks.StartedAt 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Task Timeline',
   GeneratedFormSection = 'Category'
WHERE 
   ID = 'CFD64243-AD98-4583-9393-E2A86AA869FE';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks.DueAt 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Task Timeline',
   GeneratedFormSection = 'Category'
WHERE 
   ID = 'D6A809C0-B643-4045-BBBC-43420E9C4D9D';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks.CompletedAt 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Task Timeline',
   GeneratedFormSection = 'Category'
WHERE 
   ID = 'AEB061C9-C5B7-429C-BBFB-BFE7F0B9B8DB';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks.HoursEstimated 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Task Effort and Metrics',
   GeneratedFormSection = 'Category'
WHERE 
   ID = '05869A56-0E75-4721-8FDF-4969DF401C85';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks.HoursActual 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Task Effort and Metrics',
   GeneratedFormSection = 'Category'
WHERE 
   ID = '5025C924-87BC-4045-B5B2-AF280B8BF9D5';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks.PercentComplete 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Task Effort and Metrics',
   GeneratedFormSection = 'Category'
WHERE 
   ID = 'C0C67A45-F9F6-4962-A5DC-2176F8EF1F0A';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks.Sequence 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Task Details',
   GeneratedFormSection = 'Category'
WHERE 
   ID = 'C1D1EB47-D5AF-42B7-926E-38440E14B0B0';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks.BlockedReason 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Task Status and Workflow',
   GeneratedFormSection = 'Category'
WHERE 
   ID = '3365149D-DB81-4D9D-BB29-2D491C6E86FA';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks.CompletionNotes 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Task Details',
   GeneratedFormSection = 'Category'
WHERE 
   ID = '61B50EAD-8C53-4C9F-96AA-76ECDEDAE434';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks.CreatedByPersonID 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Task Details',
   GeneratedFormSection = 'Category',
   DisplayName = 'Created By Person'
WHERE 
   ID = 'FB407166-23F9-4BB3-98FB-599F619BB218';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks.OverdueNotifiedAt 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Task Timeline',
   GeneratedFormSection = 'Category'
WHERE 
   ID = '23302EB0-8C39-40D4-B309-FAF86854AEE2';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks.TaskTypeStatusID 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Task Status and Workflow',
   GeneratedFormSection = 'Category',
   DisplayName = 'Task Type Status'
WHERE 
   ID = '84A6F1CB-4453-4651-B20F-58F0A29789C8';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks.PredictedSLABreachProbability 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Task SLA and Risk',
   GeneratedFormSection = 'Category'
WHERE 
   ID = '9AAF8300-10B1-4C0C-8A05-CE90F22C22E4';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks.PredictedSLARiskBand 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Task SLA and Risk',
   GeneratedFormSection = 'Category'
WHERE 
   ID = '95D95CDC-AECE-417E-A7EB-BB87A0197A3E';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks.PredictedSLAScoredAt 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Task SLA and Risk',
   GeneratedFormSection = 'Category'
WHERE 
   ID = '6EBF3400-38A4-4CE7-A1E8-76DFBB328821';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks.HealthStatus 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Task Status and Workflow',
   GeneratedFormSection = 'Category'
WHERE 
   ID = 'FF834CC2-1FD6-438E-BD22-82F6BEA0EAF2';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks.ConfidenceScore 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Task Effort and Metrics',
   GeneratedFormSection = 'Category'
WHERE 
   ID = '6B700581-9114-4D4D-87FD-7803E6990FE6';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks.BaselineValue 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Task Effort and Metrics',
   GeneratedFormSection = 'Category'
WHERE 
   ID = '2FAB02DE-F972-461E-9B21-4387520AF9B2';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks.TargetValue 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Task Effort and Metrics',
   GeneratedFormSection = 'Category'
WHERE 
   ID = 'D9BDA046-A66F-4965-B964-56A2833E4000';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks.CurrentValue 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Task Effort and Metrics',
   GeneratedFormSection = 'Category'
WHERE 
   ID = 'D568F0DF-CF9A-41D6-8ECE-5ED935AFFF02';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks.UnitOfMeasure 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Task Effort and Metrics',
   GeneratedFormSection = 'Category'
WHERE 
   ID = 'A15515CE-2505-4A75-909B-996D159BF8B3';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks.MetricDirection 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Task Effort and Metrics',
   GeneratedFormSection = 'Category'
WHERE 
   ID = '72A1ACE2-6BD6-4861-9DE0-F617873736D7';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks.RollupWeight 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Task Effort and Metrics',
   GeneratedFormSection = 'Category'
WHERE 
   ID = '32734BDB-ADA6-4D79-B571-BB7A39E50808';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks.PlanningPeriod 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Task Timeline',
   GeneratedFormSection = 'Category'
WHERE 
   ID = '74340CB6-2CF9-4078-B056-BCEC5AB63A3A';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks.CheckInCadence 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Task Timeline',
   GeneratedFormSection = 'Category'
WHERE 
   ID = '74337FD7-6B08-4EE4-AFE9-5C97EE684B19';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks.LastCheckInAt 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Task Timeline',
   GeneratedFormSection = 'Category'
WHERE 
   ID = '8CAF3BC8-B357-4B60-AD0E-76B818806CCC';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks.NextCheckInDueAt 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Task Timeline',
   GeneratedFormSection = 'Category'
WHERE 
   ID = '8DB46A9C-8567-43D3-85E1-AF3174F6628F';

/* Update FieldCategoryInfo setting for entity */

                  UPDATE [${mjSchema}].[EntitySetting]
                  SET [Value] = '{
  "Branch and Commit Info": {
    "description": "Source and target branches alongside head commit information",
    "icon": "fa fa-code"
  },
  "Dates and Timeline": {
    "description": "Timestamps for milestones, merges, and synchronization events",
    "icon": "fa fa-calendar-alt"
  },
  "Diff Metrics": {
    "description": "Code diff metrics including changed files, additions, and deletions",
    "icon": "fa fa-chart-bar"
  },
  "Pull Request Details": {
    "description": "Core pull request metadata, identifiers, links, and relationships",
    "icon": "fa fa-code-branch"
  },
  "Status and Workflow": {
    "description": "Lifecycle state, draft status, review decisions, and CI check statuses",
    "icon": "fa fa-tasks"
  },
  "System Metadata": {
    "description": "System-managed audit trails and sync hashes",
    "icon": "fa fa-cog"
  },
  "Task Details": {
    "description": "Core descriptive fields inherited from Tasks",
    "icon": "fa fa-info-circle",
    "inheritedFromEntityID": "B348FFA2-B1A7-4AC2-B6FD-F4E0C0697466",
    "inheritedFromEntityName": "MJ_BizApps_Tasks: Tasks"
  },
  "Task Effort and Metrics": {
    "description": "Effort tracking and metric fields inherited from Tasks",
    "icon": "fa fa-chart-bar",
    "inheritedFromEntityID": "B348FFA2-B1A7-4AC2-B6FD-F4E0C0697466",
    "inheritedFromEntityName": "MJ_BizApps_Tasks: Tasks"
  },
  "Task SLA and Risk": {
    "description": "SLA predictions and risk assessment fields inherited from Tasks",
    "icon": "fa fa-shield-alt",
    "inheritedFromEntityID": "B348FFA2-B1A7-4AC2-B6FD-F4E0C0697466",
    "inheritedFromEntityName": "MJ_BizApps_Tasks: Tasks"
  },
  "Task Status and Workflow": {
    "description": "Status, priority, and workflow fields inherited from Tasks",
    "icon": "fa fa-stream",
    "inheritedFromEntityID": "B348FFA2-B1A7-4AC2-B6FD-F4E0C0697466",
    "inheritedFromEntityName": "MJ_BizApps_Tasks: Tasks"
  },
  "Task Timeline": {
    "description": "Dates, timelines, and check-in fields inherited from Tasks",
    "icon": "fa fa-calendar-alt",
    "inheritedFromEntityID": "B348FFA2-B1A7-4AC2-B6FD-F4E0C0697466",
    "inheritedFromEntityName": "MJ_BizApps_Tasks: Tasks"
  }
}', [__mj_UpdatedAt] = GETUTCDATE()
                  WHERE [EntityID] = 'A6B673F8-43BC-4875-AFF6-AC620592822E' AND [Name] = 'FieldCategoryInfo';

/* Update FieldCategoryIcons setting (legacy) */

                  UPDATE [${mjSchema}].[EntitySetting]
                  SET [Value] = '{
  "Branch and Commit Info": "fa fa-code",
  "Dates and Timeline": "fa fa-calendar-alt",
  "Diff Metrics": "fa fa-chart-bar",
  "Pull Request Details": "fa fa-code-branch",
  "Status and Workflow": "fa fa-tasks",
  "System Metadata": "fa fa-cog",
  "Task Details": "fa fa-info-circle",
  "Task Effort and Metrics": "fa fa-chart-bar",
  "Task SLA and Risk": "fa fa-shield-alt",
  "Task Status and Workflow": "fa fa-stream",
  "Task Timeline": "fa fa-calendar-alt"
}', [__mj_UpdatedAt] = GETUTCDATE()
                  WHERE [EntityID] = 'A6B673F8-43BC-4875-AFF6-AC620592822E' AND [Name] = 'FieldCategoryIcons';
