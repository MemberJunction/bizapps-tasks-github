import { createSign } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { homedir } from 'node:os';
import { resolve } from 'node:path';
import {
    LogError,
    RunView,
    type IMetadataProvider,
    type IRunViewProvider,
    type UserInfo,
} from '@memberjunction/core';
import type { MJCompanyIntegrationEntityType } from '@memberjunction/core-entities';
import { CredentialEngine } from '@memberjunction/credentials';
import { GetGlobalObjectStore, IsValidUUID } from '@memberjunction/global';
import { AssertValidUUID } from './sql-safety.js';

export const GITHUB_INTEGRATION_NAME = 'GitHub';
export const DEFAULT_GITHUB_API_BASE_URL = 'https://api.github.com';

/**
 * Shared Global Object Store key used across `@memberjunction/core-actions`,
 * `@mj-biz-apps/tasks-github-core`, and `@mj-biz-apps/software-factory-core`
 * so minted 1-hour GitHub App installation tokens are reused process-wide.
 */
export const INSTALLATION_TOKEN_CACHE_GLOBAL_KEY = '___SINGLETON__GitHubInstallationTokenCache';

const TOKEN_CACHE_TTL_MS = 50 * 60 * 1000;

export type GitHubPermissionLevel = 'read' | 'write' | 'admin';

export interface GitHubInstallationPermissions {
    contents?: GitHubPermissionLevel;
    issues?: GitHubPermissionLevel;
    pull_requests?: GitHubPermissionLevel;
    checks?: GitHubPermissionLevel;
    statuses?: GitHubPermissionLevel;
    actions?: GitHubPermissionLevel;
    metadata?: 'read';
}

export const DEFAULT_TASKS_GITHUB_READ_PERMISSIONS: Readonly<GitHubInstallationPermissions> = Object.freeze({
    contents: 'read',
    issues: 'read',
    pull_requests: 'read',
    checks: 'read',
    statuses: 'read',
    metadata: 'read',
});

export type GitHubVaultAuthSource =
    | 'credential'
    | 'user-delegated'
    | 'company-integration'
    | 'default-credential'
    | 'environment';

export type GitHubVaultAuthKind = 'github-app' | 'pat' | 'oauth-3lo';

export interface ResolvedGitHubVaultAuth {
    token: string;
    apiBaseUrl: string;
    source: GitHubVaultAuthSource;
    authKind: GitHubVaultAuthKind;
    credentialId?: string;
    defaultOwner?: string;
    allowedRepositories?: string[];
}

export interface GitHubAppAuthConfig {
    appId: string;
    installationId: string;
    privateKey: string;
    apiBaseUrl?: string;
}

export interface MintGitHubInstallationTokenOptions {
    repositories?: string[];
    permissions?: GitHubInstallationPermissions;
    fetchImpl?: typeof fetch;
    nowSeconds?: number;
    skipCache?: boolean;
}

export interface ResolveGitHubVaultAuthOptions {
    credentialId?: string | null;
    credentialName?: string | null;
    companyId?: string | null;
    useUserDelegatedAuth?: boolean;
    targetRepository?: { owner: string; repo: string };
    permissions?: GitHubInstallationPermissions;
    contextUser?: UserInfo;
    provider?: IMetadataProvider & IRunViewProvider;
    fetchImpl?: typeof fetch;
    env?: NodeJS.ProcessEnv;
}

export interface ResolveGitHubWebhookSecretOptions {
    explicitSecret?: string | null;
    credentialId?: string | null;
    contextUser?: UserInfo;
    provider?: IMetadataProvider;
    env?: NodeJS.ProcessEnv;
}

interface CachedInstallationToken {
    token: string;
    expiresAtMs: number;
}

interface ParsedCompanyIntegrationConfig {
    baseUrl?: string;
    BaseURL?: string;
    apiUrl?: string;
    apiBaseUrl?: string;
    owner?: string;
    Owner?: string;
    defaultOwner?: string;
    DefaultOwner?: string;
    organization?: string;
    Organization?: string;
    org?: string;
    repositories?: string | string[];
    Repositories?: string | string[];
    allowedRepositories?: string | string[];
    AllowedRepositories?: string | string[];
    repo?: string;
    token?: string;
    Token?: string;
    apiToken?: string;
    personalAccessToken?: string;
    accessToken?: string;
    AccessToken?: string;
    githubToken?: string;
    appId?: string | number;
    AppId?: string | number;
    githubAppId?: string | number;
    installationId?: string | number;
    InstallationId?: string | number;
    githubInstallationId?: string | number;
    privateKey?: string;
    PrivateKey?: string;
    githubPrivateKey?: string;
    webhookSecret?: string;
    WebhookSecret?: string;
}

