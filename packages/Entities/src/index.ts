export * from './generated/entity_subclasses.js';

/**
 * Forces the GitHub Tasks entity subclasses to remain in the bundle despite tree-shaking.
 */
export function LoadTasksGitHubEntities(): void {
    // Side-effect registration via './generated/entity_subclasses.js'
}
