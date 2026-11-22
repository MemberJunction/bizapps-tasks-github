/**
 * @fileoverview Centralized, strongly-typed execution limits, runaway-guard ceilings,
 * resource guards, and operational tuning configuration resolver for `@mj-biz-apps/tasks-github-*`.
 *
 * Wraps and integrates with `@memberjunction/core`'s {@link LimitsConfigResolver} so hosts
 * using `mj.config.cjs` / `LimitsConfigResolver.Instance` resolve core MemberJunction limits
 * alongside domain-specific GitHub Tasks sync, webhook, auth, inference, and CoS limits.
 *
 * Precedence order (lowest -> highest):
 * 1. `CodeFallback` (`DEFAULT_GITHUB_TASKS_LIMITS`)
 * 2. `MjConfig` (registered via `GitHubTasksLimitsResolver.Instance.RegisterConfigLimits`)
 * 3. `Environment` (`MJ_TASKS_GITHUB_LIMITS_JSON` and `MJ_TASKS_GITHUB_LIMIT_*` env vars)
 * 4. `CallOverride` (explicit per-call overrides passed to `Resolve()`)
 */

import {
    LimitsConfigResolver,
    type LimitsResolveOptions,
    type LimitsResolutionInput,
    type MJLimitsResolutionResult,
} from '@memberjunction/core';
import { BaseSingleton } from '@memberjunction/global';

// ============================================================================
// Documented External GitHub API ProtocolLimit Constants
// ============================================================================

/** ProtocolLimit: GitHub REST API v3 hard maximum items per page (`per_page <= 100`). */
export const GITHUB_REST_MAX_PER_PAGE = 100;

/** ProtocolLimit: GitHub App RS256 JWT `iat` clock-skew margin (60 seconds in the past). */
export const GITHUB_APP_JWT_CLOCK_SKEW_SECONDS = 60;

/** ProtocolLimit: GitHub App RS256 JWT expiration offset (+540s; max 600s total lifetime). */
export const GITHUB_APP_JWT_EXPIRATION_SECONDS = 540;

/** ProtocolLimit: GitHub App installation access tokens expire 60 minutes (3,600,000 ms) after minting. */
export const GITHUB_INSTALLATION_TOKEN_MAX_TTL_MS = 60 * 60 * 1000;

/** ProtocolLimit: GitHub Webhooks maximum HTTP delivery payload size (25 MiB). */
export const GITHUB_WEBHOOK_MAX_PAYLOAD_BYTES = 25 * 1024 * 1024;

// ============================================================================
// Limit Categories, Config Interfaces & Key Paths
// ============================================================================

export type GitHubTasksLimitCategory = 'RunawayGuard' | 'ResourceGuard' | 'Tuning';

export type GitHubTasksLimitsSourceTier =
    | 'CodeFallback'
    | 'MjConfig'
    | 'Environment'
    | 'CallOverride';

export const GITHUB_TASKS_LIMITS_TIER_PRECEDENCE: readonly GitHubTasksLimitsSourceTier[] = [
    'CodeFallback',
    'MjConfig',
    'Environment',
    'CallOverride',
] as const;

export interface GitHubRestLimitsConfig {
    /** RunawayGuard: maximum pagination pages fetched per GitHub REST endpoint (/issues or /pulls). */
    SyncMaxPages: number;
    /** Tuning: GitHub REST `per_page` batch size (clamped <= {@link GITHUB_REST_MAX_PER_PAGE}). */
    SyncPerPage: number;
    /** ResourceGuard: per-request AbortSignal timeout in ms for GitHub REST sync calls. */
    SyncRequestTimeoutMs: number;
    /** ResourceGuard: maximum transient HTTP retry attempts (429/502/503/504) per sync request. */
    SyncMaxRetries: number;
    /** ResourceGuard: upper ceiling in ms when honoring HTTP `Retry-After` headers. */
    RetryAfterMaxDelayMs: number;
    /** Tuning: base linear backoff delay in ms when `Retry-After` header is absent. */
    RetryBaseDelayMs: number;
}

export interface GitHubWebhookLimitsConfig {
    /** RunawayGuard: maximum pagination pages fetched for commit check-runs or PR reviews per webhook. */
    LiveStateMaxPages: number;
    /** ResourceGuard: per-request AbortSignal timeout in ms for webhook live-state REST lookups. */
    LiveStateRequestTimeoutMs: number;
    /** ResourceGuard: maximum `X-GitHub-Delivery` IDs retained in in-memory deduplication set. */
    MaxTrackedDeliveryIds: number;
    /** ResourceGuard: maximum commit SHAs retained in in-memory LRU check-status fallback map. */
    MaxTrackedCheckShas: number;
    /** ResourceGuard: maximum pull requests retained in in-memory LRU review-decision fallback map. */
    MaxTrackedPrReviews: number;
    /** ResourceGuard: maximum webhook HTTP body size in bytes (clamped <= {@link GITHUB_WEBHOOK_MAX_PAYLOAD_BYTES}). */
    MaxBodyBytes: number;
}

