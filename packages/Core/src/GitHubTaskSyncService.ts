import {
    IMetadataProvider,
    IRunViewProvider,
    LogError,
    Metadata,
    RunView,
    UserInfo,
} from '@memberjunction/core';
import { BaseSingleton, EscapeSQLString, UUIDsEqual } from '@memberjunction/global';
import type {
    mjBizAppsTasksTaskAssignmentEntity,
    mjBizAppsTasksTaskEntity,
    mjBizAppsTasksTaskRoleEntity,
    mjBizAppsTasksTaskTypeEntity,
    mjBizAppsTasksTaskTypeStatusEntity,
} from '@mj-biz-apps/tasks-entities';
import type {
    mjBizAppsTasksGitHubGitHubIdentityEntity,
    mjBizAppsTasksGitHubGitHubIssueTaskEntity,
    mjBizAppsTasksGitHubGitHubPullRequestTaskEntity,
    mjBizAppsTasksGitHubGitHubRepositoryEntity,
} from '@mj-biz-apps/tasks-github-entities';
import { GitHubFieldOwnershipPolicy } from './GitHubFieldOwnershipPolicy.js';
import { GitHubTaskInferenceService, TASKS_ENTITY_NAME } from './GitHubTaskInferenceService.js';
import { AssertValidUUID } from './sql-safety.js';
import type {
    GitHubIssueStateReason,
    GitHubPullRequestChecksStatus,
    IGitHubRepositoryFetcher,
    NormalizedGitHubIssueInput,
    NormalizedGitHubPullRequestInput,
    NormalizedGitHubSyncItem,
    NormalizedGitHubUserRef,
    RepositorySyncSummary,
    SingleItemSyncResult,
} from './types.js';

export const GITHUB_REPOSITORIES_ENTITY = 'MJ_BizApps_Tasks_GitHub: Git Hub Repositories';
export const GITHUB_IDENTITIES_ENTITY = 'MJ_BizApps_Tasks_GitHub: Git Hub Identities';
export const GITHUB_ISSUE_TASKS_ENTITY = 'MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks';
export const GITHUB_PR_TASKS_ENTITY = 'MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks';
export const TASK_TYPES_ENTITY = 'MJ_BizApps_Tasks: Task Types';
export const TASK_TYPE_STATUS_ENTITY = 'MJ_BizApps_Tasks: Task Type Status';
export const TASK_ASSIGNMENTS_ENTITY = 'MJ_BizApps_Tasks: Task Assignments';
export const TASK_ROLES_ENTITY = 'MJ_BizApps_Tasks: Task Roles';
export const PEOPLE_ENTITY = 'MJ_BizApps_Common: People';

const GITHUB_ASSIGNMENT_NOTE_PREFIX = 'Synced from GitHub (@';

interface SyncReferenceContext {
    tasksEntityId: string;
    peopleEntityId: string;
    issueTaskTypeId: string;
    prTaskTypeId: string;
    issueStatusesByCode: Map<string, string>;
    prStatusesByCode: Map<string, string>;
    primaryRoleId: string;
    reviewerRoleId: string;
    personIdByUserId: Map<string, { login: string; personId: string }>;
    identityByLowerLogin: Map<string, { personId: string; userId: string | null }>;
}

interface PreloadedRepoExtensions {
    issuesByNumber: Map<number, mjBizAppsTasksGitHubGitHubIssueTaskEntity>;
    issuesByNodeId: Map<string, mjBizAppsTasksGitHubGitHubIssueTaskEntity>;
    prsByNumber: Map<number, mjBizAppsTasksGitHubGitHubPullRequestTaskEntity>;
    prsByNodeId: Map<string, mjBizAppsTasksGitHubGitHubPullRequestTaskEntity>;
}

interface GitHubRestUserJson {
    id?: number | string;
    node_id?: string;
    login?: string;
}

interface GitHubRestLabelJson {
    name?: string;
}

interface GitHubRestMilestoneJson {
    title?: string | null;
    due_on?: string | null;
}

interface GitHubRestIssueJson {
    number?: number;
    node_id?: string;
    title?: string;
    body?: string | null;
    html_url?: string;
    state?: string;
    state_reason?: string | null;
    labels?: GitHubRestLabelJson[];
    milestone?: GitHubRestMilestoneJson | null;
    user?: GitHubRestUserJson | null;
    assignees?: GitHubRestUserJson[];
    updated_at?: string | null;
    pull_request?: Record<string, string | null>;
}

interface GitHubRestPullRequestJson {
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
    user?: GitHubRestUserJson | null;
    assignees?: GitHubRestUserJson[];
    requested_reviewers?: GitHubRestUserJson[];
    changed_files?: number | null;
    additions?: number | null;
    deletions?: number | null;
    labels?: GitHubRestLabelJson[];
    milestone?: GitHubRestMilestoneJson | null;
    updated_at?: string | null;
}

/**
 * Default GitHub REST API fetcher used when `GITHUB_TOKEN` (or `GH_TOKEN`) is configured on the host
 * and no custom `IGitHubRepositoryFetcher` has been registered.
 */
export class DefaultGitHubRestRepositoryFetcher implements IGitHubRepositoryFetcher {
    private static readonly MAX_PAGES = 20;
    private static readonly PAGE_SIZE = 100;

    public async FetchRepositoryItems(
        owner: string,
        name: string,
    ): Promise<NormalizedGitHubSyncItem[]> {
        const token = (process.env.GITHUB_TOKEN ?? process.env.GH_TOKEN ?? '').trim();
        if (!token) {
            throw new Error(
                `GITHUB_TOKEN (or GH_TOKEN) is not configured; cannot fetch repository items for '${owner}/${name}' without a GitHub token or custom IGitHubRepositoryFetcher.`,
            );
        }
        const headers: Record<string, string> = {
            Accept: 'application/vnd.github+json',
            Authorization: `Bearer ${token}`,
            'X-GitHub-Api-Version': '2022-11-28',
        };
        const baseUrl = `https://api.github.com/repos/${encodeURIComponent(owner)}/${encodeURIComponent(name)}`;
        const [rawIssues, rawPulls] = await Promise.all([
            this.fetchPaginated<GitHubRestIssueJson>(`${baseUrl}/issues`, headers, `${owner}/${name} issues`),
            this.fetchPaginated<GitHubRestPullRequestJson>(`${baseUrl}/pulls`, headers, `${owner}/${name} pull requests`),
        ]);
        const normalized: NormalizedGitHubSyncItem[] = [];

        for (const issue of rawIssues) {
            // GitHub's /issues endpoint also returns PRs; skip entries with a `pull_request` key
            if (issue.pull_request != null) continue;
            if (typeof issue.number !== 'number' || !issue.node_id || !issue.title || !issue.html_url) continue;
            const rawReason = issue.state_reason ?? null;
            const validReason: GitHubIssueStateReason | null =
                rawReason === 'completed' || rawReason === 'not_planned' || rawReason === 'reopened' || rawReason === 'duplicate'
                    ? rawReason
                    : null;
            const assignees: NormalizedGitHubUserRef[] = (issue.assignees ?? [])
                .filter((a) => typeof a.login === 'string' && a.login.trim().length > 0)
                .map((a) => ({
                    login: (a.login ?? '').trim(),
                    userId: a.id != null ? String(a.id) : (a.node_id ?? null),
                }));
            normalized.push({
                kind: 'issue',
                number: issue.number,
                nodeId: issue.node_id,
                title: issue.title,
                body: issue.body ?? null,
                htmlUrl: issue.html_url,
                state: issue.state === 'closed' ? 'closed' : 'open',
                stateReason: validReason,
                labels: (issue.labels ?? []).map((l) => l.name?.trim() ?? '').filter((n) => n.length > 0),
                milestoneTitle: issue.milestone?.title ?? null,
                milestoneDueAt: issue.milestone?.due_on ?? null,
                authorLogin: issue.user?.login ?? null,
                authorUserId: issue.user?.id != null ? String(issue.user.id) : (issue.user?.node_id ?? null),
                assigneeLogins: assignees.map((a) => a.login),
                assignees,
                updatedAt: issue.updated_at ?? null,
            });
        }

        for (const pr of rawPulls) {
            if (typeof pr.number !== 'number' || !pr.node_id || !pr.title || !pr.html_url) continue;
            const assignees: NormalizedGitHubUserRef[] = (pr.assignees ?? [])
                .filter((a) => typeof a.login === 'string' && a.login.trim().length > 0)
                .map((a) => ({
                    login: (a.login ?? '').trim(),
                    userId: a.id != null ? String(a.id) : (a.node_id ?? null),
                }));
            const requestedReviewers: NormalizedGitHubUserRef[] = (pr.requested_reviewers ?? [])
                .filter((r) => typeof r.login === 'string' && r.login.trim().length > 0)
                .map((r) => ({
                    login: (r.login ?? '').trim(),
                    userId: r.id != null ? String(r.id) : (r.node_id ?? null),
                }));
            normalized.push({
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
                authorUserId: pr.user?.id != null ? String(pr.user.id) : (pr.user?.node_id ?? null),
                assigneeLogins: assignees.map((a) => a.login),
                assignees,
                requestedReviewerLogins: requestedReviewers.map((r) => r.login),
                requestedReviewers,
                changedFiles: typeof pr.changed_files === 'number' ? pr.changed_files : undefined,
                additions: typeof pr.additions === 'number' ? pr.additions : undefined,
                deletions: typeof pr.deletions === 'number' ? pr.deletions : undefined,
                labels: (pr.labels ?? []).map((l) => l.name?.trim() ?? '').filter((n) => n.length > 0),
                milestoneTitle: pr.milestone?.title ?? null,
                milestoneDueAt: pr.milestone?.due_on ?? null,
                mergedAt: pr.merged_at ?? null,
                updatedAt: pr.updated_at ?? null,
            });
        }

        return normalized;
    }

