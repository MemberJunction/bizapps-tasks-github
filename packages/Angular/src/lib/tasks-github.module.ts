import { NgModule } from '@angular/core';
import { LoadTasksGitHubEntities } from '@mj-biz-apps/tasks-github-entities';
import { GitHubTaskDetailBadgeComponent } from './components/github-task-detail-badge/github-task-detail-badge.component.js';
import { GitHubTasksAdminResource } from './components/github-tasks-admin/github-tasks-admin-resource.component.js';

@NgModule({
    imports: [GitHubTasksAdminResource, GitHubTaskDetailBadgeComponent],
    exports: [GitHubTasksAdminResource, GitHubTaskDetailBadgeComponent],
})
export class TasksGitHubAngularModule {}

/**
 * Tree-shaking prevention & client-side startup hook for the BizApps Tasks GitHub Extension.
 * Ensures all `@RegisterClass` entity subclasses and `GitHubTasksAdminResource` remain in the bundle.
 */
export function LoadBizAppsTasksGitHubClient(): void {
    LoadTasksGitHubEntities();
    void GitHubTasksAdminResource;
    void GitHubTaskDetailBadgeComponent;
}