export interface GitHubAuthLimitsConfig {
    /** Tuning: GitHub App installation token cache TTL in ms (clamped <= {@link GITHUB_INSTALLATION_TOKEN_MAX_TTL_MS}). */
    InstallationTokenCacheTtlMs: number;
    /** ResourceGuard: maximum error response characters retained from token exchange failures. */
    ErrorDetailMaxChars: number;
}

export interface GitHubInferenceLimitsConfig {
    /** Tuning: default debounce window in ms coalescing rapid webhook edits before LLM inference. */
    DebounceMs: number;
    /** ResourceGuard: maximum candidate open issue objectives loaded into LLM prompt context. */
    CandidateObjectivesMaxRows: number;
    /** ResourceGuard: maximum candidate active task categories loaded into LLM prompt context. */
    CandidateCategoriesMaxRows: number;
    /** Tuning: minimum confidence score in (0, 1] required to persist an inferred Field Suggestion. */
    MinSuggestionConfidence: number;
}

export interface GitHubCoSLimitsConfig {
    /** Tuning: hours after which a pending PR review request is marked stale. */
    StaleReviewThresholdHours: number;
    /** Tuning: default PR/review limit returned by CoS actions (clamped <= `MaxPRLimit`). */
    DefaultPRLimit: number;
    /** ResourceGuard: hard ceiling on `Limit` parameter in CoS PR/review actions. */
    MaxPRLimit: number;
    /** Tuning: default horizon in days for GitHub briefing (clamped <= `MaxBriefingHorizonDays`). */
    DefaultBriefingHorizonDays: number;
    /** ResourceGuard: hard ceiling on `HorizonDays` parameter in `GetMyGitHubBriefingAction`. */
    MaxBriefingHorizonDays: number;
    /** Tuning: default per-section item limit in `GetMyGitHubBriefingAction` (clamped <= `MaxBriefingLimit`). */
    DefaultBriefingLimit: number;
    /** ResourceGuard: hard ceiling on `Limit`/`MaxItems` parameter in `GetMyGitHubBriefingAction`. */
    MaxBriefingLimit: number;
    /** ResourceGuard: bounded query cap for `LinkedUserID` person resolution ambiguity checks. */
    PersonUserLookupMaxRows: number;
    /** ResourceGuard: bounded candidate fetch cap when matching caller Person by email. */
    PersonEmailLookupMaxRows: number;
}

export interface GitHubTasksLimitsConfig {
    GitHubRest: GitHubRestLimitsConfig;
    Webhook: GitHubWebhookLimitsConfig;
    Auth: GitHubAuthLimitsConfig;
    Inference: GitHubInferenceLimitsConfig;
    CoS: GitHubCoSLimitsConfig;
}

export interface GitHubTasksLimitsOverride {
    GitHubRest?: Partial<GitHubRestLimitsConfig>;
    Webhook?: Partial<GitHubWebhookLimitsConfig>;
    Auth?: Partial<GitHubAuthLimitsConfig>;
    Inference?: Partial<GitHubInferenceLimitsConfig>;
    CoS?: Partial<GitHubCoSLimitsConfig>;
}

export type GitHubRestLimitKeyPath = `GitHubRest.${keyof GitHubRestLimitsConfig}`;
export type GitHubWebhookLimitKeyPath = `Webhook.${keyof GitHubWebhookLimitsConfig}`;
export type GitHubAuthLimitKeyPath = `Auth.${keyof GitHubAuthLimitsConfig}`;
export type GitHubInferenceLimitKeyPath = `Inference.${keyof GitHubInferenceLimitsConfig}`;
export type GitHubCoSLimitKeyPath = `CoS.${keyof GitHubCoSLimitsConfig}`;

export type GitHubTasksLimitKeyPath =
    | GitHubRestLimitKeyPath
    | GitHubWebhookLimitKeyPath
    | GitHubAuthLimitKeyPath
    | GitHubInferenceLimitKeyPath
    | GitHubCoSLimitKeyPath;

export interface GitHubTasksLimitDescriptor {
    readonly Key: GitHubTasksLimitKeyPath;
    readonly Category: GitHubTasksLimitCategory;
    readonly EnvVar: string;
    readonly DefaultValue: number;
    readonly ValueKind: 'positiveInt' | 'unitFraction';
    readonly ProtocolCeiling?: number;
    readonly MaxKeyDependency?: GitHubTasksLimitKeyPath;
}

/**
 * Approved code fallback defaults matching existing production values so unset configurations
 * preserve exact runtime behavior.
 */
