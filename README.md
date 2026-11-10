# BizApps Tasks GitHub Extension (`mj-bizapps-tasks-github`)

MemberJunction Open App that folds GitHub Issues and Pull Requests directly into **BizApps Tasks** as strongly-typed IS-A `Task` subtypes — without duplicating GitHub's review UI or corrupting human planning data.

## Architecture Overview

| Layer | Responsibility |
| --- | --- |
| **Database Schema (`__mj_BizAppsTasksGitHub`)** | `GitHubRepository`, `GitHubIdentity`, `GitHubIssueTask` (`IS-A __mj_BizAppsTasks.Task`), and `GitHubPullRequestTask` (`IS-A __mj_BizAppsTasks.Task`). |
| **`@mj-biz-apps/tasks-github-entities`** | Generated entity subclasses and Zod schemas for all 4 entities, with cross-schema `Entity.ParentID` pointing to `MJ_BizApps_Tasks: Tasks`. |
| **`@mj-biz-apps/tasks-github-core`** | `GitHubFieldOwnershipPolicy`, `GitHubTaskSyncService` (reconciler + `ImportRule`), `GitHubTaskInferenceService` (`MJ: Field Suggestions` + milestone superseding), and `GitHubWebhookService` (constant-time HMAC-SHA256 verification). |
| **`@mj-biz-apps/tasks-github-actions`** | `Sync GitHub Repositories To Tasks`, `Handle GitHub Webhook Delivery`, and `Infer GitHub Task Planning Fields`. |
| **`@mj-biz-apps/tasks-github-server`** | GraphQL resolvers, `LoadBizAppsTasksGitHubServer()`, and Express-compatible `createGitHubTasksWebhookHandler()` middleware. |
| **`@mj-biz-apps/tasks-github-integration-tests`** | Live-DB integration check bundle (`github-tasks-extension`: `GH1`–`GH3`). |

## Key Design Principles

1. **IS-A Subtypes on `Task` (`SubtypeSelector` `AutoEnsureOnSave`)**:
   - `GITHUB_ISSUE` (`ExtensionEntity = 'MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks'`) and `GITHUB_PR` (`ExtensionEntity = 'MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks'`).
   - Saving a bare `Task` with `TypeID = GITHUB_ISSUE` or `GITHUB_PR` automatically provisions the matching child row in the same SQL transaction, while `OnSubtypeChange = 'Refuse'` prevents cross-subtype corruption.
2. **Strict Field Ownership (No Two-Way Sync Conflicts)**:
   - **GitHub-owned (pull-only)**: `Name` (title), `Description` (body), GitHub lifecycle status (`OPEN`, `IN_PROGRESS`, `COMPLETED`, `NOT_PLANNED`, `DRAFT`, `REVIEW_REQUIRED`, `CHANGES_REQUESTED`, `APPROVED`, `MERGED`, `CLOSED`), labels, branches, SHAs, check status, review decision, and `TaskAssignment` `Primary` / `Reviewer` roles mapped through `GitHubIdentity`.
   - **Advisory `ChecksStatus` & `ReviewDecision` Projections**: On `check_suite`, `check_run`, and `pull_request_review` webhooks, `GitHubWebhookService` queries GitHub REST (`GET /repos/{o}/{r}/commits/{sha}/check-runs` + `/status` and `GET /repos/{o}/{r}/pulls/{n}/reviews`) when `GITHUB_TOKEN`/`GH_TOKEN` is configured, falling back to a bounded 5,000-entry LRU map when offline. Both columns are **advisory UI projections for task dashboards** — Software Factory's merge gate must read check runs and reviews directly from GitHub at merge time rather than gating on these columns.
   - **Tasks-owned (never overwritten on re-sync)**: `DueAt`, `HoursEstimated`, `HoursActual`, `ParentID` (objective/OKR parent), `Priority`, `CategoryID`, `PercentComplete`, and the factory dispatch status `READY_FOR_FACTORY`.
3. **Human-Verified Planning Inference (`MJ: Field Suggestions`)**:
   - When an issue or PR body changes (`BodyHash` SHA-256 delta), `GitHubTaskInferenceService` extracts candidate `DueAt`, `HoursEstimated`, `ParentID`, `Priority`, and `CategoryID` values into `MJ: Field Suggestions` (`AnchorType = 'Field'`) rather than silently writing planning fields.
   - Authoritative GitHub `MilestoneDueAt` automatically marks pending `DueAt` field suggestions as `Outcome = 'Superseded'`.
4. **Chief of Staff Skill (`"GitHub Tasks & Pull Requests"`)**:
   - Granted to `Chief of Staff` via `metadata/skills` so agents combine BizApps Tasks queries with MJ's GitHub integration actions (`Create Issue`, `Get Pull Request`, `Review Pull Request`, `Merge Pull Request`, `List Workflow Runs`, etc.).

## Documentation

- [GitHub Tasks Sync, Webhooks & Field Ownership Guide](guides/GITHUB_TASKS_SYNC_AND_OWNERSHIP_GUIDE.md)

## Commands

```bash
pnpm run build:packages     # Build all 5 packages in topological order
pnpm run test               # Run Vitest unit tests across all packages
pnpm run mj:migrate         # Apply SQL Server migrations to __mj_BizAppsTasksGitHub
pnpm run mj:migrate:convert # Convert SQL Server migrations to PostgreSQL
```
