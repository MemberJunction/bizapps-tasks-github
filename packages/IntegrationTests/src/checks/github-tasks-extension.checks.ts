import { createHmac } from 'node:crypto';
import { IMetadataProvider, IRunViewProvider, RunView } from '@memberjunction/core';
import { UUIDsEqual } from '@memberjunction/global';
import {
    Assert,
    AssertEqual,
    IntegrationCheckRegistry,
    type NamedCheck,
} from '@memberjunction/testing-integration/registry';
import { mjBizAppsCommonPersonEntity } from '@mj-biz-apps/common-entities';
import {
    mjBizAppsTasksTaskActivityEntity,
    mjBizAppsTasksTaskAssignmentEntity,
    mjBizAppsTasksTaskEntity,
    mjBizAppsTasksTaskTypeEntity,
} from '@mj-biz-apps/tasks-entities';
import {
    mjBizAppsTasksGitHubGitHubIdentityEntity,
    mjBizAppsTasksGitHubGitHubIssueTaskEntity,
    mjBizAppsTasksGitHubGitHubPullRequestTaskEntity,
    mjBizAppsTasksGitHubGitHubRepositoryEntity,
} from '@mj-biz-apps/tasks-github-entities';
import {
    FIELD_SUGGESTIONS_ENTITY_NAME,
    GITHUB_IDENTITIES_ENTITY,
    GITHUB_ISSUE_TASKS_ENTITY,
    GITHUB_PR_TASKS_ENTITY,
    GITHUB_REPOSITORIES_ENTITY,
    GitHubTaskInferenceService,
    GitHubTaskSyncService,
    GitHubWebhookService,
    IFieldSuggestionEntityRecord,
    PEOPLE_ENTITY,
    TASK_ASSIGNMENTS_ENTITY,
    TASK_TYPES_ENTITY,
    TASKS_ENTITY_NAME,
} from '@mj-biz-apps/tasks-github-core';

const BUNDLE_NAME = 'github-tasks-extension';