export const DEFAULT_GITHUB_TASKS_LIMITS: Readonly<GitHubTasksLimitsConfig> = {
    GitHubRest: {
        SyncMaxPages: 20,
        SyncPerPage: 100,
        SyncRequestTimeoutMs: 10_000,
        SyncMaxRetries: 2,
        RetryAfterMaxDelayMs: 2_000,
        RetryBaseDelayMs: 150,
    },
    Webhook: {
        LiveStateMaxPages: 3,
        LiveStateRequestTimeoutMs: 4_000,
        MaxTrackedDeliveryIds: 5_000,
        MaxTrackedCheckShas: 5_000,
        MaxTrackedPrReviews: 5_000,
        MaxBodyBytes: 10 * 1024 * 1024,
    },
    Auth: {
        InstallationTokenCacheTtlMs: 50 * 60 * 1000,
        ErrorDetailMaxChars: 200,
    },
    Inference: {
        DebounceMs: 1_500,
        CandidateObjectivesMaxRows: 50,
        CandidateCategoriesMaxRows: 50,
        MinSuggestionConfidence: 0.55,
    },
    CoS: {
        StaleReviewThresholdHours: 24,
        DefaultPRLimit: 25,
        MaxPRLimit: 100,
        DefaultBriefingHorizonDays: 7,
        MaxBriefingHorizonDays: 90,
        DefaultBriefingLimit: 10,
        MaxBriefingLimit: 50,
        PersonUserLookupMaxRows: 2,
        PersonEmailLookupMaxRows: 5,
    },
};

