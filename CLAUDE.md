# BizApps Tasks GitHub Extension — Development Guide

This repository (`MemberJunction/bizapps-tasks-github`) implements the MemberJunction Open App for GitHub Issue & Pull Request Task subtypes (`__mj_BizAppsTasksGitHub`), repository & identity mapping, bidirectional sync, webhook ingestion, LLM planning-field inference, Chief of Staff GitHub skills, and Angular Explorer UI.

## Package Architecture

| Package | Path | Responsibility |
| --- | --- | --- |
| `@mj-biz-apps/tasks-github-entities` | `packages/Entities` | Generated entity subclasses (`GitHubRepository`, `GitHubIdentity`, `GitHubIssueTask`, `GitHubPullRequestTask`) and `GitHubTasksEngineBase` (`BaseEngine` metadata/config cache shared across browser and server). |
| `@mj-biz-apps/tasks-github-core` | `packages/Core` | Core domain services: `GitHubTaskSyncService`, `GitHubWebhookService`, `GitHubTaskInferenceService`, `GitHubFieldOwnershipPolicy`, `GitHubVaultAuthResolver`, `ConnectorGitHubMirrorRepositoryFetcher`, and `GitHubTasksLimitsResolver`. |
| `@mj-biz-apps/tasks-github-actions` | `packages/Actions` | Action subclasses (`SyncGitHubRepositoryTasksAction`, `HandleGitHubWebhookAction`, `InferGitHubTaskFieldsAction`) and Chief of Staff actions (`GetMyGitHubPRsAction`, `GetGitHubReviewsWaitingOnMeAction`, `GetMyGitHubBriefingAction`). |
| `@mj-biz-apps/tasks-github-server` | `packages/Server` | GraphQL resolvers, Express webhook middleware (`GitHubTasksWebhookServerExtension`), and server bootstrap (`LoadBizAppsTasksGitHubServer`). |
| `@mj-biz-apps/tasks-github-ng` | `packages/Angular` | Explorer UI: `GitHubTasksAdminResource` console, standalone `GitHubWorkPanelComponent` & `GitHubTaskDetailBadgeComponent`, generated entity forms, and `BaseFormPanel` contributions. |
| `@mj-biz-apps/tasks-github-integration-tests` | `packages/IntegrationTests` | Live integration check bundle (`GH1`–`GH3`). |

### Dependency Model
- `@memberjunction/*` and sibling `@mj-biz-apps/*` packages MUST be declared as caret/range `peerDependencies` (and pinned in `devDependencies`), **never** as runtime `dependencies` (except intra-repo `@mj-biz-apps/tasks-github-*` dependencies).
- Always run `node ./.github/scripts/check-dependency-model.mjs` and `node ./.github/scripts/check-caret-pins.mjs` after touching any `package.json`.

## Build, Test & Guard Commands

```bash
# Build all workspace packages in dependency order
pnpm run build:packages

# Run all unit tests across all packages
pnpm run test

# Run repository & dependency guards (same scripts as CI)
./.github/scripts/validate-package-repository.sh
./.github/scripts/validate-package-files.sh
./.github/scripts/validate-metadata-directory-order.sh
node ./.github/scripts/check-dependency-model.mjs --self-test
node ./.github/scripts/check-dependency-model.mjs
node ./.github/scripts/check-caret-pins.mjs --self-test
node ./.github/scripts/check-caret-pins.mjs
./.github/scripts/validate-migration-filenames.sh
node ./.github/scripts/check-migration-entityfield-sequence.mjs
node ./.github/scripts/check-migration-no-prune.mjs
```

## Critical Coding Standards

- **No `any` and no lazy `unknown`**: Never use `any`, `as any`, `: unknown`, or `as unknown as ...`. Use strongly-typed generated entity classes and explicit interfaces.
- **No `.Get()` / `.Set()`**: Always access strongly-typed entity properties directly (e.g. `repo.IsTracked`, `identity.GitHubLogin`).
- **Derive value-list unions from entities**: Use indexed access types such as `mjBizAppsTasksGitHubGitHubRepositoryEntity['ImportRule']` rather than hand-copying string literal unions.
- **No cross-package re-exports**: Each package exports only what it defines. Import `GitHubTasksEngineBase` and entity classes directly from `@mj-biz-apps/tasks-github-entities`.
- **Singletons via `BaseSingleton` / `BaseEngine`**: Never use manual `private static _instance` fields.
- **Modern Angular templates**: Use `@if` / `@for` / `@switch` and `inject()` for new Angular code; persist user preferences via `UserInfoEngine.Instance` (never `localStorage`).
- **Git hygiene**: Create feature branches from `origin/next`, stage explicitly (`git add <file>` — never `git add -A` / `.`), never commit directly to `next` or `main`, and always merge PRs with `--merge` (never `--squash`).

---

## 5-Rule BizApps Performance & Caching Standard

All data loading and caching across `bizapps-tasks-github` MUST follow these five rules:

