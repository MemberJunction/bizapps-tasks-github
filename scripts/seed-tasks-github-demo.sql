-- =============================================================================
-- Multi-Domain Idempotent Demo Seed Script: bizapps-tasks-github
-- Seeds 40 realistic rows across 5 tables:
--   1. [__mj_BizAppsTasksGitHub].[GitHubRepository]        (4 repositories)
--   2. [__mj_BizAppsTasks].[Task]                          (16 base tasks)
--   3. [__mj_BizAppsTasksGitHub].[GitHubIssueTask]         (8 issue subtypes)
--   4. [__mj_BizAppsTasksGitHub].[GitHubPullRequestTask]   (8 PR subtypes)
--   5. [__mj_BizAppsTasks].[TaskLink]                      (4 polymorphic links)
--
-- Covers Open, InProgress, Blocked, Completed, and Cancelled task states;
-- open, closed (completed / not_planned), draft, review-required, changes-requested,
-- approved, and merged GitHub Issue / Pull Request lifecycles across multiple repos.
-- =============================================================================

---------------------------------------------------------------------------
-- 1. GitHubRepository (4 tracked & untracked repositories across workflows)
---------------------------------------------------------------------------
IF NOT EXISTS (
    SELECT 1 FROM [__mj_BizAppsTasksGitHub].[GitHubRepository]
    WHERE [ID] = '7A100001-0000-4000-8000-000000000001'
       OR ([Owner] = N'MemberJunction' AND [Name] = N'MJ')
)
    INSERT INTO [__mj_BizAppsTasksGitHub].[GitHubRepository]
        ([ID], [Owner], [Name], [DefaultBranch], [IsTracked], [ImportRule], [InstallationID])
    VALUES
        ('7A100001-0000-4000-8000-000000000001', N'MemberJunction', N'MJ', N'next', 1, N'AssignedOnly', N'inst-mj-core-001');

IF NOT EXISTS (
    SELECT 1 FROM [__mj_BizAppsTasksGitHub].[GitHubRepository]
    WHERE [ID] = '7A100001-0000-4000-8000-000000000002'
       OR ([Owner] = N'MemberJunction' AND [Name] = N'bizapps-tasks')
)
    INSERT INTO [__mj_BizAppsTasksGitHub].[GitHubRepository]
        ([ID], [Owner], [Name], [DefaultBranch], [IsTracked], [ImportRule], [InstallationID])
    VALUES
        ('7A100001-0000-4000-8000-000000000002', N'MemberJunction', N'bizapps-tasks', N'next', 1, N'All', N'inst-bizapps-002');

IF NOT EXISTS (
    SELECT 1 FROM [__mj_BizAppsTasksGitHub].[GitHubRepository]
    WHERE [ID] = '7A100001-0000-4000-8000-000000000003'
       OR ([Owner] = N'MemberJunction' AND [Name] = N'bizapps-tasks-github')
)
    INSERT INTO [__mj_BizAppsTasksGitHub].[GitHubRepository]
        ([ID], [Owner], [Name], [DefaultBranch], [IsTracked], [ImportRule], [InstallationID])
    VALUES
        ('7A100001-0000-4000-8000-000000000003', N'MemberJunction', N'bizapps-tasks-github', N'next', 1, N'All', N'inst-bizapps-003');

IF NOT EXISTS (
    SELECT 1 FROM [__mj_BizAppsTasksGitHub].[GitHubRepository]
    WHERE [ID] = '7A100001-0000-4000-8000-000000000004'
       OR ([Owner] = N'MemberJunction' AND [Name] = N'bizapps-planning')
)
    INSERT INTO [__mj_BizAppsTasksGitHub].[GitHubRepository]
        ([ID], [Owner], [Name], [DefaultBranch], [IsTracked], [ImportRule], [InstallationID])
    VALUES
        ('7A100001-0000-4000-8000-000000000004', N'MemberJunction', N'bizapps-planning', N'next', 0, N'AssignedOnly', NULL);
GO

---------------------------------------------------------------------------
-- 2. Base Task Rows (16 tasks: 8 GITHUB_ISSUE + 8 GITHUB_PR across all statuses)
---------------------------------------------------------------------------
-- 8 Issue base tasks
IF NOT EXISTS (SELECT 1 FROM [__mj_BizAppsTasks].[Task] WHERE [ID] = '7B100001-0000-4000-8000-000000000101')
    INSERT INTO [__mj_BizAppsTasks].[Task] ([ID], [Name], [Description], [TypeID], [Status], [Priority], [PercentComplete], [Sequence], [TaskTypeStatusID], [Visibility])
    VALUES ('7B100001-0000-4000-8000-000000000101', N'Support LimitsConfigResolver override hierarchy in Core', N'Expose strongly-typed limits configuration lookup with Environment and MjConfig precedence.', 'A1D17128-D2BF-4C18-905C-6422B58E6AC1', N'InProgress', N'High', 65, 10, '13B5E78F-D4A0-4BC9-8F19-C37BCBDBE811', N'Standard');