export const GITHUB_TASKS_LIMIT_DESCRIPTORS: readonly GitHubTasksLimitDescriptor[] = [
    {
        Key: 'GitHubRest.SyncMaxPages',
        Category: 'RunawayGuard',
        EnvVar: 'MJ_TASKS_GITHUB_LIMIT_GITHUB_REST_SYNC_MAX_PAGES',
        DefaultValue: DEFAULT_GITHUB_TASKS_LIMITS.GitHubRest.SyncMaxPages,
        ValueKind: 'positiveInt',
    },
    {
        Key: 'GitHubRest.SyncPerPage',
        Category: 'Tuning',
        EnvVar: 'MJ_TASKS_GITHUB_LIMIT_GITHUB_REST_SYNC_PER_PAGE',
        DefaultValue: DEFAULT_GITHUB_TASKS_LIMITS.GitHubRest.SyncPerPage,
        ValueKind: 'positiveInt',
        ProtocolCeiling: GITHUB_REST_MAX_PER_PAGE,
    },
    {
        Key: 'GitHubRest.SyncRequestTimeoutMs',
        Category: 'ResourceGuard',
        EnvVar: 'MJ_TASKS_GITHUB_LIMIT_GITHUB_REST_SYNC_REQUEST_TIMEOUT_MS',
        DefaultValue: DEFAULT_GITHUB_TASKS_LIMITS.GitHubRest.SyncRequestTimeoutMs,
        ValueKind: 'positiveInt',
    },
    {
        Key: 'GitHubRest.SyncMaxRetries',
        Category: 'ResourceGuard',
        EnvVar: 'MJ_TASKS_GITHUB_LIMIT_GITHUB_REST_SYNC_MAX_RETRIES',
        DefaultValue: DEFAULT_GITHUB_TASKS_LIMITS.GitHubRest.SyncMaxRetries,
        ValueKind: 'positiveInt',
    },
    {
        Key: 'GitHubRest.RetryAfterMaxDelayMs',
        Category: 'ResourceGuard',
        EnvVar: 'MJ_TASKS_GITHUB_LIMIT_GITHUB_REST_RETRY_AFTER_MAX_DELAY_MS',
        DefaultValue: DEFAULT_GITHUB_TASKS_LIMITS.GitHubRest.RetryAfterMaxDelayMs,
        ValueKind: 'positiveInt',
    },
    {
        Key: 'GitHubRest.RetryBaseDelayMs',
        Category: 'Tuning',
        EnvVar: 'MJ_TASKS_GITHUB_LIMIT_GITHUB_REST_RETRY_BASE_DELAY_MS',
        DefaultValue: DEFAULT_GITHUB_TASKS_LIMITS.GitHubRest.RetryBaseDelayMs,
        ValueKind: 'positiveInt',
    },
    {
        Key: 'Webhook.LiveStateMaxPages',
        Category: 'RunawayGuard',
        EnvVar: 'MJ_TASKS_GITHUB_LIMIT_WEBHOOK_LIVE_STATE_MAX_PAGES',
        DefaultValue: DEFAULT_GITHUB_TASKS_LIMITS.Webhook.LiveStateMaxPages,
        ValueKind: 'positiveInt',
    },
    {
        Key: 'Webhook.LiveStateRequestTimeoutMs',
        Category: 'ResourceGuard',
        EnvVar: 'MJ_TASKS_GITHUB_LIMIT_WEBHOOK_LIVE_STATE_REQUEST_TIMEOUT_MS',
        DefaultValue: DEFAULT_GITHUB_TASKS_LIMITS.Webhook.LiveStateRequestTimeoutMs,
        ValueKind: 'positiveInt',
    },
    {
        Key: 'Webhook.MaxTrackedDeliveryIds',
        Category: 'ResourceGuard',
        EnvVar: 'MJ_TASKS_GITHUB_LIMIT_WEBHOOK_MAX_TRACKED_DELIVERY_IDS',
        DefaultValue: DEFAULT_GITHUB_TASKS_LIMITS.Webhook.MaxTrackedDeliveryIds,
        ValueKind: 'positiveInt',
    },
    {
        Key: 'Webhook.MaxTrackedCheckShas',
        Category: 'ResourceGuard',
        EnvVar: 'MJ_TASKS_GITHUB_LIMIT_WEBHOOK_MAX_TRACKED_CHECK_SHAS',
        DefaultValue: DEFAULT_GITHUB_TASKS_LIMITS.Webhook.MaxTrackedCheckShas,
        ValueKind: 'positiveInt',
    },
    {
        Key: 'Webhook.MaxTrackedPrReviews',
        Category: 'ResourceGuard',
        EnvVar: 'MJ_TASKS_GITHUB_LIMIT_WEBHOOK_MAX_TRACKED_PR_REVIEWS',
        DefaultValue: DEFAULT_GITHUB_TASKS_LIMITS.Webhook.MaxTrackedPrReviews,
        ValueKind: 'positiveInt',
    },
    {
        Key: 'Webhook.MaxBodyBytes',
        Category: 'ResourceGuard',
        EnvVar: 'MJ_TASKS_GITHUB_LIMIT_WEBHOOK_MAX_BODY_BYTES',
        DefaultValue: DEFAULT_GITHUB_TASKS_LIMITS.Webhook.MaxBodyBytes,
        ValueKind: 'positiveInt',
        ProtocolCeiling: GITHUB_WEBHOOK_MAX_PAYLOAD_BYTES,
    },
    {
        Key: 'Auth.InstallationTokenCacheTtlMs',
        Category: 'Tuning',
        EnvVar: 'MJ_TASKS_GITHUB_LIMIT_AUTH_INSTALLATION_TOKEN_CACHE_TTL_MS',
        DefaultValue: DEFAULT_GITHUB_TASKS_LIMITS.Auth.InstallationTokenCacheTtlMs,
        ValueKind: 'positiveInt',
        ProtocolCeiling: GITHUB_INSTALLATION_TOKEN_MAX_TTL_MS,
    },
    {
        Key: 'Auth.ErrorDetailMaxChars',
        Category: 'ResourceGuard',
        EnvVar: 'MJ_TASKS_GITHUB_LIMIT_AUTH_ERROR_DETAIL_MAX_CHARS',
        DefaultValue: DEFAULT_GITHUB_TASKS_LIMITS.Auth.ErrorDetailMaxChars,
        ValueKind: 'positiveInt',
    },
    {
        Key: 'Inference.DebounceMs',
        Category: 'Tuning',
        EnvVar: 'MJ_TASKS_GITHUB_LIMIT_INFERENCE_DEBOUNCE_MS',
        DefaultValue: DEFAULT_GITHUB_TASKS_LIMITS.Inference.DebounceMs,
        ValueKind: 'positiveInt',
    },
    {
        Key: 'Inference.CandidateObjectivesMaxRows',
        Category: 'ResourceGuard',
        EnvVar: 'MJ_TASKS_GITHUB_LIMIT_INFERENCE_CANDIDATE_OBJECTIVES_MAX_ROWS',
        DefaultValue: DEFAULT_GITHUB_TASKS_LIMITS.Inference.CandidateObjectivesMaxRows,
        ValueKind: 'positiveInt',
    },
    {
        Key: 'Inference.CandidateCategoriesMaxRows',
        Category: 'ResourceGuard',
        EnvVar: 'MJ_TASKS_GITHUB_LIMIT_INFERENCE_CANDIDATE_CATEGORIES_MAX_ROWS',
        DefaultValue: DEFAULT_GITHUB_TASKS_LIMITS.Inference.CandidateCategoriesMaxRows,
        ValueKind: 'positiveInt',
    },
    {
        Key: 'Inference.MinSuggestionConfidence',
        Category: 'Tuning',
        EnvVar: 'MJ_TASKS_GITHUB_LIMIT_INFERENCE_MIN_SUGGESTION_CONFIDENCE',
        DefaultValue: DEFAULT_GITHUB_TASKS_LIMITS.Inference.MinSuggestionConfidence,
        ValueKind: 'unitFraction',
        ProtocolCeiling: 1,
    },
    {
        Key: 'CoS.StaleReviewThresholdHours',
        Category: 'Tuning',
        EnvVar: 'MJ_TASKS_GITHUB_LIMIT_COS_STALE_REVIEW_THRESHOLD_HOURS',
        DefaultValue: DEFAULT_GITHUB_TASKS_LIMITS.CoS.StaleReviewThresholdHours,
        ValueKind: 'positiveInt',
    },
    {
        Key: 'CoS.MaxPRLimit',
        Category: 'ResourceGuard',
        EnvVar: 'MJ_TASKS_GITHUB_LIMIT_COS_MAX_PR_LIMIT',
        DefaultValue: DEFAULT_GITHUB_TASKS_LIMITS.CoS.MaxPRLimit,
        ValueKind: 'positiveInt',
    },
    {
        Key: 'CoS.DefaultPRLimit',
        Category: 'Tuning',
        EnvVar: 'MJ_TASKS_GITHUB_LIMIT_COS_DEFAULT_PR_LIMIT',
        DefaultValue: DEFAULT_GITHUB_TASKS_LIMITS.CoS.DefaultPRLimit,
        ValueKind: 'positiveInt',
        MaxKeyDependency: 'CoS.MaxPRLimit',
    },
    {
        Key: 'CoS.MaxBriefingHorizonDays',
        Category: 'ResourceGuard',
        EnvVar: 'MJ_TASKS_GITHUB_LIMIT_COS_MAX_BRIEFING_HORIZON_DAYS',
        DefaultValue: DEFAULT_GITHUB_TASKS_LIMITS.CoS.MaxBriefingHorizonDays,
        ValueKind: 'positiveInt',
    },
    {
        Key: 'CoS.DefaultBriefingHorizonDays',
        Category: 'Tuning',
        EnvVar: 'MJ_TASKS_GITHUB_LIMIT_COS_DEFAULT_BRIEFING_HORIZON_DAYS',
        DefaultValue: DEFAULT_GITHUB_TASKS_LIMITS.CoS.DefaultBriefingHorizonDays,
        ValueKind: 'positiveInt',
        MaxKeyDependency: 'CoS.MaxBriefingHorizonDays',
    },
    {
        Key: 'CoS.MaxBriefingLimit',
        Category: 'ResourceGuard',
        EnvVar: 'MJ_TASKS_GITHUB_LIMIT_COS_MAX_BRIEFING_LIMIT',
        DefaultValue: DEFAULT_GITHUB_TASKS_LIMITS.CoS.MaxBriefingLimit,
        ValueKind: 'positiveInt',
    },
    {
        Key: 'CoS.DefaultBriefingLimit',
        Category: 'Tuning',
        EnvVar: 'MJ_TASKS_GITHUB_LIMIT_COS_DEFAULT_BRIEFING_LIMIT',
        DefaultValue: DEFAULT_GITHUB_TASKS_LIMITS.CoS.DefaultBriefingLimit,
        ValueKind: 'positiveInt',
        MaxKeyDependency: 'CoS.MaxBriefingLimit',
    },
    {
        Key: 'CoS.PersonUserLookupMaxRows',
        Category: 'ResourceGuard',
        EnvVar: 'MJ_TASKS_GITHUB_LIMIT_COS_PERSON_USER_LOOKUP_MAX_ROWS',
        DefaultValue: DEFAULT_GITHUB_TASKS_LIMITS.CoS.PersonUserLookupMaxRows,
        ValueKind: 'positiveInt',
    },
    {
        Key: 'CoS.PersonEmailLookupMaxRows',
        Category: 'ResourceGuard',
        EnvVar: 'MJ_TASKS_GITHUB_LIMIT_COS_PERSON_EMAIL_LOOKUP_MAX_ROWS',
        DefaultValue: DEFAULT_GITHUB_TASKS_LIMITS.CoS.PersonEmailLookupMaxRows,
        ValueKind: 'positiveInt',
    },
] as const;

