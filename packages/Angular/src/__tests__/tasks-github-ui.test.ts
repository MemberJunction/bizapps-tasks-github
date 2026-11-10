import { describe, expect, it } from 'vitest';
import {
    BuildGitHubIssueBadgeViewModel,
    BuildGitHubPullRequestBadgeViewModel,
    BuildGitHubTaskDetailBadgeViewModel,
    BuildGitHubTasksAdminAgentContext,
    BuildIdentityMappingViewModel,
    BuildTrackedRepositoryCards,
    BuildWebhookDeliveryRows,
    ExtractRepoFullNameFromHtmlUrl,
    FilterTrackedRepositoryCards,
    LoadBizAppsTasksGitHubClient,
    PULL_OWNED_FIELD_LOCK_NOTICE,
    ParseGitHubLabelsJson,
    ParseGitHubTasksAdminTab,
    TasksGitHubAngularModule,
    ValidateGitHubUsername,
} from '../public-api.js';

describe('@mj-biz-apps/tasks-github-ng UI helpers & view-model builders', () => {
    describe('ValidateGitHubUsername', () => {
        it('accepts valid 1-to-39 char alphanumeric and single-hyphen GitHub handles', () => {
            expect(ValidateGitHubUsername('octocat')).toEqual({
                IsValid: true,
                NormalizedLogin: 'octocat',
                ErrorMessage: null,
            });
            expect(ValidateGitHubUsername('  mj-bot-2026  ')).toEqual({
                IsValid: true,
                NormalizedLogin: 'mj-bot-2026',
                ErrorMessage: null,
            });
            expect(ValidateGitHubUsername('a')).toEqual({
                IsValid: true,
                NormalizedLogin: 'a',
                ErrorMessage: null,
            });
            expect(ValidateGitHubUsername('a'.repeat(39)).IsValid).toBe(true);
        });

        it('rejects empty, leading/trailing hyphen, consecutive hyphen, @-prefixed, and >39 char handles', () => {
            expect(ValidateGitHubUsername('').IsValid).toBe(false);
            expect(ValidateGitHubUsername('   ').IsValid).toBe(false);
            expect(ValidateGitHubUsername('-octocat').IsValid).toBe(false);
            expect(ValidateGitHubUsername('octocat-').IsValid).toBe(false);
            expect(ValidateGitHubUsername('octo--cat').IsValid).toBe(false);
            expect(ValidateGitHubUsername('@octocat').IsValid).toBe(false);
            expect(ValidateGitHubUsername('octo_cat').IsValid).toBe(false);
            expect(ValidateGitHubUsername('a'.repeat(40)).IsValid).toBe(false);
        });
    });

    describe('BuildIdentityMappingViewModel', () => {
        const people = [
            {
                ID: '11111111-1111-4111-8111-111111111111',
                FirstName: 'Ada',
                LastName: 'Lovelace',
                Email: 'ada@example.com',
                Status: 'Active',
            },
            {
                ID: '22222222-2222-4222-8222-222222222222',
                FirstName: 'Grace',
                LastName: 'Hopper',
                Email: 'grace@example.com',
                Status: 'Active',
            },
        ];

        const identities = [
            {
                ID: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
                PersonID: '11111111-1111-4111-8111-111111111111',
                GitHubLogin: 'adalovelace',
                GitHubUserID: '10101',
                IsActive: true,
                OAuthTokenCredentialID: 'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
            },
        ];

        it('resolves Email -> Person -> GitHubIdentity as Linked with OAuth3LO when OAuthTokenCredentialID is populated', () => {
            const vm = BuildIdentityMappingViewModel({
                currentUser: {
                    ID: '99999999-9999-4999-8999-999999999999',
                    Email: 'ADA@EXAMPLE.COM',
                    FirstLast: 'Ada Lovelace',
                },
                people,
                identities,
            });

            expect(vm.LinkStatus).toBe('Linked');
            expect(vm.PersonID).toBe('11111111-1111-4111-8111-111111111111');
            expect(vm.IdentityID).toBe('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');
            expect(vm.GitHubLogin).toBe('adalovelace');
            expect(vm.OAuthTokenCredentialID).toBe('cccccccc-cccc-4ccc-8ccc-cccccccccccc');
            expect(vm.VaultAuthStatus).toBe('OAuth3LO');
        });

        it('computes Unlinked and AppFallback when Person exists without an active GitHubIdentity or 3LO token', () => {
            const vm = BuildIdentityMappingViewModel({
                currentUser: {
                    ID: '88888888-8888-4888-8888-888888888888',
                    Email: 'grace@example.com',
                    FirstLast: 'Grace Hopper',
                },
                people,
                identities,
            });

            expect(vm.LinkStatus).toBe('Unlinked');
            expect(vm.PersonID).toBe('22222222-2222-4222-8222-222222222222');
            expect(vm.PersonDisplayName).toBe('Grace Hopper');
            expect(vm.IdentityID).toBeNull();
            expect(vm.GitHubLogin).toBeNull();
            expect(vm.VaultAuthStatus).toBe('AppFallback');
            expect(vm.OAuthTokenCredentialID).toBeNull();
        });

        it('computes PersonNotFound when signed-in user matches no People record', () => {
            const vm = BuildIdentityMappingViewModel({
                currentUser: {
                    ID: '77777777-7777-4777-8777-777777777777',
                    Email: 'nobody@example.com',
                },
                people,
                identities,
            });

            expect(vm.LinkStatus).toBe('PersonNotFound');
            expect(vm.PersonID).toBeNull();
            expect(vm.IdentityID).toBeNull();
            expect(vm.GitHubLogin).toBeNull();
            expect(vm.VaultAuthStatus).toBe('AppFallback');
        });
    });

    describe('BuildTrackedRepositoryCards & FilterTrackedRepositoryCards', () => {
        const ciMirrorId = '10000000-0000-4000-8000-000000000001';
        const ciRestOnlyId = '10000000-0000-4000-8000-000000000002';
        const repoMirrorId = '20000000-0000-4000-8000-000000000001';
        const repoRestId = '20000000-0000-4000-8000-000000000002';

        it('marks repositories with active @memberjunction/connector-github Entity Maps as ConnectorMirror and others as GitHubREST', () => {
            const cards = BuildTrackedRepositoryCards({
                repositories: [
                    {
                        ID: repoRestId,
                        Owner: 'AcmeCorp',
                        Name: 'legacy-portal',
                        DefaultBranch: 'main',
                        IsTracked: false,
                        ImportRule: 'All',
                        CompanyIntegrationID: ciRestOnlyId,
                    },
                    {
                        ID: repoMirrorId,
                        Owner: 'MemberJunction',
                        Name: 'bizapps-tasks-github',
                        DefaultBranch: 'next',
                        IsTracked: true,
                        ImportRule: 'AssignedOnly',
                        DefaultProjectID: '30000000-0000-4000-8000-000000000009',
                    },
                ],
                companyIntegrations: [
                    {
                        ID: ciMirrorId,
                        Integration: 'GitHub',
                        IsActive: true,
                        Configuration: JSON.stringify({ owner: 'MemberJunction' }),
                    },
                    {
                        ID: ciRestOnlyId,
                        Integration: 'GitHub',
                        IsActive: true,
                        Configuration: JSON.stringify({ owner: 'AcmeCorp' }),
                    },
                ],
                entityMaps: [
                    {
                        ID: '40000000-0000-4000-8000-000000000001',
                        CompanyIntegrationID: ciMirrorId,
                        ExternalObjectName: 'issues',
                        SyncEnabled: true,
                        Status: 'Active',
                    },
                    {
                        ID: '40000000-0000-4000-8000-000000000002',
                        CompanyIntegrationID: ciRestOnlyId,
                        ExternalObjectName: 'issues',
                        SyncEnabled: false,
                        Status: 'Inactive',
                    },
                ],
                lastSyncedByRepositoryID: {
                    [repoMirrorId]: '2026-11-10T15:00:00.000Z',
                },
            });

            // Tracked repositories sort ahead of untracked repositories
            expect(cards).toHaveLength(2);
            expect(cards[0]?.FullName).toBe('MemberJunction/bizapps-tasks-github');
            expect(cards[0]?.CompanyIntegrationID).toBe(ciMirrorId);
            expect(cards[0]?.DefaultProjectID).toBe('30000000-0000-4000-8000-000000000009');
            expect(cards[0]?.SyncSourceBadge).toBe('ConnectorMirror');
            expect(cards[0]?.LastSyncedAt).toBe('2026-11-10T15:00:00.000Z');

            expect(cards[1]?.FullName).toBe('AcmeCorp/legacy-portal');
            expect(cards[1]?.SyncSourceBadge).toBe('GitHubREST');
            expect(cards[1]?.LastSyncedAt).toBeNull();
            expect(cards[1]?.LastSyncedDisplay).toBe('Never synced');

            // Filtering by tracking state and search query
            expect(FilterTrackedRepositoryCards(cards, 'tracked', '')).toHaveLength(1);
            expect(FilterTrackedRepositoryCards(cards, 'untracked', '')).toHaveLength(1);
            expect(FilterTrackedRepositoryCards(cards, 'all', 'connectormirror')).toHaveLength(1);
            expect(FilterTrackedRepositoryCards(cards, 'all', 'nonexistent')).toHaveLength(0);
        });
    });

    describe('BuildGitHubTaskDetailBadgeViewModel & label parsing', () => {
        it('formats GitHubIssueTask and GitHubPullRequestTask detail badges with diff stats, branches, checks, reviews, and lock notice', () => {
            expect(ParseGitHubLabelsJson('["bug", {"name":"priority:high"}]')).toEqual([
                'bug',
                'priority:high',
            ]);
            expect(ParseGitHubLabelsJson('enhancement, ui')).toEqual(['enhancement', 'ui']);
            expect(
                ExtractRepoFullNameFromHtmlUrl('https://github.com/MemberJunction/bizapps-tasks-github/pull/2'),
            ).toBe('MemberJunction/bizapps-tasks-github');

            const issueVm = BuildGitHubIssueBadgeViewModel({
                ID: '50000000-0000-4000-8000-000000000001',
                Number: 17,
                HtmlURL: 'https://github.com/MemberJunction/bizapps-tasks-github/issues/17',
                State: 'closed',
                StateReason: 'not_planned',
                Labels: '["triage","wontfix"]',
                Milestone: 'v1.0 Pilot',
            });
            expect(issueVm.NumberLabel).toBe('#17');
            expect(issueVm.IssueState).toBe('closed');
            expect(issueVm.StateLabel).toBe('Closed · Not Planned');
            expect(issueVm.HtmlUrl).toBe('https://github.com/MemberJunction/bizapps-tasks-github/issues/17');
            expect(issueVm.RepositoryFullName).toBe('MemberJunction/bizapps-tasks-github');
            expect(issueVm.Labels).toEqual(['triage', 'wontfix']);
            expect(issueVm.PullOwnedFieldLockNotice).toBe(PULL_OWNED_FIELD_LOCK_NOTICE);

            const prVm = BuildGitHubPullRequestBadgeViewModel({
                ID: '50000000-0000-4000-8000-000000000002',
                Number: 2,
                HtmlURL: 'https://github.com/MemberJunction/bizapps-tasks-github/pull/2',
                State: 'open',
                IsDraft: false,
                ReviewDecision: 'APPROVED',
                ChecksStatus: 'Passing',
                Additions: 412,
                Deletions: 19,
                ChangedFiles: 11,
                HeadBranch: 'feat/tasks-github-angular-ui',
                BaseBranch: 'next',
                Labels: '["ui","webhooks"]',
            });
            expect(prVm.NumberLabel).toBe('#2');
            expect(prVm.PRState).toBe('open');
            expect(prVm.StateLabel).toBe('Open');
            expect(prVm.ReviewDecisionLabel).toBe('Approved');
            expect(prVm.ChecksStatusLabel).toBe('Checks Passing');
            expect(prVm.DiffStatLabel).toBe('+412 / -19');
            expect(prVm.BranchComparisonLabel).toBe('feat/tasks-github-angular-ui -> next');
            expect(prVm.HtmlUrl).toBe('https://github.com/MemberJunction/bizapps-tasks-github/pull/2');

            const combined = BuildGitHubTaskDetailBadgeViewModel({
                taskID: '50000000-0000-4000-8000-000000000002',
                pullRequestTask: {
                    ID: '50000000-0000-4000-8000-000000000002',
                    Number: 2,
                    HtmlURL: 'https://github.com/MemberJunction/bizapps-tasks-github/pull/2',
                    State: 'merged',
                    IsDraft: false,
                    Additions: 50,
                    Deletions: 5,
                    HeadBranch: 'feat/x',
                    BaseBranch: 'next',
                },
            });
            expect(combined.HasGitHubLink).toBe(true);
            expect(combined.PullRequest?.StateLabel).toBe('Merged');
            expect(combined.PrimaryHtmlUrl).toBe('https://github.com/MemberJunction/bizapps-tasks-github/pull/2');
            expect(combined.GitHubOwnedFields).toContain('Name');
            expect(combined.TasksOwnedFields).toContain('Priority');
        });
    });

    describe('Webhook delivery rows, agent context, and client bootstrap exports', () => {
        it('formats webhook delivery rows, caps agent context, and exports LoadBizAppsTasksGitHubClient', () => {
            expect(ParseGitHubTasksAdminTab('IDENTITY')).toBe('identity');
            expect(ParseGitHubTasksAdminTab('invalid')).toBeNull();

            const deliveries = BuildWebhookDeliveryRows([
                {
                    ID: '60000000-0000-4000-8000-000000000001',
                    DeliveryID: 'gh-deliv-001',
                    EventName: 'pull_request',
                    RepositoryFullName: 'MemberJunction/bizapps-tasks-github',
                    Status: 'synced',
                    ReceivedAt: '2026-11-10T16:30:00.000Z',
                },
                {
                    ID: '60000000-0000-4000-8000-000000000002',
                    ResultCode: 'VALIDATION_ERROR',
                    StartedAt: '2026-11-10T16:31:00.000Z',
                },
            ]);
            expect(deliveries[0]?.StatusTone).toBe('success');
            expect(deliveries[1]?.StatusTone).toBe('error');

            const identity = BuildIdentityMappingViewModel({
                currentUser: { Email: 'nobody@example.com' },
                people: [],
                identities: [],
            });
            const context = BuildGitHubTasksAdminAgentContext({
                activeTab: 'webhooks',
                trackingFilter: 'all',
                searchQuery: '',
                allRepositories: [],
                filteredRepositories: [],
                identity,
                webhookDeliveries: deliveries,
            });
            expect(context.ActiveTab).toBe('webhooks');
            expect(context.RecentWebhookDeliveryCount).toBe(2);

            expect(typeof LoadBizAppsTasksGitHubClient).toBe('function');
            expect(() => LoadBizAppsTasksGitHubClient()).not.toThrow();
            expect(TasksGitHubAngularModule).toBeDefined();
        });
    });
});
