-- Teardown for BizApps Tasks GitHub Extension (executed by `mj app remove`).
-- Retires runtime & metadata rows written into shared schemas (__mj and __mj_BizAppsTasks)
-- in full foreign-key dependency order before __mj_BizAppsTasksGitHub is dropped.

-- 0. Retire Tasks application NavItem settings contributed by bizapps-tasks-github
DELETE FROM [${mjSchema}].[ApplicationSetting]
 WHERE [Name] LIKE N'NavItem.bizapps-tasks-github.%';

-- 1. Retire "GitHub Tasks & Pull Requests" skill and grants
UPDATE [${mjSchema}].[SearchExecutionLog]
   SET [AISkillID] = NULL
 WHERE [AISkillID] IN (SELECT [ID] FROM [${mjSchema}].[AISkill] WHERE [Name] = N'GitHub Tasks & Pull Requests');

DELETE FROM [${mjSchema}].[ConversationSkill]
 WHERE [SkillID] IN (SELECT [ID] FROM [${mjSchema}].[AISkill] WHERE [Name] = N'GitHub Tasks & Pull Requests');

DELETE FROM [${mjSchema}].[AISkillPermission]
 WHERE [SkillID] IN (SELECT [ID] FROM [${mjSchema}].[AISkill] WHERE [Name] = N'GitHub Tasks & Pull Requests');

DELETE FROM [${mjSchema}].[AISkillSearchScope]
 WHERE [SkillID] IN (SELECT [ID] FROM [${mjSchema}].[AISkill] WHERE [Name] = N'GitHub Tasks & Pull Requests');

DELETE FROM [${mjSchema}].[AISkillSubAgent]
 WHERE [SkillID] IN (SELECT [ID] FROM [${mjSchema}].[AISkill] WHERE [Name] = N'GitHub Tasks & Pull Requests');

DELETE FROM [${mjSchema}].[AISkillAction]
 WHERE [SkillID] IN (SELECT [ID] FROM [${mjSchema}].[AISkill] WHERE [Name] = N'GitHub Tasks & Pull Requests');

DELETE FROM [${mjSchema}].[AIAgentSkill]
 WHERE [SkillID] IN (SELECT [ID] FROM [${mjSchema}].[AISkill] WHERE [Name] = N'GitHub Tasks & Pull Requests');

DELETE FROM [${mjSchema}].[AISkill]
 WHERE [Name] = N'GitHub Tasks & Pull Requests';

-- 2. Retire Field Suggestions (IS-A Comment -> Conversation) created by the GitHub inference prompt or linked to GITHUB_* Tasks
DECLARE @GitHubFieldSuggestionIDs TABLE ([ID] UNIQUEIDENTIFIER NOT NULL PRIMARY KEY);

INSERT INTO @GitHubFieldSuggestionIDs ([ID])
SELECT DISTINCT fs.[ID]
  FROM [${mjSchema}].[FieldSuggestion] fs
  LEFT JOIN [${mjSchema}].[Comment] cm ON cm.[ID] = fs.[ID]
  LEFT JOIN [${mjSchema}].[Conversation] conv ON conv.[ID] = cm.[ID]
 WHERE fs.[AIPromptRunID] IN (
           SELECT pr.[ID]
             FROM [${mjSchema}].[AIPromptRun] pr
             INNER JOIN [${mjSchema}].[AIPrompt] p ON p.[ID] = pr.[PromptID]
            WHERE p.[Name] = N'GitHub Task Planning Field Inference'
       )
    OR (
           conv.[LinkedEntityID] IN (SELECT [ID] FROM [${mjSchema}].[Entity] WHERE [Name] = N'MJ_BizApps_Tasks: Tasks')
       AND LOWER(conv.[LinkedRecordID]) IN (
               SELECT LOWER(CAST(t.[ID] AS NVARCHAR(50)))
                 FROM [__mj_BizAppsTasks].[Task] t
                 INNER JOIN [__mj_BizAppsTasks].[TaskType] tt ON tt.[ID] = t.[TypeID]
                WHERE tt.[Code] IN (N'GITHUB_ISSUE', N'GITHUB_PR')
           )
       );

DECLARE @GitHubConversationDetailIDs TABLE ([ID] UNIQUEIDENTIFIER NOT NULL PRIMARY KEY);

