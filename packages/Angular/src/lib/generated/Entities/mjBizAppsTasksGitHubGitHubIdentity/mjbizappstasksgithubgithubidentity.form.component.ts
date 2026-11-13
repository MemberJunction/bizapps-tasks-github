import { Component } from '@angular/core';
import { mjBizAppsTasksGitHubGitHubIdentityEntity } from '@mj-biz-apps/tasks-github-entities';
import { RegisterClass } from '@memberjunction/global';
import { BaseFormComponent } from '@memberjunction/ng-base-forms';

@RegisterClass(BaseFormComponent, 'MJ_BizApps_Tasks_GitHub: Git Hub Identities') // Tell MemberJunction about this class
@Component({
    standalone: false,
    selector: 'gen-mjbizappstasksgithubgithubidentity-form',
    templateUrl: './mjbizappstasksgithubgithubidentity.form.component.html'
})
export class mjBizAppsTasksGitHubGitHubIdentityFormComponent extends BaseFormComponent {
    public record!: mjBizAppsTasksGitHubGitHubIdentityEntity;

    override async ngOnInit() {
        await super.ngOnInit();
        this.initSections([
            { sectionKey: 'gitHubIdentityDetails', sectionName: 'GitHub Identity Details', isExpanded: true },
            { sectionKey: 'systemMetadata', sectionName: 'System Metadata', isExpanded: false }
        ]);
    }
}