    private async fetchPaginated<T>(
        endpointUrl: string,
        headers: Record<string, string>,
        label: string,
    ): Promise<T[]> {
        const collected: T[] = [];
        for (let page = 1; page <= DefaultGitHubRestRepositoryFetcher.MAX_PAGES; page += 1) {
            const url = `${endpointUrl}?state=all&per_page=${DefaultGitHubRestRepositoryFetcher.PAGE_SIZE}&page=${page}`;
            const res = await fetch(url, { headers });
            if (!res.ok) {
                throw new Error(`GitHub REST API error fetching ${label} (page ${page}): HTTP ${res.status}`);
            }
            const batch = (await res.json()) as T[];
            if (!Array.isArray(batch) || batch.length === 0) {
                break;
            }
            collected.push(...batch);
            if (batch.length < DefaultGitHubRestRepositoryFetcher.PAGE_SIZE) {
                break;
            }
            if (page === DefaultGitHubRestRepositoryFetcher.MAX_PAGES) {
                LogError(
                    `[DefaultGitHubRestRepositoryFetcher] Pagination for ${label} reached the ${DefaultGitHubRestRepositoryFetcher.MAX_PAGES}-page cap (${collected.length} items); additional items were truncated.`,
                );
            }
        }
        return collected;
    }
}

export interface SyncSingleItemOptions {
    repository: mjBizAppsTasksGitHubGitHubRepositoryEntity;
    item: NormalizedGitHubSyncItem;
    contextUser: UserInfo;
    runInference?: boolean;
    queueInference?: boolean;
    provider?: IMetadataProvider & IRunViewProvider;
}

export interface SyncRepositoryOptions {
    repositoryId?: string | null;
    items?: NormalizedGitHubSyncItem[];
    runInference?: boolean;
    contextUser: UserInfo;
    provider?: IMetadataProvider & IRunViewProvider;
}

export class GitHubTaskSyncService extends BaseSingleton<GitHubTaskSyncService> {
    private _fetcher: IGitHubRepositoryFetcher | null = null;
    private readonly _defaultFetcher = new DefaultGitHubRestRepositoryFetcher();
    private readonly _itemLocks = new Map<string, Promise<void>>();

    public constructor() {
        super();
    }

    public static get Instance(): GitHubTaskSyncService {
        return GitHubTaskSyncService.getInstance<GitHubTaskSyncService>();
    }

    public SetRepositoryFetcher(fetcher: IGitHubRepositoryFetcher): void {
        this._fetcher = fetcher;
    }

    public ClearRepositoryFetcher(): void {
        this._fetcher = null;
    }

    /**
     * Synchronizes one tracked repository (or all tracked repositories when `repositoryId` is omitted).
     */
    public async SyncRepositories(options: SyncRepositoryOptions): Promise<RepositorySyncSummary[]> {
        const md = options.provider ?? Metadata.Provider;
        const rv = options.provider ? RunView.FromMetadataProvider(options.provider) : new RunView();

        const extraFilter = options.repositoryId
            ? `ID = '${AssertValidUUID(options.repositoryId, 'repositoryId')}'`
            : `IsTracked = 1`;

        const repoRes = await rv.RunView<mjBizAppsTasksGitHubGitHubRepositoryEntity>(
            {
                EntityName: GITHUB_REPOSITORIES_ENTITY,
                ExtraFilter: extraFilter,
                ResultType: 'entity_object',
            },
            options.contextUser,
        );

        if (!repoRes.Success) {
            throw new Error(`Failed loading GitHub repositories: ${repoRes.ErrorMessage}`);
        }

        const repos = repoRes.Results ?? [];
        if (options.repositoryId && repos.length === 0) {
            throw new Error(`GitHubRepository '${options.repositoryId}' not found`);
        }

        const refContext = await this.loadReferenceContext(md, rv, options.contextUser);
        const summaries: RepositorySyncSummary[] = [];

        for (const repo of repos) {
            if (!repo.IsTracked) {
                summaries.push({
                    repositoryId: repo.ID,
                    repositoryFullName: `${repo.Owner}/${repo.Name}`,
                    created: 0,
                    updated: 0,
                    skipped: 0,
                    supersededDueAtSuggestions: 0,
                    inferredSuggestionsCreated: 0,
                    taskIds: [],
                });
                continue;
            }

            const activeFetcher = this._fetcher ?? this._defaultFetcher;
            const items = options.items
                ?? (await activeFetcher.FetchRepositoryItems(repo.Owner, repo.Name, options.contextUser, md));

            const summary: RepositorySyncSummary = {
                repositoryId: repo.ID,
                repositoryFullName: `${repo.Owner}/${repo.Name}`,
                created: 0,
                updated: 0,
                skipped: 0,
                supersededDueAtSuggestions: 0,
                inferredSuggestionsCreated: 0,
                taskIds: [],
            };

            const preloaded = items.length > 0
                ? await this.preloadRepositoryExtensions(repo.ID, rv, options.contextUser)
                : undefined;

            for (const item of items) {
                const res = await this.syncSingleItemWithContext(
                    repo,
                    item,
                    refContext,
                    options.contextUser,
                    options.runInference !== false,
                    false,
                    md,
                    rv,
                    preloaded,
                );
                if (res.action === 'created') {
                    summary.created += 1;
                } else if (res.action === 'updated') {
                    summary.updated += 1;
                } else {
                    summary.skipped += 1;
                }
                summary.supersededDueAtSuggestions += res.supersededDueAtSuggestions ?? 0;
                summary.inferredSuggestionsCreated += res.inferredSuggestionsCreated ?? 0;
                if (res.taskId) {
                    summary.taskIds.push(res.taskId);
                }
            }

            summaries.push(summary);
        }

        return summaries;
    }

    /**
     * Immediately synchronizes a single GitHub issue or pull request (used by webhook deliveries).
     */
    public async SyncSingleItem(options: SyncSingleItemOptions): Promise<SingleItemSyncResult> {
        const md = options.provider ?? Metadata.Provider;
        const rv = options.provider ? RunView.FromMetadataProvider(options.provider) : new RunView();
        const refContext = await this.loadReferenceContext(md, rv, options.contextUser);
        return this.syncSingleItemWithContext(
            options.repository,
            options.item,
            refContext,
            options.contextUser,
            options.runInference === true,
            options.queueInference === true,
            md,
            rv,
        );
    }