interface GitHubInstallationTokenExchangePayload {
    token?: string;
    expires_at?: string;
    message?: string;
}

export class GitHubRepoNotAllowedError extends Error {
    public readonly Owner: string;
    public readonly Repo: string;

    public constructor(message: string, owner: string, repo: string) {
        super(message);
        this.name = 'GitHubRepoNotAllowedError';
        this.Owner = owner;
        this.Repo = repo;
    }
}

export function TrimTrailingSlashes(value: string): string {
    let end = value.length;
    while (end > 0 && value.charCodeAt(end - 1) === 47 /* / */) {
        end -= 1;
    }
    return end === value.length ? value : value.slice(0, end);
}

export function NormalizeGitHubApiBaseUrl(rawUrl: string | null | undefined): string {
    const trimmed = (rawUrl ?? '').trim();
    if (!trimmed) {
        return DEFAULT_GITHUB_API_BASE_URL;
    }
    const withoutTrailing = TrimTrailingSlashes(trimmed);
    if (withoutTrailing.toLowerCase() === 'https://github.com') {
        return DEFAULT_GITHUB_API_BASE_URL;
    }
    return withoutTrailing;
}

export function NormalizePrivateKey(rawKey: string | null | undefined): string | null {
    if (!rawKey || !rawKey.trim()) {
        return null;
    }
    return rawKey.trim().replace(/\\n/g, '\n');
}

function base64url(input: Buffer | string): string {
    return Buffer.from(input).toString('base64url');
}

/**
 * Signs a short-lived RS256 JWT assertion for a GitHub App (`iat = now - 60s`, `exp = now + 540s`).
 */
export function BuildGitHubAppJwt(
    appId: string,
    privateKeyPem: string,
    nowSeconds: number = Math.floor(Date.now() / 1000),
): string {
    const normalizedKey = NormalizePrivateKey(privateKeyPem);
    if (!normalizedKey) {
        throw new Error('GitHub App private key is empty or invalid.');
    }
    const header = base64url(JSON.stringify({ alg: 'RS256', typ: 'JWT' }));
    const payload = base64url(
        JSON.stringify({
            iat: nowSeconds - 60,
            exp: nowSeconds + 540,
            iss: appId,
        }),
    );
    const signer = createSign('RSA-SHA256');
    signer.update(`${header}.${payload}`);
    const signature = base64url(signer.sign(normalizedKey));
    return `${header}.${payload}.${signature}`;
}

function getInstallationTokenCache(): Map<string, CachedInstallationToken> {
    const store = GetGlobalObjectStore();
    if (!store) {
        return new Map<string, CachedInstallationToken>();
    }
    let existing = store[INSTALLATION_TOKEN_CACHE_GLOBAL_KEY] as Map<string, CachedInstallationToken> | undefined;
    if (!existing) {
        existing = new Map<string, CachedInstallationToken>();
        store[INSTALLATION_TOKEN_CACHE_GLOBAL_KEY] = existing;
    }
    return existing;
}

function buildTokenCacheKey(
    config: GitHubAppAuthConfig,
    repos: string[] | undefined,
    permissions: GitHubInstallationPermissions | undefined,
): string {
    const baseUrlPart = NormalizeGitHubApiBaseUrl(config.apiBaseUrl).toLowerCase();
    const repoPart = repos && repos.length > 0 ? [...repos].sort().join(',') : '*';
    const permPart = permissions
        ? Object.entries(permissions)
              .filter(([, v]) => v !== undefined)
              .sort(([a], [b]) => a.localeCompare(b))
              .map(([k, v]) => `${k}:${v}`)
              .join(',')
        : '*';
    return `${baseUrlPart}|${config.appId}|${config.installationId}|${repoPart}|${permPart}`;
}

export function ClearGitHubInstallationTokenCache(): void {
    getInstallationTokenCache().clear();
}

