# AGENTS.md — BizApps Tasks GitHub Extension

This repository follows the development guidelines, package architecture, build/test commands, and the **5-Rule BizApps Performance & Caching Standard** documented in **[CLAUDE.md](CLAUDE.md)**.

## Quick Reference for Coding Agents

1. **Read [CLAUDE.md](CLAUDE.md)** before editing code in this repository.
2. **Strict TypeScript**: Zero `any`, zero lazy `unknown` (`as unknown`, `as unknown as ...`), zero `.Get()`/`.Set()`, derive value-list unions from generated entity classes, and zero cross-package re-exports.
3. **5-Rule BizApps Performance & Caching Standard**:
   - **Rule 1**: Use `GitHubTasksEngineBase.Instance` (`@mj-biz-apps/tasks-github-entities`, `BaseEngine` + `BaseSingleton` + `@RegisterForStartup()`) for bounded `Git Hub Repositories` and `Git Hub Identities` lookups (`Repositories`, `ActiveRepositories`, `RepositoryById`, `RepositoryByFullName`, `Identities`, `ActiveIdentities`, `IdentityById`, `IdentityByGitHubLogin`, `IdentitiesByPersonId`, `IdentitiesByUserId`).
   - **Rule 2**: Keep `ProviderToUse` impersonation/multi-provider safe (`this._activeProvider ?? Metadata.Provider`), set `CacheLocal: true` ONLY on verified non-RLS reference entities (`CacheLocal: false` on RLS entities), gate reads with `EntityByName(...)?.GetUserPermisions(user)?.CanRead`, and reset caches on `userId` switches.
   - **Rule 3**: Collapse independent `RunView` bursts into a single `rv.RunViews([...], contextUser)` batch using `RunView.FromMetadataProvider(provider)` and `ResultType: 'simple'` (or `'count_only'`) for read-only queries.
   - **Rule 4**: Use `ConversationEngine`-style bounded container window caching (keyed by parent/container ID, invalidated on `BaseEntity` events + user switch) only for bounded parent scopes; **never** cache arbitrary `ExtraFilter` transactional lists.
   - **Rule 5**: Use two-step entity `RunView`s instead of raw base-view SQL subqueries on RLS entities.
4. **Verification before commit/PR**:
   - `pnpm run build:packages`
   - `pnpm run test`
   - `node ./.github/scripts/check-dependency-model.mjs`
   - `node ./.github/scripts/check-caret-pins.mjs`
   - All repo guard scripts in `.github/workflows/build.yml` and `.github/workflows/repo-checks.yml`
5. **Git rules**: Feature branch from `origin/next`, explicit `git add <file>` (never `git add -A` / `.`), never commit directly to `next`/`main`, and merge PRs via `gh pr merge --merge` (never `--squash`).
