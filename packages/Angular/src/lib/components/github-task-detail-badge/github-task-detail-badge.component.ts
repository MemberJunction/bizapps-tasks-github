import {
    ChangeDetectionStrategy,
    ChangeDetectorRef,
    Component,
    Input,
    OnDestroy,
    inject,
} from '@angular/core';
import { LogError, RunView } from '@memberjunction/core';
import { IsValidUUID } from '@memberjunction/global';
import { BaseAngularComponent } from '@memberjunction/ng-base-types';
import { BuildGitHubTaskDetailBadgeViewModel } from '../../tasks-github-ui.helpers.js';
import {
    GITHUB_ISSUE_TASKS_ENTITY_NAME,
    GITHUB_PR_TASKS_ENTITY_NAME,
    type GitHubIssueTaskBadgeInput,
    type GitHubPullRequestTaskBadgeInput,
    type GitHubTaskDetailBadgeViewModel,
} from '../../tasks-github-ui.models.js';

/**
 * Embeddable badge & metadata strip (`<mj-tasks-github-detail-badge>`) for BizApps Tasks detail panels/forms.
 *
 * Supports two data modes:
 * - **Controlled mode:** Supply `[PullRequest]` and/or `[Issue]` to render pre-loaded subtype rows with
 *   zero `RunView` round-trips.
 * - **Self-fetching mode:** Supply `[taskId]` (or `[TaskID]`) with `[PullRequest]` and `[Issue]` unset (`null`)
 *   to query `MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks` and
 *   `MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks` by shared primary key (`ID = '<taskId>'`)
 *   using `this.ProviderToUse` (`new RunView(this.RunViewToUse)`).
 */
@Component({
    selector: 'mj-tasks-github-detail-badge',
    standalone: true,
    imports: [],
    changeDetection: ChangeDetectionStrategy.OnPush,
    templateUrl: './github-task-detail-badge.component.html',
    styleUrls: ['./github-task-detail-badge.component.css'],
})
export class GitHubTaskDetailBadgeComponent extends BaseAngularComponent implements OnDestroy {
    private readonly cdr = inject(ChangeDetectorRef, { optional: true });
    private _taskId: string | null = null;
    private _showOwnershipNotice = true;
    private _pullRequest: GitHubPullRequestTaskBadgeInput | null = null;
    private _issue: GitHubIssueTaskBadgeInput | null = null;
    private _loadSequence = 0;
    private _refreshQueued = false;
    private _destroyed = false;

    public IsLoading = false;
    public LoadError: string | null = null;
    public BadgeViewModel: GitHubTaskDetailBadgeViewModel | null = null;

    @Input()
    public get taskId(): string | null {
        return this._taskId;
    }

    public set taskId(value: string | null) {
        const normalized = value?.trim() || null;
        if (this._taskId === normalized) {
            return;
        }
        this._taskId = normalized;
        this.scheduleRefresh();
    }

    @Input()
    public get TaskID(): string | null {
        return this._taskId;
    }

    public set TaskID(value: string | null) {
        this.taskId = value;
    }

    @Input()
    public get showOwnershipNotice(): boolean {
        return this._showOwnershipNotice;
    }

    public set showOwnershipNotice(value: boolean) {
        const next = Boolean(value);
        if (this._showOwnershipNotice === next) {
            return;
        }
        this._showOwnershipNotice = next;
        this.cdr?.markForCheck();
    }

    @Input()
    public get ShowOwnershipNotice(): boolean {
        return this._showOwnershipNotice;
    }

    public set ShowOwnershipNotice(value: boolean) {
        this.showOwnershipNotice = value;
    }

    @Input()
    public get PullRequest(): GitHubPullRequestTaskBadgeInput | null {
        return this._pullRequest;
    }

    public set PullRequest(value: GitHubPullRequestTaskBadgeInput | null) {
        const next = value ?? null;
        if (this._pullRequest === next) {
            return;
        }
        this._pullRequest = next;
        this.scheduleRefresh();
    }

    @Input()
    public get Issue(): GitHubIssueTaskBadgeInput | null {
        return this._issue;
    }