IF NOT EXISTS (SELECT 1 FROM [__mj_BizAppsTasks].[Task] WHERE [ID] = '7B100001-0000-4000-8000-000000000102')
    INSERT INTO [__mj_BizAppsTasks].[Task] ([ID], [Name], [Description], [TypeID], [Status], [Priority], [PercentComplete], [Sequence], [TaskTypeStatusID], [Visibility])
    VALUES ('7B100001-0000-4000-8000-000000000102', N'Add PostgreSQL Flyway parity checks for TaskTypeStatus', N'Ensure PostgreSQL migration converter preserves TaskTypeStatus seed identifiers.', 'A1D17128-D2BF-4C18-905C-6422B58E6AC1', N'Open', N'Medium', 0, 20, '2CB403FB-5217-4E65-AFC2-78A2127D7BDA', N'Standard');

IF NOT EXISTS (SELECT 1 FROM [__mj_BizAppsTasks].[Task] WHERE [ID] = '7B100001-0000-4000-8000-000000000103')
    INSERT INTO [__mj_BizAppsTasks].[Task] ([ID], [Name], [Description], [TypeID], [Status], [Priority], [PercentComplete], [Sequence], [TaskTypeStatusID], [Visibility])
    VALUES ('7B100001-0000-4000-8000-000000000103', N'Verify WCAG keyboard access on hero form panel chips', N'Replace clickable span chips with semantic button elements across GitHub form panels.', 'A1D17128-D2BF-4C18-905C-6422B58E6AC1', N'Open', N'High', 25, 30, 'C308BC86-C335-4614-B78E-CE7654CA143D', N'Standard');

IF NOT EXISTS (SELECT 1 FROM [__mj_BizAppsTasks].[Task] WHERE [ID] = '7B100001-0000-4000-8000-000000000104')
    INSERT INTO [__mj_BizAppsTasks].[Task] ([ID], [Name], [Description], [TypeID], [Status], [Priority], [PercentComplete], [Sequence], [TaskTypeStatusID], [Visibility])
    VALUES ('7B100001-0000-4000-8000-000000000104', N'Harden HMAC-SHA256 webhook signature verification against chunked UTF-8 payloads', N'Verify multi-byte UTF-8 emojis split across HTTP chunks keep exact byte digest parity.', 'A1D17128-D2BF-4C18-905C-6422B58E6AC1', N'Completed', N'Critical', 100, 40, '2CFDFD0E-176C-4304-8BAD-CAAF6D25A3D8', N'Standard');

IF NOT EXISTS (SELECT 1 FROM [__mj_BizAppsTasks].[Task] WHERE [ID] = '7B100001-0000-4000-8000-000000000105')
    INSERT INTO [__mj_BizAppsTasks].[Task] ([ID], [Name], [Description], [TypeID], [Status], [Priority], [PercentComplete], [Sequence], [TaskTypeStatusID], [Visibility])
    VALUES ('7B100001-0000-4000-8000-000000000105', N'Legacy XML webhook envelope support', N'Superseded by application/json HMAC-SHA256 payload standard.', 'A1D17128-D2BF-4C18-905C-6422B58E6AC1', N'Cancelled', N'Low', 0, 50, '31DD4B5E-46E2-44B8-8CDF-EE4908F734A7', N'Standard');

IF NOT EXISTS (SELECT 1 FROM [__mj_BizAppsTasks].[Task] WHERE [ID] = '7B100001-0000-4000-8000-000000000106')
    INSERT INTO [__mj_BizAppsTasks].[Task] ([ID], [Name], [Description], [TypeID], [Status], [Priority], [PercentComplete], [Sequence], [TaskTypeStatusID], [Visibility])
    VALUES ('7B100001-0000-4000-8000-000000000106', N'Add Chief of Staff morning review queue rhythm template', N'Deliver weekday morning digest highlighting stale PR review requests over 24h.', 'A1D17128-D2BF-4C18-905C-6422B58E6AC1', N'Completed', N'High', 100, 60, '2CFDFD0E-176C-4304-8BAD-CAAF6D25A3D8', N'Standard');

IF NOT EXISTS (SELECT 1 FROM [__mj_BizAppsTasks].[Task] WHERE [ID] = '7B100001-0000-4000-8000-000000000107')
    INSERT INTO [__mj_BizAppsTasks].[Task] ([ID], [Name], [Description], [TypeID], [Status], [Priority], [PercentComplete], [Sequence], [TaskTypeStatusID], [Visibility])
    VALUES ('7B100001-0000-4000-8000-000000000107', N'Add planning objective link suggestion inference', N'Suggest parent objective and category on newly synced GitHub issues via MJ Field Suggestions.', 'A1D17128-D2BF-4C18-905C-6422B58E6AC1', N'InProgress', N'Medium', 50, 70, '13B5E78F-D4A0-4BC9-8F19-C37BCBDBE811', N'Standard');

