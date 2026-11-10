import { createHmac, timingSafeEqual } from 'node:crypto';
import {
    IMetadataProvider,
    IRunViewProvider,
    LogError,
    Metadata,
    RunView,
    UserInfo,
} from '@memberjunction/core';
import { BaseSingleton, EscapeSQLString } from '@memberjunction/global';
import type { mjBizAppsTasksGitHubGitHubRepositoryEntity } from '@mj-biz-apps/tasks-github-entities';
import { GITHUB_REPOSITORIES_ENTITY, GitHubTaskSyncService } from './GitHubTaskSyncService.js';
import type {
    GitHubIssueStateReason,
    GitHubPullRequestChecksStatus,
    GitHubPullRequestReviewDecision,
    IGitHubLiveStateFetcher,
    NormalizedGitHubIssueInput,
    NormalizedGitHubPullRequestInput,
    NormalizedGitHubSyncItem,
    NormalizedGitHubUserRef,
    SingleItemSyncResult,
} from './types.js';

export type SupportedGitHubWebhookEvent =
    | 'issues'
    | 'pull_request'
    | 'pull_request_review'
    | 'check_suite'
    | 'check_run';

const MAX_TRACKED_DELIVERY_IDS = 5000;
const MAX_TRACKED_CHECK_SHAS = 5000;
const MAX_TRACKED_PR_REVIEWS = 5000;

interface GitHubRestCheckRunItem {
    id?: number;
    name?: string | null;
    status?: string | null;
    conclusion?: string | null;
}

interface GitHubRestCheckRunsResponse {
    total_count?: number;
    check_runs?: GitHubRestCheckRunItem[];
}

interface GitHubRestCombinedStatusResponse {
    state?: string | null;
    total_count?: number;
    statuses?: Array<{ context?: string | null; state?: string | null }>;
}

interface GitHubRestReviewItem {
    id?: number;
    state?: string | null;
    submitted_at?: string | null;
    user?: {
        id?: number | string;
        login?: string | null;
    } | null;
}

/**
 * Default GitHub REST implementation of `IGitHubLiveStateFetcher`.
 * When `GITHUB_TOKEN` or `GH_TOKEN` is configured on the server, webhook events for check runs,
 * check suites, and pull request reviews query GitHub's REST API directly for the authoritative
 * aggregate state on that commit or pull request — surviving MJAPI restarts and multi-instance
 * load balancing. When no token is configured, returns `null`/`undefined` so `GitHubWebhookService`
 * falls back to its bounded in-memory LRU state maps.
 */
export class DefaultGitHubRestLiveStateFetcher implements IGitHubLiveStateFetcher {
    public constructor(private readonly _explicitToken?: string) {}

    private getAuthToken(): string {
        if (this._explicitToken !== undefined) {
            return this._explicitToken.trim();
        }
        if (process.env.VITEST === 'true' || process.env.NODE_ENV === 'test') {
            return '';
        }
        return process.env.GITHUB_TOKEN?.trim() || process.env.GH_TOKEN?.trim() || '';
    }

    private buildHeaders(token: string): Record<string, string> {
        return {
            Accept: 'application/vnd.github+json',
            Authorization: `Bearer ${token}`,
            'X-GitHub-Api-Version': '2022-11-28',
            'User-Agent': 'MemberJunction-BizApps-Tasks-GitHub',
        };
    }

