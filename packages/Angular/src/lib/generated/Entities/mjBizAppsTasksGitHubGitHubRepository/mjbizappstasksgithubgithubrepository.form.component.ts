import { Component } from '@angular/core';
import { mjBizAppsTasksGitHubGitHubRepositoryEntity } from '@mj-biz-apps/tasks-github-entities';
import { RegisterClass } from '@memberjunction/global';
import { BaseFormComponent } from '@memberjunction/ng-base-forms';
import {  } from "@memberjunction/ng-entity-viewer"

@RegisterClass(BaseFormComponent, 'MJ_BizApps_Tasks_GitHub: Git Hub Repositories') // Tell MemberJunction about this class
@Component({
    standalone: false,
    selector: 'gen-mjbizappstasksgithubgithubrepository-form',
    templateUrl: './mjbizappstasksgithubgithubrepository.form.component.html'
})
export class mjBizAppsTasksGitHubGitHubRepositoryFormComponent extends BaseFormComponent {
    public record!: mjBizAppsTasksGitHubGitHubRepositoryEntity;

    override async ngOnInit() {
        await super.ngOnInit();
        this.initSections([
            { sectionKey: 'repositoryDetails', sectionName: 'Repository Details', isExpanded: true },
            { sectionKey: 'syncAndImportConfiguration', sectionName: 'Sync and Import Configuration', isExpanded: true },
            { sectionKey: 'integrationAndLinks', sectionName: 'Integration and Links', isExpanded: true },
            { sectionKey: 'systemMetadata', sectionName: 'System Metadata', isExpanded: false },
            { sectionKey: 'mJBizAppsTasksGitHubGitHubIssueTasks', sectionName: 'Git Hub Issue Tasks', isExpanded: false },
            { sectionKey: 'mJBizAppsTasksGitHubGitHubPullRequestTasks', sectionName: 'Git Hub Pull Request Tasks', isExpanded: false }
        ]);
    }
}

