import { AIPromptParams } from '@memberjunction/ai-core-plus';
import { AIPromptRunner } from '@memberjunction/ai-prompts';
import { AIEngineBase } from '@memberjunction/ai-engine-base';
import {
    IMetadataProvider,
    IRunViewProvider,
    Metadata,
    RunView,
    UserInfo,
} from '@memberjunction/core';
import { BaseSingleton, UUIDsEqual } from '@memberjunction/global';
import type { mjBizAppsTasksTaskEntity } from '@mj-biz-apps/tasks-entities';
import { GitHubFieldOwnershipPolicy } from './GitHubFieldOwnershipPolicy.js';
import { AssertValidUUID, EscapeSqlLiteral, IsValidUUIDString } from './sql-safety.js';
import type {
    IFieldSuggestionEntityRecord,
    IGitHubInferenceExtractor,
    InferenceContextInput,
    InferenceExtractionResult,
    InferredPlanningSuggestionCandidate,
    TasksOwnedPlanningFieldName,
} from './types.js';

export const TASKS_ENTITY_NAME = 'MJ_BizApps_Tasks: Tasks';
export const FIELD_SUGGESTIONS_ENTITY_NAME = 'MJ: Field Suggestions';
export const CONVERSATION_TYPES_ENTITY_NAME = 'MJ: Conversation Types';
export const COMMENT_TYPES_ENTITY_NAME = 'MJ: Comment Types';
export const ENVIRONMENTS_ENTITY_NAME = 'MJ: Environments';
export const INFERENCE_PROMPT_NAME = 'GitHub Task Planning Field Inference';

interface IdRow {
    ID: string;
}

interface RawPromptJsonShape {
    suggestions?: Array<{
        field?: string;
        value?: string | number;
        confidence?: number;
        rationale?: string;
    }>;
    mentionedLogins?: string[];
}

export interface RunTaskInferenceOptions {
    task: mjBizAppsTasksTaskEntity;
    repositoryFullName: string;
    itemKind: 'issue' | 'pull_request';
    number: number;
    title: string;
    body: string | null;
    milestoneDueAt: Date | string | null;
    structuredLogins: string[];
    contextUser: UserInfo;
    provider?: IMetadataProvider & IRunViewProvider;
}

export interface RunTaskInferenceResult {
    createdCount: number;
    supersededCount: number;
    skippedFields: string[];
    unmappedMentionLogins: string[];
    createdSuggestionIds: string[];
}

class DefaultPromptInferenceExtractor implements IGitHubInferenceExtractor {
    public async ExtractPlanningSuggestions(
        input: InferenceContextInput,
        contextUser: UserInfo,
    ): Promise<InferenceExtractionResult> {
        await AIEngineBase.Instance.Config(false, contextUser);
        const prompt = AIEngineBase.Instance.Prompts.find(
            (p) => p.Name.trim().toLowerCase() === INFERENCE_PROMPT_NAME.toLowerCase(),
        );
        if (!prompt) {
            return { suggestions: [], mentionedLogins: [], promptRunId: null };
        }

        const params = new AIPromptParams();
        params.prompt = prompt;
        params.contextUser = contextUser;
        params.data = {
            repositoryFullName: input.repositoryFullName,
            itemKind: input.itemKind,
            number: input.number,
            title: input.title,
            body: input.body,
            milestoneDueAt: input.milestoneDueAt ?? 'none',
            structuredLoginsJson: JSON.stringify(input.structuredLogins),
            candidateObjectivesJson: JSON.stringify(input.candidateObjectives),
            candidateCategoriesJson: JSON.stringify(input.candidateCategories),
        };

        const runner = new AIPromptRunner();
        const result = await runner.ExecutePrompt<RawPromptJsonShape>(params);
        if (!result.success || !result.result) {
            return {
                suggestions: [],
                mentionedLogins: [],
                promptRunId: result.promptRun?.ID ?? null,
            };
        }

        const parsedSuggestions: InferredPlanningSuggestionCandidate[] = [];
        for (const candidate of result.result.suggestions ?? []) {
            if (
                typeof candidate.field === 'string' &&
                GitHubFieldOwnershipPolicy.IsTasksOwnedPlanningField(candidate.field) &&
                (typeof candidate.value === 'string' || typeof candidate.value === 'number') &&
                typeof candidate.confidence === 'number'
            ) {
                parsedSuggestions.push({
                    field: candidate.field,
                    value: candidate.value,
                    confidence: candidate.confidence,
                    rationale: typeof candidate.rationale === 'string' ? candidate.rationale : '',
                });
            }
        }

        const mentionedLogins = Array.isArray(result.result.mentionedLogins)
            ? result.result.mentionedLogins.filter((login): login is string => typeof login === 'string')
            : [];

        return {
            suggestions: parsedSuggestions,
            mentionedLogins,
            promptRunId: result.promptRun?.ID ?? null,
        };
    }
}

