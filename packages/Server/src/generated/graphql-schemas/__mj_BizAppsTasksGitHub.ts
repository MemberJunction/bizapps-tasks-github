/********************************************************************************
* ALL ENTITIES - TypeGraphQL Type Class Definition - AUTO GENERATED FILE
* Generated Entities and Resolvers for Server
*
*   >>> DO NOT MODIFY THIS FILE!!!!!!!!!!!!
*   >>> YOUR CHANGES WILL BE OVERWRITTEN
*   >>> THE NEXT TIME THIS FILE IS GENERATED
*
**********************************************************************************/
import { Arg, Ctx, Int, Query, Resolver, Field, Float, ObjectType, InputType, Mutation,
            PubSub, PubSubEngine, ResolverBase, RunViewByIDInput, RunViewByNameInput, RunDynamicViewInput,
            AppContext, KeyValuePairInput, DeleteOptionsInput, GraphQLTimestamp as Timestamp,
            GetReadOnlyProvider, GetReadWriteProvider, RestoreContextInput } from '@memberjunction/server';
import { Metadata, EntityPermissionType, CompositeKey, UserInfo } from '@memberjunction/core'

import { MaxLength } from 'class-validator';
import * as mj_core_schema_server_object_types from '@memberjunction/server'


import { mjBizAppsTasksGitHubGitHubIdentityEntity, mjBizAppsTasksGitHubGitHubIssueTaskEntity, mjBizAppsTasksGitHubGitHubPullRequestTaskEntity, mjBizAppsTasksGitHubGitHubRepositoryEntity } from '@mj-biz-apps/tasks-github-entities';
    

//****************************************************************************
// ENTITY CLASS for MJ_BizApps_Tasks_GitHub: Git Hub Identities
//****************************************************************************
@ObjectType({ description: "Maps GitHub user logins to BizApps Common Person records so GitHub issue/PR assignees and requested reviewers synchronize into Primary and Reviewer TaskAssignment rows." })
export class mjBizAppsTasksGitHubGitHubIdentity_ {
    @Field() 
    @MaxLength(36)
    ID: string;
        
    @Field({nullable: true, description: "Case-insensitive GitHub username / handle (e.g. octocat)."}) 
    @MaxLength(100)
    GitHubLogin?: string;
        
    @Field({nullable: true, description: "Target BizApps Common Person record associated with this GitHub login."}) 
    @MaxLength(36)
    PersonID?: string;
        
    @Field({nullable: true, description: "Optional numeric or GraphQL node identifier for the GitHub user account."}) 
    @MaxLength(64)
    GitHubUserID?: string;
        
    @Field(() => Boolean, {nullable: true, description: "Whether this login mapping is currently active for task import and assignment resolution."}) 
    IsActive?: boolean;
        
    @Field() 
    _mj__CreatedAt: Date;
        
    @Field() 
    _mj__UpdatedAt: Date;
        
    @Field({nullable: true}) 
    @MaxLength(250)
    Person?: string;
        
    @Field(() => [String], { nullable: true, description: `Field-level security: when non-null, the fields on this entity the calling user may read. Any other field arriving as null was withheld by the server rather than genuinely empty. Null for callers with no field restrictions.` })
    ReadableFields___?: string[];
        
}

//****************************************************************************
// INPUT TYPE for MJ_BizApps_Tasks_GitHub: Git Hub Identities
//****************************************************************************
@InputType()
export class CreatemjBizAppsTasksGitHubGitHubIdentityInput {
    @Field({ nullable: true })
    ID?: string;

    @Field({ nullable: true })
    GitHubLogin?: string;

    @Field({ nullable: true })
    PersonID?: string;

    @Field({ nullable: true })
    GitHubUserID: string | null;

    @Field(() => Boolean, { nullable: true })
    IsActive?: boolean;

    @Field(() => RestoreContextInput, { nullable: true })
    RestoreContext___?: RestoreContextInput;
}
    

//****************************************************************************
// INPUT TYPE for MJ_BizApps_Tasks_GitHub: Git Hub Identities
//****************************************************************************
@InputType()
export class UpdatemjBizAppsTasksGitHubGitHubIdentityInput {
    @Field()
    ID: string;

    @Field({ nullable: true })
    GitHubLogin?: string;

    @Field({ nullable: true })
    PersonID?: string;

    @Field({ nullable: true })
    GitHubUserID?: string | null;

    @Field(() => Boolean, { nullable: true })
    IsActive?: boolean;

    @Field(() => [KeyValuePairInput], { nullable: true })
    OldValues___?: KeyValuePairInput[];

    @Field(() => RestoreContextInput, { nullable: true })
    RestoreContext___?: RestoreContextInput;
}
    
//****************************************************************************
// RESOLVER for MJ_BizApps_Tasks_GitHub: Git Hub Identities
//****************************************************************************
@ObjectType()
export class RunmjBizAppsTasksGitHubGitHubIdentityViewResult {
    @Field(() => [mjBizAppsTasksGitHubGitHubIdentity_])
    Results: mjBizAppsTasksGitHubGitHubIdentity_[];

    @Field(() => String, {nullable: true})
    UserViewRunID?: string;

    @Field(() => Int, {nullable: true})
    RowCount: number;

    @Field(() => Int, {nullable: true})
    TotalRowCount: number;

    @Field(() => Int, {nullable: true})
    ExecutionTime: number;

    @Field({nullable: true})
    ErrorMessage?: string;

    @Field(() => Boolean, {nullable: false})
    Success: boolean;
}

@Resolver(mjBizAppsTasksGitHubGitHubIdentity_)
export class mjBizAppsTasksGitHubGitHubIdentityResolver extends ResolverBase {
    @Query(() => RunmjBizAppsTasksGitHubGitHubIdentityViewResult)
    async RunmjBizAppsTasksGitHubGitHubIdentityViewByID(@Arg('input', () => RunViewByIDInput) input: RunViewByIDInput, @Ctx() { providers, userPayload }: AppContext, @PubSub() pubSub: PubSubEngine) {
        const provider = GetReadOnlyProvider(providers, { allowFallbackToReadWrite: true });
        return super.RunViewByIDGeneric(input, provider, userPayload, pubSub);
    }

    @Query(() => RunmjBizAppsTasksGitHubGitHubIdentityViewResult)
    async RunmjBizAppsTasksGitHubGitHubIdentityViewByName(@Arg('input', () => RunViewByNameInput) input: RunViewByNameInput, @Ctx() { providers, userPayload }: AppContext, @PubSub() pubSub: PubSubEngine) {
        const provider = GetReadOnlyProvider(providers, { allowFallbackToReadWrite: true });
        return super.RunViewByNameGeneric(input, provider, userPayload, pubSub);
    }

    @Query(() => RunmjBizAppsTasksGitHubGitHubIdentityViewResult)
    async RunmjBizAppsTasksGitHubGitHubIdentityDynamicView(@Arg('input', () => RunDynamicViewInput) input: RunDynamicViewInput, @Ctx() { providers, userPayload }: AppContext, @PubSub() pubSub: PubSubEngine) {
        const provider = GetReadOnlyProvider(providers, { allowFallbackToReadWrite: true });
        input.EntityName = 'MJ_BizApps_Tasks_GitHub: Git Hub Identities';
        return super.RunDynamicViewGeneric(input, provider, userPayload, pubSub);
    }
    @Query(() => mjBizAppsTasksGitHubGitHubIdentity_, { nullable: true })
    async mjBizAppsTasksGitHubGitHubIdentity(@Arg('ID', () => String) ID: string, @Ctx() { userPayload, providers }: AppContext, @PubSub() pubSub: PubSubEngine): Promise<mjBizAppsTasksGitHubGitHubIdentity_ | null> {
        this.CheckUserReadPermissions('MJ_BizApps_Tasks_GitHub: Git Hub Identities', userPayload);
        const provider = GetReadOnlyProvider(providers, { allowFallbackToReadWrite: true });
        const sSQL = `SELECT * FROM ${provider.QuoteSchemaAndView('__mj_BizAppsTasksGitHub', 'vwGitHubIdentities')} WHERE ${provider.QuoteIdentifier('ID')}=${provider.BuildParameterPlaceholder(0)} ` + this.getRowLevelSecurityWhereClause(provider, 'MJ_BizApps_Tasks_GitHub: Git Hub Identities', userPayload, EntityPermissionType.Read, 'AND');
        const rows = await provider.ExecuteSQL(sSQL, [ID], undefined, this.GetUserFromPayload(userPayload));
        const result = await this.MapFieldNamesToCodeNames('MJ_BizApps_Tasks_GitHub: Git Hub Identities', rows && rows.length > 0 ? rows[0] : null, this.GetUserFromPayload(userPayload));
        return result;
    }
    
