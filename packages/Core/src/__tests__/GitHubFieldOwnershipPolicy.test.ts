import { describe, expect, it } from 'vitest';
import {
    AssertValidUUID,
    EscapeSqlLiteral,
    GITHUB_FIELD_OWNERSHIP_RULES,
    GitHubFieldOwnershipPolicy,
    IsValidUUIDString,
} from '../index.js';

describe('GitHubFieldOwnershipPolicy & SQL Safety', () => {
    it('distinguishes GitHub-owned pull fields from Tasks-owned planning fields', () => {
        expect(GitHubFieldOwnershipPolicy.IsGitHubOwnedTaskField('Name')).toBe(true);
        expect(GitHubFieldOwnershipPolicy.IsGitHubOwnedTaskField('Description')).toBe(true);
        expect(GitHubFieldOwnershipPolicy.IsGitHubOwnedTaskField('Status')).toBe(true);
        expect(GitHubFieldOwnershipPolicy.IsGitHubOwnedTaskField('DueAt')).toBe(false);

        expect(GitHubFieldOwnershipPolicy.IsTasksOwnedPlanningField('DueAt')).toBe(true);
        expect(GitHubFieldOwnershipPolicy.IsTasksOwnedPlanningField('HoursEstimated')).toBe(true);
        expect(GitHubFieldOwnershipPolicy.IsTasksOwnedPlanningField('ParentID')).toBe(true);
        expect(GitHubFieldOwnershipPolicy.IsTasksOwnedPlanningField('Priority')).toBe(true);
        expect(GitHubFieldOwnershipPolicy.IsTasksOwnedPlanningField('CategoryID')).toBe(true);
        expect(GitHubFieldOwnershipPolicy.IsTasksOwnedPlanningField('Name')).toBe(false);
        expect(GITHUB_FIELD_OWNERSHIP_RULES.length).toBeGreaterThanOrEqual(11);
    });

    it('maps GitHub issue states and state reasons to lifecycle codes and core statuses', () => {
        const base = {
            kind: 'issue' as const,
            number: 42,
            nodeId: 'I_kwDO1',
            title: 'Fix race condition',
            body: 'Details',
            htmlUrl: 'https://github.com/org/repo/issues/42',
            state: 'open' as const,
        };

        expect(GitHubFieldOwnershipPolicy.MapIssueTypeStatusCode(base)).toBe('OPEN');
        expect(
            GitHubFieldOwnershipPolicy.MapIssueTypeStatusCode({ ...base, assigneeLogins: ['alice'] }),
        ).toBe('IN_PROGRESS');
        expect(
            GitHubFieldOwnershipPolicy.MapIssueTypeStatusCode({
                ...base,
                state: 'closed',
                stateReason: 'completed',
            }),
        ).toBe('COMPLETED');
        expect(
            GitHubFieldOwnershipPolicy.MapIssueTypeStatusCode({
                ...base,
                state: 'closed',
                stateReason: 'not_planned',
            }),
        ).toBe('NOT_PLANNED');

        expect(GitHubFieldOwnershipPolicy.MapTypeStatusCodeToCoreStatus('OPEN')).toBe('Open');
        expect(GitHubFieldOwnershipPolicy.MapTypeStatusCodeToCoreStatus('IN_PROGRESS')).toBe('InProgress');
        expect(GitHubFieldOwnershipPolicy.MapTypeStatusCodeToCoreStatus('COMPLETED')).toBe('Completed');
        expect(GitHubFieldOwnershipPolicy.MapTypeStatusCodeToCoreStatus('NOT_PLANNED')).toBe('Cancelled');
    });

    it('maps GitHub pull request draft, review, merge, and closed states accurately', () => {
        const basePr = {
            kind: 'pull_request' as const,
            number: 99,
            nodeId: 'PR_kwDO99',
            title: 'Add subtype folding',
            body: 'Closes #42',
            htmlUrl: 'https://github.com/org/repo/pull/99',
            state: 'open' as const,
        };

        expect(GitHubFieldOwnershipPolicy.MapPullRequestTypeStatusCode({ ...basePr, isDraft: true })).toBe('DRAFT');
        expect(GitHubFieldOwnershipPolicy.MapPullRequestTypeStatusCode(basePr)).toBe('OPEN');
        expect(
            GitHubFieldOwnershipPolicy.MapPullRequestTypeStatusCode({
                ...basePr,
                requestedReviewerLogins: ['bob'],
            }),
        ).toBe('REVIEW_REQUIRED');
        expect(
            GitHubFieldOwnershipPolicy.MapPullRequestTypeStatusCode({
                ...basePr,
                reviewDecision: 'CHANGES_REQUESTED',
            }),
        ).toBe('CHANGES_REQUESTED');
        expect(
            GitHubFieldOwnershipPolicy.MapPullRequestTypeStatusCode({
                ...basePr,
                reviewDecision: 'APPROVED',
            }),
        ).toBe('APPROVED');
        expect(
            GitHubFieldOwnershipPolicy.MapPullRequestTypeStatusCode({
                ...basePr,
                state: 'merged',
            }),
        ).toBe('MERGED');
        expect(
            GitHubFieldOwnershipPolicy.MapPullRequestTypeStatusCode({
                ...basePr,
                state: 'closed',
            }),
        ).toBe('CLOSED');

        expect(GitHubFieldOwnershipPolicy.MapTypeStatusCodeToCoreStatus('CHANGES_REQUESTED')).toBe('Blocked');
        expect(GitHubFieldOwnershipPolicy.MapTypeStatusCodeToCoreStatus('MERGED')).toBe('Completed');
        expect(GitHubFieldOwnershipPolicy.MapTypeStatusCodeToCoreStatus('CLOSED')).toBe('Cancelled');
    });

    it('computes deterministic SHA-256 body hashes and enforces UUID/SQL escaping', () => {
        const h1 = GitHubFieldOwnershipPolicy.ComputeBodyHash('Title A', 'Body text');
        const h2 = GitHubFieldOwnershipPolicy.ComputeBodyHash('  Title A  ', '  Body text  ');
        const h3 = GitHubFieldOwnershipPolicy.ComputeBodyHash('Title A', 'Edited body text');

        expect(h1).toHaveLength(64);
        expect(h1).toBe(h2);
        expect(h1).not.toBe(h3);

        const validUuid = 'A1B2C3D4-1109-4A11-9B06-000000000001';
        expect(IsValidUUIDString(validUuid)).toBe(true);
        expect(IsValidUUIDString('not-a-uuid')).toBe(false);
        expect(AssertValidUUID(` ${validUuid} `, 'test')).toBe(validUuid);
        expect(() => AssertValidUUID("'; DROP TABLE Task;--", 'bad')).toThrow(/Invalid UUID/);
        expect(EscapeSqlLiteral("O'Reilly")).toBe("O''Reilly");
    });
});
