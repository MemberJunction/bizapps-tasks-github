import { Component, OnInit, ChangeDetectorRef, inject } from '@angular/core';
import { CompositeKey, RunView } from '@memberjunction/core';
import { RegisterClassEx } from '@memberjunction/global';
import { BaseFormPanel } from '@memberjunction/ng-base-forms';
import { NavigationService } from '@memberjunction/ng-shared';
import type { mjBizAppsTasksGitHubGitHubRepositoryEntity } from '@mj-biz-apps/tasks-github-entities';

@RegisterClassEx(BaseFormPanel, {
    key: 'github-tasks:repository-overview-panel',
    skipNullKeyWarning: true,
    metadata: {
        entity: 'MJ_BizApps_Tasks_GitHub: Git Hub Repositories',
        slot: 'before-fields',
        sortKey: 10,
        contributionKey: 'repository-overview',
    },
})
@Component({
    standalone: false,
    selector: 'mj-github-repository-overview-panel',
    templateUrl: './github-repository-overview.panel.html',
    styleUrls: ['./github-form-panels.css'],
})
export class GitHubRepositoryOverviewPanel extends BaseFormPanel<mjBizAppsTasksGitHubGitHubRepositoryEntity> implements OnInit {
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

    public OpenPrCount = 0;
    public OpenIssueCount = 0;
    public IsLoadingCounts = false;

    public async ngOnInit(): Promise<void> {
        await this.loadLiveCounts();
    }

    public get RepositoryFullName(): string {
        const owner = this.Record?.Owner?.trim() || '';
        const name = this.Record?.Name?.trim() || '';
        if (owner && name) return `${owner}/${name}`;
        return name || owner || 'Repository';
    }

    public get DefaultBranch(): string {
        return this.Record?.DefaultBranch?.trim() || 'main';
    }

    public get IsTracked(): boolean {
        return Boolean(this.Record?.IsTracked);
    }

    public get ImportRuleLabel(): string {
        return this.Record?.ImportRule === 'AssignedOnly' ? 'Import: Assigned Only' : 'Import: All';
    }

    public get GitHubUrl(): string | null {
        const owner = this.Record?.Owner?.trim();
        const name = this.Record?.Name?.trim();
        if (owner && name) {
            return `https://github.com/${owner}/${name}`;
        }
        return null;
    }

    public get HasDeliveryPolicy(): boolean {
        return Boolean(this.Record?.DeliveryPolicyID);
    }

    public OpenOnGitHub(): void {
        const url = this.GitHubUrl;
        if (url) {
            window.open(url, '_blank', 'noopener,noreferrer');
        }
    }

    public NavigateToDeliveryPolicy(): void {
        const policyId = this.Record?.DeliveryPolicyID;
        if (!policyId) return;

        const pk = new CompositeKey();
        pk.KeyValuePairs.push({ FieldName: 'ID', Value: policyId });

        if (this.navService) {
            this.navService.OpenEntityRecord('MJ_BizApps_SoftwareFactory: Delivery Policies', pk);
        } else if (this.FormComponent) {
            this.FormComponent.OnFormNavigate({
                Kind: 'record',
                EntityName: 'MJ_BizApps_SoftwareFactory: Delivery Policies',
                PrimaryKey: pk,
            });
        }
    }

    private async loadLiveCounts(): Promise<void> {
        const repoId = this.Record?.ID;
        if (!repoId) return;

        this.IsLoadingCounts = true;
        try {
            const rv = RunView.FromMetadataProvider(this.FormComponent?.ProviderToUse);

            const prPromise = rv.RunView({
                EntityName: 'MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks',
                ExtraFilter: `RepositoryID = '${repoId}' AND State = 'open'`,
                ResultType: 'count_only',
            });

            const issuePromise = rv.RunView({
                EntityName: 'MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks',
                ExtraFilter: `RepositoryID = '${repoId}' AND State = 'open'`,
                ResultType: 'count_only',
            });

            const [prResult, issueResult] = await Promise.all([prPromise, issuePromise]);

            if (prResult.Success) {
                this.OpenPrCount = prResult.TotalRowCount ?? 0;
            }
            if (issueResult.Success) {
                this.OpenIssueCount = issueResult.TotalRowCount ?? 0;
            }
        } catch {
            // Non-blocking for UI render
        } finally {
            this.IsLoadingCounts = false;
            this.cdr?.detectChanges();
        }
    }
}
