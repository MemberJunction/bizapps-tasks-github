const UUID_PATTERN = /^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/;

/**
 * Validates that a value is a canonical 36-character UUID before interpolating into SQL filters.
 */
export function IsValidUUIDString(value: string | null | undefined): value is string {
    return typeof value === 'string' && UUID_PATTERN.test(value.trim());
}

/**
 * Throws if `value` is not a valid canonical UUID.
 */
export function AssertValidUUID(value: string | null | undefined, label: string): string {
    if (!IsValidUUIDString(value)) {
        throw new Error(`Invalid UUID for ${label}: '${String(value)}'`);
    }
    return value.trim();
}

/**
 * Escapes single quotes for SQL string literals inside RunView ExtraFilter expressions.
 */
export function EscapeSqlLiteral(value: string): string {
    return value.replace(/'/g, "''");
}
