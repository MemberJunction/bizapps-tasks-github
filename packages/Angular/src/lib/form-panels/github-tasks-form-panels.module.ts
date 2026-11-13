import { NgModule } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { BaseFormsModule } from '@memberjunction/ng-base-forms';
import { LinkDirectivesModule } from '@memberjunction/ng-link-directives';
import { EntityViewerModule } from '@memberjunction/ng-entity-viewer';

import { GitHubRepositoryOverviewPanel } from './github-repository-overview.panel.js';
import { GitHubPullRequestHeroPanel } from './github-pull-request-hero.panel.js';
import { GitHubIssueHeroPanel } from './github-issue-hero.panel.js';
import { TaskGitHubLinksPanel } from './task-github-links.panel.js';

@NgModule({
    declarations: [
        GitHubRepositoryOverviewPanel,
        GitHubPullRequestHeroPanel,
        GitHubIssueHeroPanel,
        TaskGitHubLinksPanel,
    ],
    imports: [
        CommonModule,
        FormsModule,
        BaseFormsModule,
        LinkDirectivesModule,
        EntityViewerModule,
    ],
    exports: [
        GitHubRepositoryOverviewPanel,
        GitHubPullRequestHeroPanel,
        GitHubIssueHeroPanel,
        TaskGitHubLinksPanel,
    ],
})
export class GitHubTasksFormPanelsModule {}