IF NOT EXISTS (SELECT 1 FROM [__mj_BizAppsTasks].[Task] WHERE [ID] = '7B100001-0000-4000-8000-000000000108')
    INSERT INTO [__mj_BizAppsTasks].[Task] ([ID], [Name], [Description], [TypeID], [Status], [Priority], [PercentComplete], [Sequence], [TaskTypeStatusID], [Visibility])
    VALUES ('7B100001-0000-4000-8000-000000000108', N'Expose ConnectorMirror vs GitHubREST badge in Sync Console', N'Indicate whether repository uses @memberjunction/connector-github mirror or REST polling.', 'A1D17128-D2BF-4C18-905C-6422B58E6AC1', N'Open', N'Medium', 10, 80, '2CB403FB-5217-4E65-AFC2-78A2127D7BDA', N'Standard');

-- 8 Pull Request base tasks
IF NOT EXISTS (SELECT 1 FROM [__mj_BizAppsTasks].[Task] WHERE [ID] = '7B100001-0000-4000-8000-000000000201')
    INSERT INTO [__mj_BizAppsTasks].[Task] ([ID], [Name], [Description], [TypeID], [Status], [Priority], [PercentComplete], [Sequence], [TaskTypeStatusID], [Visibility])
    VALUES ('7B100001-0000-4000-8000-000000000201', N'feat(core): route sync and webhook limits through GitHubTasksLimitsResolver', N'Routes RunawayGuard, ResourceGuard, and Tuning limits through GitHubTasksLimitsResolver.', 'A7390C71-90B3-482D-8304-3C61C1E39605', N'InProgress', N'High', 85, 110, 'F331B5F5-B798-4567-8294-02A8F1F6B1E9', N'Standard');

IF NOT EXISTS (SELECT 1 FROM [__mj_BizAppsTasks].[Task] WHERE [ID] = '7B100001-0000-4000-8000-000000000202')
    INSERT INTO [__mj_BizAppsTasks].[Task] ([ID], [Name], [Description], [TypeID], [Status], [Priority], [PercentComplete], [Sequence], [TaskTypeStatusID], [Visibility])
    VALUES ('7B100001-0000-4000-8000-000000000202', N'fix(ui): semantic button elements and keyboard support on panel chips', N'Upgrades interactive chips in Angular hero panels to semantic button elements.', 'A7390C71-90B3-482D-8304-3C61C1E39605', N'InProgress', N'High', 75, 120, 'C1C7F078-8EEC-4769-8712-E264999B8818', N'Standard');

IF NOT EXISTS (SELECT 1 FROM [__mj_BizAppsTasks].[Task] WHERE [ID] = '7B100001-0000-4000-8000-000000000203')
    INSERT INTO [__mj_BizAppsTasks].[Task] ([ID], [Name], [Description], [TypeID], [Status], [Priority], [PercentComplete], [Sequence], [TaskTypeStatusID], [Visibility])
    VALUES ('7B100001-0000-4000-8000-000000000203', N'feat(webhooks): raw UTF-8 stream buffering and fail-closed verification', N'Captures exact raw request buffer ahead of Express JSON parsers.', 'A7390C71-90B3-482D-8304-3C61C1E39605', N'Completed', N'Critical', 100, 130, '80CC4643-3EC2-437C-A525-DC92BF944471', N'Standard');

IF NOT EXISTS (SELECT 1 FROM [__mj_BizAppsTasks].[Task] WHERE [ID] = '7B100001-0000-4000-8000-000000000204')
    INSERT INTO [__mj_BizAppsTasks].[Task] ([ID], [Name], [Description], [TypeID], [Status], [Priority], [PercentComplete], [Sequence], [TaskTypeStatusID], [Visibility])
    VALUES ('7B100001-0000-4000-8000-000000000204', N'feat(cos): add GetMyGitHubPRs and GetGitHubReviewsWaitingOnMe actions', N'Implements Chief of Staff read tools and weekday review-queue digest.', 'A7390C71-90B3-482D-8304-3C61C1E39605', N'Completed', N'High', 100, 140, '80CC4643-3EC2-437C-A525-DC92BF944471', N'Standard');

IF NOT EXISTS (SELECT 1 FROM [__mj_BizAppsTasks].[Task] WHERE [ID] = '7B100001-0000-4000-8000-000000000205')
    INSERT INTO [__mj_BizAppsTasks].[Task] ([ID], [Name], [Description], [TypeID], [Status], [Priority], [PercentComplete], [Sequence], [TaskTypeStatusID], [Visibility])
    VALUES ('7B100001-0000-4000-8000-000000000205', N'wip: experimental GraphQL subscription relay for PR checks', N'Draft exploration for GraphQL check-suite subscriptions.', 'A7390C71-90B3-482D-8304-3C61C1E39605', N'InProgress', N'Low', 20, 150, '9B867CEF-0AAB-4CE4-9066-20222D47288D', N'Standard');

