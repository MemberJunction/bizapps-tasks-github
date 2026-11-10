-- PostgreSQL teardown for BizApps Tasks GitHub Extension (executed by `mj app remove`).
-- Retires runtime & metadata rows written into shared schemas (__mj and __mj_bizappstasks)
-- in full foreign-key dependency order before __mj_bizappstasksgithub is dropped.

-- 1. Retire "GitHub Tasks & Pull Requests" skill and grants
UPDATE ${mjSchema}."SearchExecutionLog"
   SET "AISkillID" = NULL
 WHERE "AISkillID" IN (SELECT "ID" FROM ${mjSchema}."AISkill" WHERE "Name" = 'GitHub Tasks & Pull Requests');

DELETE FROM ${mjSchema}."ConversationSkill"
 WHERE "SkillID" IN (SELECT "ID" FROM ${mjSchema}."AISkill" WHERE "Name" = 'GitHub Tasks & Pull Requests');

DELETE FROM ${mjSchema}."AISkillPermission"
 WHERE "SkillID" IN (SELECT "ID" FROM ${mjSchema}."AISkill" WHERE "Name" = 'GitHub Tasks & Pull Requests');

DELETE FROM ${mjSchema}."AISkillSearchScope"
 WHERE "SkillID" IN (SELECT "ID" FROM ${mjSchema}."AISkill" WHERE "Name" = 'GitHub Tasks & Pull Requests');

DELETE FROM ${mjSchema}."AISkillSubAgent"
 WHERE "SkillID" IN (SELECT "ID" FROM ${mjSchema}."AISkill" WHERE "Name" = 'GitHub Tasks & Pull Requests');

DELETE FROM ${mjSchema}."AISkillAction"
 WHERE "SkillID" IN (SELECT "ID" FROM ${mjSchema}."AISkill" WHERE "Name" = 'GitHub Tasks & Pull Requests');

DELETE FROM ${mjSchema}."AIAgentSkill"
 WHERE "SkillID" IN (SELECT "ID" FROM ${mjSchema}."AISkill" WHERE "Name" = 'GitHub Tasks & Pull Requests');

DELETE FROM ${mjSchema}."AISkill"
 WHERE "Name" = 'GitHub Tasks & Pull Requests';

-- 2. Retire Field Suggestions (IS-A Comment -> Conversation) created by the GitHub inference prompt or linked to GITHUB_* Tasks
CREATE TEMP TABLE IF NOT EXISTS _github_field_suggestion_ids AS
SELECT DISTINCT fs."ID"
  FROM ${mjSchema}."FieldSuggestion" fs
  LEFT JOIN ${mjSchema}."Comment" cm ON cm."ID" = fs."ID"
  LEFT JOIN ${mjSchema}."Conversation" conv ON conv."ID" = cm."ID"
 WHERE fs."AIPromptRunID" IN (
           SELECT pr."ID"
             FROM ${mjSchema}."AIPromptRun" pr
             INNER JOIN ${mjSchema}."AIPrompt" p ON p."ID" = pr."PromptID"
            WHERE p."Name" = 'GitHub Task Planning Field Inference'
       )
    OR (
           conv."LinkedEntityID" IN (SELECT "ID" FROM ${mjSchema}."Entity" WHERE "Name" = 'MJ_BizApps_Tasks: Tasks')
       AND LOWER(conv."LinkedRecordID") IN (
               SELECT LOWER(t."ID"::text)
                 FROM __mj_bizappstasks."Task" t
                 INNER JOIN __mj_bizappstasks."TaskType" tt ON tt."ID" = t."TypeID"
                WHERE tt."Code" IN ('GITHUB_ISSUE', 'GITHUB_PR')
           )
       );

CREATE TEMP TABLE IF NOT EXISTS _github_conversation_detail_ids AS
SELECT "ID"
  FROM ${mjSchema}."ConversationDetail"
 WHERE "ConversationID" IN (SELECT "ID" FROM _github_field_suggestion_ids);