export async function MintGitHubInstallationToken(
    config: GitHubAppAuthConfig,
    options?: MintGitHubInstallationTokenOptions,
): Promise<string> {
    const tokenCache = getInstallationTokenCache();
    const cacheKey = buildTokenCacheKey(config, options?.repositories, options?.permissions);
    const nowMs = options?.nowSeconds !== undefined ? options.nowSeconds * 1000 : Date.now();

    if (!options?.skipCache) {
        const cached = tokenCache.get(cacheKey);
        if (cached && cached.expiresAtMs > nowMs) {
            return cached.token;
        }
    }

    const jwt = BuildGitHubAppJwt(config.appId, config.privateKey, options?.nowSeconds);
    const baseUrl = NormalizeGitHubApiBaseUrl(config.apiBaseUrl);
    const url = `${baseUrl}/app/installations/${encodeURIComponent(config.installationId)}/access_tokens`;

    const bodyPayload: {
        repositories?: string[];
        permissions?: GitHubInstallationPermissions;
    } = {};
    if (options?.repositories && options.repositories.length > 0) {
        bodyPayload.repositories = options.repositories;
    }
    if (options?.permissions && Object.keys(options.permissions).length > 0) {
        bodyPayload.permissions = options.permissions;
    }

    const fetchFn = options?.fetchImpl ?? fetch;
    const response = await fetchFn(url, {
        method: 'POST',
        headers: {
            Authorization: `Bearer ${jwt}`,
            Accept: 'application/vnd.github+json',
            'X-GitHub-Api-Version': '2022-11-28',
            'User-Agent': 'MemberJunction-GitHub-Integration',
            'Content-Type': 'application/json',
        },
        body: Object.keys(bodyPayload).length > 0 ? JSON.stringify(bodyPayload) : undefined,
    });

    if (!response.ok) {
        let detail = '';
        try {
            const text = await response.text();
            const parsed = JSON.parse(text) as GitHubInstallationTokenExchangePayload;
            detail = parsed.message ?? text.slice(0, 200);
        } catch {
            /* ignore parse error */
        }
        throw new Error(
            `GitHub App installation ${config.installationId} token exchange failed with HTTP ${response.status}` +
                (detail ? `: ${detail}` : ''),
        );
    }

    const data = (await response.json()) as GitHubInstallationTokenExchangePayload;
    if (!data?.token) {
        throw new Error(`GitHub App installation ${config.installationId} returned no access token.`);
    }

    tokenCache.set(cacheKey, {
        token: data.token,
        expiresAtMs: nowMs + TOKEN_CACHE_TTL_MS,
    });

    return data.token;
}

export function ParseAllowedRepositories(raw: string | readonly string[] | null | undefined): string[] {
    if (!raw) {
        return [];
    }
    if (Array.isArray(raw)) {
        return raw
            .filter((entry): entry is string => typeof entry === 'string')
            .map((s) => s.trim())
            .filter((s) => s.length > 0);
    }
    if (typeof raw !== 'string' || !raw.trim()) {
        return [];
    }
    return raw
        .split(/[,\n]+/)
        .map((s) => s.trim())
        .filter((s) => s.length > 0);
}

export function IsRepositoryAllowed(
    owner: string,
    repo: string,
    allowedRepositories: readonly string[] | undefined,
): boolean {
    if (!allowedRepositories || allowedRepositories.length === 0) {
        return true;
    }
    const normalizedOwner = owner.trim().toLowerCase();
    const normalizedRepo = repo.trim().toLowerCase();
    const full = `${normalizedOwner}/${normalizedRepo}`;

    for (const rawPattern of allowedRepositories) {
        const pattern = rawPattern.trim().toLowerCase();
        if (!pattern) continue;
        if (pattern === '*' || pattern === '*/*') {
            return true;
        }
        if (pattern.endsWith('/*')) {
            const patternOwner = pattern.slice(0, -2);
            if (patternOwner === normalizedOwner) {
                return true;
            }
            continue;
        }
        if (!pattern.includes('/')) {
            if (pattern === normalizedRepo) {
                return true;
            }
            continue;
        }
        if (pattern === full) {
            return true;
        }
    }
    return false;
}