    @Mutation(() => mjBizAppsTasksGitHubGitHubIdentity_)
    async CreatemjBizAppsTasksGitHubGitHubIdentity(
        @Arg('input', () => CreatemjBizAppsTasksGitHubGitHubIdentityInput) input: CreatemjBizAppsTasksGitHubGitHubIdentityInput,
        @Ctx() { providers, userPayload }: AppContext,
        @PubSub() pubSub: PubSubEngine
    ) {
        const provider = GetReadWriteProvider(providers);
        return this.CreateRecord('MJ_BizApps_Tasks_GitHub: Git Hub Identities', input, provider, userPayload, pubSub)
    }
        
    @Mutation(() => mjBizAppsTasksGitHubGitHubIdentity_)
    async UpdatemjBizAppsTasksGitHubGitHubIdentity(
        @Arg('input', () => UpdatemjBizAppsTasksGitHubGitHubIdentityInput) input: UpdatemjBizAppsTasksGitHubGitHubIdentityInput,
        @Ctx() { providers, userPayload }: AppContext,
        @PubSub() pubSub: PubSubEngine
    ) {
        const provider = GetReadWriteProvider(providers);
        return this.UpdateRecord('MJ_BizApps_Tasks_GitHub: Git Hub Identities', input, provider, userPayload, pubSub);
    }
    
    @Mutation(() => mjBizAppsTasksGitHubGitHubIdentity_)
    async DeletemjBizAppsTasksGitHubGitHubIdentity(@Arg('ID', () => String) ID: string, @Arg('options___', () => DeleteOptionsInput) options: DeleteOptionsInput, @Ctx() { providers, userPayload }: AppContext, @PubSub() pubSub: PubSubEngine) {
        const provider = GetReadWriteProvider(providers);
        const key = new CompositeKey([{FieldName: 'ID', Value: ID}]);
        return this.DeleteRecord('MJ_BizApps_Tasks_GitHub: Git Hub Identities', key, options, provider, userPayload, pubSub);
    }
    
}

//****************************************************************************
// ENTITY CLASS for MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks
//****************************************************************************
@ObjectType({ description: "Disjoint IS-A child of MJ_BizApps_Tasks: Tasks for GITHUB_ISSUE tasks, storing GitHub-owned issue metadata, milestone dates, and idempotent external sync keys." })
export class mjBizAppsTasksGitHubGitHubIssueTask_ {
    @Field({description: "Shared primary key referencing __mj_BizAppsTasks.Task(ID)."}) 
    @MaxLength(36)
    ID: string;
        
    @Field({nullable: true, description: "GitHubRepository to which this issue belongs."}) 
    @MaxLength(36)
    RepositoryID?: string;
        
    @Field(() => Int, {nullable: true, description: "Repository-scoped GitHub issue number (#N). Unique per RepositoryID when populated."}) 
    Number?: number;
        
    @Field({nullable: true, description: "Global GitHub GraphQL node identifier for idempotent cross-rename sync."}) 
    @MaxLength(128)
    NodeID?: string;
        
    @Field({nullable: true, description: "Canonical browser URL to view or edit the issue on GitHub."}) 
    @MaxLength(1000)
    HtmlURL?: string;
        
    @Field({nullable: true, description: "GitHub issue state (open or closed)."}) 
    @MaxLength(20)
    State?: string;
        
    @Field({nullable: true, description: "Optional GitHub issue state_reason (completed, not_planned, reopened, duplicate)."}) 
    @MaxLength(40)
    StateReason?: string;
        
    @Field({nullable: true, description: "JSON array of GitHub label names applied to the issue."}) 
    Labels?: string;
        
    @Field({nullable: true, description: "GitHub milestone title when assigned."}) 
    @MaxLength(255)
    Milestone?: string;
        
    @Field({nullable: true, description: "Due timestamp of the GitHub milestone; supersedes pending inferred DueAt Field Suggestions."}) 
    MilestoneDueAt?: Date;
        
    @Field({nullable: true, description: "GitHub login of the user who opened the issue."}) 
    @MaxLength(100)
    AuthorLogin?: string;
        
    @Field({nullable: true, description: "SHA-256 hash of the last synced issue body used to detect text edits and trigger Field Suggestion re-inference."}) 
    @MaxLength(64)
    BodyHash?: string;
        
    @Field({nullable: true, description: "Upstream updated_at timestamp reported by GitHub."}) 
    GitHubUpdatedAt?: Date;
        
    @Field({nullable: true, description: "Timestamp when BizApps Tasks GitHub sync last reconciled this issue."}) 
    LastSyncedAt?: Date;
        
    @Field() 
    _mj__CreatedAt: Date;
        
    @Field() 
    _mj__UpdatedAt: Date;
        
    @Field({nullable: true}) 
    @MaxLength(255)
    Name?: string;
        
    @Field({nullable: true}) 
    Description?: string;
        
    @Field({nullable: true}) 
    @MaxLength(36)
    TypeID?: string;
        
    @Field({nullable: true}) 
    @MaxLength(36)
    CategoryID?: string;
        
    @Field({nullable: true}) 
    @MaxLength(36)
    ParentID?: string;
        
    @Field({nullable: true}) 
    @MaxLength(50)
    Status?: string;
        
    @Field({nullable: true}) 
    @MaxLength(20)
    Priority?: string;
        
    @Field({nullable: true}) 
    StartedAt?: Date;
        
    @Field({nullable: true}) 
    DueAt?: Date;
        
    @Field({nullable: true}) 
    CompletedAt?: Date;
        
    @Field(() => Float, {nullable: true}) 
    HoursEstimated?: number;
        
    @Field(() => Float, {nullable: true}) 
    HoursActual?: number;
        
    @Field(() => Int, {nullable: true}) 
    PercentComplete?: number;
        
    @Field(() => Int, {nullable: true}) 
    Sequence?: number;
        
    @Field({nullable: true}) 
    BlockedReason?: string;
        
    @Field({nullable: true}) 
    CompletionNotes?: string;
        
    @Field({nullable: true}) 
    @MaxLength(36)
    CreatedByPersonID?: string;
        
    @Field({nullable: true}) 
    OverdueNotifiedAt?: Date;
        
    @Field({nullable: true}) 
    @MaxLength(36)
    TaskTypeStatusID?: string;
        
    @Field(() => Float, {nullable: true}) 
    PredictedSLABreachProbability?: number;
        
    @Field({nullable: true}) 
    @MaxLength(20)
    PredictedSLARiskBand?: string;
        
    @Field({nullable: true}) 
    PredictedSLAScoredAt?: Date;
        
    @Field({nullable: true}) 
    @MaxLength(20)
    HealthStatus?: string;
        
    @Field(() => Int, {nullable: true}) 
    ConfidenceScore?: number;
        
    @Field(() => Float, {nullable: true}) 
    BaselineValue?: number;
        
    @Field(() => Float, {nullable: true}) 
    TargetValue?: number;
        