    public async FetchCommitChecksStatus(
        owner: string,
        repo: string,
        headSha: string,
    ): Promise<GitHubPullRequestChecksStatus | null> {
        const token = this.getAuthToken();
        if (!token) {
            return null;
        }
        const headers = this.buildHeaders(token);
        const encodedOwner = encodeURIComponent(owner);
        const encodedRepo = encodeURIComponent(repo);
        const encodedSha = encodeURIComponent(headSha);

        const latestRunByName = new Map<string, { id: number; status: GitHubPullRequestChecksStatus }>();
        for (let page = 1; page <= 10; page += 1) {
            const url = `https://api.github.com/repos/${encodedOwner}/${encodedRepo}/commits/${encodedSha}/check-runs?per_page=100&page=${page}`;
            const response = await fetch(url, { headers });
            if (!response.ok) {
                throw new Error(`GitHub REST GET ${url} failed with HTTP ${response.status}`);
            }
            const body = (await response.json()) as GitHubRestCheckRunsResponse;
            const runs = body.check_runs ?? [];
            for (const run of runs) {
                const nameKey = (run.name?.trim() || String(run.id ?? 'default')).toLowerCase();
                const runId = typeof run.id === 'number' ? run.id : 0;
                const existing = latestRunByName.get(nameKey);
                if (!existing || runId >= existing.id) {
                    latestRunByName.set(nameKey, {
                        id: runId,
                        status: this.mapCheckRunToStatus(run.status, run.conclusion),
                    });
                }
            }
            if (runs.length < 100) {
                break;
            }
        }

        const statusUrl = `https://api.github.com/repos/${encodedOwner}/${encodedRepo}/commits/${encodedSha}/status`;
        const statusRes = await fetch(statusUrl, { headers });
        if (!statusRes.ok) {
            throw new Error(`GitHub REST GET ${statusUrl} failed with HTTP ${statusRes.status}`);
        }
        const combinedStatus = (await statusRes.json()) as GitHubRestCombinedStatusResponse;

        const allStatuses: GitHubPullRequestChecksStatus[] = Array.from(latestRunByName.values()).map((r) => r.status);
        const commitStatusCount = combinedStatus.total_count ?? combinedStatus.statuses?.length ?? 0;
        if (commitStatusCount > 0) {
            const rawState = (combinedStatus.state ?? '').toLowerCase();
            if (rawState === 'failure' || rawState === 'error') {
                allStatuses.push('Failing');
            } else if (rawState === 'pending') {
                allStatuses.push('Pending');
            } else if (rawState === 'success') {
                allStatuses.push('Passing');
            }
        }

        if (allStatuses.some((s) => s === 'Failing')) {
            return 'Failing';
        }
        if (allStatuses.some((s) => s === 'Pending')) {
            return 'Pending';
        }
        if (allStatuses.some((s) => s === 'Passing')) {
            return 'Passing';
        }
        return 'Neutral';
    }

    public async FetchPullRequestReviewDecision(
        owner: string,
        repo: string,
        pullNumber: number,
        hasRequestedReviewers: boolean,
    ): Promise<GitHubPullRequestReviewDecision | null | undefined> {
        const token = this.getAuthToken();
        if (!token) {
            return undefined;
        }
        const headers = this.buildHeaders(token);
        const encodedOwner = encodeURIComponent(owner);
        const encodedRepo = encodeURIComponent(repo);

        const reviewerDecisions = new Map<string, 'APPROVED' | 'CHANGES_REQUESTED'>();
        for (let page = 1; page <= 10; page += 1) {
            const url = `https://api.github.com/repos/${encodedOwner}/${encodedRepo}/pulls/${pullNumber}/reviews?per_page=100&page=${page}`;
            const response = await fetch(url, { headers });
            if (!response.ok) {
                throw new Error(`GitHub REST GET ${url} failed with HTTP ${response.status}`);
            }
            const reviews = (await response.json()) as GitHubRestReviewItem[];
            for (const review of reviews) {
                const reviewerKey = (
                    review.user?.login?.trim()
                    || (review.user?.id != null ? String(review.user.id) : '')
                ).toLowerCase();
                if (!reviewerKey) {
                    continue;
                }
                const state = (review.state ?? '').toUpperCase();
                if (state === 'APPROVED') {
                    reviewerDecisions.set(reviewerKey, 'APPROVED');
                } else if (state === 'CHANGES_REQUESTED') {
                    reviewerDecisions.set(reviewerKey, 'CHANGES_REQUESTED');
                } else if (state === 'DISMISSED') {
                    reviewerDecisions.delete(reviewerKey);
                }
            }
            if (reviews.length < 100) {
                break;
            }
        }

        const decisions = Array.from(reviewerDecisions.values());
        if (decisions.some((d) => d === 'CHANGES_REQUESTED')) {
            return 'CHANGES_REQUESTED';
        }
        if (decisions.some((d) => d === 'APPROVED')) {
            return 'APPROVED';
        }
        return hasRequestedReviewers ? 'REVIEW_REQUIRED' : null;
    }

