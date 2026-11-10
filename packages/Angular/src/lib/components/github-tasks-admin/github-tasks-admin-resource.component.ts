import {
    ChangeDetectionStrategy,
    ChangeDetectorRef,
    Component,
    OnDestroy,
    OnInit,
    inject,
} from '@angular/core';
import { FormsModule } from '@angular/forms';
import { Subject } from 'rxjs';
import { debounceTime, filter, takeUntil } from 'rxjs/operators';
import { BaseEntity, LogError, RunView, type BaseEntityEvent, type RunViewParams } from '@memberjunction/core';
import { UserInfoEngine, type ResourceData } from '@memberjunction/core-entities';
import { IsValidUUID, MJEventType, MJGlobal, RegisterClass, UUIDsEqual, type MJEvent } from '@memberjunction/global';
import { GraphQLActionClient, GraphQLDataProvider } from '@memberjunction/graphql-dataprovider';
import { BaseResourceComponent } from '@memberjunction/ng-shared';
import { SharedGenericModule } from '@memberjunction/ng-shared-generic';
import {
    MJButtonDirective,
    MJEmptyStateComponent,
    MJFilterChipComponent,
    MJPageBodyComponent,
    MJPageHeaderComponent,
    MJPageLayoutComponent,
    MJPageSearchComponent,
    MJRefreshButtonComponent,
    MJStatBadgeComponent,
} from '@memberjunction/ng-ui-components';
import { ResolvePersonIDForUser } from '@mj-biz-apps/common-entities';
import type {
    mjBizAppsTasksGitHubGitHubIdentityEntity,
    mjBizAppsTasksGitHubGitHubRepositoryEntity,
} from '@mj-biz-apps/tasks-github-entities';
import {
    BuildGitHubTasksAdminAgentContext,
    BuildIdentityMappingViewModel,
    BuildTrackedRepositoryCards,
    BuildWebhookDeliveryRows,
    FilterTrackedRepositoryCards,
    ParseGitHubTasksAdminTab,
    ValidateGitHubUsername,
} from '../../tasks-github-ui.helpers.js';
import {
    ACTION_EXECUTION_LOGS_ENTITY_NAME,
    COMPANY_INTEGRATION_ENTITY_MAPS_ENTITY_NAME,
    COMPANY_INTEGRATIONS_ENTITY_NAME,
    GITHUB_IDENTITIES_ENTITY_NAME,
    GITHUB_ISSUE_TASKS_ENTITY_NAME,
    GITHUB_PR_TASKS_ENTITY_NAME,
    GITHUB_REPOSITORIES_ENTITY_NAME,
    GITHUB_WEBHOOK_DELIVERIES_ENTITY_CANDIDATES,
    HANDLE_GITHUB_TASKS_WEBHOOK_ACTION_ID,
    PEOPLE_ENTITY_NAME,
    SYNC_GITHUB_REPOSITORY_TASKS_ACTION_ID,
    TASKS_GITHUB_ADMIN_ACTIVE_TAB_SETTING_KEY,
    type CompanyIntegrationEntityMapSummaryInput,
    type CompanyIntegrationSummaryInput,
    type GitHubIdentityRecordInput,
    type GitHubRepositoryCardInput,
    type GitHubRepositoryImportRule,
    type GitHubTasksAdminTab,
    type IdentityMappingViewModel,
    type PersonIdentityRecordInput,
    type RawWebhookDeliveryRecordInput,
    type RepositoryTrackingFilter,
    type TrackedRepositoryCardViewModel,
    type WebhookDeliveryRowViewModel,
} from '../../tasks-github-ui.models.js';

type AdminPageClientTool = Parameters<
    NonNullable<GitHubTasksAdminResource['navigationService']>['SetAgentClientTools']
>[1][number];

interface RepositorySyncTimestampRow {
    RepositoryID?: string | null;
    LastSyncedAt?: Date | string | null;
}

interface DelegatedCredentialRow {
    ID: string;
    Name?: string | null;
    IsActive?: boolean | null;
}

interface ParsedSyncSummaryJson {
    repositoriesSynced?: number;
    created?: number;
    updated?: number;
    skipped?: number;
}

const LIVE_ENTITIES: readonly string[] = [
    GITHUB_REPOSITORIES_ENTITY_NAME,
    GITHUB_IDENTITIES_ENTITY_NAME,
    GITHUB_ISSUE_TASKS_ENTITY_NAME,
    GITHUB_PR_TASKS_ENTITY_NAME,
];

const TRACKING_FILTER_OPTIONS: readonly { Value: RepositoryTrackingFilter; Label: string }[] = [
    { Value: 'all', Label: 'All' },
    { Value: 'tracked', Label: 'Tracked' },
    { Value: 'untracked', Label: 'Untracked' },
];

