import { createHmac, timingSafeEqual } from 'node:crypto';
import {
    IMetadataProvider,
    IRunViewProvider,
    Metadata,
    RunView,
    UserInfo,
} from '@memberjunction/core';
import { BaseSingleton } from '@memberjunction/global';
import type { mjBizAppsTasksGitHubGitHubRepositoryEntity } from '@mj-biz-apps/tasks-github-entities';
import { GITHUB_REPOSITORIES_ENTITY, GitHubTaskSyncService } from './GitHubTaskSyncService.js';
import { EscapeSqlLiteral } from './sql-safety.js';
import type {
    GitHubIssueStateReason,
    GitHubPullRequestReviewDecision,
    NormalizedGitHubIssueInput,
    NormalizedGitHubPullRequestInput,
    NormalizedGitHubSyncItem,
    SingleItemSyncResult,
} from './types.js';

export type SupportedGitHubWebhookEvent = 'issues' | 'pull_request' | 'pull_request_review';

interface WebhookUserPayload {
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

interface WebhookEnvelopePayload {
    action?: string;
    repository?: {
        name?: string;
        owner?: { login?: string } | null;
    } | null;
    issue?: WebhookIssuePayload | null;
    pull_request?: WebhookPullRequestPayload | null;
    review?: WebhookReviewPayload | null;
}

export interface HandleGitHubWebhookParams {
    eventName: string;
    deliveryId?: string | null;
    signatureHeader: string;
    rawPayload: string;
    webhookSecret: string;
    runInference?: boolean;
    contextUser: UserInfo;
    provider?: IMetadataProvider & IRunViewProvider;
}

export interface HandleGitHubWebhookResult {
    status: 'synced' | 'ignored' | 'invalid_signature' | 'validation_error';
    reason?: string;
    syncResult?: SingleItemSyncResult;
}

export class GitHubWebhookService extends BaseSingleton<GitHubWebhookService> {
    public constructor() {
        super();
    }

    public static get Instance(): GitHubWebhookService {
        return GitHubWebhookService.getInstance<GitHubWebhookService>();
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

        const cleanEvent = params.eventName.trim();
        if (cleanEvent !== 'issues' && cleanEvent !== 'pull_request' && cleanEvent !== 'pull_request_review') {
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
                    `Owner = '${EscapeSqlLiteral(owner)}' AND Name = '${EscapeSqlLiteral(repoName)}'`,
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
            return {
                status: 'ignored',
                reason: `Repository '${owner}/${repoName}' is not registered or not tracked`,
            };
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
            runInference: params.runInference !== false,
            provider: md as IMetadataProvider & IRunViewProvider,
        });

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

    private extractNormalizedItem(
        eventName: SupportedGitHubWebhookEvent,
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
                assigneeLogins: (issue.assignees ?? [])
                    .map((a) => a.login?.trim() ?? '')
                    .filter((l) => l.length > 0),
                updatedAt: issue.updated_at ?? null,
            };
            return normalized;
        }

        const pr = payload.pull_request;
        if (!pr || typeof pr.number !== 'number' || !pr.node_id || !pr.title || !pr.html_url) {
            return null;
        }

        let reviewDecision: GitHubPullRequestReviewDecision | null = null;
        if (eventName === 'pull_request_review') {
            const reviewState = (payload.review?.state ?? '').toLowerCase();
            if (reviewState === 'approved') {
                reviewDecision = 'APPROVED';
            } else if (reviewState === 'changes_requested') {
                reviewDecision = 'CHANGES_REQUESTED';
            }
        }

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
            assigneeLogins: (pr.assignees ?? [])
                .map((a) => a.login?.trim() ?? '')
                .filter((l) => l.length > 0),
            requestedReviewerLogins: (pr.requested_reviewers ?? [])
                .map((r) => r.login?.trim() ?? '')
                .filter((l) => l.length > 0),
            reviewDecision,
            changedFiles: pr.changed_files ?? null,
            additions: pr.additions ?? null,
            deletions: pr.deletions ?? null,
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