    private mapCheckRunToStatus(
        rawStatus: string | null | undefined,
        rawConclusion: string | null | undefined,
    ): GitHubPullRequestChecksStatus {
        const status = (rawStatus ?? '').toLowerCase();
        const conclusion = (rawConclusion ?? '').toLowerCase();
        if (status !== 'completed') {
            return 'Pending';
        }
        if (conclusion === 'success') {
            return 'Passing';
        }
        if (conclusion === 'neutral' || conclusion === 'skipped' || conclusion === 'stale') {
            return 'Neutral';
        }
        if (
            conclusion === 'failure'
            || conclusion === 'timed_out'
            || conclusion === 'cancelled'
            || conclusion === 'action_required'
            || conclusion === 'startup_failure'
        ) {
            return 'Failing';
        }
        return 'Neutral';
    }
}

interface WebhookUserPayload {
    id?: number | string;
    node_id?: string;
    login?: string;
}

interface WebhookLabelPayload {
    name?: string;
}

interface WebhookMilestonePayload {
    title?: string | null;
    due_on?: string | null;
}

interface WebhookIssuePayload {
    number?: number;
    node_id?: string;
    title?: string;
    body?: string | null;
    html_url?: string;
    state?: string;
    state_reason?: string | null;
    labels?: WebhookLabelPayload[];
    milestone?: WebhookMilestonePayload | null;
    user?: WebhookUserPayload | null;
    assignees?: WebhookUserPayload[];
    updated_at?: string | null;
}

interface WebhookPullRequestPayload {
    number?: number;
    node_id?: string;
    title?: string;
    body?: string | null;
    html_url?: string;
    state?: string;
    draft?: boolean;
    merged?: boolean;
    merged_at?: string | null;
    head?: { ref?: string; sha?: string } | null;
    base?: { ref?: string } | null;
    user?: WebhookUserPayload | null;
    assignees?: WebhookUserPayload[];
    requested_reviewers?: WebhookUserPayload[];
    changed_files?: number | null;
    additions?: number | null;
    deletions?: number | null;
    labels?: WebhookLabelPayload[];
    milestone?: WebhookMilestonePayload | null;
    updated_at?: string | null;
}

interface WebhookReviewPayload {
    state?: string;
    user?: WebhookUserPayload | null;
}

interface WebhookCheckPullRequestRef {
    number?: number;
    base?: {
        repo?: {
            full_name?: string;
            name?: string;
            owner?: { login?: string } | null;
        } | null;
    } | null;
}

interface WebhookCheckPayload {
    id?: number | string;
    name?: string | null;
    status?: string | null;
    conclusion?: string | null;
    head_sha?: string | null;
    app?: {
        id?: number | string;
        slug?: string | null;
    } | null;
    pull_requests?: WebhookCheckPullRequestRef[] | null;
}

interface WebhookEnvelopePayload {
    action?: string;
    repository?: {
        name?: string;
        owner?: { login?: string } | null;
    } | null;
    issue?: WebhookIssuePayload | null;
    pull_request?: WebhookPullRequestPayload | null;
    review?: WebhookReviewPayload | null;
    check_suite?: WebhookCheckPayload | null;
    check_run?: WebhookCheckPayload | null;
}

export interface HandleGitHubWebhookParams {
    eventName: string;
    deliveryId?: string | null;
    signatureHeader: string;
    rawPayload: string;
    webhookSecret: string;
    runInference?: boolean;
    queueInference?: boolean;
    contextUser: UserInfo;
    provider?: IMetadataProvider & IRunViewProvider;
}

export interface HandleGitHubWebhookResult {
    status: 'synced' | 'ignored' | 'invalid_signature' | 'validation_error';
    reason?: string;
    syncResult?: SingleItemSyncResult;
}

export class GitHubWebhookService extends BaseSingleton<GitHubWebhookService> {
    private readonly _processedDeliveries = new Set<string>();
    private readonly _checkStatesBySha = new Map<string, Map<string, GitHubPullRequestChecksStatus>>();
    private readonly _reviewStatesByPr = new Map<string, Map<string, 'APPROVED' | 'CHANGES_REQUESTED'>>();
    private _liveStateFetcher: IGitHubLiveStateFetcher = new DefaultGitHubRestLiveStateFetcher();

    public constructor() {
        super();
    }

    public static get Instance(): GitHubWebhookService {
        return GitHubWebhookService.getInstance<GitHubWebhookService>();
    }