INSERT INTO @GitHubConversationDetailIDs ([ID])
SELECT [ID]
  FROM [${mjSchema}].[ConversationDetail]
 WHERE [ConversationID] IN (SELECT [ID] FROM @GitHubFieldSuggestionIDs);

DELETE FROM [${mjSchema}].[FieldSuggestion]
 WHERE [ID] IN (SELECT [ID] FROM @GitHubFieldSuggestionIDs);

UPDATE [${mjSchema}].[Conversation]
   SET [LastConversationID] = NULL
 WHERE [LastConversationID] IN (SELECT [ID] FROM @GitHubFieldSuggestionIDs);

UPDATE [${mjSchema}].[AIAgentRun]
   SET [ConversationDetailID] = NULL
 WHERE [ConversationDetailID] IN (SELECT [ID] FROM @GitHubConversationDetailIDs);

UPDATE [${mjSchema}].[AIAgentRun]
   SET [ConversationID] = NULL
 WHERE [ConversationID] IN (SELECT [ID] FROM @GitHubFieldSuggestionIDs);

DELETE FROM [${mjSchema}].[ConversationCompactionRun]
 WHERE [ConversationDetailID] IN (SELECT [ID] FROM @GitHubConversationDetailIDs);

DELETE FROM [${mjSchema}].[ConversationDetailRating]
 WHERE [ConversationDetailID] IN (SELECT [ID] FROM @GitHubConversationDetailIDs);

DELETE FROM [${mjSchema}].[ConversationDetailAttachment]
 WHERE [ConversationDetailID] IN (SELECT [ID] FROM @GitHubConversationDetailIDs);

DELETE FROM [${mjSchema}].[ConversationDetailArtifact]
 WHERE [ConversationDetailID] IN (SELECT [ID] FROM @GitHubConversationDetailIDs);

UPDATE [${mjSchema}].[ConversationDetail]
   SET [ParentID] = NULL
 WHERE [ConversationID] IN (SELECT [ID] FROM @GitHubFieldSuggestionIDs)
    OR [ParentID] IN (SELECT [ID] FROM @GitHubConversationDetailIDs);

DELETE FROM [${mjSchema}].[ConversationDetail]
 WHERE [ConversationID] IN (SELECT [ID] FROM @GitHubFieldSuggestionIDs);

DELETE FROM [${mjSchema}].[ConversationArtifact]
 WHERE [ConversationID] IN (SELECT [ID] FROM @GitHubFieldSuggestionIDs);

DELETE FROM [${mjSchema}].[ConversationBranch]
 WHERE [ConversationID] IN (SELECT [ID] FROM @GitHubFieldSuggestionIDs);

DELETE FROM [${mjSchema}].[ConversationSkill]
 WHERE [ConversationID] IN (SELECT [ID] FROM @GitHubFieldSuggestionIDs);

DELETE FROM [${mjSchema}].[Comment]
 WHERE [ID] IN (SELECT [ID] FROM @GitHubFieldSuggestionIDs);

DELETE FROM [${mjSchema}].[Conversation]
 WHERE [ID] IN (SELECT [ID] FROM @GitHubFieldSuggestionIDs);

-- 3. Retire Planning Inference Prompt, its Template, and its execution runs
DECLARE @GitHubPromptIDs TABLE ([ID] UNIQUEIDENTIFIER NOT NULL PRIMARY KEY);
INSERT INTO @GitHubPromptIDs ([ID])
SELECT [ID]
  FROM [${mjSchema}].[AIPrompt]
 WHERE [Name] = N'GitHub Task Planning Field Inference';

DECLARE @GitHubTemplateIDs TABLE ([ID] UNIQUEIDENTIFIER NOT NULL PRIMARY KEY);
INSERT INTO @GitHubTemplateIDs ([ID])
SELECT DISTINCT [TemplateID]
  FROM [${mjSchema}].[AIPrompt]
 WHERE [ID] IN (SELECT [ID] FROM @GitHubPromptIDs)
   AND [TemplateID] IS NOT NULL;

DECLARE @GitHubPromptRunIDs TABLE ([ID] UNIQUEIDENTIFIER NOT NULL PRIMARY KEY);
INSERT INTO @GitHubPromptRunIDs ([ID])
SELECT [ID]
  FROM [${mjSchema}].[AIPromptRun]
 WHERE [PromptID] IN (SELECT [ID] FROM @GitHubPromptIDs)
    OR [ChildPromptID] IN (SELECT [ID] FROM @GitHubPromptIDs)
    OR [JudgeID] IN (SELECT [ID] FROM @GitHubPromptIDs);

