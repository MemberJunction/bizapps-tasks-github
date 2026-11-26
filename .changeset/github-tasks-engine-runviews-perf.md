---
"@mj-biz-apps/tasks-github-entities": minor
"@mj-biz-apps/tasks-github-core": patch
"@mj-biz-apps/tasks-github-actions": patch
"@mj-biz-apps/tasks-github-ng": patch
---

Add `GitHubTasksEngineBase` (`BaseEngine` + `BaseSingleton` + `@RegisterForStartup()`) in `@mj-biz-apps/tasks-github-entities` caching bounded non-RLS `Git Hub Repositories` and `Git Hub Identities` with O(1) lookup helpers, impersonation/provider-switch safety, `userId`-switch cache reset, `CanRead` permission gating, and immediate auto-refresh invalidation. Wire `GitHubTasksEngineBase` and collapse independent `RunView` bursts into batched `rv.RunViews([...])` calls across Core, Actions, and Angular packages, and document the 5-Rule BizApps Performance & Caching Standard in `CLAUDE.md` and `AGENTS.md`.
