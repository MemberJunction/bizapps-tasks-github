---
"@mj-biz-apps/tasks-github-actions": minor
"@mj-biz-apps/tasks-github-server": minor
---

Bring `bizapps-tasks-github` onto the Chief of Staff Extensible Skills contract:

- Add three strongly-typed, `AuthorizesCaller = true`, `TypedActionPolicyGuard`-enforced Chief of Staff actions in `@mj-biz-apps/tasks-github-actions`: `Get My GitHub PRs` (`GetMyGitHubPRsAction`), `Get GitHub Reviews Waiting On Me` (`GetGitHubReviewsWaitingOnMeAction`), and deterministic briefing contributor `Get My GitHub Briefing` (`GetMyGitHubBriefingAction`).
- Update the `GitHub Tasks & Pull Requests` skill metadata with `AllowMetadataSyncUpdate: true` on the `Chief of Staff` grant, bind the read tools (`Role: 'Tool'`, `ExposeToModel: true`) and briefing contributor (`Role: 'Briefing'`, `ExposeToModel: false`), keep bulk sync/inference operator actions out of default model exposure (`ExposeToModel: false`), and refresh the skill instructions template.
- Add the offered `PRs Waiting On You` (`github-review-queue`, `45 8 * * 1-5` UTC) Chief of Staff rhythm template under `metadata/rhythm-templates/` and register it in `metadata/.mj-sync.json`.
- Update SQL Server and PostgreSQL teardown scripts to disable materialized `github-review-queue` routines and remove the rhythm template, proactive suggestions, and new CoS action metadata cleanly.