    /**
     * Registers a custom `IGitHubLiveStateFetcher` for querying authoritative commit checks and PR reviews
     * (useful in unit tests or GitHub App installation token setups).
     */
    public SetLiveStateFetcher(fetcher: IGitHubLiveStateFetcher | null): void {
        this._liveStateFetcher = fetcher ?? new DefaultGitHubRestLiveStateFetcher();
    }

    /**
     * Resets the live state fetcher back to `DefaultGitHubRestLiveStateFetcher`.
     */
    public ClearLiveStateFetcher(): void {
        this._liveStateFetcher = new DefaultGitHubRestLiveStateFetcher();
    }

    /**
     * Clears the in-memory processed `X-GitHub-Delivery` set, bounded per-SHA/per-PR fallback maps,
     * and custom live state fetcher (primarily used by tests).
     */
    public ClearProcessedDeliveries(): void {
        this._processedDeliveries.clear();
        this._checkStatesBySha.clear();
        this._reviewStatesByPr.clear();
        this._liveStateFetcher = new DefaultGitHubRestLiveStateFetcher();
    }

    /**
     * Returns the current number of commit SHAs tracked in the bounded in-memory check-status fallback map.
     */
    public GetTrackedCheckShaCount(): number {
        return this._checkStatesBySha.size;
    }

    /**
     * Returns the current number of pull requests tracked in the bounded in-memory review-decision fallback map.
     */
    public GetTrackedPrReviewCount(): number {
        return this._reviewStatesByPr.size;
    }

    /**
     * Constant-time HMAC-SHA256 verification of `X-Hub-Signature-256` (`sha256=<hex>`).
     * Fails closed when secret, header, or raw payload is missing or mismatched.
     */
    public VerifySignature(rawPayload: string, signatureHeader: string, secret: string): boolean {
        if (!secret || !signatureHeader || !signatureHeader.startsWith('sha256=')) {
            return false;
        }
        const providedHex = signatureHeader.slice('sha256='.length).trim();
        if (!/^[0-9a-fA-F]{64}$/.test(providedHex)) {
            return false;
        }
        const expectedHex = createHmac('sha256', secret).update(rawPayload, 'utf8').digest('hex');
        const providedBuf = Buffer.from(providedHex.toLowerCase(), 'utf8');
        const expectedBuf = Buffer.from(expectedHex.toLowerCase(), 'utf8');
        if (providedBuf.length !== expectedBuf.length) {
            return false;
        }
        return timingSafeEqual(providedBuf, expectedBuf);
    }

