import {
    Metadata,
    RunView,
    type EntityInfo,
    type IMetadataProvider,
    type IRunViewProvider,
    type UserInfo,
} from '@memberjunction/core';
import type {
    MJCompanyIntegrationEntityMapEntityType,
    MJCompanyIntegrationEntityType,
    MJCompanyIntegrationFieldMapEntityType,
} from '@memberjunction/core-entities';
import { EscapeSQLString, IsValidUUID, UUIDsEqual } from '@memberjunction/global';
import { GITHUB_INTEGRATION_NAME } from './GitHubVaultAuthResolver.js';
import { AssertValidUUID } from './sql-safety.js';
import type {
    GitHubIssueStateReason,
    IGitHubRepositoryFetcher,
    NormalizedGitHubIssueInput,
    NormalizedGitHubPullRequestInput,
    NormalizedGitHubSyncItem,
    NormalizedGitHubUserRef,
} from './types.js';

type MirrorRowPrimitive = string | number | boolean | Date | null | undefined;
type MirrorSimpleRow = Record<string, MirrorRowPrimitive>;

interface ParsedMirrorLabelObject {
    name?: string | null;
}

const SAFE_SQL_IDENTIFIER_PATTERN = /^[A-Za-z_][A-Za-z0-9_]*$/;

export interface ConnectorGitHubMirrorOptions {
    companyId?: string | null;
}

interface ResolvedMirrorObjectMapping {
    externalObjectName: 'issues' | 'pull_requests';
    entityName: string;
    entityInfo: EntityInfo | null;
    destFieldBySourceLower: Map<string, string>;
}

function normalizeIdentifierKey(name: string): string {
    return name.replace(/_/g, '').toLowerCase();
}

function resolveEntityInfo(
    md: IMetadataProvider,
    entityId: string,
    entityNameHint: string | null,
): { entityName: string; entityInfo: EntityInfo | null } | null {
    const entities = Array.isArray(md.Entities) ? md.Entities : [];
    const byId = entities.find((e) => UUIDsEqual(e.ID, entityId));
    if (byId) {
        return { entityName: byId.Name, entityInfo: byId };
    }
    if (entityNameHint && entityNameHint.trim().length > 0) {
        const cleanHint = entityNameHint.trim();
        const byName = entities.find((e) => e.Name.toLowerCase() === cleanHint.toLowerCase());
        return { entityName: byName ? byName.Name : cleanHint, entityInfo: byName ?? null };
    }
    return null;
}

function resolveDestinationFieldName(
    sourceFieldName: string,
    mapping: ResolvedMirrorObjectMapping,
): string | null {
    const explicit = mapping.destFieldBySourceLower.get(sourceFieldName.toLowerCase());
    if (explicit) {
        if (!mapping.entityInfo) {
            return SAFE_SQL_IDENTIFIER_PATTERN.test(explicit) ? explicit : null;
        }
        const verified = mapping.entityInfo.Fields.find(
            (f) => f.Name.toLowerCase() === explicit.toLowerCase(),
        );
        return verified && SAFE_SQL_IDENTIFIER_PATTERN.test(verified.Name) ? verified.Name : null;
    }

    if (!mapping.entityInfo) {
        return SAFE_SQL_IDENTIFIER_PATTERN.test(sourceFieldName) ? sourceFieldName : null;
    }

    const exact = mapping.entityInfo.Fields.find(
        (f) => f.Name.toLowerCase() === sourceFieldName.toLowerCase(),
    );
    if (exact && SAFE_SQL_IDENTIFIER_PATTERN.test(exact.Name)) {
        return exact.Name;
    }

    const collapsed = normalizeIdentifierKey(sourceFieldName);
    const fuzzy = mapping.entityInfo.Fields.find((f) => normalizeIdentifierKey(f.Name) === collapsed);
    if (fuzzy && SAFE_SQL_IDENTIFIER_PATTERN.test(fuzzy.Name)) {
        return fuzzy.Name;
    }

    return null;
}