### Rule 1: `BaseEngine` + `BaseSingleton` (`@RegisterForStartup()`) for Bounded Taxonomy & Config Tables
- Bounded, low-cardinality configuration and taxonomy entities (`MJ_BizApps_Tasks_GitHub: Git Hub Repositories` and `MJ_BizApps_Tasks_GitHub: Git Hub Identities`) MUST be cached via `GitHubTasksEngineBase extends BaseEngine<GitHubTasksEngineBase>` in `@mj-biz-apps/tasks-github-entities`.
- Placing `GitHubTasksEngineBase` in the Entities package lets both Angular UI (`@mj-biz-apps/tasks-github-ng`) and server/core/actions packages consume the exact same singleton cache with zero circular dependencies and zero extra peer dependencies.
- Maintain memoized O(1) lookup helpers (`Repositories`, `ActiveRepositories`, `RepositoryById`, `RepositoryByFullName`, `Identities`, `ActiveIdentities`, `IdentityById`, `IdentityByGitHubLogin`, `IdentitiesByPersonId`, `IdentitiesByUserId`) rebuilt automatically in `AdditionalLoading`, `NotifyDataChange`, and `HandleIndividualBaseEntityEvent`.

### Rule 2: Impersonation & Multi-Provider-Safe `ProviderToUse`, RLS-Aware `CacheLocal`, `CanRead` Gating & User-Switch Reset
- **Never latch to a stale bootstrap provider**: Override `get ProviderToUse(): IMetadataProvider` on `BaseEngine` subclasses to return the active provider passed to `Config()` or live `Metadata.Provider` (`this._activeProvider ?? Metadata.Provider`). Never let `BaseEngine`'s first-wins `_provider` permanently pin a bootstrap provider across impersonation or provider swaps.
- **RLS-aware `CacheLocal`**: Check `metadata/entities/.ui-role-permissions.json` and migrations before setting `CacheLocal`. Set `CacheLocal: true` **only** on verified global, non-RLS reference/config entities (`Git Hub Repositories` and `Git Hub Identities` have no RLS). Set `CacheLocal: false` on any RLS-scoped entity so row-filtered slices are never shared across users in local cache.
- **`CanRead` permission gating**: Gate engine loads and reads with `provider.EntityByName(entityName)?.GetUserPermisions(user)?.CanRead`. Never issue doomed `RunView`s for entities the active user cannot read, and degrade gracefully to empty collections when restricted.
- **Automatic user-switch cache reset**: Detect `CurrentUser.ID` / `contextUser.ID` switches (and non-identical provider swaps) in `EnsureLoaded()`, `Config()`, and read guards to clear caches and reload cleanly rather than leaking a previous user's view.

### Rule 3: `rv.RunViews([...])` GraphQL Batching & `ResultType: 'simple'`
- **Never fire parallel `Promise.all([rv.RunView(...), rv.RunView(...)])` or independent sequential `await rv.RunView(...)` bursts.** Collapse independent queries into a **single `rv.RunViews([...], contextUser)` batch call** so browser clients execute one GraphQL HTTP round-trip and servers execute one batched dispatch.
- Always construct `RunView` from the active provider (`RunView.FromMetadataProvider(provider)` or `new RunView(this.RunViewToUse)` in `BaseAngularComponent`).
- Use `ResultType: 'simple'` (or `ResultType: 'count_only'` for counts) whenever rows are read-only projections; reserve `ResultType: 'entity_object'` strictly for rows you will mutate with `.Save()` or `.Delete()`.

### Rule 4: Bounded Container Window Caching vs Never Caching Arbitrary `ExtraFilter` Lists
- When caching transactional child rows for a specific parent container (e.g. a single task, repository, or conversation thread), follow the `ConversationEngine` pattern: maintain a **bounded** in-memory window keyed by parent/container ID, invalidated on matching `BaseEntity` save/delete events and cleared on user switch.
- **NEVER** cache arbitrary `ExtraFilter` SQL transactional lists (such as filtered PR searches, date-ranged briefings, or ad-hoc user queries). Keep transactional list queries direct via `rv.RunView` / `rv.RunViews` with explicit `MaxRows` limits.

### Rule 5: Two-Step Entity `RunView`s Instead of Raw Base-View SQL Subqueries on RLS Entities
- Never embed raw SQL subqueries against underlying views/tables inside `ExtraFilter` when crossing entity boundaries with Row-Level Security (e.g. `ID IN (SELECT ... FROM vw...)`). Raw SQL subqueries bypass MJ's entity-level RLS predicates and permissions.
- Always use a **two-step entity `RunView`** pattern: first query the parent/join entity through `RunView` (so MJ applies entity permissions and RLS), validate the returned UUIDs (`IsValidUUID` / `AssertValidUUID`), and then query the target entity using an explicit `IN (...)` filter (batching multiple independent second-step queries via `rv.RunViews`).