    /**
     * Verifies and processes a single GitHub webhook delivery, immediately synchronizing the
     * affected issue or pull request into BizApps Tasks.
     *
     * Note: synchronous LLM inference is disabled by default inside webhook deliveries (`runInference: false`)
     * so webhook requests complete well within GitHub's 10-second delivery window. Callers can set
     * `queueInference: true` to debounce background inference for mapped contributors, or `runInference: true`
     * when synchronous inference is explicitly desired.
     */
    public async HandleWebhook(params: HandleGitHubWebhookParams): Promise<HandleGitHubWebhookResult> {
        if (!params.webhookSecret || params.webhookSecret.trim().length === 0) {
            return {
                status: 'invalid_signature',
                reason: 'Webhook secret is not configured; refusing unverified delivery (fail-closed)',
            };
        }

        if (!this.VerifySignature(params.rawPayload, params.signatureHeader, params.webhookSecret)) {
            return {
                status: 'invalid_signature',
                reason: 'X-Hub-Signature-256 HMAC-SHA256 verification failed',
            };
        }

        const cleanDeliveryId = params.deliveryId?.trim() ?? '';
        if (cleanDeliveryId.length > 0 && this._processedDeliveries.has(cleanDeliveryId)) {
            return {
                status: 'ignored',
                reason: `Duplicate delivery ID '${cleanDeliveryId}' already processed`,
            };
        }

        const cleanEvent = params.eventName.trim();
        if (
            cleanEvent !== 'issues'
            && cleanEvent !== 'pull_request'
            && cleanEvent !== 'pull_request_review'
            && cleanEvent !== 'check_suite'
            && cleanEvent !== 'check_run'
        ) {
            this.recordDeliveryId(cleanDeliveryId);
            return {
                status: 'ignored',
                reason: `Unsupported GitHub webhook event '${cleanEvent}'`,
            };
        }

        let parsed: WebhookEnvelopePayload;
        try {
            parsed = JSON.parse(params.rawPayload) as WebhookEnvelopePayload;
        } catch {
            return {
                status: 'validation_error',
                reason: 'Webhook payload is not valid JSON',
            };
        }

        const owner = parsed.repository?.owner?.login?.trim() ?? '';
        const repoName = parsed.repository?.name?.trim() ?? '';
        if (!owner || !repoName) {
            return {
                status: 'validation_error',
                reason: 'Webhook payload missing repository.owner.login or repository.name',
            };
        }

        const md = params.provider ?? Metadata.Provider;
        const rv = params.provider ? RunView.FromMetadataProvider(params.provider) : new RunView();

        const repoRes = await rv.RunView<mjBizAppsTasksGitHubGitHubRepositoryEntity>(
            {
                EntityName: GITHUB_REPOSITORIES_ENTITY,
                ExtraFilter:
                    `Owner = '${EscapeSQLString(owner)}' AND Name = '${EscapeSQLString(repoName)}'`,
                MaxRows: 1,
                ResultType: 'entity_object',
            },
            params.contextUser,
        );
        if (!repoRes.Success) {
            throw new Error(`Failed querying GitHubRepository for webhook '${owner}/${repoName}': ${repoRes.ErrorMessage}`);
        }

        const repository = repoRes.Results?.[0] ?? null;
        if (!repository || !repository.IsTracked) {
            this.recordDeliveryId(cleanDeliveryId);
            return {
                status: 'ignored',
                reason: `Repository '${owner}/${repoName}' is not registered or not tracked`,
            };
        }

        if (cleanEvent === 'check_suite' || cleanEvent === 'check_run') {
            return this.handleCheckEvent(cleanEvent, parsed, repository, cleanDeliveryId, params.contextUser, md as IMetadataProvider & IRunViewProvider);
        }

        const normalizedItem = await this.extractNormalizedItem(cleanEvent, parsed, repository);
        if (!normalizedItem) {
            return {
                status: 'validation_error',
                reason: `Webhook payload missing required ${cleanEvent} fields`,
            };
        }

        const syncResult = await GitHubTaskSyncService.Instance.SyncSingleItem({
            repository,
            item: normalizedItem,
            contextUser: params.contextUser,
            runInference: params.runInference === true,
            queueInference: params.queueInference === true,
            provider: md as IMetadataProvider & IRunViewProvider,
        });

        this.recordDeliveryId(cleanDeliveryId);

        if (syncResult.action === 'skipped') {
            return {
                status: 'ignored',
                reason: syncResult.reason ?? 'Item skipped by repository ImportRule',
                syncResult,
            };
        }

        return {
            status: 'synced',
            syncResult,
        };
    }