    private async syncSingleItemWithContext(
        repository: mjBizAppsTasksGitHubGitHubRepositoryEntity,
        item: NormalizedGitHubSyncItem,
        refContext: SyncReferenceContext,
        contextUser: UserInfo,
        runInference: boolean,
        queueInference: boolean,
        md: IMetadataProvider,
        rv: RunView,
        preloaded?: PreloadedRepoExtensions,
    ): Promise<SingleItemSyncResult> {
        if (!repository.IsTracked) {
            return { action: 'skipped', reason: 'Repository is not tracked' };
        }

        const validation = GitHubFieldOwnershipPolicy.ValidateNormalizedGitHubSyncItem(
            item,
            `${repository.Owner}/${repository.Name}`,
        );
        if (!validation.valid || !validation.item) {
            throw new Error(validation.error ?? 'Invalid NormalizedGitHubSyncItem');
        }
        const validItem = validation.item;
        const lockKey = `${repository.ID.toLowerCase()}:${validItem.kind}:${validItem.number}`;

        return this.runWithItemLock(lockKey, async () => {
            if (validItem.kind === 'issue') {
                return this.syncIssueItem(
                    repository,
                    validItem,
                    refContext,
                    contextUser,
                    runInference,
                    queueInference,
                    md,
                    rv,
                    preloaded,
                );
            }
            return this.syncPullRequestItem(
                repository,
                validItem,
                refContext,
                contextUser,
                runInference,
                queueInference,
                md,
                rv,
                preloaded,
            );
        });
    }

    private async runWithItemLock<T>(key: string, fn: () => Promise<T>): Promise<T> {
        const previous = this._itemLocks.get(key) ?? Promise.resolve();
        let release!: () => void;
        const current = new Promise<void>((resolve) => {
            release = resolve;
        });
        const chained = previous.then(() => current);
        this._itemLocks.set(key, chained);
        await previous;
        try {
            return await fn();
        } finally {
            release();
            if (this._itemLocks.get(key) === chained) {
                this._itemLocks.delete(key);
            }
        }
    }

    private async syncIssueItem(
        repository: mjBizAppsTasksGitHubGitHubRepositoryEntity,
        issue: NormalizedGitHubIssueInput,
        refContext: SyncReferenceContext,
        contextUser: UserInfo,
        runInference: boolean,
        queueInference: boolean,
        md: IMetadataProvider,
        rv: RunView,
        preloaded?: PreloadedRepoExtensions,
        isRetryAfterCollision = false,
    ): Promise<SingleItemSyncResult> {
        const existingExt =
            (!isRetryAfterCollision ? this.findPreloadedIssueExtension(preloaded, issue.number, issue.nodeId) : null)
            ?? (await this.findExistingIssueExtension(repository.ID, issue.number, issue.nodeId, rv, contextUser));

        const incomingUpdatedAt = this.parseOptionalDate(issue.updatedAt);
        const existingUpdatedAt = this.parseOptionalDate(existingExt?.GitHubUpdatedAt);
        if (
            existingExt
            && incomingUpdatedAt != null
            && existingUpdatedAt != null
            && incomingUpdatedAt.getTime() < existingUpdatedAt.getTime()
        ) {
            return {
                action: 'skipped',
                reason: 'Stale payload older than stored GitHubUpdatedAt',
                taskId: existingExt.ID,
            };
        }

        const mappedPrimaryPeople = this.resolveMappedPeople(
            issue.assignees ?? [],
            issue.assigneeLogins ?? [],
            refContext,
        );

        if (
            existingExt
            && incomingUpdatedAt != null
            && existingUpdatedAt != null
            && incomingUpdatedAt.getTime() === existingUpdatedAt.getTime()
        ) {
            const unchanged = await this.isIssueContentUnchanged(
                existingExt,
                issue,
                mappedPrimaryPeople,
                refContext,
                rv,
                contextUser,
            );
            if (unchanged) {
                return {
                    action: 'skipped',
                    reason: 'Unchanged content at equal GitHubUpdatedAt',
                    taskId: existingExt.ID,
                };
            }
        }

        if (!existingExt && repository.ImportRule === 'AssignedOnly' && mappedPrimaryPeople.length === 0) {
            return {
                action: 'skipped',
                reason: 'Filtered out by ImportRule=AssignedOnly (no mapped GitHubIdentity assignee)',
            };
        }

        const isNew = existingExt == null;
        const task = await md.GetEntityObject<mjBizAppsTasksTaskEntity>(TASKS_ENTITY_NAME, contextUser);
        if (isNew) {
            task.NewRecord();
            task.TypeID = refContext.issueTaskTypeId;
            task.Priority = 'Medium';
        } else {
            const loaded = await task.Load(existingExt.ID);
            if (!loaded) {
                throw new Error(`Failed loading base Task '${existingExt.ID}' for GitHub issue #${issue.number}`);
            }
        }

        const typeStatusCode = GitHubFieldOwnershipPolicy.MapIssueTypeStatusCode(issue);
        const preservedFactoryStatus = !isNew
            && issue.state === 'open'
            && this.isReadyForFactoryStatus(task.TaskTypeStatusID, refContext.issueStatusesByCode);

        const effectiveStatusCode = preservedFactoryStatus ? 'READY_FOR_FACTORY' : typeStatusCode;
        const typeStatusId = refContext.issueStatusesByCode.get(effectiveStatusCode) ?? null;
        const coreStatus = GitHubFieldOwnershipPolicy.MapTypeStatusCodeToCoreStatus(effectiveStatusCode);

        // Pull-only GitHub-owned fields; Tasks-owned planning fields (Priority, DueAt, HoursEstimated, ParentID, CategoryID) are NEVER overwritten!
        task.Name = issue.title;
        task.Description = issue.body ?? null;
        task.Status = coreStatus;
        task.TaskTypeStatusID = typeStatusId;
        if (coreStatus === 'Completed' && !task.CompletedAt) {
            task.CompletedAt = new Date();
        } else if (coreStatus !== 'Completed' && coreStatus !== 'Cancelled') {
            task.CompletedAt = null;
        }

        const taskSaved = await task.Save();
        if (!taskSaved) {
            throw new Error(`Failed saving Task for GitHub issue #${issue.number}: ${task.LatestResult?.CompleteMessage ?? 'save failed'}`);
        }

        // Load the IS-A child row (auto-provisioned on save by Tasks SubtypeSelector AutoEnsureOnSave: true)
        const issueExt = await md.GetEntityObject<mjBizAppsTasksGitHubGitHubIssueTaskEntity>(
            GITHUB_ISSUE_TASKS_ENTITY,
            contextUser,
        );
        const extLoaded = await issueExt.Load(task.ID);
        if (!extLoaded) {
            issueExt.NewRecord();
            issueExt.ID = task.ID;
        }

        const newBodyHash = GitHubFieldOwnershipPolicy.ComputeBodyHash(issue.title, issue.body);
        const previousBodyHash = issueExt.BodyHash;
        const bodyChanged = isNew || previousBodyHash !== newBodyHash;
        const milestoneDate = this.parseOptionalDate(issue.milestoneDueAt);

        issueExt.RepositoryID = repository.ID;
        issueExt.Number = issue.number;
        issueExt.NodeID = issue.nodeId;
        issueExt.HtmlURL = issue.htmlUrl;
        issueExt.State = issue.state;
        issueExt.StateReason = issue.stateReason ?? null;
        issueExt.Labels = issue.labels ? JSON.stringify(issue.labels) : null;
        issueExt.Milestone = issue.milestoneTitle ?? null;
        issueExt.MilestoneDueAt = milestoneDate;
        issueExt.AuthorLogin = issue.authorLogin ?? null;
        issueExt.BodyHash = newBodyHash;
        issueExt.GitHubUpdatedAt = incomingUpdatedAt ?? existingUpdatedAt;
        issueExt.LastSyncedAt = new Date();

        const extSaved = await issueExt.Save();
        if (!extSaved) {
            if (isNew && !isRetryAfterCollision) {
                // Recover cleanly from cross-process UX_GitHubIssueTask_Repo_Number collision:
                // In MJ, deleting an IS-A child (issueExt.Delete()) deletes both the child row and the parent Task row.
                if (extLoaded) {
                    const extDeleted = await issueExt.Delete();
                    if (!extDeleted) {
                        const delErr = `Failed deleting orphan GitHubIssueTask '${issueExt.ID}' after collision on #${issue.number}: ${issueExt.LatestResult?.CompleteMessage ?? 'delete failed'}`;
                        LogError(delErr);
                        throw new Error(delErr);
                    }
                } else {
                    const orphanDeleted = await task.Delete();
                    if (!orphanDeleted) {
                        const delErr = `Failed deleting orphan Task '${task.ID}' after GitHubIssueTask collision on #${issue.number}: ${task.LatestResult?.CompleteMessage ?? 'delete failed'}`;
                        LogError(delErr);
                        throw new Error(delErr);
                    }
                }
                const collided = await this.findExistingIssueExtension(
                    repository.ID,
                    issue.number,
                    issue.nodeId,
                    rv,
                    contextUser,
                );
                if (collided) {
                    return this.syncIssueItem(
                        repository,
                        issue,
                        refContext,
                        contextUser,
                        runInference,
                        queueInference,
                        md,
                        rv,
                        undefined,
                        true,
                    );
                }
            }
            const errMsg = `Failed saving GitHubIssueTask extension for #${issue.number}: ${issueExt.LatestResult?.CompleteMessage ?? 'save failed'}`;
            LogError(errMsg);
            throw new Error(errMsg);
        }

        if (preloaded) {
            preloaded.issuesByNumber.set(issue.number, issueExt);
            if (issue.nodeId) {
                preloaded.issuesByNodeId.set(issue.nodeId, issueExt);
            }
        }

        await this.reconcileTaskAssignments(
            task.ID,
            mappedPrimaryPeople,
            [],
            refContext,
            contextUser,
            md,
            rv,
        );

        let supersededDueAtSuggestions = 0;
        if (milestoneDate != null) {
            supersededDueAtSuggestions = await GitHubTaskInferenceService.Instance.SupersedePendingSuggestionsForField(
                refContext.tasksEntityId,
                task.ID,
                'DueAt',
                contextUser,
                md,
                rv,
            );
        }

        let inferredSuggestionsCreated = 0;
        const inferenceOptions = {
            task,
            repositoryId: repository.ID,
            repositoryFullName: `${repository.Owner}/${repository.Name}`,
            itemKind: 'issue' as const,
            number: issue.number,
            title: issue.title,
            body: issue.body,
            milestoneDueAt: milestoneDate,
            structuredLogins: mappedPrimaryPeople.map((p) => p.login),
            contextUser,
            provider: md as IMetadataProvider & IRunViewProvider,
        };
        if (runInference && bodyChanged) {
            const infRes = await GitHubTaskInferenceService.Instance.InferTaskPlanningFields(inferenceOptions);
            inferredSuggestionsCreated = infRes.createdCount;
        } else if (queueInference && bodyChanged) {
            const hasMappedAuthorOrAssignee =
                mappedPrimaryPeople.length > 0
                || this.resolveMappedPeople(
                    issue.authorLogin ? [{ login: issue.authorLogin, userId: issue.authorUserId }] : [],
                    [],
                    refContext,
                ).length > 0;
            if (hasMappedAuthorOrAssignee) {
                GitHubTaskInferenceService.Instance.QueueDebouncedInference(inferenceOptions);
            }
        }

        return {
            action: isNew ? 'created' : 'updated',
            taskId: task.ID,
            bodyChanged,
            supersededDueAtSuggestions,
            inferredSuggestionsCreated,
        };
    }