export function ResolveInstallationRepositoryScope(
    targetRepo: { owner: string; repo: string } | undefined,
    allowedRepositories: readonly string[] | undefined,
): string[] | undefined {
    if (targetRepo) {
        if (!IsRepositoryAllowed(targetRepo.owner, targetRepo.repo, allowedRepositories)) {
            throw new GitHubRepoNotAllowedError(
                `Repository '${targetRepo.owner}/${targetRepo.repo}' is not permitted by credential allowlist (${allowedRepositories?.join(', ')}).`,
                targetRepo.owner,
                targetRepo.repo,
            );
        }
        return [targetRepo.repo];
    }

    if (!allowedRepositories || allowedRepositories.length === 0) {
        return undefined;
    }

    const explicitRepos: string[] = [];
    for (const pattern of allowedRepositories) {
        const trimmed = pattern.trim();
        if (trimmed.includes('*')) {
            return undefined;
        }
        const slashIdx = trimmed.indexOf('/');
        const repoName = slashIdx >= 0 ? trimmed.slice(slashIdx + 1).trim() : trimmed;
        if (repoName && !explicitRepos.includes(repoName)) {
            explicitRepos.push(repoName);
        }
    }
    return explicitRepos.length > 0 ? explicitRepos : undefined;
}

export function ReadGitHubAppFromEnv(env: NodeJS.ProcessEnv = process.env): GitHubAppAuthConfig | null {
    const appId = (env.GITHUB_APP_ID ?? '').trim();
    const installationId = (env.GITHUB_APP_INSTALLATION_ID ?? '').trim();
    if (!appId || !installationId) {
        return null;
    }

    let privateKey: string | null = null;
    const keyPath = (env.GITHUB_APP_PRIVATE_KEY_PATH ?? '').trim();
    if (keyPath) {
        const resolved = keyPath.startsWith('~/') ? resolve(homedir(), keyPath.slice(2)) : resolve(keyPath);
        try {
            privateKey = NormalizePrivateKey(readFileSync(resolved, 'utf-8'));
        } catch {
            privateKey = null;
        }
    }
    if (!privateKey) {
        privateKey = NormalizePrivateKey(env.GITHUB_APP_PRIVATE_KEY);
    }
    if (!privateKey) {
        return null;
    }

    return {
        appId,
        installationId,
        privateKey,
        apiBaseUrl: NormalizeGitHubApiBaseUrl(env.GITHUB_API_URL),
    };
}

async function hydrateFromValuesMap(
    values: Record<string, string | undefined>,
    source: GitHubVaultAuthSource,
    options: {
        credentialId?: string;
        targetRepository?: { owner: string; repo: string };
        permissions?: GitHubInstallationPermissions;
        fetchImpl?: typeof fetch;
        fallbackApiBaseUrl?: string;
        fallbackOwner?: string;
        fallbackAllowedRepos?: string[];
    },
): Promise<ResolvedGitHubVaultAuth | null> {
    const parsedAllowed = ParseAllowedRepositories(values.allowedRepositories ?? values.AllowedRepositories);
    const allowedRepos = parsedAllowed.length > 0 ? parsedAllowed : (options.fallbackAllowedRepos ?? []);

    if (options.targetRepository) {
        const { owner, repo } = options.targetRepository;
        if (!IsRepositoryAllowed(owner, repo, allowedRepos)) {
            throw new GitHubRepoNotAllowedError(
                `Repository '${owner}/${repo}' is not permitted by credential allowlist (${allowedRepos.join(', ')}).`,
                owner,
                repo,
            );
        }
    }

    const defaultOwner =
        values.defaultOwner?.trim() ||
        values.DefaultOwner?.trim() ||
        values.owner?.trim() ||
        options.fallbackOwner?.trim() ||
        undefined;

    const apiBaseUrl = NormalizeGitHubApiBaseUrl(
        values.apiBaseUrl ?? values.baseUrl ?? values.BaseURL ?? values.apiUrl ?? options.fallbackApiBaseUrl,
    );

    const appId = (values.appId ?? values.AppId ?? values.githubAppId ?? '').trim();
    const installationId = (values.installationId ?? values.InstallationId ?? values.githubInstallationId ?? '').trim();
    const privateKey = NormalizePrivateKey(values.privateKey ?? values.PrivateKey ?? values.githubPrivateKey);

    if (appId && installationId && privateKey) {
        const repoScope = ResolveInstallationRepositoryScope(options.targetRepository, allowedRepos);
        const token = await MintGitHubInstallationToken(
            {
                appId,
                installationId,
                privateKey,
                apiBaseUrl,
            },
            {
                repositories: repoScope,
                permissions: options.permissions ?? DEFAULT_TASKS_GITHUB_READ_PERMISSIONS,
                fetchImpl: options.fetchImpl,
            },
        );
        return {
            token,
            apiBaseUrl,
            source,
            authKind: 'github-app',
            credentialId: options.credentialId,
            defaultOwner,
            allowedRepositories: allowedRepos.length > 0 ? allowedRepos : undefined,
        };
    }

    for (const key of [
        'token',
        'Token',
        'personalAccessToken',
        'apiToken',
        'apiKey',
        'APIKey',
        'api_key',
        'accessToken',
        'AccessToken',
        'githubToken',
    ]) {
        const candidate = values[key];
        if (typeof candidate === 'string' && candidate.trim().length > 0) {
            return {
                token: candidate.trim(),
                apiBaseUrl,
                source,
                authKind: source === 'user-delegated' ? 'oauth-3lo' : 'pat',
                credentialId: options.credentialId,
                defaultOwner,
                allowedRepositories: allowedRepos.length > 0 ? allowedRepos : undefined,
            };
        }
    }

    return null;
}

