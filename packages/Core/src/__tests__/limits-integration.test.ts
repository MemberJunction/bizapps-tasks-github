import { createHmac, generateKeyPairSync } from 'node:crypto';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import {
    LimitsConfigResolver,
    RunView,
    type IMetadataProvider,
    type IRunViewProvider,
    type RunViewParams,
    type RunViewResult,
    type UserInfo,
} from '@memberjunction/core';
import {
    GITHUB_REPOSITORIES_ENTITY_NAME,
    GitHubTasksEngineBase,
} from '@mj-biz-apps/tasks-github-entities';
import {
    ClearGitHubInstallationTokenCache,
    DefaultGitHubRestLiveStateFetcher,
    DefaultGitHubRestRepositoryFetcher,
    GITHUB_INSTALLATION_TOKEN_MAX_TTL_MS,
    GITHUB_REST_MAX_PER_PAGE,
    GitHubTaskInferenceService,
    GitHubTaskSyncService,
    GitHubTasksLimitsResolver,
    GitHubWebhookService,
    MintGitHubInstallationToken,
    type IGitHubInferenceExtractor,
    type IGitHubLiveStateFetcher,
    type InferenceContextInput,
    type InferenceExtractionResult,
} from '../index.js';

const TEST_RSA_PRIVATE_KEY = generateKeyPairSync('rsa', { modulusLength: 2048 })
    .privateKey.export({ type: 'pkcs8', format: 'pem' })
    .toString();

const TEST_USER = {
    ID: '11111111-1111-4111-8111-111111111111',
    Name: 'Limits Tester',
    Email: 'limits-tester@example.com',
    IsActive: true,
} as UserInfo;

function makeJsonResponse(status: number, body: object, headers: Record<string, string> = {}): Response {
    return new Response(JSON.stringify(body), {
        status,
        headers: {
            'Content-Type': 'application/json',
            ...headers,
        },
    });
}

