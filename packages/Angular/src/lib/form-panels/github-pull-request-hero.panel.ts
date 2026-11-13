import { Component, OnInit, ChangeDetectorRef, inject } from '@angular/core';
import { CompositeKey, RunView } from '@memberjunction/core';
import { RegisterClassEx } from '@memberjunction/global';
import { BaseFormPanel } from '@memberjunction/ng-base-forms';
import { NavigationService } from '@memberjunction/ng-shared';
import type { mjBizAppsTasksGitHubGitHubPullRequestTaskEntity } from '@mj-biz-apps/tasks-github-entities';
import type { mjBizAppsTasksTaskLinkEntity } from '@mj-biz-apps/tasks-entities';

interface LinkedTaskItem {
    TaskID: string;
    TaskName: string;
    TaskStatus?: string;
}

@RegisterClassEx(BaseFormPanel, {
    key: 'github-tasks:pull-request-hero-panel',
    skipNullKeyWarning: true,
    metadata: {
        entity: 'MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks',
        slot: 'before-fields',
        sortKey: 10,
        contributionKey: 'pull-request-hero',
    },
})
@Component({
    standalone: false,
    selector: 'mj-github-pull-request-hero-panel',
    templateUrl: './github-pull-request-hero.panel.html',
    styleUrls: ['./github-form-panels.css'],
})
export class GitHubPullRequestHeroPanel extends BaseFormPanel<mjBizAppsTasksGitHubGitHubPullRequestTaskEntity> implements OnInit {
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

    public LinkedTasks: LinkedTaskItem[] = [];
    public IsLoadingLinks = false;

    public async ngOnInit(): Promise<void> {
        await this.loadLinkedTasks();
    }

    public get PrNumberLabel(): string {
        const num = this.Record?.Number;
        return num != null ? `#${num}` : 'PR';
    }

    public get Title(): string {
        return this.Record?.Name || 'Pull Request';
    }

    public get State(): 'open' | 'merged' | 'closed' | 'draft' {
        if (this.Record?.IsDraft && this.Record?.State === 'open') {
            return 'draft';
        }
        return this.Record?.State || 'open';
    }

    public get StateLabel(): string {
        switch (this.State) {
            case 'draft': return 'Draft';
            case 'merged': return 'Merged';
            case 'closed': return 'Closed';
            case 'open':
            default:
                return 'Open';
        }
    }

    public get HeadBranch(): string {
        return this.Record?.HeadBranch?.trim() || '';
    }

    public get BaseBranch(): string {
        return this.Record?.BaseBranch?.trim() || '';
    }

    public get BranchFlow(): string {
        if (this.HeadBranch && this.BaseBranch) {
            return `${this.HeadBranch} → ${this.BaseBranch}`;
        }
        return this.HeadBranch || this.BaseBranch || '—';
    }

    public get ShortHeadSha(): string | null {
        const sha = this.Record?.HeadSha?.trim();
        return sha ? sha.substring(0, 7) : null;
    }

    public get Additions(): number {
        return typeof this.Record?.Additions === 'number' ? this.Record.Additions : 0;
    }

    public get Deletions(): number {
        return typeof this.Record?.Deletions === 'number' ? this.Record.Deletions : 0;
    }

    public get ChangedFiles(): number {
        return typeof this.Record?.ChangedFiles === 'number' ? this.Record.ChangedFiles : 0;
    }

    public get AddPercent(): number {
        const total = this.Additions + this.Deletions;
        if (total === 0) return 50;
        return Math.max(10, Math.min(90, Math.round((this.Additions / total) * 100)));
    }

    public get DelPercent(): number {
        return 100 - this.AddPercent;
    }

    public get ReviewDecision(): string | null {
        return this.Record?.ReviewDecision || null;
    }

    public get ChecksStatus(): string | null {
        return this.Record?.ChecksStatus || null;
    }

    public get HtmlUrl(): string | null {
        return this.Record?.HtmlURL?.trim() || null;
    }

    public OpenOnGitHub(): void {
        const url = this.HtmlUrl;
        if (url) {
            window.open(url, '_blank', 'noopener,noreferrer');
        }
    }

    public NavigateToTask(taskId: string): void {
        if (!taskId) return;
        const pk = new CompositeKey();
        pk.KeyValuePairs.push({ FieldName: 'ID', Value: taskId });

        if (this.navService) {
            this.navService.OpenEntityRecord('MJ_BizApps_Tasks: Tasks', pk);
        } else if (this.FormComponent) {
            this.FormComponent.OnFormNavigate({
                Kind: 'record',
                EntityName: 'MJ_BizApps_Tasks: Tasks',
                PrimaryKey: pk,
            });
        }
    }

    private async loadLinkedTasks(): Promise<void> {
        const prTaskId = this.Record?.ID;
        if (!prTaskId) return;

        this.IsLoadingLinks = true;
        try {
            const rv = RunView.FromMetadataProvider(this.FormComponent?.ProviderToUse);

            // Fetch any task links where RecordID = prTaskId or TaskID = prTaskId
            const linkResult = await rv.RunView<mjBizAppsTasksTaskLinkEntity>({
                EntityName: 'MJ_BizApps_Tasks: Task Links',
                ExtraFilter: `RecordID = '${prTaskId}' OR TaskID = '${prTaskId}'`,
                ResultType: 'simple',
            });

            if (linkResult.Success && Array.isArray(linkResult.Results)) {
                const items: LinkedTaskItem[] = [];
                for (const row of linkResult.Results) {
                    if (row.TaskID && row.TaskID !== prTaskId) {
                        items.push({
                            TaskID: row.TaskID,
                            TaskName: row.Task || 'Linked Task',
                        });
                    }
                }
                this.LinkedTasks = items;
            }
        } catch {
            // Non-blocking
        } finally {
            this.IsLoadingLinks = false;
            this.cdr?.detectChanges();
        }
    }
}
