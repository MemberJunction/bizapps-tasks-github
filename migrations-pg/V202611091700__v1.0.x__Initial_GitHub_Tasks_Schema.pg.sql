-- ============================================================================
-- MemberJunction PostgreSQL Migration
-- Converted from SQL Server using TypeScript conversion pipeline
-- ============================================================================

-- Extensions
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Schema
--
-- The schema name is emitted UNQUOTED, so PostgreSQL folds it to lowercase. That is deliberate and
-- self-consistent: everything downstream in a converted migration refers to it unquoted too, so
-- both definition and lookup land on the same folded name.
--
-- DOWNSTREAM NOTE for the build engineer: a PostgreSQL database that was populated by an EARLIER
-- converter — one that emitted a quoted, case-preserved name — already holds that mixed-case
-- schema: for a target named MySchema_Name, the quoted "MySchema_Name". Re-converting against
-- that database creates a SECOND, empty schema myschema_name rather than reusing the existing
-- one, because IF NOT EXISTS compares the folded name and finds no match. The repo's own committed
-- migrations-pg files are unaffected (the only quoted CREATE SCHEMAs there are the four pg_dump
-- baselines, which this path does not produce), so this is an open-app / downstream concern, not
-- one for this repo's Flyway history.
CREATE SCHEMA IF NOT EXISTS __mj_BizAppsTasksGitHub;
SET search_path TO __mj_BizAppsTasksGitHub, public;

-- Ensure backslashes in string literals are treated literally (not as escape sequences)
SET standard_conforming_strings = on;

-- NOTE: Earlier converter versions made INTEGER to BOOLEAN cast implicit by
-- modifying the system catalog so SS-style INSERT INTO bool_col VALUES (1)
-- would work. That modification required pg_catalog write privileges, which
-- managed PG (RDS, Aurora, Cloud SQL, Azure) does not grant. As of v5.30 all
-- bulk INSERTs are emitted with native TRUE/FALSE values directly, so the
-- cast modification is no longer needed. Removed to support managed-PG
-- installs out of the box.


-- ===================== DDL: Tables, PKs, Indexes =====================

CREATE SCHEMA IF NOT EXISTS __mj_bizappstasksgithub;

---------------------------------------------------------------------------
-- 1. GitHubRepository
---------------------------------------------------------------------------
CREATE TABLE __mj_BizAppsTasksGitHub."GitHubRepository" (
 "ID" UUID NOT NULL DEFAULT gen_random_uuid(),
 "Owner" VARCHAR(150) NOT NULL,
 "Name" VARCHAR(200) NOT NULL,
 "DefaultBranch" VARCHAR(120) NOT NULL DEFAULT 'main',
 "IsTracked" BOOLEAN NOT NULL DEFAULT TRUE,
 "ImportRule" VARCHAR(20) NOT NULL DEFAULT 'AssignedOnly',
 "InstallationID" VARCHAR(100) NULL,
 "OrganizationID" UUID NULL,
 "DeliveryPolicyID" UUID NULL,
 CONSTRAINT "PK_GitHubRepository" PRIMARY KEY ("ID"),
 CONSTRAINT "UQ_GitHubRepository_Owner_Name" UNIQUE ("Owner", "Name"),
 CONSTRAINT "FK_GitHubRepository_Organization" FOREIGN KEY ("OrganizationID") REFERENCES __mj_BizAppsCommon."Organization"("ID"),
 CONSTRAINT "CK_GitHubRepository_ImportRule" CHECK ("ImportRule" IN ('AssignedOnly', 'All'))
);

CREATE INDEX IF NOT EXISTS "IX_GitHubRepository_IsTracked"
    ON __mj_BizAppsTasksGitHub."GitHubRepository" ("IsTracked");

CREATE INDEX IF NOT EXISTS "IX_GitHubRepository_OrganizationID"
    ON __mj_BizAppsTasksGitHub."GitHubRepository" ("OrganizationID");

---------------------------------------------------------------------------
-- 2. GitHubIdentity
---------------------------------------------------------------------------
CREATE TABLE __mj_BizAppsTasksGitHub."GitHubIdentity" (
 "ID" UUID NOT NULL DEFAULT gen_random_uuid(),
 "GitHubLogin" VARCHAR(100) NOT NULL,
 "PersonID" UUID NOT NULL,
 "GitHubUserID" VARCHAR(64) NULL,
 "IsActive" BOOLEAN NOT NULL DEFAULT TRUE,
 CONSTRAINT "PK_GitHubIdentity" PRIMARY KEY ("ID"),
 CONSTRAINT "UQ_GitHubIdentity_Login" UNIQUE ("GitHubLogin"),
 CONSTRAINT "FK_GitHubIdentity_Person" FOREIGN KEY ("PersonID") REFERENCES __mj_BizAppsCommon."Person"("ID")
);

CREATE INDEX IF NOT EXISTS "IX_GitHubIdentity_PersonID"
    ON __mj_BizAppsTasksGitHub."GitHubIdentity" ("PersonID");

---------------------------------------------------------------------------
-- 3. GitHubIssueTask (IS-A Disjoint Child of __mj_BizAppsTasks.Task)
---------------------------------------------------------------------------
CREATE TABLE __mj_BizAppsTasksGitHub."GitHubIssueTask" (
 "ID" UUID NOT NULL,
 "RepositoryID" UUID NULL,
 "Number" INTEGER NULL,
 "NodeID" VARCHAR(128) NULL,
 "HtmlURL" VARCHAR(1000) NULL,
 "State" VARCHAR(20) NOT NULL DEFAULT 'open',
 "StateReason" VARCHAR(40) NULL,
 "Labels" TEXT NULL,
 "Milestone" VARCHAR(255) NULL,
 "MilestoneDueAt" TIMESTAMPTZ NULL,
 "AuthorLogin" VARCHAR(100) NULL,
 "BodyHash" VARCHAR(64) NULL,
 "GitHubUpdatedAt" TIMESTAMPTZ NULL,
 "LastSyncedAt" TIMESTAMPTZ NULL,
 CONSTRAINT "PK_GitHubIssueTask" PRIMARY KEY ("ID"),
 CONSTRAINT "FK_GitHubIssueTask_Task" FOREIGN KEY ("ID") REFERENCES __mj_BizAppsTasks."Task"("ID"),
 CONSTRAINT "FK_GitHubIssueTask_Repository" FOREIGN KEY ("RepositoryID") REFERENCES __mj_BizAppsTasksGitHub."GitHubRepository"("ID"),
 CONSTRAINT "CK_GitHubIssueTask_State" CHECK ("State" IN ('open', 'closed')),
 CONSTRAINT "CK_GitHubIssueTask_StateReason" CHECK ("StateReason" IS NULL OR "StateReason" IN ('completed', 'not_planned', 'reopened', 'duplicate'))
);

CREATE UNIQUE INDEX IF NOT EXISTS "UX_GitHubIssueTask_Repo_Number"
    ON __mj_BizAppsTasksGitHub."GitHubIssueTask" ("RepositoryID", "Number")
    WHERE "RepositoryID" IS NOT NULL AND "Number" IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS "UX_GitHubIssueTask_NodeID"
    ON __mj_BizAppsTasksGitHub."GitHubIssueTask" ("NodeID")
    WHERE "NodeID" IS NOT NULL;

---------------------------------------------------------------------------
-- 4. GitHubPullRequestTask (IS-A Disjoint Child of __mj_BizAppsTasks.Task)
---------------------------------------------------------------------------
CREATE TABLE __mj_BizAppsTasksGitHub."GitHubPullRequestTask" (
 "ID" UUID NOT NULL,
 "RepositoryID" UUID NULL,
 "Number" INTEGER NULL,
 "NodeID" VARCHAR(128) NULL,
 "HtmlURL" VARCHAR(1000) NULL,
 "State" VARCHAR(20) NOT NULL DEFAULT 'open',
 "IsDraft" BOOLEAN NOT NULL DEFAULT FALSE,
 "HeadBranch" VARCHAR(255) NULL,
 "HeadSha" VARCHAR(64) NULL,
 "BaseBranch" VARCHAR(255) NULL,
 "AuthorLogin" VARCHAR(100) NULL,
 "ReviewDecision" VARCHAR(40) NULL,
 "ChecksStatus" VARCHAR(30) NULL,
 "ChangedFiles" INTEGER NULL,
 "Additions" INTEGER NULL,
 "Deletions" INTEGER NULL,
 "Labels" TEXT NULL,
 "Milestone" VARCHAR(255) NULL,
 "MilestoneDueAt" TIMESTAMPTZ NULL,
 "MergedAt" TIMESTAMPTZ NULL,
 "LinkedIssueTaskID" UUID NULL,
 "BodyHash" VARCHAR(64) NULL,
 "GitHubUpdatedAt" TIMESTAMPTZ NULL,
 "LastSyncedAt" TIMESTAMPTZ NULL,
 CONSTRAINT "PK_GitHubPullRequestTask" PRIMARY KEY ("ID"),
 CONSTRAINT "FK_GitHubPRTask_Task" FOREIGN KEY ("ID") REFERENCES __mj_BizAppsTasks."Task"("ID"),
 CONSTRAINT "FK_GitHubPRTask_Repository" FOREIGN KEY ("RepositoryID") REFERENCES __mj_BizAppsTasksGitHub."GitHubRepository"("ID"),
 CONSTRAINT "FK_GitHubPRTask_LinkedIssueTask" FOREIGN KEY ("LinkedIssueTaskID") REFERENCES __mj_BizAppsTasks."Task"("ID"),
 CONSTRAINT "CK_GitHubPRTask_State" CHECK ("State" IN ('open', 'closed', 'merged')),
 CONSTRAINT "CK_GitHubPRTask_ReviewDecision" CHECK ("ReviewDecision" IS NULL OR "ReviewDecision" IN ('APPROVED', 'CHANGES_REQUESTED', 'REVIEW_REQUIRED')),
 CONSTRAINT "CK_GitHubPRTask_ChecksStatus" CHECK ("ChecksStatus" IS NULL OR "ChecksStatus" IN ('Pending', 'Passing', 'Failing', 'Neutral'))
);

CREATE UNIQUE INDEX IF NOT EXISTS "UX_GitHubPRTask_Repo_Number"
    ON __mj_BizAppsTasksGitHub."GitHubPullRequestTask" ("RepositoryID", "Number")
    WHERE "RepositoryID" IS NOT NULL AND "Number" IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS "UX_GitHubPRTask_NodeID"
    ON __mj_BizAppsTasksGitHub."GitHubPullRequestTask" ("NodeID")
    WHERE "NodeID" IS NOT NULL;

CREATE INDEX IF NOT EXISTS "IX_GitHubPRTask_LinkedIssueTaskID"
    ON __mj_BizAppsTasksGitHub."GitHubPullRequestTask" ("LinkedIssueTaskID");

ALTER TABLE __mj_BizAppsTasksGitHub."GitHubRepository"
 ADD COLUMN IF NOT EXISTS "__mj_CreatedAt" TIMESTAMPTZ NULL;

/* SQL text to add special date field __mj_UpdatedAt to entity __mj_BizAppsTasksGitHub.GitHubRepository */
ALTER TABLE __mj_BizAppsTasksGitHub."GitHubRepository"
 ADD COLUMN IF NOT EXISTS "__mj_UpdatedAt" TIMESTAMPTZ NULL;

/* SQL text to add special date field __mj_CreatedAt to entity __mj_BizAppsTasksGitHub.GitHubIssueTask */
ALTER TABLE __mj_BizAppsTasksGitHub."GitHubIssueTask"
 ADD COLUMN IF NOT EXISTS "__mj_CreatedAt" TIMESTAMPTZ NULL;

/* SQL text to add special date field __mj_UpdatedAt to entity __mj_BizAppsTasksGitHub.GitHubIssueTask */
ALTER TABLE __mj_BizAppsTasksGitHub."GitHubIssueTask"
 ADD COLUMN IF NOT EXISTS "__mj_UpdatedAt" TIMESTAMPTZ NULL;

/* SQL text to add special date field __mj_CreatedAt to entity __mj_BizAppsTasksGitHub.GitHubIdentity */
ALTER TABLE __mj_BizAppsTasksGitHub."GitHubIdentity"
 ADD COLUMN IF NOT EXISTS "__mj_CreatedAt" TIMESTAMPTZ NULL;

/* SQL text to add special date field __mj_UpdatedAt to entity __mj_BizAppsTasksGitHub.GitHubIdentity */
ALTER TABLE __mj_BizAppsTasksGitHub."GitHubIdentity"
 ADD COLUMN IF NOT EXISTS "__mj_UpdatedAt" TIMESTAMPTZ NULL;

/* SQL text to add special date field __mj_CreatedAt to entity __mj_BizAppsTasksGitHub.GitHubPullRequestTask */
ALTER TABLE __mj_BizAppsTasksGitHub."GitHubPullRequestTask"
 ADD COLUMN IF NOT EXISTS "__mj_CreatedAt" TIMESTAMPTZ NULL;

/* SQL text to add special date field __mj_UpdatedAt to entity __mj_BizAppsTasksGitHub.GitHubPullRequestTask */
ALTER TABLE __mj_BizAppsTasksGitHub."GitHubPullRequestTask"
 ADD COLUMN IF NOT EXISTS "__mj_UpdatedAt" TIMESTAMPTZ NULL;

CREATE INDEX IF NOT EXISTS "IDX_AUTO_MJ_FKEY_GitHubIdentity_PersonID" ON __mj_BizAppsTasksGitHub."GitHubIdentity" ("PersonID");

CREATE INDEX IF NOT EXISTS "IDX_AUTO_MJ_FKEY_GitHubIssueTask_RepositoryID" ON __mj_BizAppsTasksGitHub."GitHubIssueTask" ("RepositoryID");

CREATE INDEX IF NOT EXISTS "IDX_AUTO_MJ_FKEY_GitHubPullRequestTask_RepositoryID" ON __mj_BizAppsTasksGitHub."GitHubPullRequestTask" ("RepositoryID");

CREATE INDEX IF NOT EXISTS "IDX_AUTO_MJ_FKEY_GitHubPullRequestTask_LinkedIssueTaskID" ON __mj_BizAppsTasksGitHub."GitHubPullRequestTask" ("LinkedIssueTaskID");

CREATE INDEX IF NOT EXISTS "IDX_AUTO_MJ_FKEY_GitHubRepository_OrganizationID" ON __mj_BizAppsTasksGitHub."GitHubRepository" ("OrganizationID");


-- ===================== Views =====================

DROP VIEW IF EXISTS __mj_BizAppsTasksGitHub."vwGitHubIdentities" CASCADE;
DO $do$
DECLARE
  v_target_schema CONSTANT TEXT := '__mj_BizAppsTasksGitHub';
  v_target_name CONSTANT TEXT := 'vwGitHubIdentities';
  vsql CONSTANT TEXT := $vsql$CREATE OR REPLACE VIEW __mj_BizAppsTasksGitHub."vwGitHubIdentities"
AS SELECT
    g.*,
    "mjBizAppsCommonPerson_PersonID"."DisplayName" AS "Person"
FROM
    __mj_BizAppsTasksGitHub."GitHubIdentity" AS g
LEFT OUTER JOIN
    __mj_BizAppsCommon."Person" AS "mjBizAppsCommonPerson_PersonID"
  ON
    g."PersonID" = "mjBizAppsCommonPerson_PersonID"."ID"$vsql$;
  v_target_oid OID;
  v_dep RECORD;
  v_captured JSONB[] := ARRAY[]::JSONB[];
  v_n INTEGER;
BEGIN
  EXECUTE vsql;
EXCEPTION WHEN invalid_table_definition THEN
  -- Column list changed; need CASCADE. Preserve dependent views first.
  SELECT c.oid INTO v_target_oid
  FROM pg_class c JOIN pg_namespace n ON c.relnamespace = n.oid
  WHERE n.nspname = v_target_schema AND c.relname = v_target_name AND c.relkind = 'v';
  IF v_target_oid IS NOT NULL THEN
    FOR v_dep IN
      WITH RECURSIVE deps AS (
        SELECT c.oid, c.relname AS name, n.nspname AS schema, 1 AS depth
        FROM pg_rewrite r
        JOIN pg_depend d ON d.objid = r.oid
        JOIN pg_class c ON c.oid = r.ev_class
        JOIN pg_namespace n ON c.relnamespace = n.oid
        WHERE d.refobjid = v_target_oid AND d.deptype = 'n'
          AND c.oid <> v_target_oid AND c.relkind = 'v'
        UNION
        SELECT c.oid, c.relname, n.nspname, p.depth + 1
        FROM deps p
        JOIN pg_rewrite r ON TRUE
        JOIN pg_depend d ON d.objid = r.oid AND d.refobjid = p.oid
        JOIN pg_class c ON c.oid = r.ev_class
        JOIN pg_namespace n ON c.relnamespace = n.oid
        WHERE c.relkind = 'v' AND c.oid <> p.oid
      )
      SELECT oid, name, schema, MAX(depth) AS max_depth,
             pg_catalog.pg_get_viewdef(oid, true) AS viewdef
      FROM deps GROUP BY oid, name, schema
      ORDER BY MAX(depth) ASC
    LOOP
      v_captured := v_captured || jsonb_build_object(
        'schema', v_dep.schema, 'name', v_dep.name, 'def', v_dep.viewdef);
    END LOOP;
  END IF;
  EXECUTE format('DROP VIEW IF EXISTS %I.%I CASCADE', v_target_schema, v_target_name);
  EXECUTE vsql;
  IF v_captured IS NOT NULL AND array_length(v_captured, 1) > 0 THEN
    FOR v_n IN 1..array_length(v_captured, 1) LOOP
      BEGIN
        EXECUTE format('CREATE VIEW %I.%I AS %s',
          v_captured[v_n]->>'schema', v_captured[v_n]->>'name', v_captured[v_n]->>'def');
      EXCEPTION WHEN others THEN
        RAISE WARNING 'Could not restore dependent view %.%: %',
          v_captured[v_n]->>'schema', v_captured[v_n]->>'name', SQLERRM;
      END;
    END LOOP;
  END IF;
END;
$do$;

DROP VIEW IF EXISTS __mj_BizAppsTasksGitHub."vwGitHubIssueTasks" CASCADE;
DO $do$
DECLARE
  v_target_schema CONSTANT TEXT := '__mj_BizAppsTasksGitHub';
  v_target_name CONSTANT TEXT := 'vwGitHubIssueTasks';
  vsql CONSTANT TEXT := $vsql$CREATE OR REPLACE VIEW __mj_BizAppsTasksGitHub."vwGitHubIssueTasks"
AS SELECT
    g.*,
    "mjBizAppsTasksGitHubGitHubRepository_RepositoryID"."Name" AS "Repository"
FROM
    __mj_BizAppsTasksGitHub."GitHubIssueTask" AS g
LEFT OUTER JOIN
    __mj_BizAppsTasksGitHub."GitHubRepository" AS "mjBizAppsTasksGitHubGitHubRepository_RepositoryID"
  ON
    g."RepositoryID" = "mjBizAppsTasksGitHubGitHubRepository_RepositoryID"."ID"$vsql$;
  v_target_oid OID;
  v_dep RECORD;
  v_captured JSONB[] := ARRAY[]::JSONB[];
  v_n INTEGER;
BEGIN
  EXECUTE vsql;
EXCEPTION WHEN invalid_table_definition THEN
  -- Column list changed; need CASCADE. Preserve dependent views first.
  SELECT c.oid INTO v_target_oid
  FROM pg_class c JOIN pg_namespace n ON c.relnamespace = n.oid
  WHERE n.nspname = v_target_schema AND c.relname = v_target_name AND c.relkind = 'v';
  IF v_target_oid IS NOT NULL THEN
    FOR v_dep IN
      WITH RECURSIVE deps AS (
        SELECT c.oid, c.relname AS name, n.nspname AS schema, 1 AS depth
        FROM pg_rewrite r
        JOIN pg_depend d ON d.objid = r.oid
        JOIN pg_class c ON c.oid = r.ev_class
        JOIN pg_namespace n ON c.relnamespace = n.oid
        WHERE d.refobjid = v_target_oid AND d.deptype = 'n'
          AND c.oid <> v_target_oid AND c.relkind = 'v'
        UNION
        SELECT c.oid, c.relname, n.nspname, p.depth + 1
        FROM deps p
        JOIN pg_rewrite r ON TRUE
        JOIN pg_depend d ON d.objid = r.oid AND d.refobjid = p.oid
        JOIN pg_class c ON c.oid = r.ev_class
        JOIN pg_namespace n ON c.relnamespace = n.oid
        WHERE c.relkind = 'v' AND c.oid <> p.oid
      )
      SELECT oid, name, schema, MAX(depth) AS max_depth,
             pg_catalog.pg_get_viewdef(oid, true) AS viewdef
      FROM deps GROUP BY oid, name, schema
      ORDER BY MAX(depth) ASC
    LOOP
      v_captured := v_captured || jsonb_build_object(
        'schema', v_dep.schema, 'name', v_dep.name, 'def', v_dep.viewdef);
    END LOOP;
  END IF;
  EXECUTE format('DROP VIEW IF EXISTS %I.%I CASCADE', v_target_schema, v_target_name);
  EXECUTE vsql;
  IF v_captured IS NOT NULL AND array_length(v_captured, 1) > 0 THEN
    FOR v_n IN 1..array_length(v_captured, 1) LOOP
      BEGIN
        EXECUTE format('CREATE VIEW %I.%I AS %s',
          v_captured[v_n]->>'schema', v_captured[v_n]->>'name', v_captured[v_n]->>'def');
      EXCEPTION WHEN others THEN
        RAISE WARNING 'Could not restore dependent view %.%: %',
          v_captured[v_n]->>'schema', v_captured[v_n]->>'name', SQLERRM;
      END;
    END LOOP;
  END IF;
END;
$do$;

DROP VIEW IF EXISTS __mj_BizAppsTasksGitHub."vwGitHubRepositories" CASCADE;
DO $do$
DECLARE
  v_target_schema CONSTANT TEXT := '__mj_BizAppsTasksGitHub';
  v_target_name CONSTANT TEXT := 'vwGitHubRepositories';
  vsql CONSTANT TEXT := $vsql$CREATE OR REPLACE VIEW __mj_BizAppsTasksGitHub."vwGitHubRepositories"
AS SELECT
    g.*,
    "mjBizAppsCommonOrganization_OrganizationID"."Name" AS "Organization"
FROM
    __mj_BizAppsTasksGitHub."GitHubRepository" AS g
LEFT OUTER JOIN
    __mj_BizAppsCommon."Organization" AS "mjBizAppsCommonOrganization_OrganizationID"
  ON
    g."OrganizationID" = "mjBizAppsCommonOrganization_OrganizationID"."ID"$vsql$;
  v_target_oid OID;
  v_dep RECORD;
  v_captured JSONB[] := ARRAY[]::JSONB[];
  v_n INTEGER;
BEGIN
  EXECUTE vsql;
EXCEPTION WHEN invalid_table_definition THEN
  -- Column list changed; need CASCADE. Preserve dependent views first.
  SELECT c.oid INTO v_target_oid
  FROM pg_class c JOIN pg_namespace n ON c.relnamespace = n.oid
  WHERE n.nspname = v_target_schema AND c.relname = v_target_name AND c.relkind = 'v';
  IF v_target_oid IS NOT NULL THEN
    FOR v_dep IN
      WITH RECURSIVE deps AS (
        SELECT c.oid, c.relname AS name, n.nspname AS schema, 1 AS depth
        FROM pg_rewrite r
        JOIN pg_depend d ON d.objid = r.oid
        JOIN pg_class c ON c.oid = r.ev_class
        JOIN pg_namespace n ON c.relnamespace = n.oid
        WHERE d.refobjid = v_target_oid AND d.deptype = 'n'
          AND c.oid <> v_target_oid AND c.relkind = 'v'
        UNION
        SELECT c.oid, c.relname, n.nspname, p.depth + 1
        FROM deps p
        JOIN pg_rewrite r ON TRUE
        JOIN pg_depend d ON d.objid = r.oid AND d.refobjid = p.oid
        JOIN pg_class c ON c.oid = r.ev_class
        JOIN pg_namespace n ON c.relnamespace = n.oid
        WHERE c.relkind = 'v' AND c.oid <> p.oid
      )
      SELECT oid, name, schema, MAX(depth) AS max_depth,
             pg_catalog.pg_get_viewdef(oid, true) AS viewdef
      FROM deps GROUP BY oid, name, schema
      ORDER BY MAX(depth) ASC
    LOOP
      v_captured := v_captured || jsonb_build_object(
        'schema', v_dep.schema, 'name', v_dep.name, 'def', v_dep.viewdef);
    END LOOP;
  END IF;
  EXECUTE format('DROP VIEW IF EXISTS %I.%I CASCADE', v_target_schema, v_target_name);
  EXECUTE vsql;
  IF v_captured IS NOT NULL AND array_length(v_captured, 1) > 0 THEN
    FOR v_n IN 1..array_length(v_captured, 1) LOOP
      BEGIN
        EXECUTE format('CREATE VIEW %I.%I AS %s',
          v_captured[v_n]->>'schema', v_captured[v_n]->>'name', v_captured[v_n]->>'def');
      EXCEPTION WHEN others THEN
        RAISE WARNING 'Could not restore dependent view %.%: %',
          v_captured[v_n]->>'schema', v_captured[v_n]->>'name', SQLERRM;
      END;
    END LOOP;
  END IF;
END;
$do$;

DROP VIEW IF EXISTS __mj_BizAppsTasksGitHub."vwGitHubPullRequestTasks" CASCADE;
DO $do$
DECLARE
  v_target_schema CONSTANT TEXT := '__mj_BizAppsTasksGitHub';
  v_target_name CONSTANT TEXT := 'vwGitHubPullRequestTasks';
  vsql CONSTANT TEXT := $vsql$CREATE OR REPLACE VIEW __mj_BizAppsTasksGitHub."vwGitHubPullRequestTasks"
AS SELECT
    g.*,
    "mjBizAppsTasksGitHubGitHubRepository_RepositoryID"."Name" AS "Repository",
    "mjBizAppsTasksTask_LinkedIssueTaskID"."Name" AS "LinkedIssueTask"
FROM
    __mj_BizAppsTasksGitHub."GitHubPullRequestTask" AS g
LEFT OUTER JOIN
    __mj_BizAppsTasksGitHub."GitHubRepository" AS "mjBizAppsTasksGitHubGitHubRepository_RepositoryID"
  ON
    g."RepositoryID" = "mjBizAppsTasksGitHubGitHubRepository_RepositoryID"."ID"
LEFT OUTER JOIN
    __mj_BizAppsTasks."Task" AS "mjBizAppsTasksTask_LinkedIssueTaskID"
  ON
    g."LinkedIssueTaskID" = "mjBizAppsTasksTask_LinkedIssueTaskID"."ID"$vsql$;
  v_target_oid OID;
  v_dep RECORD;
  v_captured JSONB[] := ARRAY[]::JSONB[];
  v_n INTEGER;
BEGIN
  EXECUTE vsql;
EXCEPTION WHEN invalid_table_definition THEN
  -- Column list changed; need CASCADE. Preserve dependent views first.
  SELECT c.oid INTO v_target_oid
  FROM pg_class c JOIN pg_namespace n ON c.relnamespace = n.oid
  WHERE n.nspname = v_target_schema AND c.relname = v_target_name AND c.relkind = 'v';
  IF v_target_oid IS NOT NULL THEN
    FOR v_dep IN
      WITH RECURSIVE deps AS (
        SELECT c.oid, c.relname AS name, n.nspname AS schema, 1 AS depth
        FROM pg_rewrite r
        JOIN pg_depend d ON d.objid = r.oid
        JOIN pg_class c ON c.oid = r.ev_class
        JOIN pg_namespace n ON c.relnamespace = n.oid
        WHERE d.refobjid = v_target_oid AND d.deptype = 'n'
          AND c.oid <> v_target_oid AND c.relkind = 'v'
        UNION
        SELECT c.oid, c.relname, n.nspname, p.depth + 1
        FROM deps p
        JOIN pg_rewrite r ON TRUE
        JOIN pg_depend d ON d.objid = r.oid AND d.refobjid = p.oid
        JOIN pg_class c ON c.oid = r.ev_class
        JOIN pg_namespace n ON c.relnamespace = n.oid
        WHERE c.relkind = 'v' AND c.oid <> p.oid
      )
      SELECT oid, name, schema, MAX(depth) AS max_depth,
             pg_catalog.pg_get_viewdef(oid, true) AS viewdef
      FROM deps GROUP BY oid, name, schema
      ORDER BY MAX(depth) ASC
    LOOP
      v_captured := v_captured || jsonb_build_object(
        'schema', v_dep.schema, 'name', v_dep.name, 'def', v_dep.viewdef);
    END LOOP;
  END IF;
  EXECUTE format('DROP VIEW IF EXISTS %I.%I CASCADE', v_target_schema, v_target_name);
  EXECUTE vsql;
  IF v_captured IS NOT NULL AND array_length(v_captured, 1) > 0 THEN
    FOR v_n IN 1..array_length(v_captured, 1) LOOP
      BEGIN
        EXECUTE format('CREATE VIEW %I.%I AS %s',
          v_captured[v_n]->>'schema', v_captured[v_n]->>'name', v_captured[v_n]->>'def');
      EXCEPTION WHEN others THEN
        RAISE WARNING 'Could not restore dependent view %.%: %',
          v_captured[v_n]->>'schema', v_captured[v_n]->>'name', SQLERRM;
      END;
    END LOOP;
  END IF;
END;
$do$;

DROP VIEW IF EXISTS __mj_BizAppsTasksGitHub."vwGitHubPullRequestTasks" CASCADE;
DO $do$
DECLARE
  v_target_schema CONSTANT TEXT := '__mj_BizAppsTasksGitHub';
  v_target_name CONSTANT TEXT := 'vwGitHubPullRequestTasks';
  vsql CONSTANT TEXT := $vsql$CREATE OR REPLACE VIEW __mj_BizAppsTasksGitHub."vwGitHubPullRequestTasks"
AS SELECT
    g.*,
    __mj_isa_p1."Name",
    __mj_isa_p1."Description",
    __mj_isa_p1."TypeID",
    __mj_isa_p1."CategoryID",
    __mj_isa_p1."ParentID",
    __mj_isa_p1."Status",
    __mj_isa_p1."Priority",
    __mj_isa_p1."StartedAt",
    __mj_isa_p1."DueAt",
    __mj_isa_p1."CompletedAt",
    __mj_isa_p1."HoursEstimated",
    __mj_isa_p1."HoursActual",
    __mj_isa_p1."PercentComplete",
    __mj_isa_p1."Sequence",
    __mj_isa_p1."BlockedReason",
    __mj_isa_p1."CompletionNotes",
    __mj_isa_p1."CreatedByPersonID",
    __mj_isa_p1."OverdueNotifiedAt",
    __mj_isa_p1."TaskTypeStatusID",
    __mj_isa_p1."PredictedSLABreachProbability",
    __mj_isa_p1."PredictedSLARiskBand",
    __mj_isa_p1."PredictedSLAScoredAt",
    __mj_isa_p1."HealthStatus",
    __mj_isa_p1."ConfidenceScore",
    __mj_isa_p1."BaselineValue",
    __mj_isa_p1."TargetValue",
    __mj_isa_p1."CurrentValue",
    __mj_isa_p1."UnitOfMeasure",
    __mj_isa_p1."MetricDirection",
    __mj_isa_p1."RollupWeight",
    __mj_isa_p1."PlanningPeriod",
    __mj_isa_p1."CheckInCadence",
    __mj_isa_p1."LastCheckInAt",
    __mj_isa_p1."NextCheckInDueAt",
    "mjBizAppsTasksGitHubGitHubRepository_RepositoryID"."Name" AS "Repository",
    "mjBizAppsTasksTask_LinkedIssueTaskID"."Name" AS "LinkedIssueTask"
FROM
    __mj_BizAppsTasksGitHub."GitHubPullRequestTask" AS g
INNER JOIN
    __mj_BizAppsTasks."Task" AS __mj_isa_p1
  ON
    g."ID" = __mj_isa_p1."ID"
LEFT OUTER JOIN
    __mj_BizAppsTasksGitHub."GitHubRepository" AS "mjBizAppsTasksGitHubGitHubRepository_RepositoryID"
  ON
    g."RepositoryID" = "mjBizAppsTasksGitHubGitHubRepository_RepositoryID"."ID"
LEFT OUTER JOIN
    __mj_BizAppsTasks."Task" AS "mjBizAppsTasksTask_LinkedIssueTaskID"
  ON
    g."LinkedIssueTaskID" = "mjBizAppsTasksTask_LinkedIssueTaskID"."ID"$vsql$;
  v_target_oid OID;
  v_dep RECORD;
  v_captured JSONB[] := ARRAY[]::JSONB[];
  v_n INTEGER;
BEGIN
  EXECUTE vsql;
EXCEPTION WHEN invalid_table_definition THEN
  -- Column list changed; need CASCADE. Preserve dependent views first.
  SELECT c.oid INTO v_target_oid
  FROM pg_class c JOIN pg_namespace n ON c.relnamespace = n.oid
  WHERE n.nspname = v_target_schema AND c.relname = v_target_name AND c.relkind = 'v';
  IF v_target_oid IS NOT NULL THEN
    FOR v_dep IN
      WITH RECURSIVE deps AS (
        SELECT c.oid, c.relname AS name, n.nspname AS schema, 1 AS depth
        FROM pg_rewrite r
        JOIN pg_depend d ON d.objid = r.oid
        JOIN pg_class c ON c.oid = r.ev_class
        JOIN pg_namespace n ON c.relnamespace = n.oid
        WHERE d.refobjid = v_target_oid AND d.deptype = 'n'
          AND c.oid <> v_target_oid AND c.relkind = 'v'
        UNION
        SELECT c.oid, c.relname, n.nspname, p.depth + 1
        FROM deps p
        JOIN pg_rewrite r ON TRUE
        JOIN pg_depend d ON d.objid = r.oid AND d.refobjid = p.oid
        JOIN pg_class c ON c.oid = r.ev_class
        JOIN pg_namespace n ON c.relnamespace = n.oid
        WHERE c.relkind = 'v' AND c.oid <> p.oid
      )
      SELECT oid, name, schema, MAX(depth) AS max_depth,
             pg_catalog.pg_get_viewdef(oid, true) AS viewdef
      FROM deps GROUP BY oid, name, schema
      ORDER BY MAX(depth) ASC
    LOOP
      v_captured := v_captured || jsonb_build_object(
        'schema', v_dep.schema, 'name', v_dep.name, 'def', v_dep.viewdef);
    END LOOP;
  END IF;
  EXECUTE format('DROP VIEW IF EXISTS %I.%I CASCADE', v_target_schema, v_target_name);
  EXECUTE vsql;
  IF v_captured IS NOT NULL AND array_length(v_captured, 1) > 0 THEN
    FOR v_n IN 1..array_length(v_captured, 1) LOOP
      BEGIN
        EXECUTE format('CREATE VIEW %I.%I AS %s',
          v_captured[v_n]->>'schema', v_captured[v_n]->>'name', v_captured[v_n]->>'def');
      EXCEPTION WHEN others THEN
        RAISE WARNING 'Could not restore dependent view %.%: %',
          v_captured[v_n]->>'schema', v_captured[v_n]->>'name', SQLERRM;
      END;
    END LOOP;
  END IF;
END;
$do$;

DROP VIEW IF EXISTS __mj_BizAppsTasksGitHub."vwGitHubIssueTasks" CASCADE;
DO $do$
DECLARE
  v_target_schema CONSTANT TEXT := '__mj_BizAppsTasksGitHub';
  v_target_name CONSTANT TEXT := 'vwGitHubIssueTasks';
  vsql CONSTANT TEXT := $vsql$CREATE OR REPLACE VIEW __mj_BizAppsTasksGitHub."vwGitHubIssueTasks"
AS SELECT
    g.*,
    __mj_isa_p1."Name",
    __mj_isa_p1."Description",
    __mj_isa_p1."TypeID",
    __mj_isa_p1."CategoryID",
    __mj_isa_p1."ParentID",
    __mj_isa_p1."Status",
    __mj_isa_p1."Priority",
    __mj_isa_p1."StartedAt",
    __mj_isa_p1."DueAt",
    __mj_isa_p1."CompletedAt",
    __mj_isa_p1."HoursEstimated",
    __mj_isa_p1."HoursActual",
    __mj_isa_p1."PercentComplete",
    __mj_isa_p1."Sequence",
    __mj_isa_p1."BlockedReason",
    __mj_isa_p1."CompletionNotes",
    __mj_isa_p1."CreatedByPersonID",
    __mj_isa_p1."OverdueNotifiedAt",
    __mj_isa_p1."TaskTypeStatusID",
    __mj_isa_p1."PredictedSLABreachProbability",
    __mj_isa_p1."PredictedSLARiskBand",
    __mj_isa_p1."PredictedSLAScoredAt",
    __mj_isa_p1."HealthStatus",
    __mj_isa_p1."ConfidenceScore",
    __mj_isa_p1."BaselineValue",
    __mj_isa_p1."TargetValue",
    __mj_isa_p1."CurrentValue",
    __mj_isa_p1."UnitOfMeasure",
    __mj_isa_p1."MetricDirection",
    __mj_isa_p1."RollupWeight",
    __mj_isa_p1."PlanningPeriod",
    __mj_isa_p1."CheckInCadence",
    __mj_isa_p1."LastCheckInAt",
    __mj_isa_p1."NextCheckInDueAt",
    "mjBizAppsTasksGitHubGitHubRepository_RepositoryID"."Name" AS "Repository"
FROM
    __mj_BizAppsTasksGitHub."GitHubIssueTask" AS g
INNER JOIN
    __mj_BizAppsTasks."Task" AS __mj_isa_p1
  ON
    g."ID" = __mj_isa_p1."ID"
LEFT OUTER JOIN
    __mj_BizAppsTasksGitHub."GitHubRepository" AS "mjBizAppsTasksGitHubGitHubRepository_RepositoryID"
  ON
    g."RepositoryID" = "mjBizAppsTasksGitHubGitHubRepository_RepositoryID"."ID"$vsql$;
  v_target_oid OID;
  v_dep RECORD;
  v_captured JSONB[] := ARRAY[]::JSONB[];
  v_n INTEGER;
BEGIN
  EXECUTE vsql;
EXCEPTION WHEN invalid_table_definition THEN
  -- Column list changed; need CASCADE. Preserve dependent views first.
  SELECT c.oid INTO v_target_oid
  FROM pg_class c JOIN pg_namespace n ON c.relnamespace = n.oid
  WHERE n.nspname = v_target_schema AND c.relname = v_target_name AND c.relkind = 'v';
  IF v_target_oid IS NOT NULL THEN
    FOR v_dep IN
      WITH RECURSIVE deps AS (
        SELECT c.oid, c.relname AS name, n.nspname AS schema, 1 AS depth
        FROM pg_rewrite r
        JOIN pg_depend d ON d.objid = r.oid
        JOIN pg_class c ON c.oid = r.ev_class
        JOIN pg_namespace n ON c.relnamespace = n.oid
        WHERE d.refobjid = v_target_oid AND d.deptype = 'n'
          AND c.oid <> v_target_oid AND c.relkind = 'v'
        UNION
        SELECT c.oid, c.relname, n.nspname, p.depth + 1
        FROM deps p
        JOIN pg_rewrite r ON TRUE
        JOIN pg_depend d ON d.objid = r.oid AND d.refobjid = p.oid
        JOIN pg_class c ON c.oid = r.ev_class
        JOIN pg_namespace n ON c.relnamespace = n.oid
        WHERE c.relkind = 'v' AND c.oid <> p.oid
      )
      SELECT oid, name, schema, MAX(depth) AS max_depth,
             pg_catalog.pg_get_viewdef(oid, true) AS viewdef
      FROM deps GROUP BY oid, name, schema
      ORDER BY MAX(depth) ASC
    LOOP
      v_captured := v_captured || jsonb_build_object(
        'schema', v_dep.schema, 'name', v_dep.name, 'def', v_dep.viewdef);
    END LOOP;
  END IF;
  EXECUTE format('DROP VIEW IF EXISTS %I.%I CASCADE', v_target_schema, v_target_name);
  EXECUTE vsql;
  IF v_captured IS NOT NULL AND array_length(v_captured, 1) > 0 THEN
    FOR v_n IN 1..array_length(v_captured, 1) LOOP
      BEGIN
        EXECUTE format('CREATE VIEW %I.%I AS %s',
          v_captured[v_n]->>'schema', v_captured[v_n]->>'name', v_captured[v_n]->>'def');
      EXCEPTION WHEN others THEN
        RAISE WARNING 'Could not restore dependent view %.%: %',
          v_captured[v_n]->>'schema', v_captured[v_n]->>'name', SQLERRM;
      END;
    END LOOP;
  END IF;
END;
$do$;


-- ===================== Stored Procedures (sp*) =====================

-- SKIPPED: procedure (auto-conversion not supported)
-- CREATE PROCEDURE [__mj_BizAppsTasksGitHub].[spCreateGitHubIdentity]
--     @ID UUID = NULL,
--     @GitHubLogin VARCHAR(100),
--     @PersonID UUID,
--     @GitHubUserID_Clear bit = 0,
--   ...

-- SKIPPED: procedure (auto-conversion not supported)
-- CREATE PROCEDURE [__mj_BizAppsTasksGitHub].[spUpdateGitHubIdentity]
--     @ID UUID,
--     @GitHubLogin VARCHAR(100) = NULL,
--     @PersonID UUID = NULL,
--     @GitHubUserID_Clear bit ...

-- SKIPPED: procedure (auto-conversion not supported)
-- CREATE PROCEDURE [__mj_BizAppsTasksGitHub].[spDeleteGitHubIdentity]
--     @ID UUID
-- AS
-- BEGIN
--     SET NOCOUNT ON;
-- 
--     DELETE FROM
--         [__mj_BizAppsTasksGitHub].[GitHubIdentity]
--     WHERE
-- ...

-- SKIPPED: procedure (auto-conversion not supported)
-- CREATE PROCEDURE [__mj_BizAppsTasksGitHub].[spCreateGitHubIssueTask]
--     @ID UUID = NULL,
--     @RepositoryID_Clear bit = 0,
--     @RepositoryID UUID = NULL,
--     @Number_Clear bit ...

-- SKIPPED: procedure (auto-conversion not supported)
-- CREATE PROCEDURE [__mj_BizAppsTasksGitHub].[spUpdateGitHubIssueTask]
--     @ID UUID,
--     @RepositoryID_Clear bit = 0,
--     @RepositoryID UUID = NULL,
--     @Number_Clear bit = 0,
--   ...

-- SKIPPED: procedure (auto-conversion not supported)
-- CREATE PROCEDURE [__mj_BizAppsTasksGitHub].[spDeleteGitHubIssueTask]
--     @ID UUID
-- AS
-- BEGIN
--     SET NOCOUNT ON;
-- 
--     DELETE FROM
--         [__mj_BizAppsTasksGitHub].[GitHubIssueTask]
--     WHER...

-- SKIPPED: procedure (auto-conversion not supported)
-- CREATE PROCEDURE [__mj_BizAppsTasksGitHub].[spCreateGitHubRepository]
--     @ID UUID = NULL,
--     @Owner VARCHAR(150),
--     @Name VARCHAR(200),
--     @DefaultBranch VARCHAR(120) = NULL,
--     @...

-- SKIPPED: procedure (auto-conversion not supported)
-- CREATE PROCEDURE [__mj_BizAppsTasksGitHub].[spUpdateGitHubRepository]
--     @ID UUID,
--     @Owner VARCHAR(150) = NULL,
--     @Name VARCHAR(200) = NULL,
--     @DefaultBranch VARCHAR(120) = NULL...

-- SKIPPED: procedure (auto-conversion not supported)
-- CREATE PROCEDURE [__mj_BizAppsTasksGitHub].[spDeleteGitHubRepository]
--     @ID UUID
-- AS
-- BEGIN
--     SET NOCOUNT ON;
-- 
--     DELETE FROM
--         [__mj_BizAppsTasksGitHub].[GitHubRepository]
--     WH...

-- SKIPPED: procedure (auto-conversion not supported)
-- CREATE PROCEDURE [__mj_BizAppsTasksGitHub].[spCreateGitHubPullRequestTask]
--     @ID UUID = NULL,
--     @RepositoryID_Clear bit = 0,
--     @RepositoryID UUID = NULL,
--     @Number_Clea...

-- SKIPPED: procedure (auto-conversion not supported)
-- CREATE PROCEDURE [__mj_BizAppsTasksGitHub].[spUpdateGitHubPullRequestTask]
--     @ID UUID,
--     @RepositoryID_Clear bit = 0,
--     @RepositoryID UUID = NULL,
--     @Number_Clear bit =...

-- SKIPPED: procedure (auto-conversion not supported)
-- CREATE PROCEDURE [__mj_BizAppsTasksGitHub].[spDeleteGitHubPullRequestTask]
--     @ID UUID
-- AS
-- BEGIN
--     SET NOCOUNT ON;
-- 
--     DELETE FROM
--         [__mj_BizAppsTasksGitHub].[GitHubPullRequestTa...

-- SKIPPED: procedure (auto-conversion not supported)
-- CREATE PROCEDURE [__mj_BizAppsTasksGitHub].[spCreateGitHubPullRequestTask]
--     @ID UUID = NULL,
--     @RepositoryID_Clear bit = 0,
--     @RepositoryID UUID = NULL,
--     @Number_Clea...

-- SKIPPED: procedure (auto-conversion not supported)
-- CREATE PROCEDURE [__mj_BizAppsTasksGitHub].[spUpdateGitHubPullRequestTask]
--     @ID UUID,
--     @RepositoryID_Clear bit = 0,
--     @RepositoryID UUID = NULL,
--     @Number_Clear bit =...

-- SKIPPED: procedure (auto-conversion not supported)
-- CREATE PROCEDURE [__mj_BizAppsTasksGitHub].[spDeleteGitHubPullRequestTask]
--     @ID UUID
-- AS
-- BEGIN
--     SET NOCOUNT ON;
-- 
--     DELETE FROM
--         [__mj_BizAppsTasksGitHub].[GitHubPullRequestTa...

-- SKIPPED: procedure (auto-conversion not supported)
-- CREATE PROCEDURE [__mj_BizAppsTasksGitHub].[spCreateGitHubIssueTask]
--     @ID UUID = NULL,
--     @RepositoryID_Clear bit = 0,
--     @RepositoryID UUID = NULL,
--     @Number_Clear bit ...

-- SKIPPED: procedure (auto-conversion not supported)
-- CREATE PROCEDURE [__mj_BizAppsTasksGitHub].[spUpdateGitHubIssueTask]
--     @ID UUID,
--     @RepositoryID_Clear bit = 0,
--     @RepositoryID UUID = NULL,
--     @Number_Clear bit = 0,
--   ...

-- SKIPPED: procedure (auto-conversion not supported)
-- CREATE PROCEDURE [__mj_BizAppsTasksGitHub].[spDeleteGitHubIssueTask]
--     @ID UUID
-- AS
-- BEGIN
--     SET NOCOUNT ON;
-- 
--     DELETE FROM
--         [__mj_BizAppsTasksGitHub].[GitHubIssueTask]
--     WHER...


-- ===================== Triggers =====================

-- SKIPPED: trigger (auto-conversion not supported)
-- CREATE TRIGGER [__mj_BizAppsTasksGitHub].trgUpdateGitHubIdentity
-- ON __mj_BizAppsTasksGitHub."GitHubIdentity"
-- AFTER UPDATE
-- AS
-- BEGIN
--     SET NOCOUNT ON;
--     UPDATE
--         __mj_BizAppsTasksGitHub."G

-- SKIPPED: trigger (auto-conversion not supported)
-- CREATE TRIGGER [__mj_BizAppsTasksGitHub".trgUpdateGitHubIssueTask
-- ON __mj_BizAppsTasksGitHub."GitHubIssueTask"
-- AFTER UPDATE
-- AS
-- BEGIN
--     SET NOCOUNT ON;
--     UPDATE
--         __mj_BizAppsTasksGitHub.

-- SKIPPED: trigger (auto-conversion not supported)
-- CREATE TRIGGER [__mj_BizAppsTasksGitHub].trgUpdateGitHubRepository
-- ON __mj_BizAppsTasksGitHub."GitHubRepository"
-- AFTER UPDATE
-- AS
-- BEGIN
--     SET NOCOUNT ON;
--     UPDATE
--         "__mj_BizAppsTasksGitHub

-- SKIPPED: trigger (auto-conversion not supported)
-- CREATE TRIGGER [__mj_BizAppsTasksGitHub".trgUpdateGitHubPullRequestTask
-- ON __mj_BizAppsTasksGitHub."GitHubPullRequestTask"
-- AFTER UPDATE
-- AS
-- BEGIN
--     SET NOCOUNT ON;
--     UPDATE
--         "__mj_BizAppsT

-- SKIPPED: trigger (auto-conversion not supported)
-- CREATE TRIGGER [__mj_BizAppsTasksGitHub".trgUpdateGitHubPullRequestTask
-- ON __mj_BizAppsTasksGitHub."GitHubPullRequestTask"
-- AFTER UPDATE
-- AS
-- BEGIN
--     SET NOCOUNT ON;
--     UPDATE
--         "__mj_BizAppsT

-- SKIPPED: trigger (auto-conversion not supported)
-- CREATE TRIGGER [__mj_BizAppsTasksGitHub".trgUpdateGitHubIssueTask
-- ON __mj_BizAppsTasksGitHub."GitHubIssueTask"
-- AFTER UPDATE
-- AS
-- BEGIN
--     SET NOCOUNT ON;
--     UPDATE
--         __mj_BizAppsTasksGitHub.


-- ===================== Data (INSERT/UPDATE/DELETE) =====================

INSERT INTO ${mjSchema}."Entity" (
         "ID",
         "Name",
         "DisplayName",
         "Description",
         "NameSuffix",
         "BaseTable",
         "BaseView",
         "SchemaName",
         "IncludeInAPI",
         "AllowUserSearchAPI",
         "AllowCaching",
         "TrackRecordChanges",
         "AuditRecordAccess",
         "AuditViewRuns",
         "AllowAllRowsAPI",
         "AllowCreateAPI",
         "AllowUpdateAPI",
         "AllowDeleteAPI",
         "UserViewMaxRows"
         , "__mj_CreatedAt"
         , "__mj_UpdatedAt"
      )
      VALUES (
         '6b363236-31ab-477d-8188-08f5fa9942ef',
         'MJ_BizApps_Tasks_GitHub: Git Hub Repositories',
         'Git Hub Repositories',
         'GitHub repositories connected to BizApps Tasks, storing tracking controls, import filtering rules (AssignedOnly vs All), GitHub App installation IDs, client organization link, and optional Software Factory delivery policy reference.',
         NULL,
         'GitHubRepository',
         'vwGitHubRepositories',
         '__mj_BizAppsTasksGitHub',
         TRUE,
         TRUE,
         FALSE,
         TRUE,
         FALSE,
         FALSE,
         FALSE,
         TRUE,
         TRUE,
         TRUE,
         1000
         , NOW()
         , NOW()
      );

/* SQL generated to create new application __mj_BizAppsTasksGitHub */

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM ${mjSchema}."Application" WHERE "ID" = '3fdb3d32-6722-4638-98b5-20185684874e'
    ) THEN
        INSERT INTO ${mjSchema}."Application" ("ID", "Name", "Description", "SchemaAutoAddNewEntities", "Path", "AutoUpdatePath", "DefaultForNewUser")
        VALUES ('3fdb3d32-6722-4638-98b5-20185684874e', '__mj_BizAppsTasksGitHub', 'Generated for schema', '__mj_BizAppsTasksGitHub', 'mjbizappstasksgithub', TRUE, FALSE);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM ${mjSchema}."ApplicationRole" WHERE "ApplicationID" = '3fdb3d32-6722-4638-98b5-20185684874e' AND "RoleID" = 'E0AFCCEC-6A37-EF11-86D4-000D3A4E707E'
    ) THEN
        INSERT INTO ${mjSchema}."ApplicationRole"
        ("ApplicationID", "RoleID", "CanAccess", "CanAdmin") VALUES
        ('3fdb3d32-6722-4638-98b5-20185684874e', 'E0AFCCEC-6A37-EF11-86D4-000D3A4E707E', TRUE, FALSE);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM ${mjSchema}."ApplicationRole" WHERE "ApplicationID" = '3fdb3d32-6722-4638-98b5-20185684874e' AND "RoleID" = 'DEAFCCEC-6A37-EF11-86D4-000D3A4E707E'
    ) THEN
        INSERT INTO ${mjSchema}."ApplicationRole"
        ("ApplicationID", "RoleID", "CanAccess", "CanAdmin") VALUES
        ('3fdb3d32-6722-4638-98b5-20185684874e', 'DEAFCCEC-6A37-EF11-86D4-000D3A4E707E', TRUE, TRUE);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM ${mjSchema}."ApplicationRole" WHERE "ApplicationID" = '3fdb3d32-6722-4638-98b5-20185684874e' AND "RoleID" = 'DFAFCCEC-6A37-EF11-86D4-000D3A4E707E'
    ) THEN
        INSERT INTO ${mjSchema}."ApplicationRole"
        ("ApplicationID", "RoleID", "CanAccess", "CanAdmin") VALUES
        ('3fdb3d32-6722-4638-98b5-20185684874e', 'DFAFCCEC-6A37-EF11-86D4-000D3A4E707E', TRUE, FALSE);
    END IF;
END $$;

INSERT INTO ${mjSchema}."ApplicationEntity"
                                    ("ApplicationID", "EntityID", "Sequence", "__mj_CreatedAt", "__mj_UpdatedAt") VALUES
                                    ('3fdb3d32-6722-4638-98b5-20185684874e', '6b363236-31ab-477d-8188-08f5fa9942ef', (SELECT COALESCE(MAX("Sequence"),0)+1 FROM ${mjSchema}."ApplicationEntity" WHERE "ApplicationID" = '3fdb3d32-6722-4638-98b5-20185684874e'), NOW(), NOW());

/* SQL generated to add new permission for entity MJ_BizApps_Tasks_GitHub: Git Hub Repositories for role UI */

INSERT INTO ${mjSchema}."EntityPermission"
                ("EntityID", "RoleID", "Type", "CanRead", "CanCreate", "CanUpdate", "CanDelete", "__mj_CreatedAt", "__mj_UpdatedAt")
              SELECT CAST('6b363236-31ab-477d-8188-08f5fa9942ef' AS UUID), CAST('E0AFCCEC-6A37-EF11-86D4-000D3A4E707E' AS UUID), 'Allow', 1, 0, 0, 0, NOW(), NOW()
              WHERE NOT EXISTS (
                SELECT 1 FROM ${mjSchema}."EntityPermission"
                WHERE "EntityID" = CAST('6b363236-31ab-477d-8188-08f5fa9942ef' AS UUID) AND "RoleID" = CAST('E0AFCCEC-6A37-EF11-86D4-000D3A4E707E' AS UUID) AND "Type" = 'Allow'
              );

/* SQL generated to add new permission for entity MJ_BizApps_Tasks_GitHub: Git Hub Repositories for role Developer */

INSERT INTO ${mjSchema}."EntityPermission"
                ("EntityID", "RoleID", "Type", "CanRead", "CanCreate", "CanUpdate", "CanDelete", "__mj_CreatedAt", "__mj_UpdatedAt")
              SELECT CAST('6b363236-31ab-477d-8188-08f5fa9942ef' AS UUID), CAST('DEAFCCEC-6A37-EF11-86D4-000D3A4E707E' AS UUID), 'Allow', 1, 1, 1, 1, NOW(), NOW()
              WHERE NOT EXISTS (
                SELECT 1 FROM ${mjSchema}."EntityPermission"
                WHERE "EntityID" = CAST('6b363236-31ab-477d-8188-08f5fa9942ef' AS UUID) AND "RoleID" = CAST('DEAFCCEC-6A37-EF11-86D4-000D3A4E707E' AS UUID) AND "Type" = 'Allow'
              );

/* SQL generated to add new permission for entity MJ_BizApps_Tasks_GitHub: Git Hub Repositories for role Integration */

INSERT INTO ${mjSchema}."EntityPermission"
                ("EntityID", "RoleID", "Type", "CanRead", "CanCreate", "CanUpdate", "CanDelete", "__mj_CreatedAt", "__mj_UpdatedAt")
              SELECT CAST('6b363236-31ab-477d-8188-08f5fa9942ef' AS UUID), CAST('DFAFCCEC-6A37-EF11-86D4-000D3A4E707E' AS UUID), 'Allow', 1, 1, 1, 1, NOW(), NOW()
              WHERE NOT EXISTS (
                SELECT 1 FROM ${mjSchema}."EntityPermission"
                WHERE "EntityID" = CAST('6b363236-31ab-477d-8188-08f5fa9942ef' AS UUID) AND "RoleID" = CAST('DFAFCCEC-6A37-EF11-86D4-000D3A4E707E' AS UUID) AND "Type" = 'Allow'
              );

/* SQL generated to create new entity MJ_BizApps_Tasks_GitHub: Git Hub Identities */

INSERT INTO ${mjSchema}."Entity" (
         "ID",
         "Name",
         "DisplayName",
         "Description",
         "NameSuffix",
         "BaseTable",
         "BaseView",
         "SchemaName",
         "IncludeInAPI",
         "AllowUserSearchAPI",
         "AllowCaching",
         "TrackRecordChanges",
         "AuditRecordAccess",
         "AuditViewRuns",
         "AllowAllRowsAPI",
         "AllowCreateAPI",
         "AllowUpdateAPI",
         "AllowDeleteAPI",
         "UserViewMaxRows"
         , "__mj_CreatedAt"
         , "__mj_UpdatedAt"
      )
      VALUES (
         'c7cc2bcf-090e-4832-89c7-a051f302c393',
         'MJ_BizApps_Tasks_GitHub: Git Hub Identities',
         'Git Hub Identities',
         'Maps GitHub user logins to BizApps Common Person records so GitHub issue/PR assignees and requested reviewers synchronize into Primary and Reviewer TaskAssignment rows.',
         NULL,
         'GitHubIdentity',
         'vwGitHubIdentities',
         '__mj_BizAppsTasksGitHub',
         TRUE,
         TRUE,
         FALSE,
         TRUE,
         FALSE,
         FALSE,
         FALSE,
         TRUE,
         TRUE,
         TRUE,
         1000
         , NOW()
         , NOW()
      );

/* SQL generated to add entity MJ_BizApps_Tasks_GitHub: Git Hub Identities to application ID: '3FDB3D32-6722-4638-98B5-20185684874E' */

INSERT INTO ${mjSchema}."ApplicationEntity"
                                    ("ApplicationID", "EntityID", "Sequence", "__mj_CreatedAt", "__mj_UpdatedAt") VALUES
                                    ('3FDB3D32-6722-4638-98B5-20185684874E', 'c7cc2bcf-090e-4832-89c7-a051f302c393', (SELECT COALESCE(MAX("Sequence"),0)+1 FROM ${mjSchema}."ApplicationEntity" WHERE "ApplicationID" = '3FDB3D32-6722-4638-98B5-20185684874E'), NOW(), NOW());

/* SQL generated to add new permission for entity MJ_BizApps_Tasks_GitHub: Git Hub Identities for role UI */

INSERT INTO ${mjSchema}."EntityPermission"
                ("EntityID", "RoleID", "Type", "CanRead", "CanCreate", "CanUpdate", "CanDelete", "__mj_CreatedAt", "__mj_UpdatedAt")
              SELECT CAST('c7cc2bcf-090e-4832-89c7-a051f302c393' AS UUID), CAST('E0AFCCEC-6A37-EF11-86D4-000D3A4E707E' AS UUID), 'Allow', 1, 0, 0, 0, NOW(), NOW()
              WHERE NOT EXISTS (
                SELECT 1 FROM ${mjSchema}."EntityPermission"
                WHERE "EntityID" = CAST('c7cc2bcf-090e-4832-89c7-a051f302c393' AS UUID) AND "RoleID" = CAST('E0AFCCEC-6A37-EF11-86D4-000D3A4E707E' AS UUID) AND "Type" = 'Allow'
              );

/* SQL generated to add new permission for entity MJ_BizApps_Tasks_GitHub: Git Hub Identities for role Developer */

INSERT INTO ${mjSchema}."EntityPermission"
                ("EntityID", "RoleID", "Type", "CanRead", "CanCreate", "CanUpdate", "CanDelete", "__mj_CreatedAt", "__mj_UpdatedAt")
              SELECT CAST('c7cc2bcf-090e-4832-89c7-a051f302c393' AS UUID), CAST('DEAFCCEC-6A37-EF11-86D4-000D3A4E707E' AS UUID), 'Allow', 1, 1, 1, 1, NOW(), NOW()
              WHERE NOT EXISTS (
                SELECT 1 FROM ${mjSchema}."EntityPermission"
                WHERE "EntityID" = CAST('c7cc2bcf-090e-4832-89c7-a051f302c393' AS UUID) AND "RoleID" = CAST('DEAFCCEC-6A37-EF11-86D4-000D3A4E707E' AS UUID) AND "Type" = 'Allow'
              );

/* SQL generated to add new permission for entity MJ_BizApps_Tasks_GitHub: Git Hub Identities for role Integration */

INSERT INTO ${mjSchema}."EntityPermission"
                ("EntityID", "RoleID", "Type", "CanRead", "CanCreate", "CanUpdate", "CanDelete", "__mj_CreatedAt", "__mj_UpdatedAt")
              SELECT CAST('c7cc2bcf-090e-4832-89c7-a051f302c393' AS UUID), CAST('DFAFCCEC-6A37-EF11-86D4-000D3A4E707E' AS UUID), 'Allow', 1, 1, 1, 1, NOW(), NOW()
              WHERE NOT EXISTS (
                SELECT 1 FROM ${mjSchema}."EntityPermission"
                WHERE "EntityID" = CAST('c7cc2bcf-090e-4832-89c7-a051f302c393' AS UUID) AND "RoleID" = CAST('DFAFCCEC-6A37-EF11-86D4-000D3A4E707E' AS UUID) AND "Type" = 'Allow'
              );

/* SQL generated to create new entity MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks */

INSERT INTO ${mjSchema}."Entity" (
         "ID",
         "Name",
         "DisplayName",
         "Description",
         "NameSuffix",
         "BaseTable",
         "BaseView",
         "SchemaName",
         "IncludeInAPI",
         "AllowUserSearchAPI",
         "AllowCaching",
         "TrackRecordChanges",
         "AuditRecordAccess",
         "AuditViewRuns",
         "AllowAllRowsAPI",
         "AllowCreateAPI",
         "AllowUpdateAPI",
         "AllowDeleteAPI",
         "UserViewMaxRows"
         , "__mj_CreatedAt"
         , "__mj_UpdatedAt"
      )
      VALUES (
         'dc8e0f5b-e172-4fd5-b648-8b4544f8c605',
         'MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks',
         'Git Hub Issue Tasks',
         'Disjoint IS-A child of MJ_BizApps_Tasks: Tasks for GITHUB_ISSUE tasks, storing GitHub-owned issue metadata, milestone dates, and idempotent external sync keys.',
         NULL,
         'GitHubIssueTask',
         'vwGitHubIssueTasks',
         '__mj_BizAppsTasksGitHub',
         TRUE,
         TRUE,
         FALSE,
         TRUE,
         FALSE,
         FALSE,
         FALSE,
         TRUE,
         TRUE,
         TRUE,
         1000
         , NOW()
         , NOW()
      );

/* SQL generated to add entity MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks to application ID: '3FDB3D32-6722-4638-98B5-20185684874E' */

INSERT INTO ${mjSchema}."ApplicationEntity"
                                    ("ApplicationID", "EntityID", "Sequence", "__mj_CreatedAt", "__mj_UpdatedAt") VALUES
                                    ('3FDB3D32-6722-4638-98B5-20185684874E', 'dc8e0f5b-e172-4fd5-b648-8b4544f8c605', (SELECT COALESCE(MAX("Sequence"),0)+1 FROM ${mjSchema}."ApplicationEntity" WHERE "ApplicationID" = '3FDB3D32-6722-4638-98B5-20185684874E'), NOW(), NOW());

/* SQL generated to add new permission for entity MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks for role UI */

INSERT INTO ${mjSchema}."EntityPermission"
                ("EntityID", "RoleID", "Type", "CanRead", "CanCreate", "CanUpdate", "CanDelete", "__mj_CreatedAt", "__mj_UpdatedAt")
              SELECT CAST('dc8e0f5b-e172-4fd5-b648-8b4544f8c605' AS UUID), CAST('E0AFCCEC-6A37-EF11-86D4-000D3A4E707E' AS UUID), 'Allow', 1, 0, 0, 0, NOW(), NOW()
              WHERE NOT EXISTS (
                SELECT 1 FROM ${mjSchema}."EntityPermission"
                WHERE "EntityID" = CAST('dc8e0f5b-e172-4fd5-b648-8b4544f8c605' AS UUID) AND "RoleID" = CAST('E0AFCCEC-6A37-EF11-86D4-000D3A4E707E' AS UUID) AND "Type" = 'Allow'
              );

/* SQL generated to add new permission for entity MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks for role Developer */

INSERT INTO ${mjSchema}."EntityPermission"
                ("EntityID", "RoleID", "Type", "CanRead", "CanCreate", "CanUpdate", "CanDelete", "__mj_CreatedAt", "__mj_UpdatedAt")
              SELECT CAST('dc8e0f5b-e172-4fd5-b648-8b4544f8c605' AS UUID), CAST('DEAFCCEC-6A37-EF11-86D4-000D3A4E707E' AS UUID), 'Allow', 1, 1, 1, 1, NOW(), NOW()
              WHERE NOT EXISTS (
                SELECT 1 FROM ${mjSchema}."EntityPermission"
                WHERE "EntityID" = CAST('dc8e0f5b-e172-4fd5-b648-8b4544f8c605' AS UUID) AND "RoleID" = CAST('DEAFCCEC-6A37-EF11-86D4-000D3A4E707E' AS UUID) AND "Type" = 'Allow'
              );

/* SQL generated to add new permission for entity MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks for role Integration */

INSERT INTO ${mjSchema}."EntityPermission"
                ("EntityID", "RoleID", "Type", "CanRead", "CanCreate", "CanUpdate", "CanDelete", "__mj_CreatedAt", "__mj_UpdatedAt")
              SELECT CAST('dc8e0f5b-e172-4fd5-b648-8b4544f8c605' AS UUID), CAST('DFAFCCEC-6A37-EF11-86D4-000D3A4E707E' AS UUID), 'Allow', 1, 1, 1, 1, NOW(), NOW()
              WHERE NOT EXISTS (
                SELECT 1 FROM ${mjSchema}."EntityPermission"
                WHERE "EntityID" = CAST('dc8e0f5b-e172-4fd5-b648-8b4544f8c605' AS UUID) AND "RoleID" = CAST('DFAFCCEC-6A37-EF11-86D4-000D3A4E707E' AS UUID) AND "Type" = 'Allow'
              );

/* SQL generated to create new entity MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks */

INSERT INTO ${mjSchema}."Entity" (
         "ID",
         "Name",
         "DisplayName",
         "Description",
         "NameSuffix",
         "BaseTable",
         "BaseView",
         "SchemaName",
         "IncludeInAPI",
         "AllowUserSearchAPI",
         "AllowCaching",
         "TrackRecordChanges",
         "AuditRecordAccess",
         "AuditViewRuns",
         "AllowAllRowsAPI",
         "AllowCreateAPI",
         "AllowUpdateAPI",
         "AllowDeleteAPI",
         "UserViewMaxRows"
         , "__mj_CreatedAt"
         , "__mj_UpdatedAt"
      )
      VALUES (
         'a6b673f8-43bc-4875-aff6-ac620592822e',
         'MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks',
         'Git Hub Pull Request Tasks',
         'Disjoint IS-A child of MJ_BizApps_Tasks: Tasks for GITHUB_PR tasks, storing pull request branches, head SHA, review decision, CI checks status, diff metrics, and linked issue Task.',
         NULL,
         'GitHubPullRequestTask',
         'vwGitHubPullRequestTasks',
         '__mj_BizAppsTasksGitHub',
         TRUE,
         TRUE,
         FALSE,
         TRUE,
         FALSE,
         FALSE,
         FALSE,
         TRUE,
         TRUE,
         TRUE,
         1000
         , NOW()
         , NOW()
      );

/* SQL generated to add entity MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks to application ID: '3FDB3D32-6722-4638-98B5-20185684874E' */

INSERT INTO ${mjSchema}."ApplicationEntity"
                                    ("ApplicationID", "EntityID", "Sequence", "__mj_CreatedAt", "__mj_UpdatedAt") VALUES
                                    ('3FDB3D32-6722-4638-98B5-20185684874E', 'a6b673f8-43bc-4875-aff6-ac620592822e', (SELECT COALESCE(MAX("Sequence"),0)+1 FROM ${mjSchema}."ApplicationEntity" WHERE "ApplicationID" = '3FDB3D32-6722-4638-98B5-20185684874E'), NOW(), NOW());

/* SQL generated to add new permission for entity MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks for role UI */

INSERT INTO ${mjSchema}."EntityPermission"
                ("EntityID", "RoleID", "Type", "CanRead", "CanCreate", "CanUpdate", "CanDelete", "__mj_CreatedAt", "__mj_UpdatedAt")
              SELECT CAST('a6b673f8-43bc-4875-aff6-ac620592822e' AS UUID), CAST('E0AFCCEC-6A37-EF11-86D4-000D3A4E707E' AS UUID), 'Allow', 1, 0, 0, 0, NOW(), NOW()
              WHERE NOT EXISTS (
                SELECT 1 FROM ${mjSchema}."EntityPermission"
                WHERE "EntityID" = CAST('a6b673f8-43bc-4875-aff6-ac620592822e' AS UUID) AND "RoleID" = CAST('E0AFCCEC-6A37-EF11-86D4-000D3A4E707E' AS UUID) AND "Type" = 'Allow'
              );

/* SQL generated to add new permission for entity MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks for role Developer */

INSERT INTO ${mjSchema}."EntityPermission"
                ("EntityID", "RoleID", "Type", "CanRead", "CanCreate", "CanUpdate", "CanDelete", "__mj_CreatedAt", "__mj_UpdatedAt")
              SELECT CAST('a6b673f8-43bc-4875-aff6-ac620592822e' AS UUID), CAST('DEAFCCEC-6A37-EF11-86D4-000D3A4E707E' AS UUID), 'Allow', 1, 1, 1, 1, NOW(), NOW()
              WHERE NOT EXISTS (
                SELECT 1 FROM ${mjSchema}."EntityPermission"
                WHERE "EntityID" = CAST('a6b673f8-43bc-4875-aff6-ac620592822e' AS UUID) AND "RoleID" = CAST('DEAFCCEC-6A37-EF11-86D4-000D3A4E707E' AS UUID) AND "Type" = 'Allow'
              );

/* SQL generated to add new permission for entity MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks for role Integration */

INSERT INTO ${mjSchema}."EntityPermission"
                ("EntityID", "RoleID", "Type", "CanRead", "CanCreate", "CanUpdate", "CanDelete", "__mj_CreatedAt", "__mj_UpdatedAt")
              SELECT CAST('a6b673f8-43bc-4875-aff6-ac620592822e' AS UUID), CAST('DFAFCCEC-6A37-EF11-86D4-000D3A4E707E' AS UUID), 'Allow', 1, 1, 1, 1, NOW(), NOW()
              WHERE NOT EXISTS (
                SELECT 1 FROM ${mjSchema}."EntityPermission"
                WHERE "EntityID" = CAST('a6b673f8-43bc-4875-aff6-ac620592822e' AS UUID) AND "RoleID" = CAST('DFAFCCEC-6A37-EF11-86D4-000D3A4E707E' AS UUID) AND "Type" = 'Allow'
              );

/* SQL text to update existing entities from schema */

/* SQL text to add special date field __mj_CreatedAt to entity __mj_BizAppsTasksGitHub."GitHubRepository" */
UPDATE __mj_BizAppsTasksGitHub."GitHubRepository" SET "__mj_CreatedAt" = NOW() WHERE "__mj_CreatedAt" IS NULL;

/* SQL text to add special date field __mj_CreatedAt to entity __mj_BizAppsTasksGitHub.GitHubRepository */
ALTER TABLE __mj_BizAppsTasksGitHub."GitHubRepository" ALTER COLUMN "__mj_CreatedAt" SET NOT NULL;

ALTER TABLE __mj_BizAppsTasksGitHub."GitHubRepository"
  ALTER COLUMN "__mj_CreatedAt" SET DEFAULT NOW();

/* SQL text to add special date field __mj_UpdatedAt to entity __mj_BizAppsTasksGitHub."GitHubRepository" */
UPDATE __mj_BizAppsTasksGitHub."GitHubRepository" SET "__mj_UpdatedAt" = NOW() WHERE "__mj_UpdatedAt" IS NULL;

/* SQL text to add special date field __mj_UpdatedAt to entity __mj_BizAppsTasksGitHub.GitHubRepository */
ALTER TABLE __mj_BizAppsTasksGitHub."GitHubRepository" ALTER COLUMN "__mj_UpdatedAt" SET NOT NULL;

ALTER TABLE __mj_BizAppsTasksGitHub."GitHubRepository"
  ALTER COLUMN "__mj_UpdatedAt" SET DEFAULT NOW();

/* SQL text to add special date field __mj_CreatedAt to entity __mj_BizAppsTasksGitHub."GitHubIssueTask" */
UPDATE __mj_BizAppsTasksGitHub."GitHubIssueTask" SET "__mj_CreatedAt" = NOW() WHERE "__mj_CreatedAt" IS NULL;

/* SQL text to add special date field __mj_CreatedAt to entity __mj_BizAppsTasksGitHub.GitHubIssueTask */
ALTER TABLE __mj_BizAppsTasksGitHub."GitHubIssueTask" ALTER COLUMN "__mj_CreatedAt" SET NOT NULL;

ALTER TABLE __mj_BizAppsTasksGitHub."GitHubIssueTask"
  ALTER COLUMN "__mj_CreatedAt" SET DEFAULT NOW();

/* SQL text to add special date field __mj_UpdatedAt to entity __mj_BizAppsTasksGitHub."GitHubIssueTask" */
UPDATE __mj_BizAppsTasksGitHub."GitHubIssueTask" SET "__mj_UpdatedAt" = NOW() WHERE "__mj_UpdatedAt" IS NULL;

/* SQL text to add special date field __mj_UpdatedAt to entity __mj_BizAppsTasksGitHub.GitHubIssueTask */
ALTER TABLE __mj_BizAppsTasksGitHub."GitHubIssueTask" ALTER COLUMN "__mj_UpdatedAt" SET NOT NULL;

ALTER TABLE __mj_BizAppsTasksGitHub."GitHubIssueTask"
  ALTER COLUMN "__mj_UpdatedAt" SET DEFAULT NOW();

/* SQL text to add special date field __mj_CreatedAt to entity __mj_BizAppsTasksGitHub."GitHubIdentity" */
UPDATE __mj_BizAppsTasksGitHub."GitHubIdentity" SET "__mj_CreatedAt" = NOW() WHERE "__mj_CreatedAt" IS NULL;

/* SQL text to add special date field __mj_CreatedAt to entity __mj_BizAppsTasksGitHub.GitHubIdentity */
ALTER TABLE __mj_BizAppsTasksGitHub."GitHubIdentity" ALTER COLUMN "__mj_CreatedAt" SET NOT NULL;

ALTER TABLE __mj_BizAppsTasksGitHub."GitHubIdentity"
  ALTER COLUMN "__mj_CreatedAt" SET DEFAULT NOW();

/* SQL text to add special date field __mj_UpdatedAt to entity __mj_BizAppsTasksGitHub."GitHubIdentity" */
UPDATE __mj_BizAppsTasksGitHub."GitHubIdentity" SET "__mj_UpdatedAt" = NOW() WHERE "__mj_UpdatedAt" IS NULL;

/* SQL text to add special date field __mj_UpdatedAt to entity __mj_BizAppsTasksGitHub.GitHubIdentity */
ALTER TABLE __mj_BizAppsTasksGitHub."GitHubIdentity" ALTER COLUMN "__mj_UpdatedAt" SET NOT NULL;

ALTER TABLE __mj_BizAppsTasksGitHub."GitHubIdentity"
  ALTER COLUMN "__mj_UpdatedAt" SET DEFAULT NOW();

/* SQL text to add special date field __mj_CreatedAt to entity __mj_BizAppsTasksGitHub."GitHubPullRequestTask" */
UPDATE __mj_BizAppsTasksGitHub."GitHubPullRequestTask" SET "__mj_CreatedAt" = NOW() WHERE "__mj_CreatedAt" IS NULL;

/* SQL text to add special date field __mj_CreatedAt to entity __mj_BizAppsTasksGitHub.GitHubPullRequestTask */
ALTER TABLE __mj_BizAppsTasksGitHub."GitHubPullRequestTask" ALTER COLUMN "__mj_CreatedAt" SET NOT NULL;

ALTER TABLE __mj_BizAppsTasksGitHub."GitHubPullRequestTask"
  ALTER COLUMN "__mj_CreatedAt" SET DEFAULT NOW();

/* SQL text to add special date field __mj_UpdatedAt to entity __mj_BizAppsTasksGitHub."GitHubPullRequestTask" */
UPDATE __mj_BizAppsTasksGitHub."GitHubPullRequestTask" SET "__mj_UpdatedAt" = NOW() WHERE "__mj_UpdatedAt" IS NULL;

/* SQL text to add special date field __mj_UpdatedAt to entity __mj_BizAppsTasksGitHub.GitHubPullRequestTask */
ALTER TABLE __mj_BizAppsTasksGitHub."GitHubPullRequestTask" ALTER COLUMN "__mj_UpdatedAt" SET NOT NULL;

ALTER TABLE __mj_BizAppsTasksGitHub."GitHubPullRequestTask"
  ALTER COLUMN "__mj_UpdatedAt" SET DEFAULT NOW();

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM ${mjSchema}."EntityField" WHERE "ID" = 'd38e3c3f-3676-439b-9111-df4565789c9f' OR ("EntityID" = '6B363236-31AB-477D-8188-08F5FA9942EF' AND "Name" = 'ID')
    ) THEN
        INSERT INTO ${mjSchema}."EntityField"
        (
        "ID",
        "EntityID",
        "Sequence",
        "Name",
        "DisplayName",
        "Description",
        "Type",
        "Length",
        "Precision",
        "Scale",
        "AllowsNull",
        "DefaultValue",
        "AutoIncrement",
        "AllowUpdateAPI",
        "IsVirtual",
        "IsComputed",
        "RelatedEntityID",
        "RelatedEntityFieldName",
        "IsNameField",
        "IncludeInUserSearchAPI",
        "IncludeRelatedEntityNameFieldInBaseView",
        "DefaultInView",
        "IsPrimaryKey",
        "IsUnique",
        "RelatedEntityDisplayType",
        "__mj_CreatedAt",
        "__mj_UpdatedAt"
        )
        VALUES
        (
        'd38e3c3f-3676-439b-9111-df4565789c9f',
        '6B363236-31AB-477D-8188-08F5FA9942EF', -- "Entity": "MJ_BizApps_Tasks_GitHub": "Git" "Hub" "Repositories"
        (SELECT COALESCE(MAX("Sequence"), 0) + 1 FROM ${mjSchema}."EntityField" WHERE "EntityID" = '6B363236-31AB-477D-8188-08F5FA9942EF'),
        'ID',
        'ID',
        NULL,
        'UUID',
        16,
        0,
        0,
        FALSE,
        'gen_random_uuid()',
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        NULL,
        NULL,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        TRUE,
        TRUE,
        'Search',
        NOW(),
        NOW()
        );
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM ${mjSchema}."EntityField" WHERE "ID" = '16994c95-2791-47c6-b378-4af1eace655f' OR ("EntityID" = '6B363236-31AB-477D-8188-08F5FA9942EF' AND "Name" = 'Owner')
    ) THEN
        INSERT INTO ${mjSchema}."EntityField"
        (
        "ID",
        "EntityID",
        "Sequence",
        "Name",
        "DisplayName",
        "Description",
        "Type",
        "Length",
        "Precision",
        "Scale",
        "AllowsNull",
        "DefaultValue",
        "AutoIncrement",
        "AllowUpdateAPI",
        "IsVirtual",
        "IsComputed",
        "RelatedEntityID",
        "RelatedEntityFieldName",
        "IsNameField",
        "IncludeInUserSearchAPI",
        "IncludeRelatedEntityNameFieldInBaseView",
        "DefaultInView",
        "IsPrimaryKey",
        "IsUnique",
        "RelatedEntityDisplayType",
        "__mj_CreatedAt",
        "__mj_UpdatedAt"
        )
        VALUES
        (
        '16994c95-2791-47c6-b378-4af1eace655f',
        '6B363236-31AB-477D-8188-08F5FA9942EF', -- "Entity": "MJ_BizApps_Tasks_GitHub": "Git" "Hub" "Repositories"
        (SELECT COALESCE(MAX("Sequence"), 0) + 1 FROM ${mjSchema}."EntityField" WHERE "EntityID" = '6B363236-31AB-477D-8188-08F5FA9942EF'),
        'Owner',
        'Owner',
        'GitHub organization or user login that owns the repository (e.g. MemberJunction).',
        'TEXT',
        300,
        0,
        0,
        FALSE,
        NULL,
        FALSE,
        TRUE,
        FALSE,
        FALSE,
        NULL,
        NULL,
        FALSE,
        FALSE,
        FALSE,
        TRUE,
        FALSE,
        TRUE,
        'Search',
        NOW(),
        NOW()
        );
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM ${mjSchema}."EntityField" WHERE "ID" = '8cfc093f-2135-437e-93a8-493a64dfa174' OR ("EntityID" = '6B363236-31AB-477D-8188-08F5FA9942EF' AND "Name" = 'Name')
    ) THEN
        INSERT INTO ${mjSchema}."EntityField"
        (
        "ID",
        "EntityID",
        "Sequence",
        "Name",
        "DisplayName",
        "Description",
        "Type",
        "Length",
        "Precision",
        "Scale",
        "AllowsNull",
        "DefaultValue",
        "AutoIncrement",
        "AllowUpdateAPI",
        "IsVirtual",
        "IsComputed",
        "RelatedEntityID",
        "RelatedEntityFieldName",
        "IsNameField",
        "IncludeInUserSearchAPI",
        "IncludeRelatedEntityNameFieldInBaseView",
        "DefaultInView",
        "IsPrimaryKey",
        "IsUnique",
        "RelatedEntityDisplayType",
        "__mj_CreatedAt",
        "__mj_UpdatedAt"
        )
        VALUES
        (
        '8cfc093f-2135-437e-93a8-493a64dfa174',
        '6B363236-31AB-477D-8188-08F5FA9942EF', -- "Entity": "MJ_BizApps_Tasks_GitHub": "Git" "Hub" "Repositories"
        (SELECT COALESCE(MAX("Sequence"), 0) + 1 FROM ${mjSchema}."EntityField" WHERE "EntityID" = '6B363236-31AB-477D-8188-08F5FA9942EF'),
        'Name',
        'Name',
        'Repository slug within the owner namespace (e.g. MJ, bizapps-tasks).',
        'TEXT',
        400,
        0,
        0,
        FALSE,
        NULL,
        FALSE,
        TRUE,
        FALSE,
        FALSE,
        NULL,
        NULL,
        TRUE,
        TRUE,
        FALSE,
        TRUE,
        FALSE,
        TRUE,
        'Search',
        NOW(),
        NOW()
        );
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM ${mjSchema}."EntityField" WHERE "ID" = '8231446a-482b-4d5f-a1ed-ae1a717f50a0' OR ("EntityID" = '6B363236-31AB-477D-8188-08F5FA9942EF' AND "Name" = 'DefaultBranch')
    ) THEN
        INSERT INTO ${mjSchema}."EntityField"
        (
        "ID",
        "EntityID",
        "Sequence",
        "Name",
        "DisplayName",
        "Description",
        "Type",
        "Length",
        "Precision",
        "Scale",
        "AllowsNull",
        "DefaultValue",
        "AutoIncrement",
        "AllowUpdateAPI",
        "IsVirtual",
        "IsComputed",
        "RelatedEntityID",
        "RelatedEntityFieldName",
        "IsNameField",
        "IncludeInUserSearchAPI",
        "IncludeRelatedEntityNameFieldInBaseView",
        "DefaultInView",
        "IsPrimaryKey",
        "IsUnique",
        "RelatedEntityDisplayType",
        "__mj_CreatedAt",
        "__mj_UpdatedAt"
        )
        VALUES
        (
        '8231446a-482b-4d5f-a1ed-ae1a717f50a0',
        '6B363236-31AB-477D-8188-08F5FA9942EF', -- "Entity": "MJ_BizApps_Tasks_GitHub": "Git" "Hub" "Repositories"
        (SELECT COALESCE(MAX("Sequence"), 0) + 1 FROM ${mjSchema}."EntityField" WHERE "EntityID" = '6B363236-31AB-477D-8188-08F5FA9942EF'),
        'DefaultBranch',
        'Default Branch',
        'Default target branch name on GitHub (typically main or next).',
        'TEXT',
        240,
        0,
        0,
        FALSE,
        'main',
        FALSE,
        TRUE,
        FALSE,
        FALSE,
        NULL,
        NULL,
        FALSE,
        FALSE,
        FALSE,
        TRUE,
        FALSE,
        FALSE,
        'Search',
        NOW(),
        NOW()
        );
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM ${mjSchema}."EntityField" WHERE "ID" = '89c19524-c1fb-441e-a66c-577ddc5d41c3' OR ("EntityID" = '6B363236-31AB-477D-8188-08F5FA9942EF' AND "Name" = 'IsTracked')
    ) THEN
        INSERT INTO ${mjSchema}."EntityField"
        (
        "ID",
        "EntityID",
        "Sequence",
        "Name",
        "DisplayName",
        "Description",
        "Type",
        "Length",
        "Precision",
        "Scale",
        "AllowsNull",
        "DefaultValue",
        "AutoIncrement",
        "AllowUpdateAPI",
        "IsVirtual",
        "IsComputed",
        "RelatedEntityID",
        "RelatedEntityFieldName",
        "IsNameField",
        "IncludeInUserSearchAPI",
        "IncludeRelatedEntityNameFieldInBaseView",
        "DefaultInView",
        "IsPrimaryKey",
        "IsUnique",
        "RelatedEntityDisplayType",
        "__mj_CreatedAt",
        "__mj_UpdatedAt"
        )
        VALUES
        (
        '89c19524-c1fb-441e-a66c-577ddc5d41c3',
        '6B363236-31AB-477D-8188-08F5FA9942EF', -- "Entity": "MJ_BizApps_Tasks_GitHub": "Git" "Hub" "Repositories"
        (SELECT COALESCE(MAX("Sequence"), 0) + 1 FROM ${mjSchema}."EntityField" WHERE "EntityID" = '6B363236-31AB-477D-8188-08F5FA9942EF'),
        'IsTracked',
        'Is Tracked',
        'When 1, periodic sync and incoming webhooks import eligible issues and pull requests into BizApps Tasks.',
        'BOOLEAN',
        1,
        1,
        0,
        FALSE,
        '(1)',
        FALSE,
        TRUE,
        FALSE,
        FALSE,
        NULL,
        NULL,
        FALSE,
        FALSE,
        FALSE,
        TRUE,
        FALSE,
        FALSE,
        'Search',
        NOW(),
        NOW()
        );
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM ${mjSchema}."EntityField" WHERE "ID" = 'd09cc770-1cbb-4078-8186-bf3ed875f03c' OR ("EntityID" = '6B363236-31AB-477D-8188-08F5FA9942EF' AND "Name" = 'ImportRule')
    ) THEN
        INSERT INTO ${mjSchema}."EntityField"
        (
        "ID",
        "EntityID",
        "Sequence",
        "Name",
        "DisplayName",
        "Description",
        "Type",
        "Length",
        "Precision",
        "Scale",
        "AllowsNull",
        "DefaultValue",
        "AutoIncrement",
        "AllowUpdateAPI",
        "IsVirtual",
        "IsComputed",
        "RelatedEntityID",
        "RelatedEntityFieldName",
        "IsNameField",
        "IncludeInUserSearchAPI",
        "IncludeRelatedEntityNameFieldInBaseView",
        "DefaultInView",
        "IsPrimaryKey",
        "IsUnique",
        "RelatedEntityDisplayType",
        "__mj_CreatedAt",
        "__mj_UpdatedAt"
        )
        VALUES
        (
        'd09cc770-1cbb-4078-8186-bf3ed875f03c',
        '6B363236-31AB-477D-8188-08F5FA9942EF', -- "Entity": "MJ_BizApps_Tasks_GitHub": "Git" "Hub" "Repositories"
        (SELECT COALESCE(MAX("Sequence"), 0) + 1 FROM ${mjSchema}."EntityField" WHERE "EntityID" = '6B363236-31AB-477D-8188-08F5FA9942EF'),
        'ImportRule',
        'Import Rule',
        'Controls which issues and PRs become Tasks: AssignedOnly imports items assigned to or requesting review from a mapped GitHubIdentity; All imports every issue and PR in the repository.',
        'TEXT',
        40,
        0,
        0,
        FALSE,
        'AssignedOnly',
        FALSE,
        TRUE,
        FALSE,
        FALSE,
        NULL,
        NULL,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        'Search',
        NOW(),
        NOW()
        );
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM ${mjSchema}."EntityField" WHERE "ID" = 'f6397e85-2f8b-4b39-a42f-4063209b7c3e' OR ("EntityID" = '6B363236-31AB-477D-8188-08F5FA9942EF' AND "Name" = 'InstallationID')
    ) THEN
        INSERT INTO ${mjSchema}."EntityField"
        (
        "ID",
        "EntityID",
        "Sequence",
        "Name",
        "DisplayName",
        "Description",
        "Type",
        "Length",
        "Precision",
        "Scale",
        "AllowsNull",
        "DefaultValue",
        "AutoIncrement",
        "AllowUpdateAPI",
        "IsVirtual",
        "IsComputed",
        "RelatedEntityID",
        "RelatedEntityFieldName",
        "IsNameField",
        "IncludeInUserSearchAPI",
        "IncludeRelatedEntityNameFieldInBaseView",
        "DefaultInView",
        "IsPrimaryKey",
        "IsUnique",
        "RelatedEntityDisplayType",
        "__mj_CreatedAt",
        "__mj_UpdatedAt"
        )
        VALUES
        (
        'f6397e85-2f8b-4b39-a42f-4063209b7c3e',
        '6B363236-31AB-477D-8188-08F5FA9942EF', -- "Entity": "MJ_BizApps_Tasks_GitHub": "Git" "Hub" "Repositories"
        (SELECT COALESCE(MAX("Sequence"), 0) + 1 FROM ${mjSchema}."EntityField" WHERE "EntityID" = '6B363236-31AB-477D-8188-08F5FA9942EF'),
        'InstallationID',
        'Installation ID',
        'GitHub App installation identifier scoped to this repository or organization.',
        'TEXT',
        200,
        0,
        0,
        TRUE,
        NULL,
        FALSE,
        TRUE,
        FALSE,
        FALSE,
        NULL,
        NULL,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        'Search',
        NOW(),
        NOW()
        );
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM ${mjSchema}."EntityField" WHERE "ID" = '507961d4-497e-4b22-9cff-c6506f32b45c' OR ("EntityID" = '6B363236-31AB-477D-8188-08F5FA9942EF' AND "Name" = 'OrganizationID')
    ) THEN
        INSERT INTO ${mjSchema}."EntityField"
        (
        "ID",
        "EntityID",
        "Sequence",
        "Name",
        "DisplayName",
        "Description",
        "Type",
        "Length",
        "Precision",
        "Scale",
        "AllowsNull",
        "DefaultValue",
        "AutoIncrement",
        "AllowUpdateAPI",
        "IsVirtual",
        "IsComputed",
        "RelatedEntityID",
        "RelatedEntityFieldName",
        "IsNameField",
        "IncludeInUserSearchAPI",
        "IncludeRelatedEntityNameFieldInBaseView",
        "DefaultInView",
        "IsPrimaryKey",
        "IsUnique",
        "RelatedEntityDisplayType",
        "__mj_CreatedAt",
        "__mj_UpdatedAt"
        )
        VALUES
        (
        '507961d4-497e-4b22-9cff-c6506f32b45c',
        '6B363236-31AB-477D-8188-08F5FA9942EF', -- "Entity": "MJ_BizApps_Tasks_GitHub": "Git" "Hub" "Repositories"
        (SELECT COALESCE(MAX("Sequence"), 0) + 1 FROM ${mjSchema}."EntityField" WHERE "EntityID" = '6B363236-31AB-477D-8188-08F5FA9942EF'),
        'OrganizationID',
        'Organization ID',
        'Optional client Organization in BizApps Common. Null denotes an internal repository; non-null enables Client-layer DeliveryPolicy inheritance.',
        'UUID',
        16,
        0,
        0,
        TRUE,
        NULL,
        FALSE,
        TRUE,
        FALSE,
        FALSE,
        'C70448F9-9792-41D7-A82C-784B66429D54',
        'ID',
        FALSE,
        FALSE,
        TRUE,
        FALSE,
        FALSE,
        FALSE,
        'Search',
        NOW(),
        NOW()
        );
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM ${mjSchema}."EntityField" WHERE "ID" = '2685c802-43ea-4389-b1cc-5d007755dcd6' OR ("EntityID" = '6B363236-31AB-477D-8188-08F5FA9942EF' AND "Name" = 'DeliveryPolicyID')
    ) THEN
        INSERT INTO ${mjSchema}."EntityField"
        (
        "ID",
        "EntityID",
        "Sequence",
        "Name",
        "DisplayName",
        "Description",
        "Type",
        "Length",
        "Precision",
        "Scale",
        "AllowsNull",
        "DefaultValue",
        "AutoIncrement",
        "AllowUpdateAPI",
        "IsVirtual",
        "IsComputed",
        "RelatedEntityID",
        "RelatedEntityFieldName",
        "IsNameField",
        "IncludeInUserSearchAPI",
        "IncludeRelatedEntityNameFieldInBaseView",
        "DefaultInView",
        "IsPrimaryKey",
        "IsUnique",
        "RelatedEntityDisplayType",
        "__mj_CreatedAt",
        "__mj_UpdatedAt"
        )
        VALUES
        (
        '2685c802-43ea-4389-b1cc-5d007755dcd6',
        '6B363236-31AB-477D-8188-08F5FA9942EF', -- "Entity": "MJ_BizApps_Tasks_GitHub": "Git" "Hub" "Repositories"
        (SELECT COALESCE(MAX("Sequence"), 0) + 1 FROM ${mjSchema}."EntityField" WHERE "EntityID" = '6B363236-31AB-477D-8188-08F5FA9942EF'),
        'DeliveryPolicyID',
        'Delivery Policy ID',
        'Optional UUID of the repository-level DeliveryPolicy in bizapps-software-factory when installed.',
        'UUID',
        16,
        0,
        0,
        TRUE,
        NULL,
        FALSE,
        TRUE,
        FALSE,
        FALSE,
        NULL,
        NULL,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        'Search',
        NOW(),
        NOW()
        );
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM ${mjSchema}."EntityField" WHERE "ID" = 'f9323407-463f-4ef0-8e56-800d98360b4a' OR ("EntityID" = '6B363236-31AB-477D-8188-08F5FA9942EF' AND "Name" = '__mj_CreatedAt')
    ) THEN
        INSERT INTO ${mjSchema}."EntityField"
        (
        "ID",
        "EntityID",
        "Sequence",
        "Name",
        "DisplayName",
        "Description",
        "Type",
        "Length",
        "Precision",
        "Scale",
        "AllowsNull",
        "DefaultValue",
        "AutoIncrement",
        "AllowUpdateAPI",
        "IsVirtual",
        "IsComputed",
        "RelatedEntityID",
        "RelatedEntityFieldName",
        "IsNameField",
        "IncludeInUserSearchAPI",
        "IncludeRelatedEntityNameFieldInBaseView",
        "DefaultInView",
        "IsPrimaryKey",
        "IsUnique",
        "RelatedEntityDisplayType",
        "__mj_CreatedAt",
        "__mj_UpdatedAt"
        )
        VALUES
        (
        'f9323407-463f-4ef0-8e56-800d98360b4a',
        '6B363236-31AB-477D-8188-08F5FA9942EF', -- "Entity": "MJ_BizApps_Tasks_GitHub": "Git" "Hub" "Repositories"
        (SELECT COALESCE(MAX("Sequence"), 0) + 1 FROM ${mjSchema}."EntityField" WHERE "EntityID" = '6B363236-31AB-477D-8188-08F5FA9942EF'),
        '__mj_CreatedAt',
        'Created At',
        NULL,
        'TIMESTAMPTZ',
        10,
        34,
        7,
        FALSE,
        'NOW()',
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        NULL,
        NULL,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        'Search',
        NOW(),
        NOW()
        );
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM ${mjSchema}."EntityField" WHERE "ID" = '1e25cf76-141f-4848-8a29-c47a7a522297' OR ("EntityID" = '6B363236-31AB-477D-8188-08F5FA9942EF' AND "Name" = '__mj_UpdatedAt')
    ) THEN
        INSERT INTO ${mjSchema}."EntityField"
        (
        "ID",
        "EntityID",
        "Sequence",
        "Name",
        "DisplayName",
        "Description",
        "Type",
        "Length",
        "Precision",
        "Scale",
        "AllowsNull",
        "DefaultValue",
        "AutoIncrement",
        "AllowUpdateAPI",
        "IsVirtual",
        "IsComputed",
        "RelatedEntityID",
        "RelatedEntityFieldName",
        "IsNameField",
        "IncludeInUserSearchAPI",
        "IncludeRelatedEntityNameFieldInBaseView",
        "DefaultInView",
        "IsPrimaryKey",
        "IsUnique",
        "RelatedEntityDisplayType",
        "__mj_CreatedAt",
        "__mj_UpdatedAt"
        )
        VALUES
        (
        '1e25cf76-141f-4848-8a29-c47a7a522297',
        '6B363236-31AB-477D-8188-08F5FA9942EF', -- "Entity": "MJ_BizApps_Tasks_GitHub": "Git" "Hub" "Repositories"
        (SELECT COALESCE(MAX("Sequence"), 0) + 1 FROM ${mjSchema}."EntityField" WHERE "EntityID" = '6B363236-31AB-477D-8188-08F5FA9942EF'),
        '__mj_UpdatedAt',
        'Updated At',
        NULL,
        'TIMESTAMPTZ',
        10,
        34,
        7,
        FALSE,
        'NOW()',
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        NULL,
        NULL,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        'Search',
        NOW(),
        NOW()
        );
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM ${mjSchema}."EntityField" WHERE "ID" = 'f041d734-2d08-48f3-baa4-c29f45bfb5de' OR ("EntityID" = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605' AND "Name" = 'ID')
    ) THEN
        INSERT INTO ${mjSchema}."EntityField"
        (
        "ID",
        "EntityID",
        "Sequence",
        "Name",
        "DisplayName",
        "Description",
        "Type",
        "Length",
        "Precision",
        "Scale",
        "AllowsNull",
        "DefaultValue",
        "AutoIncrement",
        "AllowUpdateAPI",
        "IsVirtual",
        "IsComputed",
        "RelatedEntityID",
        "RelatedEntityFieldName",
        "IsNameField",
        "IncludeInUserSearchAPI",
        "IncludeRelatedEntityNameFieldInBaseView",
        "DefaultInView",
        "IsPrimaryKey",
        "IsUnique",
        "RelatedEntityDisplayType",
        "__mj_CreatedAt",
        "__mj_UpdatedAt"
        )
        VALUES
        (
        'f041d734-2d08-48f3-baa4-c29f45bfb5de',
        'DC8E0F5B-E172-4FD5-B648-8B4544F8C605', -- "Entity": "MJ_BizApps_Tasks_GitHub": "Git" "Hub" "Issue" "Tasks"
        (SELECT COALESCE(MAX("Sequence"), 0) + 1 FROM ${mjSchema}."EntityField" WHERE "EntityID" = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605'),
        'ID',
        'ID',
        'Shared primary key referencing __mj_BizAppsTasks.Task(ID).',
        'UUID',
        16,
        0,
        0,
        FALSE,
        NULL,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        'B348FFA2-B1A7-4AC2-B6FD-F4E0C0697466',
        'ID',
        FALSE,
        FALSE,
        TRUE,
        FALSE,
        TRUE,
        TRUE,
        'Search',
        NOW(),
        NOW()
        );
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM ${mjSchema}."EntityField" WHERE "ID" = '54442a79-cead-408b-82aa-4119053fe27e' OR ("EntityID" = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605' AND "Name" = 'RepositoryID')
    ) THEN
        INSERT INTO ${mjSchema}."EntityField"
        (
        "ID",
        "EntityID",
        "Sequence",
        "Name",
        "DisplayName",
        "Description",
        "Type",
        "Length",
        "Precision",
        "Scale",
        "AllowsNull",
        "DefaultValue",
        "AutoIncrement",
        "AllowUpdateAPI",
        "IsVirtual",
        "IsComputed",
        "RelatedEntityID",
        "RelatedEntityFieldName",
        "IsNameField",
        "IncludeInUserSearchAPI",
        "IncludeRelatedEntityNameFieldInBaseView",
        "DefaultInView",
        "IsPrimaryKey",
        "IsUnique",
        "RelatedEntityDisplayType",
        "__mj_CreatedAt",
        "__mj_UpdatedAt"
        )
        VALUES
        (
        '54442a79-cead-408b-82aa-4119053fe27e',
        'DC8E0F5B-E172-4FD5-B648-8B4544F8C605', -- "Entity": "MJ_BizApps_Tasks_GitHub": "Git" "Hub" "Issue" "Tasks"
        (SELECT COALESCE(MAX("Sequence"), 0) + 1 FROM ${mjSchema}."EntityField" WHERE "EntityID" = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605'),
        'RepositoryID',
        'Repository ID',
        'GitHubRepository to which this issue belongs.',
        'UUID',
        16,
        0,
        0,
        TRUE,
        NULL,
        FALSE,
        TRUE,
        FALSE,
        FALSE,
        '6B363236-31AB-477D-8188-08F5FA9942EF',
        'ID',
        FALSE,
        FALSE,
        TRUE,
        FALSE,
        FALSE,
        TRUE,
        'Search',
        NOW(),
        NOW()
        );
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM ${mjSchema}."EntityField" WHERE "ID" = 'a97ca445-668e-4763-a2c6-74de67a33925' OR ("EntityID" = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605' AND "Name" = 'Number')
    ) THEN
        INSERT INTO ${mjSchema}."EntityField"
        (
        "ID",
        "EntityID",
        "Sequence",
        "Name",
        "DisplayName",
        "Description",
        "Type",
        "Length",
        "Precision",
        "Scale",
        "AllowsNull",
        "DefaultValue",
        "AutoIncrement",
        "AllowUpdateAPI",
        "IsVirtual",
        "IsComputed",
        "RelatedEntityID",
        "RelatedEntityFieldName",
        "IsNameField",
        "IncludeInUserSearchAPI",
        "IncludeRelatedEntityNameFieldInBaseView",
        "DefaultInView",
        "IsPrimaryKey",
        "IsUnique",
        "RelatedEntityDisplayType",
        "__mj_CreatedAt",
        "__mj_UpdatedAt"
        )
        VALUES
        (
        'a97ca445-668e-4763-a2c6-74de67a33925',
        'DC8E0F5B-E172-4FD5-B648-8B4544F8C605', -- "Entity": "MJ_BizApps_Tasks_GitHub": "Git" "Hub" "Issue" "Tasks"
        (SELECT COALESCE(MAX("Sequence"), 0) + 1 FROM ${mjSchema}."EntityField" WHERE "EntityID" = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605'),
        'Number',
        'Number',
        'Repository-scoped GitHub issue number (#N). Unique per RepositoryID when populated.',
        'INTEGER',
        4,
        10,
        0,
        TRUE,
        NULL,
        FALSE,
        TRUE,
        FALSE,
        FALSE,
        NULL,
        NULL,
        FALSE,
        FALSE,
        FALSE,
        TRUE,
        FALSE,
        TRUE,
        'Search',
        NOW(),
        NOW()
        );
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM ${mjSchema}."EntityField" WHERE "ID" = 'b0c058e3-ba70-4f2a-9b84-21ab522e8e6d' OR ("EntityID" = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605' AND "Name" = 'NodeID')
    ) THEN
        INSERT INTO ${mjSchema}."EntityField"
        (
        "ID",
        "EntityID",
        "Sequence",
        "Name",
        "DisplayName",
        "Description",
        "Type",
        "Length",
        "Precision",
        "Scale",
        "AllowsNull",
        "DefaultValue",
        "AutoIncrement",
        "AllowUpdateAPI",
        "IsVirtual",
        "IsComputed",
        "RelatedEntityID",
        "RelatedEntityFieldName",
        "IsNameField",
        "IncludeInUserSearchAPI",
        "IncludeRelatedEntityNameFieldInBaseView",
        "DefaultInView",
        "IsPrimaryKey",
        "IsUnique",
        "RelatedEntityDisplayType",
        "__mj_CreatedAt",
        "__mj_UpdatedAt"
        )
        VALUES
        (
        'b0c058e3-ba70-4f2a-9b84-21ab522e8e6d',
        'DC8E0F5B-E172-4FD5-B648-8B4544F8C605', -- "Entity": "MJ_BizApps_Tasks_GitHub": "Git" "Hub" "Issue" "Tasks"
        (SELECT COALESCE(MAX("Sequence"), 0) + 1 FROM ${mjSchema}."EntityField" WHERE "EntityID" = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605'),
        'NodeID',
        'Node ID',
        'Global GitHub GraphQL node identifier for idempotent cross-rename sync.',
        'TEXT',
        256,
        0,
        0,
        TRUE,
        NULL,
        FALSE,
        TRUE,
        FALSE,
        FALSE,
        NULL,
        NULL,
        FALSE,
        FALSE,
        FALSE,
        TRUE,
        FALSE,
        TRUE,
        'Search',
        NOW(),
        NOW()
        );
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM ${mjSchema}."EntityField" WHERE "ID" = '6b287fde-cf5a-4381-84a1-96a45d3e58c4' OR ("EntityID" = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605' AND "Name" = 'HtmlURL')
    ) THEN
        INSERT INTO ${mjSchema}."EntityField"
        (
        "ID",
        "EntityID",
        "Sequence",
        "Name",
        "DisplayName",
        "Description",
        "Type",
        "Length",
        "Precision",
        "Scale",
        "AllowsNull",
        "DefaultValue",
        "AutoIncrement",
        "AllowUpdateAPI",
        "IsVirtual",
        "IsComputed",
        "RelatedEntityID",
        "RelatedEntityFieldName",
        "IsNameField",
        "IncludeInUserSearchAPI",
        "IncludeRelatedEntityNameFieldInBaseView",
        "DefaultInView",
        "IsPrimaryKey",
        "IsUnique",
        "RelatedEntityDisplayType",
        "__mj_CreatedAt",
        "__mj_UpdatedAt"
        )
        VALUES
        (
        '6b287fde-cf5a-4381-84a1-96a45d3e58c4',
        'DC8E0F5B-E172-4FD5-B648-8B4544F8C605', -- "Entity": "MJ_BizApps_Tasks_GitHub": "Git" "Hub" "Issue" "Tasks"
        (SELECT COALESCE(MAX("Sequence"), 0) + 1 FROM ${mjSchema}."EntityField" WHERE "EntityID" = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605'),
        'HtmlURL',
        'Html URL',
        'Canonical browser URL to view or edit the issue on GitHub.',
        'TEXT',
        2000,
        0,
        0,
        TRUE,
        NULL,
        FALSE,
        TRUE,
        FALSE,
        FALSE,
        NULL,
        NULL,
        FALSE,
        FALSE,
        FALSE,
        TRUE,
        FALSE,
        FALSE,
        'Search',
        NOW(),
        NOW()
        );
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM ${mjSchema}."EntityField" WHERE "ID" = '54cd3bc9-e3df-4b33-9413-b2f137eb2452' OR ("EntityID" = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605' AND "Name" = 'State')
    ) THEN
        INSERT INTO ${mjSchema}."EntityField"
        (
        "ID",
        "EntityID",
        "Sequence",
        "Name",
        "DisplayName",
        "Description",
        "Type",
        "Length",
        "Precision",
        "Scale",
        "AllowsNull",
        "DefaultValue",
        "AutoIncrement",
        "AllowUpdateAPI",
        "IsVirtual",
        "IsComputed",
        "RelatedEntityID",
        "RelatedEntityFieldName",
        "IsNameField",
        "IncludeInUserSearchAPI",
        "IncludeRelatedEntityNameFieldInBaseView",
        "DefaultInView",
        "IsPrimaryKey",
        "IsUnique",
        "RelatedEntityDisplayType",
        "__mj_CreatedAt",
        "__mj_UpdatedAt"
        )
        VALUES
        (
        '54cd3bc9-e3df-4b33-9413-b2f137eb2452',
        'DC8E0F5B-E172-4FD5-B648-8B4544F8C605', -- "Entity": "MJ_BizApps_Tasks_GitHub": "Git" "Hub" "Issue" "Tasks"
        (SELECT COALESCE(MAX("Sequence"), 0) + 1 FROM ${mjSchema}."EntityField" WHERE "EntityID" = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605'),
        'State',
        'State',
        'GitHub issue state (open or closed).',
        'TEXT',
        40,
        0,
        0,
        FALSE,
        'open',
        FALSE,
        TRUE,
        FALSE,
        FALSE,
        NULL,
        NULL,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        'Search',
        NOW(),
        NOW()
        );
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM ${mjSchema}."EntityField" WHERE "ID" = 'ac27eb42-f18d-4444-99a2-9e454dbaeb49' OR ("EntityID" = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605' AND "Name" = 'StateReason')
    ) THEN
        INSERT INTO ${mjSchema}."EntityField"
        (
        "ID",
        "EntityID",
        "Sequence",
        "Name",
        "DisplayName",
        "Description",
        "Type",
        "Length",
        "Precision",
        "Scale",
        "AllowsNull",
        "DefaultValue",
        "AutoIncrement",
        "AllowUpdateAPI",
        "IsVirtual",
        "IsComputed",
        "RelatedEntityID",
        "RelatedEntityFieldName",
        "IsNameField",
        "IncludeInUserSearchAPI",
        "IncludeRelatedEntityNameFieldInBaseView",
        "DefaultInView",
        "IsPrimaryKey",
        "IsUnique",
        "RelatedEntityDisplayType",
        "__mj_CreatedAt",
        "__mj_UpdatedAt"
        )
        VALUES
        (
        'ac27eb42-f18d-4444-99a2-9e454dbaeb49',
        'DC8E0F5B-E172-4FD5-B648-8B4544F8C605', -- "Entity": "MJ_BizApps_Tasks_GitHub": "Git" "Hub" "Issue" "Tasks"
        (SELECT COALESCE(MAX("Sequence"), 0) + 1 FROM ${mjSchema}."EntityField" WHERE "EntityID" = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605'),
        'StateReason',
        'State Reason',
        'Optional GitHub issue state_reason (completed, not_planned, reopened, duplicate).',
        'TEXT',
        80,
        0,
        0,
        TRUE,
        NULL,
        FALSE,
        TRUE,
        FALSE,
        FALSE,
        NULL,
        NULL,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        'Search',
        NOW(),
        NOW()
        );
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM ${mjSchema}."EntityField" WHERE "ID" = '9f961e3c-910b-44c2-a78f-e0ac03ed963f' OR ("EntityID" = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605' AND "Name" = 'Labels')
    ) THEN
        INSERT INTO ${mjSchema}."EntityField"
        (
        "ID",
        "EntityID",
        "Sequence",
        "Name",
        "DisplayName",
        "Description",
        "Type",
        "Length",
        "Precision",
        "Scale",
        "AllowsNull",
        "DefaultValue",
        "AutoIncrement",
        "AllowUpdateAPI",
        "IsVirtual",
        "IsComputed",
        "RelatedEntityID",
        "RelatedEntityFieldName",
        "IsNameField",
        "IncludeInUserSearchAPI",
        "IncludeRelatedEntityNameFieldInBaseView",
        "DefaultInView",
        "IsPrimaryKey",
        "IsUnique",
        "RelatedEntityDisplayType",
        "__mj_CreatedAt",
        "__mj_UpdatedAt"
        )
        VALUES
        (
        '9f961e3c-910b-44c2-a78f-e0ac03ed963f',
        'DC8E0F5B-E172-4FD5-B648-8B4544F8C605', -- "Entity": "MJ_BizApps_Tasks_GitHub": "Git" "Hub" "Issue" "Tasks"
        (SELECT COALESCE(MAX("Sequence"), 0) + 1 FROM ${mjSchema}."EntityField" WHERE "EntityID" = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605'),
        'Labels',
        'Labels',
        'JSON array of GitHub label names applied to the issue.',
        'TEXT',
        -1,
        0,
        0,
        TRUE,
        NULL,
        FALSE,
        TRUE,
        FALSE,
        FALSE,
        NULL,
        NULL,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        'Search',
        NOW(),
        NOW()
        );
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM ${mjSchema}."EntityField" WHERE "ID" = '8a9b093f-91d1-4991-9069-4f2f36ad9181' OR ("EntityID" = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605' AND "Name" = 'Milestone')
    ) THEN
        INSERT INTO ${mjSchema}."EntityField"
        (
        "ID",
        "EntityID",
        "Sequence",
        "Name",
        "DisplayName",
        "Description",
        "Type",
        "Length",
        "Precision",
        "Scale",
        "AllowsNull",
        "DefaultValue",
        "AutoIncrement",
        "AllowUpdateAPI",
        "IsVirtual",
        "IsComputed",
        "RelatedEntityID",
        "RelatedEntityFieldName",
        "IsNameField",
        "IncludeInUserSearchAPI",
        "IncludeRelatedEntityNameFieldInBaseView",
        "DefaultInView",
        "IsPrimaryKey",
        "IsUnique",
        "RelatedEntityDisplayType",
        "__mj_CreatedAt",
        "__mj_UpdatedAt"
        )
        VALUES
        (
        '8a9b093f-91d1-4991-9069-4f2f36ad9181',
        'DC8E0F5B-E172-4FD5-B648-8B4544F8C605', -- "Entity": "MJ_BizApps_Tasks_GitHub": "Git" "Hub" "Issue" "Tasks"
        (SELECT COALESCE(MAX("Sequence"), 0) + 1 FROM ${mjSchema}."EntityField" WHERE "EntityID" = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605'),
        'Milestone',
        'Milestone',
        'GitHub milestone title when assigned.',
        'TEXT',
        510,
        0,
        0,
        TRUE,
        NULL,
        FALSE,
        TRUE,
        FALSE,
        FALSE,
        NULL,
        NULL,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        'Search',
        NOW(),
        NOW()
        );
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM ${mjSchema}."EntityField" WHERE "ID" = '9a88e775-dca4-46ed-b580-cc79394b5b69' OR ("EntityID" = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605' AND "Name" = 'MilestoneDueAt')
    ) THEN
        INSERT INTO ${mjSchema}."EntityField"
        (
        "ID",
        "EntityID",
        "Sequence",
        "Name",
        "DisplayName",
        "Description",
        "Type",
        "Length",
        "Precision",
        "Scale",
        "AllowsNull",
        "DefaultValue",
        "AutoIncrement",
        "AllowUpdateAPI",
        "IsVirtual",
        "IsComputed",
        "RelatedEntityID",
        "RelatedEntityFieldName",
        "IsNameField",
        "IncludeInUserSearchAPI",
        "IncludeRelatedEntityNameFieldInBaseView",
        "DefaultInView",
        "IsPrimaryKey",
        "IsUnique",
        "RelatedEntityDisplayType",
        "__mj_CreatedAt",
        "__mj_UpdatedAt"
        )
        VALUES
        (
        '9a88e775-dca4-46ed-b580-cc79394b5b69',
        'DC8E0F5B-E172-4FD5-B648-8B4544F8C605', -- "Entity": "MJ_BizApps_Tasks_GitHub": "Git" "Hub" "Issue" "Tasks"
        (SELECT COALESCE(MAX("Sequence"), 0) + 1 FROM ${mjSchema}."EntityField" WHERE "EntityID" = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605'),
        'MilestoneDueAt',
        'Milestone Due At',
        'Due timestamp of the GitHub milestone; supersedes pending inferred DueAt Field Suggestions.',
        'TIMESTAMPTZ',
        10,
        34,
        7,
        TRUE,
        NULL,
        FALSE,
        TRUE,
        FALSE,
        FALSE,
        NULL,
        NULL,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        'Search',
        NOW(),
        NOW()
        );
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM ${mjSchema}."EntityField" WHERE "ID" = '47f2bc8c-baa7-4720-8425-3f982edfd315' OR ("EntityID" = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605' AND "Name" = 'AuthorLogin')
    ) THEN
        INSERT INTO ${mjSchema}."EntityField"
        (
        "ID",
        "EntityID",
        "Sequence",
        "Name",
        "DisplayName",
        "Description",
        "Type",
        "Length",
        "Precision",
        "Scale",
        "AllowsNull",
        "DefaultValue",
        "AutoIncrement",
        "AllowUpdateAPI",
        "IsVirtual",
        "IsComputed",
        "RelatedEntityID",
        "RelatedEntityFieldName",
        "IsNameField",
        "IncludeInUserSearchAPI",
        "IncludeRelatedEntityNameFieldInBaseView",
        "DefaultInView",
        "IsPrimaryKey",
        "IsUnique",
        "RelatedEntityDisplayType",
        "__mj_CreatedAt",
        "__mj_UpdatedAt"
        )
        VALUES
        (
        '47f2bc8c-baa7-4720-8425-3f982edfd315',
        'DC8E0F5B-E172-4FD5-B648-8B4544F8C605', -- "Entity": "MJ_BizApps_Tasks_GitHub": "Git" "Hub" "Issue" "Tasks"
        (SELECT COALESCE(MAX("Sequence"), 0) + 1 FROM ${mjSchema}."EntityField" WHERE "EntityID" = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605'),
        'AuthorLogin',
        'Author Login',
        'GitHub login of the user who opened the issue.',
        'TEXT',
        200,
        0,
        0,
        TRUE,
        NULL,
        FALSE,
        TRUE,
        FALSE,
        FALSE,
        NULL,
        NULL,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        'Search',
        NOW(),
        NOW()
        );
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM ${mjSchema}."EntityField" WHERE "ID" = '0b5ed37c-d3ab-4c8a-a484-f0e12dbd9744' OR ("EntityID" = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605' AND "Name" = 'BodyHash')
    ) THEN
        INSERT INTO ${mjSchema}."EntityField"
        (
        "ID",
        "EntityID",
        "Sequence",
        "Name",
        "DisplayName",
        "Description",
        "Type",
        "Length",
        "Precision",
        "Scale",
        "AllowsNull",
        "DefaultValue",
        "AutoIncrement",
        "AllowUpdateAPI",
        "IsVirtual",
        "IsComputed",
        "RelatedEntityID",
        "RelatedEntityFieldName",
        "IsNameField",
        "IncludeInUserSearchAPI",
        "IncludeRelatedEntityNameFieldInBaseView",
        "DefaultInView",
        "IsPrimaryKey",
        "IsUnique",
        "RelatedEntityDisplayType",
        "__mj_CreatedAt",
        "__mj_UpdatedAt"
        )
        VALUES
        (
        '0b5ed37c-d3ab-4c8a-a484-f0e12dbd9744',
        'DC8E0F5B-E172-4FD5-B648-8B4544F8C605', -- "Entity": "MJ_BizApps_Tasks_GitHub": "Git" "Hub" "Issue" "Tasks"
        (SELECT COALESCE(MAX("Sequence"), 0) + 1 FROM ${mjSchema}."EntityField" WHERE "EntityID" = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605'),
        'BodyHash',
        'Body Hash',
        'SHA-256 hash of the last synced issue body used to detect text edits and trigger Field Suggestion re-inference.',
        'TEXT',
        128,
        0,
        0,
        TRUE,
        NULL,
        FALSE,
        TRUE,
        FALSE,
        FALSE,
        NULL,
        NULL,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        'Search',
        NOW(),
        NOW()
        );
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM ${mjSchema}."EntityField" WHERE "ID" = 'ff322d0f-97cb-4cee-9c1e-c347a4c145ae' OR ("EntityID" = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605' AND "Name" = 'GitHubUpdatedAt')
    ) THEN
        INSERT INTO ${mjSchema}."EntityField"
        (
        "ID",
        "EntityID",
        "Sequence",
        "Name",
        "DisplayName",
        "Description",
        "Type",
        "Length",
        "Precision",
        "Scale",
        "AllowsNull",
        "DefaultValue",
        "AutoIncrement",
        "AllowUpdateAPI",
        "IsVirtual",
        "IsComputed",
        "RelatedEntityID",
        "RelatedEntityFieldName",
        "IsNameField",
        "IncludeInUserSearchAPI",
        "IncludeRelatedEntityNameFieldInBaseView",
        "DefaultInView",
        "IsPrimaryKey",
        "IsUnique",
        "RelatedEntityDisplayType",
        "__mj_CreatedAt",
        "__mj_UpdatedAt"
        )
        VALUES
        (
        'ff322d0f-97cb-4cee-9c1e-c347a4c145ae',
        'DC8E0F5B-E172-4FD5-B648-8B4544F8C605', -- "Entity": "MJ_BizApps_Tasks_GitHub": "Git" "Hub" "Issue" "Tasks"
        (SELECT COALESCE(MAX("Sequence"), 0) + 1 FROM ${mjSchema}."EntityField" WHERE "EntityID" = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605'),
        'GitHubUpdatedAt',
        'Git Hub Updated At',
        'Upstream updated_at timestamp reported by GitHub.',
        'TIMESTAMPTZ',
        10,
        34,
        7,
        TRUE,
        NULL,
        FALSE,
        TRUE,
        FALSE,
        FALSE,
        NULL,
        NULL,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        'Search',
        NOW(),
        NOW()
        );
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM ${mjSchema}."EntityField" WHERE "ID" = '8d123f90-1cd8-42e3-a8bf-c121be46401b' OR ("EntityID" = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605' AND "Name" = 'LastSyncedAt')
    ) THEN
        INSERT INTO ${mjSchema}."EntityField"
        (
        "ID",
        "EntityID",
        "Sequence",
        "Name",
        "DisplayName",
        "Description",
        "Type",
        "Length",
        "Precision",
        "Scale",
        "AllowsNull",
        "DefaultValue",
        "AutoIncrement",
        "AllowUpdateAPI",
        "IsVirtual",
        "IsComputed",
        "RelatedEntityID",
        "RelatedEntityFieldName",
        "IsNameField",
        "IncludeInUserSearchAPI",
        "IncludeRelatedEntityNameFieldInBaseView",
        "DefaultInView",
        "IsPrimaryKey",
        "IsUnique",
        "RelatedEntityDisplayType",
        "__mj_CreatedAt",
        "__mj_UpdatedAt"
        )
        VALUES
        (
        '8d123f90-1cd8-42e3-a8bf-c121be46401b',
        'DC8E0F5B-E172-4FD5-B648-8B4544F8C605', -- "Entity": "MJ_BizApps_Tasks_GitHub": "Git" "Hub" "Issue" "Tasks"
        (SELECT COALESCE(MAX("Sequence"), 0) + 1 FROM ${mjSchema}."EntityField" WHERE "EntityID" = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605'),
        'LastSyncedAt',
        'Last Synced At',
        'Timestamp when BizApps Tasks GitHub sync last reconciled this issue.',
        'TIMESTAMPTZ',
        10,
        34,
        7,
        TRUE,
        NULL,
        FALSE,
        TRUE,
        FALSE,
        FALSE,
        NULL,
        NULL,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        'Search',
        NOW(),
        NOW()
        );
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM ${mjSchema}."EntityField" WHERE "ID" = 'dec034d1-627f-4099-84d9-71ebd162acbd' OR ("EntityID" = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605' AND "Name" = '__mj_CreatedAt')
    ) THEN
        INSERT INTO ${mjSchema}."EntityField"
        (
        "ID",
        "EntityID",
        "Sequence",
        "Name",
        "DisplayName",
        "Description",
        "Type",
        "Length",
        "Precision",
        "Scale",
        "AllowsNull",
        "DefaultValue",
        "AutoIncrement",
        "AllowUpdateAPI",
        "IsVirtual",
        "IsComputed",
        "RelatedEntityID",
        "RelatedEntityFieldName",
        "IsNameField",
        "IncludeInUserSearchAPI",
        "IncludeRelatedEntityNameFieldInBaseView",
        "DefaultInView",
        "IsPrimaryKey",
        "IsUnique",
        "RelatedEntityDisplayType",
        "__mj_CreatedAt",
        "__mj_UpdatedAt"
        )
        VALUES
        (
        'dec034d1-627f-4099-84d9-71ebd162acbd',
        'DC8E0F5B-E172-4FD5-B648-8B4544F8C605', -- "Entity": "MJ_BizApps_Tasks_GitHub": "Git" "Hub" "Issue" "Tasks"
        (SELECT COALESCE(MAX("Sequence"), 0) + 1 FROM ${mjSchema}."EntityField" WHERE "EntityID" = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605'),
        '__mj_CreatedAt',
        'Created At',
        NULL,
        'TIMESTAMPTZ',
        10,
        34,
        7,
        FALSE,
        'NOW()',
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        NULL,
        NULL,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        'Search',
        NOW(),
        NOW()
        );
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM ${mjSchema}."EntityField" WHERE "ID" = 'f846083a-3f9a-4728-86d8-6772a47ac54e' OR ("EntityID" = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605' AND "Name" = '__mj_UpdatedAt')
    ) THEN
        INSERT INTO ${mjSchema}."EntityField"
        (
        "ID",
        "EntityID",
        "Sequence",
        "Name",
        "DisplayName",
        "Description",
        "Type",
        "Length",
        "Precision",
        "Scale",
        "AllowsNull",
        "DefaultValue",
        "AutoIncrement",
        "AllowUpdateAPI",
        "IsVirtual",
        "IsComputed",
        "RelatedEntityID",
        "RelatedEntityFieldName",
        "IsNameField",
        "IncludeInUserSearchAPI",
        "IncludeRelatedEntityNameFieldInBaseView",
        "DefaultInView",
        "IsPrimaryKey",
        "IsUnique",
        "RelatedEntityDisplayType",
        "__mj_CreatedAt",
        "__mj_UpdatedAt"
        )
        VALUES
        (
        'f846083a-3f9a-4728-86d8-6772a47ac54e',
        'DC8E0F5B-E172-4FD5-B648-8B4544F8C605', -- "Entity": "MJ_BizApps_Tasks_GitHub": "Git" "Hub" "Issue" "Tasks"
        (SELECT COALESCE(MAX("Sequence"), 0) + 1 FROM ${mjSchema}."EntityField" WHERE "EntityID" = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605'),
        '__mj_UpdatedAt',
        'Updated At',
        NULL,
        'TIMESTAMPTZ',
        10,
        34,
        7,
        FALSE,
        'NOW()',
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        NULL,
        NULL,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        'Search',
        NOW(),
        NOW()
        );
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM ${mjSchema}."EntityField" WHERE "ID" = '14420024-8d4c-43fb-b3c2-c335cfdca13f' OR ("EntityID" = 'C7CC2BCF-090E-4832-89C7-A051F302C393' AND "Name" = 'ID')
    ) THEN
        INSERT INTO ${mjSchema}."EntityField"
        (
        "ID",
        "EntityID",
        "Sequence",
        "Name",
        "DisplayName",
        "Description",
        "Type",
        "Length",
        "Precision",
        "Scale",
        "AllowsNull",
        "DefaultValue",
        "AutoIncrement",
        "AllowUpdateAPI",
        "IsVirtual",
        "IsComputed",
        "RelatedEntityID",
        "RelatedEntityFieldName",
        "IsNameField",
        "IncludeInUserSearchAPI",
        "IncludeRelatedEntityNameFieldInBaseView",
        "DefaultInView",
        "IsPrimaryKey",
        "IsUnique",
        "RelatedEntityDisplayType",
        "__mj_CreatedAt",
        "__mj_UpdatedAt"
        )
        VALUES
        (
        '14420024-8d4c-43fb-b3c2-c335cfdca13f',
        'C7CC2BCF-090E-4832-89C7-A051F302C393', -- "Entity": "MJ_BizApps_Tasks_GitHub": "Git" "Hub" "Identities"
        (SELECT COALESCE(MAX("Sequence"), 0) + 1 FROM ${mjSchema}."EntityField" WHERE "EntityID" = 'C7CC2BCF-090E-4832-89C7-A051F302C393'),
        'ID',
        'ID',
        NULL,
        'UUID',
        16,
        0,
        0,
        FALSE,
        'gen_random_uuid()',
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        NULL,
        NULL,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        TRUE,
        TRUE,
        'Search',
        NOW(),
        NOW()
        );
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM ${mjSchema}."EntityField" WHERE "ID" = '2680087d-c275-43f1-8a02-eb2fac64624c' OR ("EntityID" = 'C7CC2BCF-090E-4832-89C7-A051F302C393' AND "Name" = 'GitHubLogin')
    ) THEN
        INSERT INTO ${mjSchema}."EntityField"
        (
        "ID",
        "EntityID",
        "Sequence",
        "Name",
        "DisplayName",
        "Description",
        "Type",
        "Length",
        "Precision",
        "Scale",
        "AllowsNull",
        "DefaultValue",
        "AutoIncrement",
        "AllowUpdateAPI",
        "IsVirtual",
        "IsComputed",
        "RelatedEntityID",
        "RelatedEntityFieldName",
        "IsNameField",
        "IncludeInUserSearchAPI",
        "IncludeRelatedEntityNameFieldInBaseView",
        "DefaultInView",
        "IsPrimaryKey",
        "IsUnique",
        "RelatedEntityDisplayType",
        "__mj_CreatedAt",
        "__mj_UpdatedAt"
        )
        VALUES
        (
        '2680087d-c275-43f1-8a02-eb2fac64624c',
        'C7CC2BCF-090E-4832-89C7-A051F302C393', -- "Entity": "MJ_BizApps_Tasks_GitHub": "Git" "Hub" "Identities"
        (SELECT COALESCE(MAX("Sequence"), 0) + 1 FROM ${mjSchema}."EntityField" WHERE "EntityID" = 'C7CC2BCF-090E-4832-89C7-A051F302C393'),
        'GitHubLogin',
        'Git Hub Login',
        'Case-insensitive GitHub username / handle (e.g. octocat).',
        'TEXT',
        200,
        0,
        0,
        FALSE,
        NULL,
        FALSE,
        TRUE,
        FALSE,
        FALSE,
        NULL,
        NULL,
        FALSE,
        FALSE,
        FALSE,
        TRUE,
        FALSE,
        TRUE,
        'Search',
        NOW(),
        NOW()
        );
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM ${mjSchema}."EntityField" WHERE "ID" = '86923f31-a619-4171-9700-360d0f84eaee' OR ("EntityID" = 'C7CC2BCF-090E-4832-89C7-A051F302C393' AND "Name" = 'PersonID')
    ) THEN
        INSERT INTO ${mjSchema}."EntityField"
        (
        "ID",
        "EntityID",
        "Sequence",
        "Name",
        "DisplayName",
        "Description",
        "Type",
        "Length",
        "Precision",
        "Scale",
        "AllowsNull",
        "DefaultValue",
        "AutoIncrement",
        "AllowUpdateAPI",
        "IsVirtual",
        "IsComputed",
        "RelatedEntityID",
        "RelatedEntityFieldName",
        "IsNameField",
        "IncludeInUserSearchAPI",
        "IncludeRelatedEntityNameFieldInBaseView",
        "DefaultInView",
        "IsPrimaryKey",
        "IsUnique",
        "RelatedEntityDisplayType",
        "__mj_CreatedAt",
        "__mj_UpdatedAt"
        )
        VALUES
        (
        '86923f31-a619-4171-9700-360d0f84eaee',
        'C7CC2BCF-090E-4832-89C7-A051F302C393', -- "Entity": "MJ_BizApps_Tasks_GitHub": "Git" "Hub" "Identities"
        (SELECT COALESCE(MAX("Sequence"), 0) + 1 FROM ${mjSchema}."EntityField" WHERE "EntityID" = 'C7CC2BCF-090E-4832-89C7-A051F302C393'),
        'PersonID',
        'Person ID',
        'Target BizApps Common Person record associated with this GitHub login.',
        'UUID',
        16,
        0,
        0,
        FALSE,
        NULL,
        FALSE,
        TRUE,
        FALSE,
        FALSE,
        '7A94ADA9-7880-4FAE-97D8-DB0E934C3F5F',
        'ID',
        FALSE,
        FALSE,
        TRUE,
        FALSE,
        FALSE,
        FALSE,
        'Search',
        NOW(),
        NOW()
        );
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM ${mjSchema}."EntityField" WHERE "ID" = 'da3ff8e3-9102-4bdc-9747-2c1b92282829' OR ("EntityID" = 'C7CC2BCF-090E-4832-89C7-A051F302C393' AND "Name" = 'GitHubUserID')
    ) THEN
        INSERT INTO ${mjSchema}."EntityField"
        (
        "ID",
        "EntityID",
        "Sequence",
        "Name",
        "DisplayName",
        "Description",
        "Type",
        "Length",
        "Precision",
        "Scale",
        "AllowsNull",
        "DefaultValue",
        "AutoIncrement",
        "AllowUpdateAPI",
        "IsVirtual",
        "IsComputed",
        "RelatedEntityID",
        "RelatedEntityFieldName",
        "IsNameField",
        "IncludeInUserSearchAPI",
        "IncludeRelatedEntityNameFieldInBaseView",
        "DefaultInView",
        "IsPrimaryKey",
        "IsUnique",
        "RelatedEntityDisplayType",
        "__mj_CreatedAt",
        "__mj_UpdatedAt"
        )
        VALUES
        (
        'da3ff8e3-9102-4bdc-9747-2c1b92282829',
        'C7CC2BCF-090E-4832-89C7-A051F302C393', -- "Entity": "MJ_BizApps_Tasks_GitHub": "Git" "Hub" "Identities"
        (SELECT COALESCE(MAX("Sequence"), 0) + 1 FROM ${mjSchema}."EntityField" WHERE "EntityID" = 'C7CC2BCF-090E-4832-89C7-A051F302C393'),
        'GitHubUserID',
        'Git Hub User ID',
        'Optional numeric or GraphQL node identifier for the GitHub user account.',
        'TEXT',
        128,
        0,
        0,
        TRUE,
        NULL,
        FALSE,
        TRUE,
        FALSE,
        FALSE,
        NULL,
        NULL,
        FALSE,
        FALSE,
        FALSE,
        TRUE,
        FALSE,
        FALSE,
        'Search',
        NOW(),
        NOW()
        );
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM ${mjSchema}."EntityField" WHERE "ID" = '859b1d57-888e-4f5e-9394-11927fcde8ca' OR ("EntityID" = 'C7CC2BCF-090E-4832-89C7-A051F302C393' AND "Name" = 'IsActive')
    ) THEN
        INSERT INTO ${mjSchema}."EntityField"
        (
        "ID",
        "EntityID",
        "Sequence",
        "Name",
        "DisplayName",
        "Description",
        "Type",
        "Length",
        "Precision",
        "Scale",
        "AllowsNull",
        "DefaultValue",
        "AutoIncrement",
        "AllowUpdateAPI",
        "IsVirtual",
        "IsComputed",
        "RelatedEntityID",
        "RelatedEntityFieldName",
        "IsNameField",
        "IncludeInUserSearchAPI",
        "IncludeRelatedEntityNameFieldInBaseView",
        "DefaultInView",
        "IsPrimaryKey",
        "IsUnique",
        "RelatedEntityDisplayType",
        "__mj_CreatedAt",
        "__mj_UpdatedAt"
        )
        VALUES
        (
        '859b1d57-888e-4f5e-9394-11927fcde8ca',
        'C7CC2BCF-090E-4832-89C7-A051F302C393', -- "Entity": "MJ_BizApps_Tasks_GitHub": "Git" "Hub" "Identities"
        (SELECT COALESCE(MAX("Sequence"), 0) + 1 FROM ${mjSchema}."EntityField" WHERE "EntityID" = 'C7CC2BCF-090E-4832-89C7-A051F302C393'),
        'IsActive',
        'Is Active',
        'Whether this login mapping is currently active for task import and assignment resolution.',
        'BOOLEAN',
        1,
        1,
        0,
        FALSE,
        '(1)',
        FALSE,
        TRUE,
        FALSE,
        FALSE,
        NULL,
        NULL,
        FALSE,
        FALSE,
        FALSE,
        TRUE,
        FALSE,
        FALSE,
        'Search',
        NOW(),
        NOW()
        );
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM ${mjSchema}."EntityField" WHERE "ID" = '0f52c847-41b4-44f5-9ff7-83df5bfc74d9' OR ("EntityID" = 'C7CC2BCF-090E-4832-89C7-A051F302C393' AND "Name" = '__mj_CreatedAt')
    ) THEN
        INSERT INTO ${mjSchema}."EntityField"
        (
        "ID",
        "EntityID",
        "Sequence",
        "Name",
        "DisplayName",
        "Description",
        "Type",
        "Length",
        "Precision",
        "Scale",
        "AllowsNull",
        "DefaultValue",
        "AutoIncrement",
        "AllowUpdateAPI",
        "IsVirtual",
        "IsComputed",
        "RelatedEntityID",
        "RelatedEntityFieldName",
        "IsNameField",
        "IncludeInUserSearchAPI",
        "IncludeRelatedEntityNameFieldInBaseView",
        "DefaultInView",
        "IsPrimaryKey",
        "IsUnique",
        "RelatedEntityDisplayType",
        "__mj_CreatedAt",
        "__mj_UpdatedAt"
        )
        VALUES
        (
        '0f52c847-41b4-44f5-9ff7-83df5bfc74d9',
        'C7CC2BCF-090E-4832-89C7-A051F302C393', -- "Entity": "MJ_BizApps_Tasks_GitHub": "Git" "Hub" "Identities"
        (SELECT COALESCE(MAX("Sequence"), 0) + 1 FROM ${mjSchema}."EntityField" WHERE "EntityID" = 'C7CC2BCF-090E-4832-89C7-A051F302C393'),
        '__mj_CreatedAt',
        'Created At',
        NULL,
        'TIMESTAMPTZ',
        10,
        34,
        7,
        FALSE,
        'NOW()',
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        NULL,
        NULL,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        'Search',
        NOW(),
        NOW()
        );
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM ${mjSchema}."EntityField" WHERE "ID" = '168eed29-3b45-4398-973f-71a7da22e916' OR ("EntityID" = 'C7CC2BCF-090E-4832-89C7-A051F302C393' AND "Name" = '__mj_UpdatedAt')
    ) THEN
        INSERT INTO ${mjSchema}."EntityField"
        (
        "ID",
        "EntityID",
        "Sequence",
        "Name",
        "DisplayName",
        "Description",
        "Type",
        "Length",
        "Precision",
        "Scale",
        "AllowsNull",
        "DefaultValue",
        "AutoIncrement",
        "AllowUpdateAPI",
        "IsVirtual",
        "IsComputed",
        "RelatedEntityID",
        "RelatedEntityFieldName",
        "IsNameField",
        "IncludeInUserSearchAPI",
        "IncludeRelatedEntityNameFieldInBaseView",
        "DefaultInView",
        "IsPrimaryKey",
        "IsUnique",
        "RelatedEntityDisplayType",
        "__mj_CreatedAt",
        "__mj_UpdatedAt"
        )
        VALUES
        (
        '168eed29-3b45-4398-973f-71a7da22e916',
        'C7CC2BCF-090E-4832-89C7-A051F302C393', -- "Entity": "MJ_BizApps_Tasks_GitHub": "Git" "Hub" "Identities"
        (SELECT COALESCE(MAX("Sequence"), 0) + 1 FROM ${mjSchema}."EntityField" WHERE "EntityID" = 'C7CC2BCF-090E-4832-89C7-A051F302C393'),
        '__mj_UpdatedAt',
        'Updated At',
        NULL,
        'TIMESTAMPTZ',
        10,
        34,
        7,
        FALSE,
        'NOW()',
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        NULL,
        NULL,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        'Search',
        NOW(),
        NOW()
        );
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM ${mjSchema}."EntityField" WHERE "ID" = '4afbf1a3-202b-4657-938b-652ef047768f' OR ("EntityID" = 'A6B673F8-43BC-4875-AFF6-AC620592822E' AND "Name" = 'ID')
    ) THEN
        INSERT INTO ${mjSchema}."EntityField"
        (
        "ID",
        "EntityID",
        "Sequence",
        "Name",
        "DisplayName",
        "Description",
        "Type",
        "Length",
        "Precision",
        "Scale",
        "AllowsNull",
        "DefaultValue",
        "AutoIncrement",
        "AllowUpdateAPI",
        "IsVirtual",
        "IsComputed",
        "RelatedEntityID",
        "RelatedEntityFieldName",
        "IsNameField",
        "IncludeInUserSearchAPI",
        "IncludeRelatedEntityNameFieldInBaseView",
        "DefaultInView",
        "IsPrimaryKey",
        "IsUnique",
        "RelatedEntityDisplayType",
        "__mj_CreatedAt",
        "__mj_UpdatedAt"
        )
        VALUES
        (
        '4afbf1a3-202b-4657-938b-652ef047768f',
        'A6B673F8-43BC-4875-AFF6-AC620592822E', -- "Entity": "MJ_BizApps_Tasks_GitHub": "Git" "Hub" "Pull" "Request" "Tasks"
        (SELECT COALESCE(MAX("Sequence"), 0) + 1 FROM ${mjSchema}."EntityField" WHERE "EntityID" = 'A6B673F8-43BC-4875-AFF6-AC620592822E'),
        'ID',
        'ID',
        'Shared primary key referencing __mj_BizAppsTasks.Task(ID).',
        'UUID',
        16,
        0,
        0,
        FALSE,
        NULL,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        'B348FFA2-B1A7-4AC2-B6FD-F4E0C0697466',
        'ID',
        FALSE,
        FALSE,
        TRUE,
        FALSE,
        TRUE,
        TRUE,
        'Search',
        NOW(),
        NOW()
        );
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM ${mjSchema}."EntityField" WHERE "ID" = '80c22b8d-1383-4ac3-bc9d-6540c3fded78' OR ("EntityID" = 'A6B673F8-43BC-4875-AFF6-AC620592822E' AND "Name" = 'RepositoryID')
    ) THEN
        INSERT INTO ${mjSchema}."EntityField"
        (
        "ID",
        "EntityID",
        "Sequence",
        "Name",
        "DisplayName",
        "Description",
        "Type",
        "Length",
        "Precision",
        "Scale",
        "AllowsNull",
        "DefaultValue",
        "AutoIncrement",
        "AllowUpdateAPI",
        "IsVirtual",
        "IsComputed",
        "RelatedEntityID",
        "RelatedEntityFieldName",
        "IsNameField",
        "IncludeInUserSearchAPI",
        "IncludeRelatedEntityNameFieldInBaseView",
        "DefaultInView",
        "IsPrimaryKey",
        "IsUnique",
        "RelatedEntityDisplayType",
        "__mj_CreatedAt",
        "__mj_UpdatedAt"
        )
        VALUES
        (
        '80c22b8d-1383-4ac3-bc9d-6540c3fded78',
        'A6B673F8-43BC-4875-AFF6-AC620592822E', -- "Entity": "MJ_BizApps_Tasks_GitHub": "Git" "Hub" "Pull" "Request" "Tasks"
        (SELECT COALESCE(MAX("Sequence"), 0) + 1 FROM ${mjSchema}."EntityField" WHERE "EntityID" = 'A6B673F8-43BC-4875-AFF6-AC620592822E'),
        'RepositoryID',
        'Repository ID',
        'GitHubRepository to which this pull request belongs.',
        'UUID',
        16,
        0,
        0,
        TRUE,
        NULL,
        FALSE,
        TRUE,
        FALSE,
        FALSE,
        '6B363236-31AB-477D-8188-08F5FA9942EF',
        'ID',
        FALSE,
        FALSE,
        TRUE,
        FALSE,
        FALSE,
        TRUE,
        'Search',
        NOW(),
        NOW()
        );
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM ${mjSchema}."EntityField" WHERE "ID" = 'd0157ce0-e6ee-41d6-828d-f774b96ab24c' OR ("EntityID" = 'A6B673F8-43BC-4875-AFF6-AC620592822E' AND "Name" = 'Number')
    ) THEN
        INSERT INTO ${mjSchema}."EntityField"
        (
        "ID",
        "EntityID",
        "Sequence",
        "Name",
        "DisplayName",
        "Description",
        "Type",
        "Length",
        "Precision",
        "Scale",
        "AllowsNull",
        "DefaultValue",
        "AutoIncrement",
        "AllowUpdateAPI",
        "IsVirtual",
        "IsComputed",
        "RelatedEntityID",
        "RelatedEntityFieldName",
        "IsNameField",
        "IncludeInUserSearchAPI",
        "IncludeRelatedEntityNameFieldInBaseView",
        "DefaultInView",
        "IsPrimaryKey",
        "IsUnique",
        "RelatedEntityDisplayType",
        "__mj_CreatedAt",
        "__mj_UpdatedAt"
        )
        VALUES
        (
        'd0157ce0-e6ee-41d6-828d-f774b96ab24c',
        'A6B673F8-43BC-4875-AFF6-AC620592822E', -- "Entity": "MJ_BizApps_Tasks_GitHub": "Git" "Hub" "Pull" "Request" "Tasks"
        (SELECT COALESCE(MAX("Sequence"), 0) + 1 FROM ${mjSchema}."EntityField" WHERE "EntityID" = 'A6B673F8-43BC-4875-AFF6-AC620592822E'),
        'Number',
        'Number',
        'Repository-scoped GitHub pull request number (#N). Unique per RepositoryID when populated.',
        'INTEGER',
        4,
        10,
        0,
        TRUE,
        NULL,
        FALSE,
        TRUE,
        FALSE,
        FALSE,
        NULL,
        NULL,
        FALSE,
        FALSE,
        FALSE,
        TRUE,
        FALSE,
        TRUE,
        'Search',
        NOW(),
        NOW()
        );
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM ${mjSchema}."EntityField" WHERE "ID" = '07679af9-e8a9-4aeb-ad5c-2cb9ba40a3f4' OR ("EntityID" = 'A6B673F8-43BC-4875-AFF6-AC620592822E' AND "Name" = 'NodeID')
    ) THEN
        INSERT INTO ${mjSchema}."EntityField"
        (
        "ID",
        "EntityID",
        "Sequence",
        "Name",
        "DisplayName",
        "Description",
        "Type",
        "Length",
        "Precision",
        "Scale",
        "AllowsNull",
        "DefaultValue",
        "AutoIncrement",
        "AllowUpdateAPI",
        "IsVirtual",
        "IsComputed",
        "RelatedEntityID",
        "RelatedEntityFieldName",
        "IsNameField",
        "IncludeInUserSearchAPI",
        "IncludeRelatedEntityNameFieldInBaseView",
        "DefaultInView",
        "IsPrimaryKey",
        "IsUnique",
        "RelatedEntityDisplayType",
        "__mj_CreatedAt",
        "__mj_UpdatedAt"
        )
        VALUES
        (
        '07679af9-e8a9-4aeb-ad5c-2cb9ba40a3f4',
        'A6B673F8-43BC-4875-AFF6-AC620592822E', -- "Entity": "MJ_BizApps_Tasks_GitHub": "Git" "Hub" "Pull" "Request" "Tasks"
        (SELECT COALESCE(MAX("Sequence"), 0) + 1 FROM ${mjSchema}."EntityField" WHERE "EntityID" = 'A6B673F8-43BC-4875-AFF6-AC620592822E'),
        'NodeID',
        'Node ID',
        'Global GitHub GraphQL node identifier for idempotent sync.',
        'TEXT',
        256,
        0,
        0,
        TRUE,
        NULL,
        FALSE,
        TRUE,
        FALSE,
        FALSE,
        NULL,
        NULL,
        FALSE,
        FALSE,
        FALSE,
        TRUE,
        FALSE,
        TRUE,
        'Search',
        NOW(),
        NOW()
        );
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM ${mjSchema}."EntityField" WHERE "ID" = 'f2598281-767d-423e-b92a-3000708efe1a' OR ("EntityID" = 'A6B673F8-43BC-4875-AFF6-AC620592822E' AND "Name" = 'HtmlURL')
    ) THEN
        INSERT INTO ${mjSchema}."EntityField"
        (
        "ID",
        "EntityID",
        "Sequence",
        "Name",
        "DisplayName",
        "Description",
        "Type",
        "Length",
        "Precision",
        "Scale",
        "AllowsNull",
        "DefaultValue",
        "AutoIncrement",
        "AllowUpdateAPI",
        "IsVirtual",
        "IsComputed",
        "RelatedEntityID",
        "RelatedEntityFieldName",
        "IsNameField",
        "IncludeInUserSearchAPI",
        "IncludeRelatedEntityNameFieldInBaseView",
        "DefaultInView",
        "IsPrimaryKey",
        "IsUnique",
        "RelatedEntityDisplayType",
        "__mj_CreatedAt",
        "__mj_UpdatedAt"
        )
        VALUES
        (
        'f2598281-767d-423e-b92a-3000708efe1a',
        'A6B673F8-43BC-4875-AFF6-AC620592822E', -- "Entity": "MJ_BizApps_Tasks_GitHub": "Git" "Hub" "Pull" "Request" "Tasks"
        (SELECT COALESCE(MAX("Sequence"), 0) + 1 FROM ${mjSchema}."EntityField" WHERE "EntityID" = 'A6B673F8-43BC-4875-AFF6-AC620592822E'),
        'HtmlURL',
        'Html URL',
        'Canonical browser URL to view or review the pull request on GitHub.',
        'TEXT',
        2000,
        0,
        0,
        TRUE,
        NULL,
        FALSE,
        TRUE,
        FALSE,
        FALSE,
        NULL,
        NULL,
        FALSE,
        FALSE,
        FALSE,
        TRUE,
        FALSE,
        FALSE,
        'Search',
        NOW(),
        NOW()
        );
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM ${mjSchema}."EntityField" WHERE "ID" = '5cbfaabd-0af2-4e67-91b1-f089e6c56c4d' OR ("EntityID" = 'A6B673F8-43BC-4875-AFF6-AC620592822E' AND "Name" = 'State')
    ) THEN
        INSERT INTO ${mjSchema}."EntityField"
        (
        "ID",
        "EntityID",
        "Sequence",
        "Name",
        "DisplayName",
        "Description",
        "Type",
        "Length",
        "Precision",
        "Scale",
        "AllowsNull",
        "DefaultValue",
        "AutoIncrement",
        "AllowUpdateAPI",
        "IsVirtual",
        "IsComputed",
        "RelatedEntityID",
        "RelatedEntityFieldName",
        "IsNameField",
        "IncludeInUserSearchAPI",
        "IncludeRelatedEntityNameFieldInBaseView",
        "DefaultInView",
        "IsPrimaryKey",
        "IsUnique",
        "RelatedEntityDisplayType",
        "__mj_CreatedAt",
        "__mj_UpdatedAt"
        )
        VALUES
        (
        '5cbfaabd-0af2-4e67-91b1-f089e6c56c4d',
        'A6B673F8-43BC-4875-AFF6-AC620592822E', -- "Entity": "MJ_BizApps_Tasks_GitHub": "Git" "Hub" "Pull" "Request" "Tasks"
        (SELECT COALESCE(MAX("Sequence"), 0) + 1 FROM ${mjSchema}."EntityField" WHERE "EntityID" = 'A6B673F8-43BC-4875-AFF6-AC620592822E'),
        'State',
        'State',
        'Pull request lifecycle state on GitHub (open, closed, or merged).',
        'TEXT',
        40,
        0,
        0,
        FALSE,
        'open',
        FALSE,
        TRUE,
        FALSE,
        FALSE,
        NULL,
        NULL,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        'Search',
        NOW(),
        NOW()
        );
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM ${mjSchema}."EntityField" WHERE "ID" = '6702784e-ce7d-41dd-a906-6958e5415a5d' OR ("EntityID" = 'A6B673F8-43BC-4875-AFF6-AC620592822E' AND "Name" = 'IsDraft')
    ) THEN
        INSERT INTO ${mjSchema}."EntityField"
        (
        "ID",
        "EntityID",
        "Sequence",
        "Name",
        "DisplayName",
        "Description",
        "Type",
        "Length",
        "Precision",
        "Scale",
        "AllowsNull",
        "DefaultValue",
        "AutoIncrement",
        "AllowUpdateAPI",
        "IsVirtual",
        "IsComputed",
        "RelatedEntityID",
        "RelatedEntityFieldName",
        "IsNameField",
        "IncludeInUserSearchAPI",
        "IncludeRelatedEntityNameFieldInBaseView",
        "DefaultInView",
        "IsPrimaryKey",
        "IsUnique",
        "RelatedEntityDisplayType",
        "__mj_CreatedAt",
        "__mj_UpdatedAt"
        )
        VALUES
        (
        '6702784e-ce7d-41dd-a906-6958e5415a5d',
        'A6B673F8-43BC-4875-AFF6-AC620592822E', -- "Entity": "MJ_BizApps_Tasks_GitHub": "Git" "Hub" "Pull" "Request" "Tasks"
        (SELECT COALESCE(MAX("Sequence"), 0) + 1 FROM ${mjSchema}."EntityField" WHERE "EntityID" = 'A6B673F8-43BC-4875-AFF6-AC620592822E'),
        'IsDraft',
        'Is Draft',
        'Whether the pull request is currently marked as a Draft on GitHub.',
        'BOOLEAN',
        1,
        1,
        0,
        FALSE,
        '(0)',
        FALSE,
        TRUE,
        FALSE,
        FALSE,
        NULL,
        NULL,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        'Search',
        NOW(),
        NOW()
        );
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM ${mjSchema}."EntityField" WHERE "ID" = '6a042282-8dc0-4158-b972-f2eff37c1387' OR ("EntityID" = 'A6B673F8-43BC-4875-AFF6-AC620592822E' AND "Name" = 'HeadBranch')
    ) THEN
        INSERT INTO ${mjSchema}."EntityField"
        (
        "ID",
        "EntityID",
        "Sequence",
        "Name",
        "DisplayName",
        "Description",
        "Type",
        "Length",
        "Precision",
        "Scale",
        "AllowsNull",
        "DefaultValue",
        "AutoIncrement",
        "AllowUpdateAPI",
        "IsVirtual",
        "IsComputed",
        "RelatedEntityID",
        "RelatedEntityFieldName",
        "IsNameField",
        "IncludeInUserSearchAPI",
        "IncludeRelatedEntityNameFieldInBaseView",
        "DefaultInView",
        "IsPrimaryKey",
        "IsUnique",
        "RelatedEntityDisplayType",
        "__mj_CreatedAt",
        "__mj_UpdatedAt"
        )
        VALUES
        (
        '6a042282-8dc0-4158-b972-f2eff37c1387',
        'A6B673F8-43BC-4875-AFF6-AC620592822E', -- "Entity": "MJ_BizApps_Tasks_GitHub": "Git" "Hub" "Pull" "Request" "Tasks"
        (SELECT COALESCE(MAX("Sequence"), 0) + 1 FROM ${mjSchema}."EntityField" WHERE "EntityID" = 'A6B673F8-43BC-4875-AFF6-AC620592822E'),
        'HeadBranch',
        'Head Branch',
        'Source branch ref of the pull request (head.ref).',
        'TEXT',
        510,
        0,
        0,
        TRUE,
        NULL,
        FALSE,
        TRUE,
        FALSE,
        FALSE,
        NULL,
        NULL,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        'Search',
        NOW(),
        NOW()
        );
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM ${mjSchema}."EntityField" WHERE "ID" = '68d879e4-6123-482d-8637-a6b7e250b9cb' OR ("EntityID" = 'A6B673F8-43BC-4875-AFF6-AC620592822E' AND "Name" = 'HeadSha')
    ) THEN
        INSERT INTO ${mjSchema}."EntityField"
        (
        "ID",
        "EntityID",
        "Sequence",
        "Name",
        "DisplayName",
        "Description",
        "Type",
        "Length",
        "Precision",
        "Scale",
        "AllowsNull",
        "DefaultValue",
        "AutoIncrement",
        "AllowUpdateAPI",
        "IsVirtual",
        "IsComputed",
        "RelatedEntityID",
        "RelatedEntityFieldName",
        "IsNameField",
        "IncludeInUserSearchAPI",
        "IncludeRelatedEntityNameFieldInBaseView",
        "DefaultInView",
        "IsPrimaryKey",
        "IsUnique",
        "RelatedEntityDisplayType",
        "__mj_CreatedAt",
        "__mj_UpdatedAt"
        )
        VALUES
        (
        '68d879e4-6123-482d-8637-a6b7e250b9cb',
        'A6B673F8-43BC-4875-AFF6-AC620592822E', -- "Entity": "MJ_BizApps_Tasks_GitHub": "Git" "Hub" "Pull" "Request" "Tasks"
        (SELECT COALESCE(MAX("Sequence"), 0) + 1 FROM ${mjSchema}."EntityField" WHERE "EntityID" = 'A6B673F8-43BC-4875-AFF6-AC620592822E'),
        'HeadSha',
        'Head Sha',
        'Commit SHA at the tip of HeadBranch (head.sha), verified by Software Factory merge gates.',
        'TEXT',
        128,
        0,
        0,
        TRUE,
        NULL,
        FALSE,
        TRUE,
        FALSE,
        FALSE,
        NULL,
        NULL,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        'Search',
        NOW(),
        NOW()
        );
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM ${mjSchema}."EntityField" WHERE "ID" = '8d2db26a-0621-4a94-a932-a4c1f47e1dcf' OR ("EntityID" = 'A6B673F8-43BC-4875-AFF6-AC620592822E' AND "Name" = 'BaseBranch')
    ) THEN
        INSERT INTO ${mjSchema}."EntityField"
        (
        "ID",
        "EntityID",
        "Sequence",
        "Name",
        "DisplayName",
        "Description",
        "Type",
        "Length",
        "Precision",
        "Scale",
        "AllowsNull",
        "DefaultValue",
        "AutoIncrement",
        "AllowUpdateAPI",
        "IsVirtual",
        "IsComputed",
        "RelatedEntityID",
        "RelatedEntityFieldName",
        "IsNameField",
        "IncludeInUserSearchAPI",
        "IncludeRelatedEntityNameFieldInBaseView",
        "DefaultInView",
        "IsPrimaryKey",
        "IsUnique",
        "RelatedEntityDisplayType",
        "__mj_CreatedAt",
        "__mj_UpdatedAt"
        )
        VALUES
        (
        '8d2db26a-0621-4a94-a932-a4c1f47e1dcf',
        'A6B673F8-43BC-4875-AFF6-AC620592822E', -- "Entity": "MJ_BizApps_Tasks_GitHub": "Git" "Hub" "Pull" "Request" "Tasks"
        (SELECT COALESCE(MAX("Sequence"), 0) + 1 FROM ${mjSchema}."EntityField" WHERE "EntityID" = 'A6B673F8-43BC-4875-AFF6-AC620592822E'),
        'BaseBranch',
        'Base Branch',
        'Target branch ref into which the pull request merges (base.ref).',
        'TEXT',
        510,
        0,
        0,
        TRUE,
        NULL,
        FALSE,
        TRUE,
        FALSE,
        FALSE,
        NULL,
        NULL,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        'Search',
        NOW(),
        NOW()
        );
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM ${mjSchema}."EntityField" WHERE "ID" = 'debaddf7-a747-400c-bec1-8a93fddf6193' OR ("EntityID" = 'A6B673F8-43BC-4875-AFF6-AC620592822E' AND "Name" = 'AuthorLogin')
    ) THEN
        INSERT INTO ${mjSchema}."EntityField"
        (
        "ID",
        "EntityID",
        "Sequence",
        "Name",
        "DisplayName",
        "Description",
        "Type",
        "Length",
        "Precision",
        "Scale",
        "AllowsNull",
        "DefaultValue",
        "AutoIncrement",
        "AllowUpdateAPI",
        "IsVirtual",
        "IsComputed",
        "RelatedEntityID",
        "RelatedEntityFieldName",
        "IsNameField",
        "IncludeInUserSearchAPI",
        "IncludeRelatedEntityNameFieldInBaseView",
        "DefaultInView",
        "IsPrimaryKey",
        "IsUnique",
        "RelatedEntityDisplayType",
        "__mj_CreatedAt",
        "__mj_UpdatedAt"
        )
        VALUES
        (
        'debaddf7-a747-400c-bec1-8a93fddf6193',
        'A6B673F8-43BC-4875-AFF6-AC620592822E', -- "Entity": "MJ_BizApps_Tasks_GitHub": "Git" "Hub" "Pull" "Request" "Tasks"
        (SELECT COALESCE(MAX("Sequence"), 0) + 1 FROM ${mjSchema}."EntityField" WHERE "EntityID" = 'A6B673F8-43BC-4875-AFF6-AC620592822E'),
        'AuthorLogin',
        'Author Login',
        'GitHub login of the pull request author.',
        'TEXT',
        200,
        0,
        0,
        TRUE,
        NULL,
        FALSE,
        TRUE,
        FALSE,
        FALSE,
        NULL,
        NULL,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        'Search',
        NOW(),
        NOW()
        );
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM ${mjSchema}."EntityField" WHERE "ID" = 'd0242db3-acfc-4ad6-9b8a-7af48e27bbe4' OR ("EntityID" = 'A6B673F8-43BC-4875-AFF6-AC620592822E' AND "Name" = 'ReviewDecision')
    ) THEN
        INSERT INTO ${mjSchema}."EntityField"
        (
        "ID",
        "EntityID",
        "Sequence",
        "Name",
        "DisplayName",
        "Description",
        "Type",
        "Length",
        "Precision",
        "Scale",
        "AllowsNull",
        "DefaultValue",
        "AutoIncrement",
        "AllowUpdateAPI",
        "IsVirtual",
        "IsComputed",
        "RelatedEntityID",
        "RelatedEntityFieldName",
        "IsNameField",
        "IncludeInUserSearchAPI",
        "IncludeRelatedEntityNameFieldInBaseView",
        "DefaultInView",
        "IsPrimaryKey",
        "IsUnique",
        "RelatedEntityDisplayType",
        "__mj_CreatedAt",
        "__mj_UpdatedAt"
        )
        VALUES
        (
        'd0242db3-acfc-4ad6-9b8a-7af48e27bbe4',
        'A6B673F8-43BC-4875-AFF6-AC620592822E', -- "Entity": "MJ_BizApps_Tasks_GitHub": "Git" "Hub" "Pull" "Request" "Tasks"
        (SELECT COALESCE(MAX("Sequence"), 0) + 1 FROM ${mjSchema}."EntityField" WHERE "EntityID" = 'A6B673F8-43BC-4875-AFF6-AC620592822E'),
        'ReviewDecision',
        'Review Decision',
        'Aggregated GitHub review decision (APPROVED, CHANGES_REQUESTED, or REVIEW_REQUIRED).',
        'TEXT',
        80,
        0,
        0,
        TRUE,
        NULL,
        FALSE,
        TRUE,
        FALSE,
        FALSE,
        NULL,
        NULL,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        'Search',
        NOW(),
        NOW()
        );
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM ${mjSchema}."EntityField" WHERE "ID" = '57b97f3b-7437-49c3-a2a3-89f8f14f3224' OR ("EntityID" = 'A6B673F8-43BC-4875-AFF6-AC620592822E' AND "Name" = 'ChecksStatus')
    ) THEN
        INSERT INTO ${mjSchema}."EntityField"
        (
        "ID",
        "EntityID",
        "Sequence",
        "Name",
        "DisplayName",
        "Description",
        "Type",
        "Length",
        "Precision",
        "Scale",
        "AllowsNull",
        "DefaultValue",
        "AutoIncrement",
        "AllowUpdateAPI",
        "IsVirtual",
        "IsComputed",
        "RelatedEntityID",
        "RelatedEntityFieldName",
        "IsNameField",
        "IncludeInUserSearchAPI",
        "IncludeRelatedEntityNameFieldInBaseView",
        "DefaultInView",
        "IsPrimaryKey",
        "IsUnique",
        "RelatedEntityDisplayType",
        "__mj_CreatedAt",
        "__mj_UpdatedAt"
        )
        VALUES
        (
        '57b97f3b-7437-49c3-a2a3-89f8f14f3224',
        'A6B673F8-43BC-4875-AFF6-AC620592822E', -- "Entity": "MJ_BizApps_Tasks_GitHub": "Git" "Hub" "Pull" "Request" "Tasks"
        (SELECT COALESCE(MAX("Sequence"), 0) + 1 FROM ${mjSchema}."EntityField" WHERE "EntityID" = 'A6B673F8-43BC-4875-AFF6-AC620592822E'),
        'ChecksStatus',
        'Checks Status',
        'Aggregated status of required GitHub CI checks on HeadSha (Pending, Passing, Failing, Neutral).',
        'TEXT',
        60,
        0,
        0,
        TRUE,
        NULL,
        FALSE,
        TRUE,
        FALSE,
        FALSE,
        NULL,
        NULL,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        'Search',
        NOW(),
        NOW()
        );
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM ${mjSchema}."EntityField" WHERE "ID" = 'c43679af-0136-4312-bfc7-50a774a1df96' OR ("EntityID" = 'A6B673F8-43BC-4875-AFF6-AC620592822E' AND "Name" = 'ChangedFiles')
    ) THEN
        INSERT INTO ${mjSchema}."EntityField"
        (
        "ID",
        "EntityID",
        "Sequence",
        "Name",
        "DisplayName",
        "Description",
        "Type",
        "Length",
        "Precision",
        "Scale",
        "AllowsNull",
        "DefaultValue",
        "AutoIncrement",
        "AllowUpdateAPI",
        "IsVirtual",
        "IsComputed",
        "RelatedEntityID",
        "RelatedEntityFieldName",
        "IsNameField",
        "IncludeInUserSearchAPI",
        "IncludeRelatedEntityNameFieldInBaseView",
        "DefaultInView",
        "IsPrimaryKey",
        "IsUnique",
        "RelatedEntityDisplayType",
        "__mj_CreatedAt",
        "__mj_UpdatedAt"
        )
        VALUES
        (
        'c43679af-0136-4312-bfc7-50a774a1df96',
        'A6B673F8-43BC-4875-AFF6-AC620592822E', -- "Entity": "MJ_BizApps_Tasks_GitHub": "Git" "Hub" "Pull" "Request" "Tasks"
        (SELECT COALESCE(MAX("Sequence"), 0) + 1 FROM ${mjSchema}."EntityField" WHERE "EntityID" = 'A6B673F8-43BC-4875-AFF6-AC620592822E'),
        'ChangedFiles',
        'Changed Files',
        'Number of files touched in the pull request diff.',
        'INTEGER',
        4,
        10,
        0,
        TRUE,
        NULL,
        FALSE,
        TRUE,
        FALSE,
        FALSE,
        NULL,
        NULL,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        'Search',
        NOW(),
        NOW()
        );
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM ${mjSchema}."EntityField" WHERE "ID" = 'e7c6d6dd-3b2c-4d1f-854c-36ec48ea6541' OR ("EntityID" = 'A6B673F8-43BC-4875-AFF6-AC620592822E' AND "Name" = 'Additions')
    ) THEN
        INSERT INTO ${mjSchema}."EntityField"
        (
        "ID",
        "EntityID",
        "Sequence",
        "Name",
        "DisplayName",
        "Description",
        "Type",
        "Length",
        "Precision",
        "Scale",
        "AllowsNull",
        "DefaultValue",
        "AutoIncrement",
        "AllowUpdateAPI",
        "IsVirtual",
        "IsComputed",
        "RelatedEntityID",
        "RelatedEntityFieldName",
        "IsNameField",
        "IncludeInUserSearchAPI",
        "IncludeRelatedEntityNameFieldInBaseView",
        "DefaultInView",
        "IsPrimaryKey",
        "IsUnique",
        "RelatedEntityDisplayType",
        "__mj_CreatedAt",
        "__mj_UpdatedAt"
        )
        VALUES
        (
        'e7c6d6dd-3b2c-4d1f-854c-36ec48ea6541',
        'A6B673F8-43BC-4875-AFF6-AC620592822E', -- "Entity": "MJ_BizApps_Tasks_GitHub": "Git" "Hub" "Pull" "Request" "Tasks"
        (SELECT COALESCE(MAX("Sequence"), 0) + 1 FROM ${mjSchema}."EntityField" WHERE "EntityID" = 'A6B673F8-43BC-4875-AFF6-AC620592822E'),
        'Additions',
        'Additions',
        'Lines added in the pull request diff.',
        'INTEGER',
        4,
        10,
        0,
        TRUE,
        NULL,
        FALSE,
        TRUE,
        FALSE,
        FALSE,
        NULL,
        NULL,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        'Search',
        NOW(),
        NOW()
        );
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM ${mjSchema}."EntityField" WHERE "ID" = '79a88aca-735f-4126-af8c-e84e0eab6dbe' OR ("EntityID" = 'A6B673F8-43BC-4875-AFF6-AC620592822E' AND "Name" = 'Deletions')
    ) THEN
        INSERT INTO ${mjSchema}."EntityField"
        (
        "ID",
        "EntityID",
        "Sequence",
        "Name",
        "DisplayName",
        "Description",
        "Type",
        "Length",
        "Precision",
        "Scale",
        "AllowsNull",
        "DefaultValue",
        "AutoIncrement",
        "AllowUpdateAPI",
        "IsVirtual",
        "IsComputed",
        "RelatedEntityID",
        "RelatedEntityFieldName",
        "IsNameField",
        "IncludeInUserSearchAPI",
        "IncludeRelatedEntityNameFieldInBaseView",
        "DefaultInView",
        "IsPrimaryKey",
        "IsUnique",
        "RelatedEntityDisplayType",
        "__mj_CreatedAt",
        "__mj_UpdatedAt"
        )
        VALUES
        (
        '79a88aca-735f-4126-af8c-e84e0eab6dbe',
        'A6B673F8-43BC-4875-AFF6-AC620592822E', -- "Entity": "MJ_BizApps_Tasks_GitHub": "Git" "Hub" "Pull" "Request" "Tasks"
        (SELECT COALESCE(MAX("Sequence"), 0) + 1 FROM ${mjSchema}."EntityField" WHERE "EntityID" = 'A6B673F8-43BC-4875-AFF6-AC620592822E'),
        'Deletions',
        'Deletions',
        'Lines deleted in the pull request diff.',
        'INTEGER',
        4,
        10,
        0,
        TRUE,
        NULL,
        FALSE,
        TRUE,
        FALSE,
        FALSE,
        NULL,
        NULL,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        'Search',
        NOW(),
        NOW()
        );
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM ${mjSchema}."EntityField" WHERE "ID" = '88926596-fb58-4ab7-aef8-3bcb7f927b0a' OR ("EntityID" = 'A6B673F8-43BC-4875-AFF6-AC620592822E' AND "Name" = 'Labels')
    ) THEN
        INSERT INTO ${mjSchema}."EntityField"
        (
        "ID",
        "EntityID",
        "Sequence",
        "Name",
        "DisplayName",
        "Description",
        "Type",
        "Length",
        "Precision",
        "Scale",
        "AllowsNull",
        "DefaultValue",
        "AutoIncrement",
        "AllowUpdateAPI",
        "IsVirtual",
        "IsComputed",
        "RelatedEntityID",
        "RelatedEntityFieldName",
        "IsNameField",
        "IncludeInUserSearchAPI",
        "IncludeRelatedEntityNameFieldInBaseView",
        "DefaultInView",
        "IsPrimaryKey",
        "IsUnique",
        "RelatedEntityDisplayType",
        "__mj_CreatedAt",
        "__mj_UpdatedAt"
        )
        VALUES
        (
        '88926596-fb58-4ab7-aef8-3bcb7f927b0a',
        'A6B673F8-43BC-4875-AFF6-AC620592822E', -- "Entity": "MJ_BizApps_Tasks_GitHub": "Git" "Hub" "Pull" "Request" "Tasks"
        (SELECT COALESCE(MAX("Sequence"), 0) + 1 FROM ${mjSchema}."EntityField" WHERE "EntityID" = 'A6B673F8-43BC-4875-AFF6-AC620592822E'),
        'Labels',
        'Labels',
        'JSON array of GitHub label names applied to the pull request.',
        'TEXT',
        -1,
        0,
        0,
        TRUE,
        NULL,
        FALSE,
        TRUE,
        FALSE,
        FALSE,
        NULL,
        NULL,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        'Search',
        NOW(),
        NOW()
        );
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM ${mjSchema}."EntityField" WHERE "ID" = '3a7bdb54-1596-447c-b919-0dba77bf1988' OR ("EntityID" = 'A6B673F8-43BC-4875-AFF6-AC620592822E' AND "Name" = 'Milestone')
    ) THEN
        INSERT INTO ${mjSchema}."EntityField"
        (
        "ID",
        "EntityID",
        "Sequence",
        "Name",
        "DisplayName",
        "Description",
        "Type",
        "Length",
        "Precision",
        "Scale",
        "AllowsNull",
        "DefaultValue",
        "AutoIncrement",
        "AllowUpdateAPI",
        "IsVirtual",
        "IsComputed",
        "RelatedEntityID",
        "RelatedEntityFieldName",
        "IsNameField",
        "IncludeInUserSearchAPI",
        "IncludeRelatedEntityNameFieldInBaseView",
        "DefaultInView",
        "IsPrimaryKey",
        "IsUnique",
        "RelatedEntityDisplayType",
        "__mj_CreatedAt",
        "__mj_UpdatedAt"
        )
        VALUES
        (
        '3a7bdb54-1596-447c-b919-0dba77bf1988',
        'A6B673F8-43BC-4875-AFF6-AC620592822E', -- "Entity": "MJ_BizApps_Tasks_GitHub": "Git" "Hub" "Pull" "Request" "Tasks"
        (SELECT COALESCE(MAX("Sequence"), 0) + 1 FROM ${mjSchema}."EntityField" WHERE "EntityID" = 'A6B673F8-43BC-4875-AFF6-AC620592822E'),
        'Milestone',
        'Milestone',
        'GitHub milestone title when assigned.',
        'TEXT',
        510,
        0,
        0,
        TRUE,
        NULL,
        FALSE,
        TRUE,
        FALSE,
        FALSE,
        NULL,
        NULL,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        'Search',
        NOW(),
        NOW()
        );
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM ${mjSchema}."EntityField" WHERE "ID" = '4ccf1bdd-f21d-4003-8499-9a1d6c9c02e2' OR ("EntityID" = 'A6B673F8-43BC-4875-AFF6-AC620592822E' AND "Name" = 'MilestoneDueAt')
    ) THEN
        INSERT INTO ${mjSchema}."EntityField"
        (
        "ID",
        "EntityID",
        "Sequence",
        "Name",
        "DisplayName",
        "Description",
        "Type",
        "Length",
        "Precision",
        "Scale",
        "AllowsNull",
        "DefaultValue",
        "AutoIncrement",
        "AllowUpdateAPI",
        "IsVirtual",
        "IsComputed",
        "RelatedEntityID",
        "RelatedEntityFieldName",
        "IsNameField",
        "IncludeInUserSearchAPI",
        "IncludeRelatedEntityNameFieldInBaseView",
        "DefaultInView",
        "IsPrimaryKey",
        "IsUnique",
        "RelatedEntityDisplayType",
        "__mj_CreatedAt",
        "__mj_UpdatedAt"
        )
        VALUES
        (
        '4ccf1bdd-f21d-4003-8499-9a1d6c9c02e2',
        'A6B673F8-43BC-4875-AFF6-AC620592822E', -- "Entity": "MJ_BizApps_Tasks_GitHub": "Git" "Hub" "Pull" "Request" "Tasks"
        (SELECT COALESCE(MAX("Sequence"), 0) + 1 FROM ${mjSchema}."EntityField" WHERE "EntityID" = 'A6B673F8-43BC-4875-AFF6-AC620592822E'),
        'MilestoneDueAt',
        'Milestone Due At',
        'Due timestamp of the GitHub milestone; supersedes pending inferred DueAt Field Suggestions.',
        'TIMESTAMPTZ',
        10,
        34,
        7,
        TRUE,
        NULL,
        FALSE,
        TRUE,
        FALSE,
        FALSE,
        NULL,
        NULL,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        'Search',
        NOW(),
        NOW()
        );
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM ${mjSchema}."EntityField" WHERE "ID" = '4801e8b7-847b-411d-b5f0-002551b4f237' OR ("EntityID" = 'A6B673F8-43BC-4875-AFF6-AC620592822E' AND "Name" = 'MergedAt')
    ) THEN
        INSERT INTO ${mjSchema}."EntityField"
        (
        "ID",
        "EntityID",
        "Sequence",
        "Name",
        "DisplayName",
        "Description",
        "Type",
        "Length",
        "Precision",
        "Scale",
        "AllowsNull",
        "DefaultValue",
        "AutoIncrement",
        "AllowUpdateAPI",
        "IsVirtual",
        "IsComputed",
        "RelatedEntityID",
        "RelatedEntityFieldName",
        "IsNameField",
        "IncludeInUserSearchAPI",
        "IncludeRelatedEntityNameFieldInBaseView",
        "DefaultInView",
        "IsPrimaryKey",
        "IsUnique",
        "RelatedEntityDisplayType",
        "__mj_CreatedAt",
        "__mj_UpdatedAt"
        )
        VALUES
        (
        '4801e8b7-847b-411d-b5f0-002551b4f237',
        'A6B673F8-43BC-4875-AFF6-AC620592822E', -- "Entity": "MJ_BizApps_Tasks_GitHub": "Git" "Hub" "Pull" "Request" "Tasks"
        (SELECT COALESCE(MAX("Sequence"), 0) + 1 FROM ${mjSchema}."EntityField" WHERE "EntityID" = 'A6B673F8-43BC-4875-AFF6-AC620592822E'),
        'MergedAt',
        'Merged At',
        'Timestamp when the pull request was merged on GitHub.',
        'TIMESTAMPTZ',
        10,
        34,
        7,
        TRUE,
        NULL,
        FALSE,
        TRUE,
        FALSE,
        FALSE,
        NULL,
        NULL,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        'Search',
        NOW(),
        NOW()
        );
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM ${mjSchema}."EntityField" WHERE "ID" = 'af64dc8d-5285-46a8-a44b-145bda229838' OR ("EntityID" = 'A6B673F8-43BC-4875-AFF6-AC620592822E' AND "Name" = 'LinkedIssueTaskID')
    ) THEN
        INSERT INTO ${mjSchema}."EntityField"
        (
        "ID",
        "EntityID",
        "Sequence",
        "Name",
        "DisplayName",
        "Description",
        "Type",
        "Length",
        "Precision",
        "Scale",
        "AllowsNull",
        "DefaultValue",
        "AutoIncrement",
        "AllowUpdateAPI",
        "IsVirtual",
        "IsComputed",
        "RelatedEntityID",
        "RelatedEntityFieldName",
        "IsNameField",
        "IncludeInUserSearchAPI",
        "IncludeRelatedEntityNameFieldInBaseView",
        "DefaultInView",
        "IsPrimaryKey",
        "IsUnique",
        "RelatedEntityDisplayType",
        "__mj_CreatedAt",
        "__mj_UpdatedAt"
        )
        VALUES
        (
        'af64dc8d-5285-46a8-a44b-145bda229838',
        'A6B673F8-43BC-4875-AFF6-AC620592822E', -- "Entity": "MJ_BizApps_Tasks_GitHub": "Git" "Hub" "Pull" "Request" "Tasks"
        (SELECT COALESCE(MAX("Sequence"), 0) + 1 FROM ${mjSchema}."EntityField" WHERE "EntityID" = 'A6B673F8-43BC-4875-AFF6-AC620592822E'),
        'LinkedIssueTaskID',
        'Linked Issue Task ID',
        'Optional reference to the Task (e.g. GITHUB_ISSUE or FACTORY_WORK) that this pull request implements or closes.',
        'UUID',
        16,
        0,
        0,
        TRUE,
        NULL,
        FALSE,
        TRUE,
        FALSE,
        FALSE,
        'B348FFA2-B1A7-4AC2-B6FD-F4E0C0697466',
        'ID',
        FALSE,
        FALSE,
        TRUE,
        FALSE,
        FALSE,
        FALSE,
        'Search',
        NOW(),
        NOW()
        );
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM ${mjSchema}."EntityField" WHERE "ID" = '6e18bab8-7f3d-42c0-ac47-d1ccb685a2e0' OR ("EntityID" = 'A6B673F8-43BC-4875-AFF6-AC620592822E' AND "Name" = 'BodyHash')
    ) THEN
        INSERT INTO ${mjSchema}."EntityField"
        (
        "ID",
        "EntityID",
        "Sequence",
        "Name",
        "DisplayName",
        "Description",
        "Type",
        "Length",
        "Precision",
        "Scale",
        "AllowsNull",
        "DefaultValue",
        "AutoIncrement",
        "AllowUpdateAPI",
        "IsVirtual",
        "IsComputed",
        "RelatedEntityID",
        "RelatedEntityFieldName",
        "IsNameField",
        "IncludeInUserSearchAPI",
        "IncludeRelatedEntityNameFieldInBaseView",
        "DefaultInView",
        "IsPrimaryKey",
        "IsUnique",
        "RelatedEntityDisplayType",
        "__mj_CreatedAt",
        "__mj_UpdatedAt"
        )
        VALUES
        (
        '6e18bab8-7f3d-42c0-ac47-d1ccb685a2e0',
        'A6B673F8-43BC-4875-AFF6-AC620592822E', -- "Entity": "MJ_BizApps_Tasks_GitHub": "Git" "Hub" "Pull" "Request" "Tasks"
        (SELECT COALESCE(MAX("Sequence"), 0) + 1 FROM ${mjSchema}."EntityField" WHERE "EntityID" = 'A6B673F8-43BC-4875-AFF6-AC620592822E'),
        'BodyHash',
        'Body Hash',
        'SHA-256 hash of the last synced pull request body used to detect text edits and trigger Field Suggestion re-inference.',
        'TEXT',
        128,
        0,
        0,
        TRUE,
        NULL,
        FALSE,
        TRUE,
        FALSE,
        FALSE,
        NULL,
        NULL,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        'Search',
        NOW(),
        NOW()
        );
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM ${mjSchema}."EntityField" WHERE "ID" = 'cfa8847f-9404-4b62-810f-863dd426852b' OR ("EntityID" = 'A6B673F8-43BC-4875-AFF6-AC620592822E' AND "Name" = 'GitHubUpdatedAt')
    ) THEN
        INSERT INTO ${mjSchema}."EntityField"
        (
        "ID",
        "EntityID",
        "Sequence",
        "Name",
        "DisplayName",
        "Description",
        "Type",
        "Length",
        "Precision",
        "Scale",
        "AllowsNull",
        "DefaultValue",
        "AutoIncrement",
        "AllowUpdateAPI",
        "IsVirtual",
        "IsComputed",
        "RelatedEntityID",
        "RelatedEntityFieldName",
        "IsNameField",
        "IncludeInUserSearchAPI",
        "IncludeRelatedEntityNameFieldInBaseView",
        "DefaultInView",
        "IsPrimaryKey",
        "IsUnique",
        "RelatedEntityDisplayType",
        "__mj_CreatedAt",
        "__mj_UpdatedAt"
        )
        VALUES
        (
        'cfa8847f-9404-4b62-810f-863dd426852b',
        'A6B673F8-43BC-4875-AFF6-AC620592822E', -- "Entity": "MJ_BizApps_Tasks_GitHub": "Git" "Hub" "Pull" "Request" "Tasks"
        (SELECT COALESCE(MAX("Sequence"), 0) + 1 FROM ${mjSchema}."EntityField" WHERE "EntityID" = 'A6B673F8-43BC-4875-AFF6-AC620592822E'),
        'GitHubUpdatedAt',
        'Git Hub Updated At',
        'Upstream updated_at timestamp reported by GitHub.',
        'TIMESTAMPTZ',
        10,
        34,
        7,
        TRUE,
        NULL,
        FALSE,
        TRUE,
        FALSE,
        FALSE,
        NULL,
        NULL,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        'Search',
        NOW(),
        NOW()
        );
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM ${mjSchema}."EntityField" WHERE "ID" = '4e1457ac-6957-44b9-baf9-93c09114807e' OR ("EntityID" = 'A6B673F8-43BC-4875-AFF6-AC620592822E' AND "Name" = 'LastSyncedAt')
    ) THEN
        INSERT INTO ${mjSchema}."EntityField"
        (
        "ID",
        "EntityID",
        "Sequence",
        "Name",
        "DisplayName",
        "Description",
        "Type",
        "Length",
        "Precision",
        "Scale",
        "AllowsNull",
        "DefaultValue",
        "AutoIncrement",
        "AllowUpdateAPI",
        "IsVirtual",
        "IsComputed",
        "RelatedEntityID",
        "RelatedEntityFieldName",
        "IsNameField",
        "IncludeInUserSearchAPI",
        "IncludeRelatedEntityNameFieldInBaseView",
        "DefaultInView",
        "IsPrimaryKey",
        "IsUnique",
        "RelatedEntityDisplayType",
        "__mj_CreatedAt",
        "__mj_UpdatedAt"
        )
        VALUES
        (
        '4e1457ac-6957-44b9-baf9-93c09114807e',
        'A6B673F8-43BC-4875-AFF6-AC620592822E', -- "Entity": "MJ_BizApps_Tasks_GitHub": "Git" "Hub" "Pull" "Request" "Tasks"
        (SELECT COALESCE(MAX("Sequence"), 0) + 1 FROM ${mjSchema}."EntityField" WHERE "EntityID" = 'A6B673F8-43BC-4875-AFF6-AC620592822E'),
        'LastSyncedAt',
        'Last Synced At',
        'Timestamp when BizApps Tasks GitHub sync last reconciled this pull request.',
        'TIMESTAMPTZ',
        10,
        34,
        7,
        TRUE,
        NULL,
        FALSE,
        TRUE,
        FALSE,
        FALSE,
        NULL,
        NULL,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        'Search',
        NOW(),
        NOW()
        );
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM ${mjSchema}."EntityField" WHERE "ID" = '5d5a0e69-1ed4-4863-a611-34bf239fa515' OR ("EntityID" = 'A6B673F8-43BC-4875-AFF6-AC620592822E' AND "Name" = '__mj_CreatedAt')
    ) THEN
        INSERT INTO ${mjSchema}."EntityField"
        (
        "ID",
        "EntityID",
        "Sequence",
        "Name",
        "DisplayName",
        "Description",
        "Type",
        "Length",
        "Precision",
        "Scale",
        "AllowsNull",
        "DefaultValue",
        "AutoIncrement",
        "AllowUpdateAPI",
        "IsVirtual",
        "IsComputed",
        "RelatedEntityID",
        "RelatedEntityFieldName",
        "IsNameField",
        "IncludeInUserSearchAPI",
        "IncludeRelatedEntityNameFieldInBaseView",
        "DefaultInView",
        "IsPrimaryKey",
        "IsUnique",
        "RelatedEntityDisplayType",
        "__mj_CreatedAt",
        "__mj_UpdatedAt"
        )
        VALUES
        (
        '5d5a0e69-1ed4-4863-a611-34bf239fa515',
        'A6B673F8-43BC-4875-AFF6-AC620592822E', -- "Entity": "MJ_BizApps_Tasks_GitHub": "Git" "Hub" "Pull" "Request" "Tasks"
        (SELECT COALESCE(MAX("Sequence"), 0) + 1 FROM ${mjSchema}."EntityField" WHERE "EntityID" = 'A6B673F8-43BC-4875-AFF6-AC620592822E'),
        '__mj_CreatedAt',
        'Created At',
        NULL,
        'TIMESTAMPTZ',
        10,
        34,
        7,
        FALSE,
        'NOW()',
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        NULL,
        NULL,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        'Search',
        NOW(),
        NOW()
        );
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM ${mjSchema}."EntityField" WHERE "ID" = 'f3a56a47-49d7-4e66-b762-aedc7f65dbdb' OR ("EntityID" = 'A6B673F8-43BC-4875-AFF6-AC620592822E' AND "Name" = '__mj_UpdatedAt')
    ) THEN
        INSERT INTO ${mjSchema}."EntityField"
        (
        "ID",
        "EntityID",
        "Sequence",
        "Name",
        "DisplayName",
        "Description",
        "Type",
        "Length",
        "Precision",
        "Scale",
        "AllowsNull",
        "DefaultValue",
        "AutoIncrement",
        "AllowUpdateAPI",
        "IsVirtual",
        "IsComputed",
        "RelatedEntityID",
        "RelatedEntityFieldName",
        "IsNameField",
        "IncludeInUserSearchAPI",
        "IncludeRelatedEntityNameFieldInBaseView",
        "DefaultInView",
        "IsPrimaryKey",
        "IsUnique",
        "RelatedEntityDisplayType",
        "__mj_CreatedAt",
        "__mj_UpdatedAt"
        )
        VALUES
        (
        'f3a56a47-49d7-4e66-b762-aedc7f65dbdb',
        'A6B673F8-43BC-4875-AFF6-AC620592822E', -- "Entity": "MJ_BizApps_Tasks_GitHub": "Git" "Hub" "Pull" "Request" "Tasks"
        (SELECT COALESCE(MAX("Sequence"), 0) + 1 FROM ${mjSchema}."EntityField" WHERE "EntityID" = 'A6B673F8-43BC-4875-AFF6-AC620592822E'),
        '__mj_UpdatedAt',
        'Updated At',
        NULL,
        'TIMESTAMPTZ',
        10,
        34,
        7,
        FALSE,
        'NOW()',
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        NULL,
        NULL,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        'Search',
        NOW(),
        NOW()
        );
    END IF;
END $$;

INSERT INTO ${mjSchema}."EntityFieldValue"
                                       ("ID", "EntityFieldID", "Sequence", "Value", "Code", "Source", "__mj_CreatedAt", "__mj_UpdatedAt")
                                    VALUES
                                       ('8c8c3982-1b02-4d76-9c3f-61f557196fde', 'D09CC770-1CBB-4078-8186-BF3ED875F03C', 1, 'All', 'All', 'Check', NOW(), NOW());

/* SQL text to insert entity field value with ID ba996e4d-b437-484f-9b69-0b2c5a335417 */

INSERT INTO ${mjSchema}."EntityFieldValue"
                                       ("ID", "EntityFieldID", "Sequence", "Value", "Code", "Source", "__mj_CreatedAt", "__mj_UpdatedAt")
                                    VALUES
                                       ('ba996e4d-b437-484f-9b69-0b2c5a335417', 'D09CC770-1CBB-4078-8186-BF3ED875F03C', 2, 'AssignedOnly', 'AssignedOnly', 'Check', NOW(), NOW());

/* SQL text to update ValueListType for entity field ID D09CC770-1CBB-4078-8186-BF3ED875F03C */

UPDATE ${mjSchema}."EntityField" SET "ValueListType"='List' WHERE "ID"='D09CC770-1CBB-4078-8186-BF3ED875F03C';

/* SQL text to insert entity field value with ID 1b5b4514-5903-4025-bbe6-429b39a20d88 */

INSERT INTO ${mjSchema}."EntityFieldValue"
                                       ("ID", "EntityFieldID", "Sequence", "Value", "Code", "Source", "__mj_CreatedAt", "__mj_UpdatedAt")
                                    VALUES
                                       ('1b5b4514-5903-4025-bbe6-429b39a20d88', '54CD3BC9-E3DF-4B33-9413-B2F137EB2452', 1, 'closed', 'closed', 'Check', NOW(), NOW());

/* SQL text to insert entity field value with ID bc36d270-d78c-4704-8705-ee4ca7a1f4b9 */

INSERT INTO ${mjSchema}."EntityFieldValue"
                                       ("ID", "EntityFieldID", "Sequence", "Value", "Code", "Source", "__mj_CreatedAt", "__mj_UpdatedAt")
                                    VALUES
                                       ('bc36d270-d78c-4704-8705-ee4ca7a1f4b9', '54CD3BC9-E3DF-4B33-9413-B2F137EB2452', 2, 'open', 'open', 'Check', NOW(), NOW());

/* SQL text to update ValueListType for entity field ID 54CD3BC9-E3DF-4B33-9413-B2F137EB2452 */

UPDATE ${mjSchema}."EntityField" SET "ValueListType"='List' WHERE "ID"='54CD3BC9-E3DF-4B33-9413-B2F137EB2452';

/* SQL text to insert entity field value with ID d4d4b560-1b25-49cb-b29e-bd1281de3a90 */

INSERT INTO ${mjSchema}."EntityFieldValue"
                                       ("ID", "EntityFieldID", "Sequence", "Value", "Code", "Source", "__mj_CreatedAt", "__mj_UpdatedAt")
                                    VALUES
                                       ('d4d4b560-1b25-49cb-b29e-bd1281de3a90', 'AC27EB42-F18D-4444-99A2-9E454DBAEB49', 1, 'completed', 'completed', 'Check', NOW(), NOW());

/* SQL text to insert entity field value with ID f9f7b77e-670b-450e-94d6-d5bc4750bc24 */

INSERT INTO ${mjSchema}."EntityFieldValue"
                                       ("ID", "EntityFieldID", "Sequence", "Value", "Code", "Source", "__mj_CreatedAt", "__mj_UpdatedAt")
                                    VALUES
                                       ('f9f7b77e-670b-450e-94d6-d5bc4750bc24', 'AC27EB42-F18D-4444-99A2-9E454DBAEB49', 2, 'duplicate', 'duplicate', 'Check', NOW(), NOW());

/* SQL text to insert entity field value with ID 97b353b7-4df6-47e8-9e6a-657bd3c02695 */

INSERT INTO ${mjSchema}."EntityFieldValue"
                                       ("ID", "EntityFieldID", "Sequence", "Value", "Code", "Source", "__mj_CreatedAt", "__mj_UpdatedAt")
                                    VALUES
                                       ('97b353b7-4df6-47e8-9e6a-657bd3c02695', 'AC27EB42-F18D-4444-99A2-9E454DBAEB49', 3, 'not_planned', 'not_planned', 'Check', NOW(), NOW());

/* SQL text to insert entity field value with ID 93d0898d-073f-4845-8ead-36ed4383899e */

INSERT INTO ${mjSchema}."EntityFieldValue"
                                       ("ID", "EntityFieldID", "Sequence", "Value", "Code", "Source", "__mj_CreatedAt", "__mj_UpdatedAt")
                                    VALUES
                                       ('93d0898d-073f-4845-8ead-36ed4383899e', 'AC27EB42-F18D-4444-99A2-9E454DBAEB49', 4, 'reopened', 'reopened', 'Check', NOW(), NOW());

/* SQL text to update ValueListType for entity field ID AC27EB42-F18D-4444-99A2-9E454DBAEB49 */

UPDATE ${mjSchema}."EntityField" SET "ValueListType"='List' WHERE "ID"='AC27EB42-F18D-4444-99A2-9E454DBAEB49';

/* SQL text to insert entity field value with ID 10d2ab58-e633-4bc9-a41d-defb3eac7ffd */

INSERT INTO ${mjSchema}."EntityFieldValue"
                                       ("ID", "EntityFieldID", "Sequence", "Value", "Code", "Source", "__mj_CreatedAt", "__mj_UpdatedAt")
                                    VALUES
                                       ('10d2ab58-e633-4bc9-a41d-defb3eac7ffd', '5CBFAABD-0AF2-4E67-91B1-F089E6C56C4D', 1, 'closed', 'closed', 'Check', NOW(), NOW());

/* SQL text to insert entity field value with ID 7e5a5659-0e7b-4eac-b6b6-b0c32ad144f0 */

INSERT INTO ${mjSchema}."EntityFieldValue"
                                       ("ID", "EntityFieldID", "Sequence", "Value", "Code", "Source", "__mj_CreatedAt", "__mj_UpdatedAt")
                                    VALUES
                                       ('7e5a5659-0e7b-4eac-b6b6-b0c32ad144f0', '5CBFAABD-0AF2-4E67-91B1-F089E6C56C4D', 2, 'merged', 'merged', 'Check', NOW(), NOW());

/* SQL text to insert entity field value with ID 9b11894a-bec6-4f7e-8e64-ce143b88276f */

INSERT INTO ${mjSchema}."EntityFieldValue"
                                       ("ID", "EntityFieldID", "Sequence", "Value", "Code", "Source", "__mj_CreatedAt", "__mj_UpdatedAt")
                                    VALUES
                                       ('9b11894a-bec6-4f7e-8e64-ce143b88276f', '5CBFAABD-0AF2-4E67-91B1-F089E6C56C4D', 3, 'open', 'open', 'Check', NOW(), NOW());

/* SQL text to update ValueListType for entity field ID 5CBFAABD-0AF2-4E67-91B1-F089E6C56C4D */

UPDATE ${mjSchema}."EntityField" SET "ValueListType"='List' WHERE "ID"='5CBFAABD-0AF2-4E67-91B1-F089E6C56C4D';

/* SQL text to insert entity field value with ID ed759dfa-1781-4f43-92b2-cc725ecf4a19 */

INSERT INTO ${mjSchema}."EntityFieldValue"
                                       ("ID", "EntityFieldID", "Sequence", "Value", "Code", "Source", "__mj_CreatedAt", "__mj_UpdatedAt")
                                    VALUES
                                       ('ed759dfa-1781-4f43-92b2-cc725ecf4a19', 'D0242DB3-ACFC-4AD6-9B8A-7AF48E27BBE4', 1, 'APPROVED', 'APPROVED', 'Check', NOW(), NOW());

/* SQL text to insert entity field value with ID be4c345c-aa49-4bb2-a197-5541fa02a4d9 */

INSERT INTO ${mjSchema}."EntityFieldValue"
                                       ("ID", "EntityFieldID", "Sequence", "Value", "Code", "Source", "__mj_CreatedAt", "__mj_UpdatedAt")
                                    VALUES
                                       ('be4c345c-aa49-4bb2-a197-5541fa02a4d9', 'D0242DB3-ACFC-4AD6-9B8A-7AF48E27BBE4', 2, 'CHANGES_REQUESTED', 'CHANGES_REQUESTED', 'Check', NOW(), NOW());

/* SQL text to insert entity field value with ID 78463bdd-98f6-4aab-b237-c1ea739f6ed4 */

INSERT INTO ${mjSchema}."EntityFieldValue"
                                       ("ID", "EntityFieldID", "Sequence", "Value", "Code", "Source", "__mj_CreatedAt", "__mj_UpdatedAt")
                                    VALUES
                                       ('78463bdd-98f6-4aab-b237-c1ea739f6ed4', 'D0242DB3-ACFC-4AD6-9B8A-7AF48E27BBE4', 3, 'REVIEW_REQUIRED', 'REVIEW_REQUIRED', 'Check', NOW(), NOW());

/* SQL text to update ValueListType for entity field ID D0242DB3-ACFC-4AD6-9B8A-7AF48E27BBE4 */

UPDATE ${mjSchema}."EntityField" SET "ValueListType"='List' WHERE "ID"='D0242DB3-ACFC-4AD6-9B8A-7AF48E27BBE4';

/* SQL text to insert entity field value with ID b22540b8-fe08-407d-9660-f3ea4c96d295 */

INSERT INTO ${mjSchema}."EntityFieldValue"
                                       ("ID", "EntityFieldID", "Sequence", "Value", "Code", "Source", "__mj_CreatedAt", "__mj_UpdatedAt")
                                    VALUES
                                       ('b22540b8-fe08-407d-9660-f3ea4c96d295', '57B97F3B-7437-49C3-A2A3-89F8F14F3224', 1, 'Failing', 'Failing', 'Check', NOW(), NOW());

/* SQL text to insert entity field value with ID a61af79c-cbce-4957-b745-553788b8d3e9 */

INSERT INTO ${mjSchema}."EntityFieldValue"
                                       ("ID", "EntityFieldID", "Sequence", "Value", "Code", "Source", "__mj_CreatedAt", "__mj_UpdatedAt")
                                    VALUES
                                       ('a61af79c-cbce-4957-b745-553788b8d3e9', '57B97F3B-7437-49C3-A2A3-89F8F14F3224', 2, 'Neutral', 'Neutral', 'Check', NOW(), NOW());

/* SQL text to insert entity field value with ID b1956394-c71c-4a3b-b69d-c1e19ea4f88e */

INSERT INTO ${mjSchema}."EntityFieldValue"
                                       ("ID", "EntityFieldID", "Sequence", "Value", "Code", "Source", "__mj_CreatedAt", "__mj_UpdatedAt")
                                    VALUES
                                       ('b1956394-c71c-4a3b-b69d-c1e19ea4f88e', '57B97F3B-7437-49C3-A2A3-89F8F14F3224', 3, 'Passing', 'Passing', 'Check', NOW(), NOW());

/* SQL text to insert entity field value with ID 35bed740-35c8-4e45-a029-036731451086 */

INSERT INTO ${mjSchema}."EntityFieldValue"
                                       ("ID", "EntityFieldID", "Sequence", "Value", "Code", "Source", "__mj_CreatedAt", "__mj_UpdatedAt")
                                    VALUES
                                       ('35bed740-35c8-4e45-a029-036731451086', '57B97F3B-7437-49C3-A2A3-89F8F14F3224', 4, 'Pending', 'Pending', 'Check', NOW(), NOW());

/* SQL text to update ValueListType for entity field ID 57B97F3B-7437-49C3-A2A3-89F8F14F3224 */

UPDATE ${mjSchema}."EntityField" SET "ValueListType"='List' WHERE "ID"='57B97F3B-7437-49C3-A2A3-89F8F14F3224';

/* Deterministic search-flag hygiene — clear AllowUserSearchAPI */

UPDATE ${mjSchema}."Entity"
         SET "AllowUserSearchAPI" = FALSE
         WHERE "ID" IN (
            SELECT e."ID"
            FROM ${mjSchema}."Entity" e
            WHERE e."AllowUserSearchAPI" = TRUE
              AND e."AutoUpdateAllowUserSearchAPI" = TRUE
              AND e."VirtualEntity" = FALSE
              AND COALESCE(e."FullTextSearchEnabled", 0) = 0
              AND e."SchemaName" NOT IN ('${mjSchema}','__mj_BizAppsAccounting','__mj_BizAppsCommon','__mj_BizAppsOrders','__mj_BizAppsTasks','sys')
              AND NOT EXISTS (
               SELECT 1 FROM ${mjSchema}."EntityField" f2
               WHERE f2."EntityID" = e."ID"
                 AND f2."IncludeInUserSearchAPI" = TRUE
            )
         );


/* Create Entity Relationship: MJ_BizApps_Tasks_GitHub: Git Hub Repositories -> MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks (One To Many via RepositoryID) */

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM ${mjSchema}."EntityRelationship" WHERE "ID" = 'e3e49d6f-6251-4286-8024-4da8b4f074d9' OR ("EntityID" = '6B363236-31AB-477D-8188-08F5FA9942EF' AND "RelatedEntityID" = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605' AND "RelatedEntityJoinField" = 'RepositoryID')
    ) THEN
        INSERT INTO ${mjSchema}."EntityRelationship" ("ID", "EntityID", "RelatedEntityID", "RelatedEntityJoinField", "Type", "BundleInAPI", "DisplayInForm", "Sequence", "__mj_CreatedAt", "__mj_UpdatedAt")
        VALUES ('e3e49d6f-6251-4286-8024-4da8b4f074d9', '6B363236-31AB-477D-8188-08F5FA9942EF', 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605', 'RepositoryID', 'One To Many', TRUE, TRUE, 1, NOW(), NOW());
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM ${mjSchema}."EntityRelationship" WHERE "ID" = '4557bdcd-cc5d-4d76-9570-d19af339c7be' OR ("EntityID" = '6B363236-31AB-477D-8188-08F5FA9942EF' AND "RelatedEntityID" = 'A6B673F8-43BC-4875-AFF6-AC620592822E' AND "RelatedEntityJoinField" = 'RepositoryID')
    ) THEN
        INSERT INTO ${mjSchema}."EntityRelationship" ("ID", "EntityID", "RelatedEntityID", "RelatedEntityJoinField", "Type", "BundleInAPI", "DisplayInForm", "Sequence", "__mj_CreatedAt", "__mj_UpdatedAt")
        VALUES ('4557bdcd-cc5d-4d76-9570-d19af339c7be', '6B363236-31AB-477D-8188-08F5FA9942EF', 'A6B673F8-43BC-4875-AFF6-AC620592822E', 'RepositoryID', 'One To Many', TRUE, TRUE, 2, NOW(), NOW());
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM ${mjSchema}."EntityRelationship" WHERE "ID" = '4a8f7207-f2e6-4099-a4bf-f9ecba2397b2' OR ("EntityID" = 'C70448F9-9792-41D7-A82C-784B66429D54' AND "RelatedEntityID" = '6B363236-31AB-477D-8188-08F5FA9942EF' AND "RelatedEntityJoinField" = 'OrganizationID')
    ) THEN
        INSERT INTO ${mjSchema}."EntityRelationship" ("ID", "EntityID", "RelatedEntityID", "RelatedEntityJoinField", "Type", "BundleInAPI", "DisplayInForm", "Sequence", "__mj_CreatedAt", "__mj_UpdatedAt")
        VALUES ('4a8f7207-f2e6-4099-a4bf-f9ecba2397b2', 'C70448F9-9792-41D7-A82C-784B66429D54', '6B363236-31AB-477D-8188-08F5FA9942EF', 'OrganizationID', 'One To Many', TRUE, TRUE, 19, NOW(), NOW());
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM ${mjSchema}."EntityRelationship" WHERE "ID" = 'aeb83264-4f5b-48b5-9b45-e3a0826045d0' OR ("EntityID" = '7A94ADA9-7880-4FAE-97D8-DB0E934C3F5F' AND "RelatedEntityID" = 'C7CC2BCF-090E-4832-89C7-A051F302C393' AND "RelatedEntityJoinField" = 'PersonID')
    ) THEN
        INSERT INTO ${mjSchema}."EntityRelationship" ("ID", "EntityID", "RelatedEntityID", "RelatedEntityJoinField", "Type", "BundleInAPI", "DisplayInForm", "Sequence", "__mj_CreatedAt", "__mj_UpdatedAt")
        VALUES ('aeb83264-4f5b-48b5-9b45-e3a0826045d0', '7A94ADA9-7880-4FAE-97D8-DB0E934C3F5F', 'C7CC2BCF-090E-4832-89C7-A051F302C393', 'PersonID', 'One To Many', TRUE, TRUE, 29, NOW(), NOW());
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM ${mjSchema}."EntityRelationship" WHERE "ID" = '1a25a4ba-8160-4aa9-b9cc-16f9ddff33cb' OR ("EntityID" = 'B348FFA2-B1A7-4AC2-B6FD-F4E0C0697466' AND "RelatedEntityID" = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605' AND "RelatedEntityJoinField" = 'ID')
    ) THEN
        INSERT INTO ${mjSchema}."EntityRelationship" ("ID", "EntityID", "RelatedEntityID", "RelatedEntityJoinField", "Type", "BundleInAPI", "DisplayInForm", "Sequence", "__mj_CreatedAt", "__mj_UpdatedAt")
        VALUES ('1a25a4ba-8160-4aa9-b9cc-16f9ddff33cb', 'B348FFA2-B1A7-4AC2-B6FD-F4E0C0697466', 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605', 'ID', 'One To Many', TRUE, TRUE, 17, NOW(), NOW());
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM ${mjSchema}."EntityRelationship" WHERE "ID" = '5ed8b56d-29da-442d-81dd-2f7110a01b23' OR ("EntityID" = 'B348FFA2-B1A7-4AC2-B6FD-F4E0C0697466' AND "RelatedEntityID" = 'A6B673F8-43BC-4875-AFF6-AC620592822E' AND "RelatedEntityJoinField" = 'ID')
    ) THEN
        INSERT INTO ${mjSchema}."EntityRelationship" ("ID", "EntityID", "RelatedEntityID", "RelatedEntityJoinField", "Type", "BundleInAPI", "DisplayInForm", "Sequence", "__mj_CreatedAt", "__mj_UpdatedAt")
        VALUES ('5ed8b56d-29da-442d-81dd-2f7110a01b23', 'B348FFA2-B1A7-4AC2-B6FD-F4E0C0697466', 'A6B673F8-43BC-4875-AFF6-AC620592822E', 'ID', 'One To Many', TRUE, TRUE, 18, NOW(), NOW());
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM ${mjSchema}."EntityRelationship" WHERE "ID" = 'cb4e2dff-4613-4bd1-9e43-c6bebdac19bf' OR ("EntityID" = 'B348FFA2-B1A7-4AC2-B6FD-F4E0C0697466' AND "RelatedEntityID" = 'A6B673F8-43BC-4875-AFF6-AC620592822E' AND "RelatedEntityJoinField" = 'LinkedIssueTaskID')
    ) THEN
        INSERT INTO ${mjSchema}."EntityRelationship" ("ID", "EntityID", "RelatedEntityID", "RelatedEntityJoinField", "Type", "BundleInAPI", "DisplayInForm", "Sequence", "__mj_CreatedAt", "__mj_UpdatedAt")
        VALUES ('cb4e2dff-4613-4bd1-9e43-c6bebdac19bf', 'B348FFA2-B1A7-4AC2-B6FD-F4E0C0697466', 'A6B673F8-43BC-4875-AFF6-AC620592822E', 'LinkedIssueTaskID', 'One To Many', TRUE, TRUE, 19, NOW(), NOW());
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM ${mjSchema}."EntityField" WHERE "ID" = 'fb25ea32-a752-4fa3-ad55-72034e18507b' OR ("EntityID" = '6B363236-31AB-477D-8188-08F5FA9942EF' AND "Name" = 'Organization')
    ) THEN
        INSERT INTO ${mjSchema}."EntityField"
        (
        "ID",
        "EntityID",
        "Sequence",
        "Name",
        "DisplayName",
        "Description",
        "Type",
        "Length",
        "Precision",
        "Scale",
        "AllowsNull",
        "DefaultValue",
        "AutoIncrement",
        "AllowUpdateAPI",
        "IsVirtual",
        "IsComputed",
        "RelatedEntityID",
        "RelatedEntityFieldName",
        "IsNameField",
        "IncludeInUserSearchAPI",
        "IncludeRelatedEntityNameFieldInBaseView",
        "DefaultInView",
        "IsPrimaryKey",
        "IsUnique",
        "RelatedEntityDisplayType",
        "__mj_CreatedAt",
        "__mj_UpdatedAt"
        )
        VALUES
        (
        'fb25ea32-a752-4fa3-ad55-72034e18507b',
        '6B363236-31AB-477D-8188-08F5FA9942EF', -- "Entity": "MJ_BizApps_Tasks_GitHub": "Git" "Hub" "Repositories"
        (SELECT COALESCE(MAX("Sequence"), 0) + 1 FROM ${mjSchema}."EntityField" WHERE "EntityID" = '6B363236-31AB-477D-8188-08F5FA9942EF'),
        'Organization',
        'Organization',
        NULL,
        'TEXT',
        510,
        0,
        0,
        TRUE,
        NULL,
        FALSE,
        FALSE,
        TRUE,
        FALSE,
        NULL,
        NULL,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        'Search',
        NOW(),
        NOW()
        );
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM ${mjSchema}."EntityField" WHERE "ID" = '7eacb6de-e83e-4d1e-9523-f035ac1c7547' OR ("EntityID" = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605' AND "Name" = 'Repository')
    ) THEN
        INSERT INTO ${mjSchema}."EntityField"
        (
        "ID",
        "EntityID",
        "Sequence",
        "Name",
        "DisplayName",
        "Description",
        "Type",
        "Length",
        "Precision",
        "Scale",
        "AllowsNull",
        "DefaultValue",
        "AutoIncrement",
        "AllowUpdateAPI",
        "IsVirtual",
        "IsComputed",
        "RelatedEntityID",
        "RelatedEntityFieldName",
        "IsNameField",
        "IncludeInUserSearchAPI",
        "IncludeRelatedEntityNameFieldInBaseView",
        "DefaultInView",
        "IsPrimaryKey",
        "IsUnique",
        "RelatedEntityDisplayType",
        "__mj_CreatedAt",
        "__mj_UpdatedAt"
        )
        VALUES
        (
        '7eacb6de-e83e-4d1e-9523-f035ac1c7547',
        'DC8E0F5B-E172-4FD5-B648-8B4544F8C605', -- "Entity": "MJ_BizApps_Tasks_GitHub": "Git" "Hub" "Issue" "Tasks"
        (SELECT COALESCE(MAX("Sequence"), 0) + 1 FROM ${mjSchema}."EntityField" WHERE "EntityID" = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605'),
        'Repository',
        'Repository',
        NULL,
        'TEXT',
        400,
        0,
        0,
        TRUE,
        NULL,
        FALSE,
        FALSE,
        TRUE,
        FALSE,
        NULL,
        NULL,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        'Search',
        NOW(),
        NOW()
        );
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM ${mjSchema}."EntityField" WHERE "ID" = '60f671eb-d0b7-42ff-ad43-0a300001e37e' OR ("EntityID" = 'C7CC2BCF-090E-4832-89C7-A051F302C393' AND "Name" = 'Person')
    ) THEN
        INSERT INTO ${mjSchema}."EntityField"
        (
        "ID",
        "EntityID",
        "Sequence",
        "Name",
        "DisplayName",
        "Description",
        "Type",
        "Length",
        "Precision",
        "Scale",
        "AllowsNull",
        "DefaultValue",
        "AutoIncrement",
        "AllowUpdateAPI",
        "IsVirtual",
        "IsComputed",
        "RelatedEntityID",
        "RelatedEntityFieldName",
        "IsNameField",
        "IncludeInUserSearchAPI",
        "IncludeRelatedEntityNameFieldInBaseView",
        "DefaultInView",
        "IsPrimaryKey",
        "IsUnique",
        "RelatedEntityDisplayType",
        "__mj_CreatedAt",
        "__mj_UpdatedAt"
        )
        VALUES
        (
        '60f671eb-d0b7-42ff-ad43-0a300001e37e',
        'C7CC2BCF-090E-4832-89C7-A051F302C393', -- "Entity": "MJ_BizApps_Tasks_GitHub": "Git" "Hub" "Identities"
        (SELECT COALESCE(MAX("Sequence"), 0) + 1 FROM ${mjSchema}."EntityField" WHERE "EntityID" = 'C7CC2BCF-090E-4832-89C7-A051F302C393'),
        'Person',
        'Person',
        NULL,
        'TEXT',
        500,
        0,
        0,
        TRUE,
        NULL,
        FALSE,
        FALSE,
        TRUE,
        FALSE,
        NULL,
        NULL,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        'Search',
        NOW(),
        NOW()
        );
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM ${mjSchema}."EntityField" WHERE "ID" = '4e32f6e1-bd8a-4f42-8f15-04093eaf9eb2' OR ("EntityID" = 'A6B673F8-43BC-4875-AFF6-AC620592822E' AND "Name" = 'Repository')
    ) THEN
        INSERT INTO ${mjSchema}."EntityField"
        (
        "ID",
        "EntityID",
        "Sequence",
        "Name",
        "DisplayName",
        "Description",
        "Type",
        "Length",
        "Precision",
        "Scale",
        "AllowsNull",
        "DefaultValue",
        "AutoIncrement",
        "AllowUpdateAPI",
        "IsVirtual",
        "IsComputed",
        "RelatedEntityID",
        "RelatedEntityFieldName",
        "IsNameField",
        "IncludeInUserSearchAPI",
        "IncludeRelatedEntityNameFieldInBaseView",
        "DefaultInView",
        "IsPrimaryKey",
        "IsUnique",
        "RelatedEntityDisplayType",
        "__mj_CreatedAt",
        "__mj_UpdatedAt"
        )
        VALUES
        (
        '4e32f6e1-bd8a-4f42-8f15-04093eaf9eb2',
        'A6B673F8-43BC-4875-AFF6-AC620592822E', -- "Entity": "MJ_BizApps_Tasks_GitHub": "Git" "Hub" "Pull" "Request" "Tasks"
        (SELECT COALESCE(MAX("Sequence"), 0) + 1 FROM ${mjSchema}."EntityField" WHERE "EntityID" = 'A6B673F8-43BC-4875-AFF6-AC620592822E'),
        'Repository',
        'Repository',
        NULL,
        'TEXT',
        400,
        0,
        0,
        TRUE,
        NULL,
        FALSE,
        FALSE,
        TRUE,
        FALSE,
        NULL,
        NULL,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        'Search',
        NOW(),
        NOW()
        );
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM ${mjSchema}."EntityField" WHERE "ID" = '34645952-8ca4-4a7f-af70-1b782bd89c0b' OR ("EntityID" = 'A6B673F8-43BC-4875-AFF6-AC620592822E' AND "Name" = 'LinkedIssueTask')
    ) THEN
        INSERT INTO ${mjSchema}."EntityField"
        (
        "ID",
        "EntityID",
        "Sequence",
        "Name",
        "DisplayName",
        "Description",
        "Type",
        "Length",
        "Precision",
        "Scale",
        "AllowsNull",
        "DefaultValue",
        "AutoIncrement",
        "AllowUpdateAPI",
        "IsVirtual",
        "IsComputed",
        "RelatedEntityID",
        "RelatedEntityFieldName",
        "IsNameField",
        "IncludeInUserSearchAPI",
        "IncludeRelatedEntityNameFieldInBaseView",
        "DefaultInView",
        "IsPrimaryKey",
        "IsUnique",
        "RelatedEntityDisplayType",
        "__mj_CreatedAt",
        "__mj_UpdatedAt"
        )
        VALUES
        (
        '34645952-8ca4-4a7f-af70-1b782bd89c0b',
        'A6B673F8-43BC-4875-AFF6-AC620592822E', -- "Entity": "MJ_BizApps_Tasks_GitHub": "Git" "Hub" "Pull" "Request" "Tasks"
        (SELECT COALESCE(MAX("Sequence"), 0) + 1 FROM ${mjSchema}."EntityField" WHERE "EntityID" = 'A6B673F8-43BC-4875-AFF6-AC620592822E'),
        'LinkedIssueTask',
        'Linked Issue Task',
        NULL,
        'TEXT',
        510,
        0,
        0,
        TRUE,
        NULL,
        FALSE,
        FALSE,
        TRUE,
        FALSE,
        NULL,
        NULL,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        'Search',
        NOW(),
        NOW()
        );
    END IF;
END $$;

UPDATE ${mjSchema}."EntityField"
               SET "DefaultInView" = TRUE
               WHERE "ID" = 'D09CC770-1CBB-4078-8186-BF3ED875F03C'
               AND "AutoUpdateDefaultInView" = TRUE;

UPDATE ${mjSchema}."EntityField"
               SET "IncludeInUserSearchAPI" = TRUE
               WHERE "ID" = '16994C95-2791-47C6-B378-4AF1EACE655F'
               AND "AutoUpdateIncludeInUserSearchAPI" = TRUE;

UPDATE ${mjSchema}."EntityField"
               SET "UserSearchPredicateAPI" = 'BeginsWith'
               WHERE "ID" = '16994C95-2791-47C6-B378-4AF1EACE655F'
               AND "AutoUpdateUserSearchPredicate" = TRUE;

UPDATE ${mjSchema}."EntityField"
               SET "UserSearchPredicateAPI" = 'BeginsWith'
               WHERE "ID" = '8CFC093F-2135-437E-93A8-493A64DFA174'
               AND "AutoUpdateUserSearchPredicate" = TRUE;

/* Set field properties for entity */

UPDATE ${mjSchema}."EntityField"
               SET "DefaultInView" = TRUE
               WHERE "ID" = '5CBFAABD-0AF2-4E67-91B1-F089E6C56C4D'
               AND "AutoUpdateDefaultInView" = TRUE;

UPDATE ${mjSchema}."EntityField"
               SET "DefaultInView" = TRUE
               WHERE "ID" = '6A042282-8DC0-4158-B972-F2EFF37C1387'
               AND "AutoUpdateDefaultInView" = TRUE;

UPDATE ${mjSchema}."EntityField"
               SET "DefaultInView" = TRUE
               WHERE "ID" = '8D2DB26A-0621-4A94-A932-A4C1F47E1DCF'
               AND "AutoUpdateDefaultInView" = TRUE;

UPDATE ${mjSchema}."EntityField"
               SET "DefaultInView" = TRUE
               WHERE "ID" = 'DEBADDF7-A747-400C-BEC1-8A93FDDF6193'
               AND "AutoUpdateDefaultInView" = TRUE;

UPDATE ${mjSchema}."EntityField"
               SET "DefaultInView" = TRUE
               WHERE "ID" = 'D0242DB3-ACFC-4AD6-9B8A-7AF48E27BBE4'
               AND "AutoUpdateDefaultInView" = TRUE;

UPDATE ${mjSchema}."EntityField"
               SET "DefaultInView" = TRUE
               WHERE "ID" = '57B97F3B-7437-49C3-A2A3-89F8F14F3224'
               AND "AutoUpdateDefaultInView" = TRUE;

UPDATE ${mjSchema}."EntityField"
               SET "IncludeInUserSearchAPI" = TRUE
               WHERE "ID" = '6A042282-8DC0-4158-B972-F2EFF37C1387'
               AND "AutoUpdateIncludeInUserSearchAPI" = TRUE;

UPDATE ${mjSchema}."EntityField"
               SET "IncludeInUserSearchAPI" = TRUE
               WHERE "ID" = 'DEBADDF7-A747-400C-BEC1-8A93FDDF6193'
               AND "AutoUpdateIncludeInUserSearchAPI" = TRUE;

UPDATE ${mjSchema}."EntityField"
               SET "UserSearchPredicateAPI" = 'BeginsWith'
               WHERE "ID" = '6A042282-8DC0-4158-B972-F2EFF37C1387'
               AND "AutoUpdateUserSearchPredicate" = TRUE;

UPDATE ${mjSchema}."EntityField"
               SET "UserSearchPredicateAPI" = 'Exact'
               WHERE "ID" = 'DEBADDF7-A747-400C-BEC1-8A93FDDF6193'
               AND "AutoUpdateUserSearchPredicate" = TRUE;

UPDATE ${mjSchema}."Entity"
            SET "AllowUserSearchAPI" = TRUE
            WHERE "ID" = 'A6B673F8-43BC-4875-AFF6-AC620592822E'
            AND "AutoUpdateAllowUserSearchAPI" = TRUE;

/* Set field properties for entity */

UPDATE ${mjSchema}."EntityField"
               SET "IsNameField" = TRUE
               WHERE "ID" = '8A9B093F-91D1-4991-9069-4F2F36AD9181'
               AND "AutoUpdateIsNameField" = TRUE;

UPDATE ${mjSchema}."EntityField"
               SET "DefaultInView" = TRUE
               WHERE "ID" = '54CD3BC9-E3DF-4B33-9413-B2F137EB2452'
               AND "AutoUpdateDefaultInView" = TRUE;

UPDATE ${mjSchema}."EntityField"
               SET "DefaultInView" = TRUE
               WHERE "ID" = '8A9B093F-91D1-4991-9069-4F2F36AD9181'
               AND "AutoUpdateDefaultInView" = TRUE;

UPDATE ${mjSchema}."EntityField"
               SET "DefaultInView" = TRUE
               WHERE "ID" = '47F2BC8C-BAA7-4720-8425-3F982EDFD315'
               AND "AutoUpdateDefaultInView" = TRUE;

UPDATE ${mjSchema}."EntityField"
               SET "DefaultInView" = TRUE
               WHERE "ID" = 'FF322D0F-97CB-4CEE-9C1E-C347A4C145AE'
               AND "AutoUpdateDefaultInView" = TRUE;

UPDATE ${mjSchema}."EntityField"
               SET "IncludeInUserSearchAPI" = TRUE
               WHERE "ID" = '8A9B093F-91D1-4991-9069-4F2F36AD9181'
               AND "AutoUpdateIncludeInUserSearchAPI" = TRUE;

UPDATE ${mjSchema}."EntityField"
               SET "IncludeInUserSearchAPI" = TRUE
               WHERE "ID" = '47F2BC8C-BAA7-4720-8425-3F982EDFD315'
               AND "AutoUpdateIncludeInUserSearchAPI" = TRUE;

UPDATE ${mjSchema}."EntityField"
               SET "UserSearchPredicateAPI" = 'BeginsWith'
               WHERE "ID" = '8A9B093F-91D1-4991-9069-4F2F36AD9181'
               AND "AutoUpdateUserSearchPredicate" = TRUE;

UPDATE ${mjSchema}."EntityField"
               SET "UserSearchPredicateAPI" = 'Exact'
               WHERE "ID" = '47F2BC8C-BAA7-4720-8425-3F982EDFD315'
               AND "AutoUpdateUserSearchPredicate" = TRUE;

/* Set categories for 12 fields */

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Repositories.ID

UPDATE ${mjSchema}."EntityField"
SET 
   "Category" = 'System Metadata',
   "GeneratedFormSection" = 'Category'
WHERE 
   "ID" = 'D38E3C3F-3676-439B-9111-DF4565789C9F';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Repositories.Owner

UPDATE ${mjSchema}."EntityField"
SET 
   "Category" = 'Repository Details',
   "GeneratedFormSection" = 'Category'
WHERE 
   "ID" = '16994C95-2791-47C6-B378-4AF1EACE655F';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Repositories.Name

UPDATE ${mjSchema}."EntityField"
SET 
   "Category" = 'Repository Details',
   "GeneratedFormSection" = 'Category'
WHERE 
   "ID" = '8CFC093F-2135-437E-93A8-493A64DFA174';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Repositories.DefaultBranch

UPDATE ${mjSchema}."EntityField"
SET 
   "Category" = 'Repository Details',
   "GeneratedFormSection" = 'Category'
WHERE 
   "ID" = '8231446A-482B-4D5F-A1ED-AE1A717F50A0';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Repositories.IsTracked

UPDATE ${mjSchema}."EntityField"
SET 
   "Category" = 'Sync and Import Configuration',
   "GeneratedFormSection" = 'Category'
WHERE 
   "ID" = '89C19524-C1FB-441E-A66C-577DDC5D41C3';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Repositories.ImportRule

UPDATE ${mjSchema}."EntityField"
SET 
   "Category" = 'Sync and Import Configuration',
   "GeneratedFormSection" = 'Category'
WHERE 
   "ID" = 'D09CC770-1CBB-4078-8186-BF3ED875F03C';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Repositories.InstallationID

UPDATE ${mjSchema}."EntityField"
SET 
   "Category" = 'Integration and Links',
   "GeneratedFormSection" = 'Category'
WHERE 
   "ID" = 'F6397E85-2F8B-4B39-A42F-4063209B7C3E';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Repositories.OrganizationID

UPDATE ${mjSchema}."EntityField"
SET 
   "Category" = 'Integration and Links',
   "GeneratedFormSection" = 'Category'
WHERE 
   "ID" = '507961D4-497E-4B22-9CFF-C6506F32B45C';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Repositories.DeliveryPolicyID

UPDATE ${mjSchema}."EntityField"
SET 
   "Category" = 'Integration and Links',
   "GeneratedFormSection" = 'Category'
WHERE 
   "ID" = '2685C802-43EA-4389-B1CC-5D007755DCD6';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Repositories.__mj_CreatedAt

UPDATE ${mjSchema}."EntityField"
SET 
   "Category" = 'System Metadata',
   "GeneratedFormSection" = 'Category'
WHERE 
   "ID" = 'F9323407-463F-4EF0-8E56-800D98360B4A';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Repositories.__mj_UpdatedAt

UPDATE ${mjSchema}."EntityField"
SET 
   "Category" = 'System Metadata',
   "GeneratedFormSection" = 'Category'
WHERE 
   "ID" = '1E25CF76-141F-4848-8A29-C47A7A522297';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Repositories.Organization

UPDATE ${mjSchema}."EntityField"
SET 
   "Category" = 'Integration and Links',
   "GeneratedFormSection" = 'Category'
WHERE 
   "ID" = 'FB25EA32-A752-4FA3-AD55-72034E18507B';

/* Set entity icon to fa fa-code-branch */

UPDATE ${mjSchema}."Entity"
               SET "Icon" = 'fa fa-code-branch', "__mj_UpdatedAt" = NOW()
               WHERE "ID" = '6B363236-31AB-477D-8188-08F5FA9942EF';

/* Insert FieldCategoryInfo setting for entity */

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM ${mjSchema}."EntitySetting" WHERE "EntityID" = '6B363236-31AB-477D-8188-08F5FA9942EF' AND "Name" = 'FieldCategoryInfo'
    ) THEN
        INSERT INTO ${mjSchema}."EntitySetting" ("ID", "EntityID", "Name", "Value", "__mj_CreatedAt", "__mj_UpdatedAt")
        VALUES ('10dd11f1-5444-5fba-8141-e897ef1cb5b5', '6B363236-31AB-477D-8188-08F5FA9942EF', 'FieldCategoryInfo', '{
        "Integration and Links": {
        "description": "GitHub app installation and organization/policy links",
        "icon": "fa fa-link"
        },
        "Repository Details": {
        "description": "Core GitHub repository identification and branch configuration",
        "icon": "fa fa-code-branch"
        },
        "Sync and Import Configuration": {
        "description": "Rules and toggles for tracking and importing GitHub issues and pull requests",
        "icon": "fa fa-sliders-h"
        },
        "System Metadata": {
        "description": "System-managed audit and tracking fields",
        "icon": "fa fa-cog"
        }
        }', NOW(), NOW());
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM ${mjSchema}."EntitySetting" WHERE "EntityID" = '6B363236-31AB-477D-8188-08F5FA9942EF' AND "Name" = 'FieldCategoryIcons'
    ) THEN
        INSERT INTO ${mjSchema}."EntitySetting" ("ID", "EntityID", "Name", "Value", "__mj_CreatedAt", "__mj_UpdatedAt")
        VALUES ('091ada65-bfce-5cb9-900b-0e1a1c46c0af', '6B363236-31AB-477D-8188-08F5FA9942EF', 'FieldCategoryIcons', '{
        "Integration and Links": "fa fa-link",
        "Repository Details": "fa fa-code-branch",
        "Sync and Import Configuration": "fa fa-sliders-h",
        "System Metadata": "fa fa-cog"
        }', NOW(), NOW());
    END IF;
END $$;

UPDATE ${mjSchema}."ApplicationEntity"
         SET "DefaultForNewUser" = TRUE, "__mj_UpdatedAt" = NOW()
         WHERE "EntityID" = '6B363236-31AB-477D-8188-08F5FA9942EF';

/* Set categories for 28 fields */

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks.ID

UPDATE ${mjSchema}."EntityField"
SET 
   "Category" = 'System Metadata',
   "GeneratedFormSection" = 'Category'
WHERE 
   "ID" = '4AFBF1A3-202B-4657-938B-652EF047768F';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks.RepositoryID

UPDATE ${mjSchema}."EntityField"
SET 
   "Category" = 'Pull Request Details',
   "GeneratedFormSection" = 'Category'
WHERE 
   "ID" = '80C22B8D-1383-4AC3-BC9D-6540C3FDED78';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks.Number

UPDATE ${mjSchema}."EntityField"
SET 
   "Category" = 'Pull Request Details',
   "GeneratedFormSection" = 'Category'
WHERE 
   "ID" = 'D0157CE0-E6EE-41D6-828D-F774B96AB24C';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks.NodeID

UPDATE ${mjSchema}."EntityField"
SET 
   "Category" = 'Pull Request Details',
   "GeneratedFormSection" = 'Category'
WHERE 
   "ID" = '07679AF9-E8A9-4AEB-AD5C-2CB9BA40A3F4';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks.HtmlURL

UPDATE ${mjSchema}."EntityField"
SET 
   "Category" = 'Pull Request Details',
   "GeneratedFormSection" = 'Category',
   "DisplayName" = 'HTML URL',
   "ExtendedType" = 'URL'
WHERE 
   "ID" = 'F2598281-767D-423E-B92A-3000708EFE1A';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks.State

UPDATE ${mjSchema}."EntityField"
SET 
   "Category" = 'Status and Workflow',
   "GeneratedFormSection" = 'Category'
WHERE 
   "ID" = '5CBFAABD-0AF2-4E67-91B1-F089E6C56C4D';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks.IsDraft

UPDATE ${mjSchema}."EntityField"
SET 
   "Category" = 'Status and Workflow',
   "GeneratedFormSection" = 'Category'
WHERE 
   "ID" = '6702784E-CE7D-41DD-A906-6958E5415A5D';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks.HeadBranch

UPDATE ${mjSchema}."EntityField"
SET 
   "Category" = 'Branch and Commit Info',
   "GeneratedFormSection" = 'Category'
WHERE 
   "ID" = '6A042282-8DC0-4158-B972-F2EFF37C1387';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks.HeadSha

UPDATE ${mjSchema}."EntityField"
SET 
   "Category" = 'Branch and Commit Info',
   "GeneratedFormSection" = 'Category',
   "DisplayName" = 'Head SHA'
WHERE 
   "ID" = '68D879E4-6123-482D-8637-A6B7E250B9CB';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks.BaseBranch

UPDATE ${mjSchema}."EntityField"
SET 
   "Category" = 'Branch and Commit Info',
   "GeneratedFormSection" = 'Category'
WHERE 
   "ID" = '8D2DB26A-0621-4A94-A932-A4C1F47E1DCF';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks.AuthorLogin

UPDATE ${mjSchema}."EntityField"
SET 
   "Category" = 'Pull Request Details',
   "GeneratedFormSection" = 'Category'
WHERE 
   "ID" = 'DEBADDF7-A747-400C-BEC1-8A93FDDF6193';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks.ReviewDecision

UPDATE ${mjSchema}."EntityField"
SET 
   "Category" = 'Status and Workflow',
   "GeneratedFormSection" = 'Category'
WHERE 
   "ID" = 'D0242DB3-ACFC-4AD6-9B8A-7AF48E27BBE4';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks.ChecksStatus

UPDATE ${mjSchema}."EntityField"
SET 
   "Category" = 'Status and Workflow',
   "GeneratedFormSection" = 'Category'
WHERE 
   "ID" = '57B97F3B-7437-49C3-A2A3-89F8F14F3224';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks.ChangedFiles

UPDATE ${mjSchema}."EntityField"
SET 
   "Category" = 'Diff Metrics',
   "GeneratedFormSection" = 'Category'
WHERE 
   "ID" = 'C43679AF-0136-4312-BFC7-50A774A1DF96';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks.Additions

UPDATE ${mjSchema}."EntityField"
SET 
   "Category" = 'Diff Metrics',
   "GeneratedFormSection" = 'Category'
WHERE 
   "ID" = 'E7C6D6DD-3B2C-4D1F-854C-36EC48EA6541';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks.Deletions

UPDATE ${mjSchema}."EntityField"
SET 
   "Category" = 'Diff Metrics',
   "GeneratedFormSection" = 'Category'
WHERE 
   "ID" = '79A88ACA-735F-4126-AF8C-E84E0EAB6DBE';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks.Labels

UPDATE ${mjSchema}."EntityField"
SET 
   "Category" = 'Pull Request Details',
   "GeneratedFormSection" = 'Category',
   "ExtendedType" = 'JSON'
WHERE 
   "ID" = '88926596-FB58-4AB7-AEF8-3BCB7F927B0A';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks.Milestone

UPDATE ${mjSchema}."EntityField"
SET 
   "Category" = 'Pull Request Details',
   "GeneratedFormSection" = 'Category'
WHERE 
   "ID" = '3A7BDB54-1596-447C-B919-0DBA77BF1988';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks.MilestoneDueAt

UPDATE ${mjSchema}."EntityField"
SET 
   "Category" = 'Dates and Timeline',
   "GeneratedFormSection" = 'Category'
WHERE 
   "ID" = '4CCF1BDD-F21D-4003-8499-9A1D6C9C02E2';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks.MergedAt

UPDATE ${mjSchema}."EntityField"
SET 
   "Category" = 'Dates and Timeline',
   "GeneratedFormSection" = 'Category'
WHERE 
   "ID" = '4801E8B7-847B-411D-B5F0-002551B4F237';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks.LinkedIssueTaskID

UPDATE ${mjSchema}."EntityField"
SET 
   "Category" = 'Pull Request Details',
   "GeneratedFormSection" = 'Category'
WHERE 
   "ID" = 'AF64DC8D-5285-46A8-A44B-145BDA229838';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks.BodyHash

UPDATE ${mjSchema}."EntityField"
SET 
   "Category" = 'System Metadata',
   "GeneratedFormSection" = 'Category'
WHERE 
   "ID" = '6E18BAB8-7F3D-42C0-AC47-D1CCB685A2E0';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks.GitHubUpdatedAt

UPDATE ${mjSchema}."EntityField"
SET 
   "Category" = 'Dates and Timeline',
   "GeneratedFormSection" = 'Category',
   "DisplayName" = 'GitHub Updated At'
WHERE 
   "ID" = 'CFA8847F-9404-4B62-810F-863DD426852B';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks.LastSyncedAt

UPDATE ${mjSchema}."EntityField"
SET 
   "Category" = 'Dates and Timeline',
   "GeneratedFormSection" = 'Category'
WHERE 
   "ID" = '4E1457AC-6957-44B9-BAF9-93C09114807E';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks.__mj_CreatedAt

UPDATE ${mjSchema}."EntityField"
SET 
   "Category" = 'System Metadata',
   "GeneratedFormSection" = 'Category'
WHERE 
   "ID" = '5D5A0E69-1ED4-4863-A611-34BF239FA515';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks.__mj_UpdatedAt

UPDATE ${mjSchema}."EntityField"
SET 
   "Category" = 'System Metadata',
   "GeneratedFormSection" = 'Category'
WHERE 
   "ID" = 'F3A56A47-49D7-4E66-B762-AEDC7F65DBDB';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks.Repository

UPDATE ${mjSchema}."EntityField"
SET 
   "Category" = 'Pull Request Details',
   "GeneratedFormSection" = 'Category'
WHERE 
   "ID" = '4E32F6E1-BD8A-4F42-8F15-04093EAF9EB2';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks.LinkedIssueTask

UPDATE ${mjSchema}."EntityField"
SET 
   "Category" = 'Pull Request Details',
   "GeneratedFormSection" = 'Category'
WHERE 
   "ID" = '34645952-8CA4-4A7F-AF70-1B782BD89C0B';

/* Set entity icon to fa fa-code-branch */

UPDATE ${mjSchema}."Entity"
               SET "Icon" = 'fa fa-code-branch', "__mj_UpdatedAt" = NOW()
               WHERE "ID" = 'A6B673F8-43BC-4875-AFF6-AC620592822E';

/* Insert FieldCategoryInfo setting for entity */

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM ${mjSchema}."EntitySetting" WHERE "EntityID" = 'A6B673F8-43BC-4875-AFF6-AC620592822E' AND "Name" = 'FieldCategoryInfo'
    ) THEN
        INSERT INTO ${mjSchema}."EntitySetting" ("ID", "EntityID", "Name", "Value", "__mj_CreatedAt", "__mj_UpdatedAt")
        VALUES ('1a852e8b-0efa-544d-9498-b739c112e598', 'A6B673F8-43BC-4875-AFF6-AC620592822E', 'FieldCategoryInfo', '{
        "Branch and Commit Info": {
        "description": "Source and target branches alongside head commit information",
        "icon": "fa fa-code"
        },
        "Dates and Timeline": {
        "description": "Timestamps for milestones, merges, and synchronization events",
        "icon": "fa fa-calendar-alt"
        },
        "Diff Metrics": {
        "description": "Code diff metrics including changed files, additions, and deletions",
        "icon": "fa fa-chart-bar"
        },
        "Pull Request Details": {
        "description": "Core pull request metadata, identifiers, links, and relationships",
        "icon": "fa fa-code-branch"
        },
        "Status and Workflow": {
        "description": "Lifecycle state, draft status, review decisions, and CI check statuses",
        "icon": "fa fa-tasks"
        },
        "System Metadata": {
        "description": "System-managed audit trails and sync hashes",
        "icon": "fa fa-cog"
        }
        }', NOW(), NOW());
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM ${mjSchema}."EntitySetting" WHERE "EntityID" = 'A6B673F8-43BC-4875-AFF6-AC620592822E' AND "Name" = 'FieldCategoryIcons'
    ) THEN
        INSERT INTO ${mjSchema}."EntitySetting" ("ID", "EntityID", "Name", "Value", "__mj_CreatedAt", "__mj_UpdatedAt")
        VALUES ('64509eb4-e40e-53f0-be3e-229cd8b216c9', 'A6B673F8-43BC-4875-AFF6-AC620592822E', 'FieldCategoryIcons', '{
        "Branch and Commit Info": "fa fa-code",
        "Dates and Timeline": "fa fa-calendar-alt",
        "Diff Metrics": "fa fa-chart-bar",
        "Pull Request Details": "fa fa-code-branch",
        "Status and Workflow": "fa fa-tasks",
        "System Metadata": "fa fa-cog"
        }', NOW(), NOW());
    END IF;
END $$;

UPDATE ${mjSchema}."ApplicationEntity"
         SET "DefaultForNewUser" = TRUE, "__mj_UpdatedAt" = NOW()
         WHERE "EntityID" = 'A6B673F8-43BC-4875-AFF6-AC620592822E';

/* Set field properties for entity */

UPDATE ${mjSchema}."EntityField"
               SET "IsNameField" = TRUE
               WHERE "ID" = '2680087D-C275-43F1-8A02-EB2FAC64624C'
               AND "AutoUpdateIsNameField" = TRUE;

UPDATE ${mjSchema}."EntityField"
               SET "DefaultInView" = TRUE
               WHERE "ID" = '60F671EB-D0B7-42FF-AD43-0A300001E37E'
               AND "AutoUpdateDefaultInView" = TRUE;

/* Set categories for 8 fields */

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Identities.ID

UPDATE ${mjSchema}."EntityField"
SET 
   "Category" = 'System Metadata',
   "GeneratedFormSection" = 'Category'
WHERE 
   "ID" = '14420024-8D4C-43FB-B3C2-C335CFDCA13F';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Identities.GitHubLogin

UPDATE ${mjSchema}."EntityField"
SET 
   "Category" = 'GitHub Identity Details',
   "GeneratedFormSection" = 'Category',
   "DisplayName" = 'GitHub Login'
WHERE 
   "ID" = '2680087D-C275-43F1-8A02-EB2FAC64624C';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Identities.PersonID

UPDATE ${mjSchema}."EntityField"
SET 
   "Category" = 'GitHub Identity Details',
   "GeneratedFormSection" = 'Category',
   "DisplayName" = 'Person'
WHERE 
   "ID" = '86923F31-A619-4171-9700-360D0F84EAEE';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Identities.GitHubUserID

UPDATE ${mjSchema}."EntityField"
SET 
   "Category" = 'GitHub Identity Details',
   "GeneratedFormSection" = 'Category',
   "DisplayName" = 'GitHub User ID'
WHERE 
   "ID" = 'DA3FF8E3-9102-4BDC-9747-2C1B92282829';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Identities.IsActive

UPDATE ${mjSchema}."EntityField"
SET 
   "Category" = 'GitHub Identity Details',
   "GeneratedFormSection" = 'Category'
WHERE 
   "ID" = '859B1D57-888E-4F5E-9394-11927FCDE8CA';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Identities.Person

UPDATE ${mjSchema}."EntityField"
SET 
   "Category" = 'GitHub Identity Details',
   "GeneratedFormSection" = 'Category',
   "DisplayName" = 'Person Name'
WHERE 
   "ID" = '60F671EB-D0B7-42FF-AD43-0A300001E37E';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Identities.__mj_CreatedAt

UPDATE ${mjSchema}."EntityField"
SET 
   "Category" = 'System Metadata',
   "GeneratedFormSection" = 'Category'
WHERE 
   "ID" = '0F52C847-41B4-44F5-9FF7-83DF5BFC74D9';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Identities.__mj_UpdatedAt

UPDATE ${mjSchema}."EntityField"
SET 
   "Category" = 'System Metadata',
   "GeneratedFormSection" = 'Category'
WHERE 
   "ID" = '168EED29-3B45-4398-973F-71A7DA22E916';

/* Set entity icon to fa fa-code-branch */

UPDATE ${mjSchema}."Entity"
               SET "Icon" = 'fa fa-code-branch', "__mj_UpdatedAt" = NOW()
               WHERE "ID" = 'C7CC2BCF-090E-4832-89C7-A051F302C393';

/* Insert FieldCategoryInfo setting for entity */

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM ${mjSchema}."EntitySetting" WHERE "EntityID" = 'C7CC2BCF-090E-4832-89C7-A051F302C393' AND "Name" = 'FieldCategoryInfo'
    ) THEN
        INSERT INTO ${mjSchema}."EntitySetting" ("ID", "EntityID", "Name", "Value", "__mj_CreatedAt", "__mj_UpdatedAt")
        VALUES ('0c431937-6f04-5387-a30d-2da839924e63', 'C7CC2BCF-090E-4832-89C7-A051F302C393', 'FieldCategoryInfo', '{
        "GitHub Identity Details": {
        "description": "Mapping configuration between GitHub users and BizApps Person records",
        "icon": "fa fa-id-card"
        },
        "System Metadata": {
        "description": "System-managed audit and tracking fields",
        "icon": "fa fa-cog"
        }
        }', NOW(), NOW());
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM ${mjSchema}."EntitySetting" WHERE "EntityID" = 'C7CC2BCF-090E-4832-89C7-A051F302C393' AND "Name" = 'FieldCategoryIcons'
    ) THEN
        INSERT INTO ${mjSchema}."EntitySetting" ("ID", "EntityID", "Name", "Value", "__mj_CreatedAt", "__mj_UpdatedAt")
        VALUES ('db0318b6-aeb2-5899-95a2-1355bc2675e7', 'C7CC2BCF-090E-4832-89C7-A051F302C393', 'FieldCategoryIcons', '{
        "GitHub Identity Details": "fa fa-id-card",
        "System Metadata": "fa fa-cog"
        }', NOW(), NOW());
    END IF;
END $$;

UPDATE ${mjSchema}."ApplicationEntity"
         SET "DefaultForNewUser" = FALSE, "__mj_UpdatedAt" = NOW()
         WHERE "EntityID" = 'C7CC2BCF-090E-4832-89C7-A051F302C393';

/* Set categories for 17 fields */

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks.ID

UPDATE ${mjSchema}."EntityField"
SET 
   "Category" = 'System Metadata',
   "GeneratedFormSection" = 'Category'
WHERE 
   "ID" = 'F041D734-2D08-48F3-BAA4-C29F45BFB5DE';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks.RepositoryID

UPDATE ${mjSchema}."EntityField"
SET 
   "Category" = 'GitHub Issue Details',
   "GeneratedFormSection" = 'Category'
WHERE 
   "ID" = '54442A79-CEAD-408B-82AA-4119053FE27E';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks.Number

UPDATE ${mjSchema}."EntityField"
SET 
   "Category" = 'GitHub Issue Details',
   "GeneratedFormSection" = 'Category',
   "DisplayName" = 'Issue Number'
WHERE 
   "ID" = 'A97CA445-668E-4763-A2C6-74DE67A33925';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks.NodeID

UPDATE ${mjSchema}."EntityField"
SET 
   "Category" = 'GitHub Issue Details',
   "GeneratedFormSection" = 'Category'
WHERE 
   "ID" = 'B0C058E3-BA70-4F2A-9B84-21AB522E8E6D';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks.HtmlURL

UPDATE ${mjSchema}."EntityField"
SET 
   "Category" = 'GitHub Issue Details',
   "GeneratedFormSection" = 'Category',
   "DisplayName" = 'HTML URL',
   "ExtendedType" = 'URL'
WHERE 
   "ID" = '6B287FDE-CF5A-4381-84A1-96A45D3E58C4';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks.State

UPDATE ${mjSchema}."EntityField"
SET 
   "Category" = 'GitHub Issue Details',
   "GeneratedFormSection" = 'Category'
WHERE 
   "ID" = '54CD3BC9-E3DF-4B33-9413-B2F137EB2452';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks.StateReason

UPDATE ${mjSchema}."EntityField"
SET 
   "Category" = 'GitHub Issue Details',
   "GeneratedFormSection" = 'Category'
WHERE 
   "ID" = 'AC27EB42-F18D-4444-99A2-9E454DBAEB49';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks.Labels

UPDATE ${mjSchema}."EntityField"
SET 
   "Category" = 'GitHub Issue Details',
   "GeneratedFormSection" = 'Category',
   "ExtendedType" = 'JSON'
WHERE 
   "ID" = '9F961E3C-910B-44C2-A78F-E0AC03ED963F';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks.AuthorLogin

UPDATE ${mjSchema}."EntityField"
SET 
   "Category" = 'GitHub Issue Details',
   "GeneratedFormSection" = 'Category'
WHERE 
   "ID" = '47F2BC8C-BAA7-4720-8425-3F982EDFD315';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks.Repository

UPDATE ${mjSchema}."EntityField"
SET 
   "Category" = 'GitHub Issue Details',
   "GeneratedFormSection" = 'Category'
WHERE 
   "ID" = '7EACB6DE-E83E-4D1E-9523-F035AC1C7547';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks.Milestone

UPDATE ${mjSchema}."EntityField"
SET 
   "Category" = 'Milestone and Timeline',
   "GeneratedFormSection" = 'Category'
WHERE 
   "ID" = '8A9B093F-91D1-4991-9069-4F2F36AD9181';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks.MilestoneDueAt

UPDATE ${mjSchema}."EntityField"
SET 
   "Category" = 'Milestone and Timeline',
   "GeneratedFormSection" = 'Category'
WHERE 
   "ID" = '9A88E775-DCA4-46ED-B580-CC79394B5B69';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks.BodyHash

UPDATE ${mjSchema}."EntityField"
SET 
   "Category" = 'Sync and Audit Information',
   "GeneratedFormSection" = 'Category'
WHERE 
   "ID" = '0B5ED37C-D3AB-4C8A-A484-F0E12DBD9744';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks.GitHubUpdatedAt

UPDATE ${mjSchema}."EntityField"
SET 
   "Category" = 'Sync and Audit Information',
   "GeneratedFormSection" = 'Category',
   "DisplayName" = 'GitHub Updated At'
WHERE 
   "ID" = 'FF322D0F-97CB-4CEE-9C1E-C347A4C145AE';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks.LastSyncedAt

UPDATE ${mjSchema}."EntityField"
SET 
   "Category" = 'Sync and Audit Information',
   "GeneratedFormSection" = 'Category'
WHERE 
   "ID" = '8D123F90-1CD8-42E3-A8BF-C121BE46401B';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks.__mj_CreatedAt

UPDATE ${mjSchema}."EntityField"
SET 
   "Category" = 'System Metadata',
   "GeneratedFormSection" = 'Category'
WHERE 
   "ID" = 'DEC034D1-627F-4099-84D9-71EBD162ACBD';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks.__mj_UpdatedAt

UPDATE ${mjSchema}."EntityField"
SET 
   "Category" = 'System Metadata',
   "GeneratedFormSection" = 'Category'
WHERE 
   "ID" = 'F846083A-3F9A-4728-86D8-6772A47AC54E';

/* Set entity icon to fab fa-github */

UPDATE ${mjSchema}."Entity"
               SET "Icon" = 'fab fa-github', "__mj_UpdatedAt" = NOW()
               WHERE "ID" = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605';

/* Insert FieldCategoryInfo setting for entity */

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM ${mjSchema}."EntitySetting" WHERE "EntityID" = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605' AND "Name" = 'FieldCategoryInfo'
    ) THEN
        INSERT INTO ${mjSchema}."EntitySetting" ("ID", "EntityID", "Name", "Value", "__mj_CreatedAt", "__mj_UpdatedAt")
        VALUES ('41f6983a-476f-592d-9eb8-52ee375ce6eb', 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605', 'FieldCategoryInfo', '{
        "GitHub Issue Details": {
        "description": "Core GitHub issue metadata, identifiers, URLs, state, and labels",
        "icon": "fab fa-github"
        },
        "Milestone and Timeline": {
        "description": "GitHub milestone assignments and associated target due dates",
        "icon": "fa fa-calendar-alt"
        },
        "Sync and Audit Information": {
        "description": "External synchronization tracking keys, content hashes, and upstream timestamps",
        "icon": "fa fa-sync"
        },
        "System Metadata": {
        "description": "System-managed audit and primary key fields",
        "icon": "fa fa-cog"
        }
        }', NOW(), NOW());
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM ${mjSchema}."EntitySetting" WHERE "EntityID" = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605' AND "Name" = 'FieldCategoryIcons'
    ) THEN
        INSERT INTO ${mjSchema}."EntitySetting" ("ID", "EntityID", "Name", "Value", "__mj_CreatedAt", "__mj_UpdatedAt")
        VALUES ('3c7e42bf-7e88-50ae-a5c6-bf27303fe434', 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605', 'FieldCategoryIcons', '{
        "GitHub Issue Details": "fab fa-github",
        "Milestone and Timeline": "fa fa-calendar-alt",
        "Sync and Audit Information": "fa fa-sync",
        "System Metadata": "fa fa-cog"
        }', NOW(), NOW());
    END IF;
END $$;

UPDATE ${mjSchema}."ApplicationEntity"
         SET "DefaultForNewUser" = TRUE, "__mj_UpdatedAt" = NOW()
         WHERE "EntityID" = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605';


/* SQL text to update existing entities from schema */

UPDATE ${mjSchema}."Entity"
                                  SET "__mj_UpdatedAt"=NOW(),
                                      "ParentID" = 'B348FFA2-B1A7-4AC2-B6FD-F4E0C0697466'
                                  WHERE "ID" = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605';

/* Set IS-A ParentID for "MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks" → "MJ_BizApps_Tasks: Tasks" */

UPDATE ${mjSchema}."Entity"
                                  SET "__mj_UpdatedAt"=NOW(),
                                      "ParentID" = 'B348FFA2-B1A7-4AC2-B6FD-F4E0C0697466'
                                  WHERE "ID" = 'A6B673F8-43BC-4875-AFF6-AC620592822E';

/* Update attributes on "MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks" from additionalSchemaInfo */

UPDATE ${mjSchema}."Entity"
                              SET "__mj_UpdatedAt" = NOW(), "Configuration" = '{"Comments": {"Enabled": true, "AllowedCommentTypes": ["COMMENT", "FIELD_SUGGESTION"]}}'
                              WHERE "ID" = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605';

/* Update attributes on "MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks" from additionalSchemaInfo */

UPDATE ${mjSchema}."Entity"
                              SET "__mj_UpdatedAt" = NOW(), "Configuration" = '{"Comments": {"Enabled": true, "AllowedCommentTypes": ["COMMENT", "FIELD_SUGGESTION"]}}'
                              WHERE "ID" = 'A6B673F8-43BC-4875-AFF6-AC620592822E';

/* SQL text to sync schema info from database schemas */

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM ${mjSchema}."EntityField" WHERE "ID" = '5f177501-4505-4dfe-9813-9b930dfe80c5' OR ("EntityID" = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605' AND "Name" = 'Name')
    ) THEN
        INSERT INTO ${mjSchema}."EntityField"
        (
        "ID",
        "EntityID",
        "Sequence",
        "Name",
        "DisplayName",
        "Description",
        "Type",
        "Length",
        "Precision",
        "Scale",
        "AllowsNull",
        "DefaultValue",
        "AutoIncrement",
        "AllowUpdateAPI",
        "IsVirtual",
        "IsComputed",
        "RelatedEntityID",
        "RelatedEntityFieldName",
        "IsNameField",
        "IncludeInUserSearchAPI",
        "IncludeRelatedEntityNameFieldInBaseView",
        "DefaultInView",
        "IsPrimaryKey",
        "IsUnique",
        "RelatedEntityDisplayType",
        "__mj_CreatedAt",
        "__mj_UpdatedAt"
        )
        VALUES
        (
        '5f177501-4505-4dfe-9813-9b930dfe80c5',
        'DC8E0F5B-E172-4FD5-B648-8B4544F8C605', -- "Entity": "MJ_BizApps_Tasks_GitHub": "Git" "Hub" "Issue" "Tasks"
        (SELECT COALESCE(MAX("Sequence"), 0) + 1 FROM ${mjSchema}."EntityField" WHERE "EntityID" = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605'),
        'Name',
        'Name',
        NULL,
        'TEXT',
        510,
        0,
        0,
        FALSE,
        NULL,
        FALSE,
        FALSE,
        TRUE,
        FALSE,
        NULL,
        NULL,
        TRUE,
        TRUE,
        FALSE,
        TRUE,
        FALSE,
        FALSE,
        'Search',
        NOW(),
        NOW()
        );
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM ${mjSchema}."EntityField" WHERE "ID" = 'abc08616-bc3e-441f-8e7d-a4274959c326' OR ("EntityID" = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605' AND "Name" = 'Description')
    ) THEN
        INSERT INTO ${mjSchema}."EntityField"
        (
        "ID",
        "EntityID",
        "Sequence",
        "Name",
        "DisplayName",
        "Description",
        "Type",
        "Length",
        "Precision",
        "Scale",
        "AllowsNull",
        "DefaultValue",
        "AutoIncrement",
        "AllowUpdateAPI",
        "IsVirtual",
        "IsComputed",
        "RelatedEntityID",
        "RelatedEntityFieldName",
        "IsNameField",
        "IncludeInUserSearchAPI",
        "IncludeRelatedEntityNameFieldInBaseView",
        "DefaultInView",
        "IsPrimaryKey",
        "IsUnique",
        "RelatedEntityDisplayType",
        "__mj_CreatedAt",
        "__mj_UpdatedAt"
        )
        VALUES
        (
        'abc08616-bc3e-441f-8e7d-a4274959c326',
        'DC8E0F5B-E172-4FD5-B648-8B4544F8C605', -- "Entity": "MJ_BizApps_Tasks_GitHub": "Git" "Hub" "Issue" "Tasks"
        (SELECT COALESCE(MAX("Sequence"), 0) + 1 FROM ${mjSchema}."EntityField" WHERE "EntityID" = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605'),
        'Description',
        'Description',
        NULL,
        'TEXT',
        -1,
        0,
        0,
        TRUE,
        NULL,
        FALSE,
        FALSE,
        TRUE,
        FALSE,
        NULL,
        NULL,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        'Search',
        NOW(),
        NOW()
        );
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM ${mjSchema}."EntityField" WHERE "ID" = '104159ff-db47-414c-a573-22218c8e246e' OR ("EntityID" = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605' AND "Name" = 'TypeID')
    ) THEN
        INSERT INTO ${mjSchema}."EntityField"
        (
        "ID",
        "EntityID",
        "Sequence",
        "Name",
        "DisplayName",
        "Description",
        "Type",
        "Length",
        "Precision",
        "Scale",
        "AllowsNull",
        "DefaultValue",
        "AutoIncrement",
        "AllowUpdateAPI",
        "IsVirtual",
        "IsComputed",
        "RelatedEntityID",
        "RelatedEntityFieldName",
        "IsNameField",
        "IncludeInUserSearchAPI",
        "IncludeRelatedEntityNameFieldInBaseView",
        "DefaultInView",
        "IsPrimaryKey",
        "IsUnique",
        "RelatedEntityDisplayType",
        "__mj_CreatedAt",
        "__mj_UpdatedAt"
        )
        VALUES
        (
        '104159ff-db47-414c-a573-22218c8e246e',
        'DC8E0F5B-E172-4FD5-B648-8B4544F8C605', -- "Entity": "MJ_BizApps_Tasks_GitHub": "Git" "Hub" "Issue" "Tasks"
        (SELECT COALESCE(MAX("Sequence"), 0) + 1 FROM ${mjSchema}."EntityField" WHERE "EntityID" = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605'),
        'TypeID',
        'Type ID',
        NULL,
        'UUID',
        16,
        0,
        0,
        FALSE,
        NULL,
        FALSE,
        FALSE,
        TRUE,
        FALSE,
        NULL,
        NULL,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        'Search',
        NOW(),
        NOW()
        );
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM ${mjSchema}."EntityField" WHERE "ID" = 'bee37b1e-65c9-4b3b-8e1e-52307578d3f3' OR ("EntityID" = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605' AND "Name" = 'CategoryID')
    ) THEN
        INSERT INTO ${mjSchema}."EntityField"
        (
        "ID",
        "EntityID",
        "Sequence",
        "Name",
        "DisplayName",
        "Description",
        "Type",
        "Length",
        "Precision",
        "Scale",
        "AllowsNull",
        "DefaultValue",
        "AutoIncrement",
        "AllowUpdateAPI",
        "IsVirtual",
        "IsComputed",
        "RelatedEntityID",
        "RelatedEntityFieldName",
        "IsNameField",
        "IncludeInUserSearchAPI",
        "IncludeRelatedEntityNameFieldInBaseView",
        "DefaultInView",
        "IsPrimaryKey",
        "IsUnique",
        "RelatedEntityDisplayType",
        "__mj_CreatedAt",
        "__mj_UpdatedAt"
        )
        VALUES
        (
        'bee37b1e-65c9-4b3b-8e1e-52307578d3f3',
        'DC8E0F5B-E172-4FD5-B648-8B4544F8C605', -- "Entity": "MJ_BizApps_Tasks_GitHub": "Git" "Hub" "Issue" "Tasks"
        (SELECT COALESCE(MAX("Sequence"), 0) + 1 FROM ${mjSchema}."EntityField" WHERE "EntityID" = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605'),
        'CategoryID',
        'Category ID',
        NULL,
        'UUID',
        16,
        0,
        0,
        TRUE,
        NULL,
        FALSE,
        FALSE,
        TRUE,
        FALSE,
        NULL,
        NULL,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        'Search',
        NOW(),
        NOW()
        );
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM ${mjSchema}."EntityField" WHERE "ID" = 'b3889303-f49f-4d92-853f-65ac124f359d' OR ("EntityID" = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605' AND "Name" = 'ParentID')
    ) THEN
        INSERT INTO ${mjSchema}."EntityField"
        (
        "ID",
        "EntityID",
        "Sequence",
        "Name",
        "DisplayName",
        "Description",
        "Type",
        "Length",
        "Precision",
        "Scale",
        "AllowsNull",
        "DefaultValue",
        "AutoIncrement",
        "AllowUpdateAPI",
        "IsVirtual",
        "IsComputed",
        "RelatedEntityID",
        "RelatedEntityFieldName",
        "IsNameField",
        "IncludeInUserSearchAPI",
        "IncludeRelatedEntityNameFieldInBaseView",
        "DefaultInView",
        "IsPrimaryKey",
        "IsUnique",
        "RelatedEntityDisplayType",
        "__mj_CreatedAt",
        "__mj_UpdatedAt"
        )
        VALUES
        (
        'b3889303-f49f-4d92-853f-65ac124f359d',
        'DC8E0F5B-E172-4FD5-B648-8B4544F8C605', -- "Entity": "MJ_BizApps_Tasks_GitHub": "Git" "Hub" "Issue" "Tasks"
        (SELECT COALESCE(MAX("Sequence"), 0) + 1 FROM ${mjSchema}."EntityField" WHERE "EntityID" = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605'),
        'ParentID',
        'Parent ID',
        NULL,
        'UUID',
        16,
        0,
        0,
        TRUE,
        NULL,
        FALSE,
        FALSE,
        TRUE,
        FALSE,
        NULL,
        NULL,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        'Search',
        NOW(),
        NOW()
        );
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM ${mjSchema}."EntityField" WHERE "ID" = 'a65eda96-67f2-4c99-b96c-65388a906aac' OR ("EntityID" = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605' AND "Name" = 'Status')
    ) THEN
        INSERT INTO ${mjSchema}."EntityField"
        (
        "ID",
        "EntityID",
        "Sequence",
        "Name",
        "DisplayName",
        "Description",
        "Type",
        "Length",
        "Precision",
        "Scale",
        "AllowsNull",
        "DefaultValue",
        "AutoIncrement",
        "AllowUpdateAPI",
        "IsVirtual",
        "IsComputed",
        "RelatedEntityID",
        "RelatedEntityFieldName",
        "IsNameField",
        "IncludeInUserSearchAPI",
        "IncludeRelatedEntityNameFieldInBaseView",
        "DefaultInView",
        "IsPrimaryKey",
        "IsUnique",
        "RelatedEntityDisplayType",
        "__mj_CreatedAt",
        "__mj_UpdatedAt"
        )
        VALUES
        (
        'a65eda96-67f2-4c99-b96c-65388a906aac',
        'DC8E0F5B-E172-4FD5-B648-8B4544F8C605', -- "Entity": "MJ_BizApps_Tasks_GitHub": "Git" "Hub" "Issue" "Tasks"
        (SELECT COALESCE(MAX("Sequence"), 0) + 1 FROM ${mjSchema}."EntityField" WHERE "EntityID" = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605'),
        'Status',
        'Status',
        NULL,
        'TEXT',
        100,
        0,
        0,
        FALSE,
        NULL,
        FALSE,
        FALSE,
        TRUE,
        FALSE,
        NULL,
        NULL,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        'Search',
        NOW(),
        NOW()
        );
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM ${mjSchema}."EntityField" WHERE "ID" = 'd70abd8c-2ac1-44e1-aea2-945d6daa9ed7' OR ("EntityID" = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605' AND "Name" = 'Priority')
    ) THEN
        INSERT INTO ${mjSchema}."EntityField"
        (
        "ID",
        "EntityID",
        "Sequence",
        "Name",
        "DisplayName",
        "Description",
        "Type",
        "Length",
        "Precision",
        "Scale",
        "AllowsNull",
        "DefaultValue",
        "AutoIncrement",
        "AllowUpdateAPI",
        "IsVirtual",
        "IsComputed",
        "RelatedEntityID",
        "RelatedEntityFieldName",
        "IsNameField",
        "IncludeInUserSearchAPI",
        "IncludeRelatedEntityNameFieldInBaseView",
        "DefaultInView",
        "IsPrimaryKey",
        "IsUnique",
        "RelatedEntityDisplayType",
        "__mj_CreatedAt",
        "__mj_UpdatedAt"
        )
        VALUES
        (
        'd70abd8c-2ac1-44e1-aea2-945d6daa9ed7',
        'DC8E0F5B-E172-4FD5-B648-8B4544F8C605', -- "Entity": "MJ_BizApps_Tasks_GitHub": "Git" "Hub" "Issue" "Tasks"
        (SELECT COALESCE(MAX("Sequence"), 0) + 1 FROM ${mjSchema}."EntityField" WHERE "EntityID" = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605'),
        'Priority',
        'Priority',
        NULL,
        'TEXT',
        40,
        0,
        0,
        FALSE,
        NULL,
        FALSE,
        FALSE,
        TRUE,
        FALSE,
        NULL,
        NULL,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        'Search',
        NOW(),
        NOW()
        );
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM ${mjSchema}."EntityField" WHERE "ID" = 'e28af650-ab4a-45bb-a94d-814467a2536d' OR ("EntityID" = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605' AND "Name" = 'StartedAt')
    ) THEN
        INSERT INTO ${mjSchema}."EntityField"
        (
        "ID",
        "EntityID",
        "Sequence",
        "Name",
        "DisplayName",
        "Description",
        "Type",
        "Length",
        "Precision",
        "Scale",
        "AllowsNull",
        "DefaultValue",
        "AutoIncrement",
        "AllowUpdateAPI",
        "IsVirtual",
        "IsComputed",
        "RelatedEntityID",
        "RelatedEntityFieldName",
        "IsNameField",
        "IncludeInUserSearchAPI",
        "IncludeRelatedEntityNameFieldInBaseView",
        "DefaultInView",
        "IsPrimaryKey",
        "IsUnique",
        "RelatedEntityDisplayType",
        "__mj_CreatedAt",
        "__mj_UpdatedAt"
        )
        VALUES
        (
        'e28af650-ab4a-45bb-a94d-814467a2536d',
        'DC8E0F5B-E172-4FD5-B648-8B4544F8C605', -- "Entity": "MJ_BizApps_Tasks_GitHub": "Git" "Hub" "Issue" "Tasks"
        (SELECT COALESCE(MAX("Sequence"), 0) + 1 FROM ${mjSchema}."EntityField" WHERE "EntityID" = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605'),
        'StartedAt',
        'Started At',
        NULL,
        'TIMESTAMPTZ',
        10,
        34,
        7,
        TRUE,
        NULL,
        FALSE,
        FALSE,
        TRUE,
        FALSE,
        NULL,
        NULL,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        'Search',
        NOW(),
        NOW()
        );
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM ${mjSchema}."EntityField" WHERE "ID" = 'b83a675f-795c-47ed-81f4-cbbd5ff4d929' OR ("EntityID" = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605' AND "Name" = 'DueAt')
    ) THEN
        INSERT INTO ${mjSchema}."EntityField"
        (
        "ID",
        "EntityID",
        "Sequence",
        "Name",
        "DisplayName",
        "Description",
        "Type",
        "Length",
        "Precision",
        "Scale",
        "AllowsNull",
        "DefaultValue",
        "AutoIncrement",
        "AllowUpdateAPI",
        "IsVirtual",
        "IsComputed",
        "RelatedEntityID",
        "RelatedEntityFieldName",
        "IsNameField",
        "IncludeInUserSearchAPI",
        "IncludeRelatedEntityNameFieldInBaseView",
        "DefaultInView",
        "IsPrimaryKey",
        "IsUnique",
        "RelatedEntityDisplayType",
        "__mj_CreatedAt",
        "__mj_UpdatedAt"
        )
        VALUES
        (
        'b83a675f-795c-47ed-81f4-cbbd5ff4d929',
        'DC8E0F5B-E172-4FD5-B648-8B4544F8C605', -- "Entity": "MJ_BizApps_Tasks_GitHub": "Git" "Hub" "Issue" "Tasks"
        (SELECT COALESCE(MAX("Sequence"), 0) + 1 FROM ${mjSchema}."EntityField" WHERE "EntityID" = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605'),
        'DueAt',
        'Due At',
        NULL,
        'TIMESTAMPTZ',
        10,
        34,
        7,
        TRUE,
        NULL,
        FALSE,
        FALSE,
        TRUE,
        FALSE,
        NULL,
        NULL,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        'Search',
        NOW(),
        NOW()
        );
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM ${mjSchema}."EntityField" WHERE "ID" = 'cef54e7e-100c-432e-9d83-fe29b47c5f73' OR ("EntityID" = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605' AND "Name" = 'CompletedAt')
    ) THEN
        INSERT INTO ${mjSchema}."EntityField"
        (
        "ID",
        "EntityID",
        "Sequence",
        "Name",
        "DisplayName",
        "Description",
        "Type",
        "Length",
        "Precision",
        "Scale",
        "AllowsNull",
        "DefaultValue",
        "AutoIncrement",
        "AllowUpdateAPI",
        "IsVirtual",
        "IsComputed",
        "RelatedEntityID",
        "RelatedEntityFieldName",
        "IsNameField",
        "IncludeInUserSearchAPI",
        "IncludeRelatedEntityNameFieldInBaseView",
        "DefaultInView",
        "IsPrimaryKey",
        "IsUnique",
        "RelatedEntityDisplayType",
        "__mj_CreatedAt",
        "__mj_UpdatedAt"
        )
        VALUES
        (
        'cef54e7e-100c-432e-9d83-fe29b47c5f73',
        'DC8E0F5B-E172-4FD5-B648-8B4544F8C605', -- "Entity": "MJ_BizApps_Tasks_GitHub": "Git" "Hub" "Issue" "Tasks"
        (SELECT COALESCE(MAX("Sequence"), 0) + 1 FROM ${mjSchema}."EntityField" WHERE "EntityID" = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605'),
        'CompletedAt',
        'Completed At',
        NULL,
        'TIMESTAMPTZ',
        10,
        34,
        7,
        TRUE,
        NULL,
        FALSE,
        FALSE,
        TRUE,
        FALSE,
        NULL,
        NULL,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        'Search',
        NOW(),
        NOW()
        );
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM ${mjSchema}."EntityField" WHERE "ID" = 'c9363ae8-2c58-46c5-b437-c7d26a02c353' OR ("EntityID" = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605' AND "Name" = 'HoursEstimated')
    ) THEN
        INSERT INTO ${mjSchema}."EntityField"
        (
        "ID",
        "EntityID",
        "Sequence",
        "Name",
        "DisplayName",
        "Description",
        "Type",
        "Length",
        "Precision",
        "Scale",
        "AllowsNull",
        "DefaultValue",
        "AutoIncrement",
        "AllowUpdateAPI",
        "IsVirtual",
        "IsComputed",
        "RelatedEntityID",
        "RelatedEntityFieldName",
        "IsNameField",
        "IncludeInUserSearchAPI",
        "IncludeRelatedEntityNameFieldInBaseView",
        "DefaultInView",
        "IsPrimaryKey",
        "IsUnique",
        "RelatedEntityDisplayType",
        "__mj_CreatedAt",
        "__mj_UpdatedAt"
        )
        VALUES
        (
        'c9363ae8-2c58-46c5-b437-c7d26a02c353',
        'DC8E0F5B-E172-4FD5-B648-8B4544F8C605', -- "Entity": "MJ_BizApps_Tasks_GitHub": "Git" "Hub" "Issue" "Tasks"
        (SELECT COALESCE(MAX("Sequence"), 0) + 1 FROM ${mjSchema}."EntityField" WHERE "EntityID" = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605'),
        'HoursEstimated',
        'Hours Estimated',
        NULL,
        'decimal',
        5,
        8,
        2,
        TRUE,
        NULL,
        FALSE,
        FALSE,
        TRUE,
        FALSE,
        NULL,
        NULL,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        'Search',
        NOW(),
        NOW()
        );
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM ${mjSchema}."EntityField" WHERE "ID" = '3f2f697f-56e2-450f-bf03-77dc470d5754' OR ("EntityID" = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605' AND "Name" = 'HoursActual')
    ) THEN
        INSERT INTO ${mjSchema}."EntityField"
        (
        "ID",
        "EntityID",
        "Sequence",
        "Name",
        "DisplayName",
        "Description",
        "Type",
        "Length",
        "Precision",
        "Scale",
        "AllowsNull",
        "DefaultValue",
        "AutoIncrement",
        "AllowUpdateAPI",
        "IsVirtual",
        "IsComputed",
        "RelatedEntityID",
        "RelatedEntityFieldName",
        "IsNameField",
        "IncludeInUserSearchAPI",
        "IncludeRelatedEntityNameFieldInBaseView",
        "DefaultInView",
        "IsPrimaryKey",
        "IsUnique",
        "RelatedEntityDisplayType",
        "__mj_CreatedAt",
        "__mj_UpdatedAt"
        )
        VALUES
        (
        '3f2f697f-56e2-450f-bf03-77dc470d5754',
        'DC8E0F5B-E172-4FD5-B648-8B4544F8C605', -- "Entity": "MJ_BizApps_Tasks_GitHub": "Git" "Hub" "Issue" "Tasks"
        (SELECT COALESCE(MAX("Sequence"), 0) + 1 FROM ${mjSchema}."EntityField" WHERE "EntityID" = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605'),
        'HoursActual',
        'Hours Actual',
        NULL,
        'decimal',
        5,
        8,
        2,
        TRUE,
        NULL,
        FALSE,
        FALSE,
        TRUE,
        FALSE,
        NULL,
        NULL,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        'Search',
        NOW(),
        NOW()
        );
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM ${mjSchema}."EntityField" WHERE "ID" = '732fa3a2-4e55-44c0-9f6b-fe50b894c27e' OR ("EntityID" = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605' AND "Name" = 'PercentComplete')
    ) THEN
        INSERT INTO ${mjSchema}."EntityField"
        (
        "ID",
        "EntityID",
        "Sequence",
        "Name",
        "DisplayName",
        "Description",
        "Type",
        "Length",
        "Precision",
        "Scale",
        "AllowsNull",
        "DefaultValue",
        "AutoIncrement",
        "AllowUpdateAPI",
        "IsVirtual",
        "IsComputed",
        "RelatedEntityID",
        "RelatedEntityFieldName",
        "IsNameField",
        "IncludeInUserSearchAPI",
        "IncludeRelatedEntityNameFieldInBaseView",
        "DefaultInView",
        "IsPrimaryKey",
        "IsUnique",
        "RelatedEntityDisplayType",
        "__mj_CreatedAt",
        "__mj_UpdatedAt"
        )
        VALUES
        (
        '732fa3a2-4e55-44c0-9f6b-fe50b894c27e',
        'DC8E0F5B-E172-4FD5-B648-8B4544F8C605', -- "Entity": "MJ_BizApps_Tasks_GitHub": "Git" "Hub" "Issue" "Tasks"
        (SELECT COALESCE(MAX("Sequence"), 0) + 1 FROM ${mjSchema}."EntityField" WHERE "EntityID" = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605'),
        'PercentComplete',
        'Percent Complete',
        NULL,
        'INTEGER',
        4,
        10,
        0,
        FALSE,
        NULL,
        FALSE,
        FALSE,
        TRUE,
        FALSE,
        NULL,
        NULL,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        'Search',
        NOW(),
        NOW()
        );
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM ${mjSchema}."EntityField" WHERE "ID" = '77ec9524-1745-4341-b0fd-ebe74e176e4a' OR ("EntityID" = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605' AND "Name" = 'Sequence')
    ) THEN
        INSERT INTO ${mjSchema}."EntityField"
        (
        "ID",
        "EntityID",
        "Sequence",
        "Name",
        "DisplayName",
        "Description",
        "Type",
        "Length",
        "Precision",
        "Scale",
        "AllowsNull",
        "DefaultValue",
        "AutoIncrement",
        "AllowUpdateAPI",
        "IsVirtual",
        "IsComputed",
        "RelatedEntityID",
        "RelatedEntityFieldName",
        "IsNameField",
        "IncludeInUserSearchAPI",
        "IncludeRelatedEntityNameFieldInBaseView",
        "DefaultInView",
        "IsPrimaryKey",
        "IsUnique",
        "RelatedEntityDisplayType",
        "__mj_CreatedAt",
        "__mj_UpdatedAt"
        )
        VALUES
        (
        '77ec9524-1745-4341-b0fd-ebe74e176e4a',
        'DC8E0F5B-E172-4FD5-B648-8B4544F8C605', -- "Entity": "MJ_BizApps_Tasks_GitHub": "Git" "Hub" "Issue" "Tasks"
        (SELECT COALESCE(MAX("Sequence"), 0) + 1 FROM ${mjSchema}."EntityField" WHERE "EntityID" = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605'),
        'Sequence',
        'Sequence',
        NULL,
        'INTEGER',
        4,
        10,
        0,
        FALSE,
        NULL,
        FALSE,
        FALSE,
        TRUE,
        FALSE,
        NULL,
        NULL,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        'Search',
        NOW(),
        NOW()
        );
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM ${mjSchema}."EntityField" WHERE "ID" = 'eaf33611-eb3d-4621-bc57-292f137e43c4' OR ("EntityID" = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605' AND "Name" = 'BlockedReason')
    ) THEN
        INSERT INTO ${mjSchema}."EntityField"
        (
        "ID",
        "EntityID",
        "Sequence",
        "Name",
        "DisplayName",
        "Description",
        "Type",
        "Length",
        "Precision",
        "Scale",
        "AllowsNull",
        "DefaultValue",
        "AutoIncrement",
        "AllowUpdateAPI",
        "IsVirtual",
        "IsComputed",
        "RelatedEntityID",
        "RelatedEntityFieldName",
        "IsNameField",
        "IncludeInUserSearchAPI",
        "IncludeRelatedEntityNameFieldInBaseView",
        "DefaultInView",
        "IsPrimaryKey",
        "IsUnique",
        "RelatedEntityDisplayType",
        "__mj_CreatedAt",
        "__mj_UpdatedAt"
        )
        VALUES
        (
        'eaf33611-eb3d-4621-bc57-292f137e43c4',
        'DC8E0F5B-E172-4FD5-B648-8B4544F8C605', -- "Entity": "MJ_BizApps_Tasks_GitHub": "Git" "Hub" "Issue" "Tasks"
        (SELECT COALESCE(MAX("Sequence"), 0) + 1 FROM ${mjSchema}."EntityField" WHERE "EntityID" = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605'),
        'BlockedReason',
        'Blocked Reason',
        NULL,
        'TEXT',
        -1,
        0,
        0,
        TRUE,
        NULL,
        FALSE,
        FALSE,
        TRUE,
        FALSE,
        NULL,
        NULL,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        'Search',
        NOW(),
        NOW()
        );
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM ${mjSchema}."EntityField" WHERE "ID" = 'e856766e-55a2-4de8-990e-86d7d1e7056a' OR ("EntityID" = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605' AND "Name" = 'CompletionNotes')
    ) THEN
        INSERT INTO ${mjSchema}."EntityField"
        (
        "ID",
        "EntityID",
        "Sequence",
        "Name",
        "DisplayName",
        "Description",
        "Type",
        "Length",
        "Precision",
        "Scale",
        "AllowsNull",
        "DefaultValue",
        "AutoIncrement",
        "AllowUpdateAPI",
        "IsVirtual",
        "IsComputed",
        "RelatedEntityID",
        "RelatedEntityFieldName",
        "IsNameField",
        "IncludeInUserSearchAPI",
        "IncludeRelatedEntityNameFieldInBaseView",
        "DefaultInView",
        "IsPrimaryKey",
        "IsUnique",
        "RelatedEntityDisplayType",
        "__mj_CreatedAt",
        "__mj_UpdatedAt"
        )
        VALUES
        (
        'e856766e-55a2-4de8-990e-86d7d1e7056a',
        'DC8E0F5B-E172-4FD5-B648-8B4544F8C605', -- "Entity": "MJ_BizApps_Tasks_GitHub": "Git" "Hub" "Issue" "Tasks"
        (SELECT COALESCE(MAX("Sequence"), 0) + 1 FROM ${mjSchema}."EntityField" WHERE "EntityID" = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605'),
        'CompletionNotes',
        'Completion Notes',
        NULL,
        'TEXT',
        -1,
        0,
        0,
        TRUE,
        NULL,
        FALSE,
        FALSE,
        TRUE,
        FALSE,
        NULL,
        NULL,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        'Search',
        NOW(),
        NOW()
        );
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM ${mjSchema}."EntityField" WHERE "ID" = '6199ac88-26d6-4320-8b59-952c0e1945ea' OR ("EntityID" = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605' AND "Name" = 'CreatedByPersonID')
    ) THEN
        INSERT INTO ${mjSchema}."EntityField"
        (
        "ID",
        "EntityID",
        "Sequence",
        "Name",
        "DisplayName",
        "Description",
        "Type",
        "Length",
        "Precision",
        "Scale",
        "AllowsNull",
        "DefaultValue",
        "AutoIncrement",
        "AllowUpdateAPI",
        "IsVirtual",
        "IsComputed",
        "RelatedEntityID",
        "RelatedEntityFieldName",
        "IsNameField",
        "IncludeInUserSearchAPI",
        "IncludeRelatedEntityNameFieldInBaseView",
        "DefaultInView",
        "IsPrimaryKey",
        "IsUnique",
        "RelatedEntityDisplayType",
        "__mj_CreatedAt",
        "__mj_UpdatedAt"
        )
        VALUES
        (
        '6199ac88-26d6-4320-8b59-952c0e1945ea',
        'DC8E0F5B-E172-4FD5-B648-8B4544F8C605', -- "Entity": "MJ_BizApps_Tasks_GitHub": "Git" "Hub" "Issue" "Tasks"
        (SELECT COALESCE(MAX("Sequence"), 0) + 1 FROM ${mjSchema}."EntityField" WHERE "EntityID" = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605'),
        'CreatedByPersonID',
        'Created By Person ID',
        NULL,
        'UUID',
        16,
        0,
        0,
        TRUE,
        NULL,
        FALSE,
        FALSE,
        TRUE,
        FALSE,
        NULL,
        NULL,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        'Search',
        NOW(),
        NOW()
        );
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM ${mjSchema}."EntityField" WHERE "ID" = 'ce26b855-64ac-45b7-9549-39ac48fa7fa8' OR ("EntityID" = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605' AND "Name" = 'OverdueNotifiedAt')
    ) THEN
        INSERT INTO ${mjSchema}."EntityField"
        (
        "ID",
        "EntityID",
        "Sequence",
        "Name",
        "DisplayName",
        "Description",
        "Type",
        "Length",
        "Precision",
        "Scale",
        "AllowsNull",
        "DefaultValue",
        "AutoIncrement",
        "AllowUpdateAPI",
        "IsVirtual",
        "IsComputed",
        "RelatedEntityID",
        "RelatedEntityFieldName",
        "IsNameField",
        "IncludeInUserSearchAPI",
        "IncludeRelatedEntityNameFieldInBaseView",
        "DefaultInView",
        "IsPrimaryKey",
        "IsUnique",
        "RelatedEntityDisplayType",
        "__mj_CreatedAt",
        "__mj_UpdatedAt"
        )
        VALUES
        (
        'ce26b855-64ac-45b7-9549-39ac48fa7fa8',
        'DC8E0F5B-E172-4FD5-B648-8B4544F8C605', -- "Entity": "MJ_BizApps_Tasks_GitHub": "Git" "Hub" "Issue" "Tasks"
        (SELECT COALESCE(MAX("Sequence"), 0) + 1 FROM ${mjSchema}."EntityField" WHERE "EntityID" = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605'),
        'OverdueNotifiedAt',
        'Overdue Notified At',
        NULL,
        'TIMESTAMPTZ',
        10,
        34,
        7,
        TRUE,
        NULL,
        FALSE,
        FALSE,
        TRUE,
        FALSE,
        NULL,
        NULL,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        'Search',
        NOW(),
        NOW()
        );
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM ${mjSchema}."EntityField" WHERE "ID" = 'f0abfe53-246f-41d8-b25a-e462fc412615' OR ("EntityID" = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605' AND "Name" = 'TaskTypeStatusID')
    ) THEN
        INSERT INTO ${mjSchema}."EntityField"
        (
        "ID",
        "EntityID",
        "Sequence",
        "Name",
        "DisplayName",
        "Description",
        "Type",
        "Length",
        "Precision",
        "Scale",
        "AllowsNull",
        "DefaultValue",
        "AutoIncrement",
        "AllowUpdateAPI",
        "IsVirtual",
        "IsComputed",
        "RelatedEntityID",
        "RelatedEntityFieldName",
        "IsNameField",
        "IncludeInUserSearchAPI",
        "IncludeRelatedEntityNameFieldInBaseView",
        "DefaultInView",
        "IsPrimaryKey",
        "IsUnique",
        "RelatedEntityDisplayType",
        "__mj_CreatedAt",
        "__mj_UpdatedAt"
        )
        VALUES
        (
        'f0abfe53-246f-41d8-b25a-e462fc412615',
        'DC8E0F5B-E172-4FD5-B648-8B4544F8C605', -- "Entity": "MJ_BizApps_Tasks_GitHub": "Git" "Hub" "Issue" "Tasks"
        (SELECT COALESCE(MAX("Sequence"), 0) + 1 FROM ${mjSchema}."EntityField" WHERE "EntityID" = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605'),
        'TaskTypeStatusID',
        'Task Type Status ID',
        NULL,
        'UUID',
        16,
        0,
        0,
        TRUE,
        NULL,
        FALSE,
        FALSE,
        TRUE,
        FALSE,
        NULL,
        NULL,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        'Search',
        NOW(),
        NOW()
        );
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM ${mjSchema}."EntityField" WHERE "ID" = 'd1ab1a5c-a1ee-4ec5-95fe-4fd4c8ab7630' OR ("EntityID" = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605' AND "Name" = 'PredictedSLABreachProbability')
    ) THEN
        INSERT INTO ${mjSchema}."EntityField"
        (
        "ID",
        "EntityID",
        "Sequence",
        "Name",
        "DisplayName",
        "Description",
        "Type",
        "Length",
        "Precision",
        "Scale",
        "AllowsNull",
        "DefaultValue",
        "AutoIncrement",
        "AllowUpdateAPI",
        "IsVirtual",
        "IsComputed",
        "RelatedEntityID",
        "RelatedEntityFieldName",
        "IsNameField",
        "IncludeInUserSearchAPI",
        "IncludeRelatedEntityNameFieldInBaseView",
        "DefaultInView",
        "IsPrimaryKey",
        "IsUnique",
        "RelatedEntityDisplayType",
        "__mj_CreatedAt",
        "__mj_UpdatedAt"
        )
        VALUES
        (
        'd1ab1a5c-a1ee-4ec5-95fe-4fd4c8ab7630',
        'DC8E0F5B-E172-4FD5-B648-8B4544F8C605', -- "Entity": "MJ_BizApps_Tasks_GitHub": "Git" "Hub" "Issue" "Tasks"
        (SELECT COALESCE(MAX("Sequence"), 0) + 1 FROM ${mjSchema}."EntityField" WHERE "EntityID" = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605'),
        'PredictedSLABreachProbability',
        'Predicted SLA Breach Probability',
        NULL,
        'decimal',
        5,
        5,
        4,
        TRUE,
        NULL,
        FALSE,
        FALSE,
        TRUE,
        FALSE,
        NULL,
        NULL,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        'Search',
        NOW(),
        NOW()
        );
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM ${mjSchema}."EntityField" WHERE "ID" = 'd2574ddb-325f-473d-997a-66cc43309934' OR ("EntityID" = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605' AND "Name" = 'PredictedSLARiskBand')
    ) THEN
        INSERT INTO ${mjSchema}."EntityField"
        (
        "ID",
        "EntityID",
        "Sequence",
        "Name",
        "DisplayName",
        "Description",
        "Type",
        "Length",
        "Precision",
        "Scale",
        "AllowsNull",
        "DefaultValue",
        "AutoIncrement",
        "AllowUpdateAPI",
        "IsVirtual",
        "IsComputed",
        "RelatedEntityID",
        "RelatedEntityFieldName",
        "IsNameField",
        "IncludeInUserSearchAPI",
        "IncludeRelatedEntityNameFieldInBaseView",
        "DefaultInView",
        "IsPrimaryKey",
        "IsUnique",
        "RelatedEntityDisplayType",
        "__mj_CreatedAt",
        "__mj_UpdatedAt"
        )
        VALUES
        (
        'd2574ddb-325f-473d-997a-66cc43309934',
        'DC8E0F5B-E172-4FD5-B648-8B4544F8C605', -- "Entity": "MJ_BizApps_Tasks_GitHub": "Git" "Hub" "Issue" "Tasks"
        (SELECT COALESCE(MAX("Sequence"), 0) + 1 FROM ${mjSchema}."EntityField" WHERE "EntityID" = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605'),
        'PredictedSLARiskBand',
        'Predicted SLA Risk Band',
        NULL,
        'TEXT',
        40,
        0,
        0,
        TRUE,
        NULL,
        FALSE,
        FALSE,
        TRUE,
        FALSE,
        NULL,
        NULL,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        'Search',
        NOW(),
        NOW()
        );
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM ${mjSchema}."EntityField" WHERE "ID" = '947c6bae-94d3-4999-ac0f-dafe404e008f' OR ("EntityID" = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605' AND "Name" = 'PredictedSLAScoredAt')
    ) THEN
        INSERT INTO ${mjSchema}."EntityField"
        (
        "ID",
        "EntityID",
        "Sequence",
        "Name",
        "DisplayName",
        "Description",
        "Type",
        "Length",
        "Precision",
        "Scale",
        "AllowsNull",
        "DefaultValue",
        "AutoIncrement",
        "AllowUpdateAPI",
        "IsVirtual",
        "IsComputed",
        "RelatedEntityID",
        "RelatedEntityFieldName",
        "IsNameField",
        "IncludeInUserSearchAPI",
        "IncludeRelatedEntityNameFieldInBaseView",
        "DefaultInView",
        "IsPrimaryKey",
        "IsUnique",
        "RelatedEntityDisplayType",
        "__mj_CreatedAt",
        "__mj_UpdatedAt"
        )
        VALUES
        (
        '947c6bae-94d3-4999-ac0f-dafe404e008f',
        'DC8E0F5B-E172-4FD5-B648-8B4544F8C605', -- "Entity": "MJ_BizApps_Tasks_GitHub": "Git" "Hub" "Issue" "Tasks"
        (SELECT COALESCE(MAX("Sequence"), 0) + 1 FROM ${mjSchema}."EntityField" WHERE "EntityID" = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605'),
        'PredictedSLAScoredAt',
        'Predicted SLA Scored At',
        NULL,
        'TIMESTAMPTZ',
        10,
        34,
        7,
        TRUE,
        NULL,
        FALSE,
        FALSE,
        TRUE,
        FALSE,
        NULL,
        NULL,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        'Search',
        NOW(),
        NOW()
        );
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM ${mjSchema}."EntityField" WHERE "ID" = '8efe7eac-45db-4b89-9221-2b19b99068b9' OR ("EntityID" = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605' AND "Name" = 'HealthStatus')
    ) THEN
        INSERT INTO ${mjSchema}."EntityField"
        (
        "ID",
        "EntityID",
        "Sequence",
        "Name",
        "DisplayName",
        "Description",
        "Type",
        "Length",
        "Precision",
        "Scale",
        "AllowsNull",
        "DefaultValue",
        "AutoIncrement",
        "AllowUpdateAPI",
        "IsVirtual",
        "IsComputed",
        "RelatedEntityID",
        "RelatedEntityFieldName",
        "IsNameField",
        "IncludeInUserSearchAPI",
        "IncludeRelatedEntityNameFieldInBaseView",
        "DefaultInView",
        "IsPrimaryKey",
        "IsUnique",
        "RelatedEntityDisplayType",
        "__mj_CreatedAt",
        "__mj_UpdatedAt"
        )
        VALUES
        (
        '8efe7eac-45db-4b89-9221-2b19b99068b9',
        'DC8E0F5B-E172-4FD5-B648-8B4544F8C605', -- "Entity": "MJ_BizApps_Tasks_GitHub": "Git" "Hub" "Issue" "Tasks"
        (SELECT COALESCE(MAX("Sequence"), 0) + 1 FROM ${mjSchema}."EntityField" WHERE "EntityID" = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605'),
        'HealthStatus',
        'Health Status',
        NULL,
        'TEXT',
        40,
        0,
        0,
        TRUE,
        NULL,
        FALSE,
        FALSE,
        TRUE,
        FALSE,
        NULL,
        NULL,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        'Search',
        NOW(),
        NOW()
        );
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM ${mjSchema}."EntityField" WHERE "ID" = 'ea927e59-ffd9-4f5c-91bc-db57a268cb3f' OR ("EntityID" = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605' AND "Name" = 'ConfidenceScore')
    ) THEN
        INSERT INTO ${mjSchema}."EntityField"
        (
        "ID",
        "EntityID",
        "Sequence",
        "Name",
        "DisplayName",
        "Description",
        "Type",
        "Length",
        "Precision",
        "Scale",
        "AllowsNull",
        "DefaultValue",
        "AutoIncrement",
        "AllowUpdateAPI",
        "IsVirtual",
        "IsComputed",
        "RelatedEntityID",
        "RelatedEntityFieldName",
        "IsNameField",
        "IncludeInUserSearchAPI",
        "IncludeRelatedEntityNameFieldInBaseView",
        "DefaultInView",
        "IsPrimaryKey",
        "IsUnique",
        "RelatedEntityDisplayType",
        "__mj_CreatedAt",
        "__mj_UpdatedAt"
        )
        VALUES
        (
        'ea927e59-ffd9-4f5c-91bc-db57a268cb3f',
        'DC8E0F5B-E172-4FD5-B648-8B4544F8C605', -- "Entity": "MJ_BizApps_Tasks_GitHub": "Git" "Hub" "Issue" "Tasks"
        (SELECT COALESCE(MAX("Sequence"), 0) + 1 FROM ${mjSchema}."EntityField" WHERE "EntityID" = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605'),
        'ConfidenceScore',
        'Confidence Score',
        NULL,
        'INTEGER',
        4,
        10,
        0,
        TRUE,
        NULL,
        FALSE,
        FALSE,
        TRUE,
        FALSE,
        NULL,
        NULL,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        'Search',
        NOW(),
        NOW()
        );
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM ${mjSchema}."EntityField" WHERE "ID" = '835e5643-810d-4b4e-8e83-e9595428437c' OR ("EntityID" = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605' AND "Name" = 'BaselineValue')
    ) THEN
        INSERT INTO ${mjSchema}."EntityField"
        (
        "ID",
        "EntityID",
        "Sequence",
        "Name",
        "DisplayName",
        "Description",
        "Type",
        "Length",
        "Precision",
        "Scale",
        "AllowsNull",
        "DefaultValue",
        "AutoIncrement",
        "AllowUpdateAPI",
        "IsVirtual",
        "IsComputed",
        "RelatedEntityID",
        "RelatedEntityFieldName",
        "IsNameField",
        "IncludeInUserSearchAPI",
        "IncludeRelatedEntityNameFieldInBaseView",
        "DefaultInView",
        "IsPrimaryKey",
        "IsUnique",
        "RelatedEntityDisplayType",
        "__mj_CreatedAt",
        "__mj_UpdatedAt"
        )
        VALUES
        (
        '835e5643-810d-4b4e-8e83-e9595428437c',
        'DC8E0F5B-E172-4FD5-B648-8B4544F8C605', -- "Entity": "MJ_BizApps_Tasks_GitHub": "Git" "Hub" "Issue" "Tasks"
        (SELECT COALESCE(MAX("Sequence"), 0) + 1 FROM ${mjSchema}."EntityField" WHERE "EntityID" = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605'),
        'BaselineValue',
        'Baseline Value',
        NULL,
        'decimal',
        9,
        18,
        4,
        TRUE,
        NULL,
        FALSE,
        FALSE,
        TRUE,
        FALSE,
        NULL,
        NULL,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        'Search',
        NOW(),
        NOW()
        );
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM ${mjSchema}."EntityField" WHERE "ID" = '77dd9516-90ef-4855-9cf7-ca0d81b59a8f' OR ("EntityID" = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605' AND "Name" = 'TargetValue')
    ) THEN
        INSERT INTO ${mjSchema}."EntityField"
        (
        "ID",
        "EntityID",
        "Sequence",
        "Name",
        "DisplayName",
        "Description",
        "Type",
        "Length",
        "Precision",
        "Scale",
        "AllowsNull",
        "DefaultValue",
        "AutoIncrement",
        "AllowUpdateAPI",
        "IsVirtual",
        "IsComputed",
        "RelatedEntityID",
        "RelatedEntityFieldName",
        "IsNameField",
        "IncludeInUserSearchAPI",
        "IncludeRelatedEntityNameFieldInBaseView",
        "DefaultInView",
        "IsPrimaryKey",
        "IsUnique",
        "RelatedEntityDisplayType",
        "__mj_CreatedAt",
        "__mj_UpdatedAt"
        )
        VALUES
        (
        '77dd9516-90ef-4855-9cf7-ca0d81b59a8f',
        'DC8E0F5B-E172-4FD5-B648-8B4544F8C605', -- "Entity": "MJ_BizApps_Tasks_GitHub": "Git" "Hub" "Issue" "Tasks"
        (SELECT COALESCE(MAX("Sequence"), 0) + 1 FROM ${mjSchema}."EntityField" WHERE "EntityID" = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605'),
        'TargetValue',
        'Target Value',
        NULL,
        'decimal',
        9,
        18,
        4,
        TRUE,
        NULL,
        FALSE,
        FALSE,
        TRUE,
        FALSE,
        NULL,
        NULL,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        'Search',
        NOW(),
        NOW()
        );
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM ${mjSchema}."EntityField" WHERE "ID" = 'af810be2-ba61-46dd-adec-7f3fe7fb35e2' OR ("EntityID" = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605' AND "Name" = 'CurrentValue')
    ) THEN
        INSERT INTO ${mjSchema}."EntityField"
        (
        "ID",
        "EntityID",
        "Sequence",
        "Name",
        "DisplayName",
        "Description",
        "Type",
        "Length",
        "Precision",
        "Scale",
        "AllowsNull",
        "DefaultValue",
        "AutoIncrement",
        "AllowUpdateAPI",
        "IsVirtual",
        "IsComputed",
        "RelatedEntityID",
        "RelatedEntityFieldName",
        "IsNameField",
        "IncludeInUserSearchAPI",
        "IncludeRelatedEntityNameFieldInBaseView",
        "DefaultInView",
        "IsPrimaryKey",
        "IsUnique",
        "RelatedEntityDisplayType",
        "__mj_CreatedAt",
        "__mj_UpdatedAt"
        )
        VALUES
        (
        'af810be2-ba61-46dd-adec-7f3fe7fb35e2',
        'DC8E0F5B-E172-4FD5-B648-8B4544F8C605', -- "Entity": "MJ_BizApps_Tasks_GitHub": "Git" "Hub" "Issue" "Tasks"
        (SELECT COALESCE(MAX("Sequence"), 0) + 1 FROM ${mjSchema}."EntityField" WHERE "EntityID" = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605'),
        'CurrentValue',
        'Current Value',
        NULL,
        'decimal',
        9,
        18,
        4,
        TRUE,
        NULL,
        FALSE,
        FALSE,
        TRUE,
        FALSE,
        NULL,
        NULL,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        'Search',
        NOW(),
        NOW()
        );
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM ${mjSchema}."EntityField" WHERE "ID" = 'fd6fa1e2-da35-409a-9116-36640d818333' OR ("EntityID" = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605' AND "Name" = 'UnitOfMeasure')
    ) THEN
        INSERT INTO ${mjSchema}."EntityField"
        (
        "ID",
        "EntityID",
        "Sequence",
        "Name",
        "DisplayName",
        "Description",
        "Type",
        "Length",
        "Precision",
        "Scale",
        "AllowsNull",
        "DefaultValue",
        "AutoIncrement",
        "AllowUpdateAPI",
        "IsVirtual",
        "IsComputed",
        "RelatedEntityID",
        "RelatedEntityFieldName",
        "IsNameField",
        "IncludeInUserSearchAPI",
        "IncludeRelatedEntityNameFieldInBaseView",
        "DefaultInView",
        "IsPrimaryKey",
        "IsUnique",
        "RelatedEntityDisplayType",
        "__mj_CreatedAt",
        "__mj_UpdatedAt"
        )
        VALUES
        (
        'fd6fa1e2-da35-409a-9116-36640d818333',
        'DC8E0F5B-E172-4FD5-B648-8B4544F8C605', -- "Entity": "MJ_BizApps_Tasks_GitHub": "Git" "Hub" "Issue" "Tasks"
        (SELECT COALESCE(MAX("Sequence"), 0) + 1 FROM ${mjSchema}."EntityField" WHERE "EntityID" = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605'),
        'UnitOfMeasure',
        'Unit Of Measure',
        NULL,
        'TEXT',
        100,
        0,
        0,
        TRUE,
        NULL,
        FALSE,
        FALSE,
        TRUE,
        FALSE,
        NULL,
        NULL,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        'Search',
        NOW(),
        NOW()
        );
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM ${mjSchema}."EntityField" WHERE "ID" = '86b721d5-8aa2-4199-aef7-c933a6ba52ff' OR ("EntityID" = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605' AND "Name" = 'MetricDirection')
    ) THEN
        INSERT INTO ${mjSchema}."EntityField"
        (
        "ID",
        "EntityID",
        "Sequence",
        "Name",
        "DisplayName",
        "Description",
        "Type",
        "Length",
        "Precision",
        "Scale",
        "AllowsNull",
        "DefaultValue",
        "AutoIncrement",
        "AllowUpdateAPI",
        "IsVirtual",
        "IsComputed",
        "RelatedEntityID",
        "RelatedEntityFieldName",
        "IsNameField",
        "IncludeInUserSearchAPI",
        "IncludeRelatedEntityNameFieldInBaseView",
        "DefaultInView",
        "IsPrimaryKey",
        "IsUnique",
        "RelatedEntityDisplayType",
        "__mj_CreatedAt",
        "__mj_UpdatedAt"
        )
        VALUES
        (
        '86b721d5-8aa2-4199-aef7-c933a6ba52ff',
        'DC8E0F5B-E172-4FD5-B648-8B4544F8C605', -- "Entity": "MJ_BizApps_Tasks_GitHub": "Git" "Hub" "Issue" "Tasks"
        (SELECT COALESCE(MAX("Sequence"), 0) + 1 FROM ${mjSchema}."EntityField" WHERE "EntityID" = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605'),
        'MetricDirection',
        'Metric Direction',
        NULL,
        'TEXT',
        40,
        0,
        0,
        TRUE,
        NULL,
        FALSE,
        FALSE,
        TRUE,
        FALSE,
        NULL,
        NULL,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        'Search',
        NOW(),
        NOW()
        );
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM ${mjSchema}."EntityField" WHERE "ID" = '03f75dad-73a6-4c9c-b473-50af0f4dfdbf' OR ("EntityID" = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605' AND "Name" = 'RollupWeight')
    ) THEN
        INSERT INTO ${mjSchema}."EntityField"
        (
        "ID",
        "EntityID",
        "Sequence",
        "Name",
        "DisplayName",
        "Description",
        "Type",
        "Length",
        "Precision",
        "Scale",
        "AllowsNull",
        "DefaultValue",
        "AutoIncrement",
        "AllowUpdateAPI",
        "IsVirtual",
        "IsComputed",
        "RelatedEntityID",
        "RelatedEntityFieldName",
        "IsNameField",
        "IncludeInUserSearchAPI",
        "IncludeRelatedEntityNameFieldInBaseView",
        "DefaultInView",
        "IsPrimaryKey",
        "IsUnique",
        "RelatedEntityDisplayType",
        "__mj_CreatedAt",
        "__mj_UpdatedAt"
        )
        VALUES
        (
        '03f75dad-73a6-4c9c-b473-50af0f4dfdbf',
        'DC8E0F5B-E172-4FD5-B648-8B4544F8C605', -- "Entity": "MJ_BizApps_Tasks_GitHub": "Git" "Hub" "Issue" "Tasks"
        (SELECT COALESCE(MAX("Sequence"), 0) + 1 FROM ${mjSchema}."EntityField" WHERE "EntityID" = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605'),
        'RollupWeight',
        'Rollup Weight',
        NULL,
        'decimal',
        5,
        8,
        2,
        FALSE,
        NULL,
        FALSE,
        FALSE,
        TRUE,
        FALSE,
        NULL,
        NULL,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        'Search',
        NOW(),
        NOW()
        );
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM ${mjSchema}."EntityField" WHERE "ID" = 'e4a34b92-d140-405d-9ab7-1003eded8be8' OR ("EntityID" = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605' AND "Name" = 'PlanningPeriod')
    ) THEN
        INSERT INTO ${mjSchema}."EntityField"
        (
        "ID",
        "EntityID",
        "Sequence",
        "Name",
        "DisplayName",
        "Description",
        "Type",
        "Length",
        "Precision",
        "Scale",
        "AllowsNull",
        "DefaultValue",
        "AutoIncrement",
        "AllowUpdateAPI",
        "IsVirtual",
        "IsComputed",
        "RelatedEntityID",
        "RelatedEntityFieldName",
        "IsNameField",
        "IncludeInUserSearchAPI",
        "IncludeRelatedEntityNameFieldInBaseView",
        "DefaultInView",
        "IsPrimaryKey",
        "IsUnique",
        "RelatedEntityDisplayType",
        "__mj_CreatedAt",
        "__mj_UpdatedAt"
        )
        VALUES
        (
        'e4a34b92-d140-405d-9ab7-1003eded8be8',
        'DC8E0F5B-E172-4FD5-B648-8B4544F8C605', -- "Entity": "MJ_BizApps_Tasks_GitHub": "Git" "Hub" "Issue" "Tasks"
        (SELECT COALESCE(MAX("Sequence"), 0) + 1 FROM ${mjSchema}."EntityField" WHERE "EntityID" = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605'),
        'PlanningPeriod',
        'Planning Period',
        NULL,
        'TEXT',
        100,
        0,
        0,
        TRUE,
        NULL,
        FALSE,
        FALSE,
        TRUE,
        FALSE,
        NULL,
        NULL,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        'Search',
        NOW(),
        NOW()
        );
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM ${mjSchema}."EntityField" WHERE "ID" = 'c652b089-04bd-4a3e-bbad-07d5d2474568' OR ("EntityID" = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605' AND "Name" = 'CheckInCadence')
    ) THEN
        INSERT INTO ${mjSchema}."EntityField"
        (
        "ID",
        "EntityID",
        "Sequence",
        "Name",
        "DisplayName",
        "Description",
        "Type",
        "Length",
        "Precision",
        "Scale",
        "AllowsNull",
        "DefaultValue",
        "AutoIncrement",
        "AllowUpdateAPI",
        "IsVirtual",
        "IsComputed",
        "RelatedEntityID",
        "RelatedEntityFieldName",
        "IsNameField",
        "IncludeInUserSearchAPI",
        "IncludeRelatedEntityNameFieldInBaseView",
        "DefaultInView",
        "IsPrimaryKey",
        "IsUnique",
        "RelatedEntityDisplayType",
        "__mj_CreatedAt",
        "__mj_UpdatedAt"
        )
        VALUES
        (
        'c652b089-04bd-4a3e-bbad-07d5d2474568',
        'DC8E0F5B-E172-4FD5-B648-8B4544F8C605', -- "Entity": "MJ_BizApps_Tasks_GitHub": "Git" "Hub" "Issue" "Tasks"
        (SELECT COALESCE(MAX("Sequence"), 0) + 1 FROM ${mjSchema}."EntityField" WHERE "EntityID" = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605'),
        'CheckInCadence',
        'Check In Cadence',
        NULL,
        'TEXT',
        40,
        0,
        0,
        TRUE,
        NULL,
        FALSE,
        FALSE,
        TRUE,
        FALSE,
        NULL,
        NULL,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        'Search',
        NOW(),
        NOW()
        );
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM ${mjSchema}."EntityField" WHERE "ID" = '6fe24c88-2e9c-49e9-afd2-4e0d428f7c50' OR ("EntityID" = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605' AND "Name" = 'LastCheckInAt')
    ) THEN
        INSERT INTO ${mjSchema}."EntityField"
        (
        "ID",
        "EntityID",
        "Sequence",
        "Name",
        "DisplayName",
        "Description",
        "Type",
        "Length",
        "Precision",
        "Scale",
        "AllowsNull",
        "DefaultValue",
        "AutoIncrement",
        "AllowUpdateAPI",
        "IsVirtual",
        "IsComputed",
        "RelatedEntityID",
        "RelatedEntityFieldName",
        "IsNameField",
        "IncludeInUserSearchAPI",
        "IncludeRelatedEntityNameFieldInBaseView",
        "DefaultInView",
        "IsPrimaryKey",
        "IsUnique",
        "RelatedEntityDisplayType",
        "__mj_CreatedAt",
        "__mj_UpdatedAt"
        )
        VALUES
        (
        '6fe24c88-2e9c-49e9-afd2-4e0d428f7c50',
        'DC8E0F5B-E172-4FD5-B648-8B4544F8C605', -- "Entity": "MJ_BizApps_Tasks_GitHub": "Git" "Hub" "Issue" "Tasks"
        (SELECT COALESCE(MAX("Sequence"), 0) + 1 FROM ${mjSchema}."EntityField" WHERE "EntityID" = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605'),
        'LastCheckInAt',
        'Last Check In At',
        NULL,
        'TIMESTAMPTZ',
        10,
        34,
        7,
        TRUE,
        NULL,
        FALSE,
        FALSE,
        TRUE,
        FALSE,
        NULL,
        NULL,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        'Search',
        NOW(),
        NOW()
        );
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM ${mjSchema}."EntityField" WHERE "ID" = 'c4aa4959-c523-450d-95c7-f7c4119f6211' OR ("EntityID" = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605' AND "Name" = 'NextCheckInDueAt')
    ) THEN
        INSERT INTO ${mjSchema}."EntityField"
        (
        "ID",
        "EntityID",
        "Sequence",
        "Name",
        "DisplayName",
        "Description",
        "Type",
        "Length",
        "Precision",
        "Scale",
        "AllowsNull",
        "DefaultValue",
        "AutoIncrement",
        "AllowUpdateAPI",
        "IsVirtual",
        "IsComputed",
        "RelatedEntityID",
        "RelatedEntityFieldName",
        "IsNameField",
        "IncludeInUserSearchAPI",
        "IncludeRelatedEntityNameFieldInBaseView",
        "DefaultInView",
        "IsPrimaryKey",
        "IsUnique",
        "RelatedEntityDisplayType",
        "__mj_CreatedAt",
        "__mj_UpdatedAt"
        )
        VALUES
        (
        'c4aa4959-c523-450d-95c7-f7c4119f6211',
        'DC8E0F5B-E172-4FD5-B648-8B4544F8C605', -- "Entity": "MJ_BizApps_Tasks_GitHub": "Git" "Hub" "Issue" "Tasks"
        (SELECT COALESCE(MAX("Sequence"), 0) + 1 FROM ${mjSchema}."EntityField" WHERE "EntityID" = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605'),
        'NextCheckInDueAt',
        'Next Check In Due At',
        NULL,
        'TIMESTAMPTZ',
        10,
        34,
        7,
        TRUE,
        NULL,
        FALSE,
        FALSE,
        TRUE,
        FALSE,
        NULL,
        NULL,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        'Search',
        NOW(),
        NOW()
        );
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM ${mjSchema}."EntityField" WHERE "ID" = '4ba1a1f6-223e-4e8d-99d0-16448913d993' OR ("EntityID" = 'A6B673F8-43BC-4875-AFF6-AC620592822E' AND "Name" = 'Name')
    ) THEN
        INSERT INTO ${mjSchema}."EntityField"
        (
        "ID",
        "EntityID",
        "Sequence",
        "Name",
        "DisplayName",
        "Description",
        "Type",
        "Length",
        "Precision",
        "Scale",
        "AllowsNull",
        "DefaultValue",
        "AutoIncrement",
        "AllowUpdateAPI",
        "IsVirtual",
        "IsComputed",
        "RelatedEntityID",
        "RelatedEntityFieldName",
        "IsNameField",
        "IncludeInUserSearchAPI",
        "IncludeRelatedEntityNameFieldInBaseView",
        "DefaultInView",
        "IsPrimaryKey",
        "IsUnique",
        "RelatedEntityDisplayType",
        "__mj_CreatedAt",
        "__mj_UpdatedAt"
        )
        VALUES
        (
        '4ba1a1f6-223e-4e8d-99d0-16448913d993',
        'A6B673F8-43BC-4875-AFF6-AC620592822E', -- "Entity": "MJ_BizApps_Tasks_GitHub": "Git" "Hub" "Pull" "Request" "Tasks"
        (SELECT COALESCE(MAX("Sequence"), 0) + 1 FROM ${mjSchema}."EntityField" WHERE "EntityID" = 'A6B673F8-43BC-4875-AFF6-AC620592822E'),
        'Name',
        'Name',
        NULL,
        'TEXT',
        510,
        0,
        0,
        FALSE,
        NULL,
        FALSE,
        FALSE,
        TRUE,
        FALSE,
        NULL,
        NULL,
        TRUE,
        TRUE,
        FALSE,
        TRUE,
        FALSE,
        FALSE,
        'Search',
        NOW(),
        NOW()
        );
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM ${mjSchema}."EntityField" WHERE "ID" = '504ce539-0cc4-47d3-ad5d-120907a421ed' OR ("EntityID" = 'A6B673F8-43BC-4875-AFF6-AC620592822E' AND "Name" = 'Description')
    ) THEN
        INSERT INTO ${mjSchema}."EntityField"
        (
        "ID",
        "EntityID",
        "Sequence",
        "Name",
        "DisplayName",
        "Description",
        "Type",
        "Length",
        "Precision",
        "Scale",
        "AllowsNull",
        "DefaultValue",
        "AutoIncrement",
        "AllowUpdateAPI",
        "IsVirtual",
        "IsComputed",
        "RelatedEntityID",
        "RelatedEntityFieldName",
        "IsNameField",
        "IncludeInUserSearchAPI",
        "IncludeRelatedEntityNameFieldInBaseView",
        "DefaultInView",
        "IsPrimaryKey",
        "IsUnique",
        "RelatedEntityDisplayType",
        "__mj_CreatedAt",
        "__mj_UpdatedAt"
        )
        VALUES
        (
        '504ce539-0cc4-47d3-ad5d-120907a421ed',
        'A6B673F8-43BC-4875-AFF6-AC620592822E', -- "Entity": "MJ_BizApps_Tasks_GitHub": "Git" "Hub" "Pull" "Request" "Tasks"
        (SELECT COALESCE(MAX("Sequence"), 0) + 1 FROM ${mjSchema}."EntityField" WHERE "EntityID" = 'A6B673F8-43BC-4875-AFF6-AC620592822E'),
        'Description',
        'Description',
        NULL,
        'TEXT',
        -1,
        0,
        0,
        TRUE,
        NULL,
        FALSE,
        FALSE,
        TRUE,
        FALSE,
        NULL,
        NULL,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        'Search',
        NOW(),
        NOW()
        );
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM ${mjSchema}."EntityField" WHERE "ID" = 'a26a18fa-8f34-423e-ac94-3f3b47ac87c9' OR ("EntityID" = 'A6B673F8-43BC-4875-AFF6-AC620592822E' AND "Name" = 'TypeID')
    ) THEN
        INSERT INTO ${mjSchema}."EntityField"
        (
        "ID",
        "EntityID",
        "Sequence",
        "Name",
        "DisplayName",
        "Description",
        "Type",
        "Length",
        "Precision",
        "Scale",
        "AllowsNull",
        "DefaultValue",
        "AutoIncrement",
        "AllowUpdateAPI",
        "IsVirtual",
        "IsComputed",
        "RelatedEntityID",
        "RelatedEntityFieldName",
        "IsNameField",
        "IncludeInUserSearchAPI",
        "IncludeRelatedEntityNameFieldInBaseView",
        "DefaultInView",
        "IsPrimaryKey",
        "IsUnique",
        "RelatedEntityDisplayType",
        "__mj_CreatedAt",
        "__mj_UpdatedAt"
        )
        VALUES
        (
        'a26a18fa-8f34-423e-ac94-3f3b47ac87c9',
        'A6B673F8-43BC-4875-AFF6-AC620592822E', -- "Entity": "MJ_BizApps_Tasks_GitHub": "Git" "Hub" "Pull" "Request" "Tasks"
        (SELECT COALESCE(MAX("Sequence"), 0) + 1 FROM ${mjSchema}."EntityField" WHERE "EntityID" = 'A6B673F8-43BC-4875-AFF6-AC620592822E'),
        'TypeID',
        'Type ID',
        NULL,
        'UUID',
        16,
        0,
        0,
        FALSE,
        NULL,
        FALSE,
        FALSE,
        TRUE,
        FALSE,
        NULL,
        NULL,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        'Search',
        NOW(),
        NOW()
        );
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM ${mjSchema}."EntityField" WHERE "ID" = '2f5e2d1c-f10a-42f0-9ad0-71956d6ed9c5' OR ("EntityID" = 'A6B673F8-43BC-4875-AFF6-AC620592822E' AND "Name" = 'CategoryID')
    ) THEN
        INSERT INTO ${mjSchema}."EntityField"
        (
        "ID",
        "EntityID",
        "Sequence",
        "Name",
        "DisplayName",
        "Description",
        "Type",
        "Length",
        "Precision",
        "Scale",
        "AllowsNull",
        "DefaultValue",
        "AutoIncrement",
        "AllowUpdateAPI",
        "IsVirtual",
        "IsComputed",
        "RelatedEntityID",
        "RelatedEntityFieldName",
        "IsNameField",
        "IncludeInUserSearchAPI",
        "IncludeRelatedEntityNameFieldInBaseView",
        "DefaultInView",
        "IsPrimaryKey",
        "IsUnique",
        "RelatedEntityDisplayType",
        "__mj_CreatedAt",
        "__mj_UpdatedAt"
        )
        VALUES
        (
        '2f5e2d1c-f10a-42f0-9ad0-71956d6ed9c5',
        'A6B673F8-43BC-4875-AFF6-AC620592822E', -- "Entity": "MJ_BizApps_Tasks_GitHub": "Git" "Hub" "Pull" "Request" "Tasks"
        (SELECT COALESCE(MAX("Sequence"), 0) + 1 FROM ${mjSchema}."EntityField" WHERE "EntityID" = 'A6B673F8-43BC-4875-AFF6-AC620592822E'),
        'CategoryID',
        'Category ID',
        NULL,
        'UUID',
        16,
        0,
        0,
        TRUE,
        NULL,
        FALSE,
        FALSE,
        TRUE,
        FALSE,
        NULL,
        NULL,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        'Search',
        NOW(),
        NOW()
        );
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM ${mjSchema}."EntityField" WHERE "ID" = '8a12d74a-f61c-4669-ab9a-f83fd4418679' OR ("EntityID" = 'A6B673F8-43BC-4875-AFF6-AC620592822E' AND "Name" = 'ParentID')
    ) THEN
        INSERT INTO ${mjSchema}."EntityField"
        (
        "ID",
        "EntityID",
        "Sequence",
        "Name",
        "DisplayName",
        "Description",
        "Type",
        "Length",
        "Precision",
        "Scale",
        "AllowsNull",
        "DefaultValue",
        "AutoIncrement",
        "AllowUpdateAPI",
        "IsVirtual",
        "IsComputed",
        "RelatedEntityID",
        "RelatedEntityFieldName",
        "IsNameField",
        "IncludeInUserSearchAPI",
        "IncludeRelatedEntityNameFieldInBaseView",
        "DefaultInView",
        "IsPrimaryKey",
        "IsUnique",
        "RelatedEntityDisplayType",
        "__mj_CreatedAt",
        "__mj_UpdatedAt"
        )
        VALUES
        (
        '8a12d74a-f61c-4669-ab9a-f83fd4418679',
        'A6B673F8-43BC-4875-AFF6-AC620592822E', -- "Entity": "MJ_BizApps_Tasks_GitHub": "Git" "Hub" "Pull" "Request" "Tasks"
        (SELECT COALESCE(MAX("Sequence"), 0) + 1 FROM ${mjSchema}."EntityField" WHERE "EntityID" = 'A6B673F8-43BC-4875-AFF6-AC620592822E'),
        'ParentID',
        'Parent ID',
        NULL,
        'UUID',
        16,
        0,
        0,
        TRUE,
        NULL,
        FALSE,
        FALSE,
        TRUE,
        FALSE,
        NULL,
        NULL,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        'Search',
        NOW(),
        NOW()
        );
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM ${mjSchema}."EntityField" WHERE "ID" = 'ccae381c-911d-407d-ba0b-05bdb95cabfb' OR ("EntityID" = 'A6B673F8-43BC-4875-AFF6-AC620592822E' AND "Name" = 'Status')
    ) THEN
        INSERT INTO ${mjSchema}."EntityField"
        (
        "ID",
        "EntityID",
        "Sequence",
        "Name",
        "DisplayName",
        "Description",
        "Type",
        "Length",
        "Precision",
        "Scale",
        "AllowsNull",
        "DefaultValue",
        "AutoIncrement",
        "AllowUpdateAPI",
        "IsVirtual",
        "IsComputed",
        "RelatedEntityID",
        "RelatedEntityFieldName",
        "IsNameField",
        "IncludeInUserSearchAPI",
        "IncludeRelatedEntityNameFieldInBaseView",
        "DefaultInView",
        "IsPrimaryKey",
        "IsUnique",
        "RelatedEntityDisplayType",
        "__mj_CreatedAt",
        "__mj_UpdatedAt"
        )
        VALUES
        (
        'ccae381c-911d-407d-ba0b-05bdb95cabfb',
        'A6B673F8-43BC-4875-AFF6-AC620592822E', -- "Entity": "MJ_BizApps_Tasks_GitHub": "Git" "Hub" "Pull" "Request" "Tasks"
        (SELECT COALESCE(MAX("Sequence"), 0) + 1 FROM ${mjSchema}."EntityField" WHERE "EntityID" = 'A6B673F8-43BC-4875-AFF6-AC620592822E'),
        'Status',
        'Status',
        NULL,
        'TEXT',
        100,
        0,
        0,
        FALSE,
        NULL,
        FALSE,
        FALSE,
        TRUE,
        FALSE,
        NULL,
        NULL,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        'Search',
        NOW(),
        NOW()
        );
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM ${mjSchema}."EntityField" WHERE "ID" = '10503f3a-eaad-4efa-aa23-ed42af9335f2' OR ("EntityID" = 'A6B673F8-43BC-4875-AFF6-AC620592822E' AND "Name" = 'Priority')
    ) THEN
        INSERT INTO ${mjSchema}."EntityField"
        (
        "ID",
        "EntityID",
        "Sequence",
        "Name",
        "DisplayName",
        "Description",
        "Type",
        "Length",
        "Precision",
        "Scale",
        "AllowsNull",
        "DefaultValue",
        "AutoIncrement",
        "AllowUpdateAPI",
        "IsVirtual",
        "IsComputed",
        "RelatedEntityID",
        "RelatedEntityFieldName",
        "IsNameField",
        "IncludeInUserSearchAPI",
        "IncludeRelatedEntityNameFieldInBaseView",
        "DefaultInView",
        "IsPrimaryKey",
        "IsUnique",
        "RelatedEntityDisplayType",
        "__mj_CreatedAt",
        "__mj_UpdatedAt"
        )
        VALUES
        (
        '10503f3a-eaad-4efa-aa23-ed42af9335f2',
        'A6B673F8-43BC-4875-AFF6-AC620592822E', -- "Entity": "MJ_BizApps_Tasks_GitHub": "Git" "Hub" "Pull" "Request" "Tasks"
        (SELECT COALESCE(MAX("Sequence"), 0) + 1 FROM ${mjSchema}."EntityField" WHERE "EntityID" = 'A6B673F8-43BC-4875-AFF6-AC620592822E'),
        'Priority',
        'Priority',
        NULL,
        'TEXT',
        40,
        0,
        0,
        FALSE,
        NULL,
        FALSE,
        FALSE,
        TRUE,
        FALSE,
        NULL,
        NULL,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        'Search',
        NOW(),
        NOW()
        );
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM ${mjSchema}."EntityField" WHERE "ID" = 'cfd64243-ad98-4583-9393-e2a86aa869fe' OR ("EntityID" = 'A6B673F8-43BC-4875-AFF6-AC620592822E' AND "Name" = 'StartedAt')
    ) THEN
        INSERT INTO ${mjSchema}."EntityField"
        (
        "ID",
        "EntityID",
        "Sequence",
        "Name",
        "DisplayName",
        "Description",
        "Type",
        "Length",
        "Precision",
        "Scale",
        "AllowsNull",
        "DefaultValue",
        "AutoIncrement",
        "AllowUpdateAPI",
        "IsVirtual",
        "IsComputed",
        "RelatedEntityID",
        "RelatedEntityFieldName",
        "IsNameField",
        "IncludeInUserSearchAPI",
        "IncludeRelatedEntityNameFieldInBaseView",
        "DefaultInView",
        "IsPrimaryKey",
        "IsUnique",
        "RelatedEntityDisplayType",
        "__mj_CreatedAt",
        "__mj_UpdatedAt"
        )
        VALUES
        (
        'cfd64243-ad98-4583-9393-e2a86aa869fe',
        'A6B673F8-43BC-4875-AFF6-AC620592822E', -- "Entity": "MJ_BizApps_Tasks_GitHub": "Git" "Hub" "Pull" "Request" "Tasks"
        (SELECT COALESCE(MAX("Sequence"), 0) + 1 FROM ${mjSchema}."EntityField" WHERE "EntityID" = 'A6B673F8-43BC-4875-AFF6-AC620592822E'),
        'StartedAt',
        'Started At',
        NULL,
        'TIMESTAMPTZ',
        10,
        34,
        7,
        TRUE,
        NULL,
        FALSE,
        FALSE,
        TRUE,
        FALSE,
        NULL,
        NULL,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        'Search',
        NOW(),
        NOW()
        );
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM ${mjSchema}."EntityField" WHERE "ID" = 'd6a809c0-b643-4045-bbbc-43420e9c4d9d' OR ("EntityID" = 'A6B673F8-43BC-4875-AFF6-AC620592822E' AND "Name" = 'DueAt')
    ) THEN
        INSERT INTO ${mjSchema}."EntityField"
        (
        "ID",
        "EntityID",
        "Sequence",
        "Name",
        "DisplayName",
        "Description",
        "Type",
        "Length",
        "Precision",
        "Scale",
        "AllowsNull",
        "DefaultValue",
        "AutoIncrement",
        "AllowUpdateAPI",
        "IsVirtual",
        "IsComputed",
        "RelatedEntityID",
        "RelatedEntityFieldName",
        "IsNameField",
        "IncludeInUserSearchAPI",
        "IncludeRelatedEntityNameFieldInBaseView",
        "DefaultInView",
        "IsPrimaryKey",
        "IsUnique",
        "RelatedEntityDisplayType",
        "__mj_CreatedAt",
        "__mj_UpdatedAt"
        )
        VALUES
        (
        'd6a809c0-b643-4045-bbbc-43420e9c4d9d',
        'A6B673F8-43BC-4875-AFF6-AC620592822E', -- "Entity": "MJ_BizApps_Tasks_GitHub": "Git" "Hub" "Pull" "Request" "Tasks"
        (SELECT COALESCE(MAX("Sequence"), 0) + 1 FROM ${mjSchema}."EntityField" WHERE "EntityID" = 'A6B673F8-43BC-4875-AFF6-AC620592822E'),
        'DueAt',
        'Due At',
        NULL,
        'TIMESTAMPTZ',
        10,
        34,
        7,
        TRUE,
        NULL,
        FALSE,
        FALSE,
        TRUE,
        FALSE,
        NULL,
        NULL,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        'Search',
        NOW(),
        NOW()
        );
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM ${mjSchema}."EntityField" WHERE "ID" = 'aeb061c9-c5b7-429c-bbfb-bfe7f0b9b8db' OR ("EntityID" = 'A6B673F8-43BC-4875-AFF6-AC620592822E' AND "Name" = 'CompletedAt')
    ) THEN
        INSERT INTO ${mjSchema}."EntityField"
        (
        "ID",
        "EntityID",
        "Sequence",
        "Name",
        "DisplayName",
        "Description",
        "Type",
        "Length",
        "Precision",
        "Scale",
        "AllowsNull",
        "DefaultValue",
        "AutoIncrement",
        "AllowUpdateAPI",
        "IsVirtual",
        "IsComputed",
        "RelatedEntityID",
        "RelatedEntityFieldName",
        "IsNameField",
        "IncludeInUserSearchAPI",
        "IncludeRelatedEntityNameFieldInBaseView",
        "DefaultInView",
        "IsPrimaryKey",
        "IsUnique",
        "RelatedEntityDisplayType",
        "__mj_CreatedAt",
        "__mj_UpdatedAt"
        )
        VALUES
        (
        'aeb061c9-c5b7-429c-bbfb-bfe7f0b9b8db',
        'A6B673F8-43BC-4875-AFF6-AC620592822E', -- "Entity": "MJ_BizApps_Tasks_GitHub": "Git" "Hub" "Pull" "Request" "Tasks"
        (SELECT COALESCE(MAX("Sequence"), 0) + 1 FROM ${mjSchema}."EntityField" WHERE "EntityID" = 'A6B673F8-43BC-4875-AFF6-AC620592822E'),
        'CompletedAt',
        'Completed At',
        NULL,
        'TIMESTAMPTZ',
        10,
        34,
        7,
        TRUE,
        NULL,
        FALSE,
        FALSE,
        TRUE,
        FALSE,
        NULL,
        NULL,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        'Search',
        NOW(),
        NOW()
        );
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM ${mjSchema}."EntityField" WHERE "ID" = '05869a56-0e75-4721-8fdf-4969df401c85' OR ("EntityID" = 'A6B673F8-43BC-4875-AFF6-AC620592822E' AND "Name" = 'HoursEstimated')
    ) THEN
        INSERT INTO ${mjSchema}."EntityField"
        (
        "ID",
        "EntityID",
        "Sequence",
        "Name",
        "DisplayName",
        "Description",
        "Type",
        "Length",
        "Precision",
        "Scale",
        "AllowsNull",
        "DefaultValue",
        "AutoIncrement",
        "AllowUpdateAPI",
        "IsVirtual",
        "IsComputed",
        "RelatedEntityID",
        "RelatedEntityFieldName",
        "IsNameField",
        "IncludeInUserSearchAPI",
        "IncludeRelatedEntityNameFieldInBaseView",
        "DefaultInView",
        "IsPrimaryKey",
        "IsUnique",
        "RelatedEntityDisplayType",
        "__mj_CreatedAt",
        "__mj_UpdatedAt"
        )
        VALUES
        (
        '05869a56-0e75-4721-8fdf-4969df401c85',
        'A6B673F8-43BC-4875-AFF6-AC620592822E', -- "Entity": "MJ_BizApps_Tasks_GitHub": "Git" "Hub" "Pull" "Request" "Tasks"
        (SELECT COALESCE(MAX("Sequence"), 0) + 1 FROM ${mjSchema}."EntityField" WHERE "EntityID" = 'A6B673F8-43BC-4875-AFF6-AC620592822E'),
        'HoursEstimated',
        'Hours Estimated',
        NULL,
        'decimal',
        5,
        8,
        2,
        TRUE,
        NULL,
        FALSE,
        FALSE,
        TRUE,
        FALSE,
        NULL,
        NULL,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        'Search',
        NOW(),
        NOW()
        );
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM ${mjSchema}."EntityField" WHERE "ID" = '5025c924-87bc-4045-b5b2-af280b8bf9d5' OR ("EntityID" = 'A6B673F8-43BC-4875-AFF6-AC620592822E' AND "Name" = 'HoursActual')
    ) THEN
        INSERT INTO ${mjSchema}."EntityField"
        (
        "ID",
        "EntityID",
        "Sequence",
        "Name",
        "DisplayName",
        "Description",
        "Type",
        "Length",
        "Precision",
        "Scale",
        "AllowsNull",
        "DefaultValue",
        "AutoIncrement",
        "AllowUpdateAPI",
        "IsVirtual",
        "IsComputed",
        "RelatedEntityID",
        "RelatedEntityFieldName",
        "IsNameField",
        "IncludeInUserSearchAPI",
        "IncludeRelatedEntityNameFieldInBaseView",
        "DefaultInView",
        "IsPrimaryKey",
        "IsUnique",
        "RelatedEntityDisplayType",
        "__mj_CreatedAt",
        "__mj_UpdatedAt"
        )
        VALUES
        (
        '5025c924-87bc-4045-b5b2-af280b8bf9d5',
        'A6B673F8-43BC-4875-AFF6-AC620592822E', -- "Entity": "MJ_BizApps_Tasks_GitHub": "Git" "Hub" "Pull" "Request" "Tasks"
        (SELECT COALESCE(MAX("Sequence"), 0) + 1 FROM ${mjSchema}."EntityField" WHERE "EntityID" = 'A6B673F8-43BC-4875-AFF6-AC620592822E'),
        'HoursActual',
        'Hours Actual',
        NULL,
        'decimal',
        5,
        8,
        2,
        TRUE,
        NULL,
        FALSE,
        FALSE,
        TRUE,
        FALSE,
        NULL,
        NULL,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        'Search',
        NOW(),
        NOW()
        );
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM ${mjSchema}."EntityField" WHERE "ID" = 'c0c67a45-f9f6-4962-a5dc-2176f8ef1f0a' OR ("EntityID" = 'A6B673F8-43BC-4875-AFF6-AC620592822E' AND "Name" = 'PercentComplete')
    ) THEN
        INSERT INTO ${mjSchema}."EntityField"
        (
        "ID",
        "EntityID",
        "Sequence",
        "Name",
        "DisplayName",
        "Description",
        "Type",
        "Length",
        "Precision",
        "Scale",
        "AllowsNull",
        "DefaultValue",
        "AutoIncrement",
        "AllowUpdateAPI",
        "IsVirtual",
        "IsComputed",
        "RelatedEntityID",
        "RelatedEntityFieldName",
        "IsNameField",
        "IncludeInUserSearchAPI",
        "IncludeRelatedEntityNameFieldInBaseView",
        "DefaultInView",
        "IsPrimaryKey",
        "IsUnique",
        "RelatedEntityDisplayType",
        "__mj_CreatedAt",
        "__mj_UpdatedAt"
        )
        VALUES
        (
        'c0c67a45-f9f6-4962-a5dc-2176f8ef1f0a',
        'A6B673F8-43BC-4875-AFF6-AC620592822E', -- "Entity": "MJ_BizApps_Tasks_GitHub": "Git" "Hub" "Pull" "Request" "Tasks"
        (SELECT COALESCE(MAX("Sequence"), 0) + 1 FROM ${mjSchema}."EntityField" WHERE "EntityID" = 'A6B673F8-43BC-4875-AFF6-AC620592822E'),
        'PercentComplete',
        'Percent Complete',
        NULL,
        'INTEGER',
        4,
        10,
        0,
        FALSE,
        NULL,
        FALSE,
        FALSE,
        TRUE,
        FALSE,
        NULL,
        NULL,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        'Search',
        NOW(),
        NOW()
        );
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM ${mjSchema}."EntityField" WHERE "ID" = 'c1d1eb47-d5af-42b7-926e-38440e14b0b0' OR ("EntityID" = 'A6B673F8-43BC-4875-AFF6-AC620592822E' AND "Name" = 'Sequence')
    ) THEN
        INSERT INTO ${mjSchema}."EntityField"
        (
        "ID",
        "EntityID",
        "Sequence",
        "Name",
        "DisplayName",
        "Description",
        "Type",
        "Length",
        "Precision",
        "Scale",
        "AllowsNull",
        "DefaultValue",
        "AutoIncrement",
        "AllowUpdateAPI",
        "IsVirtual",
        "IsComputed",
        "RelatedEntityID",
        "RelatedEntityFieldName",
        "IsNameField",
        "IncludeInUserSearchAPI",
        "IncludeRelatedEntityNameFieldInBaseView",
        "DefaultInView",
        "IsPrimaryKey",
        "IsUnique",
        "RelatedEntityDisplayType",
        "__mj_CreatedAt",
        "__mj_UpdatedAt"
        )
        VALUES
        (
        'c1d1eb47-d5af-42b7-926e-38440e14b0b0',
        'A6B673F8-43BC-4875-AFF6-AC620592822E', -- "Entity": "MJ_BizApps_Tasks_GitHub": "Git" "Hub" "Pull" "Request" "Tasks"
        (SELECT COALESCE(MAX("Sequence"), 0) + 1 FROM ${mjSchema}."EntityField" WHERE "EntityID" = 'A6B673F8-43BC-4875-AFF6-AC620592822E'),
        'Sequence',
        'Sequence',
        NULL,
        'INTEGER',
        4,
        10,
        0,
        FALSE,
        NULL,
        FALSE,
        FALSE,
        TRUE,
        FALSE,
        NULL,
        NULL,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        'Search',
        NOW(),
        NOW()
        );
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM ${mjSchema}."EntityField" WHERE "ID" = '3365149d-db81-4d9d-bb29-2d491c6e86fa' OR ("EntityID" = 'A6B673F8-43BC-4875-AFF6-AC620592822E' AND "Name" = 'BlockedReason')
    ) THEN
        INSERT INTO ${mjSchema}."EntityField"
        (
        "ID",
        "EntityID",
        "Sequence",
        "Name",
        "DisplayName",
        "Description",
        "Type",
        "Length",
        "Precision",
        "Scale",
        "AllowsNull",
        "DefaultValue",
        "AutoIncrement",
        "AllowUpdateAPI",
        "IsVirtual",
        "IsComputed",
        "RelatedEntityID",
        "RelatedEntityFieldName",
        "IsNameField",
        "IncludeInUserSearchAPI",
        "IncludeRelatedEntityNameFieldInBaseView",
        "DefaultInView",
        "IsPrimaryKey",
        "IsUnique",
        "RelatedEntityDisplayType",
        "__mj_CreatedAt",
        "__mj_UpdatedAt"
        )
        VALUES
        (
        '3365149d-db81-4d9d-bb29-2d491c6e86fa',
        'A6B673F8-43BC-4875-AFF6-AC620592822E', -- "Entity": "MJ_BizApps_Tasks_GitHub": "Git" "Hub" "Pull" "Request" "Tasks"
        (SELECT COALESCE(MAX("Sequence"), 0) + 1 FROM ${mjSchema}."EntityField" WHERE "EntityID" = 'A6B673F8-43BC-4875-AFF6-AC620592822E'),
        'BlockedReason',
        'Blocked Reason',
        NULL,
        'TEXT',
        -1,
        0,
        0,
        TRUE,
        NULL,
        FALSE,
        FALSE,
        TRUE,
        FALSE,
        NULL,
        NULL,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        'Search',
        NOW(),
        NOW()
        );
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM ${mjSchema}."EntityField" WHERE "ID" = '61b50ead-8c53-4c9f-96aa-76ecdedae434' OR ("EntityID" = 'A6B673F8-43BC-4875-AFF6-AC620592822E' AND "Name" = 'CompletionNotes')
    ) THEN
        INSERT INTO ${mjSchema}."EntityField"
        (
        "ID",
        "EntityID",
        "Sequence",
        "Name",
        "DisplayName",
        "Description",
        "Type",
        "Length",
        "Precision",
        "Scale",
        "AllowsNull",
        "DefaultValue",
        "AutoIncrement",
        "AllowUpdateAPI",
        "IsVirtual",
        "IsComputed",
        "RelatedEntityID",
        "RelatedEntityFieldName",
        "IsNameField",
        "IncludeInUserSearchAPI",
        "IncludeRelatedEntityNameFieldInBaseView",
        "DefaultInView",
        "IsPrimaryKey",
        "IsUnique",
        "RelatedEntityDisplayType",
        "__mj_CreatedAt",
        "__mj_UpdatedAt"
        )
        VALUES
        (
        '61b50ead-8c53-4c9f-96aa-76ecdedae434',
        'A6B673F8-43BC-4875-AFF6-AC620592822E', -- "Entity": "MJ_BizApps_Tasks_GitHub": "Git" "Hub" "Pull" "Request" "Tasks"
        (SELECT COALESCE(MAX("Sequence"), 0) + 1 FROM ${mjSchema}."EntityField" WHERE "EntityID" = 'A6B673F8-43BC-4875-AFF6-AC620592822E'),
        'CompletionNotes',
        'Completion Notes',
        NULL,
        'TEXT',
        -1,
        0,
        0,
        TRUE,
        NULL,
        FALSE,
        FALSE,
        TRUE,
        FALSE,
        NULL,
        NULL,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        'Search',
        NOW(),
        NOW()
        );
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM ${mjSchema}."EntityField" WHERE "ID" = 'fb407166-23f9-4bb3-98fb-599f619bb218' OR ("EntityID" = 'A6B673F8-43BC-4875-AFF6-AC620592822E' AND "Name" = 'CreatedByPersonID')
    ) THEN
        INSERT INTO ${mjSchema}."EntityField"
        (
        "ID",
        "EntityID",
        "Sequence",
        "Name",
        "DisplayName",
        "Description",
        "Type",
        "Length",
        "Precision",
        "Scale",
        "AllowsNull",
        "DefaultValue",
        "AutoIncrement",
        "AllowUpdateAPI",
        "IsVirtual",
        "IsComputed",
        "RelatedEntityID",
        "RelatedEntityFieldName",
        "IsNameField",
        "IncludeInUserSearchAPI",
        "IncludeRelatedEntityNameFieldInBaseView",
        "DefaultInView",
        "IsPrimaryKey",
        "IsUnique",
        "RelatedEntityDisplayType",
        "__mj_CreatedAt",
        "__mj_UpdatedAt"
        )
        VALUES
        (
        'fb407166-23f9-4bb3-98fb-599f619bb218',
        'A6B673F8-43BC-4875-AFF6-AC620592822E', -- "Entity": "MJ_BizApps_Tasks_GitHub": "Git" "Hub" "Pull" "Request" "Tasks"
        (SELECT COALESCE(MAX("Sequence"), 0) + 1 FROM ${mjSchema}."EntityField" WHERE "EntityID" = 'A6B673F8-43BC-4875-AFF6-AC620592822E'),
        'CreatedByPersonID',
        'Created By Person ID',
        NULL,
        'UUID',
        16,
        0,
        0,
        TRUE,
        NULL,
        FALSE,
        FALSE,
        TRUE,
        FALSE,
        NULL,
        NULL,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        'Search',
        NOW(),
        NOW()
        );
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM ${mjSchema}."EntityField" WHERE "ID" = '23302eb0-8c39-40d4-b309-faf86854aee2' OR ("EntityID" = 'A6B673F8-43BC-4875-AFF6-AC620592822E' AND "Name" = 'OverdueNotifiedAt')
    ) THEN
        INSERT INTO ${mjSchema}."EntityField"
        (
        "ID",
        "EntityID",
        "Sequence",
        "Name",
        "DisplayName",
        "Description",
        "Type",
        "Length",
        "Precision",
        "Scale",
        "AllowsNull",
        "DefaultValue",
        "AutoIncrement",
        "AllowUpdateAPI",
        "IsVirtual",
        "IsComputed",
        "RelatedEntityID",
        "RelatedEntityFieldName",
        "IsNameField",
        "IncludeInUserSearchAPI",
        "IncludeRelatedEntityNameFieldInBaseView",
        "DefaultInView",
        "IsPrimaryKey",
        "IsUnique",
        "RelatedEntityDisplayType",
        "__mj_CreatedAt",
        "__mj_UpdatedAt"
        )
        VALUES
        (
        '23302eb0-8c39-40d4-b309-faf86854aee2',
        'A6B673F8-43BC-4875-AFF6-AC620592822E', -- "Entity": "MJ_BizApps_Tasks_GitHub": "Git" "Hub" "Pull" "Request" "Tasks"
        (SELECT COALESCE(MAX("Sequence"), 0) + 1 FROM ${mjSchema}."EntityField" WHERE "EntityID" = 'A6B673F8-43BC-4875-AFF6-AC620592822E'),
        'OverdueNotifiedAt',
        'Overdue Notified At',
        NULL,
        'TIMESTAMPTZ',
        10,
        34,
        7,
        TRUE,
        NULL,
        FALSE,
        FALSE,
        TRUE,
        FALSE,
        NULL,
        NULL,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        'Search',
        NOW(),
        NOW()
        );
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM ${mjSchema}."EntityField" WHERE "ID" = '84a6f1cb-4453-4651-b20f-58f0a29789c8' OR ("EntityID" = 'A6B673F8-43BC-4875-AFF6-AC620592822E' AND "Name" = 'TaskTypeStatusID')
    ) THEN
        INSERT INTO ${mjSchema}."EntityField"
        (
        "ID",
        "EntityID",
        "Sequence",
        "Name",
        "DisplayName",
        "Description",
        "Type",
        "Length",
        "Precision",
        "Scale",
        "AllowsNull",
        "DefaultValue",
        "AutoIncrement",
        "AllowUpdateAPI",
        "IsVirtual",
        "IsComputed",
        "RelatedEntityID",
        "RelatedEntityFieldName",
        "IsNameField",
        "IncludeInUserSearchAPI",
        "IncludeRelatedEntityNameFieldInBaseView",
        "DefaultInView",
        "IsPrimaryKey",
        "IsUnique",
        "RelatedEntityDisplayType",
        "__mj_CreatedAt",
        "__mj_UpdatedAt"
        )
        VALUES
        (
        '84a6f1cb-4453-4651-b20f-58f0a29789c8',
        'A6B673F8-43BC-4875-AFF6-AC620592822E', -- "Entity": "MJ_BizApps_Tasks_GitHub": "Git" "Hub" "Pull" "Request" "Tasks"
        (SELECT COALESCE(MAX("Sequence"), 0) + 1 FROM ${mjSchema}."EntityField" WHERE "EntityID" = 'A6B673F8-43BC-4875-AFF6-AC620592822E'),
        'TaskTypeStatusID',
        'Task Type Status ID',
        NULL,
        'UUID',
        16,
        0,
        0,
        TRUE,
        NULL,
        FALSE,
        FALSE,
        TRUE,
        FALSE,
        NULL,
        NULL,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        'Search',
        NOW(),
        NOW()
        );
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM ${mjSchema}."EntityField" WHERE "ID" = '9aaf8300-10b1-4c0c-8a05-ce90f22c22e4' OR ("EntityID" = 'A6B673F8-43BC-4875-AFF6-AC620592822E' AND "Name" = 'PredictedSLABreachProbability')
    ) THEN
        INSERT INTO ${mjSchema}."EntityField"
        (
        "ID",
        "EntityID",
        "Sequence",
        "Name",
        "DisplayName",
        "Description",
        "Type",
        "Length",
        "Precision",
        "Scale",
        "AllowsNull",
        "DefaultValue",
        "AutoIncrement",
        "AllowUpdateAPI",
        "IsVirtual",
        "IsComputed",
        "RelatedEntityID",
        "RelatedEntityFieldName",
        "IsNameField",
        "IncludeInUserSearchAPI",
        "IncludeRelatedEntityNameFieldInBaseView",
        "DefaultInView",
        "IsPrimaryKey",
        "IsUnique",
        "RelatedEntityDisplayType",
        "__mj_CreatedAt",
        "__mj_UpdatedAt"
        )
        VALUES
        (
        '9aaf8300-10b1-4c0c-8a05-ce90f22c22e4',
        'A6B673F8-43BC-4875-AFF6-AC620592822E', -- "Entity": "MJ_BizApps_Tasks_GitHub": "Git" "Hub" "Pull" "Request" "Tasks"
        (SELECT COALESCE(MAX("Sequence"), 0) + 1 FROM ${mjSchema}."EntityField" WHERE "EntityID" = 'A6B673F8-43BC-4875-AFF6-AC620592822E'),
        'PredictedSLABreachProbability',
        'Predicted SLA Breach Probability',
        NULL,
        'decimal',
        5,
        5,
        4,
        TRUE,
        NULL,
        FALSE,
        FALSE,
        TRUE,
        FALSE,
        NULL,
        NULL,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        'Search',
        NOW(),
        NOW()
        );
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM ${mjSchema}."EntityField" WHERE "ID" = '95d95cdc-aece-417e-a7eb-bb87a0197a3e' OR ("EntityID" = 'A6B673F8-43BC-4875-AFF6-AC620592822E' AND "Name" = 'PredictedSLARiskBand')
    ) THEN
        INSERT INTO ${mjSchema}."EntityField"
        (
        "ID",
        "EntityID",
        "Sequence",
        "Name",
        "DisplayName",
        "Description",
        "Type",
        "Length",
        "Precision",
        "Scale",
        "AllowsNull",
        "DefaultValue",
        "AutoIncrement",
        "AllowUpdateAPI",
        "IsVirtual",
        "IsComputed",
        "RelatedEntityID",
        "RelatedEntityFieldName",
        "IsNameField",
        "IncludeInUserSearchAPI",
        "IncludeRelatedEntityNameFieldInBaseView",
        "DefaultInView",
        "IsPrimaryKey",
        "IsUnique",
        "RelatedEntityDisplayType",
        "__mj_CreatedAt",
        "__mj_UpdatedAt"
        )
        VALUES
        (
        '95d95cdc-aece-417e-a7eb-bb87a0197a3e',
        'A6B673F8-43BC-4875-AFF6-AC620592822E', -- "Entity": "MJ_BizApps_Tasks_GitHub": "Git" "Hub" "Pull" "Request" "Tasks"
        (SELECT COALESCE(MAX("Sequence"), 0) + 1 FROM ${mjSchema}."EntityField" WHERE "EntityID" = 'A6B673F8-43BC-4875-AFF6-AC620592822E'),
        'PredictedSLARiskBand',
        'Predicted SLA Risk Band',
        NULL,
        'TEXT',
        40,
        0,
        0,
        TRUE,
        NULL,
        FALSE,
        FALSE,
        TRUE,
        FALSE,
        NULL,
        NULL,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        'Search',
        NOW(),
        NOW()
        );
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM ${mjSchema}."EntityField" WHERE "ID" = '6ebf3400-38a4-4ce7-a1e8-76dfbb328821' OR ("EntityID" = 'A6B673F8-43BC-4875-AFF6-AC620592822E' AND "Name" = 'PredictedSLAScoredAt')
    ) THEN
        INSERT INTO ${mjSchema}."EntityField"
        (
        "ID",
        "EntityID",
        "Sequence",
        "Name",
        "DisplayName",
        "Description",
        "Type",
        "Length",
        "Precision",
        "Scale",
        "AllowsNull",
        "DefaultValue",
        "AutoIncrement",
        "AllowUpdateAPI",
        "IsVirtual",
        "IsComputed",
        "RelatedEntityID",
        "RelatedEntityFieldName",
        "IsNameField",
        "IncludeInUserSearchAPI",
        "IncludeRelatedEntityNameFieldInBaseView",
        "DefaultInView",
        "IsPrimaryKey",
        "IsUnique",
        "RelatedEntityDisplayType",
        "__mj_CreatedAt",
        "__mj_UpdatedAt"
        )
        VALUES
        (
        '6ebf3400-38a4-4ce7-a1e8-76dfbb328821',
        'A6B673F8-43BC-4875-AFF6-AC620592822E', -- "Entity": "MJ_BizApps_Tasks_GitHub": "Git" "Hub" "Pull" "Request" "Tasks"
        (SELECT COALESCE(MAX("Sequence"), 0) + 1 FROM ${mjSchema}."EntityField" WHERE "EntityID" = 'A6B673F8-43BC-4875-AFF6-AC620592822E'),
        'PredictedSLAScoredAt',
        'Predicted SLA Scored At',
        NULL,
        'TIMESTAMPTZ',
        10,
        34,
        7,
        TRUE,
        NULL,
        FALSE,
        FALSE,
        TRUE,
        FALSE,
        NULL,
        NULL,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        'Search',
        NOW(),
        NOW()
        );
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM ${mjSchema}."EntityField" WHERE "ID" = 'ff834cc2-1fd6-438e-bd22-82f6bea0eaf2' OR ("EntityID" = 'A6B673F8-43BC-4875-AFF6-AC620592822E' AND "Name" = 'HealthStatus')
    ) THEN
        INSERT INTO ${mjSchema}."EntityField"
        (
        "ID",
        "EntityID",
        "Sequence",
        "Name",
        "DisplayName",
        "Description",
        "Type",
        "Length",
        "Precision",
        "Scale",
        "AllowsNull",
        "DefaultValue",
        "AutoIncrement",
        "AllowUpdateAPI",
        "IsVirtual",
        "IsComputed",
        "RelatedEntityID",
        "RelatedEntityFieldName",
        "IsNameField",
        "IncludeInUserSearchAPI",
        "IncludeRelatedEntityNameFieldInBaseView",
        "DefaultInView",
        "IsPrimaryKey",
        "IsUnique",
        "RelatedEntityDisplayType",
        "__mj_CreatedAt",
        "__mj_UpdatedAt"
        )
        VALUES
        (
        'ff834cc2-1fd6-438e-bd22-82f6bea0eaf2',
        'A6B673F8-43BC-4875-AFF6-AC620592822E', -- "Entity": "MJ_BizApps_Tasks_GitHub": "Git" "Hub" "Pull" "Request" "Tasks"
        (SELECT COALESCE(MAX("Sequence"), 0) + 1 FROM ${mjSchema}."EntityField" WHERE "EntityID" = 'A6B673F8-43BC-4875-AFF6-AC620592822E'),
        'HealthStatus',
        'Health Status',
        NULL,
        'TEXT',
        40,
        0,
        0,
        TRUE,
        NULL,
        FALSE,
        FALSE,
        TRUE,
        FALSE,
        NULL,
        NULL,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        'Search',
        NOW(),
        NOW()
        );
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM ${mjSchema}."EntityField" WHERE "ID" = '6b700581-9114-4d4d-87fd-7803e6990fe6' OR ("EntityID" = 'A6B673F8-43BC-4875-AFF6-AC620592822E' AND "Name" = 'ConfidenceScore')
    ) THEN
        INSERT INTO ${mjSchema}."EntityField"
        (
        "ID",
        "EntityID",
        "Sequence",
        "Name",
        "DisplayName",
        "Description",
        "Type",
        "Length",
        "Precision",
        "Scale",
        "AllowsNull",
        "DefaultValue",
        "AutoIncrement",
        "AllowUpdateAPI",
        "IsVirtual",
        "IsComputed",
        "RelatedEntityID",
        "RelatedEntityFieldName",
        "IsNameField",
        "IncludeInUserSearchAPI",
        "IncludeRelatedEntityNameFieldInBaseView",
        "DefaultInView",
        "IsPrimaryKey",
        "IsUnique",
        "RelatedEntityDisplayType",
        "__mj_CreatedAt",
        "__mj_UpdatedAt"
        )
        VALUES
        (
        '6b700581-9114-4d4d-87fd-7803e6990fe6',
        'A6B673F8-43BC-4875-AFF6-AC620592822E', -- "Entity": "MJ_BizApps_Tasks_GitHub": "Git" "Hub" "Pull" "Request" "Tasks"
        (SELECT COALESCE(MAX("Sequence"), 0) + 1 FROM ${mjSchema}."EntityField" WHERE "EntityID" = 'A6B673F8-43BC-4875-AFF6-AC620592822E'),
        'ConfidenceScore',
        'Confidence Score',
        NULL,
        'INTEGER',
        4,
        10,
        0,
        TRUE,
        NULL,
        FALSE,
        FALSE,
        TRUE,
        FALSE,
        NULL,
        NULL,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        'Search',
        NOW(),
        NOW()
        );
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM ${mjSchema}."EntityField" WHERE "ID" = '2fab02de-f972-461e-9b21-4387520af9b2' OR ("EntityID" = 'A6B673F8-43BC-4875-AFF6-AC620592822E' AND "Name" = 'BaselineValue')
    ) THEN
        INSERT INTO ${mjSchema}."EntityField"
        (
        "ID",
        "EntityID",
        "Sequence",
        "Name",
        "DisplayName",
        "Description",
        "Type",
        "Length",
        "Precision",
        "Scale",
        "AllowsNull",
        "DefaultValue",
        "AutoIncrement",
        "AllowUpdateAPI",
        "IsVirtual",
        "IsComputed",
        "RelatedEntityID",
        "RelatedEntityFieldName",
        "IsNameField",
        "IncludeInUserSearchAPI",
        "IncludeRelatedEntityNameFieldInBaseView",
        "DefaultInView",
        "IsPrimaryKey",
        "IsUnique",
        "RelatedEntityDisplayType",
        "__mj_CreatedAt",
        "__mj_UpdatedAt"
        )
        VALUES
        (
        '2fab02de-f972-461e-9b21-4387520af9b2',
        'A6B673F8-43BC-4875-AFF6-AC620592822E', -- "Entity": "MJ_BizApps_Tasks_GitHub": "Git" "Hub" "Pull" "Request" "Tasks"
        (SELECT COALESCE(MAX("Sequence"), 0) + 1 FROM ${mjSchema}."EntityField" WHERE "EntityID" = 'A6B673F8-43BC-4875-AFF6-AC620592822E'),
        'BaselineValue',
        'Baseline Value',
        NULL,
        'decimal',
        9,
        18,
        4,
        TRUE,
        NULL,
        FALSE,
        FALSE,
        TRUE,
        FALSE,
        NULL,
        NULL,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        'Search',
        NOW(),
        NOW()
        );
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM ${mjSchema}."EntityField" WHERE "ID" = 'd9bda046-a66f-4965-b964-56a2833e4000' OR ("EntityID" = 'A6B673F8-43BC-4875-AFF6-AC620592822E' AND "Name" = 'TargetValue')
    ) THEN
        INSERT INTO ${mjSchema}."EntityField"
        (
        "ID",
        "EntityID",
        "Sequence",
        "Name",
        "DisplayName",
        "Description",
        "Type",
        "Length",
        "Precision",
        "Scale",
        "AllowsNull",
        "DefaultValue",
        "AutoIncrement",
        "AllowUpdateAPI",
        "IsVirtual",
        "IsComputed",
        "RelatedEntityID",
        "RelatedEntityFieldName",
        "IsNameField",
        "IncludeInUserSearchAPI",
        "IncludeRelatedEntityNameFieldInBaseView",
        "DefaultInView",
        "IsPrimaryKey",
        "IsUnique",
        "RelatedEntityDisplayType",
        "__mj_CreatedAt",
        "__mj_UpdatedAt"
        )
        VALUES
        (
        'd9bda046-a66f-4965-b964-56a2833e4000',
        'A6B673F8-43BC-4875-AFF6-AC620592822E', -- "Entity": "MJ_BizApps_Tasks_GitHub": "Git" "Hub" "Pull" "Request" "Tasks"
        (SELECT COALESCE(MAX("Sequence"), 0) + 1 FROM ${mjSchema}."EntityField" WHERE "EntityID" = 'A6B673F8-43BC-4875-AFF6-AC620592822E'),
        'TargetValue',
        'Target Value',
        NULL,
        'decimal',
        9,
        18,
        4,
        TRUE,
        NULL,
        FALSE,
        FALSE,
        TRUE,
        FALSE,
        NULL,
        NULL,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        'Search',
        NOW(),
        NOW()
        );
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM ${mjSchema}."EntityField" WHERE "ID" = 'd568f0df-cf9a-41d6-8ece-5ed935afff02' OR ("EntityID" = 'A6B673F8-43BC-4875-AFF6-AC620592822E' AND "Name" = 'CurrentValue')
    ) THEN
        INSERT INTO ${mjSchema}."EntityField"
        (
        "ID",
        "EntityID",
        "Sequence",
        "Name",
        "DisplayName",
        "Description",
        "Type",
        "Length",
        "Precision",
        "Scale",
        "AllowsNull",
        "DefaultValue",
        "AutoIncrement",
        "AllowUpdateAPI",
        "IsVirtual",
        "IsComputed",
        "RelatedEntityID",
        "RelatedEntityFieldName",
        "IsNameField",
        "IncludeInUserSearchAPI",
        "IncludeRelatedEntityNameFieldInBaseView",
        "DefaultInView",
        "IsPrimaryKey",
        "IsUnique",
        "RelatedEntityDisplayType",
        "__mj_CreatedAt",
        "__mj_UpdatedAt"
        )
        VALUES
        (
        'd568f0df-cf9a-41d6-8ece-5ed935afff02',
        'A6B673F8-43BC-4875-AFF6-AC620592822E', -- "Entity": "MJ_BizApps_Tasks_GitHub": "Git" "Hub" "Pull" "Request" "Tasks"
        (SELECT COALESCE(MAX("Sequence"), 0) + 1 FROM ${mjSchema}."EntityField" WHERE "EntityID" = 'A6B673F8-43BC-4875-AFF6-AC620592822E'),
        'CurrentValue',
        'Current Value',
        NULL,
        'decimal',
        9,
        18,
        4,
        TRUE,
        NULL,
        FALSE,
        FALSE,
        TRUE,
        FALSE,
        NULL,
        NULL,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        'Search',
        NOW(),
        NOW()
        );
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM ${mjSchema}."EntityField" WHERE "ID" = 'a15515ce-2505-4a75-909b-996d159bf8b3' OR ("EntityID" = 'A6B673F8-43BC-4875-AFF6-AC620592822E' AND "Name" = 'UnitOfMeasure')
    ) THEN
        INSERT INTO ${mjSchema}."EntityField"
        (
        "ID",
        "EntityID",
        "Sequence",
        "Name",
        "DisplayName",
        "Description",
        "Type",
        "Length",
        "Precision",
        "Scale",
        "AllowsNull",
        "DefaultValue",
        "AutoIncrement",
        "AllowUpdateAPI",
        "IsVirtual",
        "IsComputed",
        "RelatedEntityID",
        "RelatedEntityFieldName",
        "IsNameField",
        "IncludeInUserSearchAPI",
        "IncludeRelatedEntityNameFieldInBaseView",
        "DefaultInView",
        "IsPrimaryKey",
        "IsUnique",
        "RelatedEntityDisplayType",
        "__mj_CreatedAt",
        "__mj_UpdatedAt"
        )
        VALUES
        (
        'a15515ce-2505-4a75-909b-996d159bf8b3',
        'A6B673F8-43BC-4875-AFF6-AC620592822E', -- "Entity": "MJ_BizApps_Tasks_GitHub": "Git" "Hub" "Pull" "Request" "Tasks"
        (SELECT COALESCE(MAX("Sequence"), 0) + 1 FROM ${mjSchema}."EntityField" WHERE "EntityID" = 'A6B673F8-43BC-4875-AFF6-AC620592822E'),
        'UnitOfMeasure',
        'Unit Of Measure',
        NULL,
        'TEXT',
        100,
        0,
        0,
        TRUE,
        NULL,
        FALSE,
        FALSE,
        TRUE,
        FALSE,
        NULL,
        NULL,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        'Search',
        NOW(),
        NOW()
        );
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM ${mjSchema}."EntityField" WHERE "ID" = '72a1ace2-6bd6-4861-9de0-f617873736d7' OR ("EntityID" = 'A6B673F8-43BC-4875-AFF6-AC620592822E' AND "Name" = 'MetricDirection')
    ) THEN
        INSERT INTO ${mjSchema}."EntityField"
        (
        "ID",
        "EntityID",
        "Sequence",
        "Name",
        "DisplayName",
        "Description",
        "Type",
        "Length",
        "Precision",
        "Scale",
        "AllowsNull",
        "DefaultValue",
        "AutoIncrement",
        "AllowUpdateAPI",
        "IsVirtual",
        "IsComputed",
        "RelatedEntityID",
        "RelatedEntityFieldName",
        "IsNameField",
        "IncludeInUserSearchAPI",
        "IncludeRelatedEntityNameFieldInBaseView",
        "DefaultInView",
        "IsPrimaryKey",
        "IsUnique",
        "RelatedEntityDisplayType",
        "__mj_CreatedAt",
        "__mj_UpdatedAt"
        )
        VALUES
        (
        '72a1ace2-6bd6-4861-9de0-f617873736d7',
        'A6B673F8-43BC-4875-AFF6-AC620592822E', -- "Entity": "MJ_BizApps_Tasks_GitHub": "Git" "Hub" "Pull" "Request" "Tasks"
        (SELECT COALESCE(MAX("Sequence"), 0) + 1 FROM ${mjSchema}."EntityField" WHERE "EntityID" = 'A6B673F8-43BC-4875-AFF6-AC620592822E'),
        'MetricDirection',
        'Metric Direction',
        NULL,
        'TEXT',
        40,
        0,
        0,
        TRUE,
        NULL,
        FALSE,
        FALSE,
        TRUE,
        FALSE,
        NULL,
        NULL,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        'Search',
        NOW(),
        NOW()
        );
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM ${mjSchema}."EntityField" WHERE "ID" = '32734bdb-ada6-4d79-b571-bb7a39e50808' OR ("EntityID" = 'A6B673F8-43BC-4875-AFF6-AC620592822E' AND "Name" = 'RollupWeight')
    ) THEN
        INSERT INTO ${mjSchema}."EntityField"
        (
        "ID",
        "EntityID",
        "Sequence",
        "Name",
        "DisplayName",
        "Description",
        "Type",
        "Length",
        "Precision",
        "Scale",
        "AllowsNull",
        "DefaultValue",
        "AutoIncrement",
        "AllowUpdateAPI",
        "IsVirtual",
        "IsComputed",
        "RelatedEntityID",
        "RelatedEntityFieldName",
        "IsNameField",
        "IncludeInUserSearchAPI",
        "IncludeRelatedEntityNameFieldInBaseView",
        "DefaultInView",
        "IsPrimaryKey",
        "IsUnique",
        "RelatedEntityDisplayType",
        "__mj_CreatedAt",
        "__mj_UpdatedAt"
        )
        VALUES
        (
        '32734bdb-ada6-4d79-b571-bb7a39e50808',
        'A6B673F8-43BC-4875-AFF6-AC620592822E', -- "Entity": "MJ_BizApps_Tasks_GitHub": "Git" "Hub" "Pull" "Request" "Tasks"
        (SELECT COALESCE(MAX("Sequence"), 0) + 1 FROM ${mjSchema}."EntityField" WHERE "EntityID" = 'A6B673F8-43BC-4875-AFF6-AC620592822E'),
        'RollupWeight',
        'Rollup Weight',
        NULL,
        'decimal',
        5,
        8,
        2,
        FALSE,
        NULL,
        FALSE,
        FALSE,
        TRUE,
        FALSE,
        NULL,
        NULL,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        'Search',
        NOW(),
        NOW()
        );
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM ${mjSchema}."EntityField" WHERE "ID" = '74340cb6-2cf9-4078-b056-bcec5ab63a3a' OR ("EntityID" = 'A6B673F8-43BC-4875-AFF6-AC620592822E' AND "Name" = 'PlanningPeriod')
    ) THEN
        INSERT INTO ${mjSchema}."EntityField"
        (
        "ID",
        "EntityID",
        "Sequence",
        "Name",
        "DisplayName",
        "Description",
        "Type",
        "Length",
        "Precision",
        "Scale",
        "AllowsNull",
        "DefaultValue",
        "AutoIncrement",
        "AllowUpdateAPI",
        "IsVirtual",
        "IsComputed",
        "RelatedEntityID",
        "RelatedEntityFieldName",
        "IsNameField",
        "IncludeInUserSearchAPI",
        "IncludeRelatedEntityNameFieldInBaseView",
        "DefaultInView",
        "IsPrimaryKey",
        "IsUnique",
        "RelatedEntityDisplayType",
        "__mj_CreatedAt",
        "__mj_UpdatedAt"
        )
        VALUES
        (
        '74340cb6-2cf9-4078-b056-bcec5ab63a3a',
        'A6B673F8-43BC-4875-AFF6-AC620592822E', -- "Entity": "MJ_BizApps_Tasks_GitHub": "Git" "Hub" "Pull" "Request" "Tasks"
        (SELECT COALESCE(MAX("Sequence"), 0) + 1 FROM ${mjSchema}."EntityField" WHERE "EntityID" = 'A6B673F8-43BC-4875-AFF6-AC620592822E'),
        'PlanningPeriod',
        'Planning Period',
        NULL,
        'TEXT',
        100,
        0,
        0,
        TRUE,
        NULL,
        FALSE,
        FALSE,
        TRUE,
        FALSE,
        NULL,
        NULL,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        'Search',
        NOW(),
        NOW()
        );
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM ${mjSchema}."EntityField" WHERE "ID" = '74337fd7-6b08-4ee4-afe9-5c97ee684b19' OR ("EntityID" = 'A6B673F8-43BC-4875-AFF6-AC620592822E' AND "Name" = 'CheckInCadence')
    ) THEN
        INSERT INTO ${mjSchema}."EntityField"
        (
        "ID",
        "EntityID",
        "Sequence",
        "Name",
        "DisplayName",
        "Description",
        "Type",
        "Length",
        "Precision",
        "Scale",
        "AllowsNull",
        "DefaultValue",
        "AutoIncrement",
        "AllowUpdateAPI",
        "IsVirtual",
        "IsComputed",
        "RelatedEntityID",
        "RelatedEntityFieldName",
        "IsNameField",
        "IncludeInUserSearchAPI",
        "IncludeRelatedEntityNameFieldInBaseView",
        "DefaultInView",
        "IsPrimaryKey",
        "IsUnique",
        "RelatedEntityDisplayType",
        "__mj_CreatedAt",
        "__mj_UpdatedAt"
        )
        VALUES
        (
        '74337fd7-6b08-4ee4-afe9-5c97ee684b19',
        'A6B673F8-43BC-4875-AFF6-AC620592822E', -- "Entity": "MJ_BizApps_Tasks_GitHub": "Git" "Hub" "Pull" "Request" "Tasks"
        (SELECT COALESCE(MAX("Sequence"), 0) + 1 FROM ${mjSchema}."EntityField" WHERE "EntityID" = 'A6B673F8-43BC-4875-AFF6-AC620592822E'),
        'CheckInCadence',
        'Check In Cadence',
        NULL,
        'TEXT',
        40,
        0,
        0,
        TRUE,
        NULL,
        FALSE,
        FALSE,
        TRUE,
        FALSE,
        NULL,
        NULL,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        'Search',
        NOW(),
        NOW()
        );
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM ${mjSchema}."EntityField" WHERE "ID" = '8caf3bc8-b357-4b60-ad0e-76b818806ccc' OR ("EntityID" = 'A6B673F8-43BC-4875-AFF6-AC620592822E' AND "Name" = 'LastCheckInAt')
    ) THEN
        INSERT INTO ${mjSchema}."EntityField"
        (
        "ID",
        "EntityID",
        "Sequence",
        "Name",
        "DisplayName",
        "Description",
        "Type",
        "Length",
        "Precision",
        "Scale",
        "AllowsNull",
        "DefaultValue",
        "AutoIncrement",
        "AllowUpdateAPI",
        "IsVirtual",
        "IsComputed",
        "RelatedEntityID",
        "RelatedEntityFieldName",
        "IsNameField",
        "IncludeInUserSearchAPI",
        "IncludeRelatedEntityNameFieldInBaseView",
        "DefaultInView",
        "IsPrimaryKey",
        "IsUnique",
        "RelatedEntityDisplayType",
        "__mj_CreatedAt",
        "__mj_UpdatedAt"
        )
        VALUES
        (
        '8caf3bc8-b357-4b60-ad0e-76b818806ccc',
        'A6B673F8-43BC-4875-AFF6-AC620592822E', -- "Entity": "MJ_BizApps_Tasks_GitHub": "Git" "Hub" "Pull" "Request" "Tasks"
        (SELECT COALESCE(MAX("Sequence"), 0) + 1 FROM ${mjSchema}."EntityField" WHERE "EntityID" = 'A6B673F8-43BC-4875-AFF6-AC620592822E'),
        'LastCheckInAt',
        'Last Check In At',
        NULL,
        'TIMESTAMPTZ',
        10,
        34,
        7,
        TRUE,
        NULL,
        FALSE,
        FALSE,
        TRUE,
        FALSE,
        NULL,
        NULL,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        'Search',
        NOW(),
        NOW()
        );
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM ${mjSchema}."EntityField" WHERE "ID" = '8db46a9c-8567-43d3-85e1-af3174f6628f' OR ("EntityID" = 'A6B673F8-43BC-4875-AFF6-AC620592822E' AND "Name" = 'NextCheckInDueAt')
    ) THEN
        INSERT INTO ${mjSchema}."EntityField"
        (
        "ID",
        "EntityID",
        "Sequence",
        "Name",
        "DisplayName",
        "Description",
        "Type",
        "Length",
        "Precision",
        "Scale",
        "AllowsNull",
        "DefaultValue",
        "AutoIncrement",
        "AllowUpdateAPI",
        "IsVirtual",
        "IsComputed",
        "RelatedEntityID",
        "RelatedEntityFieldName",
        "IsNameField",
        "IncludeInUserSearchAPI",
        "IncludeRelatedEntityNameFieldInBaseView",
        "DefaultInView",
        "IsPrimaryKey",
        "IsUnique",
        "RelatedEntityDisplayType",
        "__mj_CreatedAt",
        "__mj_UpdatedAt"
        )
        VALUES
        (
        '8db46a9c-8567-43d3-85e1-af3174f6628f',
        'A6B673F8-43BC-4875-AFF6-AC620592822E', -- "Entity": "MJ_BizApps_Tasks_GitHub": "Git" "Hub" "Pull" "Request" "Tasks"
        (SELECT COALESCE(MAX("Sequence"), 0) + 1 FROM ${mjSchema}."EntityField" WHERE "EntityID" = 'A6B673F8-43BC-4875-AFF6-AC620592822E'),
        'NextCheckInDueAt',
        'Next Check In Due At',
        NULL,
        'TIMESTAMPTZ',
        10,
        34,
        7,
        TRUE,
        NULL,
        FALSE,
        FALSE,
        TRUE,
        FALSE,
        NULL,
        NULL,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        'Search',
        NOW(),
        NOW()
        );
    END IF;
END $$;

UPDATE ${mjSchema}."EntityField"
                  SET "IsVirtual" = TRUE,
                      "Type"='TEXT',
                      "Length"=510,
                      "Precision"=0,
                      "Scale"=0,
                      "AllowsNull" = FALSE,
                      "AllowUpdateAPI" = TRUE,
                      "IncludeRelatedEntityNameFieldInBaseView" = FALSE,
                      "RelatedEntityID"=NULL,
                      "RelatedEntityFieldName"=NULL,
                      "RelatedEntityDisplayType"='Search'
                  WHERE "ID"='5F177501-4505-4DFE-9813-9B930DFE80C5';

/* Update IS-A parent field Description on MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks */

UPDATE ${mjSchema}."EntityField"
                  SET "IsVirtual" = TRUE,
                      "Type"='TEXT',
                      "Length"=-1,
                      "Precision"=0,
                      "Scale"=0,
                      "AllowsNull" = TRUE,
                      "AllowUpdateAPI" = TRUE,
                      "IncludeRelatedEntityNameFieldInBaseView" = FALSE,
                      "RelatedEntityID"=NULL,
                      "RelatedEntityFieldName"=NULL,
                      "RelatedEntityDisplayType"='Search'
                  WHERE "ID"='ABC08616-BC3E-441F-8E7D-A4274959C326';

/* Update IS-A parent field TypeID on MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks */

UPDATE ${mjSchema}."EntityField"
                  SET "IsVirtual" = TRUE,
                      "Type"='UUID',
                      "Length"=16,
                      "Precision"=0,
                      "Scale"=0,
                      "AllowsNull" = FALSE,
                      "AllowUpdateAPI" = TRUE,
                      "IncludeRelatedEntityNameFieldInBaseView" = FALSE,
                      "RelatedEntityID"='1E30141A-826F-4278-BAA9-BBE14D29E606',
                      "RelatedEntityFieldName"='ID',
                      "RelatedEntityDisplayType"='Search'
                  WHERE "ID"='104159FF-DB47-414C-A573-22218C8E246E';

/* Update IS-A parent field CategoryID on MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks */

UPDATE ${mjSchema}."EntityField"
                  SET "IsVirtual" = TRUE,
                      "Type"='UUID',
                      "Length"=16,
                      "Precision"=0,
                      "Scale"=0,
                      "AllowsNull" = TRUE,
                      "AllowUpdateAPI" = TRUE,
                      "IncludeRelatedEntityNameFieldInBaseView" = FALSE,
                      "RelatedEntityID"='06303FA3-48F0-45B7-BC6A-F3EBDFEE5CB6',
                      "RelatedEntityFieldName"='ID',
                      "RelatedEntityDisplayType"='Search'
                  WHERE "ID"='BEE37B1E-65C9-4B3B-8E1E-52307578D3F3';

/* Update IS-A parent field ParentID on MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks */

UPDATE ${mjSchema}."EntityField"
                  SET "IsVirtual" = TRUE,
                      "Type"='UUID',
                      "Length"=16,
                      "Precision"=0,
                      "Scale"=0,
                      "AllowsNull" = TRUE,
                      "AllowUpdateAPI" = TRUE,
                      "IncludeRelatedEntityNameFieldInBaseView" = FALSE,
                      "RelatedEntityID"='B348FFA2-B1A7-4AC2-B6FD-F4E0C0697466',
                      "RelatedEntityFieldName"='ID',
                      "RelatedEntityDisplayType"='Search'
                  WHERE "ID"='B3889303-F49F-4D92-853F-65AC124F359D';

/* Update IS-A parent field Status on MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks */

UPDATE ${mjSchema}."EntityField"
                  SET "IsVirtual" = TRUE,
                      "Type"='TEXT',
                      "Length"=100,
                      "Precision"=0,
                      "Scale"=0,
                      "AllowsNull" = FALSE,
                      "AllowUpdateAPI" = TRUE,
                      "IncludeRelatedEntityNameFieldInBaseView" = FALSE,
                      "RelatedEntityID"=NULL,
                      "RelatedEntityFieldName"=NULL,
                      "RelatedEntityDisplayType"='Search'
                  WHERE "ID"='A65EDA96-67F2-4C99-B96C-65388A906AAC';

/* Update IS-A parent field Priority on MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks */

UPDATE ${mjSchema}."EntityField"
                  SET "IsVirtual" = TRUE,
                      "Type"='TEXT',
                      "Length"=40,
                      "Precision"=0,
                      "Scale"=0,
                      "AllowsNull" = FALSE,
                      "AllowUpdateAPI" = TRUE,
                      "IncludeRelatedEntityNameFieldInBaseView" = FALSE,
                      "RelatedEntityID"=NULL,
                      "RelatedEntityFieldName"=NULL,
                      "RelatedEntityDisplayType"='Search'
                  WHERE "ID"='D70ABD8C-2AC1-44E1-AEA2-945D6DAA9ED7';

/* Update IS-A parent field StartedAt on MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks */

UPDATE ${mjSchema}."EntityField"
                  SET "IsVirtual" = TRUE,
                      "Type"='datetimeoffset',
                      "Length"=10,
                      "Precision"=34,
                      "Scale"=7,
                      "AllowsNull" = TRUE,
                      "AllowUpdateAPI" = TRUE,
                      "IncludeRelatedEntityNameFieldInBaseView" = FALSE,
                      "RelatedEntityID"=NULL,
                      "RelatedEntityFieldName"=NULL,
                      "RelatedEntityDisplayType"='Search'
                  WHERE "ID"='E28AF650-AB4A-45BB-A94D-814467A2536D';

/* Update IS-A parent field DueAt on MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks */

UPDATE ${mjSchema}."EntityField"
                  SET "IsVirtual" = TRUE,
                      "Type"='datetimeoffset',
                      "Length"=10,
                      "Precision"=34,
                      "Scale"=7,
                      "AllowsNull" = TRUE,
                      "AllowUpdateAPI" = TRUE,
                      "IncludeRelatedEntityNameFieldInBaseView" = FALSE,
                      "RelatedEntityID"=NULL,
                      "RelatedEntityFieldName"=NULL,
                      "RelatedEntityDisplayType"='Search'
                  WHERE "ID"='B83A675F-795C-47ED-81F4-CBBD5FF4D929';

/* Update IS-A parent field CompletedAt on MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks */

UPDATE ${mjSchema}."EntityField"
                  SET "IsVirtual" = TRUE,
                      "Type"='datetimeoffset',
                      "Length"=10,
                      "Precision"=34,
                      "Scale"=7,
                      "AllowsNull" = TRUE,
                      "AllowUpdateAPI" = TRUE,
                      "IncludeRelatedEntityNameFieldInBaseView" = FALSE,
                      "RelatedEntityID"=NULL,
                      "RelatedEntityFieldName"=NULL,
                      "RelatedEntityDisplayType"='Search'
                  WHERE "ID"='CEF54E7E-100C-432E-9D83-FE29B47C5F73';

/* Update IS-A parent field HoursEstimated on MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks */

UPDATE ${mjSchema}."EntityField"
                  SET "IsVirtual" = TRUE,
                      "Type"='decimal',
                      "Length"=5,
                      "Precision"=8,
                      "Scale"=2,
                      "AllowsNull" = TRUE,
                      "AllowUpdateAPI" = TRUE,
                      "IncludeRelatedEntityNameFieldInBaseView" = FALSE,
                      "RelatedEntityID"=NULL,
                      "RelatedEntityFieldName"=NULL,
                      "RelatedEntityDisplayType"='Search'
                  WHERE "ID"='C9363AE8-2C58-46C5-B437-C7D26A02C353';

/* Update IS-A parent field HoursActual on MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks */

UPDATE ${mjSchema}."EntityField"
                  SET "IsVirtual" = TRUE,
                      "Type"='decimal',
                      "Length"=5,
                      "Precision"=8,
                      "Scale"=2,
                      "AllowsNull" = TRUE,
                      "AllowUpdateAPI" = TRUE,
                      "IncludeRelatedEntityNameFieldInBaseView" = FALSE,
                      "RelatedEntityID"=NULL,
                      "RelatedEntityFieldName"=NULL,
                      "RelatedEntityDisplayType"='Search'
                  WHERE "ID"='3F2F697F-56E2-450F-BF03-77DC470D5754';

/* Update IS-A parent field PercentComplete on MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks */

UPDATE ${mjSchema}."EntityField"
                  SET "IsVirtual" = TRUE,
                      "Type"='INTEGER',
                      "Length"=4,
                      "Precision"=10,
                      "Scale"=0,
                      "AllowsNull" = FALSE,
                      "AllowUpdateAPI" = TRUE,
                      "IncludeRelatedEntityNameFieldInBaseView" = FALSE,
                      "RelatedEntityID"=NULL,
                      "RelatedEntityFieldName"=NULL,
                      "RelatedEntityDisplayType"='Search'
                  WHERE "ID"='732FA3A2-4E55-44C0-9F6B-FE50B894C27E';

/* Update IS-A parent field Sequence on MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks */

UPDATE ${mjSchema}."EntityField"
                  SET "IsVirtual" = TRUE,
                      "Type"='INTEGER',
                      "Length"=4,
                      "Precision"=10,
                      "Scale"=0,
                      "AllowsNull" = FALSE,
                      "AllowUpdateAPI" = TRUE,
                      "IncludeRelatedEntityNameFieldInBaseView" = FALSE,
                      "RelatedEntityID"=NULL,
                      "RelatedEntityFieldName"=NULL,
                      "RelatedEntityDisplayType"='Search'
                  WHERE "ID"='77EC9524-1745-4341-B0FD-EBE74E176E4A';

/* Update IS-A parent field BlockedReason on MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks */

UPDATE ${mjSchema}."EntityField"
                  SET "IsVirtual" = TRUE,
                      "Type"='TEXT',
                      "Length"=-1,
                      "Precision"=0,
                      "Scale"=0,
                      "AllowsNull" = TRUE,
                      "AllowUpdateAPI" = TRUE,
                      "IncludeRelatedEntityNameFieldInBaseView" = FALSE,
                      "RelatedEntityID"=NULL,
                      "RelatedEntityFieldName"=NULL,
                      "RelatedEntityDisplayType"='Search'
                  WHERE "ID"='EAF33611-EB3D-4621-BC57-292F137E43C4';

/* Update IS-A parent field CompletionNotes on MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks */

UPDATE ${mjSchema}."EntityField"
                  SET "IsVirtual" = TRUE,
                      "Type"='TEXT',
                      "Length"=-1,
                      "Precision"=0,
                      "Scale"=0,
                      "AllowsNull" = TRUE,
                      "AllowUpdateAPI" = TRUE,
                      "IncludeRelatedEntityNameFieldInBaseView" = FALSE,
                      "RelatedEntityID"=NULL,
                      "RelatedEntityFieldName"=NULL,
                      "RelatedEntityDisplayType"='Search'
                  WHERE "ID"='E856766E-55A2-4DE8-990E-86D7D1E7056A';

/* Update IS-A parent field CreatedByPersonID on MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks */

UPDATE ${mjSchema}."EntityField"
                  SET "IsVirtual" = TRUE,
                      "Type"='UUID',
                      "Length"=16,
                      "Precision"=0,
                      "Scale"=0,
                      "AllowsNull" = TRUE,
                      "AllowUpdateAPI" = TRUE,
                      "IncludeRelatedEntityNameFieldInBaseView" = FALSE,
                      "RelatedEntityID"='7A94ADA9-7880-4FAE-97D8-DB0E934C3F5F',
                      "RelatedEntityFieldName"='ID',
                      "RelatedEntityDisplayType"='Search'
                  WHERE "ID"='6199AC88-26D6-4320-8B59-952C0E1945EA';

/* Update IS-A parent field OverdueNotifiedAt on MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks */

UPDATE ${mjSchema}."EntityField"
                  SET "IsVirtual" = TRUE,
                      "Type"='datetimeoffset',
                      "Length"=10,
                      "Precision"=34,
                      "Scale"=7,
                      "AllowsNull" = TRUE,
                      "AllowUpdateAPI" = TRUE,
                      "IncludeRelatedEntityNameFieldInBaseView" = FALSE,
                      "RelatedEntityID"=NULL,
                      "RelatedEntityFieldName"=NULL,
                      "RelatedEntityDisplayType"='Search'
                  WHERE "ID"='CE26B855-64AC-45B7-9549-39AC48FA7FA8';

/* Update IS-A parent field TaskTypeStatusID on MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks */

UPDATE ${mjSchema}."EntityField"
                  SET "IsVirtual" = TRUE,
                      "Type"='UUID',
                      "Length"=16,
                      "Precision"=0,
                      "Scale"=0,
                      "AllowsNull" = TRUE,
                      "AllowUpdateAPI" = TRUE,
                      "IncludeRelatedEntityNameFieldInBaseView" = FALSE,
                      "RelatedEntityID"='6C8516B0-D87C-4B57-87F8-474D7FF6CDD9',
                      "RelatedEntityFieldName"='ID',
                      "RelatedEntityDisplayType"='Search'
                  WHERE "ID"='F0ABFE53-246F-41D8-B25A-E462FC412615';

/* Update IS-A parent field PredictedSLABreachProbability on MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks */

UPDATE ${mjSchema}."EntityField"
                  SET "IsVirtual" = TRUE,
                      "Type"='decimal',
                      "Length"=5,
                      "Precision"=5,
                      "Scale"=4,
                      "AllowsNull" = TRUE,
                      "AllowUpdateAPI" = TRUE,
                      "IncludeRelatedEntityNameFieldInBaseView" = FALSE,
                      "RelatedEntityID"=NULL,
                      "RelatedEntityFieldName"=NULL,
                      "RelatedEntityDisplayType"='Search'
                  WHERE "ID"='D1AB1A5C-A1EE-4EC5-95FE-4FD4C8AB7630';

/* Update IS-A parent field PredictedSLARiskBand on MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks */

UPDATE ${mjSchema}."EntityField"
                  SET "IsVirtual" = TRUE,
                      "Type"='TEXT',
                      "Length"=40,
                      "Precision"=0,
                      "Scale"=0,
                      "AllowsNull" = TRUE,
                      "AllowUpdateAPI" = TRUE,
                      "IncludeRelatedEntityNameFieldInBaseView" = FALSE,
                      "RelatedEntityID"=NULL,
                      "RelatedEntityFieldName"=NULL,
                      "RelatedEntityDisplayType"='Search'
                  WHERE "ID"='D2574DDB-325F-473D-997A-66CC43309934';

/* Update IS-A parent field PredictedSLAScoredAt on MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks */

UPDATE ${mjSchema}."EntityField"
                  SET "IsVirtual" = TRUE,
                      "Type"='datetimeoffset',
                      "Length"=10,
                      "Precision"=34,
                      "Scale"=7,
                      "AllowsNull" = TRUE,
                      "AllowUpdateAPI" = TRUE,
                      "IncludeRelatedEntityNameFieldInBaseView" = FALSE,
                      "RelatedEntityID"=NULL,
                      "RelatedEntityFieldName"=NULL,
                      "RelatedEntityDisplayType"='Search'
                  WHERE "ID"='947C6BAE-94D3-4999-AC0F-DAFE404E008F';

/* Update IS-A parent field HealthStatus on MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks */

UPDATE ${mjSchema}."EntityField"
                  SET "IsVirtual" = TRUE,
                      "Type"='TEXT',
                      "Length"=40,
                      "Precision"=0,
                      "Scale"=0,
                      "AllowsNull" = TRUE,
                      "AllowUpdateAPI" = TRUE,
                      "IncludeRelatedEntityNameFieldInBaseView" = FALSE,
                      "RelatedEntityID"=NULL,
                      "RelatedEntityFieldName"=NULL,
                      "RelatedEntityDisplayType"='Search'
                  WHERE "ID"='8EFE7EAC-45DB-4B89-9221-2B19B99068B9';

/* Update IS-A parent field ConfidenceScore on MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks */

UPDATE ${mjSchema}."EntityField"
                  SET "IsVirtual" = TRUE,
                      "Type"='INTEGER',
                      "Length"=4,
                      "Precision"=10,
                      "Scale"=0,
                      "AllowsNull" = TRUE,
                      "AllowUpdateAPI" = TRUE,
                      "IncludeRelatedEntityNameFieldInBaseView" = FALSE,
                      "RelatedEntityID"=NULL,
                      "RelatedEntityFieldName"=NULL,
                      "RelatedEntityDisplayType"='Search'
                  WHERE "ID"='EA927E59-FFD9-4F5C-91BC-DB57A268CB3F';

/* Update IS-A parent field BaselineValue on MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks */

UPDATE ${mjSchema}."EntityField"
                  SET "IsVirtual" = TRUE,
                      "Type"='decimal',
                      "Length"=9,
                      "Precision"=18,
                      "Scale"=4,
                      "AllowsNull" = TRUE,
                      "AllowUpdateAPI" = TRUE,
                      "IncludeRelatedEntityNameFieldInBaseView" = FALSE,
                      "RelatedEntityID"=NULL,
                      "RelatedEntityFieldName"=NULL,
                      "RelatedEntityDisplayType"='Search'
                  WHERE "ID"='835E5643-810D-4B4E-8E83-E9595428437C';

/* Update IS-A parent field TargetValue on MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks */

UPDATE ${mjSchema}."EntityField"
                  SET "IsVirtual" = TRUE,
                      "Type"='decimal',
                      "Length"=9,
                      "Precision"=18,
                      "Scale"=4,
                      "AllowsNull" = TRUE,
                      "AllowUpdateAPI" = TRUE,
                      "IncludeRelatedEntityNameFieldInBaseView" = FALSE,
                      "RelatedEntityID"=NULL,
                      "RelatedEntityFieldName"=NULL,
                      "RelatedEntityDisplayType"='Search'
                  WHERE "ID"='77DD9516-90EF-4855-9CF7-CA0D81B59A8F';

/* Update IS-A parent field CurrentValue on MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks */

UPDATE ${mjSchema}."EntityField"
                  SET "IsVirtual" = TRUE,
                      "Type"='decimal',
                      "Length"=9,
                      "Precision"=18,
                      "Scale"=4,
                      "AllowsNull" = TRUE,
                      "AllowUpdateAPI" = TRUE,
                      "IncludeRelatedEntityNameFieldInBaseView" = FALSE,
                      "RelatedEntityID"=NULL,
                      "RelatedEntityFieldName"=NULL,
                      "RelatedEntityDisplayType"='Search'
                  WHERE "ID"='AF810BE2-BA61-46DD-ADEC-7F3FE7FB35E2';

/* Update IS-A parent field UnitOfMeasure on MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks */

UPDATE ${mjSchema}."EntityField"
                  SET "IsVirtual" = TRUE,
                      "Type"='TEXT',
                      "Length"=100,
                      "Precision"=0,
                      "Scale"=0,
                      "AllowsNull" = TRUE,
                      "AllowUpdateAPI" = TRUE,
                      "IncludeRelatedEntityNameFieldInBaseView" = FALSE,
                      "RelatedEntityID"=NULL,
                      "RelatedEntityFieldName"=NULL,
                      "RelatedEntityDisplayType"='Search'
                  WHERE "ID"='FD6FA1E2-DA35-409A-9116-36640D818333';

/* Update IS-A parent field MetricDirection on MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks */

UPDATE ${mjSchema}."EntityField"
                  SET "IsVirtual" = TRUE,
                      "Type"='TEXT',
                      "Length"=40,
                      "Precision"=0,
                      "Scale"=0,
                      "AllowsNull" = TRUE,
                      "AllowUpdateAPI" = TRUE,
                      "IncludeRelatedEntityNameFieldInBaseView" = FALSE,
                      "RelatedEntityID"=NULL,
                      "RelatedEntityFieldName"=NULL,
                      "RelatedEntityDisplayType"='Search'
                  WHERE "ID"='86B721D5-8AA2-4199-AEF7-C933A6BA52FF';

/* Update IS-A parent field RollupWeight on MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks */

UPDATE ${mjSchema}."EntityField"
                  SET "IsVirtual" = TRUE,
                      "Type"='decimal',
                      "Length"=5,
                      "Precision"=8,
                      "Scale"=2,
                      "AllowsNull" = FALSE,
                      "AllowUpdateAPI" = TRUE,
                      "IncludeRelatedEntityNameFieldInBaseView" = FALSE,
                      "RelatedEntityID"=NULL,
                      "RelatedEntityFieldName"=NULL,
                      "RelatedEntityDisplayType"='Search'
                  WHERE "ID"='03F75DAD-73A6-4C9C-B473-50AF0F4DFDBF';

/* Update IS-A parent field PlanningPeriod on MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks */

UPDATE ${mjSchema}."EntityField"
                  SET "IsVirtual" = TRUE,
                      "Type"='TEXT',
                      "Length"=100,
                      "Precision"=0,
                      "Scale"=0,
                      "AllowsNull" = TRUE,
                      "AllowUpdateAPI" = TRUE,
                      "IncludeRelatedEntityNameFieldInBaseView" = FALSE,
                      "RelatedEntityID"=NULL,
                      "RelatedEntityFieldName"=NULL,
                      "RelatedEntityDisplayType"='Search'
                  WHERE "ID"='E4A34B92-D140-405D-9AB7-1003EDED8BE8';

/* Update IS-A parent field CheckInCadence on MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks */

UPDATE ${mjSchema}."EntityField"
                  SET "IsVirtual" = TRUE,
                      "Type"='TEXT',
                      "Length"=40,
                      "Precision"=0,
                      "Scale"=0,
                      "AllowsNull" = TRUE,
                      "AllowUpdateAPI" = TRUE,
                      "IncludeRelatedEntityNameFieldInBaseView" = FALSE,
                      "RelatedEntityID"=NULL,
                      "RelatedEntityFieldName"=NULL,
                      "RelatedEntityDisplayType"='Search'
                  WHERE "ID"='C652B089-04BD-4A3E-BBAD-07D5D2474568';

/* Update IS-A parent field LastCheckInAt on MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks */

UPDATE ${mjSchema}."EntityField"
                  SET "IsVirtual" = TRUE,
                      "Type"='datetimeoffset',
                      "Length"=10,
                      "Precision"=34,
                      "Scale"=7,
                      "AllowsNull" = TRUE,
                      "AllowUpdateAPI" = TRUE,
                      "IncludeRelatedEntityNameFieldInBaseView" = FALSE,
                      "RelatedEntityID"=NULL,
                      "RelatedEntityFieldName"=NULL,
                      "RelatedEntityDisplayType"='Search'
                  WHERE "ID"='6FE24C88-2E9C-49E9-AFD2-4E0D428F7C50';

/* Update IS-A parent field NextCheckInDueAt on MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks */

UPDATE ${mjSchema}."EntityField"
                  SET "IsVirtual" = TRUE,
                      "Type"='datetimeoffset',
                      "Length"=10,
                      "Precision"=34,
                      "Scale"=7,
                      "AllowsNull" = TRUE,
                      "AllowUpdateAPI" = TRUE,
                      "IncludeRelatedEntityNameFieldInBaseView" = FALSE,
                      "RelatedEntityID"=NULL,
                      "RelatedEntityFieldName"=NULL,
                      "RelatedEntityDisplayType"='Search'
                  WHERE "ID"='C4AA4959-C523-450D-95C7-F7C4119F6211';

/* Update entity timestamp for MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks after IS-A field sync */

UPDATE ${mjSchema}."Entity" SET "__mj_UpdatedAt"=NOW() WHERE "ID"='DC8E0F5B-E172-4FD5-B648-8B4544F8C605';

/* Update IS-A parent field Name on MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks */

UPDATE ${mjSchema}."EntityField"
                  SET "IsVirtual" = TRUE,
                      "Type"='TEXT',
                      "Length"=510,
                      "Precision"=0,
                      "Scale"=0,
                      "AllowsNull" = FALSE,
                      "AllowUpdateAPI" = TRUE,
                      "IncludeRelatedEntityNameFieldInBaseView" = FALSE,
                      "RelatedEntityID"=NULL,
                      "RelatedEntityFieldName"=NULL,
                      "RelatedEntityDisplayType"='Search'
                  WHERE "ID"='4BA1A1F6-223E-4E8D-99D0-16448913D993';

/* Update IS-A parent field Description on MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks */

UPDATE ${mjSchema}."EntityField"
                  SET "IsVirtual" = TRUE,
                      "Type"='TEXT',
                      "Length"=-1,
                      "Precision"=0,
                      "Scale"=0,
                      "AllowsNull" = TRUE,
                      "AllowUpdateAPI" = TRUE,
                      "IncludeRelatedEntityNameFieldInBaseView" = FALSE,
                      "RelatedEntityID"=NULL,
                      "RelatedEntityFieldName"=NULL,
                      "RelatedEntityDisplayType"='Search'
                  WHERE "ID"='504CE539-0CC4-47D3-AD5D-120907A421ED';

/* Update IS-A parent field TypeID on MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks */

UPDATE ${mjSchema}."EntityField"
                  SET "IsVirtual" = TRUE,
                      "Type"='UUID',
                      "Length"=16,
                      "Precision"=0,
                      "Scale"=0,
                      "AllowsNull" = FALSE,
                      "AllowUpdateAPI" = TRUE,
                      "IncludeRelatedEntityNameFieldInBaseView" = FALSE,
                      "RelatedEntityID"='1E30141A-826F-4278-BAA9-BBE14D29E606',
                      "RelatedEntityFieldName"='ID',
                      "RelatedEntityDisplayType"='Search'
                  WHERE "ID"='A26A18FA-8F34-423E-AC94-3F3B47AC87C9';

/* Update IS-A parent field CategoryID on MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks */

UPDATE ${mjSchema}."EntityField"
                  SET "IsVirtual" = TRUE,
                      "Type"='UUID',
                      "Length"=16,
                      "Precision"=0,
                      "Scale"=0,
                      "AllowsNull" = TRUE,
                      "AllowUpdateAPI" = TRUE,
                      "IncludeRelatedEntityNameFieldInBaseView" = FALSE,
                      "RelatedEntityID"='06303FA3-48F0-45B7-BC6A-F3EBDFEE5CB6',
                      "RelatedEntityFieldName"='ID',
                      "RelatedEntityDisplayType"='Search'
                  WHERE "ID"='2F5E2D1C-F10A-42F0-9AD0-71956D6ED9C5';

/* Update IS-A parent field ParentID on MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks */

UPDATE ${mjSchema}."EntityField"
                  SET "IsVirtual" = TRUE,
                      "Type"='UUID',
                      "Length"=16,
                      "Precision"=0,
                      "Scale"=0,
                      "AllowsNull" = TRUE,
                      "AllowUpdateAPI" = TRUE,
                      "IncludeRelatedEntityNameFieldInBaseView" = FALSE,
                      "RelatedEntityID"='B348FFA2-B1A7-4AC2-B6FD-F4E0C0697466',
                      "RelatedEntityFieldName"='ID',
                      "RelatedEntityDisplayType"='Search'
                  WHERE "ID"='8A12D74A-F61C-4669-AB9A-F83FD4418679';

/* Update IS-A parent field Status on MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks */

UPDATE ${mjSchema}."EntityField"
                  SET "IsVirtual" = TRUE,
                      "Type"='TEXT',
                      "Length"=100,
                      "Precision"=0,
                      "Scale"=0,
                      "AllowsNull" = FALSE,
                      "AllowUpdateAPI" = TRUE,
                      "IncludeRelatedEntityNameFieldInBaseView" = FALSE,
                      "RelatedEntityID"=NULL,
                      "RelatedEntityFieldName"=NULL,
                      "RelatedEntityDisplayType"='Search'
                  WHERE "ID"='CCAE381C-911D-407D-BA0B-05BDB95CABFB';

/* Update IS-A parent field Priority on MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks */

UPDATE ${mjSchema}."EntityField"
                  SET "IsVirtual" = TRUE,
                      "Type"='TEXT',
                      "Length"=40,
                      "Precision"=0,
                      "Scale"=0,
                      "AllowsNull" = FALSE,
                      "AllowUpdateAPI" = TRUE,
                      "IncludeRelatedEntityNameFieldInBaseView" = FALSE,
                      "RelatedEntityID"=NULL,
                      "RelatedEntityFieldName"=NULL,
                      "RelatedEntityDisplayType"='Search'
                  WHERE "ID"='10503F3A-EAAD-4EFA-AA23-ED42AF9335F2';

/* Update IS-A parent field StartedAt on MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks */

UPDATE ${mjSchema}."EntityField"
                  SET "IsVirtual" = TRUE,
                      "Type"='datetimeoffset',
                      "Length"=10,
                      "Precision"=34,
                      "Scale"=7,
                      "AllowsNull" = TRUE,
                      "AllowUpdateAPI" = TRUE,
                      "IncludeRelatedEntityNameFieldInBaseView" = FALSE,
                      "RelatedEntityID"=NULL,
                      "RelatedEntityFieldName"=NULL,
                      "RelatedEntityDisplayType"='Search'
                  WHERE "ID"='CFD64243-AD98-4583-9393-E2A86AA869FE';

/* Update IS-A parent field DueAt on MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks */

UPDATE ${mjSchema}."EntityField"
                  SET "IsVirtual" = TRUE,
                      "Type"='datetimeoffset',
                      "Length"=10,
                      "Precision"=34,
                      "Scale"=7,
                      "AllowsNull" = TRUE,
                      "AllowUpdateAPI" = TRUE,
                      "IncludeRelatedEntityNameFieldInBaseView" = FALSE,
                      "RelatedEntityID"=NULL,
                      "RelatedEntityFieldName"=NULL,
                      "RelatedEntityDisplayType"='Search'
                  WHERE "ID"='D6A809C0-B643-4045-BBBC-43420E9C4D9D';

/* Update IS-A parent field CompletedAt on MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks */

UPDATE ${mjSchema}."EntityField"
                  SET "IsVirtual" = TRUE,
                      "Type"='datetimeoffset',
                      "Length"=10,
                      "Precision"=34,
                      "Scale"=7,
                      "AllowsNull" = TRUE,
                      "AllowUpdateAPI" = TRUE,
                      "IncludeRelatedEntityNameFieldInBaseView" = FALSE,
                      "RelatedEntityID"=NULL,
                      "RelatedEntityFieldName"=NULL,
                      "RelatedEntityDisplayType"='Search'
                  WHERE "ID"='AEB061C9-C5B7-429C-BBFB-BFE7F0B9B8DB';

/* Update IS-A parent field HoursEstimated on MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks */

UPDATE ${mjSchema}."EntityField"
                  SET "IsVirtual" = TRUE,
                      "Type"='decimal',
                      "Length"=5,
                      "Precision"=8,
                      "Scale"=2,
                      "AllowsNull" = TRUE,
                      "AllowUpdateAPI" = TRUE,
                      "IncludeRelatedEntityNameFieldInBaseView" = FALSE,
                      "RelatedEntityID"=NULL,
                      "RelatedEntityFieldName"=NULL,
                      "RelatedEntityDisplayType"='Search'
                  WHERE "ID"='05869A56-0E75-4721-8FDF-4969DF401C85';

/* Update IS-A parent field HoursActual on MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks */

UPDATE ${mjSchema}."EntityField"
                  SET "IsVirtual" = TRUE,
                      "Type"='decimal',
                      "Length"=5,
                      "Precision"=8,
                      "Scale"=2,
                      "AllowsNull" = TRUE,
                      "AllowUpdateAPI" = TRUE,
                      "IncludeRelatedEntityNameFieldInBaseView" = FALSE,
                      "RelatedEntityID"=NULL,
                      "RelatedEntityFieldName"=NULL,
                      "RelatedEntityDisplayType"='Search'
                  WHERE "ID"='5025C924-87BC-4045-B5B2-AF280B8BF9D5';

/* Update IS-A parent field PercentComplete on MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks */

UPDATE ${mjSchema}."EntityField"
                  SET "IsVirtual" = TRUE,
                      "Type"='INTEGER',
                      "Length"=4,
                      "Precision"=10,
                      "Scale"=0,
                      "AllowsNull" = FALSE,
                      "AllowUpdateAPI" = TRUE,
                      "IncludeRelatedEntityNameFieldInBaseView" = FALSE,
                      "RelatedEntityID"=NULL,
                      "RelatedEntityFieldName"=NULL,
                      "RelatedEntityDisplayType"='Search'
                  WHERE "ID"='C0C67A45-F9F6-4962-A5DC-2176F8EF1F0A';

/* Update IS-A parent field Sequence on MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks */

UPDATE ${mjSchema}."EntityField"
                  SET "IsVirtual" = TRUE,
                      "Type"='INTEGER',
                      "Length"=4,
                      "Precision"=10,
                      "Scale"=0,
                      "AllowsNull" = FALSE,
                      "AllowUpdateAPI" = TRUE,
                      "IncludeRelatedEntityNameFieldInBaseView" = FALSE,
                      "RelatedEntityID"=NULL,
                      "RelatedEntityFieldName"=NULL,
                      "RelatedEntityDisplayType"='Search'
                  WHERE "ID"='C1D1EB47-D5AF-42B7-926E-38440E14B0B0';

/* Update IS-A parent field BlockedReason on MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks */

UPDATE ${mjSchema}."EntityField"
                  SET "IsVirtual" = TRUE,
                      "Type"='TEXT',
                      "Length"=-1,
                      "Precision"=0,
                      "Scale"=0,
                      "AllowsNull" = TRUE,
                      "AllowUpdateAPI" = TRUE,
                      "IncludeRelatedEntityNameFieldInBaseView" = FALSE,
                      "RelatedEntityID"=NULL,
                      "RelatedEntityFieldName"=NULL,
                      "RelatedEntityDisplayType"='Search'
                  WHERE "ID"='3365149D-DB81-4D9D-BB29-2D491C6E86FA';

/* Update IS-A parent field CompletionNotes on MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks */

UPDATE ${mjSchema}."EntityField"
                  SET "IsVirtual" = TRUE,
                      "Type"='TEXT',
                      "Length"=-1,
                      "Precision"=0,
                      "Scale"=0,
                      "AllowsNull" = TRUE,
                      "AllowUpdateAPI" = TRUE,
                      "IncludeRelatedEntityNameFieldInBaseView" = FALSE,
                      "RelatedEntityID"=NULL,
                      "RelatedEntityFieldName"=NULL,
                      "RelatedEntityDisplayType"='Search'
                  WHERE "ID"='61B50EAD-8C53-4C9F-96AA-76ECDEDAE434';

/* Update IS-A parent field CreatedByPersonID on MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks */

UPDATE ${mjSchema}."EntityField"
                  SET "IsVirtual" = TRUE,
                      "Type"='UUID',
                      "Length"=16,
                      "Precision"=0,
                      "Scale"=0,
                      "AllowsNull" = TRUE,
                      "AllowUpdateAPI" = TRUE,
                      "IncludeRelatedEntityNameFieldInBaseView" = FALSE,
                      "RelatedEntityID"='7A94ADA9-7880-4FAE-97D8-DB0E934C3F5F',
                      "RelatedEntityFieldName"='ID',
                      "RelatedEntityDisplayType"='Search'
                  WHERE "ID"='FB407166-23F9-4BB3-98FB-599F619BB218';

/* Update IS-A parent field OverdueNotifiedAt on MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks */

UPDATE ${mjSchema}."EntityField"
                  SET "IsVirtual" = TRUE,
                      "Type"='datetimeoffset',
                      "Length"=10,
                      "Precision"=34,
                      "Scale"=7,
                      "AllowsNull" = TRUE,
                      "AllowUpdateAPI" = TRUE,
                      "IncludeRelatedEntityNameFieldInBaseView" = FALSE,
                      "RelatedEntityID"=NULL,
                      "RelatedEntityFieldName"=NULL,
                      "RelatedEntityDisplayType"='Search'
                  WHERE "ID"='23302EB0-8C39-40D4-B309-FAF86854AEE2';

/* Update IS-A parent field TaskTypeStatusID on MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks */

UPDATE ${mjSchema}."EntityField"
                  SET "IsVirtual" = TRUE,
                      "Type"='UUID',
                      "Length"=16,
                      "Precision"=0,
                      "Scale"=0,
                      "AllowsNull" = TRUE,
                      "AllowUpdateAPI" = TRUE,
                      "IncludeRelatedEntityNameFieldInBaseView" = FALSE,
                      "RelatedEntityID"='6C8516B0-D87C-4B57-87F8-474D7FF6CDD9',
                      "RelatedEntityFieldName"='ID',
                      "RelatedEntityDisplayType"='Search'
                  WHERE "ID"='84A6F1CB-4453-4651-B20F-58F0A29789C8';

/* Update IS-A parent field PredictedSLABreachProbability on MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks */

UPDATE ${mjSchema}."EntityField"
                  SET "IsVirtual" = TRUE,
                      "Type"='decimal',
                      "Length"=5,
                      "Precision"=5,
                      "Scale"=4,
                      "AllowsNull" = TRUE,
                      "AllowUpdateAPI" = TRUE,
                      "IncludeRelatedEntityNameFieldInBaseView" = FALSE,
                      "RelatedEntityID"=NULL,
                      "RelatedEntityFieldName"=NULL,
                      "RelatedEntityDisplayType"='Search'
                  WHERE "ID"='9AAF8300-10B1-4C0C-8A05-CE90F22C22E4';

/* Update IS-A parent field PredictedSLARiskBand on MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks */

UPDATE ${mjSchema}."EntityField"
                  SET "IsVirtual" = TRUE,
                      "Type"='TEXT',
                      "Length"=40,
                      "Precision"=0,
                      "Scale"=0,
                      "AllowsNull" = TRUE,
                      "AllowUpdateAPI" = TRUE,
                      "IncludeRelatedEntityNameFieldInBaseView" = FALSE,
                      "RelatedEntityID"=NULL,
                      "RelatedEntityFieldName"=NULL,
                      "RelatedEntityDisplayType"='Search'
                  WHERE "ID"='95D95CDC-AECE-417E-A7EB-BB87A0197A3E';

/* Update IS-A parent field PredictedSLAScoredAt on MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks */

UPDATE ${mjSchema}."EntityField"
                  SET "IsVirtual" = TRUE,
                      "Type"='datetimeoffset',
                      "Length"=10,
                      "Precision"=34,
                      "Scale"=7,
                      "AllowsNull" = TRUE,
                      "AllowUpdateAPI" = TRUE,
                      "IncludeRelatedEntityNameFieldInBaseView" = FALSE,
                      "RelatedEntityID"=NULL,
                      "RelatedEntityFieldName"=NULL,
                      "RelatedEntityDisplayType"='Search'
                  WHERE "ID"='6EBF3400-38A4-4CE7-A1E8-76DFBB328821';

/* Update IS-A parent field HealthStatus on MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks */

UPDATE ${mjSchema}."EntityField"
                  SET "IsVirtual" = TRUE,
                      "Type"='TEXT',
                      "Length"=40,
                      "Precision"=0,
                      "Scale"=0,
                      "AllowsNull" = TRUE,
                      "AllowUpdateAPI" = TRUE,
                      "IncludeRelatedEntityNameFieldInBaseView" = FALSE,
                      "RelatedEntityID"=NULL,
                      "RelatedEntityFieldName"=NULL,
                      "RelatedEntityDisplayType"='Search'
                  WHERE "ID"='FF834CC2-1FD6-438E-BD22-82F6BEA0EAF2';

/* Update IS-A parent field ConfidenceScore on MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks */

UPDATE ${mjSchema}."EntityField"
                  SET "IsVirtual" = TRUE,
                      "Type"='INTEGER',
                      "Length"=4,
                      "Precision"=10,
                      "Scale"=0,
                      "AllowsNull" = TRUE,
                      "AllowUpdateAPI" = TRUE,
                      "IncludeRelatedEntityNameFieldInBaseView" = FALSE,
                      "RelatedEntityID"=NULL,
                      "RelatedEntityFieldName"=NULL,
                      "RelatedEntityDisplayType"='Search'
                  WHERE "ID"='6B700581-9114-4D4D-87FD-7803E6990FE6';

/* Update IS-A parent field BaselineValue on MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks */

UPDATE ${mjSchema}."EntityField"
                  SET "IsVirtual" = TRUE,
                      "Type"='decimal',
                      "Length"=9,
                      "Precision"=18,
                      "Scale"=4,
                      "AllowsNull" = TRUE,
                      "AllowUpdateAPI" = TRUE,
                      "IncludeRelatedEntityNameFieldInBaseView" = FALSE,
                      "RelatedEntityID"=NULL,
                      "RelatedEntityFieldName"=NULL,
                      "RelatedEntityDisplayType"='Search'
                  WHERE "ID"='2FAB02DE-F972-461E-9B21-4387520AF9B2';

/* Update IS-A parent field TargetValue on MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks */

UPDATE ${mjSchema}."EntityField"
                  SET "IsVirtual" = TRUE,
                      "Type"='decimal',
                      "Length"=9,
                      "Precision"=18,
                      "Scale"=4,
                      "AllowsNull" = TRUE,
                      "AllowUpdateAPI" = TRUE,
                      "IncludeRelatedEntityNameFieldInBaseView" = FALSE,
                      "RelatedEntityID"=NULL,
                      "RelatedEntityFieldName"=NULL,
                      "RelatedEntityDisplayType"='Search'
                  WHERE "ID"='D9BDA046-A66F-4965-B964-56A2833E4000';

/* Update IS-A parent field CurrentValue on MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks */

UPDATE ${mjSchema}."EntityField"
                  SET "IsVirtual" = TRUE,
                      "Type"='decimal',
                      "Length"=9,
                      "Precision"=18,
                      "Scale"=4,
                      "AllowsNull" = TRUE,
                      "AllowUpdateAPI" = TRUE,
                      "IncludeRelatedEntityNameFieldInBaseView" = FALSE,
                      "RelatedEntityID"=NULL,
                      "RelatedEntityFieldName"=NULL,
                      "RelatedEntityDisplayType"='Search'
                  WHERE "ID"='D568F0DF-CF9A-41D6-8ECE-5ED935AFFF02';

/* Update IS-A parent field UnitOfMeasure on MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks */

UPDATE ${mjSchema}."EntityField"
                  SET "IsVirtual" = TRUE,
                      "Type"='TEXT',
                      "Length"=100,
                      "Precision"=0,
                      "Scale"=0,
                      "AllowsNull" = TRUE,
                      "AllowUpdateAPI" = TRUE,
                      "IncludeRelatedEntityNameFieldInBaseView" = FALSE,
                      "RelatedEntityID"=NULL,
                      "RelatedEntityFieldName"=NULL,
                      "RelatedEntityDisplayType"='Search'
                  WHERE "ID"='A15515CE-2505-4A75-909B-996D159BF8B3';

/* Update IS-A parent field MetricDirection on MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks */

UPDATE ${mjSchema}."EntityField"
                  SET "IsVirtual" = TRUE,
                      "Type"='TEXT',
                      "Length"=40,
                      "Precision"=0,
                      "Scale"=0,
                      "AllowsNull" = TRUE,
                      "AllowUpdateAPI" = TRUE,
                      "IncludeRelatedEntityNameFieldInBaseView" = FALSE,
                      "RelatedEntityID"=NULL,
                      "RelatedEntityFieldName"=NULL,
                      "RelatedEntityDisplayType"='Search'
                  WHERE "ID"='72A1ACE2-6BD6-4861-9DE0-F617873736D7';

/* Update IS-A parent field RollupWeight on MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks */

UPDATE ${mjSchema}."EntityField"
                  SET "IsVirtual" = TRUE,
                      "Type"='decimal',
                      "Length"=5,
                      "Precision"=8,
                      "Scale"=2,
                      "AllowsNull" = FALSE,
                      "AllowUpdateAPI" = TRUE,
                      "IncludeRelatedEntityNameFieldInBaseView" = FALSE,
                      "RelatedEntityID"=NULL,
                      "RelatedEntityFieldName"=NULL,
                      "RelatedEntityDisplayType"='Search'
                  WHERE "ID"='32734BDB-ADA6-4D79-B571-BB7A39E50808';

/* Update IS-A parent field PlanningPeriod on MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks */

UPDATE ${mjSchema}."EntityField"
                  SET "IsVirtual" = TRUE,
                      "Type"='TEXT',
                      "Length"=100,
                      "Precision"=0,
                      "Scale"=0,
                      "AllowsNull" = TRUE,
                      "AllowUpdateAPI" = TRUE,
                      "IncludeRelatedEntityNameFieldInBaseView" = FALSE,
                      "RelatedEntityID"=NULL,
                      "RelatedEntityFieldName"=NULL,
                      "RelatedEntityDisplayType"='Search'
                  WHERE "ID"='74340CB6-2CF9-4078-B056-BCEC5AB63A3A';

/* Update IS-A parent field CheckInCadence on MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks */

UPDATE ${mjSchema}."EntityField"
                  SET "IsVirtual" = TRUE,
                      "Type"='TEXT',
                      "Length"=40,
                      "Precision"=0,
                      "Scale"=0,
                      "AllowsNull" = TRUE,
                      "AllowUpdateAPI" = TRUE,
                      "IncludeRelatedEntityNameFieldInBaseView" = FALSE,
                      "RelatedEntityID"=NULL,
                      "RelatedEntityFieldName"=NULL,
                      "RelatedEntityDisplayType"='Search'
                  WHERE "ID"='74337FD7-6B08-4EE4-AFE9-5C97EE684B19';

/* Update IS-A parent field LastCheckInAt on MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks */

UPDATE ${mjSchema}."EntityField"
                  SET "IsVirtual" = TRUE,
                      "Type"='datetimeoffset',
                      "Length"=10,
                      "Precision"=34,
                      "Scale"=7,
                      "AllowsNull" = TRUE,
                      "AllowUpdateAPI" = TRUE,
                      "IncludeRelatedEntityNameFieldInBaseView" = FALSE,
                      "RelatedEntityID"=NULL,
                      "RelatedEntityFieldName"=NULL,
                      "RelatedEntityDisplayType"='Search'
                  WHERE "ID"='8CAF3BC8-B357-4B60-AD0E-76B818806CCC';

/* Update IS-A parent field NextCheckInDueAt on MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks */

UPDATE ${mjSchema}."EntityField"
                  SET "IsVirtual" = TRUE,
                      "Type"='datetimeoffset',
                      "Length"=10,
                      "Precision"=34,
                      "Scale"=7,
                      "AllowsNull" = TRUE,
                      "AllowUpdateAPI" = TRUE,
                      "IncludeRelatedEntityNameFieldInBaseView" = FALSE,
                      "RelatedEntityID"=NULL,
                      "RelatedEntityFieldName"=NULL,
                      "RelatedEntityDisplayType"='Search'
                  WHERE "ID"='8DB46A9C-8567-43D3-85E1-AF3174F6628F';

/* Update entity timestamp for MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks after IS-A field sync */

UPDATE ${mjSchema}."Entity" SET "__mj_UpdatedAt"=NOW() WHERE "ID"='A6B673F8-43BC-4875-AFF6-AC620592822E';

/* SQL text to set default column width where needed */

UPDATE ${mjSchema}."EntityField"
               SET "IsNameField" = FALSE
               WHERE "ID" = '8A9B093F-91D1-4991-9069-4F2F36AD9181'
               AND "AutoUpdateIsNameField" = TRUE;

UPDATE ${mjSchema}."EntityField"
               SET "DefaultInView" = TRUE
               WHERE "ID" = 'A65EDA96-67F2-4C99-B96C-65388A906AAC'
               AND "AutoUpdateDefaultInView" = TRUE;

UPDATE ${mjSchema}."EntityField"
               SET "DefaultInView" = TRUE
               WHERE "ID" = 'D70ABD8C-2AC1-44E1-AEA2-945D6DAA9ED7'
               AND "AutoUpdateDefaultInView" = TRUE;

UPDATE ${mjSchema}."EntityField"
               SET "DefaultInView" = TRUE
               WHERE "ID" = 'B83A675F-795C-47ED-81F4-CBBD5FF4D929'
               AND "AutoUpdateDefaultInView" = TRUE;

UPDATE ${mjSchema}."EntityField"
               SET "UserSearchPredicateAPI" = 'BeginsWith'
               WHERE "ID" = '5F177501-4505-4DFE-9813-9B930DFE80C5'
               AND "AutoUpdateUserSearchPredicate" = TRUE;

/* Set field properties for entity */

UPDATE ${mjSchema}."EntityField"
               SET "DefaultInView" = TRUE
               WHERE "ID" = 'CCAE381C-911D-407D-BA0B-05BDB95CABFB'
               AND "AutoUpdateDefaultInView" = TRUE;

UPDATE ${mjSchema}."EntityField"
               SET "UserSearchPredicateAPI" = 'BeginsWith'
               WHERE "ID" = '4BA1A1F6-223E-4E8D-99D0-16448913D993'
               AND "AutoUpdateUserSearchPredicate" = TRUE;

/* Set categories for 34 fields */

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks.Name

UPDATE ${mjSchema}."EntityField"
SET 
   "Category" = 'Task Details',
   "GeneratedFormSection" = 'Category'
WHERE 
   "ID" = '5F177501-4505-4DFE-9813-9B930DFE80C5';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks.Description

UPDATE ${mjSchema}."EntityField"
SET 
   "Category" = 'Task Details',
   "GeneratedFormSection" = 'Category'
WHERE 
   "ID" = 'ABC08616-BC3E-441F-8E7D-A4274959C326';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks.TypeID

UPDATE ${mjSchema}."EntityField"
SET 
   "Category" = 'Task Details',
   "GeneratedFormSection" = 'Category',
   "DisplayName" = 'Task Type'
WHERE 
   "ID" = '104159FF-DB47-414C-A573-22218C8E246E';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks.CategoryID

UPDATE ${mjSchema}."EntityField"
SET 
   "Category" = 'Task Details',
   "GeneratedFormSection" = 'Category',
   "DisplayName" = 'Category'
WHERE 
   "ID" = 'BEE37B1E-65C9-4B3B-8E1E-52307578D3F3';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks.ParentID

UPDATE ${mjSchema}."EntityField"
SET 
   "Category" = 'Task Details',
   "GeneratedFormSection" = 'Category',
   "DisplayName" = 'Parent Task'
WHERE 
   "ID" = 'B3889303-F49F-4D92-853F-65AC124F359D';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks.Status

UPDATE ${mjSchema}."EntityField"
SET 
   "Category" = 'Task Details',
   "GeneratedFormSection" = 'Category'
WHERE 
   "ID" = 'A65EDA96-67F2-4C99-B96C-65388A906AAC';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks.Priority

UPDATE ${mjSchema}."EntityField"
SET 
   "Category" = 'Task Details',
   "GeneratedFormSection" = 'Category'
WHERE 
   "ID" = 'D70ABD8C-2AC1-44E1-AEA2-945D6DAA9ED7';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks.Sequence

UPDATE ${mjSchema}."EntityField"
SET 
   "Category" = 'Task Details',
   "GeneratedFormSection" = 'Category'
WHERE 
   "ID" = '77EC9524-1745-4341-B0FD-EBE74E176E4A';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks.BlockedReason

UPDATE ${mjSchema}."EntityField"
SET 
   "Category" = 'Task Details',
   "GeneratedFormSection" = 'Category'
WHERE 
   "ID" = 'EAF33611-EB3D-4621-BC57-292F137E43C4';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks.CompletionNotes

UPDATE ${mjSchema}."EntityField"
SET 
   "Category" = 'Task Details',
   "GeneratedFormSection" = 'Category'
WHERE 
   "ID" = 'E856766E-55A2-4DE8-990E-86D7D1E7056A';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks.CreatedByPersonID

UPDATE ${mjSchema}."EntityField"
SET 
   "Category" = 'Task Details',
   "GeneratedFormSection" = 'Category',
   "DisplayName" = 'Created By Person'
WHERE 
   "ID" = '6199AC88-26D6-4320-8B59-952C0E1945EA';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks.TaskTypeStatusID

UPDATE ${mjSchema}."EntityField"
SET 
   "Category" = 'Task Details',
   "GeneratedFormSection" = 'Category',
   "DisplayName" = 'Task Type Status'
WHERE 
   "ID" = 'F0ABFE53-246F-41D8-B25A-E462FC412615';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks.HealthStatus

UPDATE ${mjSchema}."EntityField"
SET 
   "Category" = 'Task Details',
   "GeneratedFormSection" = 'Category'
WHERE 
   "ID" = '8EFE7EAC-45DB-4B89-9221-2B19B99068B9';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks.ConfidenceScore

UPDATE ${mjSchema}."EntityField"
SET 
   "Category" = 'Task Details',
   "GeneratedFormSection" = 'Category'
WHERE 
   "ID" = 'EA927E59-FFD9-4F5C-91BC-DB57A268CB3F';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks.PlanningPeriod

UPDATE ${mjSchema}."EntityField"
SET 
   "Category" = 'Task Details',
   "GeneratedFormSection" = 'Category'
WHERE 
   "ID" = 'E4A34B92-D140-405D-9AB7-1003EDED8BE8';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks.CheckInCadence

UPDATE ${mjSchema}."EntityField"
SET 
   "Category" = 'Task Details',
   "GeneratedFormSection" = 'Category',
   "DisplayName" = 'Check-In Cadence'
WHERE 
   "ID" = 'C652B089-04BD-4A3E-BBAD-07D5D2474568';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks.StartedAt

UPDATE ${mjSchema}."EntityField"
SET 
   "Category" = 'Task Schedule and Metrics',
   "GeneratedFormSection" = 'Category'
WHERE 
   "ID" = 'E28AF650-AB4A-45BB-A94D-814467A2536D';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks.DueAt

UPDATE ${mjSchema}."EntityField"
SET 
   "Category" = 'Task Schedule and Metrics',
   "GeneratedFormSection" = 'Category'
WHERE 
   "ID" = 'B83A675F-795C-47ED-81F4-CBBD5FF4D929';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks.CompletedAt

UPDATE ${mjSchema}."EntityField"
SET 
   "Category" = 'Task Schedule and Metrics',
   "GeneratedFormSection" = 'Category'
WHERE 
   "ID" = 'CEF54E7E-100C-432E-9D83-FE29B47C5F73';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks.HoursEstimated

UPDATE ${mjSchema}."EntityField"
SET 
   "Category" = 'Task Schedule and Metrics',
   "GeneratedFormSection" = 'Category'
WHERE 
   "ID" = 'C9363AE8-2C58-46C5-B437-C7D26A02C353';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks.HoursActual

UPDATE ${mjSchema}."EntityField"
SET 
   "Category" = 'Task Schedule and Metrics',
   "GeneratedFormSection" = 'Category'
WHERE 
   "ID" = '3F2F697F-56E2-450F-BF03-77DC470D5754';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks.PercentComplete

UPDATE ${mjSchema}."EntityField"
SET 
   "Category" = 'Task Schedule and Metrics',
   "GeneratedFormSection" = 'Category'
WHERE 
   "ID" = '732FA3A2-4E55-44C0-9F6B-FE50B894C27E';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks.OverdueNotifiedAt

UPDATE ${mjSchema}."EntityField"
SET 
   "Category" = 'Task Schedule and Metrics',
   "GeneratedFormSection" = 'Category'
WHERE 
   "ID" = 'CE26B855-64AC-45B7-9549-39AC48FA7FA8';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks.PredictedSLABreachProbability

UPDATE ${mjSchema}."EntityField"
SET 
   "Category" = 'Task Schedule and Metrics',
   "GeneratedFormSection" = 'Category'
WHERE 
   "ID" = 'D1AB1A5C-A1EE-4EC5-95FE-4FD4C8AB7630';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks.PredictedSLARiskBand

UPDATE ${mjSchema}."EntityField"
SET 
   "Category" = 'Task Schedule and Metrics',
   "GeneratedFormSection" = 'Category'
WHERE 
   "ID" = 'D2574DDB-325F-473D-997A-66CC43309934';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks.PredictedSLAScoredAt

UPDATE ${mjSchema}."EntityField"
SET 
   "Category" = 'Task Schedule and Metrics',
   "GeneratedFormSection" = 'Category'
WHERE 
   "ID" = '947C6BAE-94D3-4999-AC0F-DAFE404E008F';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks.BaselineValue

UPDATE ${mjSchema}."EntityField"
SET 
   "Category" = 'Task Schedule and Metrics',
   "GeneratedFormSection" = 'Category'
WHERE 
   "ID" = '835E5643-810D-4B4E-8E83-E9595428437C';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks.TargetValue

UPDATE ${mjSchema}."EntityField"
SET 
   "Category" = 'Task Schedule and Metrics',
   "GeneratedFormSection" = 'Category'
WHERE 
   "ID" = '77DD9516-90EF-4855-9CF7-CA0D81B59A8F';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks.CurrentValue

UPDATE ${mjSchema}."EntityField"
SET 
   "Category" = 'Task Schedule and Metrics',
   "GeneratedFormSection" = 'Category'
WHERE 
   "ID" = 'AF810BE2-BA61-46DD-ADEC-7F3FE7FB35E2';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks.UnitOfMeasure

UPDATE ${mjSchema}."EntityField"
SET 
   "Category" = 'Task Schedule and Metrics',
   "GeneratedFormSection" = 'Category'
WHERE 
   "ID" = 'FD6FA1E2-DA35-409A-9116-36640D818333';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks.MetricDirection

UPDATE ${mjSchema}."EntityField"
SET 
   "Category" = 'Task Schedule and Metrics',
   "GeneratedFormSection" = 'Category'
WHERE 
   "ID" = '86B721D5-8AA2-4199-AEF7-C933A6BA52FF';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks.RollupWeight

UPDATE ${mjSchema}."EntityField"
SET 
   "Category" = 'Task Schedule and Metrics',
   "GeneratedFormSection" = 'Category'
WHERE 
   "ID" = '03F75DAD-73A6-4C9C-B473-50AF0F4DFDBF';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks.LastCheckInAt

UPDATE ${mjSchema}."EntityField"
SET 
   "Category" = 'Task Schedule and Metrics',
   "GeneratedFormSection" = 'Category',
   "DisplayName" = 'Last Check-In At'
WHERE 
   "ID" = '6FE24C88-2E9C-49E9-AFD2-4E0D428F7C50';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks.NextCheckInDueAt

UPDATE ${mjSchema}."EntityField"
SET 
   "Category" = 'Task Schedule and Metrics',
   "GeneratedFormSection" = 'Category',
   "DisplayName" = 'Next Check-In Due At'
WHERE 
   "ID" = 'C4AA4959-C523-450D-95C7-F7C4119F6211';

/* Update FieldCategoryInfo setting for entity */

UPDATE ${mjSchema}."EntitySetting"
                  SET "Value" = '{
  "GitHub Issue Details": {
    "description": "Core GitHub issue metadata, identifiers, URLs, state, and labels",
    "icon": "fab fa-github"
  },
  "Milestone and Timeline": {
    "description": "GitHub milestone assignments and associated target due dates",
    "icon": "fa fa-calendar-alt"
  },
  "Sync and Audit Information": {
    "description": "External synchronization tracking keys, content hashes, and upstream timestamps",
    "icon": "fa fa-sync"
  },
  "System Metadata": {
    "description": "System-managed audit and primary key fields",
    "icon": "fa fa-cog"
  },
  "Task Details": {
    "description": "Core task details inherited from the Tasks entity",
    "icon": "fa fa-tasks",
    "inheritedFromEntityID": "B348FFA2-B1A7-4AC2-B6FD-F4E0C0697466",
    "inheritedFromEntityName": "MJ_BizApps_Tasks: Tasks"
  },
  "Task Schedule and Metrics": {
    "description": "Schedule, progress metrics, and SLAs inherited from the Tasks entity",
    "icon": "fa fa-chart-line",
    "inheritedFromEntityID": "B348FFA2-B1A7-4AC2-B6FD-F4E0C0697466",
    "inheritedFromEntityName": "MJ_BizApps_Tasks: Tasks"
  }
}', "__mj_UpdatedAt" = NOW()
                  WHERE "EntityID" = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605' AND "Name" = 'FieldCategoryInfo';

/* Update FieldCategoryIcons setting (legacy) */

UPDATE ${mjSchema}."EntitySetting"
                  SET "Value" = '{
  "GitHub Issue Details": "fab fa-github",
  "Milestone and Timeline": "fa fa-calendar-alt",
  "Sync and Audit Information": "fa fa-sync",
  "System Metadata": "fa fa-cog",
  "Task Details": "fa fa-tasks",
  "Task Schedule and Metrics": "fa fa-chart-line"
}', "__mj_UpdatedAt" = NOW()
                  WHERE "EntityID" = 'DC8E0F5B-E172-4FD5-B648-8B4544F8C605' AND "Name" = 'FieldCategoryIcons';

/* Set categories for 34 fields */

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks.Name

UPDATE ${mjSchema}."EntityField"
SET 
   "Category" = 'Task Details',
   "GeneratedFormSection" = 'Category'
WHERE 
   "ID" = '4BA1A1F6-223E-4E8D-99D0-16448913D993';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks.Description

UPDATE ${mjSchema}."EntityField"
SET 
   "Category" = 'Task Details',
   "GeneratedFormSection" = 'Category'
WHERE 
   "ID" = '504CE539-0CC4-47D3-AD5D-120907A421ED';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks.TypeID

UPDATE ${mjSchema}."EntityField"
SET 
   "Category" = 'Task Details',
   "GeneratedFormSection" = 'Category',
   "DisplayName" = 'Type'
WHERE 
   "ID" = 'A26A18FA-8F34-423E-AC94-3F3B47AC87C9';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks.CategoryID

UPDATE ${mjSchema}."EntityField"
SET 
   "Category" = 'Task Details',
   "GeneratedFormSection" = 'Category',
   "DisplayName" = 'Category'
WHERE 
   "ID" = '2F5E2D1C-F10A-42F0-9AD0-71956D6ED9C5';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks.ParentID

UPDATE ${mjSchema}."EntityField"
SET 
   "Category" = 'Task Details',
   "GeneratedFormSection" = 'Category',
   "DisplayName" = 'Parent Task'
WHERE 
   "ID" = '8A12D74A-F61C-4669-AB9A-F83FD4418679';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks.Status

UPDATE ${mjSchema}."EntityField"
SET 
   "Category" = 'Task Status and Workflow',
   "GeneratedFormSection" = 'Category'
WHERE 
   "ID" = 'CCAE381C-911D-407D-BA0B-05BDB95CABFB';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks.Priority

UPDATE ${mjSchema}."EntityField"
SET 
   "Category" = 'Task Status and Workflow',
   "GeneratedFormSection" = 'Category'
WHERE 
   "ID" = '10503F3A-EAAD-4EFA-AA23-ED42AF9335F2';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks.StartedAt

UPDATE ${mjSchema}."EntityField"
SET 
   "Category" = 'Task Timeline',
   "GeneratedFormSection" = 'Category'
WHERE 
   "ID" = 'CFD64243-AD98-4583-9393-E2A86AA869FE';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks.DueAt

UPDATE ${mjSchema}."EntityField"
SET 
   "Category" = 'Task Timeline',
   "GeneratedFormSection" = 'Category'
WHERE 
   "ID" = 'D6A809C0-B643-4045-BBBC-43420E9C4D9D';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks.CompletedAt

UPDATE ${mjSchema}."EntityField"
SET 
   "Category" = 'Task Timeline',
   "GeneratedFormSection" = 'Category'
WHERE 
   "ID" = 'AEB061C9-C5B7-429C-BBFB-BFE7F0B9B8DB';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks.HoursEstimated

UPDATE ${mjSchema}."EntityField"
SET 
   "Category" = 'Task Effort and Metrics',
   "GeneratedFormSection" = 'Category'
WHERE 
   "ID" = '05869A56-0E75-4721-8FDF-4969DF401C85';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks.HoursActual

UPDATE ${mjSchema}."EntityField"
SET 
   "Category" = 'Task Effort and Metrics',
   "GeneratedFormSection" = 'Category'
WHERE 
   "ID" = '5025C924-87BC-4045-B5B2-AF280B8BF9D5';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks.PercentComplete

UPDATE ${mjSchema}."EntityField"
SET 
   "Category" = 'Task Effort and Metrics',
   "GeneratedFormSection" = 'Category'
WHERE 
   "ID" = 'C0C67A45-F9F6-4962-A5DC-2176F8EF1F0A';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks.Sequence

UPDATE ${mjSchema}."EntityField"
SET 
   "Category" = 'Task Details',
   "GeneratedFormSection" = 'Category'
WHERE 
   "ID" = 'C1D1EB47-D5AF-42B7-926E-38440E14B0B0';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks.BlockedReason

UPDATE ${mjSchema}."EntityField"
SET 
   "Category" = 'Task Status and Workflow',
   "GeneratedFormSection" = 'Category'
WHERE 
   "ID" = '3365149D-DB81-4D9D-BB29-2D491C6E86FA';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks.CompletionNotes

UPDATE ${mjSchema}."EntityField"
SET 
   "Category" = 'Task Details',
   "GeneratedFormSection" = 'Category'
WHERE 
   "ID" = '61B50EAD-8C53-4C9F-96AA-76ECDEDAE434';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks.CreatedByPersonID

UPDATE ${mjSchema}."EntityField"
SET 
   "Category" = 'Task Details',
   "GeneratedFormSection" = 'Category',
   "DisplayName" = 'Created By Person'
WHERE 
   "ID" = 'FB407166-23F9-4BB3-98FB-599F619BB218';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks.OverdueNotifiedAt

UPDATE ${mjSchema}."EntityField"
SET 
   "Category" = 'Task Timeline',
   "GeneratedFormSection" = 'Category'
WHERE 
   "ID" = '23302EB0-8C39-40D4-B309-FAF86854AEE2';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks.TaskTypeStatusID

UPDATE ${mjSchema}."EntityField"
SET 
   "Category" = 'Task Status and Workflow',
   "GeneratedFormSection" = 'Category',
   "DisplayName" = 'Task Type Status'
WHERE 
   "ID" = '84A6F1CB-4453-4651-B20F-58F0A29789C8';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks.PredictedSLABreachProbability

UPDATE ${mjSchema}."EntityField"
SET 
   "Category" = 'Task SLA and Risk',
   "GeneratedFormSection" = 'Category'
WHERE 
   "ID" = '9AAF8300-10B1-4C0C-8A05-CE90F22C22E4';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks.PredictedSLARiskBand

UPDATE ${mjSchema}."EntityField"
SET 
   "Category" = 'Task SLA and Risk',
   "GeneratedFormSection" = 'Category'
WHERE 
   "ID" = '95D95CDC-AECE-417E-A7EB-BB87A0197A3E';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks.PredictedSLAScoredAt

UPDATE ${mjSchema}."EntityField"
SET 
   "Category" = 'Task SLA and Risk',
   "GeneratedFormSection" = 'Category'
WHERE 
   "ID" = '6EBF3400-38A4-4CE7-A1E8-76DFBB328821';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks.HealthStatus

UPDATE ${mjSchema}."EntityField"
SET 
   "Category" = 'Task Status and Workflow',
   "GeneratedFormSection" = 'Category'
WHERE 
   "ID" = 'FF834CC2-1FD6-438E-BD22-82F6BEA0EAF2';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks.ConfidenceScore

UPDATE ${mjSchema}."EntityField"
SET 
   "Category" = 'Task Effort and Metrics',
   "GeneratedFormSection" = 'Category'
WHERE 
   "ID" = '6B700581-9114-4D4D-87FD-7803E6990FE6';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks.BaselineValue

UPDATE ${mjSchema}."EntityField"
SET 
   "Category" = 'Task Effort and Metrics',
   "GeneratedFormSection" = 'Category'
WHERE 
   "ID" = '2FAB02DE-F972-461E-9B21-4387520AF9B2';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks.TargetValue

UPDATE ${mjSchema}."EntityField"
SET 
   "Category" = 'Task Effort and Metrics',
   "GeneratedFormSection" = 'Category'
WHERE 
   "ID" = 'D9BDA046-A66F-4965-B964-56A2833E4000';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks.CurrentValue

UPDATE ${mjSchema}."EntityField"
SET 
   "Category" = 'Task Effort and Metrics',
   "GeneratedFormSection" = 'Category'
WHERE 
   "ID" = 'D568F0DF-CF9A-41D6-8ECE-5ED935AFFF02';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks.UnitOfMeasure

UPDATE ${mjSchema}."EntityField"
SET 
   "Category" = 'Task Effort and Metrics',
   "GeneratedFormSection" = 'Category'
WHERE 
   "ID" = 'A15515CE-2505-4A75-909B-996D159BF8B3';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks.MetricDirection

UPDATE ${mjSchema}."EntityField"
SET 
   "Category" = 'Task Effort and Metrics',
   "GeneratedFormSection" = 'Category'
WHERE 
   "ID" = '72A1ACE2-6BD6-4861-9DE0-F617873736D7';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks.RollupWeight

UPDATE ${mjSchema}."EntityField"
SET 
   "Category" = 'Task Effort and Metrics',
   "GeneratedFormSection" = 'Category'
WHERE 
   "ID" = '32734BDB-ADA6-4D79-B571-BB7A39E50808';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks.PlanningPeriod

UPDATE ${mjSchema}."EntityField"
SET 
   "Category" = 'Task Timeline',
   "GeneratedFormSection" = 'Category'
WHERE 
   "ID" = '74340CB6-2CF9-4078-B056-BCEC5AB63A3A';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks.CheckInCadence

UPDATE ${mjSchema}."EntityField"
SET 
   "Category" = 'Task Timeline',
   "GeneratedFormSection" = 'Category'
WHERE 
   "ID" = '74337FD7-6B08-4EE4-AFE9-5C97EE684B19';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks.LastCheckInAt

UPDATE ${mjSchema}."EntityField"
SET 
   "Category" = 'Task Timeline',
   "GeneratedFormSection" = 'Category'
WHERE 
   "ID" = '8CAF3BC8-B357-4B60-AD0E-76B818806CCC';

-- UPDATE Entity Field Category Info MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks.NextCheckInDueAt

UPDATE ${mjSchema}."EntityField"
SET 
   "Category" = 'Task Timeline',
   "GeneratedFormSection" = 'Category'
WHERE 
   "ID" = '8DB46A9C-8567-43D3-85E1-AF3174F6628F';

/* Update FieldCategoryInfo setting for entity */

UPDATE ${mjSchema}."EntitySetting"
                  SET "Value" = '{
  "Branch and Commit Info": {
    "description": "Source and target branches alongside head commit information",
    "icon": "fa fa-code"
  },
  "Dates and Timeline": {
    "description": "Timestamps for milestones, merges, and synchronization events",
    "icon": "fa fa-calendar-alt"
  },
  "Diff Metrics": {
    "description": "Code diff metrics including changed files, additions, and deletions",
    "icon": "fa fa-chart-bar"
  },
  "Pull Request Details": {
    "description": "Core pull request metadata, identifiers, links, and relationships",
    "icon": "fa fa-code-branch"
  },
  "Status and Workflow": {
    "description": "Lifecycle state, draft status, review decisions, and CI check statuses",
    "icon": "fa fa-tasks"
  },
  "System Metadata": {
    "description": "System-managed audit trails and sync hashes",
    "icon": "fa fa-cog"
  },
  "Task Details": {
    "description": "Core descriptive fields inherited from Tasks",
    "icon": "fa fa-info-circle",
    "inheritedFromEntityID": "B348FFA2-B1A7-4AC2-B6FD-F4E0C0697466",
    "inheritedFromEntityName": "MJ_BizApps_Tasks: Tasks"
  },
  "Task Effort and Metrics": {
    "description": "Effort tracking and metric fields inherited from Tasks",
    "icon": "fa fa-chart-bar",
    "inheritedFromEntityID": "B348FFA2-B1A7-4AC2-B6FD-F4E0C0697466",
    "inheritedFromEntityName": "MJ_BizApps_Tasks: Tasks"
  },
  "Task SLA and Risk": {
    "description": "SLA predictions and risk assessment fields inherited from Tasks",
    "icon": "fa fa-shield-alt",
    "inheritedFromEntityID": "B348FFA2-B1A7-4AC2-B6FD-F4E0C0697466",
    "inheritedFromEntityName": "MJ_BizApps_Tasks: Tasks"
  },
  "Task Status and Workflow": {
    "description": "Status, priority, and workflow fields inherited from Tasks",
    "icon": "fa fa-stream",
    "inheritedFromEntityID": "B348FFA2-B1A7-4AC2-B6FD-F4E0C0697466",
    "inheritedFromEntityName": "MJ_BizApps_Tasks: Tasks"
  },
  "Task Timeline": {
    "description": "Dates, timelines, and check-in fields inherited from Tasks",
    "icon": "fa fa-calendar-alt",
    "inheritedFromEntityID": "B348FFA2-B1A7-4AC2-B6FD-F4E0C0697466",
    "inheritedFromEntityName": "MJ_BizApps_Tasks: Tasks"
  }
}', "__mj_UpdatedAt" = NOW()
                  WHERE "EntityID" = 'A6B673F8-43BC-4875-AFF6-AC620592822E' AND "Name" = 'FieldCategoryInfo';

/* Update FieldCategoryIcons setting (legacy) */

UPDATE ${mjSchema}."EntitySetting"
                  SET "Value" = '{
  "Branch and Commit Info": "fa fa-code",
  "Dates and Timeline": "fa fa-calendar-alt",
  "Diff Metrics": "fa fa-chart-bar",
  "Pull Request Details": "fa fa-code-branch",
  "Status and Workflow": "fa fa-tasks",
  "System Metadata": "fa fa-cog",
  "Task Details": "fa fa-info-circle",
  "Task Effort and Metrics": "fa fa-chart-bar",
  "Task SLA and Risk": "fa fa-shield-alt",
  "Task Status and Workflow": "fa fa-stream",
  "Task Timeline": "fa fa-calendar-alt"
}', "__mj_UpdatedAt" = NOW()
                  WHERE "EntityID" = 'A6B673F8-43BC-4875-AFF6-AC620592822E' AND "Name" = 'FieldCategoryIcons';


-- ===================== Grants =====================

DO $$ BEGIN GRANT SELECT ON __mj_BizAppsTasksGitHub."vwGitHubIdentities" TO "cdp_UI", "cdp_Developer", "cdp_Integration"; EXCEPTION WHEN others THEN NULL; END $$;
/* Base View Permissions SQL for MJ_BizApps_Tasks_GitHub: Git Hub Identities */
-----------------------------------------------------------------
-- SQL Code Generation
-- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Identities
-- Item: Permissions for vwGitHubIdentities
--
-- This was generated by the MemberJunction CodeGen tool.
-- This file should NOT be edited by hand.
-----------------------------------------------------------------;

DO $$ BEGIN GRANT SELECT ON __mj_BizAppsTasksGitHub."vwGitHubIdentities" TO "cdp_UI", "cdp_Developer", "cdp_Integration"; EXCEPTION WHEN others THEN NULL; END $$;
/* spCreate SQL for MJ_BizApps_Tasks_GitHub: Git Hub Identities */
-----------------------------------------------------------------
-- SQL Code Generation
-- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Identities
-- Item: spCreateGitHubIdentity
--
-- This was generated by the MemberJunction CodeGen tool.
-- This file should NOT be edited by hand.
-----------------------------------------------------------------

------------------------------------------------------------
----- CREATE PROCEDURE FOR GitHubIdentity
------------------------------------------------------------;

DO $$ BEGIN GRANT EXECUTE ON FUNCTION __mj_BizAppsTasksGitHub."spCreateGitHubIdentity" TO "cdp_Developer", "cdp_Integration"; EXCEPTION WHEN others THEN NULL; END $$;
/* spCreate Permissions for MJ_BizApps_Tasks_GitHub: Git Hub Identities */

DO $$ BEGIN GRANT EXECUTE ON FUNCTION __mj_BizAppsTasksGitHub."spCreateGitHubIdentity" TO "cdp_Developer", "cdp_Integration"; EXCEPTION WHEN others THEN NULL; END $$;
/* spUpdate SQL for MJ_BizApps_Tasks_GitHub: Git Hub Identities */
-----------------------------------------------------------------
-- SQL Code Generation
-- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Identities
-- Item: spUpdateGitHubIdentity
--
-- This was generated by the MemberJunction CodeGen tool.
-- This file should NOT be edited by hand.
-----------------------------------------------------------------

------------------------------------------------------------
----- UPDATE PROCEDURE FOR GitHubIdentity
------------------------------------------------------------;

DO $$ BEGIN GRANT EXECUTE ON FUNCTION __mj_BizAppsTasksGitHub."spUpdateGitHubIdentity" TO "cdp_Developer", "cdp_Integration"; EXCEPTION WHEN others THEN NULL; END $$;
DO $$ BEGIN GRANT EXECUTE ON FUNCTION __mj_BizAppsTasksGitHub."spUpdateGitHubIdentity" TO "cdp_Developer", "cdp_Integration"; EXCEPTION WHEN others THEN NULL; END $$;
/* spDelete SQL for MJ_BizApps_Tasks_GitHub: Git Hub Identities */
-----------------------------------------------------------------
-- SQL Code Generation
-- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Identities
-- Item: spDeleteGitHubIdentity
--
-- This was generated by the MemberJunction CodeGen tool.
-- This file should NOT be edited by hand.
-----------------------------------------------------------------

------------------------------------------------------------
----- DELETE PROCEDURE FOR GitHubIdentity
------------------------------------------------------------;

DO $$ BEGIN GRANT EXECUTE ON FUNCTION __mj_BizAppsTasksGitHub."spDeleteGitHubIdentity" TO "cdp_Developer", "cdp_Integration"; EXCEPTION WHEN others THEN NULL; END $$;
/* spDelete Permissions for MJ_BizApps_Tasks_GitHub: Git Hub Identities */

DO $$ BEGIN GRANT EXECUTE ON FUNCTION __mj_BizAppsTasksGitHub."spDeleteGitHubIdentity" TO "cdp_Developer", "cdp_Integration"; EXCEPTION WHEN others THEN NULL; END $$;
/* SQL text to update entity field related entity name field map for entity field ID AF64DC8D-5285-46A8-A44B-145BDA229838 */

DO $$ BEGIN GRANT SELECT ON __mj_BizAppsTasksGitHub."vwGitHubIssueTasks" TO "cdp_UI", "cdp_Developer", "cdp_Integration"; EXCEPTION WHEN others THEN NULL; END $$;
/* Base View Permissions SQL for MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks */
-----------------------------------------------------------------
-- SQL Code Generation
-- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks
-- Item: Permissions for vwGitHubIssueTasks
--
-- This was generated by the MemberJunction CodeGen tool.
-- This file should NOT be edited by hand.
-----------------------------------------------------------------;

DO $$ BEGIN GRANT SELECT ON __mj_BizAppsTasksGitHub."vwGitHubIssueTasks" TO "cdp_UI", "cdp_Developer", "cdp_Integration"; EXCEPTION WHEN others THEN NULL; END $$;
/* spCreate SQL for MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks */
-----------------------------------------------------------------
-- SQL Code Generation
-- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks
-- Item: spCreateGitHubIssueTask
--
-- This was generated by the MemberJunction CodeGen tool.
-- This file should NOT be edited by hand.
-----------------------------------------------------------------

------------------------------------------------------------
----- CREATE PROCEDURE FOR GitHubIssueTask
------------------------------------------------------------;

DO $$ BEGIN GRANT EXECUTE ON FUNCTION __mj_BizAppsTasksGitHub."spCreateGitHubIssueTask" TO "cdp_Developer", "cdp_Integration"; EXCEPTION WHEN others THEN NULL; END $$;
/* spCreate Permissions for MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks */

DO $$ BEGIN GRANT EXECUTE ON FUNCTION __mj_BizAppsTasksGitHub."spCreateGitHubIssueTask" TO "cdp_Developer", "cdp_Integration"; EXCEPTION WHEN others THEN NULL; END $$;
/* spUpdate SQL for MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks */
-----------------------------------------------------------------
-- SQL Code Generation
-- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks
-- Item: spUpdateGitHubIssueTask
--
-- This was generated by the MemberJunction CodeGen tool.
-- This file should NOT be edited by hand.
-----------------------------------------------------------------

------------------------------------------------------------
----- UPDATE PROCEDURE FOR GitHubIssueTask
------------------------------------------------------------;

DO $$ BEGIN GRANT EXECUTE ON FUNCTION __mj_BizAppsTasksGitHub."spUpdateGitHubIssueTask" TO "cdp_Developer", "cdp_Integration"; EXCEPTION WHEN others THEN NULL; END $$;
DO $$ BEGIN GRANT EXECUTE ON FUNCTION __mj_BizAppsTasksGitHub."spUpdateGitHubIssueTask" TO "cdp_Developer", "cdp_Integration"; EXCEPTION WHEN others THEN NULL; END $$;
/* spDelete SQL for MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks */
-----------------------------------------------------------------
-- SQL Code Generation
-- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks
-- Item: spDeleteGitHubIssueTask
--
-- This was generated by the MemberJunction CodeGen tool.
-- This file should NOT be edited by hand.
-----------------------------------------------------------------

------------------------------------------------------------
----- DELETE PROCEDURE FOR GitHubIssueTask
------------------------------------------------------------;

DO $$ BEGIN GRANT EXECUTE ON FUNCTION __mj_BizAppsTasksGitHub."spDeleteGitHubIssueTask" TO "cdp_Developer", "cdp_Integration"; EXCEPTION WHEN others THEN NULL; END $$;
/* spDelete Permissions for MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks */

DO $$ BEGIN GRANT EXECUTE ON FUNCTION __mj_BizAppsTasksGitHub."spDeleteGitHubIssueTask" TO "cdp_Developer", "cdp_Integration"; EXCEPTION WHEN others THEN NULL; END $$;
/* Base View SQL for MJ_BizApps_Tasks_GitHub: Git Hub Repositories */
-----------------------------------------------------------------
-- SQL Code Generation
-- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Repositories
-- Item: vwGitHubRepositories
--
-- This was generated by the MemberJunction CodeGen tool.
-- This file should NOT be edited by hand.
-----------------------------------------------------------------

------------------------------------------------------------
----- BASE VIEW FOR ENTITY:      MJ_BizApps_Tasks_GitHub: Git Hub Repositories
-----               SCHEMA:      __mj_BizAppsTasksGitHub
-----               BASE TABLE:  GitHubRepository
-----               PRIMARY KEY: ID
------------------------------------------------------------;

DO $$ BEGIN GRANT SELECT ON __mj_BizAppsTasksGitHub."vwGitHubRepositories" TO "cdp_UI", "cdp_Developer", "cdp_Integration"; EXCEPTION WHEN others THEN NULL; END $$;
/* Base View Permissions SQL for MJ_BizApps_Tasks_GitHub: Git Hub Repositories */
-----------------------------------------------------------------
-- SQL Code Generation
-- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Repositories
-- Item: Permissions for vwGitHubRepositories
--
-- This was generated by the MemberJunction CodeGen tool.
-- This file should NOT be edited by hand.
-----------------------------------------------------------------;

DO $$ BEGIN GRANT SELECT ON __mj_BizAppsTasksGitHub."vwGitHubRepositories" TO "cdp_UI", "cdp_Developer", "cdp_Integration"; EXCEPTION WHEN others THEN NULL; END $$;
/* spCreate SQL for MJ_BizApps_Tasks_GitHub: Git Hub Repositories */
-----------------------------------------------------------------
-- SQL Code Generation
-- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Repositories
-- Item: spCreateGitHubRepository
--
-- This was generated by the MemberJunction CodeGen tool.
-- This file should NOT be edited by hand.
-----------------------------------------------------------------

------------------------------------------------------------
----- CREATE PROCEDURE FOR GitHubRepository
------------------------------------------------------------;

DO $$ BEGIN GRANT EXECUTE ON FUNCTION __mj_BizAppsTasksGitHub."spCreateGitHubRepository" TO "cdp_Developer", "cdp_Integration"; EXCEPTION WHEN others THEN NULL; END $$;
/* spCreate Permissions for MJ_BizApps_Tasks_GitHub: Git Hub Repositories */

DO $$ BEGIN GRANT EXECUTE ON FUNCTION __mj_BizAppsTasksGitHub."spCreateGitHubRepository" TO "cdp_Developer", "cdp_Integration"; EXCEPTION WHEN others THEN NULL; END $$;
/* spUpdate SQL for MJ_BizApps_Tasks_GitHub: Git Hub Repositories */
-----------------------------------------------------------------
-- SQL Code Generation
-- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Repositories
-- Item: spUpdateGitHubRepository
--
-- This was generated by the MemberJunction CodeGen tool.
-- This file should NOT be edited by hand.
-----------------------------------------------------------------

------------------------------------------------------------
----- UPDATE PROCEDURE FOR GitHubRepository
------------------------------------------------------------;

DO $$ BEGIN GRANT EXECUTE ON FUNCTION __mj_BizAppsTasksGitHub."spUpdateGitHubRepository" TO "cdp_Developer", "cdp_Integration"; EXCEPTION WHEN others THEN NULL; END $$;
DO $$ BEGIN GRANT EXECUTE ON FUNCTION __mj_BizAppsTasksGitHub."spUpdateGitHubRepository" TO "cdp_Developer", "cdp_Integration"; EXCEPTION WHEN others THEN NULL; END $$;
/* spDelete SQL for MJ_BizApps_Tasks_GitHub: Git Hub Repositories */
-----------------------------------------------------------------
-- SQL Code Generation
-- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Repositories
-- Item: spDeleteGitHubRepository
--
-- This was generated by the MemberJunction CodeGen tool.
-- This file should NOT be edited by hand.
-----------------------------------------------------------------

------------------------------------------------------------
----- DELETE PROCEDURE FOR GitHubRepository
------------------------------------------------------------;

DO $$ BEGIN GRANT EXECUTE ON FUNCTION __mj_BizAppsTasksGitHub."spDeleteGitHubRepository" TO "cdp_Developer", "cdp_Integration"; EXCEPTION WHEN others THEN NULL; END $$;
/* spDelete Permissions for MJ_BizApps_Tasks_GitHub: Git Hub Repositories */

DO $$ BEGIN GRANT EXECUTE ON FUNCTION __mj_BizAppsTasksGitHub."spDeleteGitHubRepository" TO "cdp_Developer", "cdp_Integration"; EXCEPTION WHEN others THEN NULL; END $$;
/* Base View SQL for MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks */
-----------------------------------------------------------------
-- SQL Code Generation
-- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks
-- Item: vwGitHubPullRequestTasks
--
-- This was generated by the MemberJunction CodeGen tool.
-- This file should NOT be edited by hand.
-----------------------------------------------------------------

------------------------------------------------------------
----- BASE VIEW FOR ENTITY:      MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks
-----               SCHEMA:      __mj_BizAppsTasksGitHub
-----               BASE TABLE:  GitHubPullRequestTask
-----               PRIMARY KEY: ID
------------------------------------------------------------;

DO $$ BEGIN GRANT SELECT ON __mj_BizAppsTasksGitHub."vwGitHubPullRequestTasks" TO "cdp_UI", "cdp_Developer", "cdp_Integration"; EXCEPTION WHEN others THEN NULL; END $$;
/* Base View Permissions SQL for MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks */
-----------------------------------------------------------------
-- SQL Code Generation
-- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks
-- Item: Permissions for vwGitHubPullRequestTasks
--
-- This was generated by the MemberJunction CodeGen tool.
-- This file should NOT be edited by hand.
-----------------------------------------------------------------;

DO $$ BEGIN GRANT SELECT ON __mj_BizAppsTasksGitHub."vwGitHubPullRequestTasks" TO "cdp_UI", "cdp_Developer", "cdp_Integration"; EXCEPTION WHEN others THEN NULL; END $$;
/* spCreate SQL for MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks */
-----------------------------------------------------------------
-- SQL Code Generation
-- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks
-- Item: spCreateGitHubPullRequestTask
--
-- This was generated by the MemberJunction CodeGen tool.
-- This file should NOT be edited by hand.
-----------------------------------------------------------------

------------------------------------------------------------
----- CREATE PROCEDURE FOR GitHubPullRequestTask
------------------------------------------------------------;

DO $$ BEGIN GRANT EXECUTE ON FUNCTION __mj_BizAppsTasksGitHub."spCreateGitHubPullRequestTask" TO "cdp_Developer", "cdp_Integration"; EXCEPTION WHEN others THEN NULL; END $$;
/* spCreate Permissions for MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks */

DO $$ BEGIN GRANT EXECUTE ON FUNCTION __mj_BizAppsTasksGitHub."spCreateGitHubPullRequestTask" TO "cdp_Developer", "cdp_Integration"; EXCEPTION WHEN others THEN NULL; END $$;
/* spUpdate SQL for MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks */
-----------------------------------------------------------------
-- SQL Code Generation
-- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks
-- Item: spUpdateGitHubPullRequestTask
--
-- This was generated by the MemberJunction CodeGen tool.
-- This file should NOT be edited by hand.
-----------------------------------------------------------------

------------------------------------------------------------
----- UPDATE PROCEDURE FOR GitHubPullRequestTask
------------------------------------------------------------;

DO $$ BEGIN GRANT EXECUTE ON FUNCTION __mj_BizAppsTasksGitHub."spUpdateGitHubPullRequestTask" TO "cdp_Developer", "cdp_Integration"; EXCEPTION WHEN others THEN NULL; END $$;
DO $$ BEGIN GRANT EXECUTE ON FUNCTION __mj_BizAppsTasksGitHub."spUpdateGitHubPullRequestTask" TO "cdp_Developer", "cdp_Integration"; EXCEPTION WHEN others THEN NULL; END $$;
/* spDelete SQL for MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks */
-----------------------------------------------------------------
-- SQL Code Generation
-- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks
-- Item: spDeleteGitHubPullRequestTask
--
-- This was generated by the MemberJunction CodeGen tool.
-- This file should NOT be edited by hand.
-----------------------------------------------------------------

------------------------------------------------------------
----- DELETE PROCEDURE FOR GitHubPullRequestTask
------------------------------------------------------------;

DO $$ BEGIN GRANT EXECUTE ON FUNCTION __mj_BizAppsTasksGitHub."spDeleteGitHubPullRequestTask" TO "cdp_Developer", "cdp_Integration"; EXCEPTION WHEN others THEN NULL; END $$;
/* spDelete Permissions for MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks */

DO $$ BEGIN GRANT EXECUTE ON FUNCTION __mj_BizAppsTasksGitHub."spDeleteGitHubPullRequestTask" TO "cdp_Developer", "cdp_Integration"; EXCEPTION WHEN others THEN NULL; END $$;
/* SQL text to insert 5 new entity field(s) */

DO $$ BEGIN REVOKE SELECT ON __mj_BizAppsTasksGitHub."vwGitHubPullRequestTasks" FROM "cdp_Developer"; EXCEPTION WHEN others THEN NULL; END $$;
DO $$ BEGIN REVOKE SELECT ON __mj_BizAppsTasksGitHub."vwGitHubPullRequestTasks" FROM "cdp_Integration"; EXCEPTION WHEN others THEN NULL; END $$;
DO $$ BEGIN REVOKE SELECT ON __mj_BizAppsTasksGitHub."vwGitHubPullRequestTasks" FROM "cdp_UI"; EXCEPTION WHEN others THEN NULL; END $$;
DO $$ BEGIN GRANT SELECT ON __mj_BizAppsTasksGitHub."vwGitHubPullRequestTasks" TO "cdp_UI", "cdp_Developer", "cdp_Integration"; EXCEPTION WHEN others THEN NULL; END $$;
/* Base View Permissions SQL for MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks */
-----------------------------------------------------------------
-- SQL Code Generation
-- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks
-- Item: Permissions for vwGitHubPullRequestTasks
--
-- This was generated by the MemberJunction CodeGen tool.
-- This file should NOT be edited by hand.
-----------------------------------------------------------------;

DO $$ BEGIN REVOKE SELECT ON __mj_BizAppsTasksGitHub."vwGitHubPullRequestTasks" FROM "cdp_Developer"; EXCEPTION WHEN others THEN NULL; END $$;
DO $$ BEGIN REVOKE SELECT ON __mj_BizAppsTasksGitHub."vwGitHubPullRequestTasks" FROM "cdp_Integration"; EXCEPTION WHEN others THEN NULL; END $$;
DO $$ BEGIN REVOKE SELECT ON __mj_BizAppsTasksGitHub."vwGitHubPullRequestTasks" FROM "cdp_UI"; EXCEPTION WHEN others THEN NULL; END $$;
DO $$ BEGIN GRANT SELECT ON __mj_BizAppsTasksGitHub."vwGitHubPullRequestTasks" TO "cdp_UI", "cdp_Developer", "cdp_Integration"; EXCEPTION WHEN others THEN NULL; END $$;
/* spCreate SQL for MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks */
-----------------------------------------------------------------
-- SQL Code Generation
-- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks
-- Item: spCreateGitHubPullRequestTask
--
-- This was generated by the MemberJunction CodeGen tool.
-- This file should NOT be edited by hand.
-----------------------------------------------------------------

------------------------------------------------------------
----- CREATE PROCEDURE FOR GitHubPullRequestTask
------------------------------------------------------------;

DO $$ BEGIN REVOKE EXECUTE ON FUNCTION __mj_BizAppsTasksGitHub."spCreateGitHubPullRequestTask" FROM "cdp_Developer"; EXCEPTION WHEN others THEN NULL; END $$;
DO $$ BEGIN REVOKE EXECUTE ON FUNCTION __mj_BizAppsTasksGitHub."spCreateGitHubPullRequestTask" FROM "cdp_Integration"; EXCEPTION WHEN others THEN NULL; END $$;
DO $$ BEGIN GRANT EXECUTE ON FUNCTION __mj_BizAppsTasksGitHub."spCreateGitHubPullRequestTask" TO "cdp_Developer", "cdp_Integration"; EXCEPTION WHEN others THEN NULL; END $$;
/* spCreate Permissions for MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks */

DO $$ BEGIN REVOKE EXECUTE ON FUNCTION __mj_BizAppsTasksGitHub."spCreateGitHubPullRequestTask" FROM "cdp_Developer"; EXCEPTION WHEN others THEN NULL; END $$;
DO $$ BEGIN REVOKE EXECUTE ON FUNCTION __mj_BizAppsTasksGitHub."spCreateGitHubPullRequestTask" FROM "cdp_Integration"; EXCEPTION WHEN others THEN NULL; END $$;
DO $$ BEGIN GRANT EXECUTE ON FUNCTION __mj_BizAppsTasksGitHub."spCreateGitHubPullRequestTask" TO "cdp_Developer", "cdp_Integration"; EXCEPTION WHEN others THEN NULL; END $$;
/* spUpdate SQL for MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks */
-----------------------------------------------------------------
-- SQL Code Generation
-- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks
-- Item: spUpdateGitHubPullRequestTask
--
-- This was generated by the MemberJunction CodeGen tool.
-- This file should NOT be edited by hand.
-----------------------------------------------------------------

------------------------------------------------------------
----- UPDATE PROCEDURE FOR GitHubPullRequestTask
------------------------------------------------------------;

DO $$ BEGIN REVOKE EXECUTE ON FUNCTION __mj_BizAppsTasksGitHub."spUpdateGitHubPullRequestTask" FROM "cdp_Developer"; EXCEPTION WHEN others THEN NULL; END $$;
DO $$ BEGIN REVOKE EXECUTE ON FUNCTION __mj_BizAppsTasksGitHub."spUpdateGitHubPullRequestTask" FROM "cdp_Integration"; EXCEPTION WHEN others THEN NULL; END $$;
DO $$ BEGIN GRANT EXECUTE ON FUNCTION __mj_BizAppsTasksGitHub."spUpdateGitHubPullRequestTask" TO "cdp_Developer", "cdp_Integration"; EXCEPTION WHEN others THEN NULL; END $$;
DO $$ BEGIN REVOKE EXECUTE ON FUNCTION __mj_BizAppsTasksGitHub."spUpdateGitHubPullRequestTask" FROM "cdp_Developer"; EXCEPTION WHEN others THEN NULL; END $$;
DO $$ BEGIN REVOKE EXECUTE ON FUNCTION __mj_BizAppsTasksGitHub."spUpdateGitHubPullRequestTask" FROM "cdp_Integration"; EXCEPTION WHEN others THEN NULL; END $$;
DO $$ BEGIN GRANT EXECUTE ON FUNCTION __mj_BizAppsTasksGitHub."spUpdateGitHubPullRequestTask" TO "cdp_Developer", "cdp_Integration"; EXCEPTION WHEN others THEN NULL; END $$;
/* spDelete SQL for MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks */
-----------------------------------------------------------------
-- SQL Code Generation
-- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks
-- Item: spDeleteGitHubPullRequestTask
--
-- This was generated by the MemberJunction CodeGen tool.
-- This file should NOT be edited by hand.
-----------------------------------------------------------------

------------------------------------------------------------
----- DELETE PROCEDURE FOR GitHubPullRequestTask
------------------------------------------------------------;

DO $$ BEGIN REVOKE EXECUTE ON FUNCTION __mj_BizAppsTasksGitHub."spDeleteGitHubPullRequestTask" FROM "cdp_Developer"; EXCEPTION WHEN others THEN NULL; END $$;
DO $$ BEGIN REVOKE EXECUTE ON FUNCTION __mj_BizAppsTasksGitHub."spDeleteGitHubPullRequestTask" FROM "cdp_Integration"; EXCEPTION WHEN others THEN NULL; END $$;
DO $$ BEGIN GRANT EXECUTE ON FUNCTION __mj_BizAppsTasksGitHub."spDeleteGitHubPullRequestTask" TO "cdp_Developer", "cdp_Integration"; EXCEPTION WHEN others THEN NULL; END $$;
/* spDelete Permissions for MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks */

DO $$ BEGIN REVOKE EXECUTE ON FUNCTION __mj_BizAppsTasksGitHub."spDeleteGitHubPullRequestTask" FROM "cdp_Developer"; EXCEPTION WHEN others THEN NULL; END $$;
DO $$ BEGIN REVOKE EXECUTE ON FUNCTION __mj_BizAppsTasksGitHub."spDeleteGitHubPullRequestTask" FROM "cdp_Integration"; EXCEPTION WHEN others THEN NULL; END $$;
DO $$ BEGIN GRANT EXECUTE ON FUNCTION __mj_BizAppsTasksGitHub."spDeleteGitHubPullRequestTask" TO "cdp_Developer", "cdp_Integration"; EXCEPTION WHEN others THEN NULL; END $$;
/* Base View SQL for MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks */
-----------------------------------------------------------------
-- SQL Code Generation
-- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks
-- Item: vwGitHubIssueTasks
--
-- This was generated by the MemberJunction CodeGen tool.
-- This file should NOT be edited by hand.
-----------------------------------------------------------------

------------------------------------------------------------
----- BASE VIEW FOR ENTITY:      MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks
-----               SCHEMA:      __mj_BizAppsTasksGitHub
-----               BASE TABLE:  GitHubIssueTask
-----               PRIMARY KEY: ID
------------------------------------------------------------;

DO $$ BEGIN REVOKE SELECT ON __mj_BizAppsTasksGitHub."vwGitHubIssueTasks" FROM "cdp_Developer"; EXCEPTION WHEN others THEN NULL; END $$;
DO $$ BEGIN REVOKE SELECT ON __mj_BizAppsTasksGitHub."vwGitHubIssueTasks" FROM "cdp_Integration"; EXCEPTION WHEN others THEN NULL; END $$;
DO $$ BEGIN REVOKE SELECT ON __mj_BizAppsTasksGitHub."vwGitHubIssueTasks" FROM "cdp_UI"; EXCEPTION WHEN others THEN NULL; END $$;
DO $$ BEGIN GRANT SELECT ON __mj_BizAppsTasksGitHub."vwGitHubIssueTasks" TO "cdp_UI", "cdp_Developer", "cdp_Integration"; EXCEPTION WHEN others THEN NULL; END $$;
/* Base View Permissions SQL for MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks */
-----------------------------------------------------------------
-- SQL Code Generation
-- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks
-- Item: Permissions for vwGitHubIssueTasks
--
-- This was generated by the MemberJunction CodeGen tool.
-- This file should NOT be edited by hand.
-----------------------------------------------------------------;

DO $$ BEGIN REVOKE SELECT ON __mj_BizAppsTasksGitHub."vwGitHubIssueTasks" FROM "cdp_Developer"; EXCEPTION WHEN others THEN NULL; END $$;
DO $$ BEGIN REVOKE SELECT ON __mj_BizAppsTasksGitHub."vwGitHubIssueTasks" FROM "cdp_Integration"; EXCEPTION WHEN others THEN NULL; END $$;
DO $$ BEGIN REVOKE SELECT ON __mj_BizAppsTasksGitHub."vwGitHubIssueTasks" FROM "cdp_UI"; EXCEPTION WHEN others THEN NULL; END $$;
DO $$ BEGIN GRANT SELECT ON __mj_BizAppsTasksGitHub."vwGitHubIssueTasks" TO "cdp_UI", "cdp_Developer", "cdp_Integration"; EXCEPTION WHEN others THEN NULL; END $$;
/* spCreate SQL for MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks */
-----------------------------------------------------------------
-- SQL Code Generation
-- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks
-- Item: spCreateGitHubIssueTask
--
-- This was generated by the MemberJunction CodeGen tool.
-- This file should NOT be edited by hand.
-----------------------------------------------------------------

------------------------------------------------------------
----- CREATE PROCEDURE FOR GitHubIssueTask
------------------------------------------------------------;

DO $$ BEGIN REVOKE EXECUTE ON FUNCTION __mj_BizAppsTasksGitHub."spCreateGitHubIssueTask" FROM "cdp_Developer"; EXCEPTION WHEN others THEN NULL; END $$;
DO $$ BEGIN REVOKE EXECUTE ON FUNCTION __mj_BizAppsTasksGitHub."spCreateGitHubIssueTask" FROM "cdp_Integration"; EXCEPTION WHEN others THEN NULL; END $$;
DO $$ BEGIN GRANT EXECUTE ON FUNCTION __mj_BizAppsTasksGitHub."spCreateGitHubIssueTask" TO "cdp_Developer", "cdp_Integration"; EXCEPTION WHEN others THEN NULL; END $$;
/* spCreate Permissions for MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks */

DO $$ BEGIN REVOKE EXECUTE ON FUNCTION __mj_BizAppsTasksGitHub."spCreateGitHubIssueTask" FROM "cdp_Developer"; EXCEPTION WHEN others THEN NULL; END $$;
DO $$ BEGIN REVOKE EXECUTE ON FUNCTION __mj_BizAppsTasksGitHub."spCreateGitHubIssueTask" FROM "cdp_Integration"; EXCEPTION WHEN others THEN NULL; END $$;
DO $$ BEGIN GRANT EXECUTE ON FUNCTION __mj_BizAppsTasksGitHub."spCreateGitHubIssueTask" TO "cdp_Developer", "cdp_Integration"; EXCEPTION WHEN others THEN NULL; END $$;
/* spUpdate SQL for MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks */
-----------------------------------------------------------------
-- SQL Code Generation
-- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks
-- Item: spUpdateGitHubIssueTask
--
-- This was generated by the MemberJunction CodeGen tool.
-- This file should NOT be edited by hand.
-----------------------------------------------------------------

------------------------------------------------------------
----- UPDATE PROCEDURE FOR GitHubIssueTask
------------------------------------------------------------;

DO $$ BEGIN REVOKE EXECUTE ON FUNCTION __mj_BizAppsTasksGitHub."spUpdateGitHubIssueTask" FROM "cdp_Developer"; EXCEPTION WHEN others THEN NULL; END $$;
DO $$ BEGIN REVOKE EXECUTE ON FUNCTION __mj_BizAppsTasksGitHub."spUpdateGitHubIssueTask" FROM "cdp_Integration"; EXCEPTION WHEN others THEN NULL; END $$;
DO $$ BEGIN GRANT EXECUTE ON FUNCTION __mj_BizAppsTasksGitHub."spUpdateGitHubIssueTask" TO "cdp_Developer", "cdp_Integration"; EXCEPTION WHEN others THEN NULL; END $$;
DO $$ BEGIN REVOKE EXECUTE ON FUNCTION __mj_BizAppsTasksGitHub."spUpdateGitHubIssueTask" FROM "cdp_Developer"; EXCEPTION WHEN others THEN NULL; END $$;
DO $$ BEGIN REVOKE EXECUTE ON FUNCTION __mj_BizAppsTasksGitHub."spUpdateGitHubIssueTask" FROM "cdp_Integration"; EXCEPTION WHEN others THEN NULL; END $$;
DO $$ BEGIN GRANT EXECUTE ON FUNCTION __mj_BizAppsTasksGitHub."spUpdateGitHubIssueTask" TO "cdp_Developer", "cdp_Integration"; EXCEPTION WHEN others THEN NULL; END $$;
/* spDelete SQL for MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks */
-----------------------------------------------------------------
-- SQL Code Generation
-- Entity: MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks
-- Item: spDeleteGitHubIssueTask
--
-- This was generated by the MemberJunction CodeGen tool.
-- This file should NOT be edited by hand.
-----------------------------------------------------------------

------------------------------------------------------------
----- DELETE PROCEDURE FOR GitHubIssueTask
------------------------------------------------------------;

DO $$ BEGIN REVOKE EXECUTE ON FUNCTION __mj_BizAppsTasksGitHub."spDeleteGitHubIssueTask" FROM "cdp_Developer"; EXCEPTION WHEN others THEN NULL; END $$;
DO $$ BEGIN REVOKE EXECUTE ON FUNCTION __mj_BizAppsTasksGitHub."spDeleteGitHubIssueTask" FROM "cdp_Integration"; EXCEPTION WHEN others THEN NULL; END $$;
DO $$ BEGIN GRANT EXECUTE ON FUNCTION __mj_BizAppsTasksGitHub."spDeleteGitHubIssueTask" TO "cdp_Developer", "cdp_Integration"; EXCEPTION WHEN others THEN NULL; END $$;
/* spDelete Permissions for MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks */

DO $$ BEGIN REVOKE EXECUTE ON FUNCTION __mj_BizAppsTasksGitHub."spDeleteGitHubIssueTask" FROM "cdp_Developer"; EXCEPTION WHEN others THEN NULL; END $$;
DO $$ BEGIN REVOKE EXECUTE ON FUNCTION __mj_BizAppsTasksGitHub."spDeleteGitHubIssueTask" FROM "cdp_Integration"; EXCEPTION WHEN others THEN NULL; END $$;
DO $$ BEGIN GRANT EXECUTE ON FUNCTION __mj_BizAppsTasksGitHub."spDeleteGitHubIssueTask" TO "cdp_Developer", "cdp_Integration"; EXCEPTION WHEN others THEN NULL; END $$;
/* SQL text to insert 68 new entity field(s) */


-- ===================== Comments =====================

COMMENT ON TABLE __mj_BizAppsTasksGitHub."GitHubRepository" IS 'GitHub repositories connected to BizApps Tasks, storing tracking controls, import filtering rules (AssignedOnly vs All), GitHub App installation IDs, client organization link, and optional Software Factory delivery policy reference.';

COMMENT ON COLUMN __mj_BizAppsTasksGitHub."GitHubRepository"."Owner" IS 'GitHub organization or user login that owns the repository (e.g. MemberJunction).';

COMMENT ON COLUMN __mj_BizAppsTasksGitHub."GitHubRepository"."Name" IS 'Repository slug within the owner namespace (e.g. MJ, bizapps-tasks).';

COMMENT ON COLUMN __mj_BizAppsTasksGitHub."GitHubRepository"."DefaultBranch" IS 'Default target branch name on GitHub (typically main or next).';

COMMENT ON COLUMN __mj_BizAppsTasksGitHub."GitHubRepository"."IsTracked" IS 'When 1, periodic sync and incoming webhooks import eligible issues and pull requests into BizApps Tasks.';

COMMENT ON COLUMN __mj_BizAppsTasksGitHub."GitHubRepository"."ImportRule" IS 'Controls which issues and PRs become Tasks: AssignedOnly imports items assigned to or requesting review from a mapped GitHubIdentity; All imports every issue and PR in the repository.';

COMMENT ON COLUMN __mj_BizAppsTasksGitHub."GitHubRepository"."InstallationID" IS 'GitHub App installation identifier scoped to this repository or organization.';

COMMENT ON COLUMN __mj_BizAppsTasksGitHub."GitHubRepository"."OrganizationID" IS 'Optional client Organization in BizApps Common. Null denotes an internal repository; non-null enables Client-layer DeliveryPolicy inheritance.';

COMMENT ON COLUMN __mj_BizAppsTasksGitHub."GitHubRepository"."DeliveryPolicyID" IS 'Optional UUID of the repository-level DeliveryPolicy in bizapps-software-factory when installed.';

COMMENT ON TABLE __mj_BizAppsTasksGitHub."GitHubIdentity" IS 'Maps GitHub user logins to BizApps Common Person records so GitHub issue/PR assignees and requested reviewers synchronize into Primary and Reviewer TaskAssignment rows.';

COMMENT ON COLUMN __mj_BizAppsTasksGitHub."GitHubIdentity"."GitHubLogin" IS 'Case-insensitive GitHub username / handle (e.g. octocat).';

COMMENT ON COLUMN __mj_BizAppsTasksGitHub."GitHubIdentity"."PersonID" IS 'Target BizApps Common Person record associated with this GitHub login.';

COMMENT ON COLUMN __mj_BizAppsTasksGitHub."GitHubIdentity"."GitHubUserID" IS 'Optional numeric or GraphQL node identifier for the GitHub user account.';

COMMENT ON COLUMN __mj_BizAppsTasksGitHub."GitHubIdentity"."IsActive" IS 'Whether this login mapping is currently active for task import and assignment resolution.';

COMMENT ON TABLE __mj_BizAppsTasksGitHub."GitHubIssueTask" IS 'Disjoint IS-A child of MJ_BizApps_Tasks: Tasks for GITHUB_ISSUE tasks, storing GitHub-owned issue metadata, milestone dates, and idempotent external sync keys.';

COMMENT ON COLUMN __mj_BizAppsTasksGitHub."GitHubIssueTask"."ID" IS 'Shared primary key referencing __mj_BizAppsTasks.Task(ID).';

COMMENT ON COLUMN __mj_BizAppsTasksGitHub."GitHubIssueTask"."RepositoryID" IS 'GitHubRepository to which this issue belongs.';

COMMENT ON COLUMN __mj_BizAppsTasksGitHub."GitHubIssueTask"."Number" IS 'Repository-scoped GitHub issue number (#N). Unique per RepositoryID when populated.';

COMMENT ON COLUMN __mj_BizAppsTasksGitHub."GitHubIssueTask"."NodeID" IS 'Global GitHub GraphQL node identifier for idempotent cross-rename sync.';

COMMENT ON COLUMN __mj_BizAppsTasksGitHub."GitHubIssueTask"."HtmlURL" IS 'Canonical browser URL to view or edit the issue on GitHub.';

COMMENT ON COLUMN __mj_BizAppsTasksGitHub."GitHubIssueTask"."State" IS 'GitHub issue state (open or closed).';

COMMENT ON COLUMN __mj_BizAppsTasksGitHub."GitHubIssueTask"."StateReason" IS 'Optional GitHub issue state_reason (completed, not_planned, reopened, duplicate).';

COMMENT ON COLUMN __mj_BizAppsTasksGitHub."GitHubIssueTask"."Labels" IS 'JSON array of GitHub label names applied to the issue.';

COMMENT ON COLUMN __mj_BizAppsTasksGitHub."GitHubIssueTask"."Milestone" IS 'GitHub milestone title when assigned.';

COMMENT ON COLUMN __mj_BizAppsTasksGitHub."GitHubIssueTask"."MilestoneDueAt" IS 'Due timestamp of the GitHub milestone; supersedes pending inferred DueAt Field Suggestions.';

COMMENT ON COLUMN __mj_BizAppsTasksGitHub."GitHubIssueTask"."AuthorLogin" IS 'GitHub login of the user who opened the issue.';

COMMENT ON COLUMN __mj_BizAppsTasksGitHub."GitHubIssueTask"."BodyHash" IS 'SHA-256 hash of the last synced issue body used to detect text edits and trigger Field Suggestion re-inference.';

COMMENT ON COLUMN __mj_BizAppsTasksGitHub."GitHubIssueTask"."GitHubUpdatedAt" IS 'Upstream updated_at timestamp reported by GitHub.';

COMMENT ON COLUMN __mj_BizAppsTasksGitHub."GitHubIssueTask"."LastSyncedAt" IS 'Timestamp when BizApps Tasks GitHub sync last reconciled this issue.';

COMMENT ON TABLE __mj_BizAppsTasksGitHub."GitHubPullRequestTask" IS 'Disjoint IS-A child of MJ_BizApps_Tasks: Tasks for GITHUB_PR tasks, storing pull request branches, head SHA, review decision, CI checks status, diff metrics, and linked issue Task.';

COMMENT ON COLUMN __mj_BizAppsTasksGitHub."GitHubPullRequestTask"."ID" IS 'Shared primary key referencing __mj_BizAppsTasks.Task(ID).';

COMMENT ON COLUMN __mj_BizAppsTasksGitHub."GitHubPullRequestTask"."RepositoryID" IS 'GitHubRepository to which this pull request belongs.';

COMMENT ON COLUMN __mj_BizAppsTasksGitHub."GitHubPullRequestTask"."Number" IS 'Repository-scoped GitHub pull request number (#N). Unique per RepositoryID when populated.';

COMMENT ON COLUMN __mj_BizAppsTasksGitHub."GitHubPullRequestTask"."NodeID" IS 'Global GitHub GraphQL node identifier for idempotent sync.';

COMMENT ON COLUMN __mj_BizAppsTasksGitHub."GitHubPullRequestTask"."HtmlURL" IS 'Canonical browser URL to view or review the pull request on GitHub.';

COMMENT ON COLUMN __mj_BizAppsTasksGitHub."GitHubPullRequestTask"."State" IS 'Pull request lifecycle state on GitHub (open, closed, or merged).';

COMMENT ON COLUMN __mj_BizAppsTasksGitHub."GitHubPullRequestTask"."IsDraft" IS 'Whether the pull request is currently marked as a Draft on GitHub.';

COMMENT ON COLUMN __mj_BizAppsTasksGitHub."GitHubPullRequestTask"."HeadBranch" IS 'Source branch ref of the pull request (head.ref).';

COMMENT ON COLUMN __mj_BizAppsTasksGitHub."GitHubPullRequestTask"."HeadSha" IS 'Commit SHA at the tip of HeadBranch (head.sha), verified by Software Factory merge gates.';

COMMENT ON COLUMN __mj_BizAppsTasksGitHub."GitHubPullRequestTask"."BaseBranch" IS 'Target branch ref into which the pull request merges (base.ref).';

COMMENT ON COLUMN __mj_BizAppsTasksGitHub."GitHubPullRequestTask"."AuthorLogin" IS 'GitHub login of the pull request author.';

COMMENT ON COLUMN __mj_BizAppsTasksGitHub."GitHubPullRequestTask"."ReviewDecision" IS 'Aggregated GitHub review decision (APPROVED, CHANGES_REQUESTED, or REVIEW_REQUIRED).';

COMMENT ON COLUMN __mj_BizAppsTasksGitHub."GitHubPullRequestTask"."ChecksStatus" IS 'Aggregated status of required GitHub CI checks on HeadSha (Pending, Passing, Failing, Neutral).';

COMMENT ON COLUMN __mj_BizAppsTasksGitHub."GitHubPullRequestTask"."ChangedFiles" IS 'Number of files touched in the pull request diff.';

COMMENT ON COLUMN __mj_BizAppsTasksGitHub."GitHubPullRequestTask"."Additions" IS 'Lines added in the pull request diff.';

COMMENT ON COLUMN __mj_BizAppsTasksGitHub."GitHubPullRequestTask"."Deletions" IS 'Lines deleted in the pull request diff.';

COMMENT ON COLUMN __mj_BizAppsTasksGitHub."GitHubPullRequestTask"."Labels" IS 'JSON array of GitHub label names applied to the pull request.';

COMMENT ON COLUMN __mj_BizAppsTasksGitHub."GitHubPullRequestTask"."Milestone" IS 'GitHub milestone title when assigned.';

COMMENT ON COLUMN __mj_BizAppsTasksGitHub."GitHubPullRequestTask"."MilestoneDueAt" IS 'Due timestamp of the GitHub milestone; supersedes pending inferred DueAt Field Suggestions.';

COMMENT ON COLUMN __mj_BizAppsTasksGitHub."GitHubPullRequestTask"."MergedAt" IS 'Timestamp when the pull request was merged on GitHub.';

COMMENT ON COLUMN __mj_BizAppsTasksGitHub."GitHubPullRequestTask"."LinkedIssueTaskID" IS 'Optional reference to the Task (e.g. GITHUB_ISSUE or FACTORY_WORK) that this pull request implements or closes.';

COMMENT ON COLUMN __mj_BizAppsTasksGitHub."GitHubPullRequestTask"."BodyHash" IS 'SHA-256 hash of the last synced pull request body used to detect text edits and trigger Field Suggestion re-inference.';

COMMENT ON COLUMN __mj_BizAppsTasksGitHub."GitHubPullRequestTask"."GitHubUpdatedAt" IS 'Upstream updated_at timestamp reported by GitHub.';

COMMENT ON COLUMN __mj_BizAppsTasksGitHub."GitHubPullRequestTask"."LastSyncedAt" IS 'Timestamp when BizApps Tasks GitHub sync last reconciled this pull request.';


-- ===================== Other =====================

-- =============================================================================
-- GENERATED BY MemberJunction CodeGen — DO NOT EDIT BY HAND
-- =============================================================================

/* SQL generated to create new entity MJ_BizApps_Tasks_GitHub: Git Hub Repositories */

/* SQL text to insert 60 new entity field(s) */

/* spUpdate Permissions for MJ_BizApps_Tasks_GitHub: Git Hub Identities */

/* spUpdate Permissions for MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks */

/* spUpdate Permissions for MJ_BizApps_Tasks_GitHub: Git Hub Repositories */

/* spUpdate Permissions for MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks */

/* spUpdate Permissions for MJ_BizApps_Tasks_GitHub: Git Hub Pull Request Tasks */

/* spUpdate Permissions for MJ_BizApps_Tasks_GitHub: Git Hub Issue Tasks */
