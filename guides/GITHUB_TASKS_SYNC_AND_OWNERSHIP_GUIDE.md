# GitHub Tasks Sync, Webhooks & Field Ownership Guide

This guide documents the data model, field-ownership contract, webhook ingestion pipeline, and planning-inference flow of `mj-bizapps-tasks-github`.

---

## 1. Schema & IS-A Hierarchy (`__mj_BizAppsTasksGitHub`)

`mj-bizapps-tasks-github` installs into its own dedicated schema (`__mj_BizAppsTasksGitHub`) and depends on:

- `mj-bizapps-common` (`__mj_BizAppsCommon` — `Organization`, `Person`)
- `mj-bizapps-tasks` (`__mj_BizAppsTasks` — `Task`, `TaskType`, `TaskTypeStatus`, `TaskAssignment`, `TaskRole`)

### Entities

| Entity Name | Table | Purpose |
| --- | --- | --- |
| `MJ_BizApps_Tasks_GitHub: Git Hub Repositories` | `GitHubRepository` | Registered repositories (`Owner`, `Name`, `DefaultBranch`, `IsTracked`, `ImportRule`, `InstallationID`, `OrganizationID`, `DeliveryPolicyID`). |
| `MJ_BizApps_Tasks_GitHub: Git Hub Identities` | `GitHubIdentity` | Maps `GitHubLogin` -> `__mj_BizAppsCommon.Person(ID)` so assignees and requested reviewers materialize as first-class `TaskAssignment` rows. |
| `MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks` | `GitHubIssueTask` | **IS-A `MJ_BizApps_Tasks: Tasks`** (`PK/FK ID -> Task.ID`). Stores `RepositoryID`, `Number`, `NodeID`, `HtmlURL`, `State`, `StateReason`, `AuthorLogin`, `Labels`, `Milestone`, `MilestoneDueAt`, `BodyHash`, `GitHubUpdatedAt`, `LastSyncedAt`. |
| `MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks` | `GitHubPullRequestTask` | **IS-A `MJ_BizApps_Tasks: Tasks`** (`PK/FK ID -> Task.ID`). Adds `IsDraft`, `HeadBranch`, `HeadSha`, `BaseBranch`, `ReviewDecision`, `ChecksStatus`, `ChangedFiles`, `Additions`, `Deletions`, `MergedAt`, and `LinkedIssueTaskID`. |

---

## 2. Field Ownership Contract

Two-way synchronization of planning fields between GitHub and an internal work-management tool is a classic source of silent data loss. `GitHubFieldOwnershipPolicy` enforces a crisp, one-owner-per-field contract:

| Field | Owner | Sync Behavior |
| --- | --- | --- |
| `Task.Name` | **GitHub** | Updated from Issue/PR `title` on every sync/webhook. |
| `Task.Description` | **GitHub** | Updated from Issue/PR `body` on every sync/webhook. |
| `Task.Status` & `Task.TaskTypeStatusID` | **GitHub** (except `READY_FOR_FACTORY`) | Mapped deterministically from GitHub state, draft flag, assignees, requested reviewers, and review decision. If a human moves an open item into `READY_FOR_FACTORY`, re-sync preserves `READY_FOR_FACTORY` until the item closes/merges. |
| `TaskAssignment` (`Primary`, `Reviewer`) | **GitHub** | Reconciled from `assignees` (`Primary`) and `requested_reviewers` (`Reviewer`) via `GitHubIdentity`. |
| `GitHubPullRequestTask.LinkedIssueTaskID` | **GitHub** | Auto-linked from `Closes #N` / `Fixes #N` / `Resolves #N` in the PR body within the same repository. |
| `Task.DueAt` | **BizApps Tasks** | Never overwritten by GitHub sync; candidate dates in Markdown become `MJ: Field Suggestions`. |
| `Task.HoursEstimated` / `HoursActual` | **BizApps Tasks** | Never overwritten by GitHub sync; effort hints become `MJ: Field Suggestions`. |
| `Task.ParentID` | **BizApps Tasks** | Objective/OKR parent hierarchy lives exclusively in BizApps Tasks. |
| `Task.Priority` | **BizApps Tasks** | Seeded only on initial creation (`Medium` for issues, `High` for PRs); never overwritten on re-sync. |
| `Task.CategoryID` | **BizApps Tasks** | Owned by BizApps Tasks; candidate categories become `MJ: Field Suggestions`. |