DELETE FROM ${mjSchema}."FieldSuggestion"
 WHERE "ID" IN (SELECT "ID" FROM _github_field_suggestion_ids);

UPDATE ${mjSchema}."Conversation"
   SET "LastConversationID" = NULL
 WHERE "LastConversationID" IN (SELECT "ID" FROM _github_field_suggestion_ids);

UPDATE ${mjSchema}."AIAgentRun"
   SET "ConversationDetailID" = NULL
 WHERE "ConversationDetailID" IN (SELECT "ID" FROM _github_conversation_detail_ids);

UPDATE ${mjSchema}."AIAgentRun"
   SET "ConversationID" = NULL
 WHERE "ConversationID" IN (SELECT "ID" FROM _github_field_suggestion_ids);

DELETE FROM ${mjSchema}."ConversationCompactionRun"
 WHERE "ConversationDetailID" IN (SELECT "ID" FROM _github_conversation_detail_ids);

DELETE FROM ${mjSchema}."ConversationDetailRating"
 WHERE "ConversationDetailID" IN (SELECT "ID" FROM _github_conversation_detail_ids);

DELETE FROM ${mjSchema}."ConversationDetailAttachment"
 WHERE "ConversationDetailID" IN (SELECT "ID" FROM _github_conversation_detail_ids);

DELETE FROM ${mjSchema}."ConversationDetailArtifact"
 WHERE "ConversationDetailID" IN (SELECT "ID" FROM _github_conversation_detail_ids);

UPDATE ${mjSchema}."ConversationDetail"
   SET "ParentID" = NULL
 WHERE "ConversationID" IN (SELECT "ID" FROM _github_field_suggestion_ids)
    OR "ParentID" IN (SELECT "ID" FROM _github_conversation_detail_ids);

DELETE FROM ${mjSchema}."ConversationDetail"
 WHERE "ConversationID" IN (SELECT "ID" FROM _github_field_suggestion_ids);

DELETE FROM ${mjSchema}."ConversationArtifact"
 WHERE "ConversationID" IN (SELECT "ID" FROM _github_field_suggestion_ids);

DELETE FROM ${mjSchema}."ConversationBranch"
 WHERE "ConversationID" IN (SELECT "ID" FROM _github_field_suggestion_ids);

DELETE FROM ${mjSchema}."ConversationSkill"
 WHERE "ConversationID" IN (SELECT "ID" FROM _github_field_suggestion_ids);

DELETE FROM ${mjSchema}."Comment"
 WHERE "ID" IN (SELECT "ID" FROM _github_field_suggestion_ids);

DELETE FROM ${mjSchema}."Conversation"
 WHERE "ID" IN (SELECT "ID" FROM _github_field_suggestion_ids);

DROP TABLE IF EXISTS _github_conversation_detail_ids;
DROP TABLE IF EXISTS _github_field_suggestion_ids;

-- 3. Retire Planning Inference Prompt, its Template, and its execution runs
CREATE TEMP TABLE IF NOT EXISTS _github_prompt_ids AS
SELECT "ID"
  FROM ${mjSchema}."AIPrompt"
 WHERE "Name" = 'GitHub Task Planning Field Inference';

CREATE TEMP TABLE IF NOT EXISTS _github_template_ids AS
SELECT DISTINCT "TemplateID" AS "ID"
  FROM ${mjSchema}."AIPrompt"
 WHERE "ID" IN (SELECT "ID" FROM _github_prompt_ids)
   AND "TemplateID" IS NOT NULL;

CREATE TEMP TABLE IF NOT EXISTS _github_prompt_run_ids AS
SELECT "ID"
  FROM ${mjSchema}."AIPromptRun"
 WHERE "PromptID" IN (SELECT "ID" FROM _github_prompt_ids)
    OR "ChildPromptID" IN (SELECT "ID" FROM _github_prompt_ids)
    OR "JudgeID" IN (SELECT "ID" FROM _github_prompt_ids);