describe('GitHubTasksLimitsResolver consumer integration (Core)', () => {
    const prevEnvValues: Record<string, string | undefined> = {};
    const ENV_KEYS = [
        'GITHUB_TOKEN',
        'GH_TOKEN',
        'MJ_TASKS_GITHUB_LIMIT_GITHUB_REST_SYNC_MAX_PAGES',
        'MJ_TASKS_GITHUB_LIMIT_GITHUB_REST_SYNC_PER_PAGE',
        'MJ_TASKS_GITHUB_LIMIT_WEBHOOK_LIVE_STATE_MAX_PAGES',
    ] as const;

    beforeEach(() => {
        for (const key of ENV_KEYS) {
            prevEnvValues[key] = process.env[key];
            delete process.env[key];
        }
        GitHubTasksLimitsResolver.Instance.ClearConfigLimits();
        LimitsConfigResolver.Instance.ClearMjConfigLimits();
        ClearGitHubInstallationTokenCache();
        GitHubWebhookService.Instance.ClearProcessedDeliveries();
        GitHubTaskInferenceService.Instance.ResetExtractor();
    });

    afterEach(() => {
        vi.restoreAllMocks();
        for (const key of ENV_KEYS) {
            const prev = prevEnvValues[key];
            if (prev === undefined) {
                delete process.env[key];
            } else {
                process.env[key] = prev;
            }
        }
        GitHubTasksLimitsResolver.Instance.ClearConfigLimits();
        LimitsConfigResolver.Instance.ClearMjConfigLimits();
        ClearGitHubInstallationTokenCache();
        GitHubWebhookService.Instance.ClearProcessedDeliveries();
        GitHubTaskInferenceService.Instance.ResetExtractor();
    });

    it('DefaultGitHubRestRepositoryFetcher enforces configured SyncMaxPages, clamps SyncPerPage <= 100, and respects SyncMaxRetries', async () => {
        process.env.GITHUB_TOKEN = 'test-pat-token';
        const requestedUrls: string[] = [];

        const mockFetch: typeof fetch = async (input) => {
            const url = typeof input === 'string' ? input : input instanceof URL ? input.toString() : input.url;
            requestedUrls.push(url);
            if (url.includes('/issues')) {
                // Return 5 items per page with rel="next" header so pagination continues up to SyncMaxPages
                const batch = Array.from({ length: 5 }, (_, idx) => ({
                    number: requestedUrls.length * 10 + idx + 1,
                    node_id: `I_node_${requestedUrls.length}_${idx}`,
                    title: `Issue ${idx + 1}`,
                    html_url: `https://github.com/MemberJunction/MJ/issues/${requestedUrls.length * 10 + idx + 1}`,
                    state: 'open',
                }));
                return makeJsonResponse(200, batch, {
                    link: '<https://api.github.com/repos/MemberJunction/MJ/issues?page=next>; rel="next"',
                });
            }
            return makeJsonResponse(200, []);
        };

        // Pass SyncMaxPages=2 and an oversized SyncPerPage=250 (must clamp to ProtocolLimit 100)
        GitHubTasksLimitsResolver.Instance.RegisterConfigLimits({
            GitHubRest: {
                SyncMaxPages: 2,
                SyncPerPage: 250,
            },
        });

        const fetcher = new DefaultGitHubRestRepositoryFetcher({ fetchImpl: mockFetch });
        const items = await fetcher.FetchRepositoryItems('MemberJunction', 'MJ');

        const issueUrls = requestedUrls.filter((u) => u.includes('/issues'));
        expect(issueUrls).toHaveLength(2);
        expect(issueUrls[0]).toContain(`per_page=${GITHUB_REST_MAX_PER_PAGE}`);
        expect(items).toHaveLength(10);

        // Verify SyncMaxRetries=1 stops after 1 retry on HTTP 503 for /issues
        let issueRetryCalls = 0;
        const failingFetch: typeof fetch = async (input) => {
            const url = typeof input === 'string' ? input : input instanceof URL ? input.toString() : input.url;
            if (url.includes('/issues')) {
                issueRetryCalls += 1;
                return makeJsonResponse(503, { message: 'Service Unavailable' });
            }
            return makeJsonResponse(200, []);
        };
        const retryFetcher = new DefaultGitHubRestRepositoryFetcher({
            fetchImpl: failingFetch,
            limits: {
                GitHubRest: {
                    SyncMaxRetries: 1,
                    RetryBaseDelayMs: 1,
                },
            },
        });
        await expect(retryFetcher.FetchRepositoryItems('MemberJunction', 'MJ')).rejects.toThrow(/HTTP 503/);
        expect(issueRetryCalls).toBe(2);
    });

    it('DefaultGitHubRestRepositoryFetcher falls back to safe defaults when invalid/NaN overrides are registered', async () => {
        process.env.GITHUB_TOKEN = 'test-pat-token';
        const requestedUrls: string[] = [];

        GitHubTasksLimitsResolver.Instance.RegisterConfigLimits({
            GitHubRest: {
                SyncMaxPages: Number.NaN,
                SyncPerPage: -50,
                SyncMaxRetries: 0,
            },
        });

        const mockFetch: typeof fetch = async (input) => {
            const url = typeof input === 'string' ? input : input instanceof URL ? input.toString() : input.url;
            requestedUrls.push(url);
            return makeJsonResponse(200, []);
        };

        const fetcher = new DefaultGitHubRestRepositoryFetcher({ fetchImpl: mockFetch });
        await fetcher.FetchRepositoryItems('MemberJunction', 'MJ');

        expect(requestedUrls.some((u) => u.includes('/issues?state=all&per_page=100&page=1'))).toBe(true);
        expect(requestedUrls.some((u) => u.includes('/pulls?state=all&per_page=100&page=1'))).toBe(true);
    });

    it('DefaultGitHubRestLiveStateFetcher enforces Webhook.LiveStateMaxPages and keeps ProtocolLimit per_page=100', async () => {
        const fetchedUrls: string[] = [];
        vi.spyOn(globalThis, 'fetch').mockImplementation((async (input: string | URL | Request) => {
            const url = typeof input === 'string' ? input : input instanceof URL ? input.toString() : input.url;
            fetchedUrls.push(url);
            if (url.includes('/check-runs')) {
                const runs = Array.from({ length: GITHUB_REST_MAX_PER_PAGE }, (_, i) => ({
                    id: i + 1,
                    name: `check-${i}`,
                    status: 'completed',
                    conclusion: 'success',
                }));
                return makeJsonResponse(200, { check_runs: runs });
            }
            return makeJsonResponse(200, { state: 'success', total_count: 1, statuses: [{ context: 'ci', state: 'success' }] });
        }) as typeof fetch);

        const fetcher = new DefaultGitHubRestLiveStateFetcher('pat-live', 'https://api.github.com', {
            Webhook: {
                LiveStateMaxPages: 2,
                LiveStateRequestTimeoutMs: 2500,
            },
        });

        const status = await fetcher.FetchCommitChecksStatus('MemberJunction', 'MJ', 'abc1234');
        expect(status).toBe('Passing');

        const checkRunUrls = fetchedUrls.filter((u) => u.includes('/check-runs'));
        expect(checkRunUrls).toHaveLength(2);
        expect(checkRunUrls[0]).toContain(`per_page=${GITHUB_REST_MAX_PER_PAGE}&page=1`);
        expect(checkRunUrls[1]).toContain(`per_page=${GITHUB_REST_MAX_PER_PAGE}&page=2`);
    });

    it('MintGitHubInstallationToken respects Auth.ErrorDetailMaxChars and clamps InstallationTokenCacheTtlMs <= 60 min', async () => {
        const longErrorJson = JSON.stringify({ error: 'X'.repeat(500) });
        const errorFetch: typeof fetch = async () => makeJsonResponse(500, { error: 'X'.repeat(500) });

        await expect(
            MintGitHubInstallationToken(
                { appId: '123', installationId: '456', privateKey: TEST_RSA_PRIVATE_KEY },
                {
                    fetchImpl: errorFetch,
                    skipCache: true,
                    limits: { Auth: { ErrorDetailMaxChars: 25 } },
                },
            ),
        ).rejects.toThrow(new RegExp(`: ${longErrorJson.slice(0, 25).replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}$`));

        let mintCount = 0;
        const okFetch: typeof fetch = async () => {
            mintCount += 1;
            return makeJsonResponse(200, { token: `ghs_token_${mintCount}` });
        };

        // Pass oversized TTL (120 min) — must clamp to ProtocolLimit 60 min (3_600_000 ms)
        const baseNowSec = 1_700_000_000;
        const firstToken = await MintGitHubInstallationToken(
            { appId: '123', installationId: '456', privateKey: TEST_RSA_PRIVATE_KEY },
            {
                fetchImpl: okFetch,
                nowSeconds: baseNowSec,
                limits: { Auth: { InstallationTokenCacheTtlMs: 120 * 60 * 1000 } },
            },
        );
        expect(firstToken).toBe('ghs_token_1');

        // At +59 minutes, cached token should still be valid
        const stillCached = await MintGitHubInstallationToken(
            { appId: '123', installationId: '456', privateKey: TEST_RSA_PRIVATE_KEY },
            {
                fetchImpl: okFetch,
                nowSeconds: baseNowSec + 59 * 60,
            },
        );
        expect(stillCached).toBe('ghs_token_1');
        expect(mintCount).toBe(1);

        // At +61 minutes (past clamped 60 min ProtocolLimit ceiling), token must re-mint
        const refreshed = await MintGitHubInstallationToken(
            { appId: '123', installationId: '456', privateKey: TEST_RSA_PRIVATE_KEY },
            {
                fetchImpl: okFetch,
                nowSeconds: baseNowSec + 61 * 60,
            },
        );
        expect(refreshed).toBe('ghs_token_2');
        expect(mintCount).toBe(2);
        expect(GITHUB_INSTALLATION_TOKEN_MAX_TTL_MS).toBe(3_600_000);
    });

    it('GitHubTaskInferenceService routes CandidateObjectivesMaxRows, CandidateCategoriesMaxRows, MinSuggestionConfidence, and DebounceMs via limits resolver', async () => {
        const capturedMaxRows: Record<string, number | undefined> = {};
        let extractionCalls = 0;

        vi.spyOn(RunView, 'FromMetadataProvider').mockImplementation(() => {
            const rv = new RunView();
            rv.RunView = (async (params: RunViewParams): Promise<RunViewResult> => {
                capturedMaxRows[params.EntityName] = params.MaxRows;
                return {
                    Success: true,
                    Results: [],
                    RowCount: 0,
                    TotalRowCount: 0,
                    ExecutionTime: 1,
                    ErrorMessage: '',
                    UserViewRunID: '',
                };
            }) as RunView['RunView'];
            rv.RunViews = (async (paramsList: RunViewParams[]): Promise<RunViewResult[]> => {
                return paramsList.map((p) => {
                    capturedMaxRows[p.EntityName] = p.MaxRows;
                    return {
                        Success: true,
                        Results: [],
                        RowCount: 0,
                        TotalRowCount: 0,
                        ExecutionTime: 1,
                        ErrorMessage: '',
                        UserViewRunID: '',
                    };
                });
            }) as RunView['RunViews'];
            return rv;
        });

        const fakeProvider = {
            Entities: [],
            EntityByName: () => undefined,
        } as Partial<IMetadataProvider & IRunViewProvider> as IMetadataProvider & IRunViewProvider;

        const mockExtractor: IGitHubInferenceExtractor = {
            ExtractPlanningSuggestions: async (_input: InferenceContextInput): Promise<InferenceExtractionResult> => {
                extractionCalls += 1;
                return {
                    suggestions: [
                        {
                            field: 'Priority',
                            value: 'High',
                            confidence: 0.75,
                            rationale: 'Confidence below raised threshold 0.90 should be skipped',
                        },
                    ],
                    mentionedLogins: [],
                    promptRunId: null,
                };
            },
        };
        GitHubTaskInferenceService.Instance.SetExtractor(mockExtractor);

        const result = await GitHubTaskInferenceService.Instance.InferTaskPlanningFields({
            task: {
                ID: '22222222-2222-4222-8222-222222222222',
                DueAt: null,
                HoursEstimated: null,
                ParentID: null,
                CategoryID: null,
                Priority: null,
            },
            repositoryId: '33333333-3333-4333-8333-333333333333',
            repositoryFullName: 'MemberJunction/MJ',
            itemKind: 'issue',
            number: 101,
            title: 'Test limits integration',
            body: 'Body text',
            milestoneDueAt: null,
            structuredLogins: [],
            contextUser: TEST_USER,
            provider: fakeProvider,
            limits: {
                Inference: {
                    CandidateObjectivesMaxRows: 12,
                    CandidateCategoriesMaxRows: 8,
                    MinSuggestionConfidence: 0.9,
                },
            },
        });

        expect(capturedMaxRows['MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks']).toBe(12);
        expect(capturedMaxRows['MJ_BizApps_Tasks: Task Categories']).toBe(8);
        expect(result.createdCount).toBe(0);
        expect(result.skippedFields).toEqual(['Priority']);

        // Verify QueueDebouncedInference uses Inference.DebounceMs from limits resolver
        GitHubTaskInferenceService.Instance.QueueDebouncedInference({
            task: {
                ID: '22222222-2222-4222-8222-222222222222',
                DueAt: null,
                HoursEstimated: null,
                ParentID: null,
                CategoryID: null,
                Priority: null,
            },
            repositoryFullName: 'MemberJunction/MJ',
            itemKind: 'issue',
            number: 102,
            title: 'Debounced check',
            body: 'Body text',
            milestoneDueAt: null,
            structuredLogins: [],
            contextUser: TEST_USER,
            provider: fakeProvider,
            limits: {
                Inference: {
                    DebounceMs: 10,
                },
            },
        });
        await new Promise<void>((resolve) => setTimeout(resolve, 40));
        await GitHubTaskInferenceService.Instance.FlushDebouncedInferences();
        expect(extractionCalls).toBe(2);
    });

    it('GitHubWebhookService enforces Webhook.MaxTrackedDeliveryIds and Webhook.MaxTrackedCheckShas LRU bounds from limits resolver', async () => {
        GitHubTasksLimitsResolver.Instance.RegisterConfigLimits({
            Webhook: {
                MaxTrackedDeliveryIds: 2,
                MaxTrackedCheckShas: 2,
            },
        });

        const secret = 'webhook-lru-secret';
        const sign = (raw: string): string =>
            `sha256=${createHmac('sha256', secret).update(raw, 'utf8').digest('hex')}`;

        const pingPayload = JSON.stringify({ zen: 'Keep it logically awesome.' });
        const sendPing = async (deliveryId: string) =>
            GitHubWebhookService.Instance.HandleWebhook({
                eventName: 'ping',
                deliveryId,
                signatureHeader: sign(pingPayload),
                rawPayload: pingPayload,
                webhookSecret: secret,
                contextUser: TEST_USER,
            });

        const r1 = await sendPing('del-1');
        expect(r1.reason).toContain("Unsupported GitHub webhook event 'ping'");
        const r2 = await sendPing('del-2');
        expect(r2.reason).toContain("Unsupported GitHub webhook event 'ping'");

        // Duplicate while still within capacity=2
        const dup1 = await sendPing('del-1');
        expect(dup1.reason).toContain("Duplicate delivery ID 'del-1'");

        // Inserting del-3 evicts oldest ('del-1')
        await sendPing('del-3');
        const postEviction1 = await sendPing('del-1');
        expect(postEviction1.reason).toContain("Unsupported GitHub webhook event 'ping'");

        // Verify MaxTrackedCheckShas=2 evicts oldest commit SHA from bounded LRU check map
        GitHubWebhookService.Instance.ClearProcessedDeliveries();
        const noopFetcher: IGitHubLiveStateFetcher = {
            FetchCommitChecksStatus: async () => null,
            FetchPullRequestReviewDecision: async () => undefined,
        };
        GitHubWebhookService.Instance.SetLiveStateFetcher(noopFetcher);

        vi.spyOn(GitHubTaskSyncService.Instance, 'UpdatePullRequestChecksStatus').mockResolvedValue({
            action: 'updated',
            kind: 'pull_request',
            number: 1,
        });

        GitHubTasksEngineBase.Instance.ResetCaches();
        let engineLoadCalls = 0;
        const resolveView = async (params: RunViewParams): Promise<RunViewResult> => ({
            Success: true,
            Results:
                params.EntityName === GITHUB_REPOSITORIES_ENTITY_NAME
                    ? [
                          {
                              ID: '99999999-9999-4999-8999-999999999999',
                              Owner: 'MemberJunction',
                              Name: 'MJ',
                              IsTracked: true,
                          },
                      ]
                    : [],
            RowCount: params.EntityName === GITHUB_REPOSITORIES_ENTITY_NAME ? 1 : 0,
            TotalRowCount: params.EntityName === GITHUB_REPOSITORIES_ENTITY_NAME ? 1 : 0,
            ExecutionTime: 1,
            ErrorMessage: '',
            UserViewRunID: '',
        });

        const fakeProvider = {
            Entities: [],
            EntityByName: () => undefined,
            RunView: resolveView as IRunViewProvider['RunView'],
            RunViews: (async (views: RunViewParams[]): Promise<RunViewResult[]> => {
                engineLoadCalls += 1;
                return Promise.all(views.map((v) => resolveView(v)));
            }) as IRunViewProvider['RunViews'],
        } as Partial<IMetadataProvider & IRunViewProvider> as IMetadataProvider & IRunViewProvider;

        try {
            for (const [idx, sha] of ['sha-1', 'sha-2', 'sha-3'].entries()) {
                const checkPayload = JSON.stringify({
                    action: 'completed',
                    repository: { name: 'MJ', owner: { login: 'MemberJunction' } },
                    check_run: {
                        id: idx + 1,
                        name: 'build',
                        head_sha: sha,
                        status: 'completed',
                        conclusion: 'success',
                        pull_requests: [{ number: 1, base: { repo: { full_name: 'MemberJunction/MJ' } } }],
                    },
                });
                await GitHubWebhookService.Instance.HandleWebhook({
                    eventName: 'check_run',
                    deliveryId: `check-del-${idx + 1}`,
                    signatureHeader: sign(checkPayload),
                    rawPayload: checkPayload,
                    webhookSecret: secret,
                    contextUser: TEST_USER,
                    provider: fakeProvider,
                });
            }

            expect(GitHubWebhookService.Instance.GetTrackedCheckShaCount()).toBe(2);
            // All 3 webhook deliveries shared the single warm GitHubTasksEngineBase cache load
            expect(engineLoadCalls).toBe(1);
        } finally {
            GitHubTasksEngineBase.Instance.ResetCaches();
        }
    });
});