async function ensureCredentialEngineLoaded(
    contextUser: UserInfo | undefined,
    provider: IMetadataProvider | undefined,
): Promise<boolean> {
    try {
        await CredentialEngine.Instance.Config(false, contextUser, provider);
        return true;
    } catch {
        return false;
    }
}

async function resolveByCredentialIdOrName(
    credentialId: string | null | undefined,
    credentialName: string | null | undefined,
    contextUser: UserInfo | undefined,
    provider: IMetadataProvider | undefined,
    hydrateOpts: {
        targetRepository?: { owner: string; repo: string };
        permissions?: GitHubInstallationPermissions;
        fetchImpl?: typeof fetch;
        fallbackApiBaseUrl?: string;
        fallbackOwner?: string;
        fallbackAllowedRepos?: string[];
    },
): Promise<ResolvedGitHubVaultAuth | null> {
    const loaded = await ensureCredentialEngineLoaded(contextUser, provider);
    if (!loaded) {
        return null;
    }

    let targetName = credentialName?.trim() || undefined;
    const cleanId = credentialId?.trim() || undefined;
    if (cleanId) {
        const match = CredentialEngine.Instance.GetCredentialById(cleanId);
        if (!match) {
            LogError(`ResolveGitHubVaultAuth: MJ: Credentials record '${cleanId}' was not found.`);
            return null;
        }
        if (match.IsActive === false) {
            LogError(`ResolveGitHubVaultAuth: MJ: Credentials record '${match.Name}' is inactive.`);
            return null;
        }
        targetName = match.Name;
    }

    if (!targetName) {
        return null;
    }

    const resolved = await CredentialEngine.Instance.getCredential<Record<string, string>>(targetName, {
        credentialId: cleanId,
        contextUser,
        subsystem: 'GitHub',
    });

    return hydrateFromValuesMap(resolved.values, 'credential', {
        ...hydrateOpts,
        credentialId: resolved.credential?.ID ?? cleanId,
    });
}

async function resolveUserDelegated3LO(
    contextUser: UserInfo,
    provider: IMetadataProvider | undefined,
    hydrateOpts: {
        targetRepository?: { owner: string; repo: string };
        permissions?: GitHubInstallationPermissions;
        fetchImpl?: typeof fetch;
    },
): Promise<ResolvedGitHubVaultAuth | null> {
    const loaded = await ensureCredentialEngineLoaded(contextUser, provider);
    if (!loaded) {
        return null;
    }
    const delegated = await CredentialEngine.Instance.GetUserDelegatedCredential('GitHub', contextUser);
    if (!delegated || !delegated.values.accessToken?.trim()) {
        return null;
    }
    return hydrateFromValuesMap(delegated.values, 'user-delegated', {
        ...hydrateOpts,
        credentialId: delegated.credential?.ID,
    });
}

function parseCompanyIntegrationConfig(rawConfig: string | null | undefined): ParsedCompanyIntegrationConfig {
    if (!rawConfig || !rawConfig.trim()) {
        return {};
    }
    try {
        const parsed = JSON.parse(rawConfig) as ParsedCompanyIntegrationConfig;
        return parsed && typeof parsed === 'object' ? parsed : {};
    } catch {
        return {};
    }
}