    private async syncPullRequestItem(
        repository: mjBizAppsTasksGitHubGitHubRepositoryEntity,
        pr: NormalizedGitHubPullRequestInput,
        refContext: SyncReferenceContext,
        contextUser: UserInfo,
        runInference: boolean,
        queueInference: boolean,
        md: IMetadataProvider,
        rv: RunView,
        preloaded?: PreloadedRepoExtensions,
        isRetryAfterCollision = false,
    ): Promise<SingleItemSyncResult> {
        const existingExt =
            (!isRetryAfterCollision ? this.findPreloadedPrExtension(preloaded, pr.number, pr.nodeId) : null)
            ?? (await this.findExistingPrExtension(repository.ID, pr.number, pr.nodeId, rv, contextUser));

        const incomingUpdatedAt = this.parseOptionalDate(pr.updatedAt);
        const existingUpdatedAt = this.parseOptionalDate(existingExt?.GitHubUpdatedAt);
        if (
            existingExt
            && incomingUpdatedAt != null
            && existingUpdatedAt != null
            && incomingUpdatedAt.getTime() < existingUpdatedAt.getTime()
        ) {
            return {
                action: 'skipped',
                reason: 'Stale payload older than stored GitHubUpdatedAt',
                taskId: existingExt.ID,
            };
        }

        const mappedPrimaryPeople = this.resolveMappedPeople(
            pr.assignees ?? [],
            pr.assigneeLogins ?? [],
            refContext,
        );
        const mappedReviewerPeople = this.resolveMappedPeople(
            pr.requestedReviewers ?? [],
            pr.requestedReviewerLogins ?? [],
            refContext,
        );

        if (
            existingExt
            && incomingUpdatedAt != null
            && existingUpdatedAt != null
            && incomingUpdatedAt.getTime() === existingUpdatedAt.getTime()
        ) {
            const unchanged = await this.isPullRequestContentUnchanged(
                existingExt,
                pr,
                mappedPrimaryPeople,
                mappedReviewerPeople,
                refContext,
                rv,
                contextUser,
            );
            if (unchanged) {
                return {
                    action: 'skipped',
                    reason: 'Unchanged content at equal GitHubUpdatedAt',
                    taskId: existingExt.ID,
                };
            }
        }

        if (
            !existingExt
            && repository.ImportRule === 'AssignedOnly'
            && mappedPrimaryPeople.length === 0
            && mappedReviewerPeople.length === 0
        ) {
            return {
                action: 'skipped',
                reason: 'Filtered out by ImportRule=AssignedOnly (no mapped GitHubIdentity assignee or reviewer)',
            };
        }

        const isNew = existingExt == null;
        const task = await md.GetEntityObject<mjBizAppsTasksTaskEntity>(TASKS_ENTITY_NAME, contextUser);
        if (isNew) {
            task.NewRecord();
            task.TypeID = refContext.prTaskTypeId;
            task.Priority = 'High';
        } else {
            const loaded = await task.Load(existingExt.ID);
            if (!loaded) {
                throw new Error(`Failed loading base Task '${existingExt.ID}' for GitHub PR #${pr.number}`);
            }
        }

        const effectiveReviewDecision =
            pr.reviewDecision !== undefined ? pr.reviewDecision : (existingExt?.ReviewDecision ?? null);
        const typeStatusCode = GitHubFieldOwnershipPolicy.MapPullRequestTypeStatusCode({
            ...pr,
            reviewDecision: effectiveReviewDecision,
        });
        const preservedFactoryStatus = !isNew
            && pr.state === 'open'
            && this.isReadyForFactoryStatus(task.TaskTypeStatusID, refContext.prStatusesByCode);

        const effectiveStatusCode = preservedFactoryStatus ? 'READY_FOR_FACTORY' : typeStatusCode;
        const typeStatusId = refContext.prStatusesByCode.get(effectiveStatusCode) ?? null;
        const coreStatus = GitHubFieldOwnershipPolicy.MapTypeStatusCodeToCoreStatus(effectiveStatusCode);

        task.Name = pr.title;
        task.Description = pr.body ?? null;
        task.Status = coreStatus;
        task.TaskTypeStatusID = typeStatusId;
        const mergedDate = this.parseOptionalDate(pr.mergedAt);
        if (coreStatus === 'Completed') {
            task.CompletedAt = mergedDate ?? task.CompletedAt ?? new Date();
        } else if (coreStatus !== 'Cancelled') {
            task.CompletedAt = null;
        }

        const taskSaved = await task.Save();
        if (!taskSaved) {
            throw new Error(`Failed saving Task for GitHub PR #${pr.number}: ${task.LatestResult?.CompleteMessage ?? 'save failed'}`);
        }

        const prExt = await md.GetEntityObject<mjBizAppsTasksGitHubGitHubPullRequestTaskEntity>(
            GITHUB_PR_TASKS_ENTITY,
            contextUser,
        );
        const extLoaded = await prExt.Load(task.ID);
        if (!extLoaded) {
            prExt.NewRecord();
            prExt.ID = task.ID;
        }

        let linkedIssueTaskId: string | null = prExt.LinkedIssueTaskID;
        const targetIssueNumber = pr.linkedIssueNumber ?? this.extractLinkedIssueNumberFromBody(pr.body);
        if (targetIssueNumber != null) {
            const linkedIssueExt =
                this.findPreloadedIssueExtension(preloaded, targetIssueNumber, '')
                ?? (await this.findExistingIssueExtension(
                    repository.ID,
                    targetIssueNumber,
                    '',
                    rv,
                    contextUser,
                ));
            if (linkedIssueExt) {
                linkedIssueTaskId = linkedIssueExt.ID;
            }
        }

        const newBodyHash = GitHubFieldOwnershipPolicy.ComputeBodyHash(pr.title, pr.body);
        const previousBodyHash = prExt.BodyHash;
        const bodyChanged = isNew || previousBodyHash !== newBodyHash;
        const milestoneDate = this.parseOptionalDate(pr.milestoneDueAt);

        prExt.RepositoryID = repository.ID;
        prExt.Number = pr.number;
        prExt.NodeID = pr.nodeId;
        prExt.HtmlURL = pr.htmlUrl;
        prExt.State = mergedDate != null ? 'merged' : pr.state;
        prExt.IsDraft = Boolean(pr.isDraft);
        prExt.HeadBranch = pr.headBranch ?? null;
        prExt.HeadSha = pr.headSha ?? null;
        prExt.BaseBranch = pr.baseBranch ?? null;
        prExt.AuthorLogin = pr.authorLogin ?? null;

        // Only overwrite ReviewDecision, ChecksStatus, ChangedFiles, Additions, Deletions when carried by the event
        if (pr.reviewDecision !== undefined) {
            prExt.ReviewDecision = pr.reviewDecision;
        } else if (isNew) {
            prExt.ReviewDecision = null;
        }
        if (pr.checksStatus !== undefined) {
            prExt.ChecksStatus = pr.checksStatus;
        } else if (isNew) {
            prExt.ChecksStatus = null;
        }
        if (pr.changedFiles !== undefined) {
            prExt.ChangedFiles = pr.changedFiles;
        } else if (isNew) {
            prExt.ChangedFiles = null;
        }
        if (pr.additions !== undefined) {
            prExt.Additions = pr.additions;
        } else if (isNew) {
            prExt.Additions = null;
        }
        if (pr.deletions !== undefined) {
            prExt.Deletions = pr.deletions;
        } else if (isNew) {
            prExt.Deletions = null;
        }

        prExt.Labels = pr.labels ? JSON.stringify(pr.labels) : null;
        prExt.Milestone = pr.milestoneTitle ?? null;
        prExt.MilestoneDueAt = milestoneDate;
        prExt.MergedAt = mergedDate;
        prExt.LinkedIssueTaskID = linkedIssueTaskId;
        prExt.BodyHash = newBodyHash;
        prExt.GitHubUpdatedAt = incomingUpdatedAt ?? existingUpdatedAt;
        prExt.LastSyncedAt = new Date();

        const extSaved = await prExt.Save();
        if (!extSaved) {
            if (isNew && !isRetryAfterCollision) {
                if (extLoaded) {
                    const extDeleted = await prExt.Delete();
                    if (!extDeleted) {
                        const delErr = `Failed deleting orphan GitHubPullRequestTask '${prExt.ID}' after collision on #${pr.number}: ${prExt.LatestResult?.CompleteMessage ?? 'delete failed'}`;
                        LogError(delErr);
                        throw new Error(delErr);
                    }
                } else {
                    const orphanDeleted = await task.Delete();
                    if (!orphanDeleted) {
                        const delErr = `Failed deleting orphan Task '${task.ID}' after GitHubPullRequestTask collision on #${pr.number}: ${task.LatestResult?.CompleteMessage ?? 'delete failed'}`;
                        LogError(delErr);
                        throw new Error(delErr);
                    }
                }
                const collided = await this.findExistingPrExtension(
                    repository.ID,
                    pr.number,
                    pr.nodeId,
                    rv,
                    contextUser,
                );
                if (collided) {
                    return this.syncPullRequestItem(
                        repository,
                        pr,
                        refContext,
                        contextUser,
                        runInference,
                        queueInference,
                        md,
                        rv,
                        undefined,
                        true,
                    );
                }
            }
            const errMsg = `Failed saving GitHubPullRequestTask extension for #${pr.number}: ${prExt.LatestResult?.CompleteMessage ?? 'save failed'}`;
            LogError(errMsg);
            throw new Error(errMsg);
        }

        if (preloaded) {
            preloaded.prsByNumber.set(pr.number, prExt);
            if (pr.nodeId) {
                preloaded.prsByNodeId.set(pr.nodeId, prExt);
            }
        }

        await this.reconcileTaskAssignments(
            task.ID,
            mappedPrimaryPeople,
            mappedReviewerPeople,
            refContext,
            contextUser,
            md,
            rv,
        );

        let supersededDueAtSuggestions = 0;
        if (milestoneDate != null) {
            supersededDueAtSuggestions = await GitHubTaskInferenceService.Instance.SupersedePendingSuggestionsForField(
                refContext.tasksEntityId,
                task.ID,
                'DueAt',
                contextUser,
                md,
                rv,
            );
        }

        let inferredSuggestionsCreated = 0;
        const structuredLogins = [
            ...mappedPrimaryPeople.map((p) => p.login),
            ...mappedReviewerPeople.map((p) => p.login),
        ];
        const inferenceOptions = {
            task,
            repositoryId: repository.ID,
            repositoryFullName: `${repository.Owner}/${repository.Name}`,
            itemKind: 'pull_request' as const,
            number: pr.number,
            title: pr.title,
            body: pr.body,
            milestoneDueAt: milestoneDate,
            structuredLogins,
            contextUser,
            provider: md as IMetadataProvider & IRunViewProvider,
        };
        if (runInference && bodyChanged) {
            const infRes = await GitHubTaskInferenceService.Instance.InferTaskPlanningFields(inferenceOptions);
            inferredSuggestionsCreated = infRes.createdCount;
        } else if (queueInference && bodyChanged) {
            const hasMappedAuthorOrParticipant =
                mappedPrimaryPeople.length > 0
                || mappedReviewerPeople.length > 0
                || this.resolveMappedPeople(
                    pr.authorLogin ? [{ login: pr.authorLogin, userId: pr.authorUserId }] : [],
                    [],
                    refContext,
                ).length > 0;
            if (hasMappedAuthorOrParticipant) {
                GitHubTaskInferenceService.Instance.QueueDebouncedInference(inferenceOptions);
            }
        }

        return {
            action: isNew ? 'created' : 'updated',
            taskId: task.ID,
            bodyChanged,
            supersededDueAtSuggestions,
            inferredSuggestionsCreated,
        };
    }