const IMPORT_RULE_OPTIONS: readonly { Value: GitHubRepositoryImportRule; Label: string }[] = [
    { Value: 'AssignedOnly', Label: 'Assigned / Requested Only' },
    { Value: 'All', Label: 'All Issues & PRs' },
];

/**
 * GitHub Sync Administration & Self-Service Identity Console (`GitHubTasksAdminResource`).
 *
 * Registered under the `Tasks` application via `NavItem.bizapps-tasks-github.github-sync`.
 * Provides three tabs persisted per user via `UserInfoEngine.Instance`:
 * 1. **Repositories**: toggle `IsTracked` and `ImportRule` (`AssignedOnly` vs `All`), inspect
 *    `'ConnectorMirror'` (`@memberjunction/connector-github`) vs `'GitHubREST'` sync source badges,
 *    and trigger on-demand `Sync GitHub Repository Tasks`.
 * 2. **My GitHub Identity**: self-service mapping between the signed-in user's `MJ_BizApps_Common: People`
 *    record and `MJ_BizApps_Tasks_GitHub: Git Hub Identities`, plus MJ Vault 3LO OAuth vs App fallback status.
 * 3. **Webhooks**: inspect recent webhook deliveries / execution logs and pilot webhook endpoint health info.
 *
 * SAFETY BOUNDARY: Only read-only navigational, filtering, and refresh client tools are exposed to the co-agent.
 * Changing repository tracking rules, linking GitHub identities, and triggering live GitHub sync runs require
 * explicit user action in the UI.
 */
@Component({
    selector: 'mj-tasks-github-admin-resource',
    standalone: true,
    imports: [
        FormsModule,
        SharedGenericModule,
        MJButtonDirective,
        MJEmptyStateComponent,
        MJFilterChipComponent,
        MJPageBodyComponent,
        MJPageHeaderComponent,
        MJPageLayoutComponent,
        MJPageSearchComponent,
        MJRefreshButtonComponent,
        MJStatBadgeComponent,
    ],
    changeDetection: ChangeDetectionStrategy.OnPush,
    templateUrl: './github-tasks-admin-resource.component.html',
    styleUrls: ['./github-tasks-admin-resource.component.css'],
})
@RegisterClass(BaseResourceComponent, 'GitHubTasksAdminResource')
export class GitHubTasksAdminResource extends BaseResourceComponent implements OnInit, OnDestroy {
    private readonly cdr = inject(ChangeDetectorRef, { optional: true });
    protected override destroy$ = new Subject<void>();

    public IsLoading = true;
    public IsSyncingAll = false;
    public SyncingRepositoryID: string | null = null;
    public SavingRepositoryID: string | null = null;
    public IsSavingIdentity = false;

    public Banner: { Type: 'success' | 'error' | 'info'; Message: string } | null = null;

    public ActiveTab: GitHubTasksAdminTab = 'repositories';
    public TrackingFilter: RepositoryTrackingFilter = 'all';
    public SearchQuery = '';

    public readonly TrackingFilterOptions = TRACKING_FILTER_OPTIONS;
    public readonly ImportRuleOptions = IMPORT_RULE_OPTIONS;

    public RepositoryCards: TrackedRepositoryCardViewModel[] = [];
    public IdentityViewModel: IdentityMappingViewModel = BuildIdentityMappingViewModel({
        currentUser: null,
        people: [],
        identities: [],
    });
    public WebhookDeliveries: WebhookDeliveryRowViewModel[] = [];

    public IdentityLoginDraft = '';
    public IdentityLoginError: string | null = null;

    private initialParamsApplied = false;

    public get FilteredRepositoryCards(): TrackedRepositoryCardViewModel[] {
        return FilterTrackedRepositoryCards(this.RepositoryCards, this.TrackingFilter, this.SearchQuery);
    }

    public get TrackedRepositoryCount(): number {
        return this.RepositoryCards.filter((card) => card.IsTracked).length;
    }

    public get ConnectorMirrorCount(): number {
        return this.RepositoryCards.filter((card) => card.SyncSourceBadge === 'ConnectorMirror').length;
    }

    public override async ngOnInit(): Promise<void> {
        super.ngOnInit();
        this.NotifyLoadStarted();
        try {
            const initialParams = this.GetQueryParams();
            this.applyInitialState(initialParams);
            this.initialParamsApplied = true;
            await this.LoadData();
            this.navigationService?.SetAgentClientTools(this, this.buildAgentTools());
            this.subscribeToLiveChanges();
        } finally {
            this.NotifyLoadComplete();
        }
    }

