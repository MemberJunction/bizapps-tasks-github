---
"@mj-biz-apps/tasks-github-entities": minor
"@mj-biz-apps/tasks-github-core": minor
"@mj-biz-apps/tasks-github-ng": patch
---

Modernize `bizapps-tasks-github` for MemberJunction 6.3 `RelatedRecordCollection` and provider-arbitrated entity transactions:

- Declare read-only `IssueTasks` and `PullRequestTasks` `RelatedRecordCollection` metadata and generated `DeclareRelatedRecords` properties on `GitHubRepository` (`Source: "database"`, `Load: "explicit"`, `ReadOnly: true`, `OnRemove: "refuse"`, `OrderBy: "Number DESC"`).
- Refactor `GitHubTaskSyncService` to persist IS-A leaf entities (`GitHubIssueTask` / `GitHubPullRequestTask`) in a single save inside `BeginEntityTransaction()`, reconcile `TaskAssignment` rows atomically within the same transaction scope (using parent `Task.Assignments` companion when available), and wrap multi-PR `UpdatePullRequestChecksStatus` updates in `BeginEntityTransaction()`.
- Fix live `CK_Task_Priority` bug in `GitHubTaskInferenceService` and prompt template by deriving valid priorities directly from `mjBizAppsTasksTaskEntity['Priority']` (`'Low' | 'Medium' | 'High' | 'Critical'`) instead of invalid `'Urgent'`, and wrap suggestion supersede + create in `BeginEntityTransaction()`.
- Enforce `protected constructor()` across all `BaseSingleton` core services (`GitHubTaskSyncService`, `GitHubTaskInferenceService`, `GitHubWebhookService`).
- Fix `GitHubTasksAdminResource` sync banner `SummaryJSON` array aggregation and replace the unbounded `MJ_BizApps_Common: People` query with a scoped current-user lookup.
- Eliminate redundant self-subtype re-queries in `TaskGitHubLinksPanel`, validate all UUIDs across form panels before `ExtraFilter` interpolation, and reuse pre-loaded `GitHubRepository.IssueTasks` / `PullRequestTasks` in `GitHubRepositoryOverviewPanel`.