    private isReadyForFactoryStatus(
        currentStatusId: string | null,
        statusesByCode: Map<string, string>,
    ): boolean {
        const readyId = statusesByCode.get('READY_FOR_FACTORY');
        return Boolean(currentStatusId && readyId && UUIDsEqual(currentStatusId, readyId));
    }

    private resolveMappedPeople(
        userRefs: NormalizedGitHubUserRef[],
        fallbackLogins: string[],
        refContext: SyncReferenceContext,
    ): Array<{ login: string; personId: string }> {
        const candidates: NormalizedGitHubUserRef[] =
            userRefs.length > 0
                ? userRefs
                : fallbackLogins.map((login) => ({ login, userId: null }));

        const seenPersonIds = new Set<string>();
        const mapped: Array<{ login: string; personId: string }> = [];

        for (const candidate of candidates) {
            const cleanLogin = candidate.login.trim();
            const cleanUserId = candidate.userId?.trim() ?? '';
            let personId: string | undefined;

            if (cleanUserId.length > 0) {
                const byUserId = refContext.personIdByUserId.get(cleanUserId);
                if (byUserId) {
                    personId = byUserId.personId;
                } else if (cleanLogin.length > 0) {
                    const byLogin = refContext.identityByLowerLogin.get(cleanLogin.toLowerCase());
                    if (byLogin) {
                        // Only fall back to login match when the stored GitHubIdentity has no conflicting GitHubUserID
                        if (!byLogin.userId || byLogin.userId === cleanUserId) {
                            personId = byLogin.personId;
                        }
                    }
                }
            } else if (cleanLogin.length > 0) {
                personId = refContext.identityByLowerLogin.get(cleanLogin.toLowerCase())?.personId;
            }

            if (!personId) continue;
            const key = personId.toLowerCase();
            if (seenPersonIds.has(key)) continue;
            seenPersonIds.add(key);
            mapped.push({ login: cleanLogin || cleanUserId, personId });
        }
        return mapped;
    }

