import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import {
    BaseEntity,
    CompositeKey,
    Metadata,
    ProviderType,
    type BaseEntityEvent,
    type EntityInfo,
    type IMetadataProvider,
    type IRunViewProvider,
    type RunViewParams,
    type RunViewResult,
    type UserInfo,
} from '@memberjunction/core';
import { MJGlobal } from '@memberjunction/global';
import {
    GITHUB_IDENTITIES_ENTITY_NAME,
    GITHUB_REPOSITORIES_ENTITY_NAME,
    GitHubTasksEngineBase,
    type mjBizAppsTasksGitHubGitHubIdentityEntity,
    type mjBizAppsTasksGitHubGitHubRepositoryEntity,
} from '../index.js';

interface RepoSeed {
    ID: string;
    Owner: string;
    Name: string;
    DefaultBranch?: string;
    IsTracked: boolean;
    ImportRule?: 'AssignedOnly' | 'All';
}

interface IdentitySeed {
    ID: string;
    GitHubLogin: string;
    PersonID: string;
    GitHubUserID?: string | null;
    IsActive: boolean;
}

interface MockEngineProviderOptions {
    providerType?: ProviderType;
    connectionString?: string;
    currentUser?: UserInfo;
    repos?: RepoSeed[];
    identities?: IdentitySeed[];
    canReadRepos?: boolean;
    canReadIdentities?: boolean;
}

const USER_A: UserInfo = {
    ID: '10000000-0000-4000-8000-000000000001',
    Name: 'Alice User',
    Email: 'alice@example.com',
} as UserInfo;

const USER_B: UserInfo = {
    ID: '10000000-0000-4000-8000-000000000002',
    Name: 'Bob Impersonated',
    Email: 'bob@example.com',
} as UserInfo;

const PERSON_ALICE = '20000000-0000-4000-8000-000000000001';
const PERSON_BOB = '20000000-0000-4000-8000-000000000002';

const REPO_MJ_ID = '30000000-0000-4000-8000-000000000001';
const REPO_TASKS_ID = '30000000-0000-4000-8000-000000000002';
const REPO_ARCHIVE_ID = '30000000-0000-4000-8000-000000000003';

const IDENT_ALICE_1 = '40000000-0000-4000-8000-000000000001';
const IDENT_ALICE_2 = '40000000-0000-4000-8000-000000000002';
const IDENT_BOB_1 = '40000000-0000-4000-8000-000000000003';

function makeEntityInfo(name: string, canRead: boolean): EntityInfo {
    return {
        ID: name === GITHUB_REPOSITORIES_ENTITY_NAME ? '90000000-0000-4000-8000-000000000001' : '90000000-0000-4000-8000-000000000002',
        Name: name,
        PrimaryKeys: [{ Name: 'ID', IsUniqueIdentifier: true }],
        Fields: [{ Name: 'ID' }],
        IsParentType: false,
        GetUserPermisions: () => ({
            CanRead: canRead,
            CanCreate: true,
            CanUpdate: true,
            CanDelete: true,
        }),
    } as EntityInfo;
}

class FakeCachedEntity {
    public EntityInfo: EntityInfo;
    public ProviderToUse?: IMetadataProvider;
    private _data: Record<string, string | number | boolean | Date | null | undefined> = {};

    public constructor(entityInfo: EntityInfo, initial?: Record<string, string | number | boolean | Date | null | undefined>) {
        this.EntityInfo = entityInfo;
        if (initial) {
            this.assignData(initial);
        }
    }

    public get PrimaryKey(): CompositeKey {
        const ck = new CompositeKey();
        const id = this._data['ID'];
        if (typeof id === 'string') {
            ck.KeyValuePairs.push({ FieldName: 'ID', Value: id });
        }
        return ck;
    }

    public HoldsEveryField(): boolean {
        return true;
    }