export const GITHUB_TASKS_LIMITS_JSON_ENV_VAR = 'MJ_TASKS_GITHUB_LIMITS_JSON';

// ============================================================================
// Typed Input / Provenance / Result Shapes (Zero `any`, Zero `unknown`)
// ============================================================================

export type GitHubTasksLimitsInputScalar = string | number | boolean | null | undefined;

export interface GitHubTasksLimitsInputObject {
    [key: string]: GitHubTasksLimitsInputValue;
}

export type GitHubTasksLimitsInputValue =
    | GitHubTasksLimitsInputScalar
    | GitHubTasksLimitsInputObject
    | readonly GitHubTasksLimitsInputValue[]
    | GitHubTasksLimitsOverride;

export type GitHubTasksEnvMap = Record<string, string | undefined>;

export interface GitHubTasksLimitProvenance {
    Key: GitHubTasksLimitKeyPath;
    Category: GitHubTasksLimitCategory;
    Value: number;
    SourceTier: GitHubTasksLimitsSourceTier;
    IsOverridden: boolean;
    WasClampedToCeiling: boolean;
    RejectedInvalidOverrides: number;
}

export interface GitHubTasksLimitsResolveOptions {
    /** Optional per-call `MjConfig` override (`null` suppresses registered MjConfig for this call). */
    mjConfig?: GitHubTasksLimitsOverride | GitHubTasksLimitsInputObject | null;
    /** Optional environment map override (`null` skips `process.env` lookup; defaults to `process.env`). */
    env?: GitHubTasksEnvMap | null;
    /** Optional per-call override (highest precedence). */
    override?: GitHubTasksLimitsOverride | GitHubTasksLimitsInputObject | null;
    /** Optional core MJ limits resolution input forwarded to `@memberjunction/core` `LimitsConfigResolver`. */
    coreMjLimitsInput?: LimitsResolutionInput;
    /** Optional core MJ limits resolution options forwarded to `@memberjunction/core` `LimitsConfigResolver`. */
    coreMjLimitsOptions?: LimitsResolveOptions;
}

export interface GitHubTasksLimitsResolutionResult {
    Limits: GitHubTasksLimitsConfig;
    Provenance: Record<GitHubTasksLimitKeyPath, GitHubTasksLimitProvenance>;
    OverriddenKeys: GitHubTasksLimitKeyPath[];
    ClampedKeys: GitHubTasksLimitKeyPath[];
    CoreMjLimits: MJLimitsResolutionResult;
}

// ============================================================================
// Defensive Validation & Normalization Helpers
// ============================================================================