    @Field(() => Float, {nullable: true}) 
    CurrentValue?: number;
        
    @Field({nullable: true}) 
    @MaxLength(50)
    UnitOfMeasure?: string;
        
    @Field({nullable: true}) 
    @MaxLength(20)
    MetricDirection?: string;
        
    @Field(() => Float, {nullable: true}) 
    RollupWeight?: number;
        
    @Field({nullable: true}) 
    @MaxLength(50)
    PlanningPeriod?: string;
        
    @Field({nullable: true}) 
    @MaxLength(20)
    CheckInCadence?: string;
        
    @Field({nullable: true}) 
    LastCheckInAt?: Date;
        
    @Field({nullable: true}) 
    NextCheckInDueAt?: Date;
        
    @Field({nullable: true}) 
    @MaxLength(200)
    Repository?: string;
        
    @Field(() => [String], { nullable: true, description: `Field-level security: when non-null, the fields on this entity the calling user may read. Any other field arriving as null was withheld by the server rather than genuinely empty. Null for callers with no field restrictions.` })
    ReadableFields___?: string[];
        
}

//****************************************************************************
// INPUT TYPE for MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks
//****************************************************************************
@InputType()
export class CreatemjBizAppsTasksGitHubGitHubIssueTaskInput {
    @Field({ nullable: true })
    ID?: string;

    @Field({ nullable: true })
    RepositoryID: string | null;

    @Field(() => Int, { nullable: true })
    Number: number | null;

    @Field({ nullable: true })
    NodeID: string | null;

    @Field({ nullable: true })
    HtmlURL: string | null;

    @Field({ nullable: true })
    State?: string;

    @Field({ nullable: true })
    StateReason: string | null;

    @Field({ nullable: true })
    Labels: string | null;

    @Field({ nullable: true })
    Milestone: string | null;

    @Field({ nullable: true })
    MilestoneDueAt: Date | null;

    @Field({ nullable: true })
    AuthorLogin: string | null;

    @Field({ nullable: true })
    BodyHash: string | null;

    @Field({ nullable: true })
    GitHubUpdatedAt: Date | null;

    @Field({ nullable: true })
    LastSyncedAt: Date | null;

    @Field({ nullable: true })
    Name?: string;

    @Field({ nullable: true })
    Description: string | null;

    @Field({ nullable: true })
    TypeID?: string;

    @Field({ nullable: true })
    CategoryID: string | null;

    @Field({ nullable: true })
    ParentID: string | null;

    @Field({ nullable: true })
    Status?: string;

    @Field({ nullable: true })
    Priority?: string;

    @Field({ nullable: true })
    StartedAt: Date | null;

    @Field({ nullable: true })
    DueAt: Date | null;

    @Field({ nullable: true })
    CompletedAt: Date | null;

    @Field(() => Float, { nullable: true })
    HoursEstimated: number | null;

    @Field(() => Float, { nullable: true })
    HoursActual: number | null;

    @Field(() => Int, { nullable: true })
    PercentComplete?: number;

    @Field(() => Int, { nullable: true })
    Sequence?: number;

    @Field({ nullable: true })
    BlockedReason: string | null;

    @Field({ nullable: true })
    CompletionNotes: string | null;

    @Field({ nullable: true })
    CreatedByPersonID: string | null;

    @Field({ nullable: true })
    OverdueNotifiedAt: Date | null;

    @Field({ nullable: true })
    TaskTypeStatusID: string | null;

    @Field(() => Float, { nullable: true })
    PredictedSLABreachProbability: number | null;

    @Field({ nullable: true })
    PredictedSLARiskBand: string | null;

    @Field({ nullable: true })
    PredictedSLAScoredAt: Date | null;

    @Field({ nullable: true })
    HealthStatus: string | null;

    @Field(() => Int, { nullable: true })
    ConfidenceScore: number | null;

    @Field(() => Float, { nullable: true })
    BaselineValue: number | null;

    @Field(() => Float, { nullable: true })
    TargetValue: number | null;

    @Field(() => Float, { nullable: true })
    CurrentValue: number | null;

    @Field({ nullable: true })
    UnitOfMeasure: string | null;

    @Field({ nullable: true })
    MetricDirection: string | null;

    @Field(() => Float, { nullable: true })
    RollupWeight?: number;

    @Field({ nullable: true })
    PlanningPeriod: string | null;

    @Field({ nullable: true })
    CheckInCadence: string | null;

    @Field({ nullable: true })
    LastCheckInAt: Date | null;

    @Field({ nullable: true })
    NextCheckInDueAt: Date | null;

    @Field(() => RestoreContextInput, { nullable: true })
    RestoreContext___?: RestoreContextInput;
}
    

//****************************************************************************
// INPUT TYPE for MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks
//****************************************************************************
@InputType()
export class UpdatemjBizAppsTasksGitHubGitHubIssueTaskInput {
    @Field()
    ID: string;

    @Field({ nullable: true })
    RepositoryID?: string | null;

    @Field(() => Int, { nullable: true })
    Number?: number | null;

    @Field({ nullable: true })
    NodeID?: string | null;

    @Field({ nullable: true })
    HtmlURL?: string | null;

    @Field({ nullable: true })
    State?: string;

    @Field({ nullable: true })
    StateReason?: string | null;

    @Field({ nullable: true })
    Labels?: string | null;

    @Field({ nullable: true })
    Milestone?: string | null;

    @Field({ nullable: true })
    MilestoneDueAt?: Date | null;

    @Field({ nullable: true })
    AuthorLogin?: string | null;

    @Field({ nullable: true })
    BodyHash?: string | null;

    @Field({ nullable: true })
    GitHubUpdatedAt?: Date | null;

    @Field({ nullable: true })
    LastSyncedAt?: Date | null;

    @Field({ nullable: true })
    Name?: string;

    @Field({ nullable: true })
    Description?: string | null;

    @Field({ nullable: true })
    TypeID?: string;

    @Field({ nullable: true })
    CategoryID?: string | null;

    @Field({ nullable: true })
    ParentID?: string | null;

    @Field({ nullable: true })
    Status?: string;

    @Field({ nullable: true })
    Priority?: string;

    @Field({ nullable: true })
    StartedAt?: Date | null;

    @Field({ nullable: true })
    DueAt?: Date | null;

    @Field({ nullable: true })
    CompletedAt?: Date | null;

    @Field(() => Float, { nullable: true })
    HoursEstimated?: number | null;

    @Field(() => Float, { nullable: true })
    HoursActual?: number | null;

    @Field(() => Int, { nullable: true })
    PercentComplete?: number;

    @Field(() => Int, { nullable: true })
    Sequence?: number;

    @Field({ nullable: true })
    BlockedReason?: string | null;

    @Field({ nullable: true })
    CompletionNotes?: string | null;

    @Field({ nullable: true })
    CreatedByPersonID?: string | null;

    @Field({ nullable: true })
    OverdueNotifiedAt?: Date | null;

    @Field({ nullable: true })
    TaskTypeStatusID?: string | null;

    @Field(() => Float, { nullable: true })
    PredictedSLABreachProbability?: number | null;

    @Field({ nullable: true })
    PredictedSLARiskBand?: string | null;

    @Field({ nullable: true })
    PredictedSLAScoredAt?: Date | null;

    @Field({ nullable: true })
    HealthStatus?: string | null;

    @Field(() => Int, { nullable: true })
    ConfidenceScore?: number | null;

    @Field(() => Float, { nullable: true })
    BaselineValue?: number | null;

    @Field(() => Float, { nullable: true })
    TargetValue?: number | null;

    @Field(() => Float, { nullable: true })
    CurrentValue?: number | null;

    @Field({ nullable: true })
    UnitOfMeasure?: string | null;

    @Field({ nullable: true })
    MetricDirection?: string | null;

    @Field(() => Float, { nullable: true })
    RollupWeight?: number;