export class GitHubTaskInferenceService extends BaseSingleton<GitHubTaskInferenceService> {
    private _extractor: IGitHubInferenceExtractor = new DefaultPromptInferenceExtractor();

    public constructor() {
        super();
    }

    public static get Instance(): GitHubTaskInferenceService {
        return GitHubTaskInferenceService.getInstance<GitHubTaskInferenceService>();
    }

    public SetExtractor(extractor: IGitHubInferenceExtractor): void {
        this._extractor = extractor;
    }

    public ResetExtractor(): void {
        this._extractor = new DefaultPromptInferenceExtractor();
    }

    /**
     * Proposes `MJ: Field Suggestions` strictly for Tasks-owned planning fields on a GitHub-backed Task.
     * Structured GitHub fields (MilestoneDueAt, structured assignees/reviewers) and already-populated
     * human planning fields always win and are never overwritten.
     */
    public async InferTaskPlanningFields(options: RunTaskInferenceOptions): Promise<RunTaskInferenceResult> {
        const {
            task,
            repositoryFullName,
            itemKind,
            number,
            title,
            body,
            milestoneDueAt,
            structuredLogins,
            contextUser,
            provider,
        } = options;

        const cleanBody = (body ?? '').trim();
        if (!title.trim() && !cleanBody) {
            return {
                createdCount: 0,
                supersededCount: 0,
                skippedFields: [],
                unmappedMentionLogins: [],
                createdSuggestionIds: [],
            };
        }

        const md = provider ?? Metadata.Provider;
        const rv = provider ? RunView.FromMetadataProvider(provider) : new RunView();

        const [objectivesResult, categoriesResult] = await rv.RunViews([
            {
                EntityName: TASKS_ENTITY_NAME,
                ExtraFilter: `Status IN ('Open', 'InProgress')`,
                Fields: ['ID', 'Name'],
                MaxRows: 50,
                ResultType: 'simple',
            },
            {
                EntityName: 'MJ_BizApps_Tasks: Task Categories',
                ExtraFilter: `IsActive = 1`,
                Fields: ['ID', 'Name'],
                MaxRows: 50,
                ResultType: 'simple',
            },
        ], contextUser);

        const candidateObjectives = (objectivesResult?.Results as Array<{ ID: string; Name: string }> | undefined ?? [])
            .filter((o) => !UUIDsEqual(o.ID, task.ID))
            .map((o) => ({ id: o.ID, name: o.Name }));
        const candidateCategories = (categoriesResult?.Results as Array<{ ID: string; Name: string }> | undefined ?? [])
            .map((c) => ({ id: c.ID, name: c.Name }));

        const normalizedMilestoneDue = milestoneDueAt instanceof Date
            ? milestoneDueAt.toISOString()
            : (typeof milestoneDueAt === 'string' && milestoneDueAt.trim().length > 0 ? milestoneDueAt.trim() : null);

        const extraction = await this._extractor.ExtractPlanningSuggestions(
            {
                repositoryFullName,
                itemKind,
                number,
                title,
                body: cleanBody,
                milestoneDueAt: normalizedMilestoneDue,
                structuredLogins,
                candidateObjectives,
                candidateCategories,
            },
            contextUser,
            md,
        );

        const structuredLower = new Set(structuredLogins.map((l) => l.trim().toLowerCase()));
        const unmappedMentionLogins = extraction.mentionedLogins
            .map((l) => l.replace(/^@/, '').trim())
            .filter((l) => l.length > 0 && !structuredLower.has(l.toLowerCase()));

        const skippedFields: string[] = [];
        const eligibleCandidates: InferredPlanningSuggestionCandidate[] = [];

        for (const candidate of extraction.suggestions) {
            if (!GitHubFieldOwnershipPolicy.IsTasksOwnedPlanningField(candidate.field)) {
                skippedFields.push(candidate.field);
                continue;
            }
            if (candidate.confidence < 0.55 || candidate.confidence > 1) {
                skippedFields.push(candidate.field);
                continue;
            }
            if (!this.isFieldEligibleForSuggestion(task, candidate.field, candidate.value, normalizedMilestoneDue)) {
                skippedFields.push(candidate.field);
                continue;
            }
            eligibleCandidates.push(candidate);
        }

        if (eligibleCandidates.length === 0) {
            return {
                createdCount: 0,
                supersededCount: 0,
                skippedFields,
                unmappedMentionLogins,
                createdSuggestionIds: [],
            };
        }

        const tasksEntityInfo = md.Entities.find((e) => e.Name === TASKS_ENTITY_NAME);
        if (!tasksEntityInfo) {
            throw new Error(`Entity metadata not found for '${TASKS_ENTITY_NAME}'`);
        }

        const ids = await this.resolveCommentSuggestionMetadataIds(rv, contextUser);
        let supersededCount = 0;
        const createdSuggestionIds: string[] = [];

        for (const candidate of eligibleCandidates) {
            supersededCount += await this.SupersedePendingSuggestionsForField(
                tasksEntityInfo.ID,
                task.ID,
                candidate.field,
                contextUser,
                md,
                rv,
            );

            const suggestion = await md.GetEntityObject<IFieldSuggestionEntityRecord>(
                FIELD_SUGGESTIONS_ENTITY_NAME,
                contextUser,
            );
            suggestion.NewRecord();
            suggestion.UserID = contextUser.ID;
            suggestion.EnvironmentID = ids.environmentId;
            suggestion.TypeID = ids.commentConversationTypeId;
            suggestion.CommentTypeID = ids.fieldSuggestionCommentTypeId;
            suggestion.Name = `Suggested ${candidate.field} for #${number}`;
            suggestion.Description = candidate.rationale || `Inferred ${candidate.field} from GitHub ${itemKind} #${number}.`;
            suggestion.Status = 'Available';
            suggestion.ApplicationScope = 'Global';
            suggestion.IsArchived = false;
            suggestion.IsPinned = false;
            suggestion.IsResolved = false;
            suggestion.LinkedEntityID = tasksEntityInfo.ID;
            suggestion.LinkedRecordID = task.ID;
            suggestion.AnchorType = 'Field';
            suggestion.AnchorKey = candidate.field;
            suggestion.SuggestedValue = this.serializeSuggestedValue(candidate.field, candidate.value);
            suggestion.Confidence = Number(candidate.confidence.toFixed(4));
            suggestion.Source = 'LLM';
            suggestion.Outcome = null;
            if (IsValidUUIDString(extraction.promptRunId)) {
                suggestion.AIPromptRunID = extraction.promptRunId;
            }

            const saved = await suggestion.Save();
            if (!saved) {
                const errMsg = suggestion.LatestResult?.CompleteMessage ?? 'Unknown save error';
                throw new Error(`Failed saving MJ: Field Suggestions for '${candidate.field}': ${errMsg}`);
            }
            createdSuggestionIds.push(suggestion.ID);
        }

        return {
            createdCount: createdSuggestionIds.length,
            supersededCount,
            skippedFields,
            unmappedMentionLogins,
            createdSuggestionIds,
        };
    }