    public override ngOnDestroy(): void {
        super.ngOnDestroy();
        this.destroy$.next();
        this.destroy$.complete();
    }

    public async GetResourceDisplayName(_data: ResourceData): Promise<string> {
        return 'GitHub Sync';
    }

    public async GetResourceIconClass(_data: ResourceData): Promise<string> {
        return 'fa-brands fa-github';
    }

    protected override OnQueryParamsChanged(params: Record<string, string>, _source: 'popstate' | 'deeplink'): void {
        const paramTab = ParseGitHubTasksAdminTab(params['tab']);
        if (paramTab) {
            this.ActiveTab = paramTab;
        }
        const filterParam = params['filter'];
        this.TrackingFilter =
            filterParam === 'tracked' || filterParam === 'untracked' ? filterParam : 'all';
        this.SearchQuery = params['q'] ?? '';
        this.publishAgentContext();
        this.RefreshView();
        this.cdr?.markForCheck();
    }

    public async LoadData(): Promise<void> {
        this.IsLoading = true;
        this.cdr?.markForCheck();

        try {
            const provider = this.ProviderToUse;
            const currentUser = provider?.CurrentUser;
            const rv = new RunView(this.RunViewToUse);

            const hasEntity = (entityName: string): boolean => {
                const entities = Array.isArray(provider?.Entities) ? provider.Entities : [];
                return entities.length === 0 || entities.some((e) => e.Name === entityName);
            };

            const webhookEntityName = this.resolveWebhookDeliveryEntityName();

            const batchQueries: RunViewParams[] = [
                {
                    EntityName: PEOPLE_ENTITY_NAME,
                    Fields: ['ID', 'FirstName', 'LastName', 'Email', 'LinkedUserID', 'Status'],
                    ResultType: 'simple',
                },
                {
                    EntityName: GITHUB_IDENTITIES_ENTITY_NAME,
                    OrderBy: '__mj_UpdatedAt DESC',
                    ResultType: 'simple',
                },
                {
                    EntityName: GITHUB_REPOSITORIES_ENTITY_NAME,
                    OrderBy: 'Owner ASC, Name ASC',
                    ResultType: 'simple',
                },
                {
                    EntityName: COMPANY_INTEGRATION_ENTITY_MAPS_ENTITY_NAME,
                    ExtraFilter: "ExternalObjectName IN ('issues', 'pull_requests', 'repositories', 'commits')",
                    ResultType: 'simple',
                },
            ];

            const optionalIndices: {
                companyIntegrations?: number;
                issueSyncTimestamps?: number;
                prSyncTimestamps?: number;
                webhookDeliveries?: number;
            } = {};

            if (hasEntity(COMPANY_INTEGRATIONS_ENTITY_NAME)) {
                optionalIndices.companyIntegrations = batchQueries.length;
                batchQueries.push({
                    EntityName: COMPANY_INTEGRATIONS_ENTITY_NAME,
                    ExtraFilter: "Integration = 'GitHub'",
                    ResultType: 'simple',
                });
            }

            if (hasEntity(GITHUB_ISSUE_TASKS_ENTITY_NAME)) {
                optionalIndices.issueSyncTimestamps = batchQueries.length;
                batchQueries.push({
                    EntityName: GITHUB_ISSUE_TASKS_ENTITY_NAME,
                    ExtraFilter: 'RepositoryID IS NOT NULL AND LastSyncedAt IS NOT NULL',
                    Fields: ['RepositoryID', 'LastSyncedAt'],
                    OrderBy: 'LastSyncedAt DESC',
                    MaxRows: 250,
                    ResultType: 'simple',
                });
            }

            if (hasEntity(GITHUB_PR_TASKS_ENTITY_NAME)) {
                optionalIndices.prSyncTimestamps = batchQueries.length;
                batchQueries.push({
                    EntityName: GITHUB_PR_TASKS_ENTITY_NAME,
                    ExtraFilter: 'RepositoryID IS NOT NULL AND LastSyncedAt IS NOT NULL',
                    Fields: ['RepositoryID', 'LastSyncedAt'],
                    OrderBy: 'LastSyncedAt DESC',
                    MaxRows: 250,
                    ResultType: 'simple',
                });
            }

            if (webhookEntityName) {
                optionalIndices.webhookDeliveries = batchQueries.length;
                batchQueries.push(
                    webhookEntityName === ACTION_EXECUTION_LOGS_ENTITY_NAME
                        ? {
                              EntityName: ACTION_EXECUTION_LOGS_ENTITY_NAME,
                              ExtraFilter: `ActionID = '${HANDLE_GITHUB_TASKS_WEBHOOK_ACTION_ID}'`,
                              OrderBy: 'StartedAt DESC',
                              MaxRows: 25,
                              ResultType: 'simple',
                          }
                        : {
                              EntityName: webhookEntityName,
                              OrderBy: '__mj_CreatedAt DESC',
                              MaxRows: 25,
                              ResultType: 'simple',
                          },
                );
            }

            const [batchResults, resolvedPersonId, delegatedOAuthCredId] = await Promise.all([
                rv.RunViews(batchQueries, currentUser),
                this.resolveCurrentUserPersonId(),
                this.resolveDelegatedOAuthCredentialId(rv),
            ]);

            const peopleRows = batchResults[0]?.Success
                ? ((batchResults[0].Results as PersonIdentityRecordInput[] | undefined) ?? [])
                : [];
            const identityRows = batchResults[1]?.Success
                ? ((batchResults[1].Results as GitHubIdentityRecordInput[] | undefined) ?? [])
                : [];
            const repoRows = batchResults[2]?.Success
                ? ((batchResults[2].Results as GitHubRepositoryCardInput[] | undefined) ?? [])
                : [];
            const entityMapRows = batchResults[3]?.Success
                ? ((batchResults[3].Results as CompanyIntegrationEntityMapSummaryInput[] | undefined) ?? [])
                : [];

            const companyIntegrationRows =
                optionalIndices.companyIntegrations !== undefined &&
                batchResults[optionalIndices.companyIntegrations]?.Success
                    ? ((batchResults[optionalIndices.companyIntegrations].Results as
                          | CompanyIntegrationSummaryInput[]
                          | undefined) ?? [])
                    : [];

            const issueTsRows =
                optionalIndices.issueSyncTimestamps !== undefined &&
                batchResults[optionalIndices.issueSyncTimestamps]?.Success
                    ? ((batchResults[optionalIndices.issueSyncTimestamps].Results as
                          | RepositorySyncTimestampRow[]
                          | undefined) ?? [])
                    : [];

            const prTsRows =
                optionalIndices.prSyncTimestamps !== undefined &&
                batchResults[optionalIndices.prSyncTimestamps]?.Success
                    ? ((batchResults[optionalIndices.prSyncTimestamps].Results as
                          | RepositorySyncTimestampRow[]
                          | undefined) ?? [])
                    : [];

            const rawDeliveryRows =
                optionalIndices.webhookDeliveries !== undefined &&
                batchResults[optionalIndices.webhookDeliveries]?.Success
                    ? ((batchResults[optionalIndices.webhookDeliveries].Results as
                          | RawWebhookDeliveryRecordInput[]
                          | undefined) ?? [])
                    : [];

            const lastSyncedMap = this.aggregateRepositoryLastSynced([...issueTsRows, ...prTsRows]);

            this.RepositoryCards = BuildTrackedRepositoryCards({
                repositories: repoRows,
                entityMaps: entityMapRows,
                companyIntegrations: companyIntegrationRows,
                lastSyncedByRepositoryID: lastSyncedMap,
            });

            this.IdentityViewModel = BuildIdentityMappingViewModel({
                currentUser: currentUser
                    ? {
                          ID: currentUser.ID,
                          Email: currentUser.Email,
                          Name: currentUser.Name,
                          FirstLast: currentUser.FirstLast,
                          LinkedEntityID: currentUser.LinkedEntityID,
                          LinkedEntityRecordID: currentUser.LinkedEntityRecordID,
                      }
                    : null,
                people: peopleRows,
                identities: identityRows,
                resolvedPersonID: resolvedPersonId,
                delegatedOAuthCredentialID: delegatedOAuthCredId,
            });

            this.IdentityLoginDraft = this.IdentityViewModel.GitHubLogin ?? '';
            this.IdentityLoginError = null;
            this.WebhookDeliveries = BuildWebhookDeliveryRows(rawDeliveryRows);
        } catch (err) {
            const msg = err instanceof Error ? err.message : String(err);
            LogError(`GitHubTasksAdminResource.LoadData failed: ${msg}`);
            this.Banner = {
                Type: 'error',
                Message: `Failed to load GitHub Sync console: ${msg}`,
            };
        } finally {
            this.IsLoading = false;
            this.publishAgentContext();
            this.RefreshView();
            this.cdr?.markForCheck();
        }
    }