---

## 3. Repository `ImportRule` Filtering

Each `GitHubRepository` declares an `ImportRule`:

- **`AssignedOnly` (default — noise control)**: Only issues/PRs where at least one assignee or requested reviewer resolves to an active `GitHubIdentity` are imported on initial discovery. Once a task exists in BizApps Tasks, updates continue to sync even if assignees later change.
- **`All`**: Every open/updated issue and pull request in the repository is imported.
- **`LabeledOnly`**: Reserved for label-scoped repositories; sync honors existing tracked tasks and configured label filters.

---

## 4. Webhook Ingestion (`X-Hub-Signature-256`)

`GitHubWebhookService` and `createGitHubTasksWebhookHandler` verify every webhook delivery **fail-closed**:

1. Rejects missing secrets, missing `X-Hub-Signature-256` headers, non-hex digests, or mismatched HMAC-SHA256 digests using `crypto.timingSafeEqual` (`HTTP 401`).
2. Processes `issues`, `pull_request`, and `pull_request_review` events immediately into `GitHubTaskSyncService`.
3. Returns `200 { ok: true, status: 'ignored' }` for `ping` or untracked repositories without creating noisy rows.

### Mounting in Host MJAPI / Express Server

When `@mj-biz-apps/tasks-github-server` is installed as an Open App server package, `GitHubTasksWebhookServerExtension` (`MJ_SERVER_EXTENSIONS`) automatically mounts the pre-auth webhook endpoint at `ApiRoute('/webhooks/github/tasks')` before JWT authentication and global JSON body parsing.

To mount the route explicitly in a custom host setup, use `registerGitHubTasksWebhookRoute` (which mounts via `ApiRoute()` and resolves the acting principal from `GITHUB_WEBHOOK_USER_EMAIL` via `ResolveConfiguredPrincipal` or falls back explicitly to `UserCache.Instance.GetSystemUser()`):

```typescript
import express from 'express';
import {
    captureRawBodyVerify,
    registerGitHubTasksWebhookRoute,
} from '@mj-biz-apps/tasks-github-server';

// If global express.json() is registered ahead of custom routes, preserve req.rawBody:
app.use(express.json({ verify: captureRawBodyVerify }));

// Mounts at ApiRoute('/webhooks/github/tasks') and runs as GITHUB_WEBHOOK_USER_EMAIL or GetSystemUser()
registerGitHubTasksWebhookRoute(app, {
    configuredUserEmail: process.env.GITHUB_WEBHOOK_USER_EMAIL,
    queueInference: true,
});
```

For bulk repository synchronization (`SyncGitHubRepositoryTasksAction` without `ItemsJSON`), set `GITHUB_TOKEN` (or `GH_TOKEN`) on the server so `DefaultGitHubRestRepositoryFetcher` fetches issues and pull requests from the GitHub REST API, or register a custom `IGitHubRepositoryFetcher` via `GitHubTaskSyncService.Instance.SetRepositoryFetcher(...)`.

---

## 5. Planning Field Inference & Milestone Superseding

When `BodyHash` (`SHA-256(trimmedTitle + '\n---\n' + trimmedBody)`) changes:

1. `GitHubTaskInferenceService` runs the `"GitHub Task Planning Field Inference"` prompt (or custom injected `IGitHubInferenceExtractor` in tests).
2. Any Tasks-owned planning field that **already has a non-null human value** on `Task` is skipped.
3. If `MilestoneDueAt` is present on GitHub, `DueAt` inference is skipped and any existing pending `DueAt` `MJ: Field Suggestions` (`Outcome IS NULL AND IsResolved = 0`) are automatically transitioned to `Outcome = 'Superseded'`, `IsResolved = true`.
4. Eligible candidates are written to `MJ: Field Suggestions` (`AnchorType = 'Field'`, `AnchorKey = <FieldName>`, `SuggestedValue = JSON.stringify(value)`, `Source = 'LLM'`, `AIPromptRunID`).