function readMirrorField(
    row: MirrorSimpleRow,
    sourceFieldName: string,
    mapping: ResolvedMirrorObjectMapping,
): MirrorRowPrimitive {
    const explicitDest = mapping.destFieldBySourceLower.get(sourceFieldName.toLowerCase());
    if (explicitDest && explicitDest in row) {
        return row[explicitDest];
    }
    if (sourceFieldName in row) {
        return row[sourceFieldName];
    }
    const targetCollapsed = normalizeIdentifierKey(explicitDest ?? sourceFieldName);
    for (const [key, val] of Object.entries(row)) {
        if (normalizeIdentifierKey(key) === targetCollapsed) {
            return val;
        }
    }
    return undefined;
}

function readString(
    row: MirrorSimpleRow,
    sourceFieldName: string,
    mapping: ResolvedMirrorObjectMapping,
): string | null {
    const raw = readMirrorField(row, sourceFieldName, mapping);
    if (raw == null) {
        return null;
    }
    const str = String(raw).trim();
    return str.length > 0 ? str : null;
}

function readUntrimmedString(
    row: MirrorSimpleRow,
    sourceFieldName: string,
    mapping: ResolvedMirrorObjectMapping,
): string | null {
    const raw = readMirrorField(row, sourceFieldName, mapping);
    if (raw == null) {
        return null;
    }
    return String(raw);
}

function readNumber(
    row: MirrorSimpleRow,
    sourceFieldName: string,
    mapping: ResolvedMirrorObjectMapping,
): number | null {
    const raw = readMirrorField(row, sourceFieldName, mapping);
    if (typeof raw === 'number' && Number.isFinite(raw)) {
        return raw;
    }
    if (typeof raw === 'string' && raw.trim().length > 0) {
        const parsed = Number(raw.trim());
        return Number.isFinite(parsed) ? parsed : null;
    }
    return null;
}

function readBoolean(
    row: MirrorSimpleRow,
    sourceFieldName: string,
    mapping: ResolvedMirrorObjectMapping,
): boolean {
    const raw = readMirrorField(row, sourceFieldName, mapping);
    if (typeof raw === 'boolean') {
        return raw;
    }
    if (typeof raw === 'number') {
        return raw !== 0;
    }
    if (typeof raw === 'string') {
        const lower = raw.trim().toLowerCase();
        return lower === 'true' || lower === '1' || lower === 'yes';
    }
    return false;
}

function readTimestamp(
    row: MirrorSimpleRow,
    sourceFieldName: string,
    mapping: ResolvedMirrorObjectMapping,
): string | Date | null {
    const raw = readMirrorField(row, sourceFieldName, mapping);
    if (raw instanceof Date) {
        return raw;
    }
    if (typeof raw === 'string' && raw.trim().length > 0) {
        return raw.trim();
    }
    return null;
}

function parseMirrorLabelsJson(rawLabelsJson: string | null): string[] {
    if (!rawLabelsJson || !rawLabelsJson.trim()) {
        return [];
    }
    try {
        const parsed = JSON.parse(rawLabelsJson) as Array<string | ParsedMirrorLabelObject>;
        if (!Array.isArray(parsed)) {
            return [];
        }
        const labels: string[] = [];
        for (const item of parsed) {
            if (typeof item === 'string' && item.trim().length > 0) {
                labels.push(item.trim());
            } else if (item && typeof item === 'object' && typeof item.name === 'string' && item.name.trim().length > 0) {
                labels.push(item.name.trim());
            }
        }
        return labels;
    } catch {
        return rawLabelsJson
            .split(',')
            .map((s) => s.trim())
            .filter((s) => s.length > 0);
    }
}

function extractClosingIssueNumber(body: string | null): number | null {
    if (!body) {
        return null;
    }
    const match = /\b(?:close[sd]?|fix(?:e[sd])?|resolve[sd]?)\s+#(\d+)\b/i.exec(body);
    if (!match) {
        return null;
    }
    const parsed = Number.parseInt(match[1], 10);
    return Number.isFinite(parsed) && parsed > 0 ? parsed : null;
}

