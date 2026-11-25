import { readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { describe, expect, it, vi } from 'vitest';
import { Injector, runInInjectionContext } from '@angular/core';
import type {
    IMetadataProvider,
    IRunViewProvider,
    RunViewParams,
    RunViewResult,
    UserInfo,
} from '@memberjunction/core';
import {
    BuildGitHubWorkItemViewModels,
    ClassifyGitHubChecksTone,
    ClassifyGitHubIssueStateTone,
    ClassifyGitHubPullRequestStateTone,
    ClassifyGitHubReviewTone,
    FilterGitHubWorkItems,
    GITHUB_ISSUE_TASKS_ENTITY_NAME,
    GITHUB_PR_TASKS_ENTITY_NAME,
    GitHubTaskDetailBadgeComponent,
    GitHubWorkPanelComponent,
    PULL_OWNED_FIELD_LOCK_NOTICE,
    type GitHubIssueWorkItemInput,
    type GitHubPullRequestWorkItemInput,
    type GitHubWorkItemViewModel,
} from '../public-api.js';

function createMockProvider(options?: {
    prResults?: GitHubPullRequestWorkItemInput[];
    issueResults?: GitHubIssueWorkItemInput[];
    failAll?: boolean;
}): {
    provider: IMetadataProvider;
    runViewProvider: IRunViewProvider;
    seenQueries: RunViewParams[];
    runViewsSpy: ReturnType<typeof vi.fn>;
} {
    const seenQueries: RunViewParams[] = [];
    const currentUser = {
        ID: '99999999-9999-4999-8999-000000000099',
        Email: 'dev@example.com',
        Name: 'Dev User',
        FirstLast: 'Dev User',
    } as UserInfo;

    const runViewsSpy = vi.fn(async (views: RunViewParams[]): Promise<RunViewResult[]> => {
        seenQueries.push(...views);
        return views.map((view) => {
            if (options?.failAll) {
                return {
                    Success: false,
                    Results: [],
                    RowCount: 0,
                    TotalRowCount: 0,
                    ExecutionTime: 1,
                    ErrorMessage: `Failed querying ${view.EntityName}`,
                };
            }
            if (view.EntityName === GITHUB_PR_TASKS_ENTITY_NAME) {
                const rows = options?.prResults ?? [];
                return {
                    Success: true,
                    Results: rows,
                    RowCount: rows.length,
                    TotalRowCount: rows.length,
                    ExecutionTime: 1,
                    ErrorMessage: '',
                };
            }
            if (view.EntityName === GITHUB_ISSUE_TASKS_ENTITY_NAME) {
                const rows = options?.issueResults ?? [];
                return {
                    Success: true,
                    Results: rows,
                    RowCount: rows.length,
                    TotalRowCount: rows.length,
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
        });
    });

    const runViewProvider: Partial<IRunViewProvider> = {
        RunView: vi.fn(async (params: RunViewParams): Promise<RunViewResult> => {
            const [first] = await runViewsSpy([params]);
            return first;
        }),
        RunViews: runViewsSpy,
    };

    const provider: Partial<IMetadataProvider & IRunViewProvider> = {
        ...runViewProvider,
        CurrentUser: currentUser,
        Entities: [],
    };

    return {
        provider: provider as IMetadataProvider,
        runViewProvider: runViewProvider as IRunViewProvider,
        seenQueries,
        runViewsSpy,
    };
}

function attachMockProvider<T extends object>(
    component: T,
    provider: IMetadataProvider,
    runViewProvider: IRunViewProvider,
): void {
    Object.defineProperty(component, 'ProviderToUse', {
        get: () => provider,
        configurable: true,
    });
    Object.defineProperty(component, 'RunViewToUse', {
        get: () => runViewProvider,
        configurable: true,
    });
}

async function flushMicrotasks(): Promise<void> {
    await new Promise<void>((resolveTimer) => setTimeout(resolveTimer, 0));
}

describe('BuildGitHubWorkItemViewModels & tone classification', () => {
    it('classifies PR, issue, review, and CI check tones accurately', () => {
        expect(ClassifyGitHubPullRequestStateTone('open', false)).toBe('success');
        expect(ClassifyGitHubPullRequestStateTone('open', true)).toBe('neutral');
        expect(ClassifyGitHubPullRequestStateTone('merged', false)).toBe('merged');
        expect(ClassifyGitHubPullRequestStateTone('closed', false)).toBe('error');

        expect(ClassifyGitHubIssueStateTone('open', null)).toBe('success');
        expect(ClassifyGitHubIssueStateTone('open', 'reopened')).toBe('success');
        expect(ClassifyGitHubIssueStateTone('closed', 'completed')).toBe('merged');
        expect(ClassifyGitHubIssueStateTone('closed', 'not_planned')).toBe('error');
        expect(ClassifyGitHubIssueStateTone('closed', 'duplicate')).toBe('error');

        expect(ClassifyGitHubReviewTone('APPROVED')).toBe('success');
        expect(ClassifyGitHubReviewTone('CHANGES_REQUESTED')).toBe('error');
        expect(ClassifyGitHubReviewTone('REVIEW_REQUIRED')).toBe('warning');
        expect(ClassifyGitHubReviewTone(null)).toBeNull();

        expect(ClassifyGitHubChecksTone('Passing')).toBe('success');
        expect(ClassifyGitHubChecksTone('Failing')).toBe('error');
        expect(ClassifyGitHubChecksTone('Pending')).toBe('warning');
        expect(ClassifyGitHubChecksTone('Neutral')).toBe('neutral');
        expect(ClassifyGitHubChecksTone(null)).toBeNull();
    });

    it('builds unified view models from both entity-shaped and DTO-shaped PR/Issue inputs and sorts open before closed', () => {
        const items = BuildGitHubWorkItemViewModels({
            repositoryFullName: 'MemberJunction/bizapps-tasks-github',
            pullRequests: [
                {
                    ID: '11111111-1111-4111-8111-111111111101',
                    Name: 'Add work panel widget',
                    Number: 42,
                    State: 'open',
                    IsDraft: false,
                    HtmlURL: 'https://github.com/MemberJunction/bizapps-tasks-github/pull/42',
                    HeadBranch: 'feat/work-panel',
                    BaseBranch: 'next',
                    Additions: 215,
                    Deletions: 18,
                    ChangedFiles: 6,
                    ReviewDecision: 'APPROVED',
                    ChecksStatus: 'Passing',
                    Labels: '["ui","enhancement"]',
                    Milestone: 'v6.3',
                    AuthorLogin: 'octocat',
                    AssigneeDisplay: 'Ada Lovelace',
                    GitHubUpdatedAt: '2026-11-25T15:00:00.000Z',
                },
                {
                    TaskID: '11111111-1111-4111-8111-111111111102',
                    Title: 'Legacy PR merged earlier',
                    Number: 39,
                    State: 'merged',
                    IsDraft: false,
                    HtmlURL: 'https://github.com/MemberJunction/bizapps-tasks-github/pull/39',
                    HeadRef: 'fix/old',
                    BaseRef: 'next',
                    Labels: ['bugfix'],
                    MilestoneTitle: 'v6.2',
                    UpdatedAt: '2026-11-24T12:00:00.000Z',
                },
            ],
            issues: [
                {
                    ID: '22222222-2222-4222-8222-222222222201',
                    Name: 'Support controlled badge mode',
                    Number: 81,
                    State: 'open',
                    HtmlURL: 'https://github.com/MemberJunction/bizapps-tasks-github/issues/81',
                    Labels: '["triage","angular"]',
                    Milestone: 'v6.3',
                    AuthorLogin: 'gracehopper',
                    GitHubUpdatedAt: '2026-11-25T16:00:00.000Z',
                },
                {
                    TaskID: '22222222-2222-4222-8222-222222222202',
                    Title: 'Duplicate tracker',
                    Number: 77,
                    State: 'closed',
                    StateReason: 'duplicate',
                    Labels: ['duplicate'],
                    UpdatedAt: '2026-11-23T09:00:00.000Z',
                },
            ],
        });

        expect(items).toHaveLength(4);

        // Open items sort first, ordered by UpdatedAt descending (#81 at 16:00 before #42 at 15:00)
        expect(items[0]?.Kind).toBe('Issue');
        expect(items[0]?.Number).toBe(81);
        expect(items[0]?.NumberLabel).toBe('Issue #81');
        expect(items[0]?.StateLabel).toBe('Open');
        expect(items[0]?.StateTone).toBe('success');
        expect(items[0]?.Labels).toEqual(['triage', 'angular']);

        expect(items[1]?.Kind).toBe('PullRequest');
        expect(items[1]?.TaskID).toBe('11111111-1111-4111-8111-111111111101');
        expect(items[1]?.NumberLabel).toBe('PR #42');
        expect(items[1]?.StateTone).toBe('success');
        expect(items[1]?.BranchComparisonLabel).toBe('feat/work-panel → next');
        expect(items[1]?.Additions).toBe(215);
        expect(items[1]?.Deletions).toBe(18);
        expect(items[1]?.ChangedFiles).toBe(6);
        expect(items[1]?.DiffStatLabel).toBe('+215 / -18');
        expect(items[1]?.ReviewDecisionLabel).toBe('Approved');
        expect(items[1]?.ReviewTone).toBe('success');
        expect(items[1]?.ChecksStatusLabel).toBe('Checks Passing');
        expect(items[1]?.ChecksTone).toBe('success');
        expect(items[1]?.AssigneeDisplay).toBe('Ada Lovelace');
        expect(items[1]?.Labels).toEqual(['ui', 'enhancement']);

        // Merged & closed items sort after open items
        expect(items[2]?.Number).toBe(39);
        expect(items[2]?.StateTone).toBe('merged');
        expect(items[2]?.DiffStatLabel).toBeNull();
        expect(items[2]?.MilestoneTitle).toBe('v6.2');
        expect(items[2]?.Labels).toEqual(['bugfix']);

        expect(items[3]?.Number).toBe(77);
        expect(items[3]?.StateLabel).toBe('Closed · Duplicate');
        expect(items[3]?.StateTone).toBe('error');

        expect(FilterGitHubWorkItems(items, 'all')).toHaveLength(4);
        expect(FilterGitHubWorkItems(items, 'prs')).toHaveLength(2);
        expect(FilterGitHubWorkItems(items, 'issues')).toHaveLength(2);
    });
});

describe('GitHubTaskDetailBadgeComponent controlled & self-fetching modes', () => {
    it('executes zero RunViews in controlled mode even when taskId/TaskID is also supplied', async () => {
        const injector = Injector.create({ providers: [] });
        const comp = runInInjectionContext(injector, () => new GitHubTaskDetailBadgeComponent());
        const mock = createMockProvider();
        attachMockProvider(comp, mock.provider, mock.runViewProvider);

        // Bind TaskID BEFORE PullRequest (mirroring typical Angular template attribute order)
        comp.TaskID = '33333333-3333-4333-8333-333333333301';
        comp.ShowOwnershipNotice = false;
        comp.PullRequest = {
            ID: '33333333-3333-4333-8333-333333333301',
            Number: 105,
            HtmlURL: 'https://github.com/MemberJunction/bizapps-tasks-github/pull/105',
            State: 'open',
            IsDraft: true,
            Additions: 30,
            Deletions: 4,
            HeadBranch: 'feat/controlled',
            BaseBranch: 'next',
            ChecksStatus: 'Pending',
        };

        await flushMicrotasks();

        expect(mock.runViewsSpy).not.toHaveBeenCalled();
        expect(comp.IsControlledMode).toBe(true);
        expect(comp.taskId).toBe('33333333-3333-4333-8333-333333333301');
        expect(comp.showOwnershipNotice).toBe(false);
        expect(comp.BadgeViewModel?.PullRequest?.NumberLabel).toBe('#105');
        expect(comp.BadgeViewModel?.PullRequest?.StateLabel).toBe('Draft');
        expect(comp.BadgeViewModel?.PullRequest?.ChecksStatusLabel).toBe('Checks Pending');
        expect(comp.BadgeViewModel?.PullOwnedFieldLockNotice).toBe(PULL_OWNED_FIELD_LOCK_NOTICE);
    });

    it('self-fetches Issue & PR subtypes via ProviderToUse when PullRequest and Issue are null', async () => {
        const taskId = '33333333-3333-4333-8333-333333333302';
        const injector = Injector.create({ providers: [] });
        const comp = runInInjectionContext(injector, () => new GitHubTaskDetailBadgeComponent());
        const mock = createMockProvider({
            issueResults: [
                {
                    ID: taskId,
                    Number: 55,
                    HtmlURL: 'https://github.com/MemberJunction/bizapps-tasks-github/issues/55',
                    State: 'open',
                    Labels: '["bug"]',
                },
            ],
        });
        attachMockProvider(comp, mock.provider, mock.runViewProvider);

        comp.taskId = taskId;
        await flushMicrotasks();

        expect(mock.runViewsSpy).toHaveBeenCalledTimes(1);
        expect(mock.seenQueries.map((q) => q.EntityName)).toEqual([
            GITHUB_ISSUE_TASKS_ENTITY_NAME,
            GITHUB_PR_TASKS_ENTITY_NAME,
        ]);
        expect(comp.BadgeViewModel?.Issue?.NumberLabel).toBe('#55');
        expect(comp.BadgeViewModel?.Issue?.Labels).toEqual(['bug']);
    });
});

describe('GitHubWorkPanelComponent', () => {
    const samplePRs: GitHubPullRequestWorkItemInput[] = [
        {
            ID: '44444444-4444-4444-8444-444444444401',
            Name: 'PR Alpha',
            Number: 101,
            State: 'open',
            IsDraft: false,
            HtmlURL: 'https://github.com/MemberJunction/bizapps-tasks-github/pull/101',
            HeadBranch: 'feat/alpha',
            BaseBranch: 'next',
            Additions: 80,
            Deletions: 12,
            ChecksStatus: 'Passing',
            ReviewDecision: 'APPROVED',
            GitHubUpdatedAt: '2026-11-25T18:00:00.000Z',
        },
        {
            ID: '44444444-4444-4444-8444-444444444402',
            Name: 'PR Beta',
            Number: 102,
            State: 'open',
            IsDraft: true,
            HtmlURL: 'https://github.com/MemberJunction/bizapps-tasks-github/pull/102',
            HeadBranch: 'feat/beta',
            BaseBranch: 'next',
            Additions: 10,
            Deletions: 2,
            GitHubUpdatedAt: '2026-11-25T17:00:00.000Z',
        },
        {
            ID: '44444444-4444-4444-8444-444444444403',
            Name: 'PR Gamma',
            Number: 98,
            State: 'merged',
            IsDraft: false,
            HtmlURL: 'https://github.com/MemberJunction/bizapps-tasks-github/pull/98',
            GitHubUpdatedAt: '2026-11-24T10:00:00.000Z',
        },
    ];

    const sampleIssues: GitHubIssueWorkItemInput[] = [
        {
            ID: '55555555-5555-4555-8555-555555555501',
            Name: 'Issue One',
            Number: 201,
            State: 'open',
            HtmlURL: 'https://github.com/MemberJunction/bizapps-tasks-github/issues/201',
            GitHubUpdatedAt: '2026-11-25T16:30:00.000Z',
        },
        {
            ID: '55555555-5555-4555-8555-555555555502',
            Name: 'Issue Two',
            Number: 202,
            State: 'closed',
            StateReason: 'completed',
            HtmlURL: 'https://github.com/MemberJunction/bizapps-tasks-github/issues/202',
            GitHubUpdatedAt: '2026-11-23T12:00:00.000Z',
        },
    ];

    it('renders controlled mode with zero RunViews, supports panel filtering (all/prs/issues), and emits outputs', async () => {
        const injector = Injector.create({ providers: [] });
        const comp = runInInjectionContext(injector, () => new GitHubWorkPanelComponent());
        const mock = createMockProvider();
        attachMockProvider(comp, mock.provider, mock.runViewProvider);

        // Even if RepositoryID is also provided, controlled PullRequests/Issues must suppress RunView
        comp.RepositoryID = '66666666-6666-4666-8666-666666666601';
        comp.PullRequests = samplePRs;
        comp.Issues = sampleIssues;

        await flushMicrotasks();

        expect(mock.runViewsSpy).not.toHaveBeenCalled();
        expect(comp.IsControlledMode).toBe(true);
        expect(comp.TotalCount).toBe(5);
        expect(comp.PullRequestCount).toBe(3);
        expect(comp.IssueCount).toBe(2);
        expect(comp.EffectiveRepositoryFullName).toBe('MemberJunction/bizapps-tasks-github');

        // Filter tabs: all -> prs -> issues
        expect(comp.FilteredItems).toHaveLength(5);
        comp.SetFilter('prs');
        expect(comp.FilteredItems).toHaveLength(3);
        expect(comp.FilteredItems.every((i) => i.Kind === 'PullRequest')).toBe(true);

        comp.SetFilter('issues');
        expect(comp.FilteredItems).toHaveLength(2);
        expect(comp.FilteredItems.every((i) => i.Kind === 'Issue')).toBe(true);

        comp.SetFilter('all');
        expect(comp.FilteredItems).toHaveLength(5);

        // Outputs: ItemClicked & ViewAllClicked
        const clickedItems: GitHubWorkItemViewModel[] = [];
        let viewAllCount = 0;
        comp.ItemClicked.subscribe((item) => clickedItems.push(item));
        comp.ViewAllClicked.subscribe(() => {
            viewAllCount++;
        });

        const firstItem = comp.AllItems[0];
        expect(firstItem).toBeDefined();
        if (firstItem) {
            comp.OnItemClick(firstItem);
            comp.OnItemKeydown(
                { key: 'Enter', preventDefault: vi.fn() },
                firstItem,
            );
        }
        expect(clickedItems).toHaveLength(2);
        expect(clickedItems[0]?.TaskID).toBe(firstItem?.TaskID);

        comp.OnViewAllClick();
        expect(viewAllCount).toBe(1);
    });

    it('supports strip mode truncation via MaxStripItems and accurate pluralized StripCountSummary', () => {
        const injector = Injector.create({ providers: [] });
        const comp = runInInjectionContext(injector, () => new GitHubWorkPanelComponent());

        comp.Mode = 'strip';
        comp.PullRequests = samplePRs;
        comp.Issues = sampleIssues;

        expect(comp.StripCountSummary).toBe('3 PRs · 2 Issues');
        expect(comp.StripItems).toHaveLength(4);
        expect(comp.HiddenStripCount).toBe(1);

        comp.MaxStripItems = 2;
        expect(comp.StripItems).toHaveLength(2);
        expect(comp.HiddenStripCount).toBe(3);

        // Singular formatting check
        comp.PullRequests = [samplePRs[0]];
        comp.Issues = [sampleIssues[0]];
        expect(comp.StripCountSummary).toBe('1 PR · 1 Issue');
        expect(comp.HiddenStripCount).toBe(0);
    });

    it('self-fetches scoped PRs & Issues via RunViews (MaxRows: 200, ResultType: simple) when PullRequests and Issues are null', async () => {
        const repoId = '77777777-7777-4777-8777-777777777701';
        const taskId1 = '44444444-4444-4444-8444-444444444401';
        const injector = Injector.create({ providers: [] });
        const comp = runInInjectionContext(injector, () => new GitHubWorkPanelComponent());
        const mock = createMockProvider({
            prResults: [samplePRs[0]],
            issueResults: [sampleIssues[0]],
        });
        attachMockProvider(comp, mock.provider, mock.runViewProvider);

        comp.RepositoryID = repoId;
        comp.TaskIDs = [taskId1, 'not-a-valid-uuid', taskId1.toUpperCase()];
        await flushMicrotasks();

        expect(mock.runViewsSpy).toHaveBeenCalledTimes(1);
        expect(mock.seenQueries).toHaveLength(2);
        for (const q of mock.seenQueries) {
            expect(q.MaxRows).toBe(200);
            expect(q.ResultType).toBe('simple');
            expect(q.ExtraFilter).toBe(`RepositoryID = '${repoId}' AND ID IN ('${taskId1}')`);
        }
        expect(comp.LoadError).toBeNull();
        expect(comp.TotalCount).toBe(2);
        expect(comp.PullRequestCount).toBe(1);
        expect(comp.IssueCount).toBe(1);
    });

    it('never issues an unscoped full-table scan when RepositoryID and TaskIDs are absent/invalid, and surfaces errors cleanly', async () => {
        const injector = Injector.create({ providers: [] });
        const comp = runInInjectionContext(injector, () => new GitHubWorkPanelComponent());
        const mock = createMockProvider({ failAll: true });
        attachMockProvider(comp, mock.provider, mock.runViewProvider);

        comp.RepositoryID = 'invalid-uuid';
        comp.TaskIDs = ['also-invalid'];
        await flushMicrotasks();

        expect(mock.runViewsSpy).not.toHaveBeenCalled();
        expect(comp.TotalCount).toBe(0);

        // Now pass a valid UUID so self-fetch executes and surfaces error
        comp.RepositoryID = '88888888-8888-4888-8888-888888888801';
        await flushMicrotasks();

        expect(mock.runViewsSpy).toHaveBeenCalledTimes(1);
        expect(comp.LoadError).toContain('Failed querying');
        expect(comp.TotalCount).toBe(0);
    });

    it('enforces pure --mj-* semantic CSS tokens and zero Explorer/Router imports', () => {
        const currentDir = dirname(fileURLToPath(import.meta.url));
        const componentTs = readFileSync(
            resolve(currentDir, '../lib/components/github-work-panel/github-work-panel.component.ts'),
            'utf8',
        );
        const componentCss = readFileSync(
            resolve(currentDir, '../lib/components/github-work-panel/github-work-panel.component.css'),
            'utf8',
        );

        expect(componentTs).not.toContain('@angular/router');
        expect(componentTs).not.toContain('NavigationService');
        expect(componentCss).not.toMatch(/#[0-9a-fA-F]{3,8}\b/);
        expect(componentCss).not.toMatch(/\brgba?\s*\(/i);
        expect(componentCss).not.toMatch(/\bhsla?\s*\(/i);
        expect(componentCss).toContain('var(--mj-');
        expect(componentCss).toContain('@container gh-work-panel');
    });
});
