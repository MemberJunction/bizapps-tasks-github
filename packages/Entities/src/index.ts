export * from './generated/entity_subclasses.js';
export * from './GitHubTasksEngineBase.js';

import { GitHubTasksEngineBase } from './GitHubTasksEngineBase.js';

/**
 * Forces the GitHub Tasks entity subclasses and engine to remain in the bundle despite tree-shaking.
 */
export function LoadTasksGitHubEntities(): void {
    // Side-effect registration via './generated/entity_subclasses.js' and './GitHubTasksEngineBase.js'
    void GitHubTasksEngineBase;
}