IF NOT EXISTS (SELECT 1 FROM [__mj_BizAppsTasks].[Task] WHERE [ID] = '7B100001-0000-4000-8000-000000000206')
    INSERT INTO [__mj_BizAppsTasks].[Task] ([ID], [Name], [Description], [TypeID], [Status], [Priority], [PercentComplete], [Sequence], [TaskTypeStatusID], [Visibility])
    VALUES ('7B100001-0000-4000-8000-000000000206', N'fix(sync): resolve reviewer feedback on transaction rollback handling', N'Requires addressing reviewer comment on transaction commit boundary.', 'A7390C71-90B3-482D-8304-3C61C1E39605', N'Blocked', N'High', 60, 160, '7CA28F79-0C6C-4781-BA81-77651BE6F65A', N'Standard');

IF NOT EXISTS (SELECT 1 FROM [__mj_BizAppsTasks].[Task] WHERE [ID] = '7B100001-0000-4000-8000-000000000207')
    INSERT INTO [__mj_BizAppsTasks].[Task] ([ID], [Name], [Description], [TypeID], [Status], [Priority], [PercentComplete], [Sequence], [TaskTypeStatusID], [Visibility])
    VALUES ('7B100001-0000-4000-8000-000000000207', N'chore: prototype legacy polling adapter', N'Closed without merge after ConnectorMirror architecture decision.', 'A7390C71-90B3-482D-8304-3C61C1E39605', N'Cancelled', N'Low', 0, 170, '2D345E51-16D2-47C3-ABD7-C32A233CE55F', N'Standard');

IF NOT EXISTS (SELECT 1 FROM [__mj_BizAppsTasks].[Task] WHERE [ID] = '7B100001-0000-4000-8000-000000000208')
    INSERT INTO [__mj_BizAppsTasks].[Task] ([ID], [Name], [Description], [TypeID], [Status], [Priority], [PercentComplete], [Sequence], [TaskTypeStatusID], [Visibility])
    VALUES ('7B100001-0000-4000-8000-000000000208', N'feat(planning): align GitHub issue milestones with OKR planning periods', N'Maps GitHub milestone due dates onto BizApps Planning quarters.', 'A7390C71-90B3-482D-8304-3C61C1E39605', N'Open', N'Medium', 40, 180, 'E97F643F-129A-403D-9DED-C91CB68DE098', N'Standard');
GO

---------------------------------------------------------------------------
-- 3. GitHubIssueTask Subtypes (8 rows spanning open, closed/completed, closed/not_planned)
---------------------------------------------------------------------------
IF NOT EXISTS (
    SELECT 1 FROM [__mj_BizAppsTasksGitHub].[GitHubIssueTask]
    WHERE [ID] = '7B100001-0000-4000-8000-000000000101' OR [NodeID] = N'I_kwDOSeedIssue101'
)
    INSERT INTO [__mj_BizAppsTasksGitHub].[GitHubIssueTask]
        ([ID], [RepositoryID], [Number], [NodeID], [HtmlURL], [State], [StateReason], [Labels], [Milestone], [AuthorLogin], [BodyHash])
    VALUES
        ('7B100001-0000-4000-8000-000000000101', '7A100001-0000-4000-8000-000000000001', 101, N'I_kwDOSeedIssue101', N'https://github.com/MemberJunction/MJ/issues/101', N'open', NULL, N'["core","limits","epic-1"]', N'v6.3', N'octocat', N'seed-hash-issue-101');

IF NOT EXISTS (
    SELECT 1 FROM [__mj_BizAppsTasksGitHub].[GitHubIssueTask]
    WHERE [ID] = '7B100001-0000-4000-8000-000000000102' OR [NodeID] = N'I_kwDOSeedIssue102'
)
    INSERT INTO [__mj_BizAppsTasksGitHub].[GitHubIssueTask]
        ([ID], [RepositoryID], [Number], [NodeID], [HtmlURL], [State], [StateReason], [Labels], [Milestone], [AuthorLogin], [BodyHash])
    VALUES
        ('7B100001-0000-4000-8000-000000000102', '7A100001-0000-4000-8000-000000000002', 102, N'I_kwDOSeedIssue102', N'https://github.com/MemberJunction/bizapps-tasks/issues/102', N'open', NULL, N'["migrations","postgres"]', N'v1.16', N'adalovelace', N'seed-hash-issue-102');