    public Get(fieldName: string): string | number | boolean | Date | null | undefined {
        return this._data[fieldName];
    }

    public GetAll(): Record<string, string | number | boolean | Date | null | undefined> {
        return { ...this._data };
    }

    public async LoadFromData(data: Record<string, string | number | boolean | Date | null | undefined>): Promise<boolean> {
        this.assignData(data);
        return true;
    }

    private assignData(data: Record<string, string | number | boolean | Date | null | undefined>): void {
        this._data = { ...data };
        Object.assign(this, data);
    }
}

function createMockProvider(opts: MockEngineProviderOptions = {}) {
    const repoEntityInfo = makeEntityInfo(GITHUB_REPOSITORIES_ENTITY_NAME, opts.canReadRepos ?? true);
    const identityEntityInfo = makeEntityInfo(GITHUB_IDENTITIES_ENTITY_NAME, opts.canReadIdentities ?? true);
    const entities = [repoEntityInfo, identityEntityInfo];
    const queriedEntities: string[] = [];
    let runViewsCalls = 0;

    let currentUser: UserInfo | undefined = opts.currentUser;
    const repos = (opts.repos ?? []).map((r) => new FakeCachedEntity(repoEntityInfo, { ...r }));
    const identities = (opts.identities ?? []).map((i) => new FakeCachedEntity(identityEntityInfo, { ...i }));

    const runSingle = async (params: RunViewParams): Promise<RunViewResult> => {
        queriedEntities.push(params.EntityName);
        if (params.EntityName === GITHUB_REPOSITORIES_ENTITY_NAME) {
            return {
                Success: true,
                Results: [...repos],
                RowCount: repos.length,
                TotalRowCount: repos.length,
                ExecutionTime: 1,
                ErrorMessage: '',
                UserViewRunID: '',
            };
        }
        if (params.EntityName === GITHUB_IDENTITIES_ENTITY_NAME) {
            return {
                Success: true,
                Results: [...identities],
                RowCount: identities.length,
                TotalRowCount: identities.length,
                ExecutionTime: 1,
                ErrorMessage: '',
                UserViewRunID: '',
            };
        }
        return {
            Success: true,
            Results: [],
            RowCount: 0,
            TotalRowCount: 0,
            ExecutionTime: 1,
            ErrorMessage: '',
            UserViewRunID: '',
        };
    };

    const providerObj: Partial<IMetadataProvider & IRunViewProvider> = {
        ProviderType: opts.providerType ?? ProviderType.Network,
        InstanceConnectionString: opts.connectionString,
        get CurrentUser(): UserInfo {
            return currentUser as UserInfo;
        },
        Entities: entities,
        EntityByName: (name: string) => entities.find((e) => e.Name === name),
        GetEntityObject: (async (entityName: string) => {
            const info = entities.find((e) => e.Name === entityName) ?? repoEntityInfo;
            return new FakeCachedEntity(info);
        }) as IMetadataProvider['GetEntityObject'],
        RunView: runSingle as IRunViewProvider['RunView'],
        RunViews: (async (views: RunViewParams[]) => {
            runViewsCalls += 1;
            return Promise.all(views.map((v) => runSingle(v)));
        }) as IRunViewProvider['RunViews'],
    };

    return {
        provider: providerObj as IMetadataProvider & IRunViewProvider,
        repoEntityInfo,
        identityEntityInfo,
        queriedEntities,
        getRunViewsCalls: () => runViewsCalls,
        setCurrentUser: (next: UserInfo | undefined) => {
            currentUser = next;
        },
    };
}

