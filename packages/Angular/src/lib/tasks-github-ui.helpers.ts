import { UUIDsEqual } from '@memberjunction/global';
import {
    GITHUB_PULL_OWNED_TASK_FIELDS,
    GITHUB_USERNAME_REGEX,
    PULL_OWNED_FIELD_LOCK_NOTICE,
    TASKS_OWNED_PLANNING_FIELDS,
    type BuildGitHubWorkItemViewModelsOptions,
    type BuildIdentityMappingOptions,
    type BuildTrackedRepositoryCardsOptions,
    type CompanyIntegrationEntityMapSummaryInput,
    type CompanyIntegrationSummaryInput,
    type GitHubIdentityRecordInput,
    type GitHubIssueBadgeViewModel,
    type GitHubIssueState,
    type GitHubIssueStateReason,
    type GitHubIssueTaskBadgeInput,
    type GitHubIssueWorkItemInput,
    type GitHubPullRequestBadgeViewModel,
    type GitHubPullRequestChecksStatus,
    type GitHubPullRequestReviewDecision,
    type GitHubPullRequestState,
    type GitHubPullRequestTaskBadgeInput,
    type GitHubPullRequestWorkItemInput,
    type GitHubRepositoryImportRule,
    type GitHubTaskDetailBadgeViewModel,
    type GitHubTasksAdminAgentContext,
    type GitHubTasksAdminTab,
    type GitHubUsernameValidationResult,
    type GitHubWorkItemTone,
    type GitHubWorkItemViewModel,
    type GitHubWorkPanelFilter,
    type IdentityMappingViewModel,
    type IdentityVaultAuthStatus,
    type PersonIdentityRecordInput,
    type RawWebhookDeliveryRecordInput,
    type RepositorySyncSourceBadge,
    type RepositoryTrackingFilter,
    type TrackedRepositoryCardViewModel,
    type WebhookDeliveryRowViewModel,
    type WebhookDeliveryStatusTone,
} from './tasks-github-ui.models.js';

const MAX_AGENT_CONTEXT_REPOSITORIES = 25;

const CONNECTOR_GITHUB_MIRROR_OBJECT_NAMES: ReadonlySet<string> = new Set([
    'issues',
    'pull_requests',
    'repositories',
    'commits',
]);

interface ParsedCompanyIntegrationConfig {
    owner?: string;
    Owner?: string;
    defaultOwner?: string;
    DefaultOwner?: string;
    organization?: string;
    Organization?: string;
    org?: string;
    repo?: string;
    repositories?: string | string[];
    Repositories?: string | string[];
    allowedRepositories?: string | string[];
    AllowedRepositories?: string | string[];
}

interface ParsedLabelEntry {
    name?: string | null;
}

// ============================================================================
// Formatting & Parsing Helpers
// ============================================================================

export function NormalizeIsoTimestamp(value: Date | string | null | undefined): string | null {
    if (value == null) {
        return null;
    }
    if (value instanceof Date) {
        return Number.isNaN(value.getTime()) ? null : value.toISOString();
    }
    const trimmed = value.trim();
    if (!trimmed) {
        return null;
    }
    const parsed = new Date(trimmed);
    return Number.isNaN(parsed.getTime()) ? trimmed : parsed.toISOString();
}

export function FormatDisplayTimestamp(value: Date | string | null | undefined, fallback = 'Never synced'): string {
    const iso = NormalizeIsoTimestamp(value);
    if (!iso) {
        return fallback;
    }
    const parsed = new Date(iso);
    if (Number.isNaN(parsed.getTime())) {
        return iso;
    }
    const year = parsed.getUTCFullYear();
    const month = String(parsed.getUTCMonth() + 1).padStart(2, '0');
    const day = String(parsed.getUTCDate()).padStart(2, '0');
    const hours = String(parsed.getUTCHours()).padStart(2, '0');
    const mins = String(parsed.getUTCMinutes()).padStart(2, '0');
    return `${year}-${month}-${day} ${hours}:${mins} UTC`;
}

export function ParseGitHubLabelsJson(rawLabels: string | null | undefined): string[] {
    if (!rawLabels || !rawLabels.trim()) {
        return [];
    }
    const trimmed = rawLabels.trim();
    try {
        const parsed: Array<string | ParsedLabelEntry> | string = JSON.parse(trimmed);
        if (Array.isArray(parsed)) {
            const out: string[] = [];
            for (const entry of parsed) {
                if (typeof entry === 'string' && entry.trim().length > 0) {
                    out.push(entry.trim());
                } else if (entry && typeof entry === 'object' && typeof entry.name === 'string' && entry.name.trim().length > 0) {
                    out.push(entry.name.trim());
                }
            }
            return out;
        }
        if (typeof parsed === 'string' && parsed.trim().length > 0) {
            return [parsed.trim()];
        }
        return [];
    } catch {
        return trimmed
            .split(',')
            .map((part) => part.trim())
            .filter((part) => part.length > 0);
    }
}

