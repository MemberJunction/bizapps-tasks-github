import {
    BaseEngine,
    BaseEnginePropertyConfig,
    BaseEntity,
    BaseEntityEvent,
    IMetadataProvider,
    Metadata,
    ProviderType,
    RegisterForStartup,
    UserInfo,
} from '@memberjunction/core';
import { NormalizeUUID } from '@memberjunction/global';
import {
    mjBizAppsTasksGitHubGitHubIdentityEntity,
    mjBizAppsTasksGitHubGitHubRepositoryEntity,
} from './generated/entity_subclasses.js';

export const GITHUB_REPOSITORIES_ENTITY_NAME = 'MJ_BizApps_Tasks_GitHub: Git Hub Repositories';
export const GITHUB_IDENTITIES_ENTITY_NAME = 'MJ_BizApps_Tasks_GitHub: Git Hub Identities';

/**
 * Shared metadata & configuration engine for BizApps Tasks GitHub Extension.
 *
 * Caches bounded, non-RLS org-wide GitHub integration reference tables:
 * - `MJ_BizApps_Tasks_GitHub: Git Hub Repositories` (`AutoRefresh: true`, `CacheLocal: true`)
 * - `MJ_BizApps_Tasks_GitHub: Git Hub Identities` (`AutoRefresh: true`, `CacheLocal: true`)
 *
 * Neither entity uses Row-Level Security (verified in `metadata/entities/.ui-role-permissions.json`
 * and schema migrations), so `CacheLocal: true` is safe on both configs.
 *
 * Safety guarantees:
 * - **Impersonation & multi-provider safe**: Overrides `ProviderToUse` to follow the active provider
 *   passed to `Config()` or live `Metadata.Provider` rather than latching permanently to a bootstrap
 *   provider.
 * - **User-switch cache reset**: Detects `CurrentUser.ID` / `contextUser.ID` switches on client/network
 *   providers (and provider swaps across test harnesses or impersonated sessions) to clear caches and
 *   reload cleanly.
 * - **Permission gating**: Gates both loading and reads with `EntityByName(...)?.GetUserPermisions(user)?.CanRead`.
 * - **O(1) memoized lookups**: Rebuilt on every load (`AdditionalLoading`), data change (`NotifyDataChange`),
 *   and auto-refresh (`HandleIndividualBaseEntityEvent`).
 */
@RegisterForStartup()
export class GitHubTasksEngineBase extends BaseEngine<GitHubTasksEngineBase> {
    private _repositories: mjBizAppsTasksGitHubGitHubRepositoryEntity[] = [];
    private _identities: mjBizAppsTasksGitHubGitHubIdentityEntity[] = [];

    private _activeProvider: IMetadataProvider | null = null;
    private _loadedProvider: IMetadataProvider | null = null;
    private _loadedUserId: string | null = null;
    private _loadedFromProviderCurrentUser = false;
    private _cacheResetPending = false;
    private _deniedEntities = new Set<string>();

    // Memoized O(1) lookup structures rebuilt on load and auto-refresh
    private _sortedRepositories: mjBizAppsTasksGitHubGitHubRepositoryEntity[] = [];
    private _activeRepositories: mjBizAppsTasksGitHubGitHubRepositoryEntity[] = [];
    private _repositoryById = new Map<string, mjBizAppsTasksGitHubGitHubRepositoryEntity>();
    private _repositoryByFullName = new Map<string, mjBizAppsTasksGitHubGitHubRepositoryEntity>();

    private _sortedIdentities: mjBizAppsTasksGitHubGitHubIdentityEntity[] = [];
    private _activeIdentities: mjBizAppsTasksGitHubGitHubIdentityEntity[] = [];
    private _identityById = new Map<string, mjBizAppsTasksGitHubGitHubIdentityEntity>();
    private _identityByGitHubLogin = new Map<string, mjBizAppsTasksGitHubGitHubIdentityEntity>();
    private _identitiesByPersonId = new Map<string, mjBizAppsTasksGitHubGitHubIdentityEntity[]>();
    private _activeIdentitiesByPersonId = new Map<string, mjBizAppsTasksGitHubGitHubIdentityEntity[]>();
    private _identitiesByUserId = new Map<string, mjBizAppsTasksGitHubGitHubIdentityEntity[]>();
    private _activeIdentitiesByUserId = new Map<string, mjBizAppsTasksGitHubGitHubIdentityEntity[]>();

