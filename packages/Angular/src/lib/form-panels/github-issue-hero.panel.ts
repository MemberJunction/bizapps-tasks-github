import { Component, OnInit, ChangeDetectorRef, inject } from '@angular/core';
import { CompositeKey, RunView } from '@memberjunction/core';
import { RegisterClassEx } from '@memberjunction/global';
import { BaseFormPanel } from '@memberjunction/ng-base-forms';
import { NavigationService } from '@memberjunction/ng-shared';
import type { mjBizAppsTasksGitHubGitHubIssueTaskEntity } from '@mj-biz-apps/tasks-github-entities';
import type { mjBizAppsTasksTaskLinkEntity } from '@mj-biz-apps/tasks-entities';
import { ParseGitHubLabelsJson } from '../tasks-github-ui.helpers.js';

interface LinkedTaskItem {
    TaskID: string;
    TaskName: string;
}

@RegisterClassEx(BaseFormPanel, {
    key: 'github-tasks:issue-hero-panel',
    skipNullKeyWarning: true,
    metadata: {
        entity: 'MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks',
        slot: 'before-fields',
        sortKey: 10,
        contributionKey: 'issue-hero',
    },
})
@Component({
    standalone: false,
    selector: 'mj-github-issue-hero-panel',
    templateUrl: './github-issue-hero.panel.html',
    styleUrls: ['./github-form-panels.css'],
})
export class GitHubIssueHeroPanel extends BaseFormPanel<mjBizAppsTasksGitHubGitHubIssueTaskEntity> implements OnInit {
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

    public get IssueNumberLabel(): string {
        const num = this.Record?.Number;
        return num != null ? `#${num}` : 'Issue';
    }

    public get Title(): string {
        return this.Record?.Name || 'Issue';
    }

    public get State(): 'open' | 'closed' {
        return this.Record?.State || 'open';
    }

    public get StateLabel(): string {
        if (this.State === 'closed') {
            const reason = this.Record?.StateReason;
            if (reason === 'completed') return 'Closed (Completed)';
            if (reason === 'not_planned') return 'Closed (Not Planned)';
            return 'Closed';
        }
        return 'Open';
    }

    public get RepositoryName(): string {
        return this.Record?.Repository?.trim() || 'GitHub Repository';
    }

    public get HasRepositoryLink(): boolean {
        return Boolean(this.Record?.RepositoryID);
    }

    public get Labels(): string[] {
        return ParseGitHubLabelsJson(this.Record?.Labels);
    }

    public get Milestone(): string | null {
        return this.Record?.Milestone?.trim() || null;
    }

    public get AuthorLogin(): string | null {
        return this.Record?.AuthorLogin?.trim() || null;
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

    public NavigateToRepository(): void {
        const repoId = this.Record?.RepositoryID;
        if (!repoId) return;

        const pk = new CompositeKey();
        pk.KeyValuePairs.push({ FieldName: 'ID', Value: repoId });

        if (this.navService) {
            this.navService.OpenEntityRecord('MJ_BizApps_Tasks_GitHub: Git Hub Repositories', pk);
        } else if (this.FormComponent) {
            this.FormComponent.OnFormNavigate({
                Kind: 'record',
                EntityName: 'MJ_BizApps_Tasks_GitHub: Git Hub Repositories',
                PrimaryKey: pk,
            });
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
        const issueTaskId = this.Record?.ID;
        if (!issueTaskId) return;

        this.IsLoadingLinks = true;
        try {
            const rv = RunView.FromMetadataProvider(this.FormComponent?.ProviderToUse);

            const linkResult = await rv.RunView<mjBizAppsTasksTaskLinkEntity>({
                EntityName: 'MJ_BizApps_Tasks: Task Links',
                ExtraFilter: `RecordID = '${issueTaskId}' OR TaskID = '${issueTaskId}'`,
                ResultType: 'simple',
            });

            if (linkResult.Success && Array.isArray(linkResult.Results)) {
                const items: LinkedTaskItem[] = [];
                for (const row of linkResult.Results) {
                    if (row.TaskID && row.TaskID !== issueTaskId) {
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
