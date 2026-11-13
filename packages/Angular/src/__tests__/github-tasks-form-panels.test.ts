import { describe, expect, it } from 'vitest';
import { MJGlobal } from '@memberjunction/global';
import { BaseFormComponent, BaseFormPanel, FormPanelRegistrationMetadata } from '@memberjunction/ng-base-forms';

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
});
