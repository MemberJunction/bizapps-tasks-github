import { generateKeyPairSync } from 'node:crypto';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import type { EntityFieldInfo, EntityInfo, IMetadataProvider, IRunViewProvider, RunViewResult, UserInfo } from '@memberjunction/core';
import type { MJCredentialEntity } from '@memberjunction/core-entities';
import { CredentialEngine } from '@memberjunction/credentials';
import { GetGlobalObjectStore } from '@memberjunction/global';
import {
    BuildGitHubAppJwt,
    ClearGitHubInstallationTokenCache,
    ConnectorGitHubMirrorRepositoryFetcher,
    DefaultGitHubRestRepositoryFetcher,
    GitHubRepoNotAllowedError,
    HasActiveGitHubConnectorMirror,
    INSTALLATION_TOKEN_CACHE_GLOBAL_KEY,
    ResolveGitHubVaultAuth,
    ResolveGitHubWebhookSecret,
} from '../index.js';

const { privateKey: TEST_RSA_PRIVATE_KEY } = generateKeyPairSync('rsa', {
    modulusLength: 2048,
    publicKeyEncoding: { type: 'spki', format: 'pem' },
    privateKeyEncoding: { type: 'pkcs8', format: 'pem' },
});

const TEST_USER = {
    ID: '99999999-9999-4999-8999-000000000001',
    Name: 'System',
} as UserInfo;

const CRED_ID_APP = '11111111-1111-4111-8111-000000000001';
const CRED_ID_PAT = '11111111-1111-4111-8111-000000000002';
const COMPANY_ID = '22222222-2222-4222-8222-000000000001';
const CI_ID = '33333333-3333-4333-8333-000000000001';
const ENTITY_ID_ISSUES = '44444444-4444-4444-8444-000000000001';
const ENTITY_ID_PRS = '44444444-4444-4444-8444-000000000002';
const MAP_ID_ISSUES = '55555555-5555-4555-8555-000000000001';
const MAP_ID_PRS = '55555555-5555-4555-8555-000000000002';

function makeMockEntityInfo(id: string, name: string, fieldNames: string[]): EntityInfo {
    const fields = fieldNames.map((fn) => ({ Name: fn } as EntityFieldInfo));
    return {
        ID: id,
        Name: name,
        Fields: fields,
    } as EntityInfo;
}

