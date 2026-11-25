import { NgModule } from '@angular/core';
import { LoadTasksGitHubEntities } from '@mj-biz-apps/tasks-github-entities';
import { GitHubTaskDetailBadgeComponent } from './components/github-task-detail-badge/github-task-detail-badge.component.js';
import { GitHubTasksAdminResource } from './components/github-tasks-admin/github-tasks-admin-resource.component.js';
import { GitHubWorkPanelComponent } from './components/github-work-panel/github-work-panel.component.js';
import { GeneratedFormsModule } from './generated/generated-forms.module.js';
import { CLASS_REGISTRATIONS } from './generated/class-registrations-manifest.js';
import { mjBizAppsTasksGitHubGitHubIdentityFormComponent } from './generated/Entities/mjBizAppsTasksGitHubGitHubIdentity/mjbizappstasksgithubgithubidentity.form.component.js';
import { mjBizAppsTasksGitHubGitHubIssueTaskFormComponent } from './generated/Entities/mjBizAppsTasksGitHubGitHubIssueTask/mjbizappstasksgithubgithubissuetask.form.component.js';
import { mjBizAppsTasksGitHubGitHubPullRequestTaskFormComponent } from './generated/Entities/mjBizAppsTasksGitHubGitHubPullRequestTask/mjbizappstasksgithubgithubpullrequesttask.form.component.js';
import { mjBizAppsTasksGitHubGitHubRepositoryFormComponent } from './generated/Entities/mjBizAppsTasksGitHubGitHubRepository/mjbizappstasksgithubgithubrepository.form.component.js';
import { GitHubTasksFormPanelsModule } from './form-panels/github-tasks-form-panels.module.js';
import { GitHubRepositoryOverviewPanel } from './form-panels/github-repository-overview.panel.js';
import { GitHubPullRequestHeroPanel } from './form-panels/github-pull-request-hero.panel.js';
import { GitHubIssueHeroPanel } from './form-panels/github-issue-hero.panel.js';
import { TaskGitHubLinksPanel } from './form-panels/task-github-links.panel.js';

@NgModule({
    imports: [
        GitHubTasksAdminResource,
        GitHubTaskDetailBadgeComponent,
        GitHubWorkPanelComponent,
        GeneratedFormsModule,
        GitHubTasksFormPanelsModule,
    ],
    exports: [
        GitHubTasksAdminResource,
        GitHubTaskDetailBadgeComponent,
        GitHubWorkPanelComponent,
        GeneratedFormsModule,
        GitHubTasksFormPanelsModule,
    ],
})
export class TasksGitHubAngularModule {}

/**
 * Tree-shaking prevention & client-side startup hook for the BizApps Tasks GitHub Extension.
 * Ensures all `@RegisterClass` entity subclasses and form components remain in the bundle.
 */
export function LoadBizAppsTasksGitHubClient(): void {
    LoadTasksGitHubEntities();
    void CLASS_REGISTRATIONS;
    void mjBizAppsTasksGitHubGitHubIdentityFormComponent;
    void mjBizAppsTasksGitHubGitHubIssueTaskFormComponent;
    void mjBizAppsTasksGitHubGitHubPullRequestTaskFormComponent;
    void mjBizAppsTasksGitHubGitHubRepositoryFormComponent;
    void GitHubTasksAdminResource;
    void GitHubTaskDetailBadgeComponent;
    void GitHubWorkPanelComponent;
    void GitHubRepositoryOverviewPanel;
    void GitHubPullRequestHeroPanel;
    void GitHubIssueHeroPanel;
    void TaskGitHubLinksPanel;
}
