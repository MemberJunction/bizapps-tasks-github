# `@mj-biz-apps/tasks-github-ng`

Angular UI package for the **BizApps Tasks — GitHub Extension** Open App (`mj-bizapps-tasks-github`).

## Exports

- **`LoadBizAppsTasksGitHubClient()`** — Client startup hook registered in `mj-app.json` (`packages.client`) to preserve `@RegisterClass` registrations for `GitHubTasksAdminResource` and GitHub Tasks entity subclasses.
- **`TasksGitHubAngularModule`** — Angular convenience module importing and re-exporting standalone GitHub Tasks UI components.
- **`GitHubTasksAdminResource`** (`@RegisterClass(BaseResourceComponent, 'GitHubTasksAdminResource')`) — Tasks application "GitHub Sync" resource with:
  - Tracked repository & `@memberjunction/connector-github` mirror vs GitHub REST sync source console
  - Self-service `MJ_BizApps_Common: People` → `MJ_BizApps_Tasks_GitHub: Git Hub Identities` handle mapping & MJ Vault 3LO OAuth status
  - Recent webhook delivery status viewer
- **`GitHubTaskDetailBadgeComponent`** (`<mj-tasks-github-detail-badge>`) — Embeddable task detail badge displaying GitHub Issue / Pull Request state chips, `+add / -del` diff stats, branch comparison, CI check & review badges, external GitHub link, and pull-owned field lock notice.
- Pure view-model builders and validators in `tasks-github-ui.models` and `tasks-github-ui.helpers`.
