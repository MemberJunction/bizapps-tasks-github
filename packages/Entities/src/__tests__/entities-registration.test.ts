import { describe, expect, it } from 'vitest';
import { MJGlobal } from '@memberjunction/global';
import { BaseEntity } from '@memberjunction/core';
import {
    LoadTasksGitHubEntities,
    mjBizAppsTasksGitHubGitHubIdentityEntity,
    mjBizAppsTasksGitHubGitHubIssueTaskEntity,
    mjBizAppsTasksGitHubGitHubPullRequestTaskEntity,
    mjBizAppsTasksGitHubGitHubRepositoryEntity,
} from '../index.js';

describe('BizApps Tasks GitHub Entities Registration', () => {
    it('registers all four GitHub extension entity classes with ClassFactory', () => {
        LoadTasksGitHubEntities();
        const factory = MJGlobal.Instance.ClassFactory;

        expect(factory.GetRegistration(BaseEntity, 'MJ_BizApps_Tasks_GitHub: Git Hub Repositories')?.SubClass)
            .toBe(mjBizAppsTasksGitHubGitHubRepositoryEntity);
        expect(factory.GetRegistration(BaseEntity, 'MJ_BizApps_Tasks_GitHub: Git Hub Identities')?.SubClass)
            .toBe(mjBizAppsTasksGitHubGitHubIdentityEntity);
        expect(factory.GetRegistration(BaseEntity, 'MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks')?.SubClass)
            .toBe(mjBizAppsTasksGitHubGitHubIssueTaskEntity);
        expect(factory.GetRegistration(BaseEntity, 'MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks')?.SubClass)
            .toBe(mjBizAppsTasksGitHubGitHubPullRequestTaskEntity);
    });
});
