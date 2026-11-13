import { Component, OnInit, ChangeDetectorRef, inject } from '@angular/core';
import { CompositeKey, RunView } from '@memberjunction/core';
import { RegisterClassEx } from '@memberjunction/global';
import { BaseFormPanel } from '@memberjunction/ng-base-forms';
import { NavigationService } from '@memberjunction/ng-shared';
import type { mjBizAppsTasksTaskEntity, mjBizAppsTasksTaskLinkEntity } from '@mj-biz-apps/tasks-entities';
import type {
    mjBizAppsTasksGitHubGitHubPullRequestTaskEntity,
    mjBizAppsTasksGitHubGitHubIssueTaskEntity,
    mjBizAppsTasksGitHubGitHubRepositoryEntity,
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

    private async loadLinkedGitHubItems(): Promise<void> {
        const taskId = this.Record?.ID;
        if (!taskId) return;

        this.IsLoading = true;
        try {
            const rv = RunView.FromMetadataProvider(this.FormComponent?.ProviderToUse);

            // 1. Fetch TaskLinks where TaskID = taskId
            const linkResult = await rv.RunView<mjBizAppsTasksTaskLinkEntity>({
                EntityName: 'MJ_BizApps_Tasks: Task Links',
                ExtraFilter: `TaskID = '${taskId}'`,
                ResultType: 'simple',
            });

            const prIds = new Set<string>();
            const issueIds = new Set<string>();
            const repoIds = new Set<string>();

            if (linkResult.Success && Array.isArray(linkResult.Results)) {
                for (const link of linkResult.Results) {
                    const entityName = (link.Entity || '').toLowerCase();
                    if (entityName.includes('pull request')) {
                        prIds.add(link.RecordID);
                    } else if (entityName.includes('issue')) {
                        issueIds.add(link.RecordID);
                    } else if (entityName.includes('repositor')) {
                        repoIds.add(link.RecordID);
                    }
                }
            }

            // 2. Also check if the task itself is a GitHub Issue or Pull Request task subtype
            const selfPrPromise = rv.RunView<mjBizAppsTasksGitHubGitHubPullRequestTaskEntity>({
                EntityName: 'MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks',
                ExtraFilter: `ID = '${taskId}'`,
                ResultType: 'simple',
            });
            const selfIssuePromise = rv.RunView<mjBizAppsTasksGitHubGitHubIssueTaskEntity>({
                EntityName: 'MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks',
                ExtraFilter: `ID = '${taskId}'`,
                ResultType: 'simple',
            });

            const [selfPrRes, selfIssueRes] = await Promise.all([selfPrPromise, selfIssuePromise]);

            if (selfPrRes.Success && Array.isArray(selfPrRes.Results) && selfPrRes.Results.length > 0) {
                prIds.add(taskId);
            }
            if (selfIssueRes.Success && Array.isArray(selfIssueRes.Results) && selfIssueRes.Results.length > 0) {
                issueIds.add(taskId);
            }

            // 3. Batch fetch details for PRs, Issues, and Repositories
            const fetchPromises: Promise<void>[] = [];

            if (prIds.size > 0) {
                const prFilter = Array.from(prIds).map(id => `ID = '${id}'`).join(' OR ');
                fetchPromises.push(
                    rv.RunView<mjBizAppsTasksGitHubGitHubPullRequestTaskEntity>({
                        EntityName: 'MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks',
                        ExtraFilter: prFilter,
                        ResultType: 'simple',
                    }).then(res => {
                        if (res.Success && Array.isArray(res.Results)) {
                            this.LinkedPullRequests = res.Results.map(pr => {
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
                            });
                        }
                    })
                );
            } else {
                this.LinkedPullRequests = [];
            }

            if (issueIds.size > 0) {
                const issueFilter = Array.from(issueIds).map(id => `ID = '${id}'`).join(' OR ');
                fetchPromises.push(
                    rv.RunView<mjBizAppsTasksGitHubGitHubIssueTaskEntity>({
                        EntityName: 'MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks',
                        ExtraFilter: issueFilter,
                        ResultType: 'simple',
                    }).then(res => {
                        if (res.Success && Array.isArray(res.Results)) {
                            this.LinkedIssues = res.Results.map(issue => ({
                                ID: issue.ID,
                                Number: issue.Number ?? null,
                                Title: issue.Name || 'Issue',
                                State: issue.State || 'open',
                                StateLabel: issue.State === 'closed' ? 'Closed' : 'Open',
                                RepositoryName: issue.Repository || 'GitHub Repository',
                                Milestone: issue.Milestone || null,
                                HtmlUrl: issue.HtmlURL || null,
                            }));
                        }
                    })
                );
            } else {
                this.LinkedIssues = [];
            }

            if (repoIds.size > 0) {
                const repoFilter = Array.from(repoIds).map(id => `ID = '${id}'`).join(' OR ');
                fetchPromises.push(
                    rv.RunView<mjBizAppsTasksGitHubGitHubRepositoryEntity>({
                        EntityName: 'MJ_BizApps_Tasks_GitHub: Git Hub Repositories',
                        ExtraFilter: repoFilter,
                        ResultType: 'simple',
                    }).then(res => {
                        if (res.Success && Array.isArray(res.Results)) {
                            this.LinkedRepositories = res.Results.map(repo => {
                                const owner = repo.Owner?.trim() || '';
                                const name = repo.Name?.trim() || '';
                                const fullName = owner && name ? `${owner}/${name}` : name || owner || 'Repository';
                                return {
                                    ID: repo.ID,
                                    FullName: fullName,
                                    DefaultBranch: repo.DefaultBranch || 'main',
                                    IsTracked: Boolean(repo.IsTracked),
                                    HtmlUrl: owner && name ? `https://github.com/${owner}/${name}` : null,
                                };
                            });
                        }
                    })
                );
            } else {
                this.LinkedRepositories = [];
            }

            await Promise.all(fetchPromises);
        } catch {
            // Non-blocking
        } finally {
            this.IsLoading = false;
            this.cdr?.detectChanges();
        }
    }
}