    public SwitchTab(tab: GitHubTasksAdminTab): void {
        if (this.ActiveTab === tab) {
            return;
        }
        this.ActiveTab = tab;
        this.persistActiveTabSetting(tab);
        this.syncQueryParams();
        this.publishAgentContext();
        this.RefreshView();
        this.cdr?.markForCheck();
    }

    public OnTabKeydown(event: KeyboardEvent): void {
        if (event.key !== 'ArrowRight' && event.key !== 'ArrowLeft') {
            return;
        }
        event.preventDefault();
        const ordered: readonly GitHubTasksAdminTab[] = ['repositories', 'identity', 'webhooks'];
        const currentIdx = ordered.indexOf(this.ActiveTab);
        const delta = event.key === 'ArrowRight' ? 1 : -1;
        const nextIdx = (currentIdx + delta + ordered.length) % ordered.length;
        const nextTab = ordered[nextIdx] ?? 'repositories';
        this.SwitchTab(nextTab);
        const targetBtnId = `gh-admin-tab-${nextTab}`;
        const el = typeof document !== 'undefined' ? document.getElementById(targetBtnId) : null;
        el?.focus();
    }

    public OnTrackingFilterChange(nextFilter: RepositoryTrackingFilter): void {
        this.TrackingFilter = nextFilter;
        this.syncQueryParams();
        this.publishAgentContext();
        this.RefreshView();
        this.cdr?.markForCheck();
    }

