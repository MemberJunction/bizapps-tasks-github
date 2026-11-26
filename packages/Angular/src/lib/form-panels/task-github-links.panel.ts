import { Component, OnInit, ChangeDetectorRef, inject } from '@angular/core';
import { CompositeKey, RunView, type RunViewParams } from '@memberjunction/core';
import { IsValidUUID, RegisterClassEx } from '@memberjunction/global';
import { BaseFormPanel } from '@memberjunction/ng-base-forms';
import { NavigationService } from '@memberjunction/ng-shared';
import type { mjBizAppsTasksTaskEntity, mjBizAppsTasksTaskLinkEntity } from '@mj-biz-apps/tasks-entities';
import {
    GitHubTasksEngineBase,
    type mjBizAppsTasksGitHubGitHubIssueTaskEntity,
    type mjBizAppsTasksGitHubGitHubPullRequestTaskEntity,
} from '@mj-biz-apps/tasks-github-entities';

interface PrDisplayItem {
    ID: string;
    Number: number | null;
    Title: string;
    State: 'open' | 'merged' | 'closed' | 'draft';
    StateLabel: string;
    BranchFlow: string;
    Additions: number;
    Deletions: number;
    HtmlUrl: string | null;
}

interface IssueDisplayItem {
    ID: string;
    Number: number | null;
    Title: string;
    State: 'open' | 'closed';
    StateLabel: string;
    RepositoryName: string;
    Milestone: string | null;
    HtmlUrl: string | null;
}

interface RepoDisplayItem {
    ID: string;
    FullName: string;
    DefaultBranch: string;
    IsTracked: boolean;
    HtmlUrl: string | null;
}

@RegisterClassEx(BaseFormPanel, {
    key: 'github-tasks:task-github-links-panel',
    skipNullKeyWarning: true,
    metadata: {
        entity: 'MJ_BizApps_Tasks: Tasks',
        slot: 'after-fields',
        sortKey: 20,
        contributionKey: 'task-github-links',
    },
})
@Component({
    standalone: false,
    selector: 'mj-task-github-links-panel',
    templateUrl: './task-github-links.panel.html',
    styleUrls: ['./github-form-panels.css'],
})
export class TaskGitHubLinksPanel extends BaseFormPanel<mjBizAppsTasksTaskEntity> implements OnInit {
    private cdr?: ChangeDetectorRef;
    private navService?: NavigationService;

    constructor() {
        super();
        try {
            this.cdr = inject(ChangeDetectorRef, { optional: true }) ?? undefined;
        } catch {
            // Direct unit test instantiation without injection context
        }
        try {
            this.navService = inject(NavigationService, { optional: true }) ?? undefined;
        } catch {
            // Direct unit test instantiation without injection context
        }
    }

    public LinkedPullRequests: PrDisplayItem[] = [];
    public LinkedIssues: IssueDisplayItem[] = [];
    public LinkedRepositories: RepoDisplayItem[] = [];
    public IsLoading = false;

    public async ngOnInit(): Promise<void> {
        await this.loadLinkedGitHubItems();
    }

    public get TotalLinkedItemsCount(): number {
        return this.LinkedPullRequests.length + this.LinkedIssues.length + this.LinkedRepositories.length;
    }

    public get HasAnyLinkedItems(): boolean {
        return this.TotalLinkedItemsCount > 0;
    }

    public OpenPr(item: PrDisplayItem): void {
        const pk = new CompositeKey();
        pk.KeyValuePairs.push({ FieldName: 'ID', Value: item.ID });
        this.navigateToEntity('MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks', pk);
    }

    public OpenIssue(item: IssueDisplayItem): void {
        const pk = new CompositeKey();
        pk.KeyValuePairs.push({ FieldName: 'ID', Value: item.ID });
        this.navigateToEntity('MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks', pk);
    }

    public OpenRepository(item: RepoDisplayItem): void {
        const pk = new CompositeKey();
        pk.KeyValuePairs.push({ FieldName: 'ID', Value: item.ID });
        this.navigateToEntity('MJ_BizApps_Tasks_GitHub: Git Hub Repositories', pk);
    }

    public OpenExternalUrl(url: string | null): void {
        if (url) {
            window.open(url, '_blank', 'noopener,noreferrer');
        }
    }