function isInputObject(raw: GitHubTasksLimitsInputValue): raw is GitHubTasksLimitsInputObject {
    return typeof raw === 'object' && raw !== null && !Array.isArray(raw);
}

function readObjectProperty(
    obj: GitHubTasksLimitsInputObject,
    keys: readonly string[],
): GitHubTasksLimitsInputValue {
    for (const key of keys) {
        if (Object.prototype.hasOwnProperty.call(obj, key)) {
            return obj[key];
        }
    }
    return undefined;
}

function toCamelCaseKey(pascalKey: string): string {
    if (!pascalKey) {
        return pascalKey;
    }
    return pascalKey.charAt(0).toLowerCase() + pascalKey.slice(1);
}

/**
 * Parses a raw override candidate into a finite strictly-positive number (`> 0`).
 * Returns `undefined` for `NaN`, `Infinity`, `-Infinity`, `<= 0`, non-numeric strings, booleans,
 * objects, or arrays.
 */
function parseStrictPositiveNumber(raw: GitHubTasksLimitsInputValue): number | undefined {
    let numeric: number;
    if (typeof raw === 'number') {
        numeric = raw;
    } else if (typeof raw === 'string') {
        const trimmed = raw.trim();
        if (trimmed.length === 0) {
            return undefined;
        }
        numeric = Number(trimmed);
    } else {
        return undefined;
    }

    if (!Number.isFinite(numeric) || numeric <= 0) {
        return undefined;
    }
    return numeric;
}

function parseDescriptorOverrideValue(
    raw: GitHubTasksLimitsInputValue,
    descriptor: GitHubTasksLimitDescriptor,
): { value: number | undefined; rejectedInvalid: boolean } {
    if (raw === undefined) {
        return { value: undefined, rejectedInvalid: false };
    }
    const parsed = parseStrictPositiveNumber(raw);
    if (parsed === undefined) {
        return { value: undefined, rejectedInvalid: true };
    }
    if (descriptor.ValueKind === 'positiveInt') {
        const truncated = Math.trunc(parsed);
        if (truncated < 1) {
            return { value: undefined, rejectedInvalid: true };
        }
        return { value: truncated, rejectedInvalid: false };
    }
    return { value: parsed, rejectedInvalid: false };
}

function cloneDefaultLimits(): GitHubTasksLimitsConfig {
    return {
        GitHubRest: { ...DEFAULT_GITHUB_TASKS_LIMITS.GitHubRest },
        Webhook: { ...DEFAULT_GITHUB_TASKS_LIMITS.Webhook },
        Auth: { ...DEFAULT_GITHUB_TASKS_LIMITS.Auth },
        Inference: { ...DEFAULT_GITHUB_TASKS_LIMITS.Inference },
        CoS: { ...DEFAULT_GITHUB_TASKS_LIMITS.CoS },
    };
}

function getKeyValueFromConfig(config: GitHubTasksLimitsConfig, key: GitHubTasksLimitKeyPath): number {
    const [section, field] = key.split('.') as [
        keyof GitHubTasksLimitsConfig,
        string,
    ];
    switch (section) {
        case 'GitHubRest':
            return config.GitHubRest[field as keyof GitHubRestLimitsConfig];
        case 'Webhook':
            return config.Webhook[field as keyof GitHubWebhookLimitsConfig];
        case 'Auth':
            return config.Auth[field as keyof GitHubAuthLimitsConfig];
        case 'Inference':
            return config.Inference[field as keyof GitHubInferenceLimitsConfig];
        case 'CoS':
            return config.CoS[field as keyof GitHubCoSLimitsConfig];
    }
}

function setKeyValueOnConfig(
    config: GitHubTasksLimitsConfig,
    key: GitHubTasksLimitKeyPath,
    value: number,
): void {
    const [section, field] = key.split('.') as [
        keyof GitHubTasksLimitsConfig,
        string,
    ];
    switch (section) {
        case 'GitHubRest':
            config.GitHubRest[field as keyof GitHubRestLimitsConfig] = value;
            break;
        case 'Webhook':
            config.Webhook[field as keyof GitHubWebhookLimitsConfig] = value;
            break;
        case 'Auth':
            config.Auth[field as keyof GitHubAuthLimitsConfig] = value;
            break;
        case 'Inference':
            config.Inference[field as keyof GitHubInferenceLimitsConfig] = value;
            break;
        case 'CoS':
            config.CoS[field as keyof GitHubCoSLimitsConfig] = value;
            break;
    }
}

function extractOverrideCandidateForKey(
    layer: GitHubTasksLimitsInputObject | null,
    key: GitHubTasksLimitKeyPath,
): GitHubTasksLimitsInputValue {
    if (!layer) {
        return undefined;
    }
    const [sectionName, fieldName] = key.split('.') as [
        keyof GitHubTasksLimitsConfig,
        string,
    ];
    const sectionVal = readObjectProperty(layer, [sectionName, toCamelCaseKey(sectionName)]);
    if (isInputObject(sectionVal)) {
        const fromSection = readObjectProperty(sectionVal, [fieldName, toCamelCaseKey(fieldName)]);
        if (fromSection !== undefined) {
            return fromSection;
        }
    }
    return readObjectProperty(layer, [key]);
}