export function ExtractRepoFullNameFromHtmlUrl(htmlUrl: string | null | undefined): string | null {
    if (!htmlUrl || !htmlUrl.trim()) {
        return null;
    }
    const match = /^https?:\/\/[^/]+\/([^/\s]+\/[^/\s#?]+?)(?:\/(?:issues|pull)\/\d+)?(?:[/?#]|$)/i.exec(
        htmlUrl.trim(),
    );
    return match ? match[1] : null;
}

export function ParseGitHubTasksAdminTab(raw: string | null | undefined): GitHubTasksAdminTab | null {
    if (!raw) {
        return null;
    }
    const normalized = raw.trim().toLowerCase();
    if (normalized === 'repositories' || normalized === 'identity' || normalized === 'webhooks') {
        return normalized;
    }
    return null;
}

// ============================================================================
// 1. Self-Service Identity Mapping Helpers
// ============================================================================

/**
 * Validates a GitHub username against `^[a-zA-Z0-9](?:[a-zA-Z0-9]|-(?=[a-zA-Z0-9])){0,38}$`.
 */
export function ValidateGitHubUsername(rawLogin: string | null | undefined): GitHubUsernameValidationResult {
    const trimmed = (rawLogin ?? '').trim();
    if (trimmed.length === 0) {
        return {
            IsValid: false,
            NormalizedLogin: '',
            ErrorMessage: 'Enter a GitHub username (for example, octocat).',
        };
    }
    if (!GITHUB_USERNAME_REGEX.test(trimmed)) {
        return {
            IsValid: false,
            NormalizedLogin: trimmed,
            ErrorMessage:
                'GitHub usernames must be 1–39 alphanumeric characters or single hyphens, and cannot start or end with a hyphen.',
        };
    }
    return {
        IsValid: true,
        NormalizedLogin: trimmed,
        ErrorMessage: null,
    };
}

function buildPersonDisplayName(person: PersonIdentityRecordInput): string {
    if (person.DisplayName && person.DisplayName.trim().length > 0) {
        return person.DisplayName.trim();
    }
    const parts = [person.FirstName?.trim() ?? '', person.LastName?.trim() ?? ''].filter((p) => p.length > 0);
    if (parts.length > 0) {
        return parts.join(' ');
    }
    if (person.Email && person.Email.trim().length > 0) {
        return person.Email.trim();
    }
    return `Person ${person.ID.slice(0, 8)}`;
}

function resolveMatchingPerson(
    options: BuildIdentityMappingOptions,
): PersonIdentityRecordInput | null {
    const { currentUser, people, resolvedPersonID } = options;
    if (resolvedPersonID && resolvedPersonID.trim().length > 0) {
        const byResolved = people.find((p) => UUIDsEqual(p.ID, resolvedPersonID.trim()));
        if (byResolved) {
            return byResolved;
        }
        return {
            ID: resolvedPersonID.trim(),
            Email: currentUser?.Email ?? null,
            DisplayName: currentUser?.FirstLast ?? currentUser?.Name ?? null,
        };
    }

    const cleanEmail = (currentUser?.Email ?? '').trim().toLowerCase();
    if (cleanEmail.length > 0) {
        const byEmail = people.find((p) => (p.Email ?? '').trim().toLowerCase() === cleanEmail);
        if (byEmail) {
            return byEmail;
        }
    }

    const linkedRecordId =
        currentUser?.LinkedEntityRecordID != null ? String(currentUser.LinkedEntityRecordID).trim() : '';
    if (linkedRecordId.length > 0) {
        const byLinkedRecord = people.find((p) => UUIDsEqual(p.ID, linkedRecordId));
        if (byLinkedRecord) {
            return byLinkedRecord;
        }
    }

    const userId = (currentUser?.ID ?? '').trim();
    if (userId.length > 0) {
        const byLinkedUser = people.find((p) => p.LinkedUserID != null && UUIDsEqual(p.LinkedUserID, userId));
        if (byLinkedUser) {
            return byLinkedUser;
        }
    }

    return null;
}

function selectPersonIdentityRecord(
    personID: string,
    identities: readonly GitHubIdentityRecordInput[],
): GitHubIdentityRecordInput | null {
    const matches = identities.filter((row) => UUIDsEqual(row.PersonID, personID));
    if (matches.length === 0) {
        return null;
    }
    const activeMatch = matches.find((row) => row.IsActive && (row.GitHubLogin ?? '').trim().length > 0);
    return activeMatch ?? matches[0] ?? null;
}

/**
 * Builds the Self-Service Identity Mapping View-Model resolving
 * `CurrentUser.Email` -> `MJ_BizApps_Common: People` -> `MJ_BizApps_Tasks_GitHub: Git Hub Identities`,
 * link status (`'Linked' | 'Unlinked' | 'PersonNotFound'`), and MJ Vault 3LO OAuth vs app fallback state.
 */
export function BuildIdentityMappingViewModel(options: BuildIdentityMappingOptions): IdentityMappingViewModel {
    const userEmail = (options.currentUser?.Email ?? '').trim() || null;
    const userDisplayName =
        (options.currentUser?.FirstLast ?? '').trim() ||
        (options.currentUser?.Name ?? '').trim() ||
        userEmail ||
        'Signed-in User';

    const matchedPerson = resolveMatchingPerson(options);
    const matchedIdentity = matchedPerson
        ? selectPersonIdentityRecord(matchedPerson.ID, options.identities)
        : null;

    const oauthCredentialId =
        (matchedIdentity?.OAuthTokenCredentialID ?? options.delegatedOAuthCredentialID ?? '').trim() || null;
    const vaultAuthStatus: IdentityVaultAuthStatus = oauthCredentialId ? 'OAuth3LO' : 'AppFallback';
    const vaultAuthLabel = oauthCredentialId
        ? 'MJ Vault 3LO OAuth Connected'
        : 'GitHub App / Vault Installation Fallback';

    if (!matchedPerson) {
        return {
            UserEmail: userEmail,
            UserDisplayName: userDisplayName,
            PersonID: null,
            PersonDisplayName: null,
            IdentityID: null,
            GitHubLogin: null,
            GitHubUserID: null,
            IsActive: false,
            LinkStatus: 'PersonNotFound',
            OAuthTokenCredentialID: oauthCredentialId,
            VaultAuthStatus: vaultAuthStatus,
            VaultAuthLabel: vaultAuthLabel,
            StatusSummary: userEmail
                ? `No BizApps Common Person record matched '${userEmail}'. Link your user account to a Person record to map a GitHub login.`
                : 'No BizApps Common Person record was found for your user session.',
        };
    }

    const personDisplayName =
        (matchedIdentity?.Person ?? '').trim() || buildPersonDisplayName(matchedPerson);
    const cleanLogin = (matchedIdentity?.GitHubLogin ?? '').trim() || null;
    const isLinked = Boolean(matchedIdentity && matchedIdentity.IsActive && cleanLogin);

    if (isLinked && matchedIdentity && cleanLogin) {
        return {
            UserEmail: userEmail,
            UserDisplayName: userDisplayName,
            PersonID: matchedPerson.ID,
            PersonDisplayName: personDisplayName,
            IdentityID: matchedIdentity.ID ?? null,
            GitHubLogin: cleanLogin,
            GitHubUserID: matchedIdentity.GitHubUserID ?? null,
            IsActive: true,
            LinkStatus: 'Linked',
            OAuthTokenCredentialID: oauthCredentialId,
            VaultAuthStatus: vaultAuthStatus,
            VaultAuthLabel: vaultAuthLabel,
            StatusSummary: `Linked @${cleanLogin} to ${personDisplayName}. Assigned issues and pull request review requests synchronize into your Tasks inbox.`,
        };
    }

    return {
        UserEmail: userEmail,
        UserDisplayName: userDisplayName,
        PersonID: matchedPerson.ID,
        PersonDisplayName: personDisplayName,
        IdentityID: matchedIdentity?.ID ?? null,
        GitHubLogin: cleanLogin,
        GitHubUserID: matchedIdentity?.GitHubUserID ?? null,
        IsActive: false,
        LinkStatus: 'Unlinked',
        OAuthTokenCredentialID: oauthCredentialId,
        VaultAuthStatus: vaultAuthStatus,
        VaultAuthLabel: vaultAuthLabel,
        StatusSummary: `No active GitHub login mapped for ${personDisplayName}. Enter your GitHub username below to sync assigned issues and PR reviews.`,
    };
}

// ============================================================================
// 2. Tracked Repository & Connector Mirror Console Helpers
// ============================================================================

function parseCompanyIntegrationConfig(raw: string | null | undefined): ParsedCompanyIntegrationConfig {
    if (!raw || !raw.trim()) {
        return {};
    }
    try {
        const parsed: ParsedCompanyIntegrationConfig | null = JSON.parse(raw);
        return parsed && typeof parsed === 'object' && !Array.isArray(parsed) ? parsed : {};
    } catch {
        return {};
    }
}

function parseRepoPatterns(raw: string | readonly string[] | undefined): string[] {
    if (!raw) {
        return [];
    }
    if (Array.isArray(raw)) {
        return raw
            .filter((entry): entry is string => typeof entry === 'string')
            .map((entry) => entry.trim().toLowerCase())
            .filter((entry) => entry.length > 0);
    }
    if (typeof raw === 'string') {
        return raw
            .split(/[,\n]+/)
            .map((entry) => entry.trim().toLowerCase())
            .filter((entry) => entry.length > 0);
    }
    return [];
}

function repoMatchesPatterns(ownerLower: string, nameLower: string, patterns: readonly string[]): boolean {
    const fullLower = `${ownerLower}/${nameLower}`;
    for (const pattern of patterns) {
        if (pattern === '*' || pattern === '*/*') {
            return true;
        }
        if (pattern.endsWith('/*')) {
            if (pattern.slice(0, -2) === ownerLower) {
                return true;
            }
            continue;
        }
        if (!pattern.includes('/')) {
            if (pattern === nameLower) {
                return true;
            }
            continue;
        }
        if (pattern === fullLower) {
            return true;
        }
    }
    return false;
}

function resolveMatchingCompanyIntegrationID(
    owner: string,
    name: string,
    explicitCompanyIntegrationID: string | null | undefined,
    companyIntegrations: readonly CompanyIntegrationSummaryInput[],
): string | null {
    const cleanExplicit = (explicitCompanyIntegrationID ?? '').trim();
    if (cleanExplicit.length > 0) {
        return cleanExplicit;
    }

    const ownerLower = owner.trim().toLowerCase();
    const nameLower = name.trim().toLowerCase();
    let wildcardMatchId: string | null = null;

    for (const ci of companyIntegrations) {
        const ciId = (ci.ID ?? '').trim();
        if (!ciId || ci.IsActive === false) {
            continue;
        }
        const integrationName = (ci.Integration ?? '').trim().toLowerCase();
        if (integrationName.length > 0 && !integrationName.includes('github')) {
            continue;
        }
        const cfg = parseCompanyIntegrationConfig(ci.Configuration);
        const patterns = parseRepoPatterns(
            cfg.allowedRepositories ??
                cfg.AllowedRepositories ??
                cfg.repositories ??
                cfg.Repositories ??
                (cfg.repo ? [cfg.repo] : undefined),
        );
        if (patterns.length > 0) {
            if (repoMatchesPatterns(ownerLower, nameLower, patterns)) {
                return ciId;
            }
            continue;
        }

        const cfgOwner = (
            cfg.owner ??
            cfg.Owner ??
            cfg.defaultOwner ??
            cfg.DefaultOwner ??
            cfg.organization ??
            cfg.Organization ??
            cfg.org ??
            ci.ExternalSystemID ??
            ''
        )
            .trim()
            .toLowerCase();

        if (cfgOwner.length > 0) {
            if (cfgOwner === ownerLower) {
                return ciId;
            }
            continue;
        }

        if (!wildcardMatchId) {
            wildcardMatchId = ciId;
        }
    }

    return wildcardMatchId;
}

function hasActiveConnectorMirrorEntityMap(
    companyIntegrationID: string | null,
    entityMaps: readonly CompanyIntegrationEntityMapSummaryInput[],
    companyIntegrations: readonly CompanyIntegrationSummaryInput[],
): boolean {
    if (!companyIntegrationID) {
        return false;
    }

    const ciRecord = companyIntegrations.find((ci) => UUIDsEqual(ci.ID, companyIntegrationID));
    if (ciRecord) {
        if (ciRecord.IsActive === false) {
            return false;
        }
        const ciIntegration = (ciRecord.Integration ?? '').trim().toLowerCase();
        if (ciIntegration.length > 0 && !ciIntegration.includes('github')) {
            return false;
        }
    }

    return entityMaps.some((map) => {
        if (!UUIDsEqual(map.CompanyIntegrationID, companyIntegrationID)) {
            return false;
        }
        if (map.SyncEnabled === false) {
            return false;
        }
        if (map.Status != null && map.Status !== 'Active') {
            return false;
        }
        const mapIntegration = (map.Integration ?? '').trim().toLowerCase();
        if (mapIntegration.length > 0 && !mapIntegration.includes('github')) {
            return false;
        }
        const extObj = (map.ExternalObjectName ?? '').trim().toLowerCase();
        if (extObj.length > 0 && !CONNECTOR_GITHUB_MIRROR_OBJECT_NAMES.has(extObj)) {
            return false;
        }
        return true;
    });
}

function lookupRepositoryLastSynced(
    repositoryID: string,
    explicitValue: Date | string | null | undefined,
    lookup: ReadonlyMap<string, Date | string | null> | Record<string, Date | string | null> | undefined,
): Date | string | null {
    if (explicitValue != null) {
        return explicitValue;
    }
    if (!lookup) {
        return null;
    }
    if (lookup instanceof Map) {
        const direct = lookup.get(repositoryID) ?? lookup.get(repositoryID.toLowerCase());
        if (direct !== undefined) {
            return direct;
        }
        for (const [k, val] of lookup.entries()) {
            if (UUIDsEqual(k, repositoryID)) {
                return val;
            }
        }
        return null;
    }
    const recordLookup = lookup as Record<string, Date | string | null>;
    for (const [k, val] of Object.entries(recordLookup)) {
        if (UUIDsEqual(k, repositoryID)) {
            return val;
        }
    }
    return null;
}

export function FormatImportRuleLabel(rule: GitHubRepositoryImportRule): string {
    switch (rule) {
        case 'AssignedOnly':
            return 'Assigned / Requested Only';
        case 'All':
            return 'All Issues & Pull Requests';
        default:
            return String(rule);
    }
}

/**
 * Builds Tracked Repository & Connector Mirror Console cards, determining `'ConnectorMirror' | 'GitHubREST'`
 * based on whether the repository's `CompanyIntegrationID` has active `MJ: Company Integration Entity Maps`
 * for `@memberjunction/connector-github`.
 */
export function BuildTrackedRepositoryCards(
    options: BuildTrackedRepositoryCardsOptions,
): TrackedRepositoryCardViewModel[] {
    const entityMaps = options.entityMaps ?? [];
    const companyIntegrations = options.companyIntegrations ?? [];

    const cards = options.repositories.map((repo): TrackedRepositoryCardViewModel => {
        const repoId = (repo.ID ?? '').trim();
        const owner = (repo.Owner ?? '').trim();
        const name = (repo.Name ?? '').trim();
        const fullName = `${owner}/${name}`;
        const importRule: GitHubRepositoryImportRule = repo.ImportRule ?? 'AssignedOnly';
        const resolvedCompanyIntegrationID = resolveMatchingCompanyIntegrationID(
            owner,
            name,
            repo.CompanyIntegrationID,
            companyIntegrations,
        );
        const mirrorActive = hasActiveConnectorMirrorEntityMap(
            resolvedCompanyIntegrationID,
            entityMaps,
            companyIntegrations,
        );
        const syncSourceBadge: RepositorySyncSourceBadge = mirrorActive ? 'ConnectorMirror' : 'GitHubREST';
        const rawLastSynced = lookupRepositoryLastSynced(
            repoId,
            repo.LastSyncedAt,
            options.lastSyncedByRepositoryID,
        );
        const lastSyncedIso = NormalizeIsoTimestamp(rawLastSynced);

        return {
            ID: repoId,
            Owner: owner,
            Name: name,
            FullName: fullName,
            DefaultBranch: (repo.DefaultBranch ?? '').trim() || 'main',
            IsTracked: Boolean(repo.IsTracked),
            ImportRule: importRule,
            ImportRuleLabel: FormatImportRuleLabel(importRule),
            DefaultProjectID: (repo.DefaultProjectID ?? '').trim() || null,
            CompanyIntegrationID: resolvedCompanyIntegrationID,
            InstallationID: (repo.InstallationID ?? '').trim() || null,
            OrganizationName: (repo.Organization ?? '').trim() || null,
            LastSyncedAt: lastSyncedIso,
            LastSyncedDisplay: FormatDisplayTimestamp(lastSyncedIso, 'Never synced'),
            SyncSourceBadge: syncSourceBadge,
            SyncSourceLabel:
                syncSourceBadge === 'ConnectorMirror'
                    ? 'Connector Mirror (@memberjunction/connector-github)'
                    : 'Direct GitHub REST',
            GitHubUrl: `https://github.com/${encodeURIComponent(owner)}/${encodeURIComponent(name)}`,
        };
    });

    return cards.sort((a, b) => {
        if (a.IsTracked !== b.IsTracked) {
            return a.IsTracked ? -1 : 1;
        }
        return a.FullName.localeCompare(b.FullName);
    });
}

export function FilterTrackedRepositoryCards(
    cards: readonly TrackedRepositoryCardViewModel[],
    trackingFilter: RepositoryTrackingFilter,
    searchQuery: string,
): TrackedRepositoryCardViewModel[] {
    const query = searchQuery.trim().toLowerCase();
    return cards.filter((card) => {
        if (trackingFilter === 'tracked' && !card.IsTracked) {
            return false;
        }
        if (trackingFilter === 'untracked' && card.IsTracked) {
            return false;
        }
        if (!query) {
            return true;
        }
        return (
            card.FullName.toLowerCase().includes(query) ||
            card.DefaultBranch.toLowerCase().includes(query) ||
            card.SyncSourceBadge.toLowerCase().includes(query) ||
            card.ImportRule.toLowerCase().includes(query) ||
            (card.OrganizationName?.toLowerCase().includes(query) ?? false)
        );
    });
}

// ============================================================================
// 3. GitHub Task Detail Badge Helpers
// ============================================================================

export function FormatGitHubIssueStateLabel(
    state: GitHubIssueState,
    stateReason: GitHubIssueStateReason,
): string {
    if (state === 'open') {
        return stateReason === 'reopened' ? 'Reopened' : 'Open';
    }
    switch (stateReason) {
        case 'not_planned':
            return 'Closed · Not Planned';
        case 'duplicate':
            return 'Closed · Duplicate';
        case 'completed':
            return 'Closed · Completed';
        default:
            return 'Closed';
    }
}

export function FormatGitHubPrStateLabel(
    state: GitHubPullRequestState,
    isDraft: boolean,
): string {
    if (state === 'merged') {
        return 'Merged';
    }
    if (state === 'closed') {
        return 'Closed';
    }
    return isDraft ? 'Draft' : 'Open';
}

export function FormatReviewDecisionLabel(decision: GitHubPullRequestReviewDecision): string | null {
    switch (decision) {
        case 'APPROVED':
            return 'Approved';
        case 'CHANGES_REQUESTED':
            return 'Changes Requested';
        case 'REVIEW_REQUIRED':
            return 'Review Required';
        case null:
        default:
            return null;
    }
}

export function FormatChecksStatusLabel(checksStatus: GitHubPullRequestChecksStatus): string | null {
    switch (checksStatus) {
        case 'Passing':
            return 'Checks Passing';
        case 'Failing':
            return 'Checks Failing';
        case 'Pending':
            return 'Checks Pending';
        case 'Neutral':
            return 'Checks Neutral';
        case null:
        default:
            return null;
    }
}

export function BuildGitHubIssueBadgeViewModel(
    issue: GitHubIssueTaskBadgeInput,
): GitHubIssueBadgeViewModel {
    const htmlUrl = (issue.HtmlURL ?? '').trim() || null;
    const repoName =
        (issue.Repository ?? '').trim() || ExtractRepoFullNameFromHtmlUrl(htmlUrl);
    const issueState: GitHubIssueState = issue.State ?? 'open';
    const stateReason: GitHubIssueStateReason = issue.StateReason ?? null;

    return {
        TaskID: issue.ID ?? '',
        Number: issue.Number ?? null,
        NumberLabel: issue.Number != null ? `#${issue.Number}` : 'Issue',
        IssueState: issueState,
        StateReason: stateReason,
        StateLabel: FormatGitHubIssueStateLabel(issueState, stateReason),
        HtmlUrl: htmlUrl,
        RepositoryFullName: repoName,
        Labels: ParseGitHubLabelsJson(issue.Labels),
        Milestone: (issue.Milestone ?? '').trim() || null,
        AuthorLogin: (issue.AuthorLogin ?? '').trim() || null,
        LastSyncedAt: NormalizeIsoTimestamp(issue.LastSyncedAt),
        PullOwnedFieldLockNotice: PULL_OWNED_FIELD_LOCK_NOTICE,
    };
}

export function BuildGitHubPullRequestBadgeViewModel(
    pr: GitHubPullRequestTaskBadgeInput,
): GitHubPullRequestBadgeViewModel {
    const htmlUrl = (pr.HtmlURL ?? '').trim() || null;
    const repoName =
        (pr.Repository ?? '').trim() || ExtractRepoFullNameFromHtmlUrl(htmlUrl);
    const additions = typeof pr.Additions === 'number' && Number.isFinite(pr.Additions) ? pr.Additions : 0;
    const deletions = typeof pr.Deletions === 'number' && Number.isFinite(pr.Deletions) ? pr.Deletions : 0;
    const headBranch = (pr.HeadBranch ?? '').trim() || null;
    const baseBranch = (pr.BaseBranch ?? '').trim() || null;
    const branchComparison =
        headBranch && baseBranch
            ? `${headBranch} -> ${baseBranch}`
            : headBranch ?? baseBranch;
    const prState: GitHubPullRequestState = pr.State ?? 'open';
    const reviewDecision: GitHubPullRequestReviewDecision = pr.ReviewDecision ?? null;
    const checksStatus: GitHubPullRequestChecksStatus = pr.ChecksStatus ?? null;
    const isDraft = Boolean(pr.IsDraft);

    return {
        TaskID: pr.ID ?? '',
        Number: pr.Number ?? null,
        NumberLabel: pr.Number != null ? `#${pr.Number}` : 'PR',
        PRState: prState,
        IsDraft: isDraft,
        StateLabel: FormatGitHubPrStateLabel(prState, isDraft),
        ReviewDecision: reviewDecision,
        ReviewDecisionLabel: FormatReviewDecisionLabel(reviewDecision),
        ChecksStatus: checksStatus,
        ChecksStatusLabel: FormatChecksStatusLabel(checksStatus),
        Additions: additions,
        Deletions: deletions,
        ChangedFiles: typeof pr.ChangedFiles === 'number' && Number.isFinite(pr.ChangedFiles) ? pr.ChangedFiles : null,
        DiffStatLabel: `+${additions} / -${deletions}`,
        HeadBranch: headBranch,
        BaseBranch: baseBranch,
        BranchComparisonLabel: branchComparison,
        HtmlUrl: htmlUrl,
        RepositoryFullName: repoName,
        Labels: ParseGitHubLabelsJson(pr.Labels),
        Milestone: (pr.Milestone ?? '').trim() || null,
        AuthorLogin: (pr.AuthorLogin ?? '').trim() || null,
        LinkedIssueTaskID: (pr.LinkedIssueTaskID ?? '').trim() || null,
        LastSyncedAt: NormalizeIsoTimestamp(pr.LastSyncedAt),
        PullOwnedFieldLockNotice: PULL_OWNED_FIELD_LOCK_NOTICE,
    };
}

/**
 * Builds the composite GitHub Task Detail Badge View-Model for a Task ID from optional
 * `GitHubIssueTask` and/or `GitHubPullRequestTask` subtype records.
 */
export function BuildGitHubTaskDetailBadgeViewModel(params: {
    taskID: string;
    issueTask?: GitHubIssueTaskBadgeInput | null;
    pullRequestTask?: GitHubPullRequestTaskBadgeInput | null;
}): GitHubTaskDetailBadgeViewModel {
    const issueVm = params.issueTask ? BuildGitHubIssueBadgeViewModel(params.issueTask) : null;
    const prVm = params.pullRequestTask ? BuildGitHubPullRequestBadgeViewModel(params.pullRequestTask) : null;

    return {
        TaskID: params.taskID,
        HasGitHubLink: issueVm !== null || prVm !== null,
        Issue: issueVm,
        PullRequest: prVm,
        PrimaryHtmlUrl: prVm?.HtmlUrl ?? issueVm?.HtmlUrl ?? null,
        PullOwnedFieldLockNotice: PULL_OWNED_FIELD_LOCK_NOTICE,
        GitHubOwnedFields: GITHUB_PULL_OWNED_TASK_FIELDS,
        TasksOwnedFields: TASKS_OWNED_PLANNING_FIELDS,
    };
}

// ============================================================================
// 3b. GitHub Work Panel View-Model Builders (`<mj-github-work-panel>`)
// ============================================================================

export function ClassifyGitHubPullRequestStateTone(
    state: GitHubPullRequestState,
    isDraft: boolean,
): GitHubWorkItemTone {
    if (state === 'merged') {
        return 'merged';
    }
    if (state === 'closed') {
        return 'error';
    }
    return isDraft ? 'neutral' : 'success';
}

export function ClassifyGitHubIssueStateTone(
    state: GitHubIssueState,
    stateReason: GitHubIssueStateReason,
): GitHubWorkItemTone {
    if (state === 'open') {
        return 'success';
    }
    if (stateReason === 'not_planned' || stateReason === 'duplicate') {
        return 'error';
    }
    return 'merged';
}

export function ClassifyGitHubReviewTone(
    decision: GitHubPullRequestReviewDecision,
): GitHubWorkItemTone | null {
    switch (decision) {
        case 'APPROVED':
            return 'success';
        case 'CHANGES_REQUESTED':
            return 'error';
        case 'REVIEW_REQUIRED':
            return 'warning';
        case null:
        default:
            return null;
    }
}

export function ClassifyGitHubChecksTone(
    checksStatus: GitHubPullRequestChecksStatus,
): GitHubWorkItemTone | null {
    switch (checksStatus) {
        case 'Passing':
            return 'success';
        case 'Failing':
            return 'error';
        case 'Pending':
            return 'warning';
        case 'Neutral':
            return 'neutral';
        case null:
        default:
            return null;
    }
}

function normalizeWorkItemLabels(raw: string | readonly string[] | null | undefined): string[] {
    if (!raw) {
        return [];
    }
    if (Array.isArray(raw)) {
        const out: string[] = [];
        for (const entry of raw) {
            if (typeof entry === 'string' && entry.trim().length > 0) {
                out.push(entry.trim());
            }
        }
        return out;
    }
    if (typeof raw === 'string') {
        return ParseGitHubLabelsJson(raw);
    }
    return [];
}

function isOpenWorkItemTone(tone: GitHubWorkItemTone): boolean {
    return tone === 'success' || tone === 'neutral';
}

/**
 * Builds a unified, deterministically sorted array of `GitHubWorkItemViewModel` cards
 * from pre-loaded or fetched GitHub Pull Request and Issue task rows, reusing
 * `BuildGitHubPullRequestBadgeViewModel`, `BuildGitHubIssueBadgeViewModel`,
 * `FormatChecksStatusLabel`, and `FormatReviewDecisionLabel`.
 */
export function BuildGitHubWorkItemViewModels(
    options: BuildGitHubWorkItemViewModelsOptions,
): GitHubWorkItemViewModel[] {
    const fallbackRepo = (options.repositoryFullName ?? '').trim() || null;
    const items: GitHubWorkItemViewModel[] = [];

    for (const pr of options.pullRequests ?? []) {
        const taskId = (pr.TaskID ?? pr.ID ?? '').trim();
        const headBranch = (pr.HeadBranch ?? pr.HeadRef ?? '').trim() || null;
        const baseBranch = (pr.BaseBranch ?? pr.BaseRef ?? '').trim() || null;
        const milestone = (pr.Milestone ?? pr.MilestoneTitle ?? '').trim() || null;
        const explicitRepo = (pr.RepositoryFullName ?? pr.Repository ?? '').trim() || null;

        const badge = BuildGitHubPullRequestBadgeViewModel({
            ID: taskId,
            Number: pr.Number ?? undefined,
            HtmlURL: pr.HtmlURL ?? undefined,
            State: pr.State ?? 'open',
            IsDraft: Boolean(pr.IsDraft),
            ReviewDecision: pr.ReviewDecision ?? null,
            ChecksStatus: pr.ChecksStatus ?? null,
            Additions: pr.Additions ?? undefined,
            Deletions: pr.Deletions ?? undefined,
            ChangedFiles: pr.ChangedFiles ?? undefined,
            HeadBranch: headBranch ?? undefined,
            BaseBranch: baseBranch ?? undefined,
            Labels: typeof pr.Labels === 'string' ? pr.Labels : undefined,
            Milestone: milestone ?? undefined,
            AuthorLogin: pr.AuthorLogin ?? undefined,
            Repository: explicitRepo ?? fallbackRepo ?? undefined,
            LinkedIssueTaskID: pr.LinkedIssueTaskID ?? undefined,
            MergedAt: pr.MergedAt ?? null,
            LastSyncedAt: pr.LastSyncedAt ?? null,
        });

        const hasDiffStats =
            (typeof pr.Additions === 'number' && Number.isFinite(pr.Additions)) ||
            (typeof pr.Deletions === 'number' && Number.isFinite(pr.Deletions));
        const labels = Array.isArray(pr.Labels) ? normalizeWorkItemLabels(pr.Labels) : badge.Labels;
        const title =
            (pr.Title ?? pr.Name ?? '').trim() ||
            (badge.Number !== null ? `Pull Request #${badge.Number}` : 'Pull Request');
        const updatedAt = NormalizeIsoTimestamp(
            pr.UpdatedAt ?? pr.GitHubUpdatedAt ?? pr.__mj_UpdatedAt ?? pr.LastSyncedAt,
        );
        const branchFlow =
            badge.HeadBranch && badge.BaseBranch
                ? `${badge.HeadBranch} → ${badge.BaseBranch}`
                : badge.HeadBranch ?? badge.BaseBranch;

        items.push({
            TaskID: taskId,
            Kind: 'PullRequest',
            Number: badge.Number,
            NumberLabel: badge.Number !== null ? `PR #${badge.Number}` : 'PR',
            Title: title,
            StateLabel: badge.StateLabel,
            StateTone: ClassifyGitHubPullRequestStateTone(badge.PRState, badge.IsDraft),
            HtmlURL: badge.HtmlUrl,
            RepositoryFullName: badge.RepositoryFullName ?? fallbackRepo,
            AuthorLogin: badge.AuthorLogin,
            AssigneeDisplay: (pr.AssigneeDisplay ?? '').trim() || null,
            HeadRef: badge.HeadBranch,
            BaseRef: badge.BaseBranch,
            BranchComparisonLabel: branchFlow,
            Additions: hasDiffStats ? badge.Additions : null,
            Deletions: hasDiffStats ? badge.Deletions : null,
            ChangedFiles: badge.ChangedFiles,
            DiffStatLabel: hasDiffStats ? badge.DiffStatLabel : null,
            IsDraft: badge.IsDraft,
            ReviewDecisionLabel: badge.ReviewDecisionLabel,
            ReviewTone: ClassifyGitHubReviewTone(badge.ReviewDecision),
            ChecksStatusLabel: badge.ChecksStatusLabel,
            ChecksTone: ClassifyGitHubChecksTone(badge.ChecksStatus),
            Labels: labels,
            MilestoneTitle: badge.Milestone,
            UpdatedAt: updatedAt,
            UpdatedAtDisplay: updatedAt ? FormatDisplayTimestamp(updatedAt, '') : null,
        });
    }

    for (const issue of options.issues ?? []) {
        const taskId = (issue.TaskID ?? issue.ID ?? '').trim();
        const milestone = (issue.Milestone ?? issue.MilestoneTitle ?? '').trim() || null;
        const explicitRepo = (issue.RepositoryFullName ?? issue.Repository ?? '').trim() || null;

        const badge = BuildGitHubIssueBadgeViewModel({
            ID: taskId,
            Number: issue.Number ?? undefined,
            HtmlURL: issue.HtmlURL ?? undefined,
            State: issue.State ?? 'open',
            StateReason: issue.StateReason ?? null,
            Labels: typeof issue.Labels === 'string' ? issue.Labels : undefined,
            Milestone: milestone ?? undefined,
            AuthorLogin: issue.AuthorLogin ?? undefined,
            Repository: explicitRepo ?? fallbackRepo ?? undefined,
            LastSyncedAt: issue.LastSyncedAt ?? null,
        });

        const labels = Array.isArray(issue.Labels) ? normalizeWorkItemLabels(issue.Labels) : badge.Labels;
        const title =
            (issue.Title ?? issue.Name ?? '').trim() ||
            (badge.Number !== null ? `Issue #${badge.Number}` : 'Issue');
        const updatedAt = NormalizeIsoTimestamp(
            issue.UpdatedAt ?? issue.GitHubUpdatedAt ?? issue.__mj_UpdatedAt ?? issue.LastSyncedAt,
        );

        items.push({
            TaskID: taskId,
            Kind: 'Issue',
            Number: badge.Number,
            NumberLabel: badge.Number !== null ? `Issue #${badge.Number}` : 'Issue',
            Title: title,
            StateLabel: badge.StateLabel,
            StateTone: ClassifyGitHubIssueStateTone(badge.IssueState, badge.StateReason),
            HtmlURL: badge.HtmlUrl,
            RepositoryFullName: badge.RepositoryFullName ?? fallbackRepo,
            AuthorLogin: badge.AuthorLogin,
            AssigneeDisplay: (issue.AssigneeDisplay ?? '').trim() || null,
            Labels: labels,
            MilestoneTitle: badge.Milestone,
            UpdatedAt: updatedAt,
            UpdatedAtDisplay: updatedAt ? FormatDisplayTimestamp(updatedAt, '') : null,
        });
    }

    return items.sort((a, b) => {
        const aOpen = isOpenWorkItemTone(a.StateTone);
        const bOpen = isOpenWorkItemTone(b.StateTone);
        if (aOpen !== bOpen) {
            return aOpen ? -1 : 1;
        }
        if (a.UpdatedAt && b.UpdatedAt && a.UpdatedAt !== b.UpdatedAt) {
            return b.UpdatedAt.localeCompare(a.UpdatedAt);
        }
        if (a.UpdatedAt && !b.UpdatedAt) {
            return -1;
        }
        if (!a.UpdatedAt && b.UpdatedAt) {
            return 1;
        }
        if (a.Kind !== b.Kind) {
            return a.Kind === 'PullRequest' ? -1 : 1;
        }
        const aNum = a.Number ?? -1;
        const bNum = b.Number ?? -1;
        if (aNum !== bNum) {
            return bNum - aNum;
        }
        return a.Title.localeCompare(b.Title);
    });
}

export function FilterGitHubWorkItems(
    items: readonly GitHubWorkItemViewModel[],
    filter: GitHubWorkPanelFilter,
): GitHubWorkItemViewModel[] {
    if (filter === 'prs') {
        return items.filter((item) => item.Kind === 'PullRequest');
    }
    if (filter === 'issues') {
        return items.filter((item) => item.Kind === 'Issue');
    }
    return [...items];
}

// ============================================================================
// 4. Webhook Delivery & Agent Context Builders
// ============================================================================

function classifyDeliveryStatusTone(rawStatus: string): WebhookDeliveryStatusTone {
    const lower = rawStatus.toLowerCase();
    if (lower.includes('sync') || lower.includes('success') || lower === 'accepted' || lower === 'processed') {
        return 'success';
    }
    if (lower.includes('ignore') || lower.includes('skip') || lower.includes('pending')) {
        return 'warning';
    }
    if (lower.includes('error') || lower.includes('fail') || lower.includes('invalid') || lower.includes('reject')) {
        return 'error';
    }
    return 'neutral';
}

export function BuildWebhookDeliveryRows(
    records: readonly RawWebhookDeliveryRecordInput[],
): WebhookDeliveryRowViewModel[] {
    return records.map((row): WebhookDeliveryRowViewModel => {
        const deliveryId = (row.DeliveryID ?? '').trim() || row.ID.slice(0, 12);
        const eventName = (row.EventName ?? row.Event ?? '').trim() || 'webhook';
        const repoName = (row.RepositoryFullName ?? row.Repository ?? '').trim() || null;
        const statusLabel = (row.Status ?? row.ResultCode ?? '').trim() || 'Recorded';
        const timestampSource = row.ReceivedAt ?? row.StartedAt ?? row.__mj_CreatedAt ?? null;
        const iso = NormalizeIsoTimestamp(timestampSource);

        return {
            ID: row.ID,
            DeliveryID: deliveryId,
            EventName: eventName,
            RepositoryFullName: repoName,
            StatusLabel: statusLabel,
            StatusTone: classifyDeliveryStatusTone(statusLabel),
            Message: (row.Message ?? '').trim() || null,
            ReceivedAtIso: iso,
            ReceivedAtDisplay: FormatDisplayTimestamp(iso, 'Unknown time'),
        };
    });
}

export function BuildGitHubTasksAdminAgentContext(params: {
    activeTab: GitHubTasksAdminTab;
    trackingFilter: RepositoryTrackingFilter;
    searchQuery: string;
    allRepositories: readonly TrackedRepositoryCardViewModel[];
    filteredRepositories: readonly TrackedRepositoryCardViewModel[];
    identity: IdentityMappingViewModel;
    webhookDeliveries: readonly WebhookDeliveryRowViewModel[];
}): GitHubTasksAdminAgentContext {
    return {
        ActiveTab: params.activeTab,
        TrackingFilter: params.trackingFilter,
        SearchQuery: params.searchQuery,
        TotalRepositoryCount: params.allRepositories.length,
        TrackedRepositoryCount: params.allRepositories.filter((r) => r.IsTracked).length,
        ConnectorMirrorRepositoryCount: params.allRepositories.filter(
            (r) => r.SyncSourceBadge === 'ConnectorMirror',
        ).length,
        FilteredRepositoryCount: params.filteredRepositories.length,
        VisibleRepositories: params.filteredRepositories
            .slice(0, MAX_AGENT_CONTEXT_REPOSITORIES)
            .map((r) => ({
                ID: r.ID,
                FullName: r.FullName,
                IsTracked: r.IsTracked,
                ImportRule: r.ImportRule,
                SyncSourceBadge: r.SyncSourceBadge,
                LastSyncedAt: r.LastSyncedAt,
            })),
        IdentityLinkStatus: params.identity.LinkStatus,
        LinkedGitHubLogin: params.identity.GitHubLogin,
        VaultAuthStatus: params.identity.VaultAuthStatus,
        RecentWebhookDeliveryCount: params.webhookDeliveries.length,
    };
}

// ============================================================================
// Sync Summary Aggregation Helpers
// ============================================================================

interface RawSyncSummaryEntry {
    repositoriesSynced?: number;
    created?: number;
    updated?: number;
    skipped?: number;
    errors?: number | string[];
}

export interface AggregatedGitHubSyncSummary {
    RepositoriesSynced: number;
    Created: number;
    Updated: number;
    Skipped: number;
    Errors: number;
}

function readNumericCount(value: number | undefined): number {
    return typeof value === 'number' && Number.isFinite(value) && value >= 0 ? value : 0;
}

function readErrorCount(value: number | string[] | undefined): number {
    if (typeof value === 'number' && Number.isFinite(value) && value >= 0) {
        return value;
    }
    if (Array.isArray(value)) {
        return value.length;
    }
    return 0;
}

/**
 * Parses `SummaryJSON` emitted by `SyncGitHubRepositoryTasksAction` (which serializes
 * `RepositorySyncSummary[]`) and aggregates counts across all repositories while remaining
 * backwards-compatible with single summary objects.
 */
export function AggregateGitHubSyncSummaryJson(
    summaryJson: string | null | undefined,
): AggregatedGitHubSyncSummary | null {
    if (!summaryJson || !summaryJson.trim()) {
        return null;
    }
    try {
        const parsed: RawSyncSummaryEntry | RawSyncSummaryEntry[] = JSON.parse(summaryJson);
        if (Array.isArray(parsed)) {
            let created = 0;
            let updated = 0;
            let skipped = 0;
            let errors = 0;
            for (const entry of parsed) {
                if (!entry || typeof entry !== 'object') {
                    continue;
                }
                created += readNumericCount(entry.created);
                updated += readNumericCount(entry.updated);
                skipped += readNumericCount(entry.skipped);
                errors += readErrorCount(entry.errors);
            }
            return {
                RepositoriesSynced: parsed.length,
                Created: created,
                Updated: updated,
                Skipped: skipped,
                Errors: errors,
            };
        }
        if (parsed && typeof parsed === 'object') {
            return {
                RepositoriesSynced:
                    typeof parsed.repositoriesSynced === 'number' && Number.isFinite(parsed.repositoriesSynced)
                        ? parsed.repositoriesSynced
                        : 1,
                Created: readNumericCount(parsed.created),
                Updated: readNumericCount(parsed.updated),
                Skipped: readNumericCount(parsed.skipped),
                Errors: readErrorCount(parsed.errors),
            };
        }
        return null;
    } catch {
        return null;
    }
}

/**
 * Formats a human-readable banner message from `SyncGitHubRepositoryTasksAction`'s `SummaryJSON` output.
 */
export function FormatGitHubSyncSummaryMessage(
    scopeLabel: string,
    summaryJson: string | null | undefined,
): string {
    const agg = AggregateGitHubSyncSummaryJson(summaryJson);
    if (!agg) {
        return `Synchronized GitHub issues and pull requests for ${scopeLabel}.`;
    }
    const base = `Synchronized ${scopeLabel}: ${agg.Created} created, ${agg.Updated} updated, ${agg.Skipped} skipped`;
    if (agg.Errors > 0) {
        return `${base} (${agg.Errors} ${agg.Errors === 1 ? 'error' : 'errors'}).`;
    }
    return `${base}.`;
}