    @Field({ nullable: true })
    PlanningPeriod?: string | null;

    @Field({ nullable: true })
    CheckInCadence?: string | null;

    @Field({ nullable: true })
    LastCheckInAt?: Date | null;

    @Field({ nullable: true })
    NextCheckInDueAt?: Date | null;

    @Field(() => [KeyValuePairInput], { nullable: true })
    OldValues___?: KeyValuePairInput[];

    @Field(() => RestoreContextInput, { nullable: true })
    RestoreContext___?: RestoreContextInput;
}
    
//****************************************************************************
// RESOLVER for MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks
//****************************************************************************
@ObjectType()
export class RunmjBizAppsTasksGitHubGitHubIssueTaskViewResult {
    @Field(() => [mjBizAppsTasksGitHubGitHubIssueTask_])
    Results: mjBizAppsTasksGitHubGitHubIssueTask_[];

    @Field(() => String, {nullable: true})
    UserViewRunID?: string;

    @Field(() => Int, {nullable: true})
    RowCount: number;

    @Field(() => Int, {nullable: true})
    TotalRowCount: number;

    @Field(() => Int, {nullable: true})
    ExecutionTime: number;

    @Field({nullable: true})
    ErrorMessage?: string;

    @Field(() => Boolean, {nullable: false})
    Success: boolean;
}

@Resolver(mjBizAppsTasksGitHubGitHubIssueTask_)
export class mjBizAppsTasksGitHubGitHubIssueTaskResolver extends ResolverBase {
    @Query(() => RunmjBizAppsTasksGitHubGitHubIssueTaskViewResult)
    async RunmjBizAppsTasksGitHubGitHubIssueTaskViewByID(@Arg('input', () => RunViewByIDInput) input: RunViewByIDInput, @Ctx() { providers, userPayload }: AppContext, @PubSub() pubSub: PubSubEngine) {
        const provider = GetReadOnlyProvider(providers, { allowFallbackToReadWrite: true });
        return super.RunViewByIDGeneric(input, provider, userPayload, pubSub);
    }

    @Query(() => RunmjBizAppsTasksGitHubGitHubIssueTaskViewResult)
    async RunmjBizAppsTasksGitHubGitHubIssueTaskViewByName(@Arg('input', () => RunViewByNameInput) input: RunViewByNameInput, @Ctx() { providers, userPayload }: AppContext, @PubSub() pubSub: PubSubEngine) {
        const provider = GetReadOnlyProvider(providers, { allowFallbackToReadWrite: true });
        return super.RunViewByNameGeneric(input, provider, userPayload, pubSub);
    }

    @Query(() => RunmjBizAppsTasksGitHubGitHubIssueTaskViewResult)
    async RunmjBizAppsTasksGitHubGitHubIssueTaskDynamicView(@Arg('input', () => RunDynamicViewInput) input: RunDynamicViewInput, @Ctx() { providers, userPayload }: AppContext, @PubSub() pubSub: PubSubEngine) {
        const provider = GetReadOnlyProvider(providers, { allowFallbackToReadWrite: true });
        input.EntityName = 'MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks';
        return super.RunDynamicViewGeneric(input, provider, userPayload, pubSub);
    }
    @Query(() => mjBizAppsTasksGitHubGitHubIssueTask_, { nullable: true })
    async mjBizAppsTasksGitHubGitHubIssueTask(@Arg('ID', () => String) ID: string, @Ctx() { userPayload, providers }: AppContext, @PubSub() pubSub: PubSubEngine): Promise<mjBizAppsTasksGitHubGitHubIssueTask_ | null> {
        this.CheckUserReadPermissions('MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks', userPayload);
        const provider = GetReadOnlyProvider(providers, { allowFallbackToReadWrite: true });
        const sSQL = `SELECT * FROM ${provider.QuoteSchemaAndView('__mj_BizAppsTasksGitHub', 'vwGitHubIssueTasks')} WHERE ${provider.QuoteIdentifier('ID')}=${provider.BuildParameterPlaceholder(0)} ` + this.getRowLevelSecurityWhereClause(provider, 'MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks', userPayload, EntityPermissionType.Read, 'AND');
        const rows = await provider.ExecuteSQL(sSQL, [ID], undefined, this.GetUserFromPayload(userPayload));
        const result = await this.MapFieldNamesToCodeNames('MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks', rows && rows.length > 0 ? rows[0] : null, this.GetUserFromPayload(userPayload));
        return result;
    }
    
    @Mutation(() => mjBizAppsTasksGitHubGitHubIssueTask_)
    async CreatemjBizAppsTasksGitHubGitHubIssueTask(
        @Arg('input', () => CreatemjBizAppsTasksGitHubGitHubIssueTaskInput) input: CreatemjBizAppsTasksGitHubGitHubIssueTaskInput,
        @Ctx() { providers, userPayload }: AppContext,
        @PubSub() pubSub: PubSubEngine
    ) {
        const provider = GetReadWriteProvider(providers);
        return this.CreateRecord('MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks', input, provider, userPayload, pubSub)
    }
        
    @Mutation(() => mjBizAppsTasksGitHubGitHubIssueTask_)
    async UpdatemjBizAppsTasksGitHubGitHubIssueTask(
        @Arg('input', () => UpdatemjBizAppsTasksGitHubGitHubIssueTaskInput) input: UpdatemjBizAppsTasksGitHubGitHubIssueTaskInput,
        @Ctx() { providers, userPayload }: AppContext,
        @PubSub() pubSub: PubSubEngine
    ) {
        const provider = GetReadWriteProvider(providers);
        return this.UpdateRecord('MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks', input, provider, userPayload, pubSub);
    }
    
    @Mutation(() => mjBizAppsTasksGitHubGitHubIssueTask_)
    async DeletemjBizAppsTasksGitHubGitHubIssueTask(@Arg('ID', () => String) ID: string, @Arg('options___', () => DeleteOptionsInput) options: DeleteOptionsInput, @Ctx() { providers, userPayload }: AppContext, @PubSub() pubSub: PubSubEngine) {
        const provider = GetReadWriteProvider(providers);
        const key = new CompositeKey([{FieldName: 'ID', Value: ID}]);
        return this.DeleteRecord('MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks', key, options, provider, userPayload, pubSub);
    }
    
}

//****************************************************************************
// ENTITY CLASS for MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks
//****************************************************************************
@ObjectType({ description: "Disjoint IS-A child of MJ_BizApps_Tasks: Tasks for GITHUB_PR tasks, storing pull request branches, head SHA, review decision, CI checks status, diff metrics, and linked issue Task." })
export class mjBizAppsTasksGitHubGitHubPullRequestTask_ {
    @Field({description: "Shared primary key referencing __mj_BizAppsTasks.Task(ID)."}) 
    @MaxLength(36)
    ID: string;
        
    @Field({nullable: true, description: "GitHubRepository to which this pull request belongs."}) 
    @MaxLength(36)
    RepositoryID?: string;
        
    @Field(() => Int, {nullable: true, description: "Repository-scoped GitHub pull request number (#N). Unique per RepositoryID when populated."}) 
    Number?: number;
        
    @Field({nullable: true, description: "Global GitHub GraphQL node identifier for idempotent sync."}) 
    @MaxLength(128)
    NodeID?: string;
        
    @Field({nullable: true, description: "Canonical browser URL to view or review the pull request on GitHub."}) 
    @MaxLength(1000)
    HtmlURL?: string;
        
    @Field({nullable: true, description: "Pull request lifecycle state on GitHub (open, closed, or merged)."}) 
    @MaxLength(20)
    State?: string;
        
    @Field(() => Boolean, {nullable: true, description: "Whether the pull request is currently marked as a Draft on GitHub."}) 
    IsDraft?: boolean;
        
    @Field({nullable: true, description: "Source branch ref of the pull request (head.ref)."}) 
    @MaxLength(255)
    HeadBranch?: string;
        