UPDATE [${mjSchema}].[AIPromptRun]
   SET [ParentID] = NULL
 WHERE [ParentID] IN (SELECT [ID] FROM @GitHubPromptRunIDs)
    OR [ID] IN (SELECT [ID] FROM @GitHubPromptRunIDs);

UPDATE [${mjSchema}].[AIPromptRun]
   SET [RerunFromPromptRunID] = NULL
 WHERE [RerunFromPromptRunID] IN (SELECT [ID] FROM @GitHubPromptRunIDs)
    OR [ID] IN (SELECT [ID] FROM @GitHubPromptRunIDs);

UPDATE [${mjSchema}].[RubricEvaluation]
   SET [AIPromptRunID] = NULL
 WHERE [AIPromptRunID] IN (SELECT [ID] FROM @GitHubPromptRunIDs);

UPDATE [${mjSchema}].[UserRoutineRun]
   SET [PromptRunID] = NULL
 WHERE [PromptRunID] IN (SELECT [ID] FROM @GitHubPromptRunIDs);

DELETE FROM [${mjSchema}].[ConversationCompactionRun]
 WHERE [PromptRunID] IN (SELECT [ID] FROM @GitHubPromptRunIDs);

DELETE FROM [${mjSchema}].[AIPromptRunMedia]
 WHERE [PromptRunID] IN (SELECT [ID] FROM @GitHubPromptRunIDs);

DELETE FROM [${mjSchema}].[AIResultCache]
 WHERE [PromptRunID] IN (SELECT [ID] FROM @GitHubPromptRunIDs)
    OR [AIPromptID] IN (SELECT [ID] FROM @GitHubPromptIDs);

DELETE FROM [${mjSchema}].[AIPromptRun]
 WHERE [ID] IN (SELECT [ID] FROM @GitHubPromptRunIDs);

DELETE FROM [${mjSchema}].[AIPromptModel]
 WHERE [PromptID] IN (SELECT [ID] FROM @GitHubPromptIDs);

DELETE FROM [${mjSchema}].[AIPrompt]
 WHERE [ID] IN (SELECT [ID] FROM @GitHubPromptIDs);

DELETE FROM [${mjSchema}].[TemplateParam]
 WHERE [TemplateID] IN (SELECT [ID] FROM @GitHubTemplateIDs);

DELETE FROM [${mjSchema}].[TemplateContent]
 WHERE [TemplateID] IN (SELECT [ID] FROM @GitHubTemplateIDs);

DELETE FROM [${mjSchema}].[Template]
 WHERE [ID] IN (SELECT [ID] FROM @GitHubTemplateIDs);

-- 4. Retire Actions, execution logs, and Action Category
DECLARE @GitHubActionIDs TABLE ([ID] UNIQUEIDENTIFIER NOT NULL PRIMARY KEY);

INSERT INTO @GitHubActionIDs ([ID])
SELECT [ID]
  FROM [${mjSchema}].[Action]
 WHERE [Name] IN (
     N'Sync GitHub Repository Tasks',
     N'Handle GitHub Tasks Webhook',
     N'Infer GitHub Task Planning Fields'
 );

DECLARE @GitHubActionExecutionLogIDs TABLE ([ID] UNIQUEIDENTIFIER NOT NULL PRIMARY KEY);

INSERT INTO @GitHubActionExecutionLogIDs ([ID])
SELECT [ID]
  FROM [${mjSchema}].[ActionExecutionLog]
 WHERE [ActionID] IN (SELECT [ID] FROM @GitHubActionIDs);

UPDATE [${mjSchema}].[ProcessRunDetail]
   SET [ActionExecutionLogID] = NULL
 WHERE [ActionExecutionLogID] IN (SELECT [ID] FROM @GitHubActionExecutionLogIDs);

UPDATE [${mjSchema}].[UserRoutineRun]
   SET [ActionExecutionLogID] = NULL
 WHERE [ActionExecutionLogID] IN (SELECT [ID] FROM @GitHubActionExecutionLogIDs);

