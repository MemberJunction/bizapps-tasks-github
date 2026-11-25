import {
    ChangeDetectionStrategy,
    ChangeDetectorRef,
    Component,
    EventEmitter,
    Input,
    OnDestroy,
    Output,
    inject,
} from '@angular/core';
import { LogError, RunView } from '@memberjunction/core';
import { IsValidUUID } from '@memberjunction/global';
import { BaseAngularComponent } from '@memberjunction/ng-base-types';
import {
    BuildGitHubWorkItemViewModels,
    FilterGitHubWorkItems,
} from '../../tasks-github-ui.helpers.js';
import {
    GITHUB_ISSUE_TASKS_ENTITY_NAME,
    GITHUB_PR_TASKS_ENTITY_NAME,
    PULL_OWNED_FIELD_LOCK_NOTICE,
    type GitHubIssueWorkItemInput,
    type GitHubPullRequestWorkItemInput,
    type GitHubWorkItemViewModel,
    type GitHubWorkPanelFilter,
    type GitHubWorkPanelMode,
} from '../../tasks-github-ui.models.js';

const SELF_FETCH_MAX_ROWS = 200;

/**
 * Reusable standalone GitHub PR & Issue Work Panel / Strip (`<mj-github-work-panel>`).
 *
 * Embeds cleanly into any MJ surface or widget container without Explorer/Router coupling:
 * - **Controlled mode:** Pass `[PullRequests]` and/or `[Issues]` (non-null) to render host-provided data
 *   with zero internal `RunView` round-trips.
 * - **Self-fetching mode:** Leave both `[PullRequests]` and `[Issues]` `null` and pass `[RepositoryID]`
 *   and/or `[TaskIDs]` to load from `MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks` and
 *   `MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks` via `new RunView(this.RunViewToUse)`.
 * - **Two layouts:** `Mode="panel"` (rich filterable card list with `[repo-header-extra]` projection slot)
 *   and `Mode="strip"` (compact horizontal summary strip with clickable pills and `ViewAllClicked`).
 */
@Component({
    selector: 'mj-github-work-panel',
    standalone: true,
    imports: [],
    changeDetection: ChangeDetectionStrategy.OnPush,
    templateUrl: './github-work-panel.component.html',
    styleUrls: ['./github-work-panel.component.css'],
})
export class GitHubWorkPanelComponent extends BaseAngularComponent implements OnDestroy {
    private readonly cdr = inject(ChangeDetectorRef, { optional: true });

    private _mode: GitHubWorkPanelMode = 'panel';
    private _pullRequests: readonly GitHubPullRequestWorkItemInput[] | null = null;
    private _issues: readonly GitHubIssueWorkItemInput[] | null = null;
    private _repositoryFullName: string | null = null;
    private _repositoryID: string | null = null;
    private _taskIDs: readonly string[] | null = null;
    private _title = 'Linked GitHub PRs & Issues';
    private _maxStripItems = 4;
    private _showFilterTabs = true;
    private _showDiffStats = true;
    private _showOwnershipNotice = false;
    private _emptyMessage = 'No synced GitHub pull requests or issues found.';

    private _fetchedPullRequests: GitHubPullRequestWorkItemInput[] = [];
    private _fetchedIssues: GitHubIssueWorkItemInput[] = [];
    private _allItems: GitHubWorkItemViewModel[] = [];
    private _filteredItems: GitHubWorkItemViewModel[] = [];
    private _stripItems: GitHubWorkItemViewModel[] = [];
    private _pullRequestCount = 0;
    private _issueCount = 0;
    private _effectiveRepositoryFullName: string | null = null;

    private _loadSequence = 0;
    private _refreshQueued = false;
    private _destroyed = false;

    public ActiveFilter: GitHubWorkPanelFilter = 'all';
    public IsLoading = false;
    public LoadError: string | null = null;
    public readonly OwnershipNoticeText = PULL_OWNED_FIELD_LOCK_NOTICE;

    @Output()
    public readonly ItemClicked = new EventEmitter<GitHubWorkItemViewModel>();

    @Output()
    public readonly ViewAllClicked = new EventEmitter<void>();

    @Input()
    public get Mode(): GitHubWorkPanelMode {
        return this._mode;
    }