    public set Issue(value: GitHubIssueTaskBadgeInput | null) {
        const next = value ?? null;
        if (this._issue === next) {
            return;
        }
        this._issue = next;
        this.scheduleRefresh();
    }

    public get IsControlledMode(): boolean {
        return this._pullRequest !== null || this._issue !== null;
    }

    public ngOnDestroy(): void {
        this._destroyed = true;
    }

    public async Reload(): Promise<void> {
        if (this.IsControlledMode) {
            this.applyControlledInputs();
            return;
        }
        await this.loadForTask(this._taskId);
    }

    private scheduleRefresh(): void {
        if (this.IsControlledMode) {
            this.applyControlledInputs();
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
                this.applyControlledInputs();
                return;
            }
            void this.loadForTask(this._taskId);
        });
    }

    private applyControlledInputs(): void {
        // Invalidate any in-flight self-fetch so stale responses cannot overwrite controlled state
        this._loadSequence++;
        this.IsLoading = false;
        this.LoadError = null;
        const resolvedTaskId =
            this._taskId ??
            this._pullRequest?.ID?.trim() ??
            this._issue?.ID?.trim() ??
            '';
        const vm = BuildGitHubTaskDetailBadgeViewModel({
            taskID: resolvedTaskId,
            issueTask: this._issue,
            pullRequestTask: this._pullRequest,
        });
        this.BadgeViewModel = vm.HasGitHubLink ? vm : null;
        this.cdr?.markForCheck();
    }

    private async loadForTask(targetTaskId: string | null): Promise<void> {
        const currentSeq = ++this._loadSequence;
        this.LoadError = null;

        if (!targetTaskId || !IsValidUUID(targetTaskId)) {
            this.IsLoading = false;
            this.BadgeViewModel = null;
            this.cdr?.markForCheck();
            return;
        }

        this.IsLoading = true;
        this.cdr?.markForCheck();

        try {
            const rv = new RunView(this.RunViewToUse);
            const currentUser = this.ProviderToUse?.CurrentUser;
            const idFilter = `ID = '${targetTaskId}'`;

            const [issueRes, prRes] = await rv.RunViews([
                {
                    EntityName: GITHUB_ISSUE_TASKS_ENTITY_NAME,
                    ExtraFilter: idFilter,
                    MaxRows: 1,
                    ResultType: 'simple',
                },
                {
                    EntityName: GITHUB_PR_TASKS_ENTITY_NAME,
                    ExtraFilter: idFilter,
                    MaxRows: 1,
                    ResultType: 'simple',
                },
            ], currentUser);

            if (this._destroyed || currentSeq !== this._loadSequence) {
                return;
            }

            const issueRow = issueRes?.Success
                ? ((issueRes.Results as GitHubIssueTaskBadgeInput[] | undefined)?.[0] ?? null)
                : null;
            const prRow = prRes?.Success
                ? ((prRes.Results as GitHubPullRequestTaskBadgeInput[] | undefined)?.[0] ?? null)
                : null;

            if (!issueRes?.Success && !prRes?.Success) {
                const errText =
                    issueRes?.ErrorMessage ||
                    prRes?.ErrorMessage ||
                    'Unable to query GitHub task subtype metadata.';
                this.LoadError = errText;
                this.BadgeViewModel = null;
                return;
            }

            const vm = BuildGitHubTaskDetailBadgeViewModel({
                taskID: targetTaskId,
                issueTask: issueRow,
                pullRequestTask: prRow,
            });
            this.BadgeViewModel = vm.HasGitHubLink ? vm : null;
        } catch (err) {
            if (this._destroyed || currentSeq !== this._loadSequence) {
                return;
            }
            const msg = err instanceof Error ? err.message : String(err);
            LogError(`GitHubTaskDetailBadgeComponent failed loading task '${targetTaskId}': ${msg}`);
            this.LoadError = msg;
            this.BadgeViewModel = null;
        } finally {
            if (!this._destroyed && currentSeq === this._loadSequence) {
                this.IsLoading = false;
                this.cdr?.markForCheck();
            }
        }
    }
}