    private navigateToEntity(entityName: string, pk: CompositeKey): void {
        if (this.navService) {
            this.navService.OpenEntityRecord(entityName, pk);
        } else if (this.FormComponent) {
            this.FormComponent.OnFormNavigate({
                Kind: 'record',
                EntityName: entityName,
                PrimaryKey: pk,
            });
        }
    }

    private mapPrDisplayItem(pr: mjBizAppsTasksGitHubGitHubPullRequestTaskEntity): PrDisplayItem {
        const state: 'open' | 'merged' | 'closed' | 'draft' =
            pr.IsDraft && pr.State === 'open' ? 'draft' : (pr.State || 'open');
        const stateLabel =
            state === 'draft' ? 'Draft' :
            state === 'merged' ? 'Merged' :
            state === 'closed' ? 'Closed' : 'Open';
        const branchFlow =
            pr.HeadBranch && pr.BaseBranch ? `${pr.HeadBranch} → ${pr.BaseBranch}` :
            pr.HeadBranch || pr.BaseBranch || '—';
        return {
            ID: pr.ID,
            Number: pr.Number ?? null,
            Title: pr.Name || 'Pull Request',
            State: state,
            StateLabel: stateLabel,
            BranchFlow: branchFlow,
            Additions: pr.Additions || 0,
            Deletions: pr.Deletions || 0,
            HtmlUrl: pr.HtmlURL || null,
        };
    }

    private mapIssueDisplayItem(issue: mjBizAppsTasksGitHubGitHubIssueTaskEntity): IssueDisplayItem {
        return {
            ID: issue.ID,
            Number: issue.Number ?? null,
            Title: issue.Name || 'Issue',
            State: issue.State || 'open',
            StateLabel: issue.State === 'closed' ? 'Closed' : 'Open',
            RepositoryName: issue.Repository || 'GitHub Repository',
            Milestone: issue.Milestone || null,
            HtmlUrl: issue.HtmlURL || null,
        };
    }