UPDATE ${mjSchema}."AIPromptRun"
   SET "ParentID" = NULL
 WHERE "ParentID" IN (SELECT "ID" FROM _github_prompt_run_ids)
    OR "ID" IN (SELECT "ID" FROM _github_prompt_run_ids);

UPDATE ${mjSchema}."AIPromptRun"
   SET "RerunFromPromptRunID" = NULL
 WHERE "RerunFromPromptRunID" IN (SELECT "ID" FROM _github_prompt_run_ids)
    OR "ID" IN (SELECT "ID" FROM _github_prompt_run_ids);

UPDATE ${mjSchema}."RubricEvaluation"
   SET "AIPromptRunID" = NULL
 WHERE "AIPromptRunID" IN (SELECT "ID" FROM _github_prompt_run_ids);

UPDATE ${mjSchema}."UserRoutineRun"
   SET "PromptRunID" = NULL
 WHERE "PromptRunID" IN (SELECT "ID" FROM _github_prompt_run_ids);

DELETE FROM ${mjSchema}."ConversationCompactionRun"
 WHERE "PromptRunID" IN (SELECT "ID" FROM _github_prompt_run_ids);

DELETE FROM ${mjSchema}."AIPromptRunMedia"
 WHERE "PromptRunID" IN (SELECT "ID" FROM _github_prompt_run_ids);

DELETE FROM ${mjSchema}."AIResultCache"
 WHERE "PromptRunID" IN (SELECT "ID" FROM _github_prompt_run_ids)
    OR "AIPromptID" IN (SELECT "ID" FROM _github_prompt_ids);

DELETE FROM ${mjSchema}."AIPromptRun"
 WHERE "ID" IN (SELECT "ID" FROM _github_prompt_run_ids);

DELETE FROM ${mjSchema}."AIPromptModel"
 WHERE "PromptID" IN (SELECT "ID" FROM _github_prompt_ids);

DELETE FROM ${mjSchema}."AIPrompt"
 WHERE "ID" IN (SELECT "ID" FROM _github_prompt_ids);

DELETE FROM ${mjSchema}."TemplateParam"
 WHERE "TemplateID" IN (SELECT "ID" FROM _github_template_ids);

DELETE FROM ${mjSchema}."TemplateContent"
 WHERE "TemplateID" IN (SELECT "ID" FROM _github_template_ids);

DELETE FROM ${mjSchema}."Template"
 WHERE "ID" IN (SELECT "ID" FROM _github_template_ids);

DROP TABLE IF EXISTS _github_prompt_run_ids;
DROP TABLE IF EXISTS _github_template_ids;
DROP TABLE IF EXISTS _github_prompt_ids;

-- 4. Retire Actions, execution logs, and Action Category
CREATE TEMP TABLE IF NOT EXISTS _github_action_ids AS
SELECT "ID"
  FROM ${mjSchema}."Action"
 WHERE "Name" IN (
     'Sync GitHub Repository Tasks',
     'Handle GitHub Tasks Webhook',
     'Infer GitHub Task Planning Fields'
 );

CREATE TEMP TABLE IF NOT EXISTS _github_action_execution_log_ids AS
SELECT "ID"
  FROM ${mjSchema}."ActionExecutionLog"
 WHERE "ActionID" IN (SELECT "ID" FROM _github_action_ids);

UPDATE ${mjSchema}."ProcessRunDetail"
   SET "ActionExecutionLogID" = NULL
 WHERE "ActionExecutionLogID" IN (SELECT "ID" FROM _github_action_execution_log_ids);

UPDATE ${mjSchema}."UserRoutineRun"
   SET "ActionExecutionLogID" = NULL
 WHERE "ActionExecutionLogID" IN (SELECT "ID" FROM _github_action_execution_log_ids);