function companyIntegrationMatchesTarget(
    row: MJCompanyIntegrationEntityType,
    cfg: ParsedCompanyIntegrationConfig,
    targetRepo: { owner: string; repo: string } | undefined,
): { matches: boolean; owner?: string; allowedRepos: string[]; apiBaseUrl?: string } {
    const owner = (
        cfg.owner ??
        cfg.Owner ??
        cfg.defaultOwner ??
        cfg.DefaultOwner ??
        cfg.organization ??
        cfg.Organization ??
        cfg.org ??
        row.ExternalSystemID ??
        ''
    ).trim() || undefined;

    const allowedRepos = ParseAllowedRepositories(
        cfg.allowedRepositories ??
            cfg.AllowedRepositories ??
            cfg.repositories ??
            cfg.Repositories ??
            (cfg.repo ? [cfg.repo] : undefined),
    );

    const apiBaseUrl = cfg.apiBaseUrl ?? cfg.baseUrl ?? cfg.BaseURL ?? cfg.apiUrl ?? undefined;

    if (!targetRepo) {
        return { matches: true, owner, allowedRepos, apiBaseUrl };
    }

    if (allowedRepos.length > 0) {
        return {
            matches: IsRepositoryAllowed(targetRepo.owner, targetRepo.repo, allowedRepos),
            owner,
            allowedRepos,
            apiBaseUrl,
        };
    }

    if (owner) {
        return {
            matches: owner.toLowerCase() === targetRepo.owner.trim().toLowerCase(),
            owner,
            allowedRepos,
            apiBaseUrl,
        };
    }

    return { matches: true, owner, allowedRepos, apiBaseUrl };
}

async function resolveFromCompanyIntegrations(
    companyId: string | null | undefined,
    contextUser: UserInfo | undefined,
    provider: (IMetadataProvider & IRunViewProvider) | undefined,
    hydrateOpts: {
        targetRepository?: { owner: string; repo: string };
        permissions?: GitHubInstallationPermissions;
        fetchImpl?: typeof fetch;
    },
): Promise<ResolvedGitHubVaultAuth | null> {
    try {
        const rv = provider ? RunView.FromMetadataProvider(provider) : new RunView();
        let extraFilter = `Integration = '${GITHUB_INTEGRATION_NAME}' AND (IsActive IS NULL OR IsActive = 1)`;
        if (companyId && companyId.trim().length > 0) {
            if (!IsValidUUID(companyId.trim())) {
                LogError(`ResolveGitHubVaultAuth: CompanyID '${companyId}' is not a valid UUID.`);
                return null;
            }
            const safeCompanyId = AssertValidUUID(companyId.trim(), 'CompanyID');
            extraFilter = `CompanyID = '${safeCompanyId}' AND ${extraFilter}`;
        }

        const result = await rv.RunView<MJCompanyIntegrationEntityType>(
            {
                EntityName: 'MJ: Company Integrations',
                ExtraFilter: extraFilter,
                ResultType: 'simple',
            },
            contextUser,
        );

        if (!result.Success || !result.Results?.length) {
            return null;
        }

        for (const row of result.Results) {
            const cfg = parseCompanyIntegrationConfig(row.Configuration);
            const scope = companyIntegrationMatchesTarget(row, cfg, hydrateOpts.targetRepository);
            if (!scope.matches && !companyId) {
                continue;
            }

            if (row.CredentialID && IsValidUUID(row.CredentialID)) {
                const viaCredential = await resolveByCredentialIdOrName(
                    row.CredentialID,
                    undefined,
                    contextUser,
                    provider,
                    {
                        ...hydrateOpts,
                        fallbackApiBaseUrl: scope.apiBaseUrl,
                        fallbackOwner: scope.owner,
                        fallbackAllowedRepos: scope.allowedRepos,
                    },
                );
                if (viaCredential) {
                    return {
                        ...viaCredential,
                        source: 'company-integration',
                    };
                }
            }

            // Also support inline CompanyIntegration.Configuration / AccessToken / APIKey per @memberjunction/connector-github
            const inlineValues: Record<string, string | undefined> = {
                token: cfg.token ?? cfg.Token ?? cfg.personalAccessToken ?? cfg.apiToken ?? cfg.githubToken,
                accessToken: cfg.accessToken ?? cfg.AccessToken ?? row.AccessToken ?? undefined,
                apiKey: row.APIKey ?? undefined,
                appId: cfg.appId != null ? String(cfg.appId) : cfg.AppId != null ? String(cfg.AppId) : cfg.githubAppId != null ? String(cfg.githubAppId) : undefined,
                installationId:
                    cfg.installationId != null
                        ? String(cfg.installationId)
                        : cfg.InstallationId != null
                          ? String(cfg.InstallationId)
                          : cfg.githubInstallationId != null
                            ? String(cfg.githubInstallationId)
                            : undefined,
                privateKey: cfg.privateKey ?? cfg.PrivateKey ?? cfg.githubPrivateKey,
                apiBaseUrl: scope.apiBaseUrl,
                defaultOwner: scope.owner,
                allowedRepositories: scope.allowedRepos.length > 0 ? scope.allowedRepos.join(',') : undefined,
            };

            const viaConfig = await hydrateFromValuesMap(inlineValues, 'company-integration', hydrateOpts);
            if (viaConfig) {
                return viaConfig;
            }
        }
    } catch {
        // Fall through to default credential / environment when MJ: Company Integrations is unavailable (e.g. unit tests)
    }

    return null;
}