    private async loadLinkedGitHubItems(): Promise<void> {
        const rawTaskId = this.Record?.ID;
        if (!rawTaskId || !IsValidUUID(rawTaskId)) return;
        const taskId = rawTaskId.trim();

        this.IsLoading = true;
        try {
            const provider = this.FormComponent?.ProviderToUse;
            const currentUser = provider?.CurrentUser;
            const rv = RunView.FromMetadataProvider(provider);

            // 1. Fetch TaskLinks and check if the task itself is a GitHub Issue or PR subtype in ONE RunViews batch
            const [linkResult, selfPrRes, selfIssueRes] = await rv.RunViews(
                [
                    {
                        EntityName: 'MJ_BizApps_Tasks: Task Links',
                        ExtraFilter: `TaskID = '${taskId}'`,
                        ResultType: 'simple',
                    },
                    {
                        EntityName: 'MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks',
                        ExtraFilter: `ID = '${taskId}'`,
                        ResultType: 'simple',
                    },
                    {
                        EntityName: 'MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks',
                        ExtraFilter: `ID = '${taskId}'`,
                        ResultType: 'simple',
                    },
                ],
                currentUser,
            );

            // Seed maps directly from the already-fetched self subtype rows (eliminating redundant re-queries)
            const prByLowerId = new Map<string, mjBizAppsTasksGitHubGitHubPullRequestTaskEntity>();
            if (selfPrRes?.Success && Array.isArray(selfPrRes.Results)) {
                for (const pr of selfPrRes.Results as mjBizAppsTasksGitHubGitHubPullRequestTaskEntity[]) {
                    if (pr.ID) {
                        prByLowerId.set(pr.ID.toLowerCase(), pr);
                    }
                }
            }

            const issueByLowerId = new Map<string, mjBizAppsTasksGitHubGitHubIssueTaskEntity>();
            if (selfIssueRes?.Success && Array.isArray(selfIssueRes.Results)) {
                for (const issue of selfIssueRes.Results as mjBizAppsTasksGitHubGitHubIssueTaskEntity[]) {
                    if (issue.ID) {
                        issueByLowerId.set(issue.ID.toLowerCase(), issue);
                    }
                }
            }

            const remainingPrIds = new Set<string>();
            const remainingIssueIds = new Set<string>();
            const repoIds = new Set<string>();

            if (linkResult?.Success && Array.isArray(linkResult.Results)) {
                for (const link of linkResult.Results as mjBizAppsTasksTaskLinkEntity[]) {
                    const recordId = typeof link.RecordID === 'string' ? link.RecordID.trim() : '';
                    if (!recordId || !IsValidUUID(recordId)) {
                        continue;
                    }
                    const lowerId = recordId.toLowerCase();
                    const entityName = (link.Entity || '').toLowerCase();
                    if (entityName.includes('pull request')) {
                        if (!prByLowerId.has(lowerId)) {
                            remainingPrIds.add(recordId);
                        }
                    } else if (entityName.includes('issue')) {
                        if (!issueByLowerId.has(lowerId)) {
                            remainingIssueIds.add(recordId);
                        }
                    } else if (entityName.includes('repositor')) {
                        repoIds.add(recordId);
                    }
                }
            }

            // 2. Batch remaining linked PR/Issue queries in ONE RunViews call; resolve Repositories from GitHubTasksEngineBase
            const phase2Queries: RunViewParams[] = [];
            let remainingPrIdx = -1;
            let remainingIssueIdx = -1;

            if (remainingPrIds.size > 0) {
                remainingPrIdx = phase2Queries.length;
                const prFilter = Array.from(remainingPrIds).map((id) => `ID = '${id}'`).join(' OR ');
                phase2Queries.push({
                    EntityName: 'MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks',
                    ExtraFilter: prFilter,
                    ResultType: 'simple',
                });
            }

            if (remainingIssueIds.size > 0) {
                remainingIssueIdx = phase2Queries.length;
                const issueFilter = Array.from(remainingIssueIds).map((id) => `ID = '${id}'`).join(' OR ');
                phase2Queries.push({
                    EntityName: 'MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks',
                    ExtraFilter: issueFilter,
                    ResultType: 'simple',
                });
            }

            const engine = GitHubTasksEngineBase.Instance;
            const [phase2Results] = await Promise.all([
                phase2Queries.length > 0 ? rv.RunViews(phase2Queries, currentUser) : Promise.resolve([]),
                repoIds.size > 0 ? engine.EnsureLoaded(currentUser, provider) : Promise.resolve(),
            ]);

            if (remainingPrIdx >= 0) {
                const prRes = phase2Results[remainingPrIdx];
                if (prRes?.Success && Array.isArray(prRes.Results)) {
                    for (const pr of prRes.Results as mjBizAppsTasksGitHubGitHubPullRequestTaskEntity[]) {
                        if (pr.ID) {
                            prByLowerId.set(pr.ID.toLowerCase(), pr);
                        }
                    }
                }
            }

            if (remainingIssueIdx >= 0) {
                const issueRes = phase2Results[remainingIssueIdx];
                if (issueRes?.Success && Array.isArray(issueRes.Results)) {
                    for (const issue of issueRes.Results as mjBizAppsTasksGitHubGitHubIssueTaskEntity[]) {
                        if (issue.ID) {
                            issueByLowerId.set(issue.ID.toLowerCase(), issue);
                        }
                    }
                }
            }

            if (repoIds.size > 0) {
                const resolvedRepos: RepoDisplayItem[] = [];
                for (const repoId of repoIds) {
                    const repo = engine.RepositoryById(repoId);
                    if (!repo) {
                        continue;
                    }
                    const owner = repo.Owner?.trim() || '';
                    const name = repo.Name?.trim() || '';
                    const fullName = owner && name ? `${owner}/${name}` : name || owner || 'Repository';
                    resolvedRepos.push({
                        ID: repo.ID,
                        FullName: fullName,
                        DefaultBranch: repo.DefaultBranch || 'main',
                        IsTracked: Boolean(repo.IsTracked),
                        HtmlUrl: owner && name ? `https://github.com/${owner}/${name}` : null,
                    });
                }
                this.LinkedRepositories = resolvedRepos;
            } else {
                this.LinkedRepositories = [];
            }

            this.LinkedPullRequests = Array.from(prByLowerId.values()).map((pr) => this.mapPrDisplayItem(pr));
            this.LinkedIssues = Array.from(issueByLowerId.values()).map((issue) => this.mapIssueDisplayItem(issue));
        } catch {
            // Non-blocking
        } finally {
            this.IsLoading = false;
            this.cdr?.detectChanges();
        }
    }
}
