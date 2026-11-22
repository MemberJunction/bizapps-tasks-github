import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { LimitsConfigResolver } from '@memberjunction/core';
import {
    DEFAULT_GITHUB_TASKS_LIMITS,
    GITHUB_APP_JWT_CLOCK_SKEW_SECONDS,
    GITHUB_APP_JWT_EXPIRATION_SECONDS,
    GITHUB_INSTALLATION_TOKEN_MAX_TTL_MS,
    GITHUB_REST_MAX_PER_PAGE,
    GITHUB_TASKS_LIMIT_DESCRIPTORS,
    GITHUB_TASKS_LIMITS_JSON_ENV_VAR,
    GITHUB_WEBHOOK_MAX_PAYLOAD_BYTES,
    GitHubTasksLimitsResolver,
    NormalizeGitHubTasksLimitsInput,
    ResolveGitHubTasksLimits,
    type GitHubTasksEnvMap,
} from '../index.js';

describe('GitHubTasksLimitsResolver & limits configuration', () => {
    beforeEach(() => {
        GitHubTasksLimitsResolver.Instance.ClearConfigLimits();
        LimitsConfigResolver.Instance.ClearMjConfigLimits();
    });

    afterEach(() => {
        GitHubTasksLimitsResolver.Instance.ClearConfigLimits();
        LimitsConfigResolver.Instance.ClearMjConfigLimits();
    });

    it('returns deterministic default fallbacks matching production baseline values with no overrides', () => {
        const result = GitHubTasksLimitsResolver.Resolve({ env: null });

        expect(result.Limits).toEqual(DEFAULT_GITHUB_TASKS_LIMITS);
        expect(result.OverriddenKeys).toEqual([]);
        expect(result.ClampedKeys).toEqual([]);
        expect(result.Limits.GitHubRest.SyncMaxPages).toBe(20);
        expect(result.Limits.GitHubRest.SyncPerPage).toBe(100);
        expect(result.Limits.GitHubRest.SyncRequestTimeoutMs).toBe(10_000);
        expect(result.Limits.GitHubRest.SyncMaxRetries).toBe(2);
        expect(result.Limits.GitHubRest.RetryAfterMaxDelayMs).toBe(2_000);
        expect(result.Limits.GitHubRest.RetryBaseDelayMs).toBe(150);
        expect(result.Limits.Webhook.LiveStateMaxPages).toBe(3);
        expect(result.Limits.Webhook.LiveStateRequestTimeoutMs).toBe(4_000);
        expect(result.Limits.Webhook.MaxTrackedDeliveryIds).toBe(5_000);
        expect(result.Limits.Webhook.MaxTrackedCheckShas).toBe(5_000);
        expect(result.Limits.Webhook.MaxTrackedPrReviews).toBe(5_000);
        expect(result.Limits.Webhook.MaxBodyBytes).toBe(10 * 1024 * 1024);
        expect(result.Limits.Auth.InstallationTokenCacheTtlMs).toBe(50 * 60 * 1000);
        expect(result.Limits.Auth.ErrorDetailMaxChars).toBe(200);
        expect(result.Limits.Inference.DebounceMs).toBe(1_500);
        expect(result.Limits.Inference.CandidateObjectivesMaxRows).toBe(50);
        expect(result.Limits.Inference.CandidateCategoriesMaxRows).toBe(50);
        expect(result.Limits.Inference.MinSuggestionConfidence).toBe(0.55);
        expect(result.Limits.CoS.StaleReviewThresholdHours).toBe(24);
        expect(result.Limits.CoS.DefaultPRLimit).toBe(25);
        expect(result.Limits.CoS.MaxPRLimit).toBe(100);
        expect(result.Limits.CoS.DefaultBriefingHorizonDays).toBe(7);
        expect(result.Limits.CoS.MaxBriefingHorizonDays).toBe(90);
        expect(result.Limits.CoS.DefaultBriefingLimit).toBe(10);
        expect(result.Limits.CoS.MaxBriefingLimit).toBe(50);
        expect(result.Limits.CoS.PersonUserLookupMaxRows).toBe(2);
        expect(result.Limits.CoS.PersonEmailLookupMaxRows).toBe(5);
        expect(result.CoreMjLimits.Limits.BriefingContributorTimeoutMs).toBe(10_000);
        expect(result.CoreMjLimits.Limits.BriefingMaxContributorChars).toBe(32_768);
    });

    it('exposes documented ProtocolLimit constants without mutable runtime overrides', () => {
        expect(GITHUB_REST_MAX_PER_PAGE).toBe(100);
        expect(GITHUB_APP_JWT_CLOCK_SKEW_SECONDS).toBe(60);
        expect(GITHUB_APP_JWT_EXPIRATION_SECONDS).toBe(540);
        expect(GITHUB_INSTALLATION_TOKEN_MAX_TTL_MS).toBe(3_600_000);
        expect(GITHUB_WEBHOOK_MAX_PAYLOAD_BYTES).toBe(25 * 1024 * 1024);
        expect(GITHUB_TASKS_LIMIT_DESCRIPTORS.length).toBe(27);
    });

    it('merges MjConfig -> Environment -> CallOverride in deterministic precedence order', () => {
        GitHubTasksLimitsResolver.Instance.RegisterConfigLimits({
            tasksGitHub: {
                GitHubRest: {
                    SyncMaxPages: 35,
                    SyncPerPage: 50,
                    SyncMaxRetries: 4,
                },
                Webhook: {
                    LiveStateMaxPages: 5,
                },
            },
        });

        const env: GitHubTasksEnvMap = {
            MJ_TASKS_GITHUB_LIMIT_GITHUB_REST_SYNC_MAX_PAGES: '45',
            MJ_TASKS_GITHUB_LIMIT_INFERENCE_DEBOUNCE_MS: '2500',
            [GITHUB_TASKS_LIMITS_JSON_ENV_VAR]: JSON.stringify({
                Auth: {
                    ErrorDetailMaxChars: 400,
                },
            }),
        };

        const result = GitHubTasksLimitsResolver.Resolve({
            env,
            override: {
                GitHubRest: {
                    SyncMaxRetries: 6,
                },
                Inference: {
                    MinSuggestionConfidence: 0.72,
                },
            },
        });

        expect(result.Limits.GitHubRest.SyncPerPage).toBe(50);
        expect(result.Provenance['GitHubRest.SyncPerPage'].SourceTier).toBe('MjConfig');

        expect(result.Limits.GitHubRest.SyncMaxPages).toBe(45);
        expect(result.Provenance['GitHubRest.SyncMaxPages'].SourceTier).toBe('Environment');

        expect(result.Limits.GitHubRest.SyncMaxRetries).toBe(6);
        expect(result.Provenance['GitHubRest.SyncMaxRetries'].SourceTier).toBe('CallOverride');

        expect(result.Limits.Webhook.LiveStateMaxPages).toBe(5);
        expect(result.Limits.Inference.DebounceMs).toBe(2500);
        expect(result.Limits.Auth.ErrorDetailMaxChars).toBe(400);
        expect(result.Limits.Inference.MinSuggestionConfidence).toBe(0.72);
    });

    it('falls back safely to valid lower tiers / defaults when overrides are NaN, Infinity, -Infinity, zero, negative, or malformed', () => {
        GitHubTasksLimitsResolver.Instance.RegisterConfigLimits({
            GitHubRest: {
                SyncMaxPages: 30,
                SyncRequestTimeoutMs: Number.NaN,
                SyncMaxRetries: Number.POSITIVE_INFINITY,
            },
            Webhook: {
                LiveStateMaxPages: Number.NEGATIVE_INFINITY,
                MaxTrackedDeliveryIds: 0,
                MaxTrackedCheckShas: -10,
            },
            Inference: {
                MinSuggestionConfidence: 0,
            },
        });

        const env: GitHubTasksEnvMap = {
            MJ_TASKS_GITHUB_LIMIT_GITHUB_REST_SYNC_MAX_PAGES: 'not-a-number',
            MJ_TASKS_GITHUB_LIMIT_WEBHOOK_LIVE_STATE_REQUEST_TIMEOUT_MS: 'Infinity',
            MJ_TASKS_GITHUB_LIMIT_AUTH_ERROR_DETAIL_MAX_CHARS: '-25',
            MJ_TASKS_GITHUB_LIMIT_COS_DEFAULT_PR_LIMIT: '0',
            MJ_TASKS_GITHUB_LIMIT_COS_MAX_PR_LIMIT: '12abc',
            [GITHUB_TASKS_LIMITS_JSON_ENV_VAR]: '{not valid json',
        };

        const result = GitHubTasksLimitsResolver.Resolve({
            env,
            override: {
                GitHubRest: {
                    RetryBaseDelayMs: 0.4, // truncates < 1 for integer limit -> rejected
                },
                Inference: {
                    MinSuggestionConfidence: -0.3,
                },
            },
        });

        // Invalid Environment string falls back to valid MjConfig tier (30)
        expect(result.Limits.GitHubRest.SyncMaxPages).toBe(30);
        expect(result.Provenance['GitHubRest.SyncMaxPages'].SourceTier).toBe('MjConfig');
        expect(result.Provenance['GitHubRest.SyncMaxPages'].RejectedInvalidOverrides).toBe(1);

        // Invalid MjConfig / Environment / CallOverride values fall back cleanly to CodeFallback defaults
        expect(result.Limits.GitHubRest.SyncRequestTimeoutMs).toBe(DEFAULT_GITHUB_TASKS_LIMITS.GitHubRest.SyncRequestTimeoutMs);
        expect(result.Limits.GitHubRest.SyncMaxRetries).toBe(DEFAULT_GITHUB_TASKS_LIMITS.GitHubRest.SyncMaxRetries);
        expect(result.Limits.GitHubRest.RetryBaseDelayMs).toBe(DEFAULT_GITHUB_TASKS_LIMITS.GitHubRest.RetryBaseDelayMs);
        expect(result.Limits.Webhook.LiveStateMaxPages).toBe(DEFAULT_GITHUB_TASKS_LIMITS.Webhook.LiveStateMaxPages);
        expect(result.Limits.Webhook.LiveStateRequestTimeoutMs).toBe(DEFAULT_GITHUB_TASKS_LIMITS.Webhook.LiveStateRequestTimeoutMs);
        expect(result.Limits.Webhook.MaxTrackedDeliveryIds).toBe(DEFAULT_GITHUB_TASKS_LIMITS.Webhook.MaxTrackedDeliveryIds);
        expect(result.Limits.Webhook.MaxTrackedCheckShas).toBe(DEFAULT_GITHUB_TASKS_LIMITS.Webhook.MaxTrackedCheckShas);
        expect(result.Limits.Auth.ErrorDetailMaxChars).toBe(DEFAULT_GITHUB_TASKS_LIMITS.Auth.ErrorDetailMaxChars);
        expect(result.Limits.CoS.DefaultPRLimit).toBe(DEFAULT_GITHUB_TASKS_LIMITS.CoS.DefaultPRLimit);
        expect(result.Limits.CoS.MaxPRLimit).toBe(DEFAULT_GITHUB_TASKS_LIMITS.CoS.MaxPRLimit);
        expect(result.Limits.Inference.MinSuggestionConfidence).toBe(DEFAULT_GITHUB_TASKS_LIMITS.Inference.MinSuggestionConfidence);
    });

    it('clamps Tuning and ResourceGuard values against GitHub API ProtocolLimit ceilings and paired max bounds', () => {
        const result = GitHubTasksLimitsResolver.Resolve({
            env: {
                MJ_TASKS_GITHUB_LIMIT_GITHUB_REST_SYNC_PER_PAGE: '500',
                MJ_TASKS_GITHUB_LIMIT_WEBHOOK_MAX_BODY_BYTES: String(100 * 1024 * 1024),
                MJ_TASKS_GITHUB_LIMIT_AUTH_INSTALLATION_TOKEN_CACHE_TTL_MS: String(90 * 60 * 1000),
            },
            override: {
                Inference: {
                    MinSuggestionConfidence: 1.5,
                },
                CoS: {
                    MaxPRLimit: 40,
                    DefaultPRLimit: 80,
                    MaxBriefingLimit: 15,
                    DefaultBriefingLimit: 25,
                    MaxBriefingHorizonDays: 14,
                    DefaultBriefingHorizonDays: 30,
                },
            },
        });

        expect(result.Limits.GitHubRest.SyncPerPage).toBe(GITHUB_REST_MAX_PER_PAGE);
        expect(result.Provenance['GitHubRest.SyncPerPage'].WasClampedToCeiling).toBe(true);

        expect(result.Limits.Webhook.MaxBodyBytes).toBe(GITHUB_WEBHOOK_MAX_PAYLOAD_BYTES);
        expect(result.Provenance['Webhook.MaxBodyBytes'].WasClampedToCeiling).toBe(true);

        expect(result.Limits.Auth.InstallationTokenCacheTtlMs).toBe(GITHUB_INSTALLATION_TOKEN_MAX_TTL_MS);
        expect(result.Provenance['Auth.InstallationTokenCacheTtlMs'].WasClampedToCeiling).toBe(true);

        expect(result.Limits.Inference.MinSuggestionConfidence).toBe(1);
        expect(result.Provenance['Inference.MinSuggestionConfidence'].WasClampedToCeiling).toBe(true);

        expect(result.Limits.CoS.DefaultPRLimit).toBe(40);
        expect(result.Limits.CoS.DefaultBriefingLimit).toBe(15);
        expect(result.Limits.CoS.DefaultBriefingHorizonDays).toBe(14);
        expect(result.ClampedKeys).toContain('GitHubRest.SyncPerPage');
        expect(result.ClampedKeys).toContain('Webhook.MaxBodyBytes');
        expect(result.ClampedKeys).toContain('Auth.InstallationTokenCacheTtlMs');
        expect(result.ClampedKeys).toContain('CoS.DefaultPRLimit');
    });

    it('normalizes mixed-case config objects via NormalizeGitHubTasksLimitsInput and integrates with core LimitsConfigResolver', () => {
        const normalized = NormalizeGitHubTasksLimitsInput({
            tasksGitHub: {
                gitHubRest: {
                    syncMaxPages: 12,
                    syncPerPage: 250,
                    syncMaxRetries: -1,
                },
                coS: {
                    staleReviewThresholdHours: 48,
                },
            },
        });

        expect(normalized).toEqual({
            GitHubRest: {
                SyncMaxPages: 12,
                SyncPerPage: 100,
            },
            CoS: {
                StaleReviewThresholdHours: 48,
            },
        });

        LimitsConfigResolver.Instance.RegisterMjConfigLimits({
            BriefingContributorTimeoutMs: 15_000,
        });
        const fullResult = GitHubTasksLimitsResolver.Resolve({
            env: null,
            override: normalized,
        });
        expect(fullResult.CoreMjLimits.Limits.BriefingContributorTimeoutMs).toBe(15_000);
        expect(ResolveGitHubTasksLimits({ env: null, override: normalized }).GitHubRest.SyncMaxPages).toBe(12);
    });
});