describe('GitHubTasksEngineBase', () => {
    const previousMetadataProvider = Metadata.Provider;

    beforeEach(() => {
        GitHubTasksEngineBase.Instance.ResetCaches();
    });

    afterEach(() => {
        GitHubTasksEngineBase.Instance.ResetCaches();
        Metadata.Provider = previousMetadataProvider;
        vi.restoreAllMocks();
    });

    it('is a BaseSingleton with O(1) repository and identity lookups and CacheLocal=true on non-RLS configs', async () => {
        expect(GitHubTasksEngineBase.Instance).toBe(GitHubTasksEngineBase.Instance);

        const mock = createMockProvider({
            currentUser: USER_A,
            repos: [
                { ID: REPO_TASKS_ID, Owner: 'MemberJunction', Name: 'bizapps-tasks-github', DefaultBranch: 'next', IsTracked: true, ImportRule: 'All' },
                { ID: REPO_MJ_ID, Owner: 'MemberJunction', Name: 'MJ', DefaultBranch: 'next', IsTracked: true, ImportRule: 'AssignedOnly' },
                { ID: REPO_ARCHIVE_ID, Owner: 'AcmeCorp', Name: 'legacy', DefaultBranch: 'main', IsTracked: false, ImportRule: 'AssignedOnly' },
            ],
            identities: [
                { ID: IDENT_ALICE_1, GitHubLogin: 'AliceDev', PersonID: PERSON_ALICE, GitHubUserID: '1001', IsActive: true },
                { ID: IDENT_ALICE_2, GitHubLogin: 'alice-old', PersonID: PERSON_ALICE, GitHubUserID: '1002', IsActive: false },
                { ID: IDENT_BOB_1, GitHubLogin: 'bob-reviewer', PersonID: PERSON_BOB, GitHubUserID: '2001', IsActive: true },
            ],
        });

        const engine = GitHubTasksEngineBase.Instance;
        await engine.Config(false, USER_A, mock.provider);

        expect(mock.getRunViewsCalls()).toBe(1);
        expect(mock.queriedEntities).toEqual([
            GITHUB_REPOSITORIES_ENTITY_NAME,
            GITHUB_IDENTITIES_ENTITY_NAME,
        ]);

        // Both configs are non-RLS and use AutoRefresh + CacheLocal
        expect(engine.ReadonlyConfigs).toHaveLength(2);
        for (const cfg of engine.ReadonlyConfigs) {
            expect(cfg.AutoRefresh).toBe(true);
            expect(cfg.CacheLocal).toBe(true);
        }

        // Sorted repositories & active (tracked) subset
        expect(engine.Repositories.map((r) => `${r.Owner}/${r.Name}`)).toEqual([
            'AcmeCorp/legacy',
            'MemberJunction/bizapps-tasks-github',
            'MemberJunction/MJ',
        ]);
        expect(engine.ActiveRepositories.map((r) => r.ID)).toEqual([REPO_TASKS_ID, REPO_MJ_ID]);

        // O(1) case-insensitive repository lookups
        expect(engine.RepositoryById(REPO_MJ_ID.toUpperCase())?.Name).toBe('MJ');
        expect(engine.RepositoryByFullName('memberjunction/mj')?.ID).toBe(REPO_MJ_ID);
        expect(engine.RepositoryByFullName('unknown/repo')).toBeUndefined();

        // O(1) identity lookups
        expect(engine.Identities).toHaveLength(3);
        expect(engine.ActiveIdentities).toHaveLength(2);
        expect(engine.IdentityById(IDENT_BOB_1.toUpperCase())?.GitHubLogin).toBe('bob-reviewer');
        expect(engine.IdentityByGitHubLogin('@alicedev')?.ID).toBe(IDENT_ALICE_1);
        expect(engine.IdentityByGitHubLogin('alice-old', false)?.ID).toBe(IDENT_ALICE_2);
        expect(engine.IdentityByGitHubLogin('alice-old', true)).toBeUndefined();
        expect(engine.IdentitiesByPersonId(PERSON_ALICE, false)).toHaveLength(2);
        expect(engine.IdentitiesByPersonId(PERSON_ALICE, true).map((i) => i.ID)).toEqual([IDENT_ALICE_1]);
        expect(engine.IdentitiesByUserId('1001', true).map((i) => i.ID)).toEqual([IDENT_ALICE_1]);
        expect(engine.IdentitiesByUserId('1002', true)).toHaveLength(0);
        expect(engine.IdentitiesByUserId('1002', false).map((i) => i.ID)).toEqual([IDENT_ALICE_2]);

        // Second EnsureLoaded reuses warm cache with zero additional RunViews calls
        await engine.EnsureLoaded(USER_A, mock.provider);
        expect(mock.getRunViewsCalls()).toBe(1);
    });

    it('follows active Config provider or live Metadata.Provider without latching to stale bootstrap provider during impersonation', async () => {
        const provider1 = createMockProvider({
            currentUser: USER_A,
            repos: [{ ID: REPO_MJ_ID, Owner: 'OrgA', Name: 'RepoA', IsTracked: true }],
            identities: [{ ID: IDENT_ALICE_1, GitHubLogin: 'alice-a', PersonID: PERSON_ALICE, IsActive: true }],
        });
        const provider2 = createMockProvider({
            currentUser: USER_B,
            repos: [{ ID: REPO_TASKS_ID, Owner: 'OrgB', Name: 'RepoB', IsTracked: true }],
            identities: [{ ID: IDENT_BOB_1, GitHubLogin: 'bob-b', PersonID: PERSON_BOB, IsActive: true }],
        });

        const engine = GitHubTasksEngineBase.Instance;

        // 1. Initial bootstrap with provider1
        await engine.Config(false, USER_A, provider1.provider);
        expect(engine.ProviderToUse).toBe(provider1.provider);
        expect(engine.RepositoryByFullName('OrgA/RepoA')?.ID).toBe(REPO_MJ_ID);

        // 2. Switch to provider2 via Config() — ProviderToUse MUST update and reload
        await engine.Config(false, USER_B, provider2.provider);
        expect(engine.ProviderToUse).toBe(provider2.provider);
        expect(engine.RepositoryByFullName('OrgA/RepoA')).toBeUndefined();
        expect(engine.RepositoryByFullName('OrgB/RepoB')?.ID).toBe(REPO_TASKS_ID);
        expect(engine.IdentityByGitHubLogin('bob-b')?.ID).toBe(IDENT_BOB_1);

        // 3. Switch live Metadata.Provider back to provider1 and call Config(false) without explicit provider arg
        Metadata.Provider = provider1.provider;
        await engine.Config(false);
        expect(engine.ProviderToUse).toBe(provider1.provider);
        expect(engine.RepositoryByFullName('OrgA/RepoA')?.ID).toBe(REPO_MJ_ID);
        expect(engine.RepositoryByFullName('OrgB/RepoB')).toBeUndefined();

        // 4. Swap live Metadata.Provider to provider2 — read guard clears stale state immediately, EnsureLoaded reloads
        Metadata.Provider = provider2.provider;
        expect(engine.ProviderToUse).toBe(provider2.provider);
        expect(engine.Repositories).toHaveLength(0);
        await engine.EnsureLoaded();
        expect(engine.RepositoryByFullName('OrgB/RepoB')?.ID).toBe(REPO_TASKS_ID);
    });

    it('detects userId switches on Network providers and clears stale caches before reloading', async () => {
        const mock = createMockProvider({
            providerType: ProviderType.Network,
            currentUser: USER_A,
            repos: [{ ID: REPO_MJ_ID, Owner: 'MemberJunction', Name: 'MJ', IsTracked: true }],
            identities: [{ ID: IDENT_ALICE_1, GitHubLogin: 'alice-dev', PersonID: PERSON_ALICE, IsActive: true }],
        });

        const engine = GitHubTasksEngineBase.Instance;
        await engine.EnsureLoaded(undefined, mock.provider);
        expect(engine.Repositories).toHaveLength(1);
        expect(mock.getRunViewsCalls()).toBe(1);

        // Impersonation swaps CurrentUser on the same provider instance
        mock.setCurrentUser(USER_B);

        // Stale cache is cleared immediately on read even before EnsureLoaded runs
        expect(engine.Repositories).toHaveLength(0);
        expect(engine.RepositoryById(REPO_MJ_ID)).toBeUndefined();

        // EnsureLoaded detects the userId switch and reloads fresh
        await engine.EnsureLoaded(undefined, mock.provider);
        expect(mock.getRunViewsCalls()).toBe(2);
        expect(engine.Repositories).toHaveLength(1);
    });

    it('shares process-wide cache across Database providers with the same InstanceConnectionString', async () => {
        const dbProvider1 = createMockProvider({
            providerType: ProviderType.Database,
            connectionString: 'mssql://localhost:1433/MJ_Test',
            repos: [{ ID: REPO_MJ_ID, Owner: 'MemberJunction', Name: 'MJ', IsTracked: true }],
            identities: [{ ID: IDENT_ALICE_1, GitHubLogin: 'alice-dev', PersonID: PERSON_ALICE, IsActive: true }],
        });
        const dbProvider2 = createMockProvider({
            providerType: ProviderType.Database,
            connectionString: 'mssql://localhost:1433/MJ_Test',
            repos: [{ ID: REPO_MJ_ID, Owner: 'MemberJunction', Name: 'MJ', IsTracked: true }],
            identities: [{ ID: IDENT_ALICE_1, GitHubLogin: 'alice-dev', PersonID: PERSON_ALICE, IsActive: true }],
        });

        const engine = GitHubTasksEngineBase.Instance;
        await engine.EnsureLoaded(USER_A, dbProvider1.provider);
        expect(dbProvider1.getRunViewsCalls()).toBe(1);

        // Second per-request provider on same DB connection reuses warm cache
        await engine.EnsureLoaded(USER_B, dbProvider2.provider);
        expect(dbProvider2.getRunViewsCalls()).toBe(0);
        expect(engine.RepositoryById(REPO_MJ_ID)?.Name).toBe('MJ');
    });

    it('gates reads and loads using EntityInfo.GetUserPermisions(user).CanRead', async () => {
        // User cannot read Git Hub Repositories, can read Git Hub Identities
        const partialMock = createMockProvider({
            currentUser: USER_A,
            canReadRepos: false,
            canReadIdentities: true,
            repos: [{ ID: REPO_MJ_ID, Owner: 'MemberJunction', Name: 'MJ', IsTracked: true }],
            identities: [{ ID: IDENT_ALICE_1, GitHubLogin: 'alice-dev', PersonID: PERSON_ALICE, IsActive: true }],
        });

        const engine = GitHubTasksEngineBase.Instance;
        await engine.Config(false, USER_A, partialMock.provider);

        expect(partialMock.queriedEntities).toEqual([GITHUB_IDENTITIES_ENTITY_NAME]);
        expect(engine.CanReadRepositories(USER_A, partialMock.provider)).toBe(false);
        expect(engine.CanReadIdentities(USER_A, partialMock.provider)).toBe(true);
        expect(engine.Repositories).toEqual([]);
        expect(engine.ActiveRepositories).toEqual([]);
        expect(engine.RepositoryById(REPO_MJ_ID)).toBeUndefined();
        expect(engine.RepositoryByFullName('MemberJunction/MJ')).toBeUndefined();
        expect(engine.IdentityByGitHubLogin('alice-dev')?.ID).toBe(IDENT_ALICE_1);

        // User denied BOTH entities -> issues zero RunViews queries
        const fullyDeniedMock = createMockProvider({
            currentUser: USER_B,
            canReadRepos: false,
            canReadIdentities: false,
            repos: [{ ID: REPO_MJ_ID, Owner: 'MemberJunction', Name: 'MJ', IsTracked: true }],
            identities: [{ ID: IDENT_ALICE_1, GitHubLogin: 'alice-dev', PersonID: PERSON_ALICE, IsActive: true }],
        });
        await engine.Config(false, USER_B, fullyDeniedMock.provider);
        expect(fullyDeniedMock.getRunViewsCalls()).toBe(0);
        expect(engine.Repositories).toEqual([]);
        expect(engine.Identities).toEqual([]);
    });

    it('rebuilds O(1) lookup maps immediately on BaseEntity save and delete auto-refresh events', async () => {
        const mock = createMockProvider({
            currentUser: USER_A,
            repos: [
                { ID: REPO_MJ_ID, Owner: 'MemberJunction', Name: 'MJ', DefaultBranch: 'next', IsTracked: true },
            ],
            identities: [
                { ID: IDENT_ALICE_1, GitHubLogin: 'alice-dev', PersonID: PERSON_ALICE, GitHubUserID: '1001', IsActive: true },
            ],
        });

        const engine = GitHubTasksEngineBase.Instance;
        await engine.Config(false, USER_A, mock.provider);
        expect(engine.RepositoryByFullName('MemberJunction/bizapps-tasks-github')).toBeUndefined();

        const changeTypes: string[] = [];
        const sub = engine.DataChange$.subscribe((evt) => {
            changeTypes.push(`${evt.config.PropertyName}:${evt.changeType}`);
        });

        try {
            // 1. Save a new repository via MJGlobal BaseEntity event
            const addedRepo = new FakeCachedEntity(mock.repoEntityInfo, {
                ID: REPO_TASKS_ID,
                Owner: 'MemberJunction',
                Name: 'bizapps-tasks-github',
                DefaultBranch: 'next',
                IsTracked: true,
            });
            const saveRepoEvent: BaseEntityEvent = {
                type: 'save',
                saveSubType: 'create',
                baseEntity: addedRepo as BaseEntity,
            };
            MJGlobal.Instance.RaiseEvent({
                component: addedRepo,
                event: 'ComponentEvent',
                eventCode: BaseEntity.BaseEventCode,
                args: saveRepoEvent,
            });

            // Wait one microtask turn for async event subscription handler to settle
            await new Promise((resolve) => setTimeout(resolve, 10));

            const added = engine.RepositoryByFullName('memberjunction/bizapps-tasks-github');
            expect(added?.ID).toBe(REPO_TASKS_ID);
            expect(engine.RepositoryById(REPO_TASKS_ID)?.Name).toBe('bizapps-tasks-github');
            expect(engine.ActiveRepositories).toHaveLength(2);
            expect(changeTypes).toContain('_repositories:add');

            // 2. Delete an identity via MJGlobal BaseEntity event
            const deletedIdentity = new FakeCachedEntity(mock.identityEntityInfo, {
                ID: IDENT_ALICE_1,
                GitHubLogin: 'alice-dev',
                PersonID: PERSON_ALICE,
                GitHubUserID: '1001',
                IsActive: true,
            });
            const deleteIdentityEvent: BaseEntityEvent = {
                type: 'delete',
                baseEntity: deletedIdentity as BaseEntity,
            };
            MJGlobal.Instance.RaiseEvent({
                component: deletedIdentity,
                event: 'ComponentEvent',
                eventCode: BaseEntity.BaseEventCode,
                args: deleteIdentityEvent,
            });

            await new Promise((resolve) => setTimeout(resolve, 10));

            expect(engine.IdentityById(IDENT_ALICE_1)).toBeUndefined();
            expect(engine.IdentityByGitHubLogin('alice-dev')).toBeUndefined();
            expect(engine.IdentitiesByPersonId(PERSON_ALICE)).toHaveLength(0);
            expect(engine.IdentitiesByUserId('1001')).toHaveLength(0);
            expect(changeTypes).toContain('_identities:delete');
        } finally {
            sub.unsubscribe();
        }
    });
});
