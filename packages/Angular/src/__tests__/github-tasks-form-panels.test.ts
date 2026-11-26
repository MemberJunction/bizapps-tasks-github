import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import type { IMetadataProvider, IRunViewProvider, RunViewParams, RunViewResult } from '@memberjunction/core';
import { MJGlobal } from '@memberjunction/global';
import { BaseFormComponent, BaseFormPanel, FormPanelRegistrationMetadata } from '@memberjunction/ng-base-forms';
import { GitHubTasksEngineBase } from '@mj-biz-apps/tasks-github-entities';

// Import public-api to trigger all registrations and exports
import {
    CLASS_REGISTRATIONS,
    CLASS_REGISTRATIONS_COUNT,
    GitHubRepositoryOverviewPanel,
    GitHubPullRequestHeroPanel,
    GitHubIssueHeroPanel,
    TaskGitHubLinksPanel,
    mjBizAppsTasksGitHubGitHubIdentityFormComponent,
    mjBizAppsTasksGitHubGitHubIssueTaskFormComponent,
    mjBizAppsTasksGitHubGitHubPullRequestTaskFormComponent,
    mjBizAppsTasksGitHubGitHubRepositoryFormComponent,
} from '../public-api.js';

describe('@mj-biz-apps/tasks-github-ng Form Registrations & Contributions', () => {
    beforeEach(() => {
        GitHubTasksEngineBase.Instance.ResetCaches();
    });

    afterEach(() => {
        GitHubTasksEngineBase.Instance.ResetCaches();
    });

    it('registers all 4 generated forms in ClassFactory under BaseFormComponent', () => {
        const repoForm = MJGlobal.Instance.ClassFactory.GetRegistration(
            BaseFormComponent,
            'MJ_BizApps_Tasks_GitHub: Git Hub Repositories'
        );
        expect(repoForm).toBeDefined();
        expect(repoForm?.SubClass).toBe(mjBizAppsTasksGitHubGitHubRepositoryFormComponent);

        const prForm = MJGlobal.Instance.ClassFactory.GetRegistration(
            BaseFormComponent,
            'MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks'
        );
        expect(prForm).toBeDefined();
        expect(prForm?.SubClass).toBe(mjBizAppsTasksGitHubGitHubPullRequestTaskFormComponent);

        const issueForm = MJGlobal.Instance.ClassFactory.GetRegistration(
            BaseFormComponent,
            'MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks'
        );
        expect(issueForm).toBeDefined();
        expect(issueForm?.SubClass).toBe(mjBizAppsTasksGitHubGitHubIssueTaskFormComponent);

        const identityForm = MJGlobal.Instance.ClassFactory.GetRegistration(
            BaseFormComponent,
            'MJ_BizApps_Tasks_GitHub: Git Hub Identities'
        );
        expect(identityForm).toBeDefined();
        expect(identityForm?.SubClass).toBe(mjBizAppsTasksGitHubGitHubIdentityFormComponent);
    });

    it('registers all 4 BaseFormPanel contributions with correct metadata, slots, and keys', () => {
        const allPanels = MJGlobal.Instance.ClassFactory.GetAllRegistrations(BaseFormPanel);
        expect(allPanels.length).toBeGreaterThanOrEqual(4);

        const repoPanelReg = allPanels.find(p => p.Key === 'github-tasks:repository-overview-panel');
        expect(repoPanelReg).toBeDefined();
        expect(repoPanelReg?.SubClass).toBe(GitHubRepositoryOverviewPanel);
        const repoMeta = repoPanelReg?.Metadata as FormPanelRegistrationMetadata;
        expect(repoMeta.entity).toBe('MJ_BizApps_Tasks_GitHub: Git Hub Repositories');
        expect(repoMeta.slot).toBe('before-fields');
        expect(repoMeta.sortKey).toBe(10);

        const prPanelReg = allPanels.find(p => p.Key === 'github-tasks:pull-request-hero-panel');
        expect(prPanelReg).toBeDefined();
        expect(prPanelReg?.SubClass).toBe(GitHubPullRequestHeroPanel);
        const prMeta = prPanelReg?.Metadata as FormPanelRegistrationMetadata;
        expect(prMeta.entity).toBe('MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks');
        expect(prMeta.slot).toBe('before-fields');
        expect(prMeta.sortKey).toBe(10);

        const issuePanelReg = allPanels.find(p => p.Key === 'github-tasks:issue-hero-panel');
        expect(issuePanelReg).toBeDefined();
        expect(issuePanelReg?.SubClass).toBe(GitHubIssueHeroPanel);
        const issueMeta = issuePanelReg?.Metadata as FormPanelRegistrationMetadata;
        expect(issueMeta.entity).toBe('MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks');
        expect(issueMeta.slot).toBe('before-fields');
        expect(issueMeta.sortKey).toBe(10);

        const taskLinksReg = allPanels.find(p => p.Key === 'github-tasks:task-github-links-panel');
        expect(taskLinksReg).toBeDefined();
        expect(taskLinksReg?.SubClass).toBe(TaskGitHubLinksPanel);
        const taskMeta = taskLinksReg?.Metadata as FormPanelRegistrationMetadata;
        expect(taskMeta.entity).toBe('MJ_BizApps_Tasks: Tasks');
        expect(taskMeta.slot).toBe('after-fields');
        expect(taskMeta.sortKey).toBe(20);
    });

    it('exports CLASS_REGISTRATIONS manifest with expected items and count', () => {
        expect(CLASS_REGISTRATIONS).toBeDefined();
        expect(CLASS_REGISTRATIONS.length).toBe(CLASS_REGISTRATIONS_COUNT);
        expect(CLASS_REGISTRATIONS).toContain(GitHubRepositoryOverviewPanel);
        expect(CLASS_REGISTRATIONS).toContain(GitHubPullRequestHeroPanel);
        expect(CLASS_REGISTRATIONS).toContain(GitHubIssueHeroPanel);
        expect(CLASS_REGISTRATIONS).toContain(TaskGitHubLinksPanel);
        expect(CLASS_REGISTRATIONS).toContain(mjBizAppsTasksGitHubGitHubRepositoryFormComponent);
    });

    it('computes repository overview view-model properties correctly', () => {
        const panel = new GitHubRepositoryOverviewPanel();
        panel.Record = {
            Owner: 'MemberJunction',
            Name: 'MJ',
            DefaultBranch: 'next',
            IsTracked: true,
            ImportRule: 'All',
            DeliveryPolicyID: 'policy-uuid-1',
        } as unknown as typeof panel.Record;

        expect(panel.RepositoryFullName).toBe('MemberJunction/MJ');
        expect(panel.DefaultBranch).toBe('next');
        expect(panel.IsTracked).toBe(true);
        expect(panel.ImportRuleLabel).toBe('Import: All');
        expect(panel.GitHubUrl).toBe('https://github.com/MemberJunction/MJ');
        expect(panel.HasDeliveryPolicy).toBe(true);
    });

    it('computes pull request hero view-model properties correctly', () => {
        const panel = new GitHubPullRequestHeroPanel();
        panel.Record = {
            Number: 42,
            Name: 'Implement Work Bus Event Bridge',
            State: 'open',
            IsDraft: false,
            HeadBranch: 'feat/work-bus',
            BaseBranch: 'next',
            HeadSha: 'a1b2c3d4e5f6g7h8',
            Additions: 300,
            Deletions: 100,
            ChangedFiles: 5,
            HtmlURL: 'https://github.com/MemberJunction/MJ/pull/42',
            ChecksStatus: 'Passing',
            ReviewDecision: 'APPROVED',
        } as unknown as typeof panel.Record;

        expect(panel.PrNumberLabel).toBe('#42');
        expect(panel.Title).toBe('Implement Work Bus Event Bridge');
        expect(panel.State).toBe('open');
        expect(panel.StateLabel).toBe('Open');
        expect(panel.BranchFlow).toBe('feat/work-bus → next');
        expect(panel.ShortHeadSha).toBe('a1b2c3d');
        expect(panel.Additions).toBe(300);
        expect(panel.Deletions).toBe(100);
        expect(panel.ChangedFiles).toBe(5);
        expect(panel.AddPercent).toBe(75);
        expect(panel.DelPercent).toBe(25);
        expect(panel.ChecksStatus).toBe('Passing');
        expect(panel.ReviewDecision).toBe('APPROVED');
        expect(panel.HtmlUrl).toBe('https://github.com/MemberJunction/MJ/pull/42');
    });

    it('computes issue hero view-model properties correctly', () => {
        const panel = new GitHubIssueHeroPanel();
        panel.Record = {
            Number: 108,
            Name: 'Fix left-rail section order and form contributions',
            State: 'closed',
            StateReason: 'completed',
            Repository: 'MemberJunction/MJ',
            RepositoryID: 'repo-uuid-1',
            Labels: '["bug", "ui", "forms"]',
            Milestone: 'v6.3-Sprint-4',
            AuthorLogin: 'octocat',
            HtmlURL: 'https://github.com/MemberJunction/MJ/issues/108',
        } as unknown as typeof panel.Record;

        expect(panel.IssueNumberLabel).toBe('#108');
        expect(panel.Title).toBe('Fix left-rail section order and form contributions');
        expect(panel.State).toBe('closed');
        expect(panel.StateLabel).toBe('Closed (Completed)');
        expect(panel.RepositoryName).toBe('MemberJunction/MJ');
        expect(panel.HasRepositoryLink).toBe(true);
        expect(panel.Labels).toEqual(['bug', 'ui', 'forms']);
        expect(panel.Milestone).toBe('v6.3-Sprint-4');
        expect(panel.AuthorLogin).toBe('octocat');
        expect(panel.HtmlUrl).toBe('https://github.com/MemberJunction/MJ/issues/108');
    });

    it('computes task github links panel counts correctly', () => {
        const panel = new TaskGitHubLinksPanel();
        expect(panel.TotalLinkedItemsCount).toBe(0);
        expect(panel.HasAnyLinkedItems).toBe(false);

        panel.LinkedPullRequests = [{
            ID: 'pr-1',
            Number: 12,
            Title: 'Fix Bug',
            State: 'open',
            StateLabel: 'Open',
            BranchFlow: 'fix → next',
            Additions: 10,
            Deletions: 2,
            HtmlUrl: null,
        }];
        panel.LinkedIssues = [{
            ID: 'issue-1',
            Number: 34,
            Title: 'Reported Issue',
            State: 'open',
            StateLabel: 'Open',
            RepositoryName: 'MemberJunction/MJ',
            Milestone: null,
            HtmlUrl: null,
        }];
        panel.LinkedRepositories = [{
            ID: 'repo-1',
            FullName: 'MemberJunction/MJ',
            DefaultBranch: 'next',
            IsTracked: true,
            HtmlUrl: null,
        }];

        expect(panel.TotalLinkedItemsCount).toBe(3);
        expect(panel.HasAnyLinkedItems).toBe(true);
    });

    it('TaskGitHubLinksPanel batches Phase 1 & Phase 2 via RunViews, avoids redundant double-fetch for self PR/Issue subtype, resolves Repositories from GitHubTasksEngineBase, and validates UUIDs', async () => {
        const taskId = '11111111-1111-4111-8111-111111111111';
        const linkedIssueId = '33333333-3333-4333-8333-333333333333';
        const linkedRepoId = '44444444-4444-4444-8444-444444444444';
        const queries: RunViewParams[] = [];
        const singleRunViewCalls: RunViewParams[] = [];
        const batchRunViewsCalls: RunViewParams[][] = [];

        const resolveView = async (params: RunViewParams): Promise<RunViewResult> => {
            queries.push(params);
            if (params.EntityName === 'MJ_BizApps_Tasks: Task Links') {
                return {
                    Success: true,
                    Results: [
                        // Invalid UUID must be ignored before interpolation
                        { Entity: 'MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks', RecordID: "' OR 1=1 --" },
                        // Self PR link already retrieved in first pass must not trigger a second PR query
                        { Entity: 'MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks', RecordID: taskId },
                        // Linked Issue + Linked Repository resolved in Phase 2
                        { Entity: 'MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks', RecordID: linkedIssueId },
                        { Entity: 'MJ_BizApps_Tasks_GitHub: Git Hub Repositories', RecordID: linkedRepoId },
                    ],
                    RowCount: 4,
                    TotalRowCount: 4,
                    ExecutionTime: 1,
                    ErrorMessage: '',
                };
            }
            if (params.EntityName === 'MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks') {
                return {
                    Success: true,
                    Results: [
                        {
                            ID: taskId,
                            Number: 99,
                            Name: 'Self PR Task',
                            State: 'open',
                            IsDraft: false,
                            HeadBranch: 'feat/tx',
                            BaseBranch: 'next',
                            Additions: 42,
                            Deletions: 7,
                            HtmlURL: 'https://github.com/MemberJunction/bizapps-tasks-github/pull/99',
                        },
                    ],
                    RowCount: 1,
                    TotalRowCount: 1,
                    ExecutionTime: 1,
                    ErrorMessage: '',
                };
            }
            if (
                params.EntityName === 'MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks' &&
                params.ExtraFilter?.includes(linkedIssueId)
            ) {
                return {
                    Success: true,
                    Results: [
                        {
                            ID: linkedIssueId,
                            Number: 12,
                            Name: 'Linked Issue',
                            State: 'open',
                            Repository: 'MemberJunction/bizapps-tasks-github',
                            Milestone: 'v6.3',
                            HtmlURL: 'https://github.com/MemberJunction/bizapps-tasks-github/issues/12',
                        },
                    ],
                    RowCount: 1,
                    TotalRowCount: 1,
                    ExecutionTime: 1,
                    ErrorMessage: '',
                };
            }
            if (params.EntityName === 'MJ_BizApps_Tasks_GitHub: Git Hub Repositories') {
                return {
                    Success: true,
                    Results: [
                        {
                            ID: linkedRepoId,
                            Owner: 'MemberJunction',
                            Name: 'bizapps-tasks-github',
                            DefaultBranch: 'next',
                            IsTracked: true,
                        },
                    ],
                    RowCount: 1,
                    TotalRowCount: 1,
                    ExecutionTime: 1,
                    ErrorMessage: '',
                };
            }
            return {
                Success: true,
                Results: [],
                RowCount: 0,
                TotalRowCount: 0,
                ExecutionTime: 1,
                ErrorMessage: '',
            };
        };

        const mockProvider: Partial<IMetadataProvider & IRunViewProvider> = {
            Entities: [],
            RunView: vi.fn(async (params: RunViewParams): Promise<RunViewResult> => {
                singleRunViewCalls.push(params);
                return resolveView(params);
            }),
            RunViews: vi.fn(async (views: RunViewParams[]): Promise<RunViewResult[]> => {
                batchRunViewsCalls.push(views);
                return Promise.all(views.map((v) => resolveView(v)));
            }),
        };

        const panel = new TaskGitHubLinksPanel();
        panel.FormComponent = {
            ProviderToUse: mockProvider,
        } as typeof panel.FormComponent;
        panel.Record = { ID: taskId } as typeof panel.Record;

        await panel.ngOnInit();

        // Zero individual RunView calls — everything is batched via RunViews!
        expect(singleRunViewCalls).toHaveLength(0);
        // Phase 1 batch has Task Links + self PR + self Issue in a SINGLE RunViews call
        expect(batchRunViewsCalls[0]).toHaveLength(3);

        const prQueries = queries.filter(
            (q) => q.EntityName === 'MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks',
        );
        // Only ONE PR query (the initial self check); zero redundant second fetch!
        expect(prQueries).toHaveLength(1);
        expect(panel.LinkedPullRequests).toHaveLength(1);
        expect(panel.LinkedPullRequests[0]?.Number).toBe(99);
        expect(panel.LinkedPullRequests[0]?.BranchFlow).toBe('feat/tx → next');
        expect(panel.LinkedIssues).toHaveLength(1);
        expect(panel.LinkedIssues[0]?.Number).toBe(12);
        expect(panel.LinkedRepositories).toHaveLength(1);
        expect(panel.LinkedRepositories[0]?.FullName).toBe('MemberJunction/bizapps-tasks-github');

        // Re-running ngOnInit reuses warm GitHubTasksEngineBase cache (zero new Git Hub Repositories queries!)
        queries.length = 0;
        await panel.ngOnInit();
        expect(queries.filter((q) => q.EntityName === 'MJ_BizApps_Tasks_GitHub: Git Hub Repositories')).toHaveLength(0);

        // Reject invalid non-UUID Record.ID with zero queries
        queries.length = 0;
        panel.Record = { ID: "invalid' OR 1=1--" } as typeof panel.Record;
        await panel.ngOnInit();
        expect(queries).toHaveLength(0);
    });

    it('GitHubRepositoryOverviewPanel reuses loaded IssueTasks/PullRequestTasks collections, batches count_only via single RunViews, and rejects invalid UUIDs', async () => {
        const repoId = '22222222-2222-4222-8222-222222222222';
        const queries: RunViewParams[] = [];
        const singleRunViewCalls: RunViewParams[] = [];
        const batchRunViewsCalls: RunViewParams[][] = [];

        const mockProvider: Partial<IRunViewProvider> = {
            RunView: vi.fn(async (params: RunViewParams): Promise<RunViewResult> => {
                singleRunViewCalls.push(params);
                queries.push(params);
                return {
                    Success: true,
                    Results: [],
                    RowCount: 0,
                    TotalRowCount: 4,
                    ExecutionTime: 1,
                    ErrorMessage: '',
                };
            }),
            RunViews: vi.fn(async (views: RunViewParams[]): Promise<RunViewResult[]> => {
                batchRunViewsCalls.push(views);
                queries.push(...views);
                return views.map(() => ({
                    Success: true,
                    Results: [],
                    RowCount: 0,
                    TotalRowCount: 4,
                    ExecutionTime: 1,
                    ErrorMessage: '',
                }));
            }),
        };

        const panel = new GitHubRepositoryOverviewPanel();
        panel.FormComponent = {
            ProviderToUse: mockProvider,
        } as typeof panel.FormComponent;

        type OverviewPanelRecord = typeof panel.Record;
        const makeRepoRecord = (
            id: string,
            issueItems: Array<{ State: 'open' | 'closed' }>,
            prItems: Array<{ State: 'open' | 'closed' | 'merged' }>,
            isLoaded: boolean,
        ): OverviewPanelRecord =>
            ({
                ID: id,
                Owner: 'MemberJunction',
                Name: 'bizapps-tasks-github',
                IssueTasks: { IsLoaded: isLoaded, Items: issueItems },
                PullRequestTasks: { IsLoaded: isLoaded, Items: prItems },
            }) as OverviewPanelRecord;

        // 1. Pre-loaded RelatedRecordCollections compute counts with ZERO DB queries
        panel.Record = makeRepoRecord(
            repoId,
            [{ State: 'open' }, { State: 'closed' }, { State: 'open' }],
            [{ State: 'open' }, { State: 'merged' }],
            true,
        );

        await panel.ngOnInit();
        expect(queries).toHaveLength(0);
        expect(panel.OpenIssueCount).toBe(2);
        expect(panel.OpenPrCount).toBe(1);

        // 2. Invalid non-UUID ID issues zero queries
        panel.Record = makeRepoRecord("not-a-uuid'; DROP TABLE x;--", [], [], false);
        await panel.ngOnInit();
        expect(queries).toHaveLength(0);

        // 3. Unloaded collections fall back to ONE batched RunViews call of 2 count_only queries
        panel.Record = makeRepoRecord(repoId, [], [], false);
        await panel.ngOnInit();
        expect(singleRunViewCalls).toHaveLength(0);
        expect(batchRunViewsCalls).toHaveLength(1);
        expect(batchRunViewsCalls[0]).toHaveLength(2);
        expect(queries).toHaveLength(2);
        expect(queries.every((q) => q.ResultType === 'count_only')).toBe(true);
        expect(panel.OpenIssueCount).toBe(4);
        expect(panel.OpenPrCount).toBe(4);
    });

    it('GitHubIssueHeroPanel and GitHubPullRequestHeroPanel skip RunView when Record.ID is not a valid UUID', async () => {
        const queries: RunViewParams[] = [];
        const mockProvider: Partial<IRunViewProvider> = {
            RunView: vi.fn(async (params: RunViewParams): Promise<RunViewResult> => {
                queries.push(params);
                return {
                    Success: true,
                    Results: [],
                    RowCount: 0,
                    TotalRowCount: 0,
                    ExecutionTime: 1,
                    ErrorMessage: '',
                };
            }),
        };

        const issuePanel = new GitHubIssueHeroPanel();
        issuePanel.FormComponent = { ProviderToUse: mockProvider } as typeof issuePanel.FormComponent;
        issuePanel.Record = { ID: "bad'id" } as typeof issuePanel.Record;
        await issuePanel.ngOnInit();

        const prPanel = new GitHubPullRequestHeroPanel();
        prPanel.FormComponent = { ProviderToUse: mockProvider } as typeof prPanel.FormComponent;
        prPanel.Record = { ID: "bad'id" } as typeof prPanel.Record;
        await prPanel.ngOnInit();

        expect(queries).toHaveLength(0);
    });
});