    public constructor() {
        super();
    }

    /**
     * Singleton instance backed by `BaseSingleton` / `GetGlobalObjectStore()`.
     */
    public static get Instance(): GitHubTasksEngineBase {
        return super.getInstance<GitHubTasksEngineBase>();
    }

    /**
     * Dynamically resolves the active provider passed to `Config()` or live `Metadata.Provider`.
     * Never permanently latches to a stale bootstrap provider during impersonation or provider swaps.
     */
    public override get ProviderToUse(): IMetadataProvider {
        return this._activeProvider ?? Metadata.Provider;
    }

    /**
     * Clears all cached rows, lookup maps, and session tracking state so the next
     * `EnsureLoaded()` or `Config()` performs a fresh load.
     */
    public ResetCaches(): void {
        this.clearDataAndLookups();
        this._activeProvider = null;
        this._loadedProvider = null;
        this._loadedUserId = null;
        this._loadedFromProviderCurrentUser = false;
        this._cacheResetPending = true;
    }

    /**
     * Checks whether the effective user has `CanRead` permission on `Git Hub Repositories`.
     */
    public CanReadRepositories(user?: UserInfo, provider?: IMetadataProvider): boolean {
        const effectiveProvider = provider ?? this.ProviderToUse;
        const effectiveUser = this.resolveEffectiveUser(user, effectiveProvider);
        return this.canUserReadEntity(GITHUB_REPOSITORIES_ENTITY_NAME, effectiveUser, effectiveProvider);
    }

    /**
     * Checks whether the effective user has `CanRead` permission on `Git Hub Identities`.
     */
    public CanReadIdentities(user?: UserInfo, provider?: IMetadataProvider): boolean {
        const effectiveProvider = provider ?? this.ProviderToUse;
        const effectiveUser = this.resolveEffectiveUser(user, effectiveProvider);
        return this.canUserReadEntity(GITHUB_IDENTITIES_ENTITY_NAME, effectiveUser, effectiveProvider);
    }

    /**
     * Ensures the engine is loaded for the active provider and user context.
     * Unlike `BaseEngine.EnsureLoaded()`, also detects provider switches, user switches
     * (impersonation), and pending cache resets even when the engine was previously loaded.
     */
    public override async EnsureLoaded(contextUser?: UserInfo, provider?: IMetadataProvider): Promise<void> {
        const effectiveProvider = provider ?? Metadata.Provider;
        const effectiveUser = this.resolveEffectiveUser(contextUser, effectiveProvider);
        const effectiveUserId = this.normalizeUserId(effectiveUser);

        if (
            this.Loaded &&
            !this._cacheResetPending &&
            !this.isProviderChanged(effectiveProvider) &&
            !this.isUserChanged(effectiveProvider, effectiveUserId)
        ) {
            return;
        }

        await this.Config(false, contextUser, provider);
    }

    /**
     * Loads and caches `Git Hub Repositories` and `Git Hub Identities` via `BaseEngine.Load()`,
     * respecting provider/user switches and `CanRead` permissions.
     */
    public async Config(
        forceRefresh: boolean = false,
        contextUser?: UserInfo,
        provider?: IMetadataProvider,
    ): Promise<void> {
        this._activeProvider = provider ?? null;
        const effectiveProvider = this.ProviderToUse;
        const effectiveUser = this.resolveEffectiveUser(contextUser, effectiveProvider);
        const effectiveUserId = this.normalizeUserId(effectiveUser);

        const providerChanged = this.isProviderChanged(effectiveProvider);
        const userChanged = this.isUserChanged(effectiveProvider, effectiveUserId);
        let effectiveForceRefresh = forceRefresh;

        if (providerChanged || userChanged || this._cacheResetPending) {
            this.clearDataAndLookups();
            effectiveForceRefresh = true;
            this._cacheResetPending = false;
        }

        const canReadRepos = this.canUserReadEntity(
            GITHUB_REPOSITORIES_ENTITY_NAME,
            effectiveUser,
            effectiveProvider,
        );
        const canReadIdentities = this.canUserReadEntity(
            GITHUB_IDENTITIES_ENTITY_NAME,
            effectiveUser,
            effectiveProvider,
        );

        this._deniedEntities.clear();
        const configs: Partial<BaseEnginePropertyConfig>[] = [];

        if (canReadRepos) {
            configs.push({
                Type: 'entity',
                EntityName: GITHUB_REPOSITORIES_ENTITY_NAME,
                PropertyName: '_repositories',
                AutoRefresh: true,
                CacheLocal: true,
            });
        } else {
            this._deniedEntities.add(GITHUB_REPOSITORIES_ENTITY_NAME);
            this._repositories = [];
        }

        if (canReadIdentities) {
            configs.push({
                Type: 'entity',
                EntityName: GITHUB_IDENTITIES_ENTITY_NAME,
                PropertyName: '_identities',
                AutoRefresh: true,
                CacheLocal: true,
            });
        } else {
            this._deniedEntities.add(GITHUB_IDENTITIES_ENTITY_NAME);
            this._identities = [];
        }

        if (configs.length === 0) {
            this._loadedProvider = effectiveProvider ?? null;
            this._loadedUserId = effectiveUserId;
            this._loadedFromProviderCurrentUser = !contextUser && Boolean(effectiveProvider?.CurrentUser?.ID);
            this.rebuildLookups();
            return;
        }

        await this.Load(configs, effectiveProvider, effectiveForceRefresh, contextUser);

        this._loadedProvider = effectiveProvider ?? null;
        this._loadedUserId = effectiveUserId;
        this._loadedFromProviderCurrentUser = !contextUser && Boolean(effectiveProvider?.CurrentUser?.ID);
        this.rebuildLookups();
    }