IF NOT EXISTS (
    SELECT 1 FROM [__mj_BizAppsTasksGitHub].[GitHubIssueTask]
    WHERE [ID] = '7B100001-0000-4000-8000-000000000103' OR [NodeID] = N'I_kwDOSeedIssue103'
)
    INSERT INTO [__mj_BizAppsTasksGitHub].[GitHubIssueTask]
        ([ID], [RepositoryID], [Number], [NodeID], [HtmlURL], [State], [StateReason], [Labels], [Milestone], [AuthorLogin], [BodyHash])
    VALUES
        ('7B100001-0000-4000-8000-000000000103', '7A100001-0000-4000-8000-000000000003', 103, N'I_kwDOSeedIssue103', N'https://github.com/MemberJunction/bizapps-tasks-github/issues/103', N'open', NULL, N'["a11y","angular","ui"]', N'v1.0', N'gracehopper', N'seed-hash-issue-103');

IF NOT EXISTS (
    SELECT 1 FROM [__mj_BizAppsTasksGitHub].[GitHubIssueTask]
    WHERE [ID] = '7B100001-0000-4000-8000-000000000104' OR [NodeID] = N'I_kwDOSeedIssue104'
)
    INSERT INTO [__mj_BizAppsTasksGitHub].[GitHubIssueTask]
        ([ID], [RepositoryID], [Number], [NodeID], [HtmlURL], [State], [StateReason], [Labels], [Milestone], [AuthorLogin], [BodyHash])
    VALUES
        ('7B100001-0000-4000-8000-000000000104', '7A100001-0000-4000-8000-000000000003', 104, N'I_kwDOSeedIssue104', N'https://github.com/MemberJunction/bizapps-tasks-github/issues/104', N'closed', N'completed', N'["security","webhooks"]', N'v1.0', N'octocat', N'seed-hash-issue-104');

IF NOT EXISTS (
    SELECT 1 FROM [__mj_BizAppsTasksGitHub].[GitHubIssueTask]
    WHERE [ID] = '7B100001-0000-4000-8000-000000000105' OR [NodeID] = N'I_kwDOSeedIssue105'
)
    INSERT INTO [__mj_BizAppsTasksGitHub].[GitHubIssueTask]
        ([ID], [RepositoryID], [Number], [NodeID], [HtmlURL], [State], [StateReason], [Labels], [Milestone], [AuthorLogin], [BodyHash])
    VALUES
        ('7B100001-0000-4000-8000-000000000105', '7A100001-0000-4000-8000-000000000003', 105, N'I_kwDOSeedIssue105', N'https://github.com/MemberJunction/bizapps-tasks-github/issues/105', N'closed', N'not_planned', N'["wontfix","webhooks"]', NULL, N'octocat', N'seed-hash-issue-105');

IF NOT EXISTS (
    SELECT 1 FROM [__mj_BizAppsTasksGitHub].[GitHubIssueTask]
    WHERE [ID] = '7B100001-0000-4000-8000-000000000106' OR [NodeID] = N'I_kwDOSeedIssue106'
)
    INSERT INTO [__mj_BizAppsTasksGitHub].[GitHubIssueTask]
        ([ID], [RepositoryID], [Number], [NodeID], [HtmlURL], [State], [StateReason], [Labels], [Milestone], [AuthorLogin], [BodyHash])
    VALUES
        ('7B100001-0000-4000-8000-000000000106', '7A100001-0000-4000-8000-000000000003', 106, N'I_kwDOSeedIssue106', N'https://github.com/MemberJunction/bizapps-tasks-github/issues/106', N'closed', N'completed', N'["cos","skills"]', N'v1.0', N'adalovelace', N'seed-hash-issue-106');

IF NOT EXISTS (
    SELECT 1 FROM [__mj_BizAppsTasksGitHub].[GitHubIssueTask]
    WHERE [ID] = '7B100001-0000-4000-8000-000000000107' OR [NodeID] = N'I_kwDOSeedIssue107'
)
    INSERT INTO [__mj_BizAppsTasksGitHub].[GitHubIssueTask]
        ([ID], [RepositoryID], [Number], [NodeID], [HtmlURL], [State], [StateReason], [Labels], [Milestone], [AuthorLogin], [BodyHash])
    VALUES
        ('7B100001-0000-4000-8000-000000000107', '7A100001-0000-4000-8000-000000000004', 107, N'I_kwDOSeedIssue107', N'https://github.com/MemberJunction/bizapps-planning/issues/107', N'open', NULL, N'["ai","field-suggestions"]', N'FY27-Q1', N'gracehopper', N'seed-hash-issue-107');

IF NOT EXISTS (
    SELECT 1 FROM [__mj_BizAppsTasksGitHub].[GitHubIssueTask]
    WHERE [ID] = '7B100001-0000-4000-8000-000000000108' OR [NodeID] = N'I_kwDOSeedIssue108'
)
    INSERT INTO [__mj_BizAppsTasksGitHub].[GitHubIssueTask]
        ([ID], [RepositoryID], [Number], [NodeID], [HtmlURL], [State], [StateReason], [Labels], [Milestone], [AuthorLogin], [BodyHash])
    VALUES
        ('7B100001-0000-4000-8000-000000000108', '7A100001-0000-4000-8000-000000000003', 108, N'I_kwDOSeedIssue108', N'https://github.com/MemberJunction/bizapps-tasks-github/issues/108', N'open', NULL, N'["ui","connector"]', N'v1.0', N'octocat', N'seed-hash-issue-108');