DELETE FROM [${mjSchema}].[ActionExecutionLog]
 WHERE [ID] IN (SELECT [ID] FROM @GitHubActionExecutionLogIDs);

IF OBJECT_ID(N'[${mjSchema}].[ScheduledActionParam]', N'U') IS NOT NULL
    AND OBJECT_ID(N'[${mjSchema}].[ScheduledAction]', N'U') IS NOT NULL
BEGIN
    EXEC sp_executesql N'
        DELETE FROM [${mjSchema}].[ScheduledActionParam]
         WHERE [ScheduledActionID] IN (
             SELECT [ID] FROM [${mjSchema}].[ScheduledAction]
              WHERE [ActionID] IN (
                  SELECT [ID] FROM [${mjSchema}].[Action]
                   WHERE [Name] IN (N''Sync GitHub Repository Tasks'', N''Handle GitHub Tasks Webhook'', N''Infer GitHub Task Planning Fields'')
              )
         );
        DELETE FROM [${mjSchema}].[ScheduledAction]
         WHERE [ActionID] IN (
             SELECT [ID] FROM [${mjSchema}].[Action]
              WHERE [Name] IN (N''Sync GitHub Repository Tasks'', N''Handle GitHub Tasks Webhook'', N''Infer GitHub Task Planning Fields'')
         );
    ';
END

DELETE FROM [${mjSchema}].[ActionAuthorization]
 WHERE [ActionID] IN (SELECT [ID] FROM @GitHubActionIDs);

DELETE FROM [${mjSchema}].[ActionContext]
 WHERE [ActionID] IN (SELECT [ID] FROM @GitHubActionIDs);

DELETE FROM [${mjSchema}].[ActionLibrary]
 WHERE [ActionID] IN (SELECT [ID] FROM @GitHubActionIDs);

DELETE FROM [${mjSchema}].[AIAgentAction]
 WHERE [ActionID] IN (SELECT [ID] FROM @GitHubActionIDs);

DELETE FROM [${mjSchema}].[EntityActionInvocation]
 WHERE [EntityActionID] IN (SELECT [ID] FROM [${mjSchema}].[EntityAction] WHERE [ActionID] IN (SELECT [ID] FROM @GitHubActionIDs));

DELETE FROM [${mjSchema}].[EntityActionParam]
 WHERE [EntityActionID] IN (SELECT [ID] FROM [${mjSchema}].[EntityAction] WHERE [ActionID] IN (SELECT [ID] FROM @GitHubActionIDs));

DELETE FROM [${mjSchema}].[EntityAction]
 WHERE [ActionID] IN (SELECT [ID] FROM @GitHubActionIDs);

DELETE FROM [${mjSchema}].[ActionResultCode]
 WHERE [ActionID] IN (SELECT [ID] FROM @GitHubActionIDs);

DELETE FROM [${mjSchema}].[ActionParam]
 WHERE [ActionID] IN (SELECT [ID] FROM @GitHubActionIDs);

DELETE FROM [${mjSchema}].[Action]
 WHERE [ID] IN (SELECT [ID] FROM @GitHubActionIDs);

DELETE FROM [${mjSchema}].[ActionCategory]
 WHERE [Name] IN (N'Tasks GitHub', N'Tasks - GitHub');

-- 5. Retire GITHUB_ISSUE & GITHUB_PR extension rows, Tasks, TaskTypeStatus rows, and TaskTypes
DECLARE @GitHubTaskTypeIDs TABLE ([ID] UNIQUEIDENTIFIER NOT NULL PRIMARY KEY);
INSERT INTO @GitHubTaskTypeIDs ([ID])
SELECT [ID]
  FROM [__mj_BizAppsTasks].[TaskType]
 WHERE [Code] IN (N'GITHUB_ISSUE', N'GITHUB_PR');

DECLARE @GitHubTaskIDs TABLE ([ID] UNIQUEIDENTIFIER NOT NULL PRIMARY KEY);
INSERT INTO @GitHubTaskIDs ([ID])
SELECT [ID]
  FROM [__mj_BizAppsTasks].[Task]
 WHERE [TypeID] IN (SELECT [ID] FROM @GitHubTaskTypeIDs);

IF OBJECT_ID(N'[__mj_BizAppsTasksGitHub].[GitHubPullRequestTask]', N'U') IS NOT NULL
    DELETE FROM [__mj_BizAppsTasksGitHub].[GitHubPullRequestTask];

