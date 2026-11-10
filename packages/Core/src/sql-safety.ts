import { EscapeSQLString, IsValidUUID } from '@memberjunction/global';

/**
 * Validates that a value is a canonical 36-character UUID before interpolating into SQL filters.
 * Delegates to `IsValidUUID` from `@memberjunction/global`.
 */
export function IsValidUUIDString(value: string | null | undefined): value is string {
    return typeof value === 'string' && IsValidUUID(value);
}

/**
 * Throws if `value` is not a valid canonical UUID.
 */
export function AssertValidUUID(value: string | null | undefined, label: string): string {
    if (typeof value !== 'string' || !IsValidUUID(value)) {
        throw new Error(`Invalid UUID for ${label}: '${String(value)}'`);
    }
    return value.trim();
}

/**
 * Escapes single quotes for SQL string literals inside RunView ExtraFilter expressions.
 * Delegates to `EscapeSQLString` from `@memberjunction/global`.
 */
export function EscapeSqlLiteral(value: string): string {
    return EscapeSQLString(value);
}