GO

---------------------------------------------------------------------------
-- 4. GitHubPullRequestTask Subtypes (8 rows spanning open, draft, merged, closed)
---------------------------------------------------------------------------
IF NOT EXISTS (
    SELECT 1 FROM [__mj_BizAppsTasksGitHub].[GitHubPullRequestTask]
    WHERE [ID] = '7B100001-0000-4000-8000-000000000201' OR [NodeID] = N'PR_kwDOSeedPR201'
)
    INSERT INTO [__mj_BizAppsTasksGitHub].[GitHubPullRequestTask]
        ([ID], [RepositoryID], [Number], [NodeID], [HtmlURL], [State], [IsDraft], [HeadBranch], [HeadSha], [BaseBranch], [AuthorLogin], [ReviewDecision], [ChecksStatus], [ChangedFiles], [Additions], [Deletions], [Labels], [Milestone], [MergedAt], [LinkedIssueTaskID])
    VALUES
        ('7B100001-0000-4000-8000-000000000201', '7A100001-0000-4000-8000-000000000003', 201, N'PR_kwDOSeedPR201', N'https://github.com/MemberJunction/bizapps-tasks-github/pull/201', N'open', 0, N'factory/limits-sweep', N'57d14b19c830a3717ea9004e26f02532d618e95b', N'next', N'adalovelace', N'APPROVED', N'Passing', 16, 2172, 92, N'["limits","core"]', N'v1.0', NULL, '7B100001-0000-4000-8000-000000000101');

IF NOT EXISTS (
    SELECT 1 FROM [__mj_BizAppsTasksGitHub].[GitHubPullRequestTask]
    WHERE [ID] = '7B100001-0000-4000-8000-000000000202' OR [NodeID] = N'PR_kwDOSeedPR202'
)
    INSERT INTO [__mj_BizAppsTasksGitHub].[GitHubPullRequestTask]
        ([ID], [RepositoryID], [Number], [NodeID], [HtmlURL], [State], [IsDraft], [HeadBranch], [HeadSha], [BaseBranch], [AuthorLogin], [ReviewDecision], [ChecksStatus], [ChangedFiles], [Additions], [Deletions], [Labels], [Milestone], [MergedAt], [LinkedIssueTaskID])
    VALUES
        ('7B100001-0000-4000-8000-000000000202', '7A100001-0000-4000-8000-000000000003', 202, N'PR_kwDOSeedPR202', N'https://github.com/MemberJunction/bizapps-tasks-github/pull/202', N'open', 0, N'fix/wcag-hero-buttons', N'a1b2c3d4e5f60718293a4b5c6d7e8f9012345678', N'next', N'gracehopper', N'REVIEW_REQUIRED', N'Passing', 4, 48, 36, N'["a11y","angular"]', N'v1.0', NULL, '7B100001-0000-4000-8000-000000000103');

IF NOT EXISTS (
    SELECT 1 FROM [__mj_BizAppsTasksGitHub].[GitHubPullRequestTask]
    WHERE [ID] = '7B100001-0000-4000-8000-000000000203' OR [NodeID] = N'PR_kwDOSeedPR203'
)
    INSERT INTO [__mj_BizAppsTasksGitHub].[GitHubPullRequestTask]
        ([ID], [RepositoryID], [Number], [NodeID], [HtmlURL], [State], [IsDraft], [HeadBranch], [HeadSha], [BaseBranch], [AuthorLogin], [ReviewDecision], [ChecksStatus], [ChangedFiles], [Additions], [Deletions], [Labels], [Milestone], [MergedAt], [LinkedIssueTaskID])
    VALUES
        ('7B100001-0000-4000-8000-000000000203', '7A100001-0000-4000-8000-000000000003', 203, N'PR_kwDOSeedPR203', N'https://github.com/MemberJunction/bizapps-tasks-github/pull/203', N'merged', 0, N'feat/hmac-utf8-stream', N'b2c3d4e5f60718293a4b5c6d7e8f901234567890', N'next', N'octocat', N'APPROVED', N'Passing', 5, 480, 42, N'["security","webhooks"]', N'v1.0', '2026-11-18T16:45:00Z', '7B100001-0000-4000-8000-000000000104');

