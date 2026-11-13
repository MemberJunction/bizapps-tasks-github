import { Component } from '@angular/core';
import { mjBizAppsTasksGitHubGitHubPullRequestTaskEntity } from '@mj-biz-apps/tasks-github-entities';
import { RegisterClass } from '@memberjunction/global';
import { BaseFormComponent } from '@memberjunction/ng-base-forms';

@RegisterClass(BaseFormComponent, 'MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks') // Tell MemberJunction about this class
@Component({
    standalone: false,
    selector: 'gen-mjbizappstasksgithubgithubpullrequesttask-form',
    templateUrl: './mjbizappstasksgithubgithubpullrequesttask.form.component.html'
})
export class mjBizAppsTasksGitHubGitHubPullRequestTaskFormComponent extends BaseFormComponent {
    public record!: mjBizAppsTasksGitHubGitHubPullRequestTaskEntity;

    override async ngOnInit() {
        await super.ngOnInit();
        this.initSections([
            { sectionKey: 'pullRequestDetails', sectionName: 'Pull Request Details', isExpanded: true },
            { sectionKey: 'statusAndWorkflow', sectionName: 'Status and Workflow', isExpanded: true },
            { sectionKey: 'branchAndCommitInfo', sectionName: 'Branch and Commit Info', isExpanded: true },
            { sectionKey: 'diffMetrics', sectionName: 'Diff Metrics', isExpanded: true },
            { sectionKey: 'datesAndTimeline', sectionName: 'Dates and Timeline', isExpanded: true },
            { sectionKey: 'taskDetails', sectionName: 'Task Details', isExpanded: true },
            { sectionKey: 'taskStatusAndWorkflow', sectionName: 'Task Status and Workflow', isExpanded: true },
            { sectionKey: 'taskTimeline', sectionName: 'Task Timeline', isExpanded: true },
            { sectionKey: 'taskEffortAndMetrics', sectionName: 'Task Effort and Metrics', isExpanded: true },
            { sectionKey: 'taskSLAAndRisk', sectionName: 'Task SLA and Risk', isExpanded: true },
            { sectionKey: 'systemMetadata', sectionName: 'System Metadata', isExpanded: false }
        ]);
    }
}