DELETE FROM ${mjSchema}."ActionExecutionLog"
 WHERE "ID" IN (SELECT "ID" FROM _github_action_execution_log_ids);

DO $$
BEGIN
    IF to_regclass('${mjSchema}."ScheduledActionParam"') IS NOT NULL
       AND to_regclass('${mjSchema}."ScheduledAction"') IS NOT NULL THEN
        EXECUTE '
            DELETE FROM ${mjSchema}."ScheduledActionParam"
             WHERE "ScheduledActionID" IN (
                 SELECT "ID" FROM ${mjSchema}."ScheduledAction"
                  WHERE "ActionID" IN (SELECT "ID" FROM _github_action_ids)
             );
            DELETE FROM ${mjSchema}."ScheduledAction"
             WHERE "ActionID" IN (SELECT "ID" FROM _github_action_ids);
        ';
    END IF;
END $$;

DELETE FROM ${mjSchema}."ActionAuthorization"
 WHERE "ActionID" IN (SELECT "ID" FROM _github_action_ids);

DELETE FROM ${mjSchema}."ActionContext"
 WHERE "ActionID" IN (SELECT "ID" FROM _github_action_ids);

DELETE FROM ${mjSchema}."ActionLibrary"
 WHERE "ActionID" IN (SELECT "ID" FROM _github_action_ids);

DELETE FROM ${mjSchema}."AIAgentAction"
 WHERE "ActionID" IN (SELECT "ID" FROM _github_action_ids);

DELETE FROM ${mjSchema}."EntityActionInvocation"
 WHERE "EntityActionID" IN (SELECT "ID" FROM ${mjSchema}."EntityAction" WHERE "ActionID" IN (SELECT "ID" FROM _github_action_ids));

DELETE FROM ${mjSchema}."EntityActionParam"
 WHERE "EntityActionID" IN (SELECT "ID" FROM ${mjSchema}."EntityAction" WHERE "ActionID" IN (SELECT "ID" FROM _github_action_ids));

DELETE FROM ${mjSchema}."EntityAction"
 WHERE "ActionID" IN (SELECT "ID" FROM _github_action_ids);

DELETE FROM ${mjSchema}."ActionResultCode"
 WHERE "ActionID" IN (SELECT "ID" FROM _github_action_ids);

DELETE FROM ${mjSchema}."ActionParam"
 WHERE "ActionID" IN (SELECT "ID" FROM _github_action_ids);

DELETE FROM ${mjSchema}."Action"
 WHERE "ID" IN (SELECT "ID" FROM _github_action_ids);

DROP TABLE IF EXISTS _github_action_execution_log_ids;
DROP TABLE IF EXISTS _github_action_ids;

DELETE FROM ${mjSchema}."ActionCategory"
 WHERE "Name" IN ('Tasks GitHub', 'Tasks - GitHub');

-- 5. Retire GITHUB_ISSUE & GITHUB_PR extension rows, Tasks, TaskTypeStatus rows, and TaskTypes
CREATE TEMP TABLE IF NOT EXISTS _github_task_type_ids AS
SELECT "ID"
  FROM __mj_bizappstasks."TaskType"
 WHERE "Code" IN ('GITHUB_ISSUE', 'GITHUB_PR');

CREATE TEMP TABLE IF NOT EXISTS _github_task_ids AS
SELECT "ID"
  FROM __mj_bizappstasks."Task"
 WHERE "TypeID" IN (SELECT "ID" FROM _github_task_type_ids);

DO $$
BEGIN
    IF to_regclass('__mj_bizappstasksgithub."GitHubPullRequestTask"') IS NOT NULL THEN
        DELETE FROM __mj_bizappstasksgithub."GitHubPullRequestTask";
    END IF;
    IF to_regclass('__mj_bizappstasksgithub."GitHubIssueTask"') IS NOT NULL THEN
        DELETE FROM __mj_bizappstasksgithub."GitHubIssueTask";
    END IF;
