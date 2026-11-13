import { Component } from '@angular/core';
import { mjBizAppsTasksGitHubGitHubIssueTaskEntity } from '@mj-biz-apps/tasks-github-entities';
import { RegisterClass } from '@memberjunction/global';
import { BaseFormComponent } from '@memberjunction/ng-base-forms';

@RegisterClass(BaseFormComponent, 'MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks') // Tell MemberJunction about this class
@Component({
    standalone: false,
    selector: 'gen-mjbizappstasksgithubgithubissuetask-form',
    templateUrl: './mjbizappstasksgithubgithubissuetask.form.component.html'
})
export class mjBizAppsTasksGitHubGitHubIssueTaskFormComponent extends BaseFormComponent {
    public record!: mjBizAppsTasksGitHubGitHubIssueTaskEntity;

    override async ngOnInit() {
        await super.ngOnInit();
        this.initSections([
            { sectionKey: 'gitHubIssueDetails', sectionName: 'GitHub Issue Details', isExpanded: true },
            { sectionKey: 'milestoneAndTimeline', sectionName: 'Milestone and Timeline', isExpanded: true },
            { sectionKey: 'syncAndAuditInformation', sectionName: 'Sync and Audit Information', isExpanded: true },
            { sectionKey: 'taskDetails', sectionName: 'Task Details', isExpanded: true },
            { sectionKey: 'taskScheduleAndMetrics', sectionName: 'Task Schedule and Metrics', isExpanded: true },
            { sectionKey: 'systemMetadata', sectionName: 'System Metadata', isExpanded: false }
        ]);
    }
}