async function resolveDefaultVaultCredential(
    contextUser: UserInfo | undefined,
    provider: IMetadataProvider | undefined,
    hydrateOpts: {
        targetRepository?: { owner: string; repo: string };
        permissions?: GitHubInstallationPermissions;
        fetchImpl?: typeof fetch;
    },
): Promise<ResolvedGitHubVaultAuth | null> {
    const loaded = await ensureCredentialEngineLoaded(contextUser, provider);
    if (!loaded) {
        return null;
    }

    for (const typeName of ['GitHub App', 'GitHub Personal Access Token']) {
        const defaultCred = CredentialEngine.Instance.GetDefaultCredentialForType(typeName);
        if (!defaultCred || defaultCred.IsActive === false) {
            continue;
        }
        try {
            const resolved = await CredentialEngine.Instance.getCredential<Record<string, string>>(defaultCred.Name, {
                credentialId: defaultCred.ID,
                contextUser,
                subsystem: 'GitHub',
            });
            const hydrated = await hydrateFromValuesMap(resolved.values, 'default-credential', {
                ...hydrateOpts,
                credentialId: defaultCred.ID,
            });
            if (hydrated) {
                return hydrated;
            }
        } catch (err) {
            if (err instanceof GitHubRepoNotAllowedError) {
                throw err;
            }
        }
    }
    return null;
}

async function resolveFromEnvironment(
    env: NodeJS.ProcessEnv,
    hydrateOpts: {
        targetRepository?: { owner: string; repo: string };
        permissions?: GitHubInstallationPermissions;
        fetchImpl?: typeof fetch;
    },
): Promise<ResolvedGitHubVaultAuth | null> {
    const allowedRepos = ParseAllowedRepositories(env.GITHUB_ALLOWED_REPOS);
    const defaultOwner = env.GITHUB_DEFAULT_OWNER?.trim() || undefined;
    const apiBaseUrl = NormalizeGitHubApiBaseUrl(env.GITHUB_API_URL);

    if (hydrateOpts.targetRepository) {
        const { owner, repo } = hydrateOpts.targetRepository;
        if (!IsRepositoryAllowed(owner, repo, allowedRepos)) {
            throw new GitHubRepoNotAllowedError(
                `Repository '${owner}/${repo}' is not permitted by GITHUB_ALLOWED_REPOS (${allowedRepos.join(', ')}).`,
                owner,
                repo,
            );
        }
    }

    const appFromEnv = ReadGitHubAppFromEnv(env);
    if (appFromEnv) {
        const repoScope = ResolveInstallationRepositoryScope(hydrateOpts.targetRepository, allowedRepos);
        const token = await MintGitHubInstallationToken(appFromEnv, {
            repositories: repoScope,
            permissions: hydrateOpts.permissions ?? DEFAULT_TASKS_GITHUB_READ_PERMISSIONS,
            fetchImpl: hydrateOpts.fetchImpl,
        });
        return {
            token,
            apiBaseUrl: appFromEnv.apiBaseUrl ?? apiBaseUrl,
            source: 'environment',
            authKind: 'github-app',
            defaultOwner,
            allowedRepositories: allowedRepos.length > 0 ? allowedRepos : undefined,
        };
    }

    const pat = (env.GITHUB_TOKEN ?? env.GH_TOKEN ?? '').trim();
    if (pat) {
        return {
            token: pat,
            apiBaseUrl,
            source: 'environment',
            authKind: 'pat',
            defaultOwner,
            allowedRepositories: allowedRepos.length > 0 ? allowedRepos : undefined,
        };
    }

    return null;
}

