/**
 * BizApps Tasks GitHub Extension — Angular UI Package (`@mj-biz-apps/tasks-github-ng`)
 *
 * NOTE: Entity classes and types live in `@mj-biz-apps/tasks-github-entities`; import them directly
 * from `@mj-biz-apps/tasks-github-entities` rather than through this package.
 */
import '@mj-biz-apps/tasks-github-entities';

// Import generated form components (triggers @RegisterClass for form components)
import './lib/generated/generated-forms.module.js';

// Form contributions (hero panels & task github links)
import './lib/form-panels/github-tasks-form-panels.module.js';

// Import class registrations manifest
import {
    CLASS_REGISTRATIONS,
    CLASS_REGISTRATIONS_COUNT,
    CLASS_REGISTRATIONS_MANIFEST_LOADED,
    CLASS_REGISTRATIONS_PACKAGES,
} from './lib/generated/class-registrations-manifest.js';

// Re-export manifest
export {
    CLASS_REGISTRATIONS,
    CLASS_REGISTRATIONS_COUNT,
    CLASS_REGISTRATIONS_MANIFEST_LOADED,
    CLASS_REGISTRATIONS_PACKAGES,
};

// Generated forms module and individual form components
export * from './lib/generated/generated-forms.module.js';
export * from './lib/generated/Entities/mjBizAppsTasksGitHubGitHubIdentity/mjbizappstasksgithubgithubidentity.form.component.js';
export * from './lib/generated/Entities/mjBizAppsTasksGitHubGitHubIssueTask/mjbizappstasksgithubgithubissuetask.form.component.js';
export * from './lib/generated/Entities/mjBizAppsTasksGitHubGitHubPullRequestTask/mjbizappstasksgithubgithubpullrequesttask.form.component.js';
export * from './lib/generated/Entities/mjBizAppsTasksGitHubGitHubRepository/mjbizappstasksgithubgithubrepository.form.component.js';

// Form panels
export * from './lib/form-panels/github-tasks-form-panels.module.js';
export * from './lib/form-panels/github-repository-overview.panel.js';
export * from './lib/form-panels/github-pull-request-hero.panel.js';
export * from './lib/form-panels/github-issue-hero.panel.js';
export * from './lib/form-panels/task-github-links.panel.js';

// Modules & Models
export * from './lib/tasks-github.module.js';
export * from './lib/tasks-github-ui.models.js';
export * from './lib/tasks-github-ui.helpers.js';
export * from './lib/components/github-tasks-admin/github-tasks-admin-resource.component.js';
export * from './lib/components/github-task-detail-badge/github-task-detail-badge.component.js';