    public set Mode(value: GitHubWorkPanelMode) {
        const next: GitHubWorkPanelMode = value === 'strip' ? 'strip' : 'panel';
        if (this._mode === next) {
            return;
        }
        this._mode = next;
        this.cdr?.markForCheck();
    }

    @Input()
    public get PullRequests(): readonly GitHubPullRequestWorkItemInput[] | null {
        return this._pullRequests;
    }

    public set PullRequests(value: readonly GitHubPullRequestWorkItemInput[] | null) {
        const next = value ?? null;
        if (this._pullRequests === next) {
            return;
        }
        this._pullRequests = next;
        this.scheduleSync();
    }

    @Input()
    public get Issues(): readonly GitHubIssueWorkItemInput[] | null {
        return this._issues;
    }

    public set Issues(value: readonly GitHubIssueWorkItemInput[] | null) {
        const next = value ?? null;
        if (this._issues === next) {
            return;
        }
        this._issues = next;
        this.scheduleSync();
    }

    @Input()
    public get RepositoryFullName(): string | null {
        return this._repositoryFullName;
    }

    public set RepositoryFullName(value: string | null) {
        const normalized = value?.trim() || null;
        if (this._repositoryFullName === normalized) {
            return;
        }
        this._repositoryFullName = normalized;
        this.rebuildViewModels();
    }

    @Input()
    public get RepositoryID(): string | null {
        return this._repositoryID;
    }

    public set RepositoryID(value: string | null) {
        const normalized = value?.trim() || null;
        if (this._repositoryID === normalized) {
            return;
        }
        this._repositoryID = normalized;
        this.scheduleSync();
    }

    @Input()
    public get TaskIDs(): readonly string[] | null {
        return this._taskIDs;
    }

    public set TaskIDs(value: readonly string[] | null) {
        const next = value ?? null;
        if (this._taskIDs === next) {
            return;
        }
        this._taskIDs = next;
        this.scheduleSync();
    }

    @Input()
    public get Title(): string {
        return this._title;
    }

    public set Title(value: string) {
        const next = (value ?? '').trim() || 'Linked GitHub PRs & Issues';
        if (this._title === next) {
            return;
        }
        this._title = next;
        this.cdr?.markForCheck();
    }

    @Input()
    public get MaxStripItems(): number {
        return this._maxStripItems;
    }

    public set MaxStripItems(value: number) {
        const parsed = typeof value === 'number' && Number.isFinite(value) ? Math.max(0, Math.floor(value)) : 4;
        if (this._maxStripItems === parsed) {
            return;
        }
        this._maxStripItems = parsed;
        this.recomputeDerivedCollections();
        this.cdr?.markForCheck();
    }

    @Input()
    public get ShowFilterTabs(): boolean {
        return this._showFilterTabs;
    }

    public set ShowFilterTabs(value: boolean) {
        const next = Boolean(value);
        if (this._showFilterTabs === next) {
            return;
        }
        this._showFilterTabs = next;
        this.cdr?.markForCheck();
    }

    @Input()
    public get ShowDiffStats(): boolean {
        return this._showDiffStats;
    }

    public set ShowDiffStats(value: boolean) {
        const next = Boolean(value);
        if (this._showDiffStats === next) {
            return;
        }
        this._showDiffStats = next;
        this.cdr?.markForCheck();
    }

    @Input()
    public get ShowOwnershipNotice(): boolean {
        return this._showOwnershipNotice;
    }

    public set ShowOwnershipNotice(value: boolean) {
        const next = Boolean(value);
        if (this._showOwnershipNotice === next) {
            return;
        }
        this._showOwnershipNotice = next;
        this.cdr?.markForCheck();
    }

    @Input()
    public get EmptyMessage(): string {
        return this._emptyMessage;
    }

    public set EmptyMessage(value: string) {
        const next = (value ?? '').trim() || 'No synced GitHub pull requests or issues found.';
        if (this._emptyMessage === next) {
            return;
        }
        this._emptyMessage = next;
        this.cdr?.markForCheck();
    }

    public get IsControlledMode(): boolean {
        return this._pullRequests !== null || this._issues !== null;
    }

