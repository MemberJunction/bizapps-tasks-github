import { createHmac, timingSafeEqual } from 'node:crypto';
import {
    IMetadataProvider,
    IRunViewProvider,
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
}

interface WebhookCheckPullRequestRef {
    number?: number;
}

interface WebhookCheckPayload {
    status?: string | null;
    conclusion?: string | null;
    head_sha?: string | null;
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

    public constructor() {
        super();
    }

    public static get Instance(): GitHubWebhookService {
        return GitHubWebhookService.getInstance<GitHubWebhookService>();
    }

    /**
     * Clears the in-memory processed `X-GitHub-Delivery` set (primarily used by tests).
     */
    public ClearProcessedDeliveries(): void {
        this._processedDeliveries.clear();
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

        const normalizedItem = this.extractNormalizedItem(cleanEvent, parsed);
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

        const status = (checkObj.status ?? '').toLowerCase();
        const conclusion = (checkObj.conclusion ?? '').toLowerCase();
        const action = (payload.action ?? '').toLowerCase();

        let checksStatus: GitHubPullRequestChecksStatus = 'Pending';
        if (status === 'completed' || action === 'completed') {
            if (conclusion === 'success') {
                checksStatus = 'Passing';
            } else if (conclusion === 'neutral' || conclusion === 'skipped') {
                checksStatus = 'Neutral';
            } else if (
                conclusion === 'failure'
                || conclusion === 'timed_out'
                || conclusion === 'cancelled'
                || conclusion === 'action_required'
                || conclusion === 'startup_failure'
                || conclusion === 'stale'
            ) {
                checksStatus = 'Failing';
            }
        }

        const prNumbers = (checkObj.pull_requests ?? [])
            .map((p) => p.number)
            .filter((n): n is number => typeof n === 'number' && Number.isInteger(n) && n > 0);
        const headSha = typeof checkObj.head_sha === 'string' ? checkObj.head_sha : null;

        const syncResult = await GitHubTaskSyncService.Instance.UpdatePullRequestChecksStatus({
            repository,
            prNumbers,
            headSha,
            checksStatus,
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

    private extractNormalizedItem(
        eventName: 'issues' | 'pull_request' | 'pull_request_review',
        payload: WebhookEnvelopePayload,
    ): NormalizedGitHubSyncItem | null {
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
            if (reviewState === 'approved') {
                reviewDecision = 'APPROVED';
            } else if (reviewState === 'changes_requested') {
                reviewDecision = 'CHANGES_REQUESTED';
            } else if (reviewState === 'dismissed') {
                const hasRemainingReviewers = (pr.requested_reviewers?.length ?? 0) > 0;
                reviewDecision = hasRemainingReviewers ? 'REVIEW_REQUIRED' : null;
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
