import {
    HandleGitHubWebhookAction,
    InferGitHubTaskFieldsAction,
    SyncGitHubRepositoryTasksAction,
} from './GitHubTasksActions.js';
import {
    GetGitHubReviewsWaitingOnMeAction,
    GetMyGitHubBriefingAction,
    GetMyGitHubPRsAction,
} from './GitHubCoSActions.js';

export * from './GitHubTasksActions.js';
export * from './GitHubCoSActions.js';

const REGISTERED_GITHUB_ACTIONS = [
    SyncGitHubRepositoryTasksAction,
    HandleGitHubWebhookAction,
    InferGitHubTaskFieldsAction,
    GetMyGitHubPRsAction,
    GetGitHubReviewsWaitingOnMeAction,
    GetMyGitHubBriefingAction,
] as const;

export function LoadTasksGitHubActions(): void {
    // Forces all GitHub Tasks action class registrations to survive bundler tree-shaking
    void REGISTERED_GITHUB_ACTIONS;
}