    public get AllItems(): readonly GitHubWorkItemViewModel[] {
        return this._allItems;
    }

    public get FilteredItems(): readonly GitHubWorkItemViewModel[] {
        return this._filteredItems;
    }

    public get StripItems(): readonly GitHubWorkItemViewModel[] {
        return this._stripItems;
    }

    public get PullRequestCount(): number {
        return this._pullRequestCount;
    }

    public get IssueCount(): number {
        return this._issueCount;
    }

    public get TotalCount(): number {
        return this._allItems.length;
    }

    public get HiddenStripCount(): number {
        return Math.max(0, this._allItems.length - this._stripItems.length);
    }

    public get EffectiveRepositoryFullName(): string | null {
        return this._effectiveRepositoryFullName;
    }

    public get StripCountSummary(): string {
        const prLabel = `${this._pullRequestCount} ${this._pullRequestCount === 1 ? 'PR' : 'PRs'}`;
        const issueLabel = `${this._issueCount} ${this._issueCount === 1 ? 'Issue' : 'Issues'}`;
        return `${prLabel} · ${issueLabel}`;
    }

    public get ActiveEmptyMessage(): string {
        if (this._allItems.length > 0 && this._filteredItems.length === 0) {
            if (this.ActiveFilter === 'prs') {
                return 'No pull requests in this view.';
            }
            if (this.ActiveFilter === 'issues') {
                return 'No issues in this view.';
            }
        }
        return this._emptyMessage;
    }

    public ngOnDestroy(): void {
        this._destroyed = true;
    }

    public SetFilter(filter: GitHubWorkPanelFilter): void {
        if (this.ActiveFilter === filter) {
            return;
        }
        this.ActiveFilter = filter;
        this.recomputeDerivedCollections();
        this.cdr?.markForCheck();
    }

    public OnItemClick(item: GitHubWorkItemViewModel): void {
        this.ItemClicked.emit(item);
    }

    public OnItemKeydown(event: Pick<KeyboardEvent, 'key' | 'preventDefault'>, item: GitHubWorkItemViewModel): void {
        if (event.key === 'Enter' || event.key === ' ') {
            event.preventDefault();
            this.ItemClicked.emit(item);
        }
    }

    public OnViewAllClick(): void {
        this.ViewAllClicked.emit();
    }

    public TrackItem(item: GitHubWorkItemViewModel): string {
        return `${item.Kind}:${item.TaskID}:${item.Number ?? ''}:${item.Title}`;
    }

    public async Reload(): Promise<void> {
        if (this.IsControlledMode) {
            this.applyControlledState();
            return;
        }
        await this.loadFromProvider();
    }

    private scheduleSync(): void {
        if (this.IsControlledMode) {
            this.applyControlledState();
            return;
        }
        if (this._refreshQueued) {
            return;
        }
        this._refreshQueued = true;
        void Promise.resolve().then(() => {
            this._refreshQueued = false;
            if (this._destroyed) {
                return;
            }
            if (this.IsControlledMode) {
                this.applyControlledState();
                return;
            }
            void this.loadFromProvider();
        });
    }

    private applyControlledState(): void {
        // Cancel any in-flight self-fetch so stale responses cannot overwrite controlled inputs
        this._loadSequence++;
        this.IsLoading = false;
        this.LoadError = null;
        this.rebuildViewModels();
    }

    private buildSelfFetchExtraFilter(): string | null {
        const clauses: string[] = [];

        if (this._repositoryID && IsValidUUID(this._repositoryID)) {
            clauses.push(`RepositoryID = '${this._repositoryID}'`);
        }

        if (this._taskIDs && this._taskIDs.length > 0) {
            const uniqueValidIds: string[] = [];
            const seen = new Set<string>();
            for (const rawId of this._taskIDs) {
                const clean = (rawId ?? '').trim();
                const lower = clean.toLowerCase();
                if (clean.length > 0 && IsValidUUID(clean) && !seen.has(lower)) {
                    seen.add(lower);
                    uniqueValidIds.push(clean);
                }
            }
            if (uniqueValidIds.length > 0) {
                clauses.push(`ID IN (${uniqueValidIds.map((id) => `'${id}'`).join(', ')})`);
            }
        }

        if (clauses.length === 0) {
            return null;
        }

        return clauses.join(' AND ');
    }