    public OnSearchChange(value: string): void {
        this.SearchQuery = value;
        this.syncQueryParams();
        this.publishAgentContext();
        this.RefreshView();
        this.cdr?.markForCheck();
    }

    public OnIdentityLoginInput(): void {
        if (this.IdentityLoginError) {
            const check = ValidateGitHubUsername(this.IdentityLoginDraft);
            if (check.IsValid) {
                this.IdentityLoginError = null;
            }
        }
    }

    public ResetIdentityDraft(): void {
        this.IdentityLoginDraft = this.IdentityViewModel.GitHubLogin ?? '';
        this.IdentityLoginError = null;
        this.cdr?.markForCheck();
    }

    public async SaveIdentityMapping(event?: Event): Promise<void> {
        event?.preventDefault();
        if (this.IsSavingIdentity) {
            return;
        }

        const personId = this.IdentityViewModel.PersonID;
        if (!personId) {
            this.Banner = {
                Type: 'error',
                Message:
                    'Cannot save GitHub login because your user account is not linked to a BizApps Common Person record.',
            };
            this.cdr?.markForCheck();
            return;
        }

        const validation = ValidateGitHubUsername(this.IdentityLoginDraft);
        if (!validation.IsValid) {
            this.IdentityLoginError = validation.ErrorMessage;
            this.cdr?.markForCheck();
            return;
        }

        this.IsSavingIdentity = true;
        this.IdentityLoginError = null;
        this.Banner = null;
        this.cdr?.markForCheck();

        try {
            const provider = this.ProviderToUse;
            const identityEntity = await provider.GetEntityObject<mjBizAppsTasksGitHubGitHubIdentityEntity>(
                GITHUB_IDENTITIES_ENTITY_NAME,
                provider.CurrentUser,
            );

            const existingId = this.IdentityViewModel.IdentityID;
            if (existingId && IsValidUUID(existingId)) {
                const loaded = await identityEntity.Load(existingId);
                if (!loaded) {
                    identityEntity.NewRecord();
                    identityEntity.PersonID = personId;
                }
            } else {
                identityEntity.NewRecord();
                identityEntity.PersonID = personId;
            }

            identityEntity.GitHubLogin = validation.NormalizedLogin;
            identityEntity.IsActive = true;

            const saved = await identityEntity.Save();
            if (!saved) {
                throw new Error(
                    identityEntity.LatestResult?.CompleteMessage ||
                        `Failed to save GitHub identity '@${validation.NormalizedLogin}'.`,
                );
            }

            await this.LoadData();
            this.Banner = {
                Type: 'success',
                Message: `Linked GitHub handle @${validation.NormalizedLogin} to ${this.IdentityViewModel.PersonDisplayName ?? 'your profile'}.`,
            };
        } catch (err) {
            const msg = err instanceof Error ? err.message : String(err);
            LogError(`SaveIdentityMapping failed: ${msg}`);
            this.Banner = {
                Type: 'error',
                Message: msg,
            };
        } finally {
            this.IsSavingIdentity = false;
            this.RefreshView();
            this.cdr?.markForCheck();
        }
    }