    private async handleCheckEvent(
        eventName: 'check_suite' | 'check_run',
        payload: WebhookEnvelopePayload,
        repository: mjBizAppsTasksGitHubGitHubRepositoryEntity,
        cleanDeliveryId: string,
        contextUser: UserInfo,
        provider: IMetadataProvider & IRunViewProvider,
    ): Promise<HandleGitHubWebhookResult> {
        const checkObj = eventName === 'check_suite' ? payload.check_suite : payload.check_run;
        if (!checkObj) {
            return {
                status: 'validation_error',
                reason: `Webhook payload missing required ${eventName} object`,
            };
        }

        const headSha = typeof checkObj.head_sha === 'string' ? checkObj.head_sha.trim() : '';
        if (!headSha) {
            return {
                status: 'validation_error',
                reason: `Webhook ${eventName} payload missing required head_sha`,
            };
        }

        const expectedFullName = `${repository.Owner}/${repository.Name}`.toLowerCase();
        const rawPrRefs = checkObj.pull_requests ?? [];
        const sameRepoPrNumbers: number[] = [];
        for (const p of rawPrRefs) {
            if (typeof p.number !== 'number' || !Number.isInteger(p.number) || p.number <= 0) {
                continue;
            }
            const baseRepo = p.base?.repo;
            if (baseRepo) {
                const fullName = (
                    baseRepo.full_name
                    ?? (baseRepo.owner?.login && baseRepo.name ? `${baseRepo.owner.login}/${baseRepo.name}` : '')
                ).trim().toLowerCase();
                if (fullName && fullName !== expectedFullName) {
                    continue;
                }
            }
            sameRepoPrNumbers.push(p.number);
        }

        if (rawPrRefs.length > 0 && sameRepoPrNumbers.length === 0) {
            this.recordDeliveryId(cleanDeliveryId);
            return {
                status: 'ignored',
                reason: 'Check event pull_requests belong to a different base repository',
            };
        }

        const status = (checkObj.status ?? '').toLowerCase();
        const conclusion = (checkObj.conclusion ?? '').toLowerCase();
        const action = (payload.action ?? '').toLowerCase();

        let singleCheckStatus: GitHubPullRequestChecksStatus = 'Pending';
        if (status === 'completed' || action === 'completed') {
            if (conclusion === 'success') {
                singleCheckStatus = 'Passing';
            } else if (conclusion === 'neutral' || conclusion === 'skipped' || conclusion === 'stale') {
                singleCheckStatus = 'Neutral';
            } else if (
                conclusion === 'failure'
                || conclusion === 'timed_out'
                || conclusion === 'cancelled'
                || conclusion === 'action_required'
                || conclusion === 'startup_failure'
            ) {
                singleCheckStatus = 'Failing';
            } else {
                singleCheckStatus = 'Neutral';
            }
        }

        const shaKey = `${expectedFullName}@${headSha}`;
        const checkMap = this.getOrCreateCheckMap(shaKey);
        const checkIdKey = eventName === 'check_run'
            ? `run:${(checkObj.name?.trim() || String(checkObj.id ?? 'default')).toLowerCase()}`
            : `suite:${String(checkObj.app?.id ?? checkObj.app?.slug ?? checkObj.id ?? 'default').toLowerCase()}`;
        checkMap.set(checkIdKey, singleCheckStatus);

        let aggregatedStatus: GitHubPullRequestChecksStatus | null = null;
        try {
            aggregatedStatus = await this._liveStateFetcher.FetchCommitChecksStatus(
                repository.Owner,
                repository.Name,
                headSha,
            );
        } catch (err) {
            LogError(
                `Failed fetching authoritative check runs from GitHub REST for '${repository.Owner}/${repository.Name}@${headSha}', falling back to bounded LRU check map: ${err instanceof Error ? err.message : String(err)}`,
            );
        }
        if (aggregatedStatus === null) {
            aggregatedStatus = this.aggregateCheckStatuses(checkMap);
        }

        const syncResult = await GitHubTaskSyncService.Instance.UpdatePullRequestChecksStatus({
            repository,
            prNumbers: sameRepoPrNumbers,
            headSha,
            checksStatus: aggregatedStatus,
            contextUser,
            provider,
        });

        this.recordDeliveryId(cleanDeliveryId);

        if (syncResult.action === 'skipped') {
            return {
                status: 'ignored',
                reason: syncResult.reason ?? 'No matching pull request for check event',
                syncResult,
            };
        }

        return {
            status: 'synced',
            syncResult,
        };
    }

    private getOrCreateCheckMap(shaKey: string): Map<string, GitHubPullRequestChecksStatus> {
        const existing = this._checkStatesBySha.get(shaKey);
        if (existing) {
            // Refresh LRU order
            this._checkStatesBySha.delete(shaKey);
            this._checkStatesBySha.set(shaKey, existing);
            return existing;
        }
        if (this._checkStatesBySha.size >= MAX_TRACKED_CHECK_SHAS) {
            const oldestKey = this._checkStatesBySha.keys().next().value;
            if (typeof oldestKey === 'string') {
                this._checkStatesBySha.delete(oldestKey);
            }
        }
        const created = new Map<string, GitHubPullRequestChecksStatus>();
        this._checkStatesBySha.set(shaKey, created);
        return created;
    }

    private getOrCreateReviewMap(prKey: string): Map<string, 'APPROVED' | 'CHANGES_REQUESTED'> {
        const existing = this._reviewStatesByPr.get(prKey);
        if (existing) {
            // Refresh LRU order
            this._reviewStatesByPr.delete(prKey);
            this._reviewStatesByPr.set(prKey, existing);
            return existing;
        }
        if (this._reviewStatesByPr.size >= MAX_TRACKED_PR_REVIEWS) {
            const oldestKey = this._reviewStatesByPr.keys().next().value;
            if (typeof oldestKey === 'string') {
                this._reviewStatesByPr.delete(oldestKey);
            }
        }
        const created = new Map<string, 'APPROVED' | 'CHANGES_REQUESTED'>();
        this._reviewStatesByPr.set(prKey, created);
        return created;
    }