describe('GitHubVaultAuthResolver & ConnectorGitHubMirrorRepositoryFetcher', () => {
    beforeEach(() => {
        ClearGitHubInstallationTokenCache();
        vi.restoreAllMocks();
    });

    afterEach(() => {
        ClearGitHubInstallationTokenCache();
        vi.restoreAllMocks();
    });

    it('signs RS256 JWTs with 60s clock-skew margin and caches repo-scoped installation tokens in GlobalObjectStore', async () => {
        const jwt = BuildGitHubAppJwt('12345', TEST_RSA_PRIVATE_KEY, 1_700_000_000);
        const parts = jwt.split('.');
        expect(parts).toHaveLength(3);
        const payload = JSON.parse(Buffer.from(parts[1], 'base64url').toString('utf8')) as {
            iat: number;
            exp: number;
            iss: string;
        };
        expect(payload.iss).toBe('12345');
        expect(payload.iat).toBe(1_700_000_000 - 60);
        expect(payload.exp).toBe(1_700_000_000 + 540);

        vi.spyOn(CredentialEngine.Instance, 'Config').mockResolvedValue();
        vi.spyOn(CredentialEngine.Instance, 'GetCredentialById').mockReturnValue({
            ID: CRED_ID_APP,
            Name: 'Org GitHub App',
            IsActive: true,
        } as MJCredentialEntity);
        vi.spyOn(CredentialEngine.Instance, 'getCredential').mockResolvedValue({
            credential: { ID: CRED_ID_APP } as MJCredentialEntity,
            source: 'database',
            expirationStatus: 'valid',
            values: {
                appId: '98765',
                installationId: '54321',
                privateKey: TEST_RSA_PRIVATE_KEY.replace(/\n/g, '\\n'),
                apiBaseUrl: 'https://GHE.Example.com/api/v3///',
                allowedRepositories: 'MemberJunction/*',
            },
        });

        const capturedRequests: Array<{ url: string; body: string | undefined }> = [];
        const mockFetch = (async (input: string | URL | Request, init?: RequestInit): Promise<Response> => {
            const url = typeof input === 'string' ? input : input instanceof URL ? input.toString() : input.url;
            capturedRequests.push({
                url,
                body: typeof init?.body === 'string' ? init.body : undefined,
            });
            return new Response(JSON.stringify({ token: 'ghs_vault_scoped_token_1' }), {
                status: 201,
                headers: { 'content-type': 'application/json' },
            });
        }) as typeof fetch;

        const first = await ResolveGitHubVaultAuth({
            credentialId: CRED_ID_APP,
            targetRepository: { owner: 'MemberJunction', repo: 'MJ' },
            contextUser: TEST_USER,
            fetchImpl: mockFetch,
        });

        expect(first).not.toBeNull();
        expect(first?.token).toBe('ghs_vault_scoped_token_1');
        expect(first?.apiBaseUrl).toBe('https://GHE.Example.com/api/v3');
        expect(first?.authKind).toBe('github-app');
        expect(first?.source).toBe('credential');
        expect(capturedRequests).toHaveLength(1);
        expect(capturedRequests[0].url).toBe('https://GHE.Example.com/api/v3/app/installations/54321/access_tokens');
        expect(JSON.parse(capturedRequests[0].body ?? '{}')).toMatchObject({
            repositories: ['MJ'],
        });

        // Second call with normalized lower-case GHE URL hits shared GlobalObjectStore cache without a 2nd POST
        const store = GetGlobalObjectStore();
        expect(store?.[INSTALLATION_TOKEN_CACHE_GLOBAL_KEY]).toBeInstanceOf(Map);

        const second = await ResolveGitHubVaultAuth({
            credentialId: CRED_ID_APP,
            targetRepository: { owner: 'MemberJunction', repo: 'MJ' },
            contextUser: TEST_USER,
            fetchImpl: mockFetch,
        });
        expect(second?.token).toBe('ghs_vault_scoped_token_1');
        expect(capturedRequests).toHaveLength(1);

        // Disallowed repository throws GitHubRepoNotAllowedError
        await expect(
            ResolveGitHubVaultAuth({
                credentialId: CRED_ID_APP,
                targetRepository: { owner: 'OtherOrg', repo: 'SecretRepo' },
                contextUser: TEST_USER,
                fetchImpl: mockFetch,
            }),
        ).rejects.toBeInstanceOf(GitHubRepoNotAllowedError);
    });

    it('resolves per-user 3LO credentials, CompanyIntegration configs, and Vault webhook secrets', async () => {
        vi.spyOn(CredentialEngine.Instance, 'Config').mockResolvedValue();
        vi.spyOn(CredentialEngine.Instance, 'GetUserDelegatedCredential').mockResolvedValue({
            credential: { ID: CRED_ID_PAT } as MJCredentialEntity,
            source: 'database',
            expirationStatus: 'valid',
            values: {
                ownerUserId: TEST_USER.ID,
                principalEmail: 'dev@example.com',
                providerName: 'GitHub',
                accessToken: 'ghu_user_3lo_token',
                refreshToken: '',
                tokenType: 'bearer',
                scope: 'repo',
                tenantId: '',
                issuedAt: '2026-11-10T00:00:00Z',
            },
        });

        const delegated = await ResolveGitHubVaultAuth({
            useUserDelegatedAuth: true,
            contextUser: TEST_USER,
        });
        expect(delegated?.token).toBe('ghu_user_3lo_token');
        expect(delegated?.authKind).toBe('oauth-3lo');
        expect(delegated?.source).toBe('user-delegated');

        // CompanyIntegration inline configuration fallback matching @memberjunction/connector-github
        const partialCiProvider: Partial<IMetadataProvider & IRunViewProvider> = {
            Entities: [],
            RunView: async <T = object>() =>
                ({
                    Success: true,
                    Results: [
                        {
                            ID: CI_ID,
                            CompanyID: COMPANY_ID,
                            Integration: 'GitHub',
                            IsActive: true,
                            CredentialID: null,
                            Configuration: JSON.stringify({
                                baseUrl: 'https://ghe.internal/api/v3',
                                personalAccessToken: 'ghp_company_integration_token',
                                repositories: ['MemberJunction/bizapps-tasks-github'],
                            }),
                        },
                    ] as T[],
                }) as RunViewResult<T>,
            RunViews: async () => [],
        };
        const mockProvider = partialCiProvider as IMetadataProvider & IRunViewProvider;

        const fromCi = await ResolveGitHubVaultAuth({
            companyId: COMPANY_ID,
            targetRepository: { owner: 'MemberJunction', repo: 'bizapps-tasks-github' },
            contextUser: TEST_USER,
            provider: mockProvider,
        });
        expect(fromCi?.token).toBe('ghp_company_integration_token');
        expect(fromCi?.apiBaseUrl).toBe('https://ghe.internal/api/v3');
        expect(fromCi?.source).toBe('company-integration');

        // ResolveGitHubWebhookSecret reads webhookSecret from default GitHub App Vault credential
        vi.spyOn(CredentialEngine.Instance, 'GetDefaultCredentialForType').mockImplementation((typeName: string) =>
            typeName === 'GitHub App'
                ? ({ ID: CRED_ID_APP, Name: 'Default GitHub App', IsActive: true } as MJCredentialEntity)
                : undefined,
        );
        vi.spyOn(CredentialEngine.Instance, 'getCredential').mockResolvedValue({
            credential: { ID: CRED_ID_APP } as MJCredentialEntity,
            source: 'database',
            expirationStatus: 'valid',
            values: {
                webhookSecret: 'vault-hmac-secret-xyz',
            },
        });

        const secret = await ResolveGitHubWebhookSecret({
            contextUser: TEST_USER,
            env: {},
        });
        expect(secret).toBe('vault-hmac-secret-xyz');
    });

    it('DefaultGitHubRestRepositoryFetcher follows RFC 5988 Link rel="next" headers, retries 503, and honors GHES ApiBaseUrl', async () => {
        vi.spyOn(CredentialEngine.Instance, 'Config').mockRejectedValue(new Error('offline'));
        const prevToken = process.env.GITHUB_TOKEN;
        const prevApiUrl = process.env.GITHUB_API_URL;
        process.env.GITHUB_TOKEN = 'ghp_env_pat';
        process.env.GITHUB_API_URL = 'https://ghe.corp.local/api/v3/';

        try {
            let issuesPage1Attempts = 0;
            const seenUrls: string[] = [];

            const mockFetch = (async (input: string | URL | Request): Promise<Response> => {
                const url = typeof input === 'string' ? input : input instanceof URL ? input.toString() : input.url;
                seenUrls.push(url);

                if (url.includes('/issues') && url.includes('page=1')) {
                    issuesPage1Attempts += 1;
                    if (issuesPage1Attempts === 1) {
                        return new Response('Service Unavailable', {
                            status: 503,
                            headers: { 'retry-after': '0' },
                        });
                    }
                    return new Response(
                        JSON.stringify([
                            {
                                number: 10,
                                node_id: 'I_kwDO_10',
                                title: 'First page issue',
                                body: 'Issue body 10',
                                html_url: 'https://ghe.corp.local/Acme/App/issues/10',
                                state: 'open',
                                labels: [{ name: 'enhancement' }],
                                user: { login: 'alice', id: 101 },
                            },
                        ]),
                        {
                            status: 200,
                            headers: {
                                'content-type': 'application/json',
                                link: '<https://ghe.corp.local/api/v3/repos/Acme/App/issues?after=cursor_2>; rel="next"',
                            },
                        },
                    );
                }

                if (url.includes('/issues?after=cursor_2')) {
                    return new Response(
                        JSON.stringify([
                            {
                                number: 11,
                                node_id: 'I_kwDO_11',
                                title: 'Second page issue via Link header',
                                body: null,
                                html_url: 'https://ghe.corp.local/Acme/App/issues/11',
                                state: 'closed',
                                state_reason: 'completed',
                            },
                        ]),
                        { status: 200, headers: { 'content-type': 'application/json' } },
                    );
                }

                return new Response(
                    JSON.stringify([
                        {
                            number: 25,
                            node_id: 'PR_kwDO_25',
                            title: 'Feature PR',
                            body: 'Closes #10',
                            html_url: 'https://ghe.corp.local/Acme/App/pull/25',
                            state: 'open',
                            draft: false,
                            head: { ref: 'feat/x', sha: 'abc1234' },
                            base: { ref: 'main' },
                        },
                    ]),
                    { status: 200, headers: { 'content-type': 'application/json' } },
                );
            }) as typeof fetch;

            const fetcher = new DefaultGitHubRestRepositoryFetcher({ fetchImpl: mockFetch });
            const items = await fetcher.FetchRepositoryItems('Acme', 'App', TEST_USER);

            expect(issuesPage1Attempts).toBe(2);
            expect(seenUrls.some((u) => u.startsWith('https://ghe.corp.local/api/v3/repos/Acme/App/issues'))).toBe(true);
            expect(seenUrls).toContain('https://ghe.corp.local/api/v3/repos/Acme/App/issues?after=cursor_2');
            expect(items).toHaveLength(3);
            expect(items.map((i) => `${i.kind}#${i.number}`)).toEqual([
                'issue#10',
                'issue#11',
                'pull_request#25',
            ]);
        } finally {
            if (prevToken === undefined) delete process.env.GITHUB_TOKEN;
            else process.env.GITHUB_TOKEN = prevToken;
            if (prevApiUrl === undefined) delete process.env.GITHUB_API_URL;
            else process.env.GITHUB_API_URL = prevApiUrl;
        }
    });

    it('ConnectorGitHubMirrorRepositoryFetcher projects @memberjunction/connector-github mirrored issues & pull_requests with zero REST calls', async () => {
        const appliedFilters: Array<{ entityName: string; filter: string }> = [];

        const partialMirrorProvider: Partial<IMetadataProvider & IRunViewProvider> = {
            Entities: [
                makeMockEntityInfo(ENTITY_ID_ISSUES, 'GitHub: Mirrored Issues', [
                    'ID',
                    'RepositoryFullName',
                    'Number',
                    'NodeID',
                    'Title',
                    'Body',
                    'State',
                    'StateReason',
                    'AuthorLogin',
                    'AssigneeLogin',
                    'LabelsJSON',
                    'IsPullRequest',
                    'HtmlURL',
                    'UpdatedAt',
                ]),
                makeMockEntityInfo(ENTITY_ID_PRS, 'GitHub: Mirrored Pull Requests', [
                    'id',
                    'repository_full_name',
                    'number',
                    'node_id',
                    'title',
                    'body',
                    'state',
                    'draft',
                    'merged_at',
                    'head_ref',
                    'head_sha',
                    'base_ref',
                    'author_login',
                    'html_url',
                    'updated_at',
                ]),
            ],
            RunView: (async (params: { EntityName: string; ExtraFilter?: string }): Promise<RunViewResult> => {
                appliedFilters.push({ entityName: params.EntityName, filter: params.ExtraFilter ?? '' });

                if (params.EntityName === 'MJ: Company Integrations') {
                    return {
                        Success: true,
                        Results: [{ ID: CI_ID, CompanyID: COMPANY_ID, Integration: 'GitHub', IsActive: true }],
                    } as RunViewResult;
                }
                if (params.EntityName === 'MJ: Company Integration Entity Maps') {
                    return {
                        Success: true,
                        Results: [
                            {
                                ID: MAP_ID_ISSUES,
                                CompanyIntegrationID: CI_ID,
                                ExternalObjectName: 'issues',
                                EntityID: ENTITY_ID_ISSUES,
                                Entity: 'GitHub: Mirrored Issues',
                                SyncEnabled: true,
                                Status: 'Active',
                                Priority: 1,
                            },
                            {
                                ID: MAP_ID_PRS,
                                CompanyIntegrationID: CI_ID,
                                ExternalObjectName: 'pull_requests',
                                EntityID: ENTITY_ID_PRS,
                                Entity: 'GitHub: Mirrored Pull Requests',
                                SyncEnabled: true,
                                Status: 'Active',
                                Priority: 2,
                            },
                        ],
                    } as RunViewResult;
                }
                if (params.EntityName === 'MJ: Company Integration Field Maps') {
                    return {
                        Success: true,
                        Results: [
                            {
                                ID: '66666666-6666-4666-8666-000000000001',
                                EntityMapID: MAP_ID_ISSUES,
                                SourceFieldName: 'repository_full_name',
                                DestinationFieldName: 'RepositoryFullName',
                                Status: 'Active',
                            },
                        ],
                    } as RunViewResult;
                }
                if (params.EntityName === 'GitHub: Mirrored Issues') {
                    return {
                        Success: true,
                        Results: [
                            {
                                RepositoryFullName: 'MemberJunction/MJ',
                                Number: 42,
                                NodeID: 'I_kwDO_42',
                                Title: 'Mirrored issue from connector-github',
                                Body: 'Needs attention',
                                State: 'open',
                                StateReason: null,
                                AuthorLogin: 'caitlin',
                                AssigneeLogin: 'amith',
                                LabelsJSON: JSON.stringify([{ name: 'bug' }, { name: 'priority:high' }]),
                                IsPullRequest: false,
                                HtmlURL: 'https://github.com/MemberJunction/MJ/issues/42',
                                UpdatedAt: '2026-11-10T12:00:00Z',
                            },
                            {
                                // PR shadow row inside GitHub /issues feed -> must be skipped!
                                RepositoryFullName: 'MemberJunction/MJ',
                                Number: 99,
                                NodeID: 'PR_shadow_99',
                                Title: 'Shadow PR row',
                                IsPullRequest: true,
                                HtmlURL: 'https://github.com/MemberJunction/MJ/pull/99',
                            },
                        ],
                    } as RunViewResult;
                }
                if (params.EntityName === 'GitHub: Mirrored Pull Requests') {
                    return {
                        Success: true,
                        Results: [
                            {
                                repository_full_name: 'MemberJunction/MJ',
                                number: 99,
                                node_id: 'PR_kwDO_99',
                                title: 'Fix mirrored bug',
                                body: 'Fixes #42',
                                state: 'closed',
                                draft: false,
                                merged_at: '2026-11-10T13:30:00Z',
                                head_ref: 'fix/mirrored-42',
                                head_sha: 'deadbeef1234',
                                base_ref: 'next',
                                author_login: 'amith',
                                html_url: 'https://github.com/MemberJunction/MJ/pull/99',
                                updated_at: '2026-11-10T13:30:00Z',
                            },
                        ],
                    } as RunViewResult;
                }
                return { Success: true, Results: [] } as RunViewResult;
            }) as IRunViewProvider['RunView'],
            RunViews: async () => [],
        };
        const mockProvider = partialMirrorProvider as IMetadataProvider & IRunViewProvider;

        const hasMirror = await HasActiveGitHubConnectorMirror(TEST_USER, mockProvider, COMPANY_ID);
        expect(hasMirror).toBe(true);

        const mirrorFetcher = new ConnectorGitHubMirrorRepositoryFetcher({ companyId: COMPANY_ID });
        const items = await mirrorFetcher.FetchRepositoryItems('MemberJunction', 'MJ', TEST_USER, mockProvider);

        expect(items).toHaveLength(2);
        const issue = items.find((i) => i.kind === 'issue');
        const pr = items.find((i) => i.kind === 'pull_request');

        expect(issue).toMatchObject({
            kind: 'issue',
            number: 42,
            nodeId: 'I_kwDO_42',
            title: 'Mirrored issue from connector-github',
            state: 'open',
            authorLogin: 'caitlin',
            assigneeLogins: ['amith'],
            labels: ['bug', 'priority:high'],
        });

        expect(pr).toMatchObject({
            kind: 'pull_request',
            number: 99,
            nodeId: 'PR_kwDO_99',
            state: 'merged',
            headBranch: 'fix/mirrored-42',
            headSha: 'deadbeef1234',
            baseBranch: 'next',
            linkedIssueNumber: 42,
        });

        // Verify verified destination column filters were pushed down cleanly
        expect(appliedFilters).toContainEqual({
            entityName: 'GitHub: Mirrored Issues',
            filter: `[RepositoryFullName] = 'MemberJunction/MJ'`,
        });
        expect(appliedFilters).toContainEqual({
            entityName: 'GitHub: Mirrored Pull Requests',
            filter: `[repository_full_name] = 'MemberJunction/MJ'`,
        });
    });
});