function matchesRepoFullNameOrUrl(
    repoFullName: string | null,
    htmlUrl: string | null,
    expectedFullNameLower: string,
): boolean {
    if (repoFullName && repoFullName.trim().toLowerCase() === expectedFullNameLower) {
        return true;
    }
    if (htmlUrl) {
        const match = /\/([^/]+\/[^/]+)\/(?:issues|pull)\/\d+/i.exec(htmlUrl);
        if (match && match[1].toLowerCase() === expectedFullNameLower) {
            return true;
        }
    }
    return false;
}

async function discoverMirrorObjectMappings(
    md: IMetadataProvider,
    rv: RunView,
    contextUser: UserInfo,
    companyId?: string | null,
): Promise<ResolvedMirrorObjectMapping[]> {
    let ciFilter = `Integration = '${GITHUB_INTEGRATION_NAME}' AND (IsActive IS NULL OR IsActive = 1)`;
    if (companyId && companyId.trim().length > 0) {
        if (!IsValidUUID(companyId.trim())) {
            throw new Error(`Invalid companyId UUID: '${companyId}'`);
        }
        ciFilter = `CompanyID = '${AssertValidUUID(companyId.trim(), 'companyId')}' AND ${ciFilter}`;
    }

    const ciRes = await rv.RunView<MJCompanyIntegrationEntityType>(
        {
            EntityName: 'MJ: Company Integrations',
            ExtraFilter: ciFilter,
            ResultType: 'simple',
        },
        contextUser,
    );
    if (!ciRes.Success || !ciRes.Results?.length) {
        return [];
    }

    const safeCiIds = ciRes.Results
        .map((r) => r.ID?.trim() ?? '')
        .filter((id) => IsValidUUID(id))
        .map((id) => `'${AssertValidUUID(id, 'CompanyIntegrationID')}'`);
    if (safeCiIds.length === 0) {
        return [];
    }

    const mapRes = await rv.RunView<MJCompanyIntegrationEntityMapEntityType>(
        {
            EntityName: 'MJ: Company Integration Entity Maps',
            ExtraFilter:
                `CompanyIntegrationID IN (${safeCiIds.join(',')}) ` +
                `AND ExternalObjectName IN ('issues', 'pull_requests') ` +
                `AND SyncEnabled = 1 AND Status = 'Active'`,
            OrderBy: 'Priority ASC',
            ResultType: 'simple',
        },
        contextUser,
    );
    if (!mapRes.Success || !mapRes.Results?.length) {
        return [];
    }

    const safeMapIds = mapRes.Results
        .map((m) => m.ID?.trim() ?? '')
        .filter((id) => IsValidUUID(id))
        .map((id) => `'${AssertValidUUID(id, 'EntityMapID')}'`);

    const fieldMapsByEntityMapId = new Map<string, MJCompanyIntegrationFieldMapEntityType[]>();
    if (safeMapIds.length > 0) {
        const fmRes = await rv.RunView<MJCompanyIntegrationFieldMapEntityType>(
            {
                EntityName: 'MJ: Company Integration Field Maps',
                ExtraFilter: `EntityMapID IN (${safeMapIds.join(',')}) AND Status = 'Active'`,
                ResultType: 'simple',
            },
            contextUser,
        );
        if (fmRes.Success && fmRes.Results) {
            for (const fm of fmRes.Results) {
                const key = fm.EntityMapID.trim().toLowerCase();
                const list = fieldMapsByEntityMapId.get(key) ?? [];
                list.push(fm);
                fieldMapsByEntityMapId.set(key, list);
            }
        }
    }

    const seenObjects = new Set<'issues' | 'pull_requests'>();
    const resolved: ResolvedMirrorObjectMapping[] = [];

    for (const entityMap of mapRes.Results) {
        const extObj = entityMap.ExternalObjectName.trim().toLowerCase();
        if (extObj !== 'issues' && extObj !== 'pull_requests') {
            continue;
        }
        if (seenObjects.has(extObj)) {
            continue;
        }
        const target = resolveEntityInfo(md, entityMap.EntityID, entityMap.Entity);
        if (!target) {
            continue;
        }
        const destFieldBySourceLower = new Map<string, string>();
        const fieldMaps = fieldMapsByEntityMapId.get(entityMap.ID.trim().toLowerCase()) ?? [];
        for (const fm of fieldMaps) {
            const src = fm.SourceFieldName?.trim();
            const dst = fm.DestinationFieldName?.trim();
            if (src && dst) {
                destFieldBySourceLower.set(src.toLowerCase(), dst);
            }
        }
        seenObjects.add(extObj);
        resolved.push({
            externalObjectName: extObj,
            entityName: target.entityName,
            entityInfo: target.entityInfo,
            destFieldBySourceLower,
        });
    }

    return resolved;
}