    private async loadFromProvider(): Promise<void> {
        const currentSeq = ++this._loadSequence;
        this.LoadError = null;

        const extraFilter = this.buildSelfFetchExtraFilter();
        if (!extraFilter) {
            this._fetchedPullRequests = [];
            this._fetchedIssues = [];
            this.IsLoading = false;
            this.rebuildViewModels();
            return;
        }

        this.IsLoading = true;
        this.cdr?.markForCheck();

        try {
            const rv = new RunView(this.RunViewToUse);
            const currentUser = this.ProviderToUse?.CurrentUser;

            const [prRes, issueRes] = await rv.RunViews(
                [
                    {
                        EntityName: GITHUB_PR_TASKS_ENTITY_NAME,
                        ExtraFilter: extraFilter,
                        MaxRows: SELF_FETCH_MAX_ROWS,
                        ResultType: 'simple',
                    },
                    {
                        EntityName: GITHUB_ISSUE_TASKS_ENTITY_NAME,
                        ExtraFilter: extraFilter,
                        MaxRows: SELF_FETCH_MAX_ROWS,
                        ResultType: 'simple',
                    },
                ],
                currentUser,
            );

            if (this._destroyed || currentSeq !== this._loadSequence || this.IsControlledMode) {
                return;
            }

            if (!prRes?.Success && !issueRes?.Success) {
                this.LoadError =
                    prRes?.ErrorMessage ||
                    issueRes?.ErrorMessage ||
                    'Unable to load synced GitHub pull requests and issues.';
                this._fetchedPullRequests = [];
                this._fetchedIssues = [];
                this.rebuildViewModels();
                return;
            }

            this._fetchedPullRequests =
                prRes?.Success && Array.isArray(prRes.Results)
                    ? (prRes.Results as GitHubPullRequestWorkItemInput[])
                    : [];
            this._fetchedIssues =
                issueRes?.Success && Array.isArray(issueRes.Results)
                    ? (issueRes.Results as GitHubIssueWorkItemInput[])
                    : [];

            this.rebuildViewModels();
        } catch (err) {
            if (this._destroyed || currentSeq !== this._loadSequence || this.IsControlledMode) {
                return;
            }
            const msg = err instanceof Error ? err.message : String(err);
            LogError(`GitHubWorkPanelComponent failed loading synced items: ${msg}`);
            this.LoadError = msg;
            this._fetchedPullRequests = [];
            this._fetchedIssues = [];
            this.rebuildViewModels();
        } finally {
            if (!this._destroyed && currentSeq === this._loadSequence) {
                this.IsLoading = false;
                this.cdr?.markForCheck();
            }
        }
    }

    private rebuildViewModels(): void {
        const pullRequests = this.IsControlledMode ? (this._pullRequests ?? []) : this._fetchedPullRequests;
        const issues = this.IsControlledMode ? (this._issues ?? []) : this._fetchedIssues;

        this._allItems = BuildGitHubWorkItemViewModels({
            pullRequests,
            issues,
            repositoryFullName: this._repositoryFullName,
        });

        this._pullRequestCount = this._allItems.filter((item) => item.Kind === 'PullRequest').length;
        this._issueCount = this._allItems.filter((item) => item.Kind === 'Issue').length;

        this._effectiveRepositoryFullName = this.resolveHeaderRepositoryName();
        this.recomputeDerivedCollections();
        this.cdr?.markForCheck();
    }

    private resolveHeaderRepositoryName(): string | null {
        if (this._repositoryFullName) {
            return this._repositoryFullName;
        }
        const uniqueRepos = new Set<string>();
        for (const item of this._allItems) {
            if (item.RepositoryFullName) {
                uniqueRepos.add(item.RepositoryFullName);
            }
        }
        return uniqueRepos.size === 1 ? Array.from(uniqueRepos)[0] ?? null : null;
    }

    private recomputeDerivedCollections(): void {
        this._filteredItems = FilterGitHubWorkItems(this._allItems, this.ActiveFilter);
        this._stripItems = this._allItems.slice(0, this._maxStripItems);
    }
}