    public async ToggleRepositoryTracking(card: TrackedRepositoryCardViewModel): Promise<void> {
        if (this.SavingRepositoryID) {
            return;
        }
        this.SavingRepositoryID = card.ID;
        this.Banner = null;
        this.cdr?.markForCheck();

        try {
            const provider = this.ProviderToUse;
            const repoEntity = await provider.GetEntityObject<mjBizAppsTasksGitHubGitHubRepositoryEntity>(
                GITHUB_REPOSITORIES_ENTITY_NAME,
                provider.CurrentUser,
            );
            const loaded = await repoEntity.Load(card.ID);
            if (!loaded) {
                throw new Error(`Could not load GitHub Repository '${card.FullName}'.`);
            }

            const nextTracked = !card.IsTracked;
            repoEntity.IsTracked = nextTracked;

            const saved = await repoEntity.Save();
            if (!saved) {
                throw new Error(
                    repoEntity.LatestResult?.CompleteMessage ||
                        `Failed updating IsTracked for '${card.FullName}'.`,
                );
            }

            await this.LoadData();
            this.Banner = {
                Type: 'success',
                Message: nextTracked
                    ? `Enabled task synchronization for ${card.FullName}.`
                    : `Paused task synchronization for ${card.FullName}.`,
            };
        } catch (err) {
            const msg = err instanceof Error ? err.message : String(err);
            LogError(`ToggleRepositoryTracking failed: ${msg}`);
            this.Banner = { Type: 'error', Message: msg };
        } finally {
            this.SavingRepositoryID = null;
            this.RefreshView();
            this.cdr?.markForCheck();
        }
    }

    public async UpdateRepositoryImportRule(
        card: TrackedRepositoryCardViewModel,
        nextRule: GitHubRepositoryImportRule,
    ): Promise<void> {
        if (this.SavingRepositoryID || card.ImportRule === nextRule) {
            return;
        }
        this.SavingRepositoryID = card.ID;
        this.Banner = null;
        this.cdr?.markForCheck();

        try {
            const provider = this.ProviderToUse;
            const repoEntity = await provider.GetEntityObject<mjBizAppsTasksGitHubGitHubRepositoryEntity>(
                GITHUB_REPOSITORIES_ENTITY_NAME,
                provider.CurrentUser,
            );
            const loaded = await repoEntity.Load(card.ID);
            if (!loaded) {
                throw new Error(`Could not load GitHub Repository '${card.FullName}'.`);
            }

            repoEntity.ImportRule = nextRule;
            const saved = await repoEntity.Save();
            if (!saved) {
                throw new Error(
                    repoEntity.LatestResult?.CompleteMessage ||
                        `Failed updating ImportRule for '${card.FullName}'.`,
                );
            }

            await this.LoadData();
            this.Banner = {
                Type: 'success',
                Message: `Updated ${card.FullName} import rule to '${nextRule}'.`,
            };
        } catch (err) {
            const msg = err instanceof Error ? err.message : String(err);
            LogError(`UpdateRepositoryImportRule failed: ${msg}`);
            this.Banner = { Type: 'error', Message: msg };
        } finally {
            this.SavingRepositoryID = null;
            this.RefreshView();
            this.cdr?.markForCheck();
        }
    }

    public async TriggerRepositorySync(card?: TrackedRepositoryCardViewModel): Promise<void> {
        if (this.IsSyncingAll || this.SyncingRepositoryID) {
            return;
        }

        const client = this.actionClient;
        if (!client) {
            this.Banner = {
                Type: 'error',
                Message: 'GraphQLActionClient is unavailable on the active metadata provider.',
            };
            this.cdr?.markForCheck();
            return;
        }

        if (card) {
            this.SyncingRepositoryID = card.ID;
        } else {
            this.IsSyncingAll = true;
        }
        this.Banner = null;
        this.cdr?.markForCheck();

        try {
            const actionParams = [
                ...(card ? [{ Name: 'RepositoryID', Value: card.ID, Type: 'Input' as const }] : []),
                { Name: 'SourceMode', Value: 'Auto', Type: 'Input' as const },
                { Name: 'RunInference', Value: 'false', Type: 'Input' as const },
                { Name: 'SummaryJSON', Value: null, Type: 'Output' as const },
            ];

            const result = await client.RunAction(SYNC_GITHUB_REPOSITORY_TASKS_ACTION_ID, actionParams);
            if (!result.Success) {
                throw new Error(result.Message || 'Sync GitHub Repository Tasks action failed.');
            }

            const summaryParam = result.Params?.find((p) => p.Name.toLowerCase() === 'summaryjson');
            const summaryMessage = this.formatSyncSummaryMessage(
                card ? card.FullName : 'all tracked repositories',
                summaryParam?.Value != null ? String(summaryParam.Value) : null,
            );

            await this.LoadData();
            this.Banner = {
                Type: 'success',
                Message: summaryMessage,
            };
        } catch (err) {
            const msg = err instanceof Error ? err.message : String(err);
            LogError(`TriggerRepositorySync failed: ${msg}`);
            this.Banner = { Type: 'error', Message: msg };
        } finally {
            this.IsSyncingAll = false;
            this.SyncingRepositoryID = null;
            this.RefreshView();
            this.cdr?.markForCheck();
        }
    }