    private async reconcileTaskAssignments(
        taskId: string,
        primaryPeople: Array<{ login: string; personId: string }>,
        reviewerPeople: Array<{ login: string; personId: string }>,
        refContext: SyncReferenceContext,
        contextUser: UserInfo,
        md: IMetadataProvider,
        rv: RunView,
    ): Promise<void> {
        const cleanTaskId = AssertValidUUID(taskId, 'taskId');
        const existingRes = await rv.RunView<mjBizAppsTasksTaskAssignmentEntity>(
            {
                EntityName: TASK_ASSIGNMENTS_ENTITY,
                ExtraFilter: `TaskID = '${cleanTaskId}'`,
                ResultType: 'entity_object',
            },
            contextUser,
        );
        if (!existingRes.Success) {
            throw new Error(`Failed loading TaskAssignments for Task '${cleanTaskId}': ${existingRes.ErrorMessage}`);
        }

        const existingRows = existingRes.Results ?? [];
        const desired = [
            ...primaryPeople.map((p) => ({ ...p, roleId: refContext.primaryRoleId })),
            ...reviewerPeople.map((p) => ({ ...p, roleId: refContext.reviewerRoleId })),
        ];

        for (const target of desired) {
            const match = existingRows.find(
                (row) =>
                    UUIDsEqual(row.AssigneeEntityID, refContext.peopleEntityId)
                    && UUIDsEqual(row.AssigneeRecordID, target.personId)
                    && UUIDsEqual(row.RoleID, target.roleId),
            );
            if (!match) {
                const assignment = await md.GetEntityObject<mjBizAppsTasksTaskAssignmentEntity>(
                    TASK_ASSIGNMENTS_ENTITY,
                    contextUser,
                );
                assignment.NewRecord();
                assignment.TaskID = cleanTaskId;
                assignment.AssigneeEntityID = refContext.peopleEntityId;
                assignment.AssigneeRecordID = target.personId;
                assignment.RoleID = target.roleId;
                assignment.RoleNotes = `${GITHUB_ASSIGNMENT_NOTE_PREFIX}${target.login})`;
                const saved = await assignment.Save();
                if (!saved) {
                    const msg = `Failed creating TaskAssignment for '@${target.login}': ${assignment.LatestResult?.CompleteMessage ?? 'save failed'}`;
                    LogError(msg);
                    throw new Error(msg);
                }
            }
        }

        for (const row of existingRows) {
            const isGitHubManaged = typeof row.RoleNotes === 'string'
                && row.RoleNotes.startsWith(GITHUB_ASSIGNMENT_NOTE_PREFIX);
            if (!isGitHubManaged) continue;

            const stillDesired = desired.some(
                (d) =>
                    UUIDsEqual(row.AssigneeEntityID, refContext.peopleEntityId)
                    && UUIDsEqual(row.AssigneeRecordID, d.personId)
                    && UUIDsEqual(row.RoleID, d.roleId),
            );
            if (!stillDesired) {
                const deleted = await row.Delete();
                if (!deleted) {
                    const msg = `Failed deleting stale TaskAssignment '${row.ID}': ${row.LatestResult?.CompleteMessage ?? 'delete failed'}`;
                    LogError(msg);
                    throw new Error(msg);
                }
            }
        }
    }

    /**
     * Updates `ChecksStatus` on all existing tracked `GitHubPullRequestTask` rows whose stored
     * `HeadSha` matches the check event's `headSha`. Events for an older commit SHA are skipped
     * so out-of-order check completions never overwrite a newer push's status.
     */
    public async UpdatePullRequestChecksStatus(options: {
        repository: mjBizAppsTasksGitHubGitHubRepositoryEntity;
        prNumbers?: number[];
        headSha?: string | null;
        checksStatus: GitHubPullRequestChecksStatus;
        contextUser: UserInfo;
        provider?: IMetadataProvider & IRunViewProvider;
    }): Promise<SingleItemSyncResult> {
        if (!options.repository.IsTracked) {
            return { action: 'skipped', reason: 'Repository is not tracked' };
        }
        const rv = options.provider ? RunView.FromMetadataProvider(options.provider) : new RunView();
        const cleanRepoId = AssertValidUUID(options.repository.ID, 'repositoryId');
        const validNums = (options.prNumbers ?? [])
            .map((n) => Math.trunc(n))
            .filter((n) => Number.isInteger(n) && n > 0);
        const cleanSha = options.headSha?.trim() ?? '';
        if (!cleanSha) {
            return { action: 'skipped', reason: 'Check event contains no head_sha' };
        }

        const prRes = await rv.RunView<mjBizAppsTasksGitHubGitHubPullRequestTaskEntity>(
            {
                EntityName: GITHUB_PR_TASKS_ENTITY,
                ExtraFilter: `RepositoryID = '${cleanRepoId}' AND HeadSha = '${EscapeSQLString(cleanSha)}'`,
                ResultType: 'entity_object',
            },
            options.contextUser,
        );
        if (!prRes.Success) {
            const errMsg = `Failed querying GitHubPullRequestTask for check event: ${prRes.ErrorMessage}`;
            LogError(errMsg);
            throw new Error(errMsg);
        }

        const candidates = (prRes.Results ?? []).filter(
            (row) =>
                (row.HeadSha ?? '').trim() === cleanSha
                && (validNums.length === 0 || (typeof row.Number === 'number' && validNums.includes(row.Number))),
        );
        if (candidates.length === 0) {
            return {
                action: 'skipped',
                reason: `No tracked GitHubPullRequestTask with HeadSha '${cleanSha}' matches the check event`,
            };
        }

        for (const prExt of candidates) {
            prExt.ChecksStatus = options.checksStatus;
            prExt.LastSyncedAt = new Date();
            const saved = await prExt.Save();
            if (!saved) {
                const errMsg = `Failed updating ChecksStatus on GitHubPullRequestTask '${prExt.ID}': ${prExt.LatestResult?.CompleteMessage ?? 'save failed'}`;
                LogError(errMsg);
                throw new Error(errMsg);
            }
        }

        return {
            action: 'updated',
            taskId: candidates[0].ID,
            bodyChanged: false,
            supersededDueAtSuggestions: 0,
            inferredSuggestionsCreated: 0,
        };
    }

    private async isIssueContentUnchanged(
        existingExt: mjBizAppsTasksGitHubGitHubIssueTaskEntity,
        issue: NormalizedGitHubIssueInput,
        mappedPrimaryPeople: Array<{ login: string; personId: string }>,
        refContext: SyncReferenceContext,
        rv: RunView,
        contextUser: UserInfo,
    ): Promise<boolean> {
        const expectedBodyHash = GitHubFieldOwnershipPolicy.ComputeBodyHash(issue.title, issue.body);
        const expectedLabels = issue.labels ? JSON.stringify(issue.labels) : null;
        const expectedMilestoneDate = this.parseOptionalDate(issue.milestoneDueAt);
        const storedMilestoneDate = this.parseOptionalDate(existingExt.MilestoneDueAt);

        if (
            (existingExt.BodyHash ?? null) !== expectedBodyHash
            || existingExt.State !== issue.state
            || (existingExt.StateReason ?? null) !== (issue.stateReason ?? null)
            || (existingExt.HtmlURL ?? null) !== issue.htmlUrl
            || (existingExt.Labels ?? null) !== expectedLabels
            || (existingExt.Milestone ?? null) !== (issue.milestoneTitle ?? null)
            || (storedMilestoneDate?.getTime() ?? null) !== (expectedMilestoneDate?.getTime() ?? null)
        ) {
            return false;
        }

        return this.areTaskAssignmentsEqual(
            existingExt.ID,
            mappedPrimaryPeople,
            [],
            refContext,
            rv,
            contextUser,
        );
    }