    /**
     * All cached `Git Hub Repositories` sorted by `Owner ASC, Name ASC`.
     * Returns an empty array when the active user lacks `CanRead`.
     */
    public get Repositories(): readonly mjBizAppsTasksGitHubGitHubRepositoryEntity[] {
        this.guardLiveSessionState();
        if (!this.canReadPropertyNow(GITHUB_REPOSITORIES_ENTITY_NAME)) {
            return [];
        }
        return this._sortedRepositories;
    }

    /**
     * All tracked (`IsTracked === true`) `Git Hub Repositories` sorted by `Owner ASC, Name ASC`.
     */
    public get ActiveRepositories(): readonly mjBizAppsTasksGitHubGitHubRepositoryEntity[] {
        this.guardLiveSessionState();
        if (!this.canReadPropertyNow(GITHUB_REPOSITORIES_ENTITY_NAME)) {
            return [];
        }
        return this._activeRepositories;
    }

    /**
     * O(1) case-insensitive UUID lookup for a cached `Git Hub Repository`.
     */
    public RepositoryById(
        id: string | null | undefined,
    ): mjBizAppsTasksGitHubGitHubRepositoryEntity | undefined {
        this.guardLiveSessionState();
        if (!id || !this.canReadPropertyNow(GITHUB_REPOSITORIES_ENTITY_NAME)) {
            return undefined;
        }
        const trimmed = id.trim();
        if (trimmed.length === 0) {
            return undefined;
        }
        return this._repositoryById.get(NormalizeUUID(trimmed));
    }

    /**
     * O(1) case-insensitive `'owner/name'` lookup for a cached `Git Hub Repository`.
     */
    public RepositoryByFullName(
        fullName: string | null | undefined,
    ): mjBizAppsTasksGitHubGitHubRepositoryEntity | undefined {
        this.guardLiveSessionState();
        if (!fullName || !this.canReadPropertyNow(GITHUB_REPOSITORIES_ENTITY_NAME)) {
            return undefined;
        }
        const key = fullName.trim().toLowerCase();
        if (key.length === 0) {
            return undefined;
        }
        return this._repositoryByFullName.get(key);
    }

    /**
     * All cached `Git Hub Identities` sorted by `GitHubLogin ASC`.
     * Returns an empty array when the active user lacks `CanRead`.
     */
    public get Identities(): readonly mjBizAppsTasksGitHubGitHubIdentityEntity[] {
        this.guardLiveSessionState();
        if (!this.canReadPropertyNow(GITHUB_IDENTITIES_ENTITY_NAME)) {
            return [];
        }
        return this._sortedIdentities;
    }

    /**
     * All active (`IsActive !== false`) `Git Hub Identities` sorted by `GitHubLogin ASC`.
     */
    public get ActiveIdentities(): readonly mjBizAppsTasksGitHubGitHubIdentityEntity[] {
        this.guardLiveSessionState();
        if (!this.canReadPropertyNow(GITHUB_IDENTITIES_ENTITY_NAME)) {
            return [];
        }
        return this._activeIdentities;
    }

