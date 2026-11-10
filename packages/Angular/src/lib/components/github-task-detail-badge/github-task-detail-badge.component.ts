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
 * Given `@Input() taskId`, queries `MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks` and
 * `MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks` by shared primary key (`ID = '<taskId>'`)
 * and renders PR/Issue status chips, diff stat pills (`+add / -del`), branch comparison, CI check and
 * review decision badges, external GitHub link, and the pull-owned field lock indicator.
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
    private _loadSequence = 0;
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
        void this.loadForTask(normalized);
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

    public ngOnDestroy(): void {
        this._destroyed = true;
    }

    public async Reload(): Promise<void> {
        await this.loadForTask(this._taskId);
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