function unwrapScopedConfigInput(
    raw: GitHubTasksLimitsOverride | GitHubTasksLimitsInputObject | null | undefined,
): GitHubTasksLimitsInputObject | null {
    if (!raw || !isInputObject(raw)) {
        return null;
    }
    const nested = readObjectProperty(raw, ['tasksGitHub', 'TasksGitHub']);
    if (isInputObject(nested)) {
        return nested;
    }
    return raw;
}

function buildEnvironmentInputLayer(env: GitHubTasksEnvMap | null | undefined): GitHubTasksLimitsInputObject | null {
    if (!env) {
        return null;
    }
    const layer: GitHubTasksLimitsInputObject = {};
    let hasEntries = false;

    const rawJson = env[GITHUB_TASKS_LIMITS_JSON_ENV_VAR];
    if (typeof rawJson === 'string' && rawJson.trim().length > 0) {
        try {
            const parsed: GitHubTasksLimitsInputValue = JSON.parse(rawJson);
            const unwrapped = isInputObject(parsed) ? unwrapScopedConfigInput(parsed) : null;
            if (unwrapped) {
                for (const [k, v] of Object.entries(unwrapped)) {
                    layer[k] = v;
                    hasEntries = true;
                }
            }
        } catch {
            // Malformed JSON override is ignored safely; defaults/valid per-key env vars remain intact
        }
    }

    for (const descriptor of GITHUB_TASKS_LIMIT_DESCRIPTORS) {
        const rawEnvVal = env[descriptor.EnvVar];
        if (typeof rawEnvVal === 'string') {
            layer[descriptor.Key] = rawEnvVal;
            hasEntries = true;
        }
    }

    return hasEntries ? layer : null;
}

/**
 * Normalizes an arbitrary config/override object into a validated {@link GitHubTasksLimitsOverride}.
 * Rejects `NaN`, `Infinity`, `-Infinity`, `<= 0`, non-finite, or malformed values and clamps any
 * value exceeding its documented GitHub API `ProtocolLimit` ceiling.
 */
export function NormalizeGitHubTasksLimitsInput(
    raw: GitHubTasksLimitsOverride | GitHubTasksLimitsInputObject | null | undefined,
): GitHubTasksLimitsOverride {
    const layer = unwrapScopedConfigInput(raw);
    if (!layer) {
        return {};
    }
    const out: GitHubTasksLimitsOverride = {};
    for (const descriptor of GITHUB_TASKS_LIMIT_DESCRIPTORS) {
        const candidate = extractOverrideCandidateForKey(layer, descriptor.Key);
        const parsed = parseDescriptorOverrideValue(candidate, descriptor);
        if (parsed.value === undefined) {
            continue;
        }
        const bounded =
            descriptor.ProtocolCeiling !== undefined && parsed.value > descriptor.ProtocolCeiling
                ? descriptor.ProtocolCeiling
                : parsed.value;
        const [section, field] = descriptor.Key.split('.') as [
            keyof GitHubTasksLimitsOverride,
            string,
        ];
        if (section === 'GitHubRest') {
            out.GitHubRest ??= {};
            out.GitHubRest[field as keyof GitHubRestLimitsConfig] = bounded;
        } else if (section === 'Webhook') {
            out.Webhook ??= {};
            out.Webhook[field as keyof GitHubWebhookLimitsConfig] = bounded;
        } else if (section === 'Auth') {
            out.Auth ??= {};
            out.Auth[field as keyof GitHubAuthLimitsConfig] = bounded;
        } else if (section === 'Inference') {
            out.Inference ??= {};
            out.Inference[field as keyof GitHubInferenceLimitsConfig] = bounded;
        } else if (section === 'CoS') {
            out.CoS ??= {};
            out.CoS[field as keyof GitHubCoSLimitsConfig] = bounded;
        }
    }
    return out;
}

// ============================================================================
// Singleton Resolver
// ============================================================================

/**
 * Strongly-typed singleton limits resolver for `bizapps-tasks-github`, integrating with
 * `@memberjunction/core`'s {@link LimitsConfigResolver}.
 */
export class GitHubTasksLimitsResolver extends BaseSingleton<GitHubTasksLimitsResolver> {
    private _registeredConfigLayer: GitHubTasksLimitsInputObject | null = null;

    public constructor() {
        super();
    }

    public static get Instance(): GitHubTasksLimitsResolver {
        return GitHubTasksLimitsResolver.getInstance<GitHubTasksLimitsResolver>();
    }

    /**
     * Convenience static entry point delegating to {@link GitHubTasksLimitsResolver.Instance.Resolve}.
     */
    public static Resolve(options?: GitHubTasksLimitsResolveOptions): GitHubTasksLimitsResolutionResult {
        return GitHubTasksLimitsResolver.Instance.Resolve(options);
    }

    /**
     * Convenience static entry point returning just the resolved {@link GitHubTasksLimitsConfig}.
     */
    public static GetLimits(options?: GitHubTasksLimitsResolveOptions): GitHubTasksLimitsConfig {
        return GitHubTasksLimitsResolver.Instance.Resolve(options).Limits;
    }

