import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

import { LoadTasksGitHubEntities } from '@mj-biz-apps/tasks-github-entities';
import { LoadTasksGitHubActions } from '@mj-biz-apps/tasks-github-actions';
import '@mj-biz-apps/tasks-github-core';
import './generated/generated.js';

import { GitHubTasksWebhookServerExtension } from './webhookMiddleware.js';

export * from './generated/generated.js';
export * from './webhookMiddleware.js';

const __dirname = fileURLToPath(new URL('.', import.meta.url));

export const RESOLVER_PATHS: string[] = [
    resolve(__dirname, 'generated/*.js'),
    resolve(__dirname, 'generated/graphql-schemas/*.js'),
];

export function LoadBizAppsTasksGitHubServer(): void {
    LoadTasksGitHubEntities();
    LoadTasksGitHubActions();
    void GitHubTasksWebhookServerExtension;
}