    /**
     * Marks any pending (`Outcome IS NULL AND IsResolved = 0`) Field Suggestions on a specific
     * `(entityId, recordId, fieldName)` anchor as `Superseded`.
     */
    public async SupersedePendingSuggestionsForField(
        linkedEntityId: string,
        linkedRecordId: string,
        fieldName: string,
        contextUser: UserInfo,
        provider?: IMetadataProvider,
        runView?: RunView,
    ): Promise<number> {
        const cleanEntityId = AssertValidUUID(linkedEntityId, 'linkedEntityId');
        const cleanRecordId = AssertValidUUID(linkedRecordId, 'linkedRecordId');
        const safeField = EscapeSqlLiteral(fieldName);

        const md = provider ?? Metadata.Provider;
        const rv = runView ?? new RunView();

        const pendingResult = await rv.RunView<IFieldSuggestionEntityRecord>(
            {
                EntityName: FIELD_SUGGESTIONS_ENTITY_NAME,
                ExtraFilter:
                    `LinkedEntityID = '${cleanEntityId}' ` +
                    `AND LinkedRecordID = '${cleanRecordId}' ` +
                    `AND AnchorType = 'field' ` +
                    `AND AnchorKey = '${safeField}' ` +
                    `AND Outcome IS NULL AND IsResolved = 0`,
                ResultType: 'entity_object',
            },
            contextUser,
        );

        if (!pendingResult.Success) {
            throw new Error(`Failed querying pending Field Suggestions: ${pendingResult.ErrorMessage}`);
        }

        let count = 0;
        for (const existing of pendingResult.Results ?? []) {
            existing.Outcome = 'Superseded';
            existing.IsResolved = true;
            existing.ResolvedByUserID = contextUser.ID;
            existing.ResolvedAt = new Date();
            const saved = await existing.Save();
            if (!saved) {
                const entityCopy = await md.GetEntityObject<IFieldSuggestionEntityRecord>(
                    FIELD_SUGGESTIONS_ENTITY_NAME,
                    contextUser,
                );
                if (await entityCopy.Load(existing.ID)) {
                    entityCopy.Outcome = 'Superseded';
                    entityCopy.IsResolved = true;
                    entityCopy.ResolvedByUserID = contextUser.ID;
                    entityCopy.ResolvedAt = new Date();
                    const retrySaved = await entityCopy.Save();
                    if (!retrySaved) {
                        throw new Error(
                            `Failed superseding Field Suggestion '${existing.ID}': ${entityCopy.LatestResult?.CompleteMessage ?? 'save failed'}`,
                        );
                    }
                }
            }
            count += 1;
        }
        return count;
    }