    @Field({nullable: true, description: "Commit SHA at the tip of HeadBranch (head.sha), verified by Software Factory merge gates."}) 
    @MaxLength(64)
    HeadSha?: string;
        
    @Field({nullable: true, description: "Target branch ref into which the pull request merges (base.ref)."}) 
    @MaxLength(255)
    BaseBranch?: string;
        
    @Field({nullable: true, description: "GitHub login of the pull request author."}) 
    @MaxLength(100)
    AuthorLogin?: string;
        
    @Field({nullable: true, description: "Aggregated GitHub review decision (APPROVED, CHANGES_REQUESTED, or REVIEW_REQUIRED)."}) 
    @MaxLength(40)
    ReviewDecision?: string;
        
    @Field({nullable: true, description: "Aggregated status of required GitHub CI checks on HeadSha (Pending, Passing, Failing, Neutral)."}) 
    @MaxLength(30)
    ChecksStatus?: string;
        
    @Field(() => Int, {nullable: true, description: "Number of files touched in the pull request diff."}) 
    ChangedFiles?: number;
        
    @Field(() => Int, {nullable: true, description: "Lines added in the pull request diff."}) 
    Additions?: number;
        
    @Field(() => Int, {nullable: true, description: "Lines deleted in the pull request diff."}) 
    Deletions?: number;
        
    @Field({nullable: true, description: "JSON array of GitHub label names applied to the pull request."}) 
    Labels?: string;
        
    @Field({nullable: true, description: "GitHub milestone title when assigned."}) 
    @MaxLength(255)
    Milestone?: string;
        
    @Field({nullable: true, description: "Due timestamp of the GitHub milestone; supersedes pending inferred DueAt Field Suggestions."}) 
    MilestoneDueAt?: Date;
        
    @Field({nullable: true, description: "Timestamp when the pull request was merged on GitHub."}) 
    MergedAt?: Date;
        
    @Field({nullable: true, description: "Optional reference to the Task (e.g. GITHUB_ISSUE or FACTORY_WORK) that this pull request implements or closes."}) 
    @MaxLength(36)
    LinkedIssueTaskID?: string;
        
    @Field({nullable: true, description: "SHA-256 hash of the last synced pull request body used to detect text edits and trigger Field Suggestion re-inference."}) 
    @MaxLength(64)
    BodyHash?: string;
        
    @Field({nullable: true, description: "Upstream updated_at timestamp reported by GitHub."}) 
    GitHubUpdatedAt?: Date;
        
    @Field({nullable: true, description: "Timestamp when BizApps Tasks GitHub sync last reconciled this pull request."}) 
    LastSyncedAt?: Date;
        
    @Field() 
    _mj__CreatedAt: Date;
        
    @Field() 
    _mj__UpdatedAt: Date;
        
    @Field({nullable: true}) 
    @MaxLength(255)
    Name?: string;
        
    @Field({nullable: true}) 
    Description?: string;
        
    @Field({nullable: true}) 
    @MaxLength(36)
    TypeID?: string;
        
    @Field({nullable: true}) 
    @MaxLength(36)
    CategoryID?: string;
        
    @Field({nullable: true}) 
    @MaxLength(36)
    ParentID?: string;
        
    @Field({nullable: true}) 
    @MaxLength(50)
    Status?: string;
        
    @Field({nullable: true}) 
    @MaxLength(20)
    Priority?: string;
        
    @Field({nullable: true}) 
    StartedAt?: Date;
        
    @Field({nullable: true}) 
    DueAt?: Date;
        
    @Field({nullable: true}) 
    CompletedAt?: Date;
        
    @Field(() => Float, {nullable: true}) 
    HoursEstimated?: number;
        
    @Field(() => Float, {nullable: true}) 
    HoursActual?: number;
        
    @Field(() => Int, {nullable: true}) 
    PercentComplete?: number;
        
    @Field(() => Int, {nullable: true}) 
    Sequence?: number;
        
    @Field({nullable: true}) 
    BlockedReason?: string;
        
    @Field({nullable: true}) 
    CompletionNotes?: string;
        
    @Field({nullable: true}) 
    @MaxLength(36)
    CreatedByPersonID?: string;
        
    @Field({nullable: true}) 
    OverdueNotifiedAt?: Date;
        
    @Field({nullable: true}) 
    @MaxLength(36)
    TaskTypeStatusID?: string;
        
    @Field(() => Float, {nullable: true}) 
    PredictedSLABreachProbability?: number;
        
    @Field({nullable: true}) 
    @MaxLength(20)
    PredictedSLARiskBand?: string;
        
    @Field({nullable: true}) 
    PredictedSLAScoredAt?: Date;
        
    @Field({nullable: true}) 
    @MaxLength(20)
    HealthStatus?: string;
        
    @Field(() => Int, {nullable: true}) 
    ConfidenceScore?: number;
        
    @Field(() => Float, {nullable: true}) 
    BaselineValue?: number;
        
    @Field(() => Float, {nullable: true}) 
    TargetValue?: number;
        
    @Field(() => Float, {nullable: true}) 
    CurrentValue?: number;
        
    @Field({nullable: true}) 
    @MaxLength(50)
    UnitOfMeasure?: string;
        
    @Field({nullable: true}) 
    @MaxLength(20)
    MetricDirection?: string;
        
    @Field(() => Float, {nullable: true}) 
    RollupWeight?: number;
        
    @Field({nullable: true}) 
    @MaxLength(50)
    PlanningPeriod?: string;
        
    @Field({nullable: true}) 
    @MaxLength(20)
    CheckInCadence?: string;
        
    @Field({nullable: true}) 
    LastCheckInAt?: Date;
        
    @Field({nullable: true}) 
    NextCheckInDueAt?: Date;
        
    @Field({nullable: true}) 
    @MaxLength(200)
    Repository?: string;
        
    @Field({nullable: true}) 
    @MaxLength(255)
    LinkedIssueTask?: string;
        
    @Field(() => [String], { nullable: true, description: `Field-level security: when non-null, the fields on this entity the calling user may read. Any other field arriving as null was withheld by the server rather than genuinely empty. Null for callers with no field restrictions.` })
    ReadableFields___?: string[];
        
}

//****************************************************************************
// INPUT TYPE for MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks
//****************************************************************************
@InputType()
export class CreatemjBizAppsTasksGitHubGitHubPullRequestTaskInput {
    @Field({ nullable: true })
    ID?: string;

    @Field({ nullable: true })
    RepositoryID: string | null;

    @Field(() => Int, { nullable: true })
    Number: number | null;

    @Field({ nullable: true })
    NodeID: string | null;

    @Field({ nullable: true })
    HtmlURL: string | null;

    @Field({ nullable: true })
    State?: string;

    @Field(() => Boolean, { nullable: true })
    IsDraft?: boolean;

    @Field({ nullable: true })
    HeadBranch: string | null;

    @Field({ nullable: true })
    HeadSha: string | null;

    @Field({ nullable: true })
    BaseBranch: string | null;

    @Field({ nullable: true })
    AuthorLogin: string | null;

    @Field({ nullable: true })
    ReviewDecision: string | null;

    @Field({ nullable: true })
    ChecksStatus: string | null;

    @Field(() => Int, { nullable: true })
    ChangedFiles: number | null;

    @Field(() => Int, { nullable: true })
    Additions: number | null;

    @Field(() => Int, { nullable: true })
    Deletions: number | null;

    @Field({ nullable: true })
    Labels: string | null;

    @Field({ nullable: true })
    Milestone: string | null;

    @Field({ nullable: true })
    MilestoneDueAt: Date | null;

    @Field({ nullable: true })
    MergedAt: Date | null;

    @Field({ nullable: true })
    LinkedIssueTaskID: string | null;

    @Field({ nullable: true })
    BodyHash: string | null;