    /**
     * O(1) case-insensitive UUID lookup for a cached `Git Hub Identity`.
     */
    public IdentityById(
        id: string | null | undefined,
    ): mjBizAppsTasksGitHubGitHubIdentityEntity | undefined {
        this.guardLiveSessionState();
        if (!id || !this.canReadPropertyNow(GITHUB_IDENTITIES_ENTITY_NAME)) {
            return undefined;
        }
        const trimmed = id.trim();
        if (trimmed.length === 0) {
            return undefined;
        }
        return this._identityById.get(NormalizeUUID(trimmed));
    }

    /**
     * O(1) case-insensitive lookup for a cached `Git Hub Identity` by `GitHubLogin`.
     * Trims whitespace and strips an optional leading `@`.
     */
    public IdentityByGitHubLogin(
        login: string | null | undefined,
        activeOnly: boolean = false,
    ): mjBizAppsTasksGitHubGitHubIdentityEntity | undefined {
        this.guardLiveSessionState();
        if (!login || !this.canReadPropertyNow(GITHUB_IDENTITIES_ENTITY_NAME)) {
            return undefined;
        }
        const normalized = login.trim().replace(/^@/, '').toLowerCase();
        if (normalized.length === 0) {
            return undefined;
        }
        const identity = this._identityByGitHubLogin.get(normalized);
        if (!identity) {
            return undefined;
        }
        if (activeOnly && identity.IsActive === false) {
            return undefined;
        }
        return identity;
    }

    /**
     * O(1) lookup for all cached `Git Hub Identities` mapped to a BizApps Common `PersonID`.
     */
    public IdentitiesByPersonId(
        personId: string | null | undefined,
        activeOnly: boolean = false,
    ): readonly mjBizAppsTasksGitHubGitHubIdentityEntity[] {
        this.guardLiveSessionState();
        if (!personId || !this.canReadPropertyNow(GITHUB_IDENTITIES_ENTITY_NAME)) {
            return [];
        }
        const trimmed = personId.trim();
        if (trimmed.length === 0) {
            return [];
        }
        const key = NormalizeUUID(trimmed);
        const map = activeOnly ? this._activeIdentitiesByPersonId : this._identitiesByPersonId;
        return map.get(key) ?? [];
    }

    /**
     * O(1) lookup for all cached `Git Hub Identities` matching a GitHub user identifier (`GitHubUserID`).
     */
    public IdentitiesByUserId(
        userId: string | null | undefined,
        activeOnly: boolean = false,
    ): readonly mjBizAppsTasksGitHubGitHubIdentityEntity[] {
        this.guardLiveSessionState();
        if (!userId || !this.canReadPropertyNow(GITHUB_IDENTITIES_ENTITY_NAME)) {
            return [];
        }
        const key = userId.trim().toLowerCase();
        if (key.length === 0) {
            return [];
        }
        const map = activeOnly ? this._activeIdentitiesByUserId : this._identitiesByUserId;
        return map.get(key) ?? [];
    }

    /**
     * Rebuilds memoized O(1) lookup indexes after every `BaseEngine.Load()` / refresh.
     */
    protected override async AdditionalLoading(_contextUser?: UserInfo): Promise<void> {
        this.rebuildLookups();
    }

    /**
     * Rebuilds memoized O(1) lookup indexes immediately before notifying `DataChange$` subscribers
     * (covering initial load, immediate mutations, remote-invalidate, and debounced refreshes).
     */
    protected override NotifyDataChange(
        config: BaseEnginePropertyConfig,
        data: unknown[],
        changeType: 'refresh' | 'add' | 'update' | 'delete' = 'refresh',
        affectedEntity?: BaseEntity,
    ): void {
        this.rebuildLookups();
        super.NotifyDataChange(config, data, changeType, affectedEntity);
    }

    /**
     * Safely delegates permission & schema-presence gating to `BaseEngine.CheckPermissionsOrSkipAll`,
     * while guarding against uninitialized `Metadata.Provider` (e.g. standalone unit tests that spy
     * directly on `RunView.prototype` without registering a metadata provider).
     */
    protected override CheckPermissionsOrSkipAll(
        configs: BaseEnginePropertyConfig[],
        contextUser: UserInfo,
    ): BaseEnginePropertyConfig[] {
        const md = this.ProviderToUse;
        if (!md || typeof md.EntityByName !== 'function') {
            return configs;
        }
        return super.CheckPermissionsOrSkipAll(configs, contextUser);
    }