    private get actionClient(): GraphQLActionClient | null {
        const provider = this.ProviderToUse;
        if (provider && ('ExecuteGQL' in provider || provider instanceof GraphQLDataProvider)) {
            return new GraphQLActionClient(provider as GraphQLDataProvider);
        }
        return null;
    }

    private formatSyncSummaryMessage(scopeLabel: string, summaryJson: string | null): string {
        if (!summaryJson || !summaryJson.trim()) {
            return `Synchronized GitHub issues and pull requests for ${scopeLabel}.`;
        }
        try {
            const parsed: ParsedSyncSummaryJson = JSON.parse(summaryJson);
            const created = typeof parsed.created === 'number' ? parsed.created : 0;
            const updated = typeof parsed.updated === 'number' ? parsed.updated : 0;
            const skipped = typeof parsed.skipped === 'number' ? parsed.skipped : 0;
            return `Synchronized ${scopeLabel}: ${created} created, ${updated} updated, ${skipped} skipped.`;
        } catch {
            return `Synchronized GitHub issues and pull requests for ${scopeLabel}.`;
        }
    }

    private resolveWebhookDeliveryEntityName(): string | null {
        const entities = Array.isArray(this.ProviderToUse?.Entities) ? this.ProviderToUse.Entities : [];
        if (entities.length === 0) {
            return null;
        }
        for (const candidate of GITHUB_WEBHOOK_DELIVERIES_ENTITY_CANDIDATES) {
            if (entities.some((e) => e.Name === candidate)) {
                return candidate;
            }
        }
        if (entities.some((e) => e.Name === ACTION_EXECUTION_LOGS_ENTITY_NAME)) {
            return ACTION_EXECUTION_LOGS_ENTITY_NAME;
        }
        return null;
    }

    private async resolveCurrentUserPersonId(): Promise<string | null> {
        const provider = this.ProviderToUse;
        const user = provider?.CurrentUser;
        if (!provider || !user) {
            return null;
        }
        try {
            return await ResolvePersonIDForUser(user, provider, user);
        } catch {
            return null;
        }
    }

    private async resolveDelegatedOAuthCredentialId(rv: RunView): Promise<string | null> {
        const provider = this.ProviderToUse;
        const user = provider?.CurrentUser;
        const entities = Array.isArray(provider?.Entities) ? provider.Entities : [];
        const credEntity = entities.find((e) => e.Name === 'MJ: Credentials');
        if (!credEntity || !user?.ID || !IsValidUUID(user.ID)) {
            return null;
        }
        const hasOwnerUserField = credEntity.Fields.some((f) => f.Name === 'OwnerUserID');
        if (!hasOwnerUserField) {
            return null;
        }
        try {
            const res = await rv.RunView<DelegatedCredentialRow>(
                {
                    EntityName: 'MJ: Credentials',
                    ExtraFilter: `OwnerUserID = '${user.ID}' AND IsActive = 1 AND Name LIKE '%GitHub%'`,
                    Fields: ['ID', 'Name', 'IsActive'],
                    MaxRows: 1,
                    ResultType: 'simple',
                },
                user,
            );
            if (res.Success && res.Results && res.Results.length > 0) {
                return res.Results[0]?.ID ?? null;
            }
        } catch {
            // Optional Vault lookup — fall back cleanly when session cannot read MJ: Credentials
        }
        return null;
    }

    private aggregateRepositoryLastSynced(
        rows: readonly RepositorySyncTimestampRow[],
    ): Map<string, string> {
        const latestByRepo = new Map<string, string>();
        for (const row of rows) {
            const repoId = row.RepositoryID?.trim();
            if (!repoId || row.LastSyncedAt == null) {
                continue;
            }
            const iso =
                row.LastSyncedAt instanceof Date
                    ? row.LastSyncedAt.toISOString()
                    : new Date(row.LastSyncedAt).toISOString();
            if (iso === 'Invalid Date') {
                continue;
            }
            const key = repoId.toLowerCase();
            const existing = latestByRepo.get(key);
            if (!existing || iso > existing) {
                latestByRepo.set(key, iso);
            }
        }
        return latestByRepo;
    }

    private applyInitialState(params: Record<string, string>): void {
        const urlTab = ParseGitHubTasksAdminTab(params['tab']);
        if (urlTab) {
            this.ActiveTab = urlTab;
        } else {
            const savedTab = this.readSavedActiveTabSetting();
            this.ActiveTab = savedTab ?? 'repositories';
        }

        const filterParam = params['filter'];
        this.TrackingFilter =
            filterParam === 'tracked' || filterParam === 'untracked' ? filterParam : 'all';
        this.SearchQuery = params['q'] ?? '';
    }