    @Field({ nullable: true })
    GitHubUpdatedAt: Date | null;

    @Field({ nullable: true })
    LastSyncedAt: Date | null;

    @Field({ nullable: true })
    Name?: string;

    @Field({ nullable: true })
    Description: string | null;

    @Field({ nullable: true })
    TypeID?: string;

    @Field({ nullable: true })
    CategoryID: string | null;

    @Field({ nullable: true })
    ParentID: string | null;

    @Field({ nullable: true })
    Status?: string;

    @Field({ nullable: true })
    Priority?: string;

    @Field({ nullable: true })
    StartedAt: Date | null;

    @Field({ nullable: true })
    DueAt: Date | null;

    @Field({ nullable: true })
    CompletedAt: Date | null;

    @Field(() => Float, { nullable: true })
    HoursEstimated: number | null;

    @Field(() => Float, { nullable: true })
    HoursActual: number | null;

    @Field(() => Int, { nullable: true })
    PercentComplete?: number;

    @Field(() => Int, { nullable: true })
    Sequence?: number;

    @Field({ nullable: true })
    BlockedReason: string | null;

    @Field({ nullable: true })
    CompletionNotes: string | null;

    @Field({ nullable: true })
    CreatedByPersonID: string | null;

    @Field({ nullable: true })
    OverdueNotifiedAt: Date | null;

    @Field({ nullable: true })
    TaskTypeStatusID: string | null;

    @Field(() => Float, { nullable: true })
    PredictedSLABreachProbability: number | null;

    @Field({ nullable: true })
    PredictedSLARiskBand: string | null;

    @Field({ nullable: true })
    PredictedSLAScoredAt: Date | null;

    @Field({ nullable: true })
    HealthStatus: string | null;

    @Field(() => Int, { nullable: true })
    ConfidenceScore: number | null;

    @Field(() => Float, { nullable: true })
    BaselineValue: number | null;

    @Field(() => Float, { nullable: true })
    TargetValue: number | null;

    @Field(() => Float, { nullable: true })
    CurrentValue: number | null;

    @Field({ nullable: true })
    UnitOfMeasure: string | null;

    @Field({ nullable: true })
    MetricDirection: string | null;

    @Field(() => Float, { nullable: true })
    RollupWeight?: number;

    @Field({ nullable: true })
    PlanningPeriod: string | null;

    @Field({ nullable: true })
    CheckInCadence: string | null;

    @Field({ nullable: true })
    LastCheckInAt: Date | null;

    @Field({ nullable: true })
    NextCheckInDueAt: Date | null;

    @Field(() => RestoreContextInput, { nullable: true })
    RestoreContext___?: RestoreContextInput;
}
    

//****************************************************************************
// INPUT TYPE for MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks
//****************************************************************************
@InputType()
export class UpdatemjBizAppsTasksGitHubGitHubPullRequestTaskInput {
    @Field()
    ID: string;

    @Field({ nullable: true })
    RepositoryID?: string | null;

    @Field(() => Int, { nullable: true })
    Number?: number | null;

    @Field({ nullable: true })
    NodeID?: string | null;

    @Field({ nullable: true })
    HtmlURL?: string | null;

    @Field({ nullable: true })
    State?: string;

    @Field(() => Boolean, { nullable: true })
    IsDraft?: boolean;

    @Field({ nullable: true })
    HeadBranch?: string | null;

    @Field({ nullable: true })
    HeadSha?: string | null;

    @Field({ nullable: true })
    BaseBranch?: string | null;

    @Field({ nullable: true })
    AuthorLogin?: string | null;

    @Field({ nullable: true })
    ReviewDecision?: string | null;

    @Field({ nullable: true })
    ChecksStatus?: string | null;

    @Field(() => Int, { nullable: true })
    ChangedFiles?: number | null;

    @Field(() => Int, { nullable: true })
    Additions?: number | null;

    @Field(() => Int, { nullable: true })
    Deletions?: number | null;

    @Field({ nullable: true })
    Labels?: string | null;

    @Field({ nullable: true })
    Milestone?: string | null;

    @Field({ nullable: true })
    MilestoneDueAt?: Date | null;

    @Field({ nullable: true })
    MergedAt?: Date | null;

    @Field({ nullable: true })
    LinkedIssueTaskID?: string | null;

    @Field({ nullable: true })
    BodyHash?: string | null;

    @Field({ nullable: true })
    GitHubUpdatedAt?: Date | null;

    @Field({ nullable: true })
    LastSyncedAt?: Date | null;

    @Field({ nullable: true })
    Name?: string;

    @Field({ nullable: true })
    Description?: string | null;

    @Field({ nullable: true })
    TypeID?: string;

    @Field({ nullable: true })
    CategoryID?: string | null;

    @Field({ nullable: true })
    ParentID?: string | null;

    @Field({ nullable: true })
    Status?: string;

    @Field({ nullable: true })
    Priority?: string;

    @Field({ nullable: true })
    StartedAt?: Date | null;

    @Field({ nullable: true })
    DueAt?: Date | null;

    @Field({ nullable: true })
    CompletedAt?: Date | null;

    @Field(() => Float, { nullable: true })
    HoursEstimated?: number | null;

    @Field(() => Float, { nullable: true })
    HoursActual?: number | null;

    @Field(() => Int, { nullable: true })
    PercentComplete?: number;

    @Field(() => Int, { nullable: true })
    Sequence?: number;

    @Field({ nullable: true })
    BlockedReason?: string | null;

    @Field({ nullable: true })
    CompletionNotes?: string | null;

    @Field({ nullable: true })
    CreatedByPersonID?: string | null;

    @Field({ nullable: true })
    OverdueNotifiedAt?: Date | null;

    @Field({ nullable: true })
    TaskTypeStatusID?: string | null;

    @Field(() => Float, { nullable: true })
    PredictedSLABreachProbability?: number | null;

    @Field({ nullable: true })
    PredictedSLARiskBand?: string | null;

    @Field({ nullable: true })
    PredictedSLAScoredAt?: Date | null;

    @Field({ nullable: true })
    HealthStatus?: string | null;

    @Field(() => Int, { nullable: true })
    ConfidenceScore?: number | null;

    @Field(() => Float, { nullable: true })
    BaselineValue?: number | null;

    @Field(() => Float, { nullable: true })
    TargetValue?: number | null;

    @Field(() => Float, { nullable: true })
    CurrentValue?: number | null;

    @Field({ nullable: true })
    UnitOfMeasure?: string | null;

    @Field({ nullable: true })
    MetricDirection?: string | null;

    @Field(() => Float, { nullable: true })
    RollupWeight?: number;

    @Field({ nullable: true })
    PlanningPeriod?: string | null;

    @Field({ nullable: true })
    CheckInCadence?: string | null;

    @Field({ nullable: true })
    LastCheckInAt?: Date | null;

    @Field({ nullable: true })
    NextCheckInDueAt?: Date | null;

    @Field(() => [KeyValuePairInput], { nullable: true })
    OldValues___?: KeyValuePairInput[];

    @Field(() => RestoreContextInput, { nullable: true })
    RestoreContext___?: RestoreContextInput;
}
    
//****************************************************************************
// RESOLVER for MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks
//****************************************************************************
@ObjectType()
export class RunmjBizAppsTasksGitHubGitHubPullRequestTaskViewResult {
    @Field(() => [mjBizAppsTasksGitHubGitHubPullRequestTask_])
    Results: mjBizAppsTasksGitHubGitHubPullRequestTask_[];

    @Field(() => String, {nullable: true})
    UserViewRunID?: string;

    @Field(() => Int, {nullable: true})
    RowCount: number;

    @Field(() => Int, {nullable: true})
    TotalRowCount: number;

    @Field(() => Int, {nullable: true})
    ExecutionTime: number;

    @Field({nullable: true})
    ErrorMessage?: string;