    /**
     * Permits `BaseEngine` immediate in-memory mutations on save/delete events even though
     * `AdditionalLoading` is overridden, because `NotifyDataChange` and `HandleIndividualBaseEntityEvent`
     * synchronously rebuild all derived O(1) lookup maps.
     */
    protected override canUseImmediateMutation(
        config: BaseEnginePropertyConfig,
        _skipAdditionalLoadingCheck: boolean = false,
    ): boolean {
        return super.canUseImmediateMutation(config, true);
    }

    /**
     * Keeps memoized lookup indexes synchronized when `BaseEntity` save/delete/remote-invalidate
     * events arrive for `Git Hub Repositories` or `Git Hub Identities`.
     */
    protected override async HandleIndividualBaseEntityEvent(event: BaseEntityEvent): Promise<boolean> {
        const result = await super.HandleIndividualBaseEntityEvent(event);
        const rawName = event.baseEntity?.EntityInfo?.Name ?? event.entityName ?? '';
        const lowerName = rawName.trim().toLowerCase();
        if (
            lowerName === GITHUB_REPOSITORIES_ENTITY_NAME.toLowerCase() ||
            lowerName === GITHUB_IDENTITIES_ENTITY_NAME.toLowerCase()
        ) {
            this.rebuildLookups();
        }
        return result;
    }

    private resolveEffectiveUser(
        contextUser: UserInfo | undefined,
        provider: IMetadataProvider | undefined,
    ): UserInfo | undefined {
        return contextUser ?? provider?.CurrentUser;
    }

    private normalizeUserId(user: UserInfo | undefined): string | null {
        const id = user?.ID?.trim();
        return id && id.length > 0 ? NormalizeUUID(id) : null;
    }

    private isProviderChanged(effectiveProvider: IMetadataProvider | undefined): boolean {
        if (!this._loadedProvider || !effectiveProvider) {
            return false;
        }
        if (this._loadedProvider === effectiveProvider) {
            return false;
        }
        const prevConn = this._loadedProvider.InstanceConnectionString;
        const nextConn = effectiveProvider.InstanceConnectionString;
        if (
            this._loadedProvider.ProviderType === ProviderType.Database &&
            effectiveProvider.ProviderType === ProviderType.Database &&
            typeof prevConn === 'string' &&
            prevConn.length > 0 &&
            prevConn === nextConn
        ) {
            return false;
        }
        return true;
    }

    private isUserChanged(
        effectiveProvider: IMetadataProvider | undefined,
        effectiveUserId: string | null,
    ): boolean {
        if (effectiveProvider?.ProviderType === ProviderType.Database) {
            return false;
        }
        if (this._loadedUserId === null && effectiveUserId === null) {
            return false;
        }
        return this._loadedUserId !== effectiveUserId;
    }

    private guardLiveSessionState(): void {
        const liveProvider = this.ProviderToUse;
        if (this.isProviderChanged(liveProvider)) {
            this.clearDataAndLookups();
            this._cacheResetPending = true;
            return;
        }
        if (liveProvider?.ProviderType === ProviderType.Database) {
            return;
        }
        const liveCurrentUserId = this.normalizeUserId(liveProvider?.CurrentUser);
        if (
            this._loadedUserId !== null &&
            ((liveCurrentUserId !== null && liveCurrentUserId !== this._loadedUserId) ||
                (liveCurrentUserId === null && this._loadedFromProviderCurrentUser))
        ) {
            this.clearDataAndLookups();
            this._cacheResetPending = true;
        }
    }

    private canUserReadEntity(
        entityName: string,
        user: UserInfo | undefined,
        provider: IMetadataProvider | undefined,
    ): boolean {
        if (!user || !provider || typeof provider.EntityByName !== 'function') {
            return true;
        }
        const entityInfo = provider.EntityByName(entityName);
        if (!entityInfo || typeof entityInfo.GetUserPermisions !== 'function') {
            return true;
        }
        return entityInfo.GetUserPermisions(user)?.CanRead !== false;
    }

    private canReadPropertyNow(entityName: string): boolean {
        if (this._deniedEntities.has(entityName)) {
            return false;
        }
        const liveProvider = this.ProviderToUse;
        const liveUser = liveProvider?.CurrentUser;
        if (liveUser && !this.canUserReadEntity(entityName, liveUser, liveProvider)) {
            return false;
        }
        return true;
    }

