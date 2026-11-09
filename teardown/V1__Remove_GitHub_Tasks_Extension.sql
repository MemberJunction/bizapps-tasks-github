-- Teardown for BizApps Tasks GitHub Extension (executed by `mj app remove`).
-- Retires metadata rows written into shared schemas (__mj and __mj_BizAppsTasks)
-- before __mj_BizAppsTasksGitHub is dropped.

-- 1. Retire "GitHub Tasks & Pull Requests" skill and grants
UPDATE [${mjSchema}].[SearchExecutionLog] SET [AISkillID] = NULL WHERE [AISkillID] = 'A1B2C3D4-1109-4A11-9B08-000000000001';
DELETE FROM [${mjSchema}].[ConversationSkill] WHERE [SkillID] = 'A1B2C3D4-1109-4A11-9B08-000000000001';
DELETE FROM [${mjSchema}].[AISkillPermission] WHERE [SkillID] = 'A1B2C3D4-1109-4A11-9B08-000000000001';
DELETE FROM [${mjSchema}].[AISkillSearchScope] WHERE [SkillID] = 'A1B2C3D4-1109-4A11-9B08-000000000001';
DELETE FROM [${mjSchema}].[AISkillSubAgent] WHERE [SkillID] = 'A1B2C3D4-1109-4A11-9B08-000000000001';
DELETE FROM [${mjSchema}].[AISkillAction] WHERE [SkillID] = 'A1B2C3D4-1109-4A11-9B08-000000000001';
DELETE FROM [${mjSchema}].[AIAgentSkill] WHERE [SkillID] = 'A1B2C3D4-1109-4A11-9B08-000000000001';
DELETE FROM [${mjSchema}].[AISkill] WHERE [ID] = 'A1B2C3D4-1109-4A11-9B08-000000000001';

-- 2. Retire Actions and Action Category
DELETE FROM [${mjSchema}].[ActionResultCode] WHERE [ActionID] IN (
    'A1B2C3D4-1109-4A11-9B02-000000000001',
    'A1B2C3D4-1109-4A11-9B03-000000000001',
    'A1B2C3D4-1109-4A11-9B04-000000000001'
);
DELETE FROM [${mjSchema}].[ActionParam] WHERE [ActionID] IN (
    'A1B2C3D4-1109-4A11-9B02-000000000001',
    'A1B2C3D4-1109-4A11-9B03-000000000001',
    'A1B2C3D4-1109-4A11-9B04-000000000001'
);
DELETE FROM [${mjSchema}].[Action] WHERE [ID] IN (
    'A1B2C3D4-1109-4A11-9B02-000000000001',
    'A1B2C3D4-1109-4A11-9B03-000000000001',
    'A1B2C3D4-1109-4A11-9B04-000000000001'
);
DELETE FROM [${mjSchema}].[ActionCategory] WHERE [ID] = 'A1B2C3D4-1109-4A11-9B01-000000000001';

-- 3. Retire Planning Inference Prompt
DELETE FROM [${mjSchema}].[AIPromptModel] WHERE [PromptID] = 'A1B2C3D4-1109-4A11-9B05-000000000001';
DELETE FROM [${mjSchema}].[AIPrompt] WHERE [ID] = 'A1B2C3D4-1109-4A11-9B05-000000000001';

-- 4. Detach ExtensionEntity from GITHUB_ISSUE & GITHUB_PR TaskTypes
UPDATE [__mj_BizAppsTasks].[TaskType]
   SET [ExtensionEntity] = NULL
 WHERE [Code] IN ('GITHUB_ISSUE', 'GITHUB_PR');