/**
 * Returns `true` when `@memberjunction/connector-github` has active `MJ: Company Integration Entity Maps`
 * configured for `issues` or `pull_requests`, allowing `SourceMode = 'Auto'` to read from the local
 * database mirror instead of making duplicate GitHub REST API calls.
 */
export async function HasActiveGitHubConnectorMirror(
    contextUser: UserInfo,
    provider?: IMetadataProvider & IRunViewProvider,
    companyId?: string | null,
): Promise<boolean> {
    try {
        const md = provider ?? Metadata.Provider;
        const rv = provider ? RunView.FromMetadataProvider(provider) : new RunView();
        const mappings = await discoverMirrorObjectMappings(md, rv, contextUser, companyId);
        return mappings.length > 0;
    } catch {
        return false;
    }
}

/**
 * Repository fetcher that reads GitHub `issues` and `pull_requests` rows mirrored into MemberJunction
 * entities by `@memberjunction/connector-github` (`MJ: Company Integration Entity Maps`), eliminating
 * duplicate GitHub REST polling when Integration Engine sync is active on the host.
 */
export class ConnectorGitHubMirrorRepositoryFetcher implements IGitHubRepositoryFetcher {
    public constructor(private readonly _options: ConnectorGitHubMirrorOptions = {}) {}