    private isFieldEligibleForSuggestion(
        task: mjBizAppsTasksTaskEntity,
        field: TasksOwnedPlanningFieldName,
        value: string | number,
        milestoneDueAt: string | null,
    ): boolean {
        switch (field) {
            case 'DueAt': {
                if (milestoneDueAt != null || task.DueAt != null) {
                    return false;
                }
                if (typeof value !== 'string') return false;
                const parsed = Date.parse(value);
                return !Number.isNaN(parsed);
            }
            case 'HoursEstimated': {
                if (task.HoursEstimated != null) {
                    return false;
                }
                const num = typeof value === 'number' ? value : Number(value);
                return Number.isFinite(num) && num > 0;
            }
            case 'ParentID': {
                if (task.ParentID != null) {
                    return false;
                }
                return typeof value === 'string' && IsValidUUIDString(value) && !UUIDsEqual(value, task.ID);
            }
            case 'CategoryID': {
                if (task.CategoryID != null) {
                    return false;
                }
                return typeof value === 'string' && IsValidUUIDString(value);
            }
            case 'Priority': {
                return (
                    typeof value === 'string' &&
                    (['Low', 'Medium', 'High', 'Urgent'] as const).includes(
                        value as 'Low' | 'Medium' | 'High' | 'Urgent',
                    )
                );
            }
            default: {
                const _exhaustive: never = field;
                return _exhaustive;
            }
        }
    }

    private serializeSuggestedValue(field: TasksOwnedPlanningFieldName, value: string | number): string {
        if (field === 'HoursEstimated') {
            const num = typeof value === 'number' ? value : Number(value);
            return JSON.stringify(num);
        }
        return JSON.stringify(String(value));
    }

    private async resolveCommentSuggestionMetadataIds(
        rv: RunView,
        contextUser: UserInfo,
    ): Promise<{
        environmentId: string;
        commentConversationTypeId: string;
        fieldSuggestionCommentTypeId: string;
    }> {
        const [envRes, convTypeRes, commentTypeRes] = await rv.RunViews([
            {
                EntityName: ENVIRONMENTS_ENTITY_NAME,
                Fields: ['ID'],
                MaxRows: 1,
                ResultType: 'simple',
            },
            {
                EntityName: CONVERSATION_TYPES_ENTITY_NAME,
                ExtraFilter: `Code = 'COMMENT'`,
                Fields: ['ID'],
                MaxRows: 1,
                ResultType: 'simple',
            },
            {
                EntityName: COMMENT_TYPES_ENTITY_NAME,
                ExtraFilter: `Code = 'FIELD_SUGGESTION'`,
                Fields: ['ID'],
                MaxRows: 1,
                ResultType: 'simple',
            },
        ], contextUser);

        const envRows = (envRes?.Results as IdRow[] | undefined) ?? [];
        const convRows = (convTypeRes?.Results as IdRow[] | undefined) ?? [];
        const commentRows = (commentTypeRes?.Results as IdRow[] | undefined) ?? [];

        if (envRows.length === 0) {
            throw new Error(`No MJ: Environments record found for Field Suggestion creation`);
        }
        if (convRows.length === 0) {
            throw new Error(`No MJ: Conversation Types record with Code='COMMENT' found`);
        }
        if (commentRows.length === 0) {
            throw new Error(`No MJ: Comment Types record with Code='FIELD_SUGGESTION' found`);
        }

        return {
            environmentId: envRows[0].ID,
            commentConversationTypeId: convRows[0].ID,
            fieldSuggestionCommentTypeId: commentRows[0].ID,
        };
    }
}