IF OBJECT_ID(N'[__mj_BizAppsTasksGitHub].[GitHubIssueTask]', N'U') IS NOT NULL
    DELETE FROM [__mj_BizAppsTasksGitHub].[GitHubIssueTask];

UPDATE [__mj_BizAppsTasks].[Task]
   SET [ParentID] = NULL
 WHERE [ParentID] IN (SELECT [ID] FROM @GitHubTaskIDs);

UPDATE [__mj_BizAppsTasks].[WorkReportItem]
   SET [TaskID] = NULL
 WHERE [TaskID] IN (SELECT [ID] FROM @GitHubTaskIDs);

DELETE FROM [__mj_BizAppsTasks].[TaskDecision]
 WHERE [TaskID] IN (SELECT [ID] FROM @GitHubTaskIDs);

DELETE FROM [__mj_BizAppsTasks].[TaskAssignment]
 WHERE [TaskID] IN (SELECT [ID] FROM @GitHubTaskIDs);

DELETE FROM [__mj_BizAppsTasks].[TaskActivity]
 WHERE [TaskID] IN (SELECT [ID] FROM @GitHubTaskIDs);

DELETE FROM [__mj_BizAppsTasks].[TaskCheckIn]
 WHERE [TaskID] IN (SELECT [ID] FROM @GitHubTaskIDs);

UPDATE [__mj_BizAppsTasks].[TaskComment]
   SET [ParentID] = NULL
 WHERE [TaskID] IN (SELECT [ID] FROM @GitHubTaskIDs)
    OR [ParentID] IN (
        SELECT [ID]
          FROM [__mj_BizAppsTasks].[TaskComment]
         WHERE [TaskID] IN (SELECT [ID] FROM @GitHubTaskIDs)
    );

DELETE FROM [__mj_BizAppsTasks].[TaskComment]
 WHERE [TaskID] IN (SELECT [ID] FROM @GitHubTaskIDs);

DELETE FROM [__mj_BizAppsTasks].[TaskDependency]
 WHERE [TaskID] IN (SELECT [ID] FROM @GitHubTaskIDs)
    OR [DependsOnTaskID] IN (SELECT [ID] FROM @GitHubTaskIDs);

DELETE FROM [__mj_BizAppsTasks].[TaskLink]
 WHERE [TaskID] IN (SELECT [ID] FROM @GitHubTaskIDs);

DELETE FROM [__mj_BizAppsTasks].[TaskNotificationLog]
 WHERE [TaskID] IN (SELECT [ID] FROM @GitHubTaskIDs);

DELETE FROM [__mj_BizAppsTasks].[TaskTagLink]
 WHERE [TaskID] IN (SELECT [ID] FROM @GitHubTaskIDs);

DELETE FROM [__mj_BizAppsTasks].[Task]
 WHERE [ID] IN (SELECT [ID] FROM @GitHubTaskIDs);

DELETE FROM [__mj_BizAppsTasks].[TaskNotificationConfig]
 WHERE [TaskTypeID] IN (SELECT [ID] FROM @GitHubTaskTypeIDs);

UPDATE [__mj_BizAppsTasks].[TaskTemplateItem]
   SET [ParentItemID] = NULL
 WHERE [TemplateID] IN (
     SELECT [ID]
       FROM [__mj_BizAppsTasks].[TaskTemplate]
      WHERE [TypeID] IN (SELECT [ID] FROM @GitHubTaskTypeIDs)
 );

DELETE FROM [__mj_BizAppsTasks].[TaskTemplateItem]
 WHERE [TemplateID] IN (
     SELECT [ID]
       FROM [__mj_BizAppsTasks].[TaskTemplate]
      WHERE [TypeID] IN (SELECT [ID] FROM @GitHubTaskTypeIDs)
 );

DELETE FROM [__mj_BizAppsTasks].[TaskTemplate]
 WHERE [TypeID] IN (SELECT [ID] FROM @GitHubTaskTypeIDs);

DELETE FROM [__mj_BizAppsTasks].[TaskTypeStatus]
 WHERE [TaskTypeID] IN (SELECT [ID] FROM @GitHubTaskTypeIDs);

DELETE FROM [__mj_BizAppsTasks].[TaskType]
 WHERE [ID] IN (SELECT [ID] FROM @GitHubTaskTypeIDs);
