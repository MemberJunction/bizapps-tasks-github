import {
    EntityTransactionScope,
    IEntityDataProvider,
    IMetadataProvider,
    LogError,
} from '@memberjunction/core';

/**
 * Structural subset of a MemberJunction provider describing provider-arbitrated
 * entity transaction capability (MJ 6.2+).
 */
export interface TransactionalMetadataProvider {
    readonly SupportsEntityTransactions?: boolean;
    BeginEntityTransaction?(): Promise<EntityTransactionScope>;
}

/**
 * Provider union accepted by `RunWithEntityTransaction`, covering `IMetadataProvider`,
 * `IEntityDataProvider`, and custom transactional test/service providers.
 */
export type MaybeTransactionalProvider =
    | IMetadataProvider
    | IEntityDataProvider
    | TransactionalMetadataProvider
    | null
    | undefined;

interface ActiveTransactionalProvider {
    readonly SupportsEntityTransactions: true;
    BeginEntityTransaction(): Promise<EntityTransactionScope>;
}

function isActiveTransactionalProvider(
    provider: MaybeTransactionalProvider,
): provider is ActiveTransactionalProvider {
    if (!provider || typeof provider !== 'object') {
        return false;
    }
    const candidate = provider as TransactionalMetadataProvider;
    return (
        candidate.SupportsEntityTransactions === true
        && typeof candidate.BeginEntityTransaction === 'function'
    );
}

/**
 * Executes `work` inside a provider-arbitrated `BeginEntityTransaction()` scope
 * whenever `provider.SupportsEntityTransactions === true`, committing atomically
 * on success and rolling back cleanly on any thrown error.
 *
 * When the provider does not support local entity transactions (for example,
 * client-side `GraphQLDataProvider` or lightweight unit-test stubs), executes
 * `work` directly.
 */
export async function RunWithEntityTransaction<T>(
    provider: MaybeTransactionalProvider,
    work: () => Promise<T>,
): Promise<T> {
    if (isActiveTransactionalProvider(provider)) {
        const scope = await provider.BeginEntityTransaction();
        try {
            const result = await work();
            await scope.Commit();
            return result;
        } catch (err) {
            try {
                await scope.Rollback();
            } catch (rollbackErr) {
                LogError(
                    `RunWithEntityTransaction: rollback failed after error; preserving original error: ${
                        rollbackErr instanceof Error ? rollbackErr.message : String(rollbackErr)
                    }`,
                );
            }
            throw err;
        }
    }
    return work();
}