IF NOT EXISTS (
    SELECT 1 FROM [__mj_BizAppsTasksGitHub].[GitHubPullRequestTask]
    WHERE [ID] = '7B100001-0000-4000-8000-000000000204' OR [NodeID] = N'PR_kwDOSeedPR204'
)
    INSERT INTO [__mj_BizAppsTasksGitHub].[GitHubPullRequestTask]
        ([ID], [RepositoryID], [Number], [NodeID], [HtmlURL], [State], [IsDraft], [HeadBranch], [HeadSha], [BaseBranch], [AuthorLogin], [ReviewDecision], [ChecksStatus], [ChangedFiles], [Additions], [Deletions], [Labels], [Milestone], [MergedAt], [LinkedIssueTaskID])
    VALUES
        ('7B100001-0000-4000-8000-000000000204', '7A100001-0000-4000-8000-000000000003', 204, N'PR_kwDOSeedPR204', N'https://github.com/MemberJunction/bizapps-tasks-github/pull/204', N'merged', 0, N'feat/cos-skills-contract', N'c3d4e5f60718293a4b5c6d7e8f90123456789012', N'next', N'adalovelace', N'APPROVED', N'Passing', 11, 940, 28, N'["cos","skills"]', N'v1.0', '2026-11-20T11:20:00Z', '7B100001-0000-4000-8000-000000000106');

IF NOT EXISTS (
    SELECT 1 FROM [__mj_BizAppsTasksGitHub].[GitHubPullRequestTask]
    WHERE [ID] = '7B100001-0000-4000-8000-000000000205' OR [NodeID] = N'PR_kwDOSeedPR205'
)
    INSERT INTO [__mj_BizAppsTasksGitHub].[GitHubPullRequestTask]
        ([ID], [RepositoryID], [Number], [NodeID], [HtmlURL], [State], [IsDraft], [HeadBranch], [HeadSha], [BaseBranch], [AuthorLogin], [ReviewDecision], [ChecksStatus], [ChangedFiles], [Additions], [Deletions], [Labels], [Milestone], [MergedAt], [LinkedIssueTaskID])
    VALUES
        ('7B100001-0000-4000-8000-000000000205', '7A100001-0000-4000-8000-000000000001', 205, N'PR_kwDOSeedPR205', N'https://github.com/MemberJunction/MJ/pull/205', N'open', 1, N'wip/graphql-check-relay', N'd4e5f60718293a4b5c6d7e8f9012345678901234', N'next', N'gracehopper', NULL, N'Pending', 3, 120, 14, N'["wip","graphql"]', NULL, NULL, NULL);

IF NOT EXISTS (
    SELECT 1 FROM [__mj_BizAppsTasksGitHub].[GitHubPullRequestTask]
    WHERE [ID] = '7B100001-0000-4000-8000-000000000206' OR [NodeID] = N'PR_kwDOSeedPR206'
)
    INSERT INTO [__mj_BizAppsTasksGitHub].[GitHubPullRequestTask]
        ([ID], [RepositoryID], [Number], [NodeID], [HtmlURL], [State], [IsDraft], [HeadBranch], [HeadSha], [BaseBranch], [AuthorLogin], [ReviewDecision], [ChecksStatus], [ChangedFiles], [Additions], [Deletions], [Labels], [Milestone], [MergedAt], [LinkedIssueTaskID])
    VALUES
        ('7B100001-0000-4000-8000-000000000206', '7A100001-0000-4000-8000-000000000002', 206, N'PR_kwDOSeedPR206', N'https://github.com/MemberJunction/bizapps-tasks/pull/206', N'open', 0, N'fix/tx-rollback-boundary', N'e5f60718293a4b5c6d7e8f901234567890123456', N'next', N'octocat', N'CHANGES_REQUESTED', N'Failing', 6, 215, 88, N'["bug","transactions"]', N'v1.16', NULL, NULL);

IF NOT EXISTS (
    SELECT 1 FROM [__mj_BizAppsTasksGitHub].[GitHubPullRequestTask]
    WHERE [ID] = '7B100001-0000-4000-8000-000000000207' OR [NodeID] = N'PR_kwDOSeedPR207'
)
    INSERT INTO [__mj_BizAppsTasksGitHub].[GitHubPullRequestTask]
        ([ID], [RepositoryID], [Number], [NodeID], [HtmlURL], [State], [IsDraft], [HeadBranch], [HeadSha], [BaseBranch], [AuthorLogin], [ReviewDecision], [ChecksStatus], [ChangedFiles], [Additions], [Deletions], [Labels], [Milestone], [MergedAt], [LinkedIssueTaskID])
    VALUES
        ('7B100001-0000-4000-8000-000000000207', '7A100001-0000-4000-8000-000000000003', 207, N'PR_kwDOSeedPR207', N'https://github.com/MemberJunction/bizapps-tasks-github/pull/207', N'closed', 0, N'chore/legacy-polling', N'f60718293a4b5c6d7e8f90123456789012345678', N'next', N'octocat', NULL, N'Neutral', 2, 75, 190, N'["deprecated"]', NULL, NULL, '7B100001-0000-4000-8000-000000000105');