    public async FetchRepositoryItems(
        owner: string,
        name: string,
        contextUser: UserInfo,
        provider?: IMetadataProvider,
    ): Promise<NormalizedGitHubSyncItem[]> {
        const customProvider = provider as (IMetadataProvider & IRunViewProvider) | undefined;
        const md = customProvider ?? Metadata.Provider;
        const rv = customProvider ? RunView.FromMetadataProvider(customProvider) : new RunView();

        const mappings = await discoverMirrorObjectMappings(
            md,
            rv,
            contextUser,
            this._options.companyId,
        );
        if (mappings.length === 0) {
            throw new Error(
                `No active '@memberjunction/connector-github' Entity Maps ('issues' / 'pull_requests') found in MJ: Company Integration Entity Maps for '${owner}/${name}'.`,
            );
        }

        const expectedFullName = `${owner.trim()}/${name.trim()}`;
        const expectedFullNameLower = expectedFullName.toLowerCase();
        const normalized: NormalizedGitHubSyncItem[] = [];

        for (const mapping of mappings) {
            const repoFullNameColumn = resolveDestinationFieldName('repository_full_name', mapping);
            const extraFilter = repoFullNameColumn
                ? `[${repoFullNameColumn}] = '${EscapeSQLString(expectedFullName)}'`
                : '';

            const rowsRes = await rv.RunView<MirrorSimpleRow>(
                {
                    EntityName: mapping.entityName,
                    ExtraFilter: extraFilter,
                    ResultType: 'simple',
                },
                contextUser,
            );
            if (!rowsRes.Success) {
                throw new Error(
                    `Failed reading mirrored GitHub '${mapping.externalObjectName}' from entity '${mapping.entityName}': ${rowsRes.ErrorMessage}`,
                );
            }

            const rows = rowsRes.Results ?? [];
            if (mapping.externalObjectName === 'issues') {
                for (const row of rows) {
                    if (readBoolean(row, 'is_pull_request', mapping)) {
                        continue;
                    }
                    const repoFull = readString(row, 'repository_full_name', mapping);
                    const htmlUrl = readString(row, 'html_url', mapping);
                    if (!matchesRepoFullNameOrUrl(repoFull, htmlUrl, expectedFullNameLower)) {
                        continue;
                    }
                    const issueNumber = readNumber(row, 'number', mapping);
                    const nodeId = readString(row, 'node_id', mapping);
                    const title = readString(row, 'title', mapping);
                    if (issueNumber === null || !nodeId || !title || !htmlUrl) {
                        continue;
                    }

                    const rawReason = readString(row, 'state_reason', mapping);
                    const validReason: GitHubIssueStateReason | null =
                        rawReason === 'completed' ||
                        rawReason === 'not_planned' ||
                        rawReason === 'reopened' ||
                        rawReason === 'duplicate'
                            ? rawReason
                            : null;

                    const assigneeLogin = readString(row, 'assignee_login', mapping);
                    const assignees: NormalizedGitHubUserRef[] = assigneeLogin ? [{ login: assigneeLogin }] : [];
                    const rawState = (readString(row, 'state', mapping) ?? 'open').toLowerCase();
                    const issueItem: NormalizedGitHubIssueInput = {
                        kind: 'issue',
                        number: issueNumber,
                        nodeId,
                        title,
                        body: readUntrimmedString(row, 'body', mapping),
                        htmlUrl,
                        state: rawState === 'closed' ? 'closed' : 'open',
                        stateReason: validReason,
                        labels: parseMirrorLabelsJson(readUntrimmedString(row, 'labels_json', mapping)),
                        authorLogin: readString(row, 'author_login', mapping),
                        assigneeLogins: assignees.map((a) => a.login),
                        assignees,
                        updatedAt: readTimestamp(row, 'updated_at', mapping),
                    };
                    normalized.push(issueItem);
                }
            } else {
                for (const row of rows) {
                    const repoFull = readString(row, 'repository_full_name', mapping);
                    const htmlUrl = readString(row, 'html_url', mapping);
                    if (!matchesRepoFullNameOrUrl(repoFull, htmlUrl, expectedFullNameLower)) {
                        continue;
                    }
                    const prNumber = readNumber(row, 'number', mapping);
                    const nodeId = readString(row, 'node_id', mapping);
                    const title = readString(row, 'title', mapping);
                    if (prNumber === null || !nodeId || !title || !htmlUrl) {
                        continue;
                    }

                    const mergedAt = readTimestamp(row, 'merged_at', mapping);
                    const rawState = (readString(row, 'state', mapping) ?? 'open').toLowerCase();
                    const assigneeLogin = readString(row, 'assignee_login', mapping);
                    const assignees: NormalizedGitHubUserRef[] = assigneeLogin ? [{ login: assigneeLogin }] : [];
                    const body = readUntrimmedString(row, 'body', mapping);

                    const prItem: NormalizedGitHubPullRequestInput = {
                        kind: 'pull_request',
                        number: prNumber,
                        nodeId,
                        title,
                        body,
                        htmlUrl,
                        state: mergedAt !== null ? 'merged' : rawState === 'closed' ? 'closed' : 'open',
                        isDraft: readBoolean(row, 'draft', mapping),
                        headBranch: readString(row, 'head_ref', mapping),
                        headSha: readString(row, 'head_sha', mapping),
                        baseBranch: readString(row, 'base_ref', mapping),
                        authorLogin: readString(row, 'author_login', mapping),
                        assigneeLogins: assignees.map((a) => a.login),
                        assignees,
                        labels: parseMirrorLabelsJson(readUntrimmedString(row, 'labels_json', mapping)),
                        mergedAt,
                        linkedIssueNumber: extractClosingIssueNumber(body),
                        updatedAt: readTimestamp(row, 'updated_at', mapping),
                    };
                    normalized.push(prItem);
                }
            }
        }

        return normalized;
    }
}
