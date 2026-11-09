import {
    IMetadataProvider,
    IRunViewProvider,
    Metadata,
    RunView,
    UserInfo,
} from '@memberjunction/core';
import { BaseSingleton, UUIDsEqual } from '@memberjunction/global';
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
import { AssertValidUUID, EscapeSqlLiteral } from './sql-safety.js';
import type {
    IGitHubRepositoryFetcher,
    NormalizedGitHubIssueInput,
    NormalizedGitHubPullRequestInput,
    NormalizedGitHubSyncItem,
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
    personIdByLowerLogin: Map<string, string>;
}

export interface SyncSingleItemOptions {
    repository: mjBizAppsTasksGitHubGitHubRepositoryEntity;
    item: NormalizedGitHubSyncItem;
    contextUser: UserInfo;
    runInference?: boolean;
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

            const items = options.items
                ?? (this._fetcher
                    ? await this._fetcher.FetchRepositoryItems(repo.Owner, repo.Name, options.contextUser, md)
                    : []);

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

            for (const item of items) {
                const res = await this.syncSingleItemWithContext(
                    repo,
                    item,
                    refContext,
                    options.contextUser,
                    options.runInference !== false,
                    md,
                    rv,
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
            options.runInference !== false,
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
        md: IMetadataProvider,
        rv: RunView,
    ): Promise<SingleItemSyncResult> {
        if (!repository.IsTracked) {
            return { action: 'skipped', reason: 'Repository is not tracked' };
        }

        if (item.kind === 'issue') {
            return this.syncIssueItem(repository, item, refContext, contextUser, runInference, md, rv);
        }
        return this.syncPullRequestItem(repository, item, refContext, contextUser, runInference, md, rv);
    }

    private async syncIssueItem(
        repository: mjBizAppsTasksGitHubGitHubRepositoryEntity,
        issue: NormalizedGitHubIssueInput,
        refContext: SyncReferenceContext,
        contextUser: UserInfo,
        runInference: boolean,
        md: IMetadataProvider,
        rv: RunView,
    ): Promise<SingleItemSyncResult> {
        const existingExt = await this.findExistingIssueExtension(repository.ID, issue.number, issue.nodeId, rv, contextUser);
        const mappedPrimaryPeople = this.resolveMappedPeople(issue.assigneeLogins ?? [], refContext.personIdByLowerLogin);

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
        issueExt.GitHubUpdatedAt = this.parseOptionalDate(issue.updatedAt);
        issueExt.LastSyncedAt = new Date();

        const extSaved = await issueExt.Save();
        if (!extSaved) {
            throw new Error(
                `Failed saving GitHubIssueTask extension for #${issue.number}: ${issueExt.LatestResult?.CompleteMessage ?? 'save failed'}`,
            );
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
        if (runInference && bodyChanged) {
            const infRes = await GitHubTaskInferenceService.Instance.InferTaskPlanningFields({
                task,
                repositoryFullName: `${repository.Owner}/${repository.Name}`,
                itemKind: 'issue',
                number: issue.number,
                title: issue.title,
                body: issue.body,
                milestoneDueAt: milestoneDate,
                structuredLogins: issue.assigneeLogins ?? [],
                contextUser,
                provider: md as IMetadataProvider & IRunViewProvider,
            });
            inferredSuggestionsCreated = infRes.createdCount;
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
        md: IMetadataProvider,
        rv: RunView,
    ): Promise<SingleItemSyncResult> {
        const existingExt = await this.findExistingPrExtension(repository.ID, pr.number, pr.nodeId, rv, contextUser);
        const mappedPrimaryPeople = this.resolveMappedPeople(pr.assigneeLogins ?? [], refContext.personIdByLowerLogin);
        const mappedReviewerPeople = this.resolveMappedPeople(
            pr.requestedReviewerLogins ?? [],
            refContext.personIdByLowerLogin,
        );

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

        const typeStatusCode = GitHubFieldOwnershipPolicy.MapPullRequestTypeStatusCode(pr);
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
            const linkedIssueExt = await this.findExistingIssueExtension(
                repository.ID,
                targetIssueNumber,
                '',
                rv,
                contextUser,
            );
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
        prExt.ReviewDecision = pr.reviewDecision ?? null;
        prExt.ChecksStatus = pr.checksStatus ?? null;
        prExt.ChangedFiles = pr.changedFiles ?? null;
        prExt.Additions = pr.additions ?? null;
        prExt.Deletions = pr.deletions ?? null;
        prExt.Labels = pr.labels ? JSON.stringify(pr.labels) : null;
        prExt.Milestone = pr.milestoneTitle ?? null;
        prExt.MilestoneDueAt = milestoneDate;
        prExt.MergedAt = mergedDate;
        prExt.LinkedIssueTaskID = linkedIssueTaskId;
        prExt.BodyHash = newBodyHash;
        prExt.GitHubUpdatedAt = this.parseOptionalDate(pr.updatedAt);
        prExt.LastSyncedAt = new Date();

        const extSaved = await prExt.Save();
        if (!extSaved) {
            throw new Error(
                `Failed saving GitHubPullRequestTask extension for #${pr.number}: ${prExt.LatestResult?.CompleteMessage ?? 'save failed'}`,
            );
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
        if (runInference && bodyChanged) {
            const structuredLogins = [
                ...(pr.assigneeLogins ?? []),
                ...(pr.requestedReviewerLogins ?? []),
            ];
            const infRes = await GitHubTaskInferenceService.Instance.InferTaskPlanningFields({
                task,
                repositoryFullName: `${repository.Owner}/${repository.Name}`,
                itemKind: 'pull_request',
                number: pr.number,
                title: pr.title,
                body: pr.body,
                milestoneDueAt: milestoneDate,
                structuredLogins,
                contextUser,
                provider: md as IMetadataProvider & IRunViewProvider,
            });
            inferredSuggestionsCreated = infRes.createdCount;
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
        logins: string[],
        personIdByLowerLogin: Map<string, string>,
    ): Array<{ login: string; personId: string }> {
        const seenPersonIds = new Set<string>();
        const mapped: Array<{ login: string; personId: string }> = [];
        for (const rawLogin of logins) {
            const clean = rawLogin.trim();
            if (!clean) continue;
            const personId = personIdByLowerLogin.get(clean.toLowerCase());
            if (!personId) continue;
            const key = personId.toLowerCase();
            if (seenPersonIds.has(key)) continue;
            seenPersonIds.add(key);
            mapped.push({ login: clean, personId });
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
                    throw new Error(
                        `Failed creating TaskAssignment for '@${target.login}': ${assignment.LatestResult?.CompleteMessage ?? 'save failed'}`,
                    );
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
                await row.Delete();
            }
        }
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
            clauses.push(`NodeID = '${EscapeSqlLiteral(nodeId.trim())}'`);
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
            clauses.push(`NodeID = '${EscapeSqlLiteral(nodeId.trim())}'`);
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
        const tasksEntity = md.Entities.find((e) => e.Name === TASKS_ENTITY_NAME);
        const peopleEntity = md.Entities.find((e) => e.Name === PEOPLE_ENTITY);
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
        const personIdByLowerLogin = new Map<string, string>();
        for (const idRow of identities) {
            personIdByLowerLogin.set(idRow.GitHubLogin.trim().toLowerCase(), idRow.PersonID);
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
            personIdByLowerLogin,
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
