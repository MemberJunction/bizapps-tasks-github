---
"@mj-biz-apps/tasks-github-core": patch
"@mj-biz-apps/tasks-github-actions": patch
"@mj-biz-apps/tasks-github-server": patch
"@mj-biz-apps/tasks-github-ng": patch
---

Complete the limits sweep and runaway-guard resolution across `@mj-biz-apps/tasks-github-*`: add the classified sweep inventory (`reports/limits-sweep-bizapps-tasks-github.csv`), introduce `GitHubTasksLimitsResolver` in `@mj-biz-apps/tasks-github-core` integrating with `@memberjunction/core`'s `LimitsConfigResolver`, route all `RunawayGuard`, `ResourceGuard`, and `Tuning` limits across Core, Actions, and Server through the resolver with safe `ProtocolLimit` clamping and fallback defaults, annotate all retained `ProtocolLimit` constants inline, and upgrade interactive Angular hero panel chips to semantic `<button type="button">` controls with keyboard accessibility.