    @Field(() => Boolean, {nullable: false})
    Success: boolean;
}

@Resolver(mjBizAppsTasksGitHubGitHubPullRequestTask_)
export class mjBizAppsTasksGitHubGitHubPullRequestTaskResolver extends ResolverBase {
    @Query(() => RunmjBizAppsTasksGitHubGitHubPullRequestTaskViewResult)
    async RunmjBizAppsTasksGitHubGitHubPullRequestTaskViewByID(@Arg('input', () => RunViewByIDInput) input: RunViewByIDInput, @Ctx() { providers, userPayload }: AppContext, @PubSub() pubSub: PubSubEngine) {
        const provider = GetReadOnlyProvider(providers, { allowFallbackToReadWrite: true });
        return super.RunViewByIDGeneric(input, provider, userPayload, pubSub);
    }

    @Query(() => RunmjBizAppsTasksGitHubGitHubPullRequestTaskViewResult)
    async RunmjBizAppsTasksGitHubGitHubPullRequestTaskViewByName(@Arg('input', () => RunViewByNameInput) input: RunViewByNameInput, @Ctx() { providers, userPayload }: AppContext, @PubSub() pubSub: PubSubEngine) {
        const provider = GetReadOnlyProvider(providers, { allowFallbackToReadWrite: true });
        return super.RunViewByNameGeneric(input, provider, userPayload, pubSub);
    }

    @Query(() => RunmjBizAppsTasksGitHubGitHubPullRequestTaskViewResult)
    async RunmjBizAppsTasksGitHubGitHubPullRequestTaskDynamicView(@Arg('input', () => RunDynamicViewInput) input: RunDynamicViewInput, @Ctx() { providers, userPayload }: AppContext, @PubSub() pubSub: PubSubEngine) {
        const provider = GetReadOnlyProvider(providers, { allowFallbackToReadWrite: true });
        input.EntityName = 'MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks';
        return super.RunDynamicViewGeneric(input, provider, userPayload, pubSub);
    }
    @Query(() => mjBizAppsTasksGitHubGitHubPullRequestTask_, { nullable: true })
    async mjBizAppsTasksGitHubGitHubPullRequestTask(@Arg('ID', () => String) ID: string, @Ctx() { userPayload, providers }: AppContext, @PubSub() pubSub: PubSubEngine): Promise<mjBizAppsTasksGitHubGitHubPullRequestTask_ | null> {
        this.CheckUserReadPermissions('MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks', userPayload);
        const provider = GetReadOnlyProvider(providers, { allowFallbackToReadWrite: true });
        const sSQL = `SELECT * FROM ${provider.QuoteSchemaAndView('__mj_BizAppsTasksGitHub', 'vwGitHubPullRequestTasks')} WHERE ${provider.QuoteIdentifier('ID')}=${provider.BuildParameterPlaceholder(0)} ` + this.getRowLevelSecurityWhereClause(provider, 'MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks', userPayload, EntityPermissionType.Read, 'AND');
        const rows = await provider.ExecuteSQL(sSQL, [ID], undefined, this.GetUserFromPayload(userPayload));
        const result = await this.MapFieldNamesToCodeNames('MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks', rows && rows.length > 0 ? rows[0] : null, this.GetUserFromPayload(userPayload));
        return result;
    }
    
    @Mutation(() => mjBizAppsTasksGitHubGitHubPullRequestTask_)
    async CreatemjBizAppsTasksGitHubGitHubPullRequestTask(
        @Arg('input', () => CreatemjBizAppsTasksGitHubGitHubPullRequestTaskInput) input: CreatemjBizAppsTasksGitHubGitHubPullRequestTaskInput,
        @Ctx() { providers, userPayload }: AppContext,
        @PubSub() pubSub: PubSubEngine
    ) {
        const provider = GetReadWriteProvider(providers);
        return this.CreateRecord('MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks', input, provider, userPayload, pubSub)
    }
        
    @Mutation(() => mjBizAppsTasksGitHubGitHubPullRequestTask_)
    async UpdatemjBizAppsTasksGitHubGitHubPullRequestTask(
        @Arg('input', () => UpdatemjBizAppsTasksGitHubGitHubPullRequestTaskInput) input: UpdatemjBizAppsTasksGitHubGitHubPullRequestTaskInput,
        @Ctx() { providers, userPayload }: AppContext,
        @PubSub() pubSub: PubSubEngine
    ) {
        const provider = GetReadWriteProvider(providers);
        return this.UpdateRecord('MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks', input, provider, userPayload, pubSub);
    }
    
    @Mutation(() => mjBizAppsTasksGitHubGitHubPullRequestTask_)
    async DeletemjBizAppsTasksGitHubGitHubPullRequestTask(@Arg('ID', () => String) ID: string, @Arg('options___', () => DeleteOptionsInput) options: DeleteOptionsInput, @Ctx() { providers, userPayload }: AppContext, @PubSub() pubSub: PubSubEngine) {
        const provider = GetReadWriteProvider(providers);
        const key = new CompositeKey([{FieldName: 'ID', Value: ID}]);
        return this.DeleteRecord('MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks', key, options, provider, userPayload, pubSub);
    }
    
}

//****************************************************************************
// ENTITY CLASS for MJ_BizApps_Tasks_GitHub: Git Hub Repositories
//****************************************************************************
@ObjectType({ description: "GitHub repositories connected to BizApps Tasks, storing tracking controls, import filtering rules (AssignedOnly vs All), GitHub App installation IDs, client organization link, and optional Software Factory delivery policy reference." })
export class mjBizAppsTasksGitHubGitHubRepository_ {
    @Field() 
    @MaxLength(36)
    ID: string;
        
    @Field({nullable: true, description: "GitHub organization or user login that owns the repository (e.g. MemberJunction)."}) 
    @MaxLength(150)
    Owner?: string;
        
    @Field({nullable: true, description: "Repository slug within the owner namespace (e.g. MJ, bizapps-tasks)."}) 
    @MaxLength(200)
    Name?: string;
        
    @Field({nullable: true, description: "Default target branch name on GitHub (typically main or next)."}) 
    @MaxLength(120)
    DefaultBranch?: string;
        
    @Field(() => Boolean, {nullable: true, description: "When 1, periodic sync and incoming webhooks import eligible issues and pull requests into BizApps Tasks."}) 
    IsTracked?: boolean;
        
    @Field({nullable: true, description: "Controls which issues and PRs become Tasks: AssignedOnly imports items assigned to or requesting review from a mapped GitHubIdentity; All imports every issue and PR in the repository."}) 
    @MaxLength(20)
    ImportRule?: string;
        
    @Field({nullable: true, description: "GitHub App installation identifier scoped to this repository or organization."}) 
    @MaxLength(100)
    InstallationID?: string;
        
    @Field({nullable: true, description: "Optional client Organization in BizApps Common. Null denotes an internal repository; non-null enables Client-layer DeliveryPolicy inheritance."}) 
    @MaxLength(36)
    OrganizationID?: string;
        
    @Field({nullable: true, description: "Optional UUID of the repository-level DeliveryPolicy in bizapps-software-factory when installed."}) 
    @MaxLength(36)
    DeliveryPolicyID?: string;
        
    @Field() 
    _mj__CreatedAt: Date;
        
    @Field() 
    _mj__UpdatedAt: Date;
        
    @Field({nullable: true}) 
    @MaxLength(255)
    Organization?: string;
        
    @Field(() => [String], { nullable: true, description: `Field-level security: when non-null, the fields on this entity the calling user may read. Any other field arriving as null was withheld by the server rather than genuinely empty. Null for callers with no field restrictions.` })
    ReadableFields___?: string[];
        
}

//****************************************************************************
// INPUT TYPE for MJ_BizApps_Tasks_GitHub: Git Hub Repositories
//****************************************************************************
@InputType()
export class CreatemjBizAppsTasksGitHubGitHubRepositoryInput {
    @Field({ nullable: true })
    ID?: string;