IF NOT EXISTS (
    SELECT 1 FROM [__mj_BizAppsTasksGitHub].[GitHubPullRequestTask]
    WHERE [ID] = '7B100001-0000-4000-8000-000000000208' OR [NodeID] = N'PR_kwDOSeedPR208'
)
    INSERT INTO [__mj_BizAppsTasksGitHub].[GitHubPullRequestTask]
        ([ID], [RepositoryID], [Number], [NodeID], [HtmlURL], [State], [IsDraft], [HeadBranch], [HeadSha], [BaseBranch], [AuthorLogin], [ReviewDecision], [ChecksStatus], [ChangedFiles], [Additions], [Deletions], [Labels], [Milestone], [MergedAt], [LinkedIssueTaskID])
    VALUES
        ('7B100001-0000-4000-8000-000000000208', '7A100001-0000-4000-8000-000000000004', 208, N'PR_kwDOSeedPR208', N'https://github.com/MemberJunction/bizapps-planning/pull/208', N'open', 0, N'feat/milestone-okr-align', N'0718293a4b5c6d7e8f901234567890123456789a', N'next', N'adalovelace', N'REVIEW_REQUIRED', N'Passing', 7, 340, 21, N'["planning","okr"]', N'FY27-Q1', NULL, '7B100001-0000-4000-8000-000000000107');
GO

---------------------------------------------------------------------------
-- 5. TaskLink Rows (4 polymorphic TaskLinks associating tasks with repositories/records)
---------------------------------------------------------------------------
DECLARE @GitHubRepoEntityID UNIQUEIDENTIFIER = (
    SELECT TOP 1 [ID] FROM [__mj].[Entity]
    WHERE [Name] = N'MJ_BizApps_Tasks_GitHub: Git Hub Repositories'
);
DECLARE @TaskEntityID UNIQUEIDENTIFIER = (
    SELECT TOP 1 [ID] FROM [__mj].[Entity]
    WHERE [Name] = N'MJ_BizApps_Tasks: Tasks'
);

IF @GitHubRepoEntityID IS NOT NULL
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM [__mj_BizAppsTasks].[TaskLink]
        WHERE [ID] = '7C100001-0000-4000-8000-000000000301'
           OR ([TaskID] = '7B100001-0000-4000-8000-000000000101' AND [EntityID] = @GitHubRepoEntityID AND [RecordID] = N'7A100001-0000-4000-8000-000000000001')
    )
        INSERT INTO [__mj_BizAppsTasks].[TaskLink] ([ID], [TaskID], [EntityID], [RecordID], [Description])
        VALUES ('7C100001-0000-4000-8000-000000000301', '7B100001-0000-4000-8000-000000000101', @GitHubRepoEntityID, N'7A100001-0000-4000-8000-000000000001', N'Primary MJ core repository implementing LimitsConfigResolver');

    IF NOT EXISTS (
        SELECT 1 FROM [__mj_BizAppsTasks].[TaskLink]
        WHERE [ID] = '7C100001-0000-4000-8000-000000000302'
           OR ([TaskID] = '7B100001-0000-4000-8000-000000000201' AND [EntityID] = @GitHubRepoEntityID AND [RecordID] = N'7A100001-0000-4000-8000-000000000003')
    )
        INSERT INTO [__mj_BizAppsTasks].[TaskLink] ([ID], [TaskID], [EntityID], [RecordID], [Description])
        VALUES ('7C100001-0000-4000-8000-000000000302', '7B100001-0000-4000-8000-000000000201', @GitHubRepoEntityID, N'7A100001-0000-4000-8000-000000000003', N'Target repository for GitHubTasksLimitsResolver rollout');
END;

IF @TaskEntityID IS NOT NULL
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM [__mj_BizAppsTasks].[TaskLink]
        WHERE [ID] = '7C100001-0000-4000-8000-000000000303'
           OR ([TaskID] = '7B100001-0000-4000-8000-000000000202' AND [EntityID] = @TaskEntityID AND [RecordID] = N'7B100001-0000-4000-8000-000000000103')
    )
        INSERT INTO [__mj_BizAppsTasks].[TaskLink] ([ID], [TaskID], [EntityID], [RecordID], [Description])
        VALUES ('7C100001-0000-4000-8000-000000000303', '7B100001-0000-4000-8000-000000000202', @TaskEntityID, N'7B100001-0000-4000-8000-000000000103', N'Implements WCAG semantic buttons for issue #103');

    IF NOT EXISTS (
        SELECT 1 FROM [__mj_BizAppsTasks].[TaskLink]
        WHERE [ID] = '7C100001-0000-4000-8000-000000000304'
           OR ([TaskID] = '7B100001-0000-4000-8000-000000000208' AND [EntityID] = @TaskEntityID AND [RecordID] = N'7B100001-0000-4000-8000-000000000107')
    )
        INSERT INTO [__mj_BizAppsTasks].[TaskLink] ([ID], [TaskID], [EntityID], [RecordID], [Description])
        VALUES ('7C100001-0000-4000-8000-000000000304', '7B100001-0000-4000-8000-000000000208', @TaskEntityID, N'7B100001-0000-4000-8000-000000000107', N'Aligns milestone scheduling with issue #107');
END;
GO