    private aggregateCheckStatuses(
        checkMap: Map<string, GitHubPullRequestChecksStatus>,
    ): GitHubPullRequestChecksStatus {
        const statuses = Array.from(checkMap.values());
        if (statuses.some((s) => s === 'Failing')) {
            return 'Failing';
        }
        if (statuses.some((s) => s === 'Pending')) {
            return 'Pending';
        }
        if (statuses.some((s) => s === 'Passing')) {
            return 'Passing';
        }
        return 'Neutral';
    }

    private recordDeliveryId(deliveryId: string): void {
        if (!deliveryId) return;
        if (this._processedDeliveries.size >= MAX_TRACKED_DELIVERY_IDS) {
            const oldest = this._processedDeliveries.values().next().value;
            if (typeof oldest === 'string') {
                this._processedDeliveries.delete(oldest);
            }
        }
        this._processedDeliveries.add(deliveryId);
    }

    private extractUserRefs(users: WebhookUserPayload[] | undefined): NormalizedGitHubUserRef[] {
        const refs: NormalizedGitHubUserRef[] = [];
        for (const u of users ?? []) {
            const login = u.login?.trim() ?? '';
            if (!login) continue;
            const userId = u.id != null ? String(u.id) : (u.node_id?.trim() || null);
            refs.push({ login, userId });
        }
        return refs;
    }