    @Field({ nullable: true })
    Owner?: string;

    @Field({ nullable: true })
    Name?: string;

    @Field({ nullable: true })
    DefaultBranch?: string;

    @Field(() => Boolean, { nullable: true })
    IsTracked?: boolean;

    @Field({ nullable: true })
    ImportRule?: string;

    @Field({ nullable: true })
    InstallationID: string | null;

    @Field({ nullable: true })
    OrganizationID: string | null;

    @Field({ nullable: true })
    DeliveryPolicyID: string | null;

    @Field(() => RestoreContextInput, { nullable: true })
    RestoreContext___?: RestoreContextInput;
}
    

//****************************************************************************
// INPUT TYPE for MJ_BizApps_Tasks_GitHub: Git Hub Repositories
//****************************************************************************
@InputType()
export class UpdatemjBizAppsTasksGitHubGitHubRepositoryInput {
    @Field()
    ID: string;

    @Field({ nullable: true })
    Owner?: string;

    @Field({ nullable: true })
    Name?: string;

    @Field({ nullable: true })
    DefaultBranch?: string;

    @Field(() => Boolean, { nullable: true })
    IsTracked?: boolean;

    @Field({ nullable: true })
    ImportRule?: string;

    @Field({ nullable: true })
    InstallationID?: string | null;

    @Field({ nullable: true })
    OrganizationID?: string | null;

    @Field({ nullable: true })
    DeliveryPolicyID?: string | null;

    @Field(() => [KeyValuePairInput], { nullable: true })
    OldValues___?: KeyValuePairInput[];

    @Field(() => RestoreContextInput, { nullable: true })
    RestoreContext___?: RestoreContextInput;
}
    
//****************************************************************************
// RESOLVER for MJ_BizApps_Tasks_GitHub: Git Hub Repositories
//****************************************************************************
@ObjectType()
export class RunmjBizAppsTasksGitHubGitHubRepositoryViewResult {
    @Field(() => [mjBizAppsTasksGitHubGitHubRepository_])
    Results: mjBizAppsTasksGitHubGitHubRepository_[];

    @Field(() => String, {nullable: true})
    UserViewRunID?: string;

    @Field(() => Int, {nullable: true})
    RowCount: number;

    @Field(() => Int, {nullable: true})
    TotalRowCount: number;

    @Field(() => Int, {nullable: true})
    ExecutionTime: number;

    @Field({nullable: true})
    ErrorMessage?: string;

    @Field(() => Boolean, {nullable: false})
    Success: boolean;
}

@Resolver(mjBizAppsTasksGitHubGitHubRepository_)
export class mjBizAppsTasksGitHubGitHubRepositoryResolver extends ResolverBase {
    @Query(() => RunmjBizAppsTasksGitHubGitHubRepositoryViewResult)
    async RunmjBizAppsTasksGitHubGitHubRepositoryViewByID(@Arg('input', () => RunViewByIDInput) input: RunViewByIDInput, @Ctx() { providers, userPayload }: AppContext, @PubSub() pubSub: PubSubEngine) {
        const provider = GetReadOnlyProvider(providers, { allowFallbackToReadWrite: true });
        return super.RunViewByIDGeneric(input, provider, userPayload, pubSub);
    }

    @Query(() => RunmjBizAppsTasksGitHubGitHubRepositoryViewResult)
    async RunmjBizAppsTasksGitHubGitHubRepositoryViewByName(@Arg('input', () => RunViewByNameInput) input: RunViewByNameInput, @Ctx() { providers, userPayload }: AppContext, @PubSub() pubSub: PubSubEngine) {
        const provider = GetReadOnlyProvider(providers, { allowFallbackToReadWrite: true });
        return super.RunViewByNameGeneric(input, provider, userPayload, pubSub);
    }

    @Query(() => RunmjBizAppsTasksGitHubGitHubRepositoryViewResult)
    async RunmjBizAppsTasksGitHubGitHubRepositoryDynamicView(@Arg('input', () => RunDynamicViewInput) input: RunDynamicViewInput, @Ctx() { providers, userPayload }: AppContext, @PubSub() pubSub: PubSubEngine) {
        const provider = GetReadOnlyProvider(providers, { allowFallbackToReadWrite: true });
        input.EntityName = 'MJ_BizApps_Tasks_GitHub: Git Hub Repositories';
        return super.RunDynamicViewGeneric(input, provider, userPayload, pubSub);
    }
    @Query(() => mjBizAppsTasksGitHubGitHubRepository_, { nullable: true })
    async mjBizAppsTasksGitHubGitHubRepository(@Arg('ID', () => String) ID: string, @Ctx() { userPayload, providers }: AppContext, @PubSub() pubSub: PubSubEngine): Promise<mjBizAppsTasksGitHubGitHubRepository_ | null> {
        this.CheckUserReadPermissions('MJ_BizApps_Tasks_GitHub: Git Hub Repositories', userPayload);
        const provider = GetReadOnlyProvider(providers, { allowFallbackToReadWrite: true });
        const sSQL = `SELECT * FROM ${provider.QuoteSchemaAndView('__mj_BizAppsTasksGitHub', 'vwGitHubRepositories')} WHERE ${provider.QuoteIdentifier('ID')}=${provider.BuildParameterPlaceholder(0)} ` + this.getRowLevelSecurityWhereClause(provider, 'MJ_BizApps_Tasks_GitHub: Git Hub Repositories', userPayload, EntityPermissionType.Read, 'AND');
        const rows = await provider.ExecuteSQL(sSQL, [ID], undefined, this.GetUserFromPayload(userPayload));
        const result = await this.MapFieldNamesToCodeNames('MJ_BizApps_Tasks_GitHub: Git Hub Repositories', rows && rows.length > 0 ? rows[0] : null, this.GetUserFromPayload(userPayload));
        return result;
    }
    
    @Mutation(() => mjBizAppsTasksGitHubGitHubRepository_)
    async CreatemjBizAppsTasksGitHubGitHubRepository(
        @Arg('input', () => CreatemjBizAppsTasksGitHubGitHubRepositoryInput) input: CreatemjBizAppsTasksGitHubGitHubRepositoryInput,
        @Ctx() { providers, userPayload }: AppContext,
        @PubSub() pubSub: PubSubEngine
    ) {
        const provider = GetReadWriteProvider(providers);
        return this.CreateRecord('MJ_BizApps_Tasks_GitHub: Git Hub Repositories', input, provider, userPayload, pubSub)
    }
        
    @Mutation(() => mjBizAppsTasksGitHubGitHubRepository_)
    async UpdatemjBizAppsTasksGitHubGitHubRepository(
        @Arg('input', () => UpdatemjBizAppsTasksGitHubGitHubRepositoryInput) input: UpdatemjBizAppsTasksGitHubGitHubRepositoryInput,
        @Ctx() { providers, userPayload }: AppContext,
        @PubSub() pubSub: PubSubEngine
    ) {
        const provider = GetReadWriteProvider(providers);
        return this.UpdateRecord('MJ_BizApps_Tasks_GitHub: Git Hub Repositories', input, provider, userPayload, pubSub);
    }
    
    @Mutation(() => mjBizAppsTasksGitHubGitHubRepository_)
    async DeletemjBizAppsTasksGitHubGitHubRepository(@Arg('ID', () => String) ID: string, @Arg('options___', () => DeleteOptionsInput) options: DeleteOptionsInput, @Ctx() { providers, userPayload }: AppContext, @PubSub() pubSub: PubSubEngine) {
        const provider = GetReadWriteProvider(providers);
        const key = new CompositeKey([{FieldName: 'ID', Value: ID}]);
        return this.DeleteRecord('MJ_BizApps_Tasks_GitHub: Git Hub Repositories', key, options, provider, userPayload, pubSub);
    }
    
}