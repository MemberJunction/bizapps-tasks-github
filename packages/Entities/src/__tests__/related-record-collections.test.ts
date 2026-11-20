import { readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { describe, expect, it } from 'vitest';
import { EntityInfo, RelatedRecordCollection } from '@memberjunction/core';
import {
    mjBizAppsTasksGitHubGitHubIssueTaskEntity,
    mjBizAppsTasksGitHubGitHubPullRequestTaskEntity,
    mjBizAppsTasksGitHubGitHubRepositoryEntity,
} from '../index.js';

interface EntityRelationshipMetadataEntry {
    fields: {
        RelatedRecordCollection?: string;
    };
    primaryKey: {
        ID: string;
    };
}

interface RelatedRecordCollectionBlob {
    Name: string;
    Source: string;
    Load: string;
    ReadOnly?: boolean;
    OnRemove: string;
    OrderBy?: string;
    ClearAfterSave?: boolean;
    RelatedEntity?: string;
    RelatedEntityJoinField?: string;
    EmbeddedRecord?: string;
}

const currentDir = dirname(fileURLToPath(import.meta.url));
const repoRoot = resolve(currentDir, '../../../..');
const relDir = resolve(repoRoot, 'metadata/entity-relationships');
const generatedEntityPath = resolve(currentDir, '../generated/entities/__mj_BizAppsTasksGitHub.ts');

function createStubEntityInfo(name: string): EntityInfo {
    return new EntityInfo({
        ID: '11111111-1111-4111-8111-111111111111',
        Name: name,
        BaseTable: name,
        BaseView: `vw${name}`,
        SchemaName: '__mj_BizAppsTasksGitHub',
    });
}

describe('GitHubRepository RelatedRecordCollection metadata & runtime behavior', () => {
    it('defines 2 read-only database/explicit RelatedRecordCollection entries and zero EmbeddedRecord declarations', () => {
        const rawEntries = readFileSync(resolve(relDir, '.entity-relationships.json'), 'utf8');
        const entries = JSON.parse(rawEntries) as EntityRelationshipMetadataEntry[];
        expect(entries).toHaveLength(2);

        const expectedTargets = new Map<string, { relatedEntity: string; name: string }>([
            [
                'github-repository-issue-tasks-collection.json',
                { relatedEntity: 'MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks', name: 'IssueTasks' },
            ],
            [
                'github-repository-pull-request-tasks-collection.json',
                { relatedEntity: 'MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks', name: 'PullRequestTasks' },
            ],
        ]);

        for (const entry of entries) {
            expect(entry.fields.RelatedRecordCollection).toMatch(/^@file:[a-z0-9-]+\.json$/);
            const fileName = (entry.fields.RelatedRecordCollection ?? '').replace(/^@file:/, '');
            const expected = expectedTargets.get(fileName);
            expect(expected).toBeDefined();
            expect(entry.primaryKey.ID).toBe(
                `@lookup:MJ: Entity Relationships.Entity=MJ_BizApps_Tasks_GitHub: Git Hub Repositories&RelatedEntity=${expected?.relatedEntity}&RelatedEntityJoinField=RepositoryID`,
            );

            const blob = JSON.parse(
                readFileSync(resolve(relDir, fileName), 'utf8'),
            ) as RelatedRecordCollectionBlob;
            expect(blob.Name).toBe(expected?.name);
            expect(blob.Source).toBe('database');
            expect(blob.Load).toBe('explicit');
            expect(blob.ReadOnly).toBe(true);
            expect(blob.OnRemove).toBe('refuse');
            expect(blob.OrderBy).toBe('Number DESC');
            expect(blob.ClearAfterSave).toBe(false);
            expect(blob.RelatedEntity).toBeUndefined();
            expect(blob.RelatedEntityJoinField).toBeUndefined();
            expect(blob.EmbeddedRecord).toBeUndefined();
        }

        // Verify zero EmbeddedRecord declarations were introduced in generated entities
        const generatedSource = readFileSync(generatedEntityPath, 'utf8');
        expect(generatedSource).not.toContain('DeclareEmbeddedRecord');
    });

    it('exposes read-only IssueTasks and PullRequestTasks companions that refuse mutations and keep Dirty=false', async () => {
        const repo = new mjBizAppsTasksGitHubGitHubRepositoryEntity(
            createStubEntityInfo('MJ_BizApps_Tasks_GitHub: Git Hub Repositories'),
        );
        const issue = new mjBizAppsTasksGitHubGitHubIssueTaskEntity(
            createStubEntityInfo('MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks'),
        );
        const pr = new mjBizAppsTasksGitHubGitHubPullRequestTaskEntity(
            createStubEntityInfo('MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks'),
        );

        expect(repo.IssueTasks).toBeInstanceOf(RelatedRecordCollection);
        expect(repo.PullRequestTasks).toBeInstanceOf(RelatedRecordCollection);
        expect(repo.GetCompanion('IssueTasks')).toBe(repo.IssueTasks);
        expect(repo.GetCompanion('PullRequestTasks')).toBe(repo.PullRequestTasks);

        expect(repo.IssueTasks.RelatedEntityName).toBe('MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks');
        expect(repo.IssueTasks.RelatedEntityJoinField).toBe('RepositoryID');
        expect(repo.IssueTasks.Source).toBe('database');
        expect(repo.IssueTasks.LoadMode).toBe('explicit');
        expect(repo.IssueTasks.IsReadOnly).toBe(true);
        expect(repo.IssueTasks.RemovalMode).toBe('refuse');
        expect(repo.IssueTasks.OrderByClause).toBe('Number DESC');
        expect(repo.IssueTasks.Dirty).toBe(false);

        expect(repo.PullRequestTasks.RelatedEntityName).toBe('MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks');
        expect(repo.PullRequestTasks.RelatedEntityJoinField).toBe('RepositoryID');
        expect(repo.PullRequestTasks.Source).toBe('database');
        expect(repo.PullRequestTasks.LoadMode).toBe('explicit');
        expect(repo.PullRequestTasks.IsReadOnly).toBe(true);
        expect(repo.PullRequestTasks.RemovalMode).toBe('refuse');
        expect(repo.PullRequestTasks.OrderByClause).toBe('Number DESC');
        expect(repo.PullRequestTasks.Dirty).toBe(false);

        // Mutations must throw on both read-only collections
        expect(() => repo.IssueTasks.Add(issue)).toThrow(/read-only/i);
        expect(() => repo.IssueTasks.Remove(issue)).toThrow(/read-only/i);
        expect(() => repo.IssueTasks.Clear()).toThrow(/read-only/i);
        await expect(repo.IssueTasks.Create()).rejects.toThrow(/read-only/i);

        expect(() => repo.PullRequestTasks.Add(pr)).toThrow(/read-only/i);
        expect(() => repo.PullRequestTasks.Remove(pr)).toThrow(/read-only/i);
        expect(() => repo.PullRequestTasks.Clear()).toThrow(/read-only/i);
        await expect(repo.PullRequestTasks.Create()).rejects.toThrow(/read-only/i);

        // Neither collection ever becomes Dirty
        expect(repo.IssueTasks.Dirty).toBe(false);
        expect(repo.PullRequestTasks.Dirty).toBe(false);
    });
});