    private readSavedActiveTabSetting(): GitHubTasksAdminTab | null {
        try {
            const raw = UserInfoEngine.Instance.GetSetting(TASKS_GITHUB_ADMIN_ACTIVE_TAB_SETTING_KEY);
            return ParseGitHubTasksAdminTab(raw);
        } catch {
            return null;
        }
    }

    private persistActiveTabSetting(tab: GitHubTasksAdminTab): void {
        try {
            UserInfoEngine.Instance.SetSettingDebounced(
                TASKS_GITHUB_ADMIN_ACTIVE_TAB_SETTING_KEY,
                tab,
                this.ProviderToUse?.CurrentUser,
            );
        } catch (err) {
            LogError(err);
        }
    }

    private syncQueryParams(): void {
        if (!this.initialParamsApplied) {
            return;
        }
        this.UpdateQueryParams({
            tab: this.ActiveTab === 'repositories' ? null : this.ActiveTab,
            filter: this.TrackingFilter === 'all' ? null : this.TrackingFilter,
            q: this.SearchQuery.trim().length > 0 ? this.SearchQuery.trim() : null,
        });
    }

    private publishAgentContext(): void {
        this.navigationService?.SetAgentContext(
            this,
            BuildGitHubTasksAdminAgentContext({
                activeTab: this.ActiveTab,
                trackingFilter: this.TrackingFilter,
                searchQuery: this.SearchQuery,
                allRepositories: this.RepositoryCards,
                filteredRepositories: this.FilteredRepositoryCards,
                identity: this.IdentityViewModel,
                webhookDeliveries: this.WebhookDeliveries,
            }),
        );
    }

    private buildAgentTools(): AdminPageClientTool[] {
        return [
            {
                Name: 'SwitchGitHubSyncTab',
                Description: 'Switch between the Repositories, Identity, and Webhooks tabs.',
                ParameterSchema: {
                    type: 'object',
                    properties: {
                        tab: { type: 'string', enum: ['repositories', 'identity', 'webhooks'] },
                    },
                    required: ['tab'],
                },
                Handler: async (p) => {
                    const nextTab = ParseGitHubTasksAdminTab(String(p['tab'] ?? '')) ?? 'repositories';
                    this.SwitchTab(nextTab);
                    return { ActiveTab: this.ActiveTab };
                },
            },
            {
                Name: 'FilterGitHubRepositories',
                Description: 'Filter visible GitHub repositories by tracking state and search query.',
                ParameterSchema: {
                    type: 'object',
                    properties: {
                        tracking: { type: 'string', enum: ['all', 'tracked', 'untracked'] },
                        query: { type: 'string' },
                    },
                },
                Handler: async (p) => {
                    const rawTracking = p['tracking'];
                    if (rawTracking === 'all' || rawTracking === 'tracked' || rawTracking === 'untracked') {
                        this.TrackingFilter = rawTracking;
                    }
                    if (typeof p['query'] === 'string') {
                        this.SearchQuery = p['query'];
                    }
                    this.syncQueryParams();
                    this.publishAgentContext();
                    this.RefreshView();
                    this.cdr?.markForCheck();
                    return {
                        TrackingFilter: this.TrackingFilter,
                        SearchQuery: this.SearchQuery,
                        FilteredCount: this.FilteredRepositoryCards.length,
                    };
                },
            },
            {
                Name: 'RefreshGitHubSyncConsole',
                Description: 'Reload tracked repositories, GitHub identity status, and recent webhook deliveries.',
                ParameterSchema: { type: 'object', properties: {} },
                Handler: async () => {
                    await this.LoadData();
                    return {
                        TotalRepositories: this.RepositoryCards.length,
                        TrackedRepositories: this.TrackedRepositoryCount,
                        IdentityLinkStatus: this.IdentityViewModel.LinkStatus,
                    };
                },
            },
        ];
    }

    private subscribeToLiveChanges(): void {
        MJGlobal.Instance.GetEventListener(false)
            .pipe(
                filter(
                    (ev: MJEvent) =>
                        ev.event === MJEventType.ComponentEvent && ev.eventCode === BaseEntity.BaseEventCode,
                ),
                filter((ev: MJEvent) => {
                    const entityEv = ev.args as BaseEntityEvent | undefined;
                    const entityName = entityEv?.baseEntity?.EntityInfo?.Name;
                    return Boolean(entityName && LIVE_ENTITIES.includes(entityName));
                }),
                debounceTime(350),
                takeUntil(this.destroy$),
            )
            .subscribe(() => {
                void this.LoadData();
            });
    }

    public IsSameRepo(idA: string | null, idB: string): boolean {
        return Boolean(idA && UUIDsEqual(idA, idB));
    }
}