const checks: NamedCheck[] = [
    {
        Id: `${BUNDLE_NAME}.GH1`,
        Name: 'GH1 — Schema entities, IS-A ParentID to Tasks, FIELD_SUGGESTION comments, GITHUB_ISSUE/GITHUB_PR lifecycles, actions, prompt, and Chief of Staff skill',
        RequiresMutation: false,
        Fn: async (ctx) => {
            const tasksInfo = ctx.Provider.Entities.find((e) => e.Name === TASKS_ENTITY_NAME);
            const repoInfo = ctx.Provider.Entities.find((e) => e.Name === GITHUB_REPOSITORIES_ENTITY);
            const idInfo = ctx.Provider.Entities.find((e) => e.Name === GITHUB_IDENTITIES_ENTITY);
            const issueInfo = ctx.Provider.Entities.find((e) => e.Name === GITHUB_ISSUE_TASKS_ENTITY);
            const prInfo = ctx.Provider.Entities.find((e) => e.Name === GITHUB_PR_TASKS_ENTITY);

            Assert(Boolean(tasksInfo), 'Tasks entity loaded');
            Assert(Boolean(repoInfo), 'GitHub Repositories entity loaded');
            Assert(Boolean(idInfo), 'GitHub Identities entity loaded');
            Assert(Boolean(issueInfo), 'GitHub Issue Tasks entity loaded');
            Assert(Boolean(prInfo), 'GitHub Pull Request Tasks entity loaded');

            Assert(
                UUIDsEqual(issueInfo!.ParentID, tasksInfo!.ID),
                'GitHubIssueTask.ParentID points to MJ_BizApps_Tasks: Tasks',
            );
            Assert(
                UUIDsEqual(prInfo!.ParentID, tasksInfo!.ID),
                'GitHubPullRequestTask.ParentID points to MJ_BizApps_Tasks: Tasks',
            );

            const rv = RunView.FromMetadataProvider(ctx.Provider);
            const [typesRes, actionsRes, skillsRes, agentSkillsRes] = await rv.RunViews([
                {
                    EntityName: TASK_TYPES_ENTITY,
                    ExtraFilter: `Code IN ('GITHUB_ISSUE', 'GITHUB_PR')`,
                    ResultType: 'simple',
                },
                {
                    EntityName: 'MJ: Actions',
                    ExtraFilter: `DriverClass LIKE 'TasksGitHub.%'`,
                    ResultType: 'simple',
                },
                {
                    EntityName: 'MJ: AI Skills',
                    ExtraFilter: `Name = 'GitHub Tasks & Pull Requests'`,
                    ResultType: 'simple',
                },
                {
                    EntityName: 'MJ: AI Agent Skills',
                    ExtraFilter: `SkillID = 'A1B2C3D4-1109-4A11-9B08-000000000001'`,
                    ResultType: 'simple',
                },
            ], ctx.User);

            const taskTypes = (typesRes?.Results as mjBizAppsTasksTaskTypeEntity[] | undefined) ?? [];
            AssertEqual(taskTypes.length, 2, 'Both GITHUB_ISSUE and GITHUB_PR TaskTypes exist');

            const issueType = taskTypes.find((t) => t.Code === 'GITHUB_ISSUE')!;
            const prType = taskTypes.find((t) => t.Code === 'GITHUB_PR')!;
            AssertEqual(issueType.ExtensionEntity, GITHUB_ISSUE_TASKS_ENTITY, 'GITHUB_ISSUE ExtensionEntity');
            AssertEqual(prType.ExtensionEntity, GITHUB_PR_TASKS_ENTITY, 'GITHUB_PR ExtensionEntity');

            AssertEqual((actionsRes?.Results ?? []).length, 3, '3 TasksGitHub actions registered');
            AssertEqual((skillsRes?.Results ?? []).length, 1, 'GitHub Tasks & Pull Requests skill exists');
            Assert(
                (agentSkillsRes?.Results ?? []).length >= 1,
                'GitHub Tasks & Pull Requests skill granted to Chief of Staff',
            );
        },
    },
    {
        Id: `${BUNDLE_NAME}.GH2`,
        Name: 'GH2 — Saving a bare GITHUB_ISSUE Task auto-provisions GitHubIssueTask via SubtypeSelector AutoEnsureOnSave and refuses changing TypeID to GITHUB_PR',
        RequiresMutation: true,
        Fn: async (ctx) => {
            const rv = RunView.FromMetadataProvider(ctx.Provider);
            const typesRes = await rv.RunView<mjBizAppsTasksTaskTypeEntity>(
                {
                    EntityName: TASK_TYPES_ENTITY,
                    ExtraFilter: `Code IN ('GITHUB_ISSUE', 'GITHUB_PR')`,
                    ResultType: 'simple',
                },
                ctx.User,
            );
            const issueType = (typesRes.Results ?? []).find((t) => t.Code === 'GITHUB_ISSUE')!;
            const prType = (typesRes.Results ?? []).find((t) => t.Code === 'GITHUB_PR')!;

            const task = await ctx.Provider.GetEntityObject<mjBizAppsTasksTaskEntity>(
                TASKS_ENTITY_NAME,
                ctx.User,
            );
            task.NewRecord();
            task.Name = 'GH2 AutoEnsureOnSave Smoke Issue';
            task.TypeID = issueType.ID;
            task.Status = 'Open';
            task.Priority = 'Medium';

            let createdTaskId = '';
            try {
                const saved = await task.Save();
                Assert(saved, `Bare GITHUB_ISSUE Task saved cleanly: ${task.LatestResult?.CompleteMessage ?? ''}`);
                createdTaskId = task.ID;

                const issueExt = await ctx.Provider.GetEntityObject<mjBizAppsTasksGitHubGitHubIssueTaskEntity>(
                    GITHUB_ISSUE_TASKS_ENTITY,
                    ctx.User,
                );
                const extExists = await issueExt.Load(createdTaskId);
                Assert(extExists, 'GitHubIssueTask IS-A child row was auto-created in the same transaction');
                AssertEqual(issueExt.State, 'open', 'Default State on auto-provisioned GitHubIssueTask');

                // Attempt cross-subtype mutation from GITHUB_ISSUE -> GITHUB_PR (must be refused by OnSubtypeChange: 'Refuse')
                task.TypeID = prType.ID;
                const changedSave = await task.Save();
                Assert(!changedSave, 'SubtypeSelector OnSubtypeChange=Refuse blocked changing GITHUB_ISSUE -> GITHUB_PR');
            } finally {
                if (createdTaskId) {
                    // Ensure class references stay retained under verbatimModuleSyntax/bundler
                    void mjBizAppsCommonPersonEntity;
                    void mjBizAppsTasksTaskActivityEntity;
                    void mjBizAppsTasksTaskAssignmentEntity;
                    void mjBizAppsTasksTaskEntity;
                    void mjBizAppsTasksTaskTypeEntity;
                    void mjBizAppsTasksGitHubGitHubIdentityEntity;
                    void mjBizAppsTasksGitHubGitHubIssueTaskEntity;
                    void mjBizAppsTasksGitHubGitHubPullRequestTaskEntity;
                    void mjBizAppsTasksGitHubGitHubRepositoryEntity;

                    const actRes = await rv.RunView<mjBizAppsTasksTaskActivityEntity>(
                        {
                            EntityName: 'MJ_BizApps_Tasks: Task Activities',
                            ExtraFilter: `TaskID = '${createdTaskId}'`,
                            ResultType: 'entity_object',
                        },
                        ctx.User,
                    );
                    for (const act of actRes.Results ?? []) {
                        await act.Delete();
                    }

                    const extCleanup = await ctx.Provider.GetEntityObject<mjBizAppsTasksGitHubGitHubIssueTaskEntity>(
                        GITHUB_ISSUE_TASKS_ENTITY,
                        ctx.User,
                    );
                    if (await extCleanup.Load(createdTaskId)) {
                        await extCleanup.Delete();
                    }
                    const taskCleanup = await ctx.Provider.GetEntityObject<mjBizAppsTasksTaskEntity>(
                        TASKS_ENTITY_NAME,
                        ctx.User,
                    );
                    if (await taskCleanup.Load(createdTaskId)) {
                        await taskCleanup.Delete();
                    }
                }
            }
        },
    },
    {
        Id: `${BUNDLE_NAME}.GH3`,
        Name: 'GH3 — End-to-end live DB sync, ImportRule=AssignedOnly, Primary/Reviewer assignments, idempotent re-sync preserving Tasks planning fields, Field Suggestion inference, MilestoneDueAt superseding, and signed webhook update',
        RequiresMutation: true,
        Fn: async (ctx) => {
            const provider = ctx.Provider as IMetadataProvider & IRunViewProvider;
            const rv = RunView.FromMetadataProvider(ctx.Provider);
            const runSuffix = Date.now().toString(36);

            let personAId = '';
            let personBId = '';
            let identityAId = '';
            let identityBId = '';
            let repoId = '';
            const createdTaskIds: string[] = [];
            const createdSuggestionIds: string[] = [];

            GitHubTaskInferenceService.Instance.SetExtractor({
                ExtractPlanningSuggestions: async () => ({
                    suggestions: [
                        {
                            field: 'DueAt',
                            value: '2026-12-20T00:00:00.000Z',
                            confidence: 0.91,
                            rationale: 'Issue body mentions Dec 20 milestone target',
                        },
                        {
                            field: 'HoursEstimated',
                            value: 5,
                            confidence: 0.84,
                            rationale: 'Estimated 5 hours of implementation and testing',
                        },
                    ],
                    mentionedLogins: [],
                    promptRunId: null,
                }),
            });

            try {
                // 1. Create two test People + GitHubIdentities + tracked GitHubRepository
                const personA = await ctx.Provider.GetEntityObject<mjBizAppsCommonPersonEntity>(
                    PEOPLE_ENTITY,
                    ctx.User,
                );
                personA.NewRecord();
                personA.FirstName = 'Alice';
                personA.LastName = `GitHubDev-${runSuffix}`;
                personA.Email = `alice.${runSuffix}@example.com`;
                personA.Status = 'Active';
                Assert(await personA.Save(), 'Saved Person A');
                personAId = personA.ID;

                const personB = await ctx.Provider.GetEntityObject<mjBizAppsCommonPersonEntity>(
                    PEOPLE_ENTITY,
                    ctx.User,
                );
                personB.NewRecord();
                personB.FirstName = 'Bob';
                personB.LastName = `GitHubReviewer-${runSuffix}`;
                personB.Email = `bob.${runSuffix}@example.com`;
                personB.Status = 'Active';
                Assert(await personB.Save(), 'Saved Person B');
                personBId = personB.ID;

                const idA = await ctx.Provider.GetEntityObject<mjBizAppsTasksGitHubGitHubIdentityEntity>(
                    GITHUB_IDENTITIES_ENTITY,
                    ctx.User,
                );
                idA.NewRecord();
                idA.GitHubLogin = `alice-${runSuffix}`;
                idA.PersonID = personAId;
                idA.IsActive = true;
                Assert(await idA.Save(), 'Saved GitHubIdentity A');
                identityAId = idA.ID;

                const idB = await ctx.Provider.GetEntityObject<mjBizAppsTasksGitHubGitHubIdentityEntity>(
                    GITHUB_IDENTITIES_ENTITY,
                    ctx.User,
                );
                idB.NewRecord();
                idB.GitHubLogin = `bob-${runSuffix}`;
                idB.PersonID = personBId;
                idB.IsActive = true;
                Assert(await idB.Save(), 'Saved GitHubIdentity B');
                identityBId = idB.ID;

                const repo = await ctx.Provider.GetEntityObject<mjBizAppsTasksGitHubGitHubRepositoryEntity>(
                    GITHUB_REPOSITORIES_ENTITY,
                    ctx.User,
                );
                repo.NewRecord();
                repo.Owner = 'MemberJunction';
                repo.Name = `workbus-smoke-${runSuffix}`;
                repo.DefaultBranch = 'next';
                repo.IsTracked = true;
                repo.ImportRule = 'AssignedOnly';
                Assert(await repo.Save(), 'Saved tracked GitHubRepository');
                repoId = repo.ID;

                // 2. Sync 1 unmapped issue (skipped), 1 mapped issue (#101), and 1 mapped PR (#102 closing #101)
                const syncSummaries = await GitHubTaskSyncService.Instance.SyncRepositories({
                    repositoryId: repoId,
                    items: [
                        {
                            kind: 'issue',
                            number: 100,
                            nodeId: `I_skip_${runSuffix}`,
                            title: 'Unmapped external issue',
                            body: 'No mapped assignee',
                            htmlUrl: `https://github.com/MemberJunction/workbus-smoke-${runSuffix}/issues/100`,
                            state: 'open',
                            assigneeLogins: ['random-outsider'],
                        },
                        {
                            kind: 'issue',
                            number: 101,
                            nodeId: `I_101_${runSuffix}`,
                            title: 'Wire GitHub task sync',
                            body: 'Target Dec 20; ~5 hours',
                            htmlUrl: `https://github.com/MemberJunction/workbus-smoke-${runSuffix}/issues/101`,
                            state: 'open',
                            assigneeLogins: [`alice-${runSuffix}`],
                        },
                        {
                            kind: 'pull_request',
                            number: 102,
                            nodeId: `PR_102_${runSuffix}`,
                            title: 'feat: implement GitHub task sync',
                            body: 'Closes #101',
                            htmlUrl: `https://github.com/MemberJunction/workbus-smoke-${runSuffix}/pull/102`,
                            state: 'open',
                            isDraft: false,
                            headBranch: 'feat/gh-sync',
                            headSha: '1122334455',
                            baseBranch: 'next',
                            assigneeLogins: [`alice-${runSuffix}`],
                            requestedReviewerLogins: [`bob-${runSuffix}`],
                            linkedIssueNumber: 101,
                        },
                    ],
                    contextUser: ctx.User,
                    provider,
                });

                AssertEqual(syncSummaries[0].skipped, 1, 'Unmapped issue skipped under AssignedOnly');
                AssertEqual(syncSummaries[0].created, 2, 'Mapped issue #101 and PR #102 created');
                createdTaskIds.push(...syncSummaries[0].taskIds);

                const [issueTaskId, prTaskId] = syncSummaries[0].taskIds;

                // Verify PR LinkedIssueTaskID & Primary + Reviewer assignments
                const prExt = await ctx.Provider.GetEntityObject<mjBizAppsTasksGitHubGitHubPullRequestTaskEntity>(
                    GITHUB_PR_TASKS_ENTITY,
                    ctx.User,
                );
                Assert(await prExt.Load(prTaskId), 'Loaded PR extension');
                Assert(UUIDsEqual(prExt.LinkedIssueTaskID, issueTaskId), 'PR LinkedIssueTaskID links to issue #101 Task');

                const prAssignmentsRes = await rv.RunView<mjBizAppsTasksTaskAssignmentEntity>(
                    {
                        EntityName: TASK_ASSIGNMENTS_ENTITY,
                        ExtraFilter: `TaskID = '${prTaskId}'`,
                        ResultType: 'simple',
                    },
                    ctx.User,
                );
                AssertEqual((prAssignmentsRes.Results ?? []).length, 2, 'PR has Primary + Reviewer TaskAssignment rows');

                // Verify Field Suggestions created on issue #101
                const issueSuggestionsRes = await rv.RunView<IFieldSuggestionEntityRecord>(
                    {
                        EntityName: FIELD_SUGGESTIONS_ENTITY_NAME,
                        ExtraFilter: `LinkedRecordID = '${issueTaskId}'`,
                        ResultType: 'simple',
                    },
                    ctx.User,
                );
                const prSuggestionsRes = await rv.RunView<IFieldSuggestionEntityRecord>(
                    {
                        EntityName: FIELD_SUGGESTIONS_ENTITY_NAME,
                        ExtraFilter: `LinkedRecordID = '${prTaskId}'`,
                        ResultType: 'simple',
                    },
                    ctx.User,
                );
                for (const s of [...(issueSuggestionsRes.Results ?? []), ...(prSuggestionsRes.Results ?? [])]) {
                    createdSuggestionIds.push(s.ID);
                }
                AssertEqual(
                    (issueSuggestionsRes.Results ?? []).length,
                    2,
                    '2 Field Suggestions (DueAt + HoursEstimated) created on issue #101',
                );

                // 3. Human updates Tasks-owned Priority='Critical' on issue #101; re-sync with MilestoneDueAt
                const issueTask = await ctx.Provider.GetEntityObject<mjBizAppsTasksTaskEntity>(
                    TASKS_ENTITY_NAME,
                    ctx.User,
                );
                Assert(await issueTask.Load(issueTaskId), 'Loaded issue Task');
                issueTask.Priority = 'Critical';
                Assert(await issueTask.Save(), 'Saved Tasks-owned Priority=Critical');

                const resyncSummary = await GitHubTaskSyncService.Instance.SyncRepositories({
                    repositoryId: repoId,
                    items: [
                        {
                            kind: 'issue',
                            number: 101,
                            nodeId: `I_101_${runSuffix}`,
                            title: 'Wire GitHub task sync (renamed on GitHub)',
                            body: 'Target Dec 20; ~5 hours',
                            htmlUrl: `https://github.com/MemberJunction/workbus-smoke-${runSuffix}/issues/101`,
                            state: 'open',
                            milestoneTitle: 'MJ 6.3',
                            milestoneDueAt: '2026-12-31T00:00:00.000Z',
                            assigneeLogins: [`alice-${runSuffix}`],
                        },
                    ],
                    contextUser: ctx.User,
                    provider,
                });

                AssertEqual(resyncSummary[0].created, 0, 'Idempotent re-sync created 0 duplicate tasks');
                AssertEqual(resyncSummary[0].updated, 1, 'Idempotent re-sync updated existing task');
                AssertEqual(resyncSummary[0].supersededDueAtSuggestions, 1, 'MilestoneDueAt superseded pending DueAt suggestion');

                const reloadedIssueTask = await ctx.Provider.GetEntityObject<mjBizAppsTasksTaskEntity>(
                    TASKS_ENTITY_NAME,
                    ctx.User,
                );
                Assert(await reloadedIssueTask.Load(issueTaskId), 'Reloaded issue Task');
                AssertEqual(reloadedIssueTask.Name, 'Wire GitHub task sync (renamed on GitHub)', 'GitHub-owned Name updated');
                AssertEqual(reloadedIssueTask.Priority, 'Critical', 'Tasks-owned Priority=Critical strictly preserved');

                // 4. Signed pull_request_review webhook updates PR #102 ReviewDecision to APPROVED
                const secret = `whsec_${runSuffix}`;
                const whBody = JSON.stringify({
                    action: 'submitted',
                    repository: {
                        name: `workbus-smoke-${runSuffix}`,
                        owner: { login: 'MemberJunction' },
                    },
                    pull_request: {
                        number: 102,
                        node_id: `PR_102_${runSuffix}`,
                        title: 'feat: implement GitHub task sync',
                        body: 'Closes #101',
                        html_url: `https://github.com/MemberJunction/workbus-smoke-${runSuffix}/pull/102`,
                        state: 'open',
                        draft: false,
                        head: { ref: 'feat/gh-sync', sha: '9988776655' },
                        base: { ref: 'next' },
                        assignees: [{ login: `alice-${runSuffix}` }],
                        requested_reviewers: [{ login: `bob-${runSuffix}` }],
                    },
                    review: { state: 'approved' },
                });
                const sig = `sha256=${createHmac('sha256', secret).update(whBody, 'utf8').digest('hex')}`;

                const whOutcome = await GitHubWebhookService.Instance.HandleWebhook({
                    eventName: 'pull_request_review',
                    signatureHeader: sig,
                    rawPayload: whBody,
                    webhookSecret: secret,
                    runInference: false,
                    contextUser: ctx.User,
                    provider,
                });
                AssertEqual(whOutcome.status, 'synced', 'Signed webhook delivery synchronized PR #102');

                const reloadedPrExt = await ctx.Provider.GetEntityObject<mjBizAppsTasksGitHubGitHubPullRequestTaskEntity>(
                    GITHUB_PR_TASKS_ENTITY,
                    ctx.User,
                );
                Assert(await reloadedPrExt.Load(prTaskId), 'Reloaded PR extension after webhook');
                AssertEqual(reloadedPrExt.ReviewDecision, 'APPROVED', 'PR ReviewDecision updated to APPROVED');
                AssertEqual(reloadedPrExt.HeadSha, '9988776655', 'PR HeadSha updated from webhook');
            } finally {
                GitHubTaskInferenceService.Instance.ResetExtractor();

                for (const sId of createdSuggestionIds) {
                    const fsObj = await ctx.Provider.GetEntityObject<IFieldSuggestionEntityRecord>(
                        FIELD_SUGGESTIONS_ENTITY_NAME,
                        ctx.User,
                    );
                    if (await fsObj.Load(sId)) {
                        await fsObj.Delete();
                    }
                }

                // Also discover any Issue/PR tasks tied to repoId in case a test step failed mid-sync
                if (repoId) {
                    const [repoPrs, repoIssues] = await rv.RunViews([
                        {
                            EntityName: GITHUB_PR_TASKS_ENTITY,
                            ExtraFilter: `RepositoryID = '${repoId}'`,
                            ResultType: 'simple',
                        },
                        {
                            EntityName: GITHUB_ISSUE_TASKS_ENTITY,
                            ExtraFilter: `RepositoryID = '${repoId}'`,
                            ResultType: 'simple',
                        },
                    ], ctx.User);
                    for (const row of [...(repoPrs?.Results ?? []), ...(repoIssues?.Results ?? [])] as Array<{ ID: string }>) {
                        if (!createdTaskIds.includes(row.ID)) {
                            createdTaskIds.push(row.ID);
                        }
                    }
                }

                // Clear LinkedIssueTaskID before deleting tasks
                for (const tId of [...createdTaskIds].reverse()) {
                    const assignRes = await rv.RunView<mjBizAppsTasksTaskAssignmentEntity>(
                        {
                            EntityName: TASK_ASSIGNMENTS_ENTITY,
                            ExtraFilter: `TaskID = '${tId}'`,
                            ResultType: 'entity_object',
                        },
                        ctx.User,
                    );
                    for (const a of assignRes.Results ?? []) {
                        await a.Delete();
                    }

                    const actRes = await rv.RunView<mjBizAppsTasksTaskActivityEntity>(
                        {
                            EntityName: 'MJ_BizApps_Tasks: Task Activities',
                            ExtraFilter: `TaskID = '${tId}'`,
                            ResultType: 'entity_object',
                        },
                        ctx.User,
                    );
                    for (const act of actRes.Results ?? []) {
                        await act.Delete();
                    }

                    const prCleanup = await ctx.Provider.GetEntityObject<mjBizAppsTasksGitHubGitHubPullRequestTaskEntity>(
                        GITHUB_PR_TASKS_ENTITY,
                        ctx.User,
                    );
                    if (await prCleanup.Load(tId)) {
                        prCleanup.LinkedIssueTaskID = null;
                        await prCleanup.Save();
                        await prCleanup.Delete();
                    }

                    const issueCleanup = await ctx.Provider.GetEntityObject<mjBizAppsTasksGitHubGitHubIssueTaskEntity>(
                        GITHUB_ISSUE_TASKS_ENTITY,
                        ctx.User,
                    );
                    if (await issueCleanup.Load(tId)) {
                        await issueCleanup.Delete();
                    }

                    const tObj = await ctx.Provider.GetEntityObject<mjBizAppsTasksTaskEntity>(
                        TASKS_ENTITY_NAME,
                        ctx.User,
                    );
                    if (await tObj.Load(tId)) {
                        await tObj.Delete();
                    }
                }

                if (repoId) {
                    const rObj = await ctx.Provider.GetEntityObject<mjBizAppsTasksGitHubGitHubRepositoryEntity>(
                        GITHUB_REPOSITORIES_ENTITY,
                        ctx.User,
                    );
                    if (await rObj.Load(repoId)) await rObj.Delete();
                }
                for (const idRowId of [identityAId, identityBId]) {
                    if (!idRowId) continue;
                    const iObj = await ctx.Provider.GetEntityObject<mjBizAppsTasksGitHubGitHubIdentityEntity>(
                        GITHUB_IDENTITIES_ENTITY,
                        ctx.User,
                    );
                    if (await iObj.Load(idRowId)) await iObj.Delete();
                }
                for (const pId of [personAId, personBId]) {
                    if (!pId) continue;
                    const pObj = await ctx.Provider.GetEntityObject<mjBizAppsCommonPersonEntity>(
                        PEOPLE_ENTITY,
                        ctx.User,
                    );
                    if (await pObj.Load(pId)) await pObj.Delete();
                }
            }
        },
    },
];

for (const check of checks) {
    IntegrationCheckRegistry.Instance.Register(check);
}

export const GITHUB_TASKS_EXTENSION_CHECKS = checks;