END $$;

UPDATE __mj_bizappstasks."Task"
   SET "ParentID" = NULL
 WHERE "ParentID" IN (SELECT "ID" FROM _github_task_ids);

UPDATE __mj_bizappstasks."WorkReportItem"
   SET "TaskID" = NULL
 WHERE "TaskID" IN (SELECT "ID" FROM _github_task_ids);

DELETE FROM __mj_bizappstasks."TaskDecision"
 WHERE "TaskID" IN (SELECT "ID" FROM _github_task_ids);

DELETE FROM __mj_bizappstasks."TaskAssignment"
 WHERE "TaskID" IN (SELECT "ID" FROM _github_task_ids);

DELETE FROM __mj_bizappstasks."TaskActivity"
 WHERE "TaskID" IN (SELECT "ID" FROM _github_task_ids);

DELETE FROM __mj_bizappstasks."TaskCheckIn"
 WHERE "TaskID" IN (SELECT "ID" FROM _github_task_ids);

UPDATE __mj_bizappstasks."TaskComment"
   SET "ParentID" = NULL
 WHERE "TaskID" IN (SELECT "ID" FROM _github_task_ids)
    OR "ParentID" IN (
        SELECT "ID"
          FROM __mj_bizappstasks."TaskComment"
         WHERE "TaskID" IN (SELECT "ID" FROM _github_task_ids)
    );

DELETE FROM __mj_bizappstasks."TaskComment"
 WHERE "TaskID" IN (SELECT "ID" FROM _github_task_ids);

DELETE FROM __mj_bizappstasks."TaskDependency"
 WHERE "TaskID" IN (SELECT "ID" FROM _github_task_ids)
    OR "DependsOnTaskID" IN (SELECT "ID" FROM _github_task_ids);

DELETE FROM __mj_bizappstasks."TaskLink"
 WHERE "TaskID" IN (SELECT "ID" FROM _github_task_ids);

DELETE FROM __mj_bizappstasks."TaskNotificationLog"
 WHERE "TaskID" IN (SELECT "ID" FROM _github_task_ids);

DELETE FROM __mj_bizappstasks."TaskTagLink"
 WHERE "TaskID" IN (SELECT "ID" FROM _github_task_ids);

DELETE FROM __mj_bizappstasks."Task"
 WHERE "ID" IN (SELECT "ID" FROM _github_task_ids);

DELETE FROM __mj_bizappstasks."TaskNotificationConfig"
 WHERE "TaskTypeID" IN (SELECT "ID" FROM _github_task_type_ids);

UPDATE __mj_bizappstasks."TaskTemplateItem"
   SET "ParentItemID" = NULL
 WHERE "TemplateID" IN (
     SELECT "ID"
       FROM __mj_bizappstasks."TaskTemplate"
      WHERE "TypeID" IN (SELECT "ID" FROM _github_task_type_ids)
 );

DELETE FROM __mj_bizappstasks."TaskTemplateItem"
 WHERE "TemplateID" IN (
     SELECT "ID"
       FROM __mj_bizappstasks."TaskTemplate"
      WHERE "TypeID" IN (SELECT "ID" FROM _github_task_type_ids)
 );

DELETE FROM __mj_bizappstasks."TaskTemplate"
 WHERE "TypeID" IN (SELECT "ID" FROM _github_task_type_ids);

DELETE FROM __mj_bizappstasks."TaskTypeStatus"
 WHERE "TaskTypeID" IN (SELECT "ID" FROM _github_task_type_ids);

DELETE FROM __mj_bizappstasks."TaskType"
 WHERE "ID" IN (SELECT "ID" FROM _github_task_type_ids);

DROP TABLE IF EXISTS _github_task_ids;
DROP TABLE IF EXISTS _github_task_type_ids;