    /**
     * Registers host configuration limits (for example from `mj.config.cjs`'s `limits.tasksGitHub`).
     * Pass `null` to clear any previously registered configuration.
     */
    public RegisterConfigLimits(
        config: GitHubTasksLimitsOverride | GitHubTasksLimitsInputObject | null,
    ): void {
        this._registeredConfigLayer = unwrapScopedConfigInput(config);
    }

    /**
     * Clears any registered `MjConfig` override (primarily for unit test isolation).
     */
    public ClearConfigLimits(): void {
        this._registeredConfigLayer = null;
    }

    /**
     * Resolves core MemberJunction limits via `@memberjunction/core`'s {@link LimitsConfigResolver}.
     */
    public ResolveCoreMjLimits(
        input?: LimitsResolutionInput,
        options?: LimitsResolveOptions,
    ): MJLimitsResolutionResult {
        return LimitsConfigResolver.Instance.Resolve(input, options);
    }

    /**
     * Resolves all `bizapps-tasks-github` limits across `CodeFallback -> MjConfig -> Environment -> CallOverride`,
     * validating inputs defensively, enforcing external GitHub API `ProtocolLimit` ceilings, and tracking
     * per-key provenance.
     */
    public Resolve(options: GitHubTasksLimitsResolveOptions = {}): GitHubTasksLimitsResolutionResult {
        const resolved = cloneDefaultLimits();
        const envMap =
            options.env === null
                ? null
                : (options.env ?? (typeof process !== 'undefined' ? process.env : null));

        const mjConfigLayer =
            options.mjConfig === undefined
                ? this._registeredConfigLayer
                : unwrapScopedConfigInput(options.mjConfig);
        const envLayer = buildEnvironmentInputLayer(envMap);
        const callLayer = unwrapScopedConfigInput(options.override);

        const layersByTier: Record<GitHubTasksLimitsSourceTier, GitHubTasksLimitsInputObject | null> = {
            CodeFallback: null,
            MjConfig: mjConfigLayer,
            Environment: envLayer,
            CallOverride: callLayer,
        };

        const provenanceEntries: Array<[GitHubTasksLimitKeyPath, GitHubTasksLimitProvenance]> = [];
        const overriddenKeys: GitHubTasksLimitKeyPath[] = [];
        const clampedKeys: GitHubTasksLimitKeyPath[] = [];

        for (const descriptor of GITHUB_TASKS_LIMIT_DESCRIPTORS) {
            let winningValue = descriptor.DefaultValue;
            let sourceTier: GitHubTasksLimitsSourceTier = 'CodeFallback';
            let rejectedCount = 0;

            for (const tier of GITHUB_TASKS_LIMITS_TIER_PRECEDENCE) {
                if (tier === 'CodeFallback') {
                    continue;
                }
                const candidate = extractOverrideCandidateForKey(layersByTier[tier], descriptor.Key);
                const parsed = parseDescriptorOverrideValue(candidate, descriptor);
                if (parsed.rejectedInvalid) {
                    rejectedCount += 1;
                }
                if (parsed.value !== undefined) {
                    winningValue = parsed.value;
                    sourceTier = tier;
                }
            }

            let wasClamped = false;
            if (descriptor.ProtocolCeiling !== undefined && winningValue > descriptor.ProtocolCeiling) {
                winningValue = descriptor.ProtocolCeiling;
                wasClamped = true;
            }
            if (descriptor.MaxKeyDependency !== undefined) {
                const ceilingVal = getKeyValueFromConfig(resolved, descriptor.MaxKeyDependency);
                if (winningValue > ceilingVal) {
                    winningValue = ceilingVal;
                    wasClamped = true;
                }
            }

            setKeyValueOnConfig(resolved, descriptor.Key, winningValue);

            const isOverridden = sourceTier !== 'CodeFallback';
            if (isOverridden) {
                overriddenKeys.push(descriptor.Key);
            }
            if (wasClamped) {
                clampedKeys.push(descriptor.Key);
            }

            provenanceEntries.push([
                descriptor.Key,
                {
                    Key: descriptor.Key,
                    Category: descriptor.Category,
                    Value: winningValue,
                    SourceTier: sourceTier,
                    IsOverridden: isOverridden,
                    WasClampedToCeiling: wasClamped,
                    RejectedInvalidOverrides: rejectedCount,
                },
            ]);
        }

        const coreMjLimits = this.ResolveCoreMjLimits(
            options.coreMjLimitsInput,
            options.coreMjLimitsOptions,
        );

        return {
            Limits: resolved,
            Provenance: Object.fromEntries(provenanceEntries) as Record<
                GitHubTasksLimitKeyPath,
                GitHubTasksLimitProvenance
            >,
            OverriddenKeys: overriddenKeys,
            ClampedKeys: clampedKeys,
            CoreMjLimits: coreMjLimits,
        };
    }
}

/**
 * Convenience helper returning the resolved {@link GitHubTasksLimitsConfig}.
 */
export function ResolveGitHubTasksLimits(
    options?: GitHubTasksLimitsResolveOptions,
): GitHubTasksLimitsConfig {
    return GitHubTasksLimitsResolver.GetLimits(options);
}