    private async isPullRequestContentUnchanged(
        existingExt: mjBizAppsTasksGitHubGitHubPullRequestTaskEntity,
        pr: NormalizedGitHubPullRequestInput,
        mappedPrimaryPeople: Array<{ login: string; personId: string }>,
        mappedReviewerPeople: Array<{ login: string; personId: string }>,
        refContext: SyncReferenceContext,
        rv: RunView,
        contextUser: UserInfo,
    ): Promise<boolean> {
        const expectedBodyHash = GitHubFieldOwnershipPolicy.ComputeBodyHash(pr.title, pr.body);
        const expectedLabels = pr.labels ? JSON.stringify(pr.labels) : null;
        const expectedMilestoneDate = this.parseOptionalDate(pr.milestoneDueAt);
        const storedMilestoneDate = this.parseOptionalDate(existingExt.MilestoneDueAt);
        const expectedMergedDate = this.parseOptionalDate(pr.mergedAt);
        const storedMergedDate = this.parseOptionalDate(existingExt.MergedAt);
        const expectedState = expectedMergedDate != null ? 'merged' : pr.state;

        if (
            (existingExt.BodyHash ?? null) !== expectedBodyHash
            || existingExt.State !== expectedState
            || Boolean(existingExt.IsDraft) !== Boolean(pr.isDraft)
            || (existingExt.HtmlURL ?? null) !== pr.htmlUrl
            || (existingExt.HeadBranch ?? null) !== (pr.headBranch ?? null)
            || (existingExt.HeadSha ?? null) !== (pr.headSha ?? null)
            || (existingExt.BaseBranch ?? null) !== (pr.baseBranch ?? null)
            || (existingExt.Labels ?? null) !== expectedLabels
            || (existingExt.Milestone ?? null) !== (pr.milestoneTitle ?? null)
            || (storedMilestoneDate?.getTime() ?? null) !== (expectedMilestoneDate?.getTime() ?? null)
            || (storedMergedDate?.getTime() ?? null) !== (expectedMergedDate?.getTime() ?? null)
            || (pr.reviewDecision !== undefined && pr.reviewDecision !== (existingExt.ReviewDecision ?? null))
            || (pr.checksStatus !== undefined && pr.checksStatus !== (existingExt.ChecksStatus ?? null))
            || (pr.changedFiles !== undefined && pr.changedFiles !== (existingExt.ChangedFiles ?? null))
            || (pr.additions !== undefined && pr.additions !== (existingExt.Additions ?? null))
            || (pr.deletions !== undefined && pr.deletions !== (existingExt.Deletions ?? null))
        ) {
            return false;
        }

        return this.areTaskAssignmentsEqual(
            existingExt.ID,
            mappedPrimaryPeople,
            mappedReviewerPeople,
            refContext,
            rv,
            contextUser,
        );
    }

    private async areTaskAssignmentsEqual(
        taskId: string,
        primaryPeople: Array<{ login: string; personId: string }>,
        reviewerPeople: Array<{ login: string; personId: string }>,
        refContext: SyncReferenceContext,
        rv: RunView,
        contextUser: UserInfo,
    ): Promise<boolean> {
        const cleanTaskId = AssertValidUUID(taskId, 'taskId');
        const existingRes = await rv.RunView<mjBizAppsTasksTaskAssignmentEntity>(
            {
                EntityName: TASK_ASSIGNMENTS_ENTITY,
                ExtraFilter: `TaskID = '${cleanTaskId}'`,
                ResultType: 'simple',
            },
            contextUser,
        );
        if (!existingRes.Success) {
            LogError(`Failed loading TaskAssignments in areTaskAssignmentsEqual for Task '${cleanTaskId}': ${existingRes.ErrorMessage}`);
            return false;
        }
        const gitHubRows = (existingRes.Results ?? []).filter(
            (row) => typeof row.RoleNotes === 'string' && row.RoleNotes.startsWith(GITHUB_ASSIGNMENT_NOTE_PREFIX),
        );
        const desiredKeys = new Set<string>([
            ...primaryPeople.map((p) => `${p.personId.toLowerCase()}:${refContext.primaryRoleId.toLowerCase()}`),
            ...reviewerPeople.map((p) => `${p.personId.toLowerCase()}:${refContext.reviewerRoleId.toLowerCase()}`),
        ]);
        if (gitHubRows.length !== desiredKeys.size) {
            return false;
        }
        for (const row of gitHubRows) {
            const key = `${String(row.AssigneeRecordID ?? '').toLowerCase()}:${String(row.RoleID ?? '').toLowerCase()}`;
            if (!desiredKeys.has(key)) {
                return false;
            }
        }
        return true;
    }

    private async preloadRepositoryExtensions(
        repositoryId: string,
        rv: RunView,
        contextUser: UserInfo,
    ): Promise<PreloadedRepoExtensions> {
        const cleanRepoId = AssertValidUUID(repositoryId, 'repositoryId');
        const [issuesRes, prsRes] = await rv.RunViews([
            {
                EntityName: GITHUB_ISSUE_TASKS_ENTITY,
                ExtraFilter: `RepositoryID = '${cleanRepoId}'`,
                ResultType: 'entity_object',
            },
            {
                EntityName: GITHUB_PR_TASKS_ENTITY,
                ExtraFilter: `RepositoryID = '${cleanRepoId}'`,
                ResultType: 'entity_object',
            },
        ], contextUser);

        if (!issuesRes?.Success || !prsRes?.Success) {
            const errMsg = issuesRes?.ErrorMessage || prsRes?.ErrorMessage || `Failed preloading extensions for repository '${cleanRepoId}'`;
            LogError(errMsg);
            throw new Error(errMsg);
        }

        const issuesByNumber = new Map<number, mjBizAppsTasksGitHubGitHubIssueTaskEntity>();
        const issuesByNodeId = new Map<string, mjBizAppsTasksGitHubGitHubIssueTaskEntity>();
        for (const row of (issuesRes?.Results as mjBizAppsTasksGitHubGitHubIssueTaskEntity[] | undefined) ?? []) {
            if (typeof row.Number === 'number') {
                issuesByNumber.set(row.Number, row);
            }
            if (typeof row.NodeID === 'string' && row.NodeID.trim().length > 0) {
                issuesByNodeId.set(row.NodeID.trim(), row);
            }
        }

        const prsByNumber = new Map<number, mjBizAppsTasksGitHubGitHubPullRequestTaskEntity>();
        const prsByNodeId = new Map<string, mjBizAppsTasksGitHubGitHubPullRequestTaskEntity>();
        for (const row of (prsRes?.Results as mjBizAppsTasksGitHubGitHubPullRequestTaskEntity[] | undefined) ?? []) {
            if (typeof row.Number === 'number') {
                prsByNumber.set(row.Number, row);
            }
            if (typeof row.NodeID === 'string' && row.NodeID.trim().length > 0) {
                prsByNodeId.set(row.NodeID.trim(), row);
            }
        }

        return {
            issuesByNumber,
            issuesByNodeId,
            prsByNumber,
            prsByNodeId,
        };
    }

    private findPreloadedIssueExtension(
        preloaded: PreloadedRepoExtensions | undefined,
        number: number,
        nodeId: string,
    ): mjBizAppsTasksGitHubGitHubIssueTaskEntity | null {
        if (!preloaded) return null;
        const byNum = preloaded.issuesByNumber.get(Math.trunc(number));
        if (byNum) return byNum;
        if (nodeId.trim().length > 0) {
            return preloaded.issuesByNodeId.get(nodeId.trim()) ?? null;
        }
        return null;
    }