    private clearDataAndLookups(): void {
        this._repositories = [];
        this._identities = [];
        this._deniedEntities.clear();
        this.rebuildLookups();
    }

    private rebuildLookups(): void {
        const repos = Array.isArray(this._repositories) ? this._repositories : [];
        const sortedRepos = [...repos].sort((a, b) => {
            const ownerCmp = (a.Owner ?? '').localeCompare(b.Owner ?? '', undefined, { sensitivity: 'base' });
            if (ownerCmp !== 0) {
                return ownerCmp;
            }
            return (a.Name ?? '').localeCompare(b.Name ?? '', undefined, { sensitivity: 'base' });
        });

        const activeRepos: mjBizAppsTasksGitHubGitHubRepositoryEntity[] = [];
        const repoById = new Map<string, mjBizAppsTasksGitHubGitHubRepositoryEntity>();
        const repoByFullName = new Map<string, mjBizAppsTasksGitHubGitHubRepositoryEntity>();

        for (const repo of sortedRepos) {
            if (repo.ID) {
                repoById.set(NormalizeUUID(repo.ID), repo);
            }
            const owner = (repo.Owner ?? '').trim();
            const name = (repo.Name ?? '').trim();
            if (owner.length > 0 && name.length > 0) {
                repoByFullName.set(`${owner}/${name}`.toLowerCase(), repo);
            }
            if (repo.IsTracked) {
                activeRepos.push(repo);
            }
        }

        this._sortedRepositories = sortedRepos;
        this._activeRepositories = activeRepos;
        this._repositoryById = repoById;
        this._repositoryByFullName = repoByFullName;

        const identities = Array.isArray(this._identities) ? this._identities : [];
        const sortedIdentities = [...identities].sort((a, b) =>
            (a.GitHubLogin ?? '').localeCompare(b.GitHubLogin ?? '', undefined, { sensitivity: 'base' }),
        );

        const activeIdentities: mjBizAppsTasksGitHubGitHubIdentityEntity[] = [];
        const identityById = new Map<string, mjBizAppsTasksGitHubGitHubIdentityEntity>();
        const identityByLogin = new Map<string, mjBizAppsTasksGitHubGitHubIdentityEntity>();
        const byPerson = new Map<string, mjBizAppsTasksGitHubGitHubIdentityEntity[]>();
        const activeByPerson = new Map<string, mjBizAppsTasksGitHubGitHubIdentityEntity[]>();
        const byUser = new Map<string, mjBizAppsTasksGitHubGitHubIdentityEntity[]>();
        const activeByUser = new Map<string, mjBizAppsTasksGitHubGitHubIdentityEntity[]>();

        for (const identity of sortedIdentities) {
            const isActive = identity.IsActive !== false;
            if (isActive) {
                activeIdentities.push(identity);
            }
            if (identity.ID) {
                identityById.set(NormalizeUUID(identity.ID), identity);
            }
            const loginKey = (identity.GitHubLogin ?? '').trim().replace(/^@/, '').toLowerCase();
            if (loginKey.length > 0) {
                identityByLogin.set(loginKey, identity);
            }
            if (identity.PersonID) {
                const personKey = NormalizeUUID(identity.PersonID);
                const list = byPerson.get(personKey) ?? [];
                list.push(identity);
                byPerson.set(personKey, list);
                if (isActive) {
                    const activeList = activeByPerson.get(personKey) ?? [];
                    activeList.push(identity);
                    activeByPerson.set(personKey, activeList);
                }
            }
            const ghUserKey = (identity.GitHubUserID ?? '').trim().toLowerCase();
            if (ghUserKey.length > 0) {
                const list = byUser.get(ghUserKey) ?? [];
                list.push(identity);
                byUser.set(ghUserKey, list);
                if (isActive) {
                    const activeList = activeByUser.get(ghUserKey) ?? [];
                    activeList.push(identity);
                    activeByUser.set(ghUserKey, activeList);
                }
            }
        }

        this._sortedIdentities = sortedIdentities;
        this._activeIdentities = activeIdentities;
        this._identityById = identityById;
        this._identityByGitHubLogin = identityByLogin;
        this._identitiesByPersonId = byPerson;
        this._activeIdentitiesByPersonId = activeByPerson;
        this._identitiesByUserId = byUser;
        this._activeIdentitiesByUserId = activeByUser;
    }
}