/**
 * Resolves governed GitHub credentials for `bizapps-tasks-github` via the 5-step priority chain:
 *  1. Explicit `credentialId` or `credentialName` in `CredentialEngine`
 *  2. Per-user delegated 3LO OAuth (`useUserDelegatedAuth: true`)
 *  3. Active `MJ: Company Integrations` (`Integration = 'GitHub'`) matching `companyId` or `targetRepository`
 *  4. Default `GitHub App` or `GitHub Personal Access Token` credential in `CredentialEngine`
 *  5. Process environment fallback (`GITHUB_APP_*` -> `GITHUB_TOKEN` / `GH_TOKEN`)
 */
export async function ResolveGitHubVaultAuth(
    options: ResolveGitHubVaultAuthOptions = {},
): Promise<ResolvedGitHubVaultAuth | null> {
    const hydrateOpts = {
        targetRepository: options.targetRepository,
        permissions: options.permissions,
        fetchImpl: options.fetchImpl,
    };

    if (options.credentialId || options.credentialName) {
        const explicit = await resolveByCredentialIdOrName(
            options.credentialId,
            options.credentialName,
            options.contextUser,
            options.provider,
            hydrateOpts,
        );
        if (explicit) {
            return explicit;
        }
    }

    if (options.useUserDelegatedAuth && options.contextUser?.ID) {
        const delegated = await resolveUserDelegated3LO(options.contextUser, options.provider, hydrateOpts);
        if (delegated) {
            return delegated;
        }
    }

    const fromCompany = await resolveFromCompanyIntegrations(
        options.companyId,
        options.contextUser,
        options.provider,
        hydrateOpts,
    );
    if (fromCompany) {
        return fromCompany;
    }

    const defaultCred = await resolveDefaultVaultCredential(options.contextUser, options.provider, hydrateOpts);
    if (defaultCred) {
        return defaultCred;
    }

    return resolveFromEnvironment(options.env ?? process.env, hydrateOpts);
}

/**
 * Resolves the HMAC-SHA256 webhook secret from:
 *  1. Explicit `explicitSecret` (programmatic middleware config)
 *  2. Explicit or default `GitHub App` credential's encrypted `webhookSecret` field in `CredentialEngine`
 *  3. `GITHUB_WEBHOOK_SECRET` environment variable
 */
export async function ResolveGitHubWebhookSecret(
    options: ResolveGitHubWebhookSecretOptions = {},
): Promise<string> {
    if (typeof options.explicitSecret === 'string' && options.explicitSecret.trim().length > 0) {
        return options.explicitSecret.trim();
    }

    const envSecret = (options.env ?? process.env).GITHUB_WEBHOOK_SECRET?.trim() ?? '';

    const loaded = await ensureCredentialEngineLoaded(options.contextUser, options.provider);
    if (loaded) {
        try {
            if (options.credentialId && IsValidUUID(options.credentialId.trim())) {
                const match = CredentialEngine.Instance.GetCredentialById(options.credentialId.trim());
                if (match && match.IsActive !== false) {
                    const resolved = await CredentialEngine.Instance.getCredential<Record<string, string>>(match.Name, {
                        credentialId: match.ID,
                        contextUser: options.contextUser,
                        subsystem: 'GitHubWebhook',
                    });
                    const secret = (resolved.values.webhookSecret ?? resolved.values.WebhookSecret ?? '').trim();
                    if (secret.length > 0) {
                        return secret;
                    }
                }
            }

            const defaultAppCred = CredentialEngine.Instance.GetDefaultCredentialForType('GitHub App');
            if (defaultAppCred && defaultAppCred.IsActive !== false) {
                const resolved = await CredentialEngine.Instance.getCredential<Record<string, string>>(
                    defaultAppCred.Name,
                    {
                        credentialId: defaultAppCred.ID,
                        contextUser: options.contextUser,
                        subsystem: 'GitHubWebhook',
                    },
                );
                const secret = (resolved.values.webhookSecret ?? resolved.values.WebhookSecret ?? '').trim();
                if (secret.length > 0) {
                    return secret;
                }
            }
        } catch {
            // Fall through to env secret when CredentialEngine decryption is unavailable without contextUser
        }
    }

    return envSecret;
}

export async function HasConfiguredGitHubWebhookSecret(
    options: ResolveGitHubWebhookSecretOptions = {},
): Promise<boolean> {
    const secret = await ResolveGitHubWebhookSecret(options);
    return secret.length > 0;
}