    private async extractNormalizedItem(
        eventName: 'issues' | 'pull_request' | 'pull_request_review',
        payload: WebhookEnvelopePayload,
        repository: mjBizAppsTasksGitHubGitHubRepositoryEntity,
    ): Promise<NormalizedGitHubSyncItem | null> {
        if (eventName === 'issues') {
            const issue = payload.issue;
            if (!issue || typeof issue.number !== 'number' || !issue.node_id || !issue.title || !issue.html_url) {
                return null;
            }
            const rawReason = issue.state_reason ?? null;
            const validReason: GitHubIssueStateReason | null =
                rawReason === 'completed' || rawReason === 'not_planned' || rawReason === 'reopened' || rawReason === 'duplicate'
                    ? rawReason
                    : null;

            const assignees = this.extractUserRefs(issue.assignees);
            const authorUserId = issue.user?.id != null
                ? String(issue.user.id)
                : (issue.user?.node_id?.trim() || null);

            const normalized: NormalizedGitHubIssueInput = {
                kind: 'issue',
                number: issue.number,
                nodeId: issue.node_id,
                title: issue.title,
                body: issue.body ?? null,
                htmlUrl: issue.html_url,
                state: issue.state === 'closed' ? 'closed' : 'open',
                stateReason: validReason,
                labels: (issue.labels ?? [])
                    .map((l) => l.name?.trim() ?? '')
                    .filter((n) => n.length > 0),
                milestoneTitle: issue.milestone?.title ?? null,
                milestoneDueAt: issue.milestone?.due_on ?? null,
                authorLogin: issue.user?.login ?? null,
                authorUserId,
                assigneeLogins: assignees.map((a) => a.login),
                assignees,
                updatedAt: issue.updated_at ?? null,
            };
            return normalized;
        }

        const pr = payload.pull_request;
        if (!pr || typeof pr.number !== 'number' || !pr.node_id || !pr.title || !pr.html_url) {
            return null;
        }

        let reviewDecision: GitHubPullRequestReviewDecision | null | undefined = undefined;
        if (eventName === 'pull_request_review') {
            const reviewState = (payload.review?.state ?? '').toLowerCase();
            const repoFullName = `${repository.Owner}/${repository.Name}`.toLowerCase();
            const prKey = `${repoFullName}#${pr.number}`;
            const reviewerKey = (
                payload.review?.user?.login?.trim()
                || (payload.review?.user?.id != null ? String(payload.review.user.id) : '')
                || 'default'
            ).toLowerCase();

            const reviewerMap = this.getOrCreateReviewMap(prKey);

            if (reviewState === 'approved') {
                reviewerMap.set(reviewerKey, 'APPROVED');
            } else if (reviewState === 'changes_requested') {
                reviewerMap.set(reviewerKey, 'CHANGES_REQUESTED');
            } else if (reviewState === 'dismissed') {
                reviewerMap.delete(reviewerKey);
            }

            if (reviewState === 'approved' || reviewState === 'changes_requested' || reviewState === 'dismissed') {
                const hasRemainingReviewers = (pr.requested_reviewers?.length ?? 0) > 0;
                let liveDecision: GitHubPullRequestReviewDecision | null | undefined = undefined;
                try {
                    liveDecision = await this._liveStateFetcher.FetchPullRequestReviewDecision(
                        repository.Owner,
                        repository.Name,
                        pr.number,
                        hasRemainingReviewers,
                    );
                } catch (err) {
                    LogError(
                        `Failed fetching authoritative PR reviews from GitHub REST for '${repository.Owner}/${repository.Name}#${pr.number}', falling back to bounded LRU review map: ${err instanceof Error ? err.message : String(err)}`,
                    );
                }

                if (liveDecision !== undefined) {
                    reviewDecision = liveDecision;
                } else {
                    const decisions = Array.from(reviewerMap.values());
                    if (decisions.some((d) => d === 'CHANGES_REQUESTED')) {
                        reviewDecision = 'CHANGES_REQUESTED';
                    } else if (decisions.some((d) => d === 'APPROVED')) {
                        reviewDecision = 'APPROVED';
                    } else {
                        reviewDecision = hasRemainingReviewers ? 'REVIEW_REQUIRED' : null;
                    }
                }
            }
            // Note: `commented` reviews do not alter aggregate reviewDecision (`undefined` preserves stored decision)
        }

        let checksStatus: GitHubPullRequestChecksStatus | null | undefined = undefined;
        if (eventName === 'pull_request' && payload.action === 'synchronize') {
            checksStatus = 'Pending';
        }

        const assignees = this.extractUserRefs(pr.assignees);
        const requestedReviewers = this.extractUserRefs(pr.requested_reviewers);
        const authorUserId = pr.user?.id != null
            ? String(pr.user.id)
            : (pr.user?.node_id?.trim() || null);

        const linkedIssueNumber = this.extractClosingIssueNumber(pr.body ?? '');

        const normalizedPr: NormalizedGitHubPullRequestInput = {
            kind: 'pull_request',
            number: pr.number,
            nodeId: pr.node_id,
            title: pr.title,
            body: pr.body ?? null,
            htmlUrl: pr.html_url,
            state: pr.merged || pr.merged_at ? 'merged' : (pr.state === 'closed' ? 'closed' : 'open'),
            isDraft: Boolean(pr.draft),
            headBranch: pr.head?.ref ?? null,
            headSha: pr.head?.sha ?? null,
            baseBranch: pr.base?.ref ?? null,
            authorLogin: pr.user?.login ?? null,
            authorUserId,
            assigneeLogins: assignees.map((a) => a.login),
            assignees,
            requestedReviewerLogins: requestedReviewers.map((r) => r.login),
            requestedReviewers,
            reviewDecision,
            checksStatus,
            changedFiles: typeof pr.changed_files === 'number' ? pr.changed_files : undefined,
            additions: typeof pr.additions === 'number' ? pr.additions : undefined,
            deletions: typeof pr.deletions === 'number' ? pr.deletions : undefined,
            labels: (pr.labels ?? [])
                .map((l) => l.name?.trim() ?? '')
                .filter((n) => n.length > 0),
            milestoneTitle: pr.milestone?.title ?? null,
            milestoneDueAt: pr.milestone?.due_on ?? null,
            mergedAt: pr.merged_at ?? null,
            linkedIssueNumber,
            updatedAt: pr.updated_at ?? null,
        };
        return normalizedPr;
    }

    private extractClosingIssueNumber(body: string): number | null {
        const match = /\b(?:close[sd]?|fix(?:e[sd])?|resolve[sd]?)\s+#(\d+)\b/i.exec(body);
        if (!match) return null;
        const parsed = Number.parseInt(match[1], 10);
        return Number.isFinite(parsed) && parsed > 0 ? parsed : null;
    }
}