    private findPreloadedPrExtension(
        preloaded: PreloadedRepoExtensions | undefined,
        number: number,
        nodeId: string,
    ): mjBizAppsTasksGitHubGitHubPullRequestTaskEntity | null {
        if (!preloaded) return null;
        const byNum = preloaded.prsByNumber.get(Math.trunc(number));
        if (byNum) return byNum;
        if (nodeId.trim().length > 0) {
            return preloaded.prsByNodeId.get(nodeId.trim()) ?? null;
        }
        return null;
    }

    private async findExistingIssueExtension(
        repositoryId: string,
        number: number,
        nodeId: string,
        rv: RunView,
        contextUser: UserInfo,
    ): Promise<mjBizAppsTasksGitHubGitHubIssueTaskEntity | null> {
        const cleanRepoId = AssertValidUUID(repositoryId, 'repositoryId');
        const safeNum = Math.trunc(number);
        const clauses = [`(RepositoryID = '${cleanRepoId}' AND Number = ${safeNum})`];
        if (nodeId.trim().length > 0) {
            clauses.push(`NodeID = '${EscapeSQLString(nodeId.trim())}'`);
        }
        const res = await rv.RunView<mjBizAppsTasksGitHubGitHubIssueTaskEntity>(
            {
                EntityName: GITHUB_ISSUE_TASKS_ENTITY,
                ExtraFilter: clauses.join(' OR '),
                MaxRows: 1,
                ResultType: 'entity_object',
            },
            contextUser,
        );
        if (!res.Success) {
            throw new Error(`Failed querying GitHubIssueTask: ${res.ErrorMessage}`);
        }
        return res.Results?.[0] ?? null;
    }

    private async findExistingPrExtension(
        repositoryId: string,
        number: number,
        nodeId: string,
        rv: RunView,
        contextUser: UserInfo,
    ): Promise<mjBizAppsTasksGitHubGitHubPullRequestTaskEntity | null> {
        const cleanRepoId = AssertValidUUID(repositoryId, 'repositoryId');
        const safeNum = Math.trunc(number);
        const clauses = [`(RepositoryID = '${cleanRepoId}' AND Number = ${safeNum})`];
        if (nodeId.trim().length > 0) {
            clauses.push(`NodeID = '${EscapeSQLString(nodeId.trim())}'`);
        }
        const res = await rv.RunView<mjBizAppsTasksGitHubGitHubPullRequestTaskEntity>(
            {
                EntityName: GITHUB_PR_TASKS_ENTITY,
                ExtraFilter: clauses.join(' OR '),
                MaxRows: 1,
                ResultType: 'entity_object',
            },
            contextUser,
        );
        if (!res.Success) {
            throw new Error(`Failed querying GitHubPullRequestTask: ${res.ErrorMessage}`);
        }
        return res.Results?.[0] ?? null;
    }

    private async loadReferenceContext(
        md: IMetadataProvider,
        rv: RunView,
        contextUser: UserInfo,
    ): Promise<SyncReferenceContext> {
        const tasksEntity = md.EntityByName(TASKS_ENTITY_NAME);
        const peopleEntity = md.EntityByName(PEOPLE_ENTITY);
        if (!tasksEntity) {
            throw new Error(`Entity '${TASKS_ENTITY_NAME}' not found in metadata`);
        }
        if (!peopleEntity) {
            throw new Error(`Entity '${PEOPLE_ENTITY}' not found in metadata`);
        }

        const [typesRes, statusesRes, rolesRes, identitiesRes] = await rv.RunViews([
            {
                EntityName: TASK_TYPES_ENTITY,
                ExtraFilter: `Code IN ('GITHUB_ISSUE', 'GITHUB_PR')`,
                ResultType: 'simple',
            },
            {
                EntityName: TASK_TYPE_STATUS_ENTITY,
                ExtraFilter: `IsActive = 1`,
                ResultType: 'simple',
            },
            {
                EntityName: TASK_ROLES_ENTITY,
                ExtraFilter: `Name IN ('Primary', 'Reviewer')`,
                ResultType: 'simple',
            },
            {
                EntityName: GITHUB_IDENTITIES_ENTITY,
                ExtraFilter: `IsActive = 1`,
                ResultType: 'simple',
            },
        ], contextUser);

        if (!typesRes?.Success || !statusesRes?.Success || !rolesRes?.Success || !identitiesRes?.Success) {
            const errMsg =
                typesRes?.ErrorMessage
                || statusesRes?.ErrorMessage
                || rolesRes?.ErrorMessage
                || identitiesRes?.ErrorMessage
                || 'Failed loading sync reference context';
            LogError(errMsg);
            throw new Error(errMsg);
        }

        const taskTypes = (typesRes?.Results as mjBizAppsTasksTaskTypeEntity[] | undefined) ?? [];
        const issueType = taskTypes.find((t) => t.Code === 'GITHUB_ISSUE');
        const prType = taskTypes.find((t) => t.Code === 'GITHUB_PR');
        if (!issueType || !prType) {
            throw new Error(`Required GITHUB_ISSUE / GITHUB_PR TaskTypes are not seeded; run mj sync push for bizapps-tasks-github`);
        }

        const statuses = (statusesRes?.Results as mjBizAppsTasksTaskTypeStatusEntity[] | undefined) ?? [];
        const issueStatusesByCode = new Map<string, string>();
        const prStatusesByCode = new Map<string, string>();
        for (const st of statuses) {
            if (UUIDsEqual(st.TaskTypeID, issueType.ID)) {
                issueStatusesByCode.set(st.Code, st.ID);
            } else if (UUIDsEqual(st.TaskTypeID, prType.ID)) {
                prStatusesByCode.set(st.Code, st.ID);
            }
        }

        const roles = (rolesRes?.Results as mjBizAppsTasksTaskRoleEntity[] | undefined) ?? [];
        const primaryRole = roles.find((r) => r.Name === 'Primary');
        const reviewerRole = roles.find((r) => r.Name === 'Reviewer');
        if (!primaryRole || !reviewerRole) {
            throw new Error(`Required Primary / Reviewer Task Roles not found in MJ_BizApps_Tasks: Task Roles`);
        }

        const identities = (identitiesRes?.Results as mjBizAppsTasksGitHubGitHubIdentityEntity[] | undefined) ?? [];
        const personIdByUserId = new Map<string, { login: string; personId: string }>();
        const identityByLowerLogin = new Map<string, { personId: string; userId: string | null }>();
        for (const idRow of identities) {
            const cleanLogin = idRow.GitHubLogin.trim();
            const cleanUserId = typeof idRow.GitHubUserID === 'string' && idRow.GitHubUserID.trim().length > 0
                ? idRow.GitHubUserID.trim()
                : null;
            identityByLowerLogin.set(cleanLogin.toLowerCase(), {
                personId: idRow.PersonID,
                userId: cleanUserId,
            });
            if (cleanUserId) {
                personIdByUserId.set(cleanUserId, {
                    login: cleanLogin,
                    personId: idRow.PersonID,
                });
            }
        }

        return {
            tasksEntityId: tasksEntity.ID,
            peopleEntityId: peopleEntity.ID,
            issueTaskTypeId: issueType.ID,
            prTaskTypeId: prType.ID,
            issueStatusesByCode,
            prStatusesByCode,
            primaryRoleId: primaryRole.ID,
            reviewerRoleId: reviewerRole.ID,
            personIdByUserId,
            identityByLowerLogin,
        };
    }

    private parseOptionalDate(value: string | Date | null | undefined): Date | null {
        if (value == null) return null;
        if (value instanceof Date) return Number.isNaN(value.getTime()) ? null : value;
        const trimmed = value.trim();
        if (!trimmed) return null;
        const parsed = new Date(trimmed);
        return Number.isNaN(parsed.getTime()) ? null : parsed;
    }

    private extractLinkedIssueNumberFromBody(body: string | null | undefined): number | null {
        if (!body) return null;
        const match = /\b(?:close[sd]?|fix(?:e[sd])?|resolve[sd]?)\s+#(\d+)\b/i.exec(body);
        if (!match) return null;
        const parsed = Number(match[1]);
        return Number.isInteger(parsed) && parsed > 0 ? parsed : null;
    }
}
