#!/usr/bin/env node
/**
 * seed-tasks-github-demo.mjs
 *
 * Applies the idempotent multi-domain demo fixtures in scripts/seed-tasks-github-demo.sql
 * against a live SQL Server database (4 GitHubRepository rows, 16 Task rows,
 * 8 GitHubIssueTask rows, 8 GitHubPullRequestTask rows, and 4 TaskLink rows across
 * Open, InProgress, Blocked, Completed, and Cancelled states).
 *
 * Resolves `mssql` via the installed `@memberjunction/sqlserver-dataprovider` package
 * without introducing a new dependency, reading connection coordinates from
 * DB_HOST, DB_PORT, DB_DATABASE, DB_USERNAME, and DB_PASSWORD environment variables.
 *
 * Usage:
 *   DB_HOST=... DB_DATABASE=... DB_USERNAME=... DB_PASSWORD=... node scripts/seed-tasks-github-demo.mjs
 */
import { createRequire } from 'node:module';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const reqFromServer = createRequire(path.resolve(here, '../packages/Server/package.json'));
const reqFromMjServer = createRequire(path.resolve(here, '../../MJ/packages/MJServer/package.json'));

function resolvePkg(specifier) {
    try {
        return reqFromServer.resolve(specifier);
    } catch {
        return reqFromMjServer.resolve(specifier);
    }
}

export function splitIntoBatches(rawSql) {
    return rawSql
        .split(/^\s*GO\s*$/im)
        .map((batch) => batch.trim())
        .filter((batch) => batch.length > 0);
}

export function substituteSchemas(rawSql, options = {}) {
    let result = rawSql;
    if (options.githubSchema) {
        result = result.replace(/\[__mj_BizAppsTasksGitHub\]/g, `[${options.githubSchema}]`);
    }
    if (options.tasksSchema) {
        result = result.replace(/\[__mj_BizAppsTasks\]/g, `[${options.tasksSchema}]`);
    }
    if (options.coreSchema) {
        result = result.replace(/\[__mj\]/g, `[${options.coreSchema}]`);
    }
    return result;
}

async function main() {
    const {
        DB_HOST,
        DB_PORT,
        DB_DATABASE,
        DB_USERNAME,
        DB_PASSWORD,
        MJ_BIZAPPS_TASKS_GITHUB_SCHEMA,
        MJ_BIZAPPS_TASKS_SCHEMA,
        MJ_CORE_SCHEMA,
    } = process.env;

    if (!DB_HOST || !DB_DATABASE || !DB_USERNAME || !DB_PASSWORD) {
        console.error('Missing required DB_HOST / DB_DATABASE / DB_USERNAME / DB_PASSWORD environment variables.');
        process.exit(1);
    }

    const sqlProviderPath = resolvePkg('@memberjunction/sqlserver-dataprovider');
    const requireFromSqlProvider = createRequire(sqlProviderPath);
    const sql = requireFromSqlProvider('mssql');

    const seedFilePath = path.resolve(here, './seed-tasks-github-demo.sql');
    const rawSql = readFileSync(seedFilePath, 'utf8');
    const substituted = substituteSchemas(rawSql, {
        githubSchema: MJ_BIZAPPS_TASKS_GITHUB_SCHEMA,
        tasksSchema: MJ_BIZAPPS_TASKS_SCHEMA,
        coreSchema: MJ_CORE_SCHEMA,
    });
    const batches = splitIntoBatches(substituted);

    const pool = await new sql.ConnectionPool({
        server: DB_HOST,
        port: Number(DB_PORT ?? 1433),
        database: DB_DATABASE,
        user: DB_USERNAME,
        password: DB_PASSWORD,
        options: { trustServerCertificate: true, encrypt: false },
        pool: { max: 5, min: 1 },
        requestTimeout: 60_000,
    }).connect();

    console.log(`Seeding ${batches.length} demo batch(es) into ${DB_DATABASE}...`);
    try {
        for (let i = 0; i < batches.length; i++) {
            await pool.request().batch(batches[i]);
            console.log(`  ✔ batch ${i + 1}/${batches.length}`);
        }
        console.log('✅ GitHub Tasks multi-domain demo fixtures seeded successfully.');
    } finally {
        await pool.close();
    }
}

function isEntryPoint() {
    if (!process.argv[1]) return false;
    return path.resolve(process.argv[1]) === fileURLToPath(import.meta.url);
}

if (isEntryPoint()) {
    main().catch((err) => {
        console.error(err);
        process.exit(1);
    });
}
