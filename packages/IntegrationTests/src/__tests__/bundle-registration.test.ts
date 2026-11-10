import { describe, expect, it } from 'vitest';
import { IntegrationCheckRegistry } from '@memberjunction/testing-integration/registry';
import { GITHUB_TASKS_EXTENSION_CHECKS } from '../index.js';

describe('BizApps Tasks GitHub Integration Bundle Registration', () => {
    it('registers GH1–GH3 integration checks in IntegrationCheckRegistry', () => {
        expect(GITHUB_TASKS_EXTENSION_CHECKS).toHaveLength(3);
        const ids = IntegrationCheckRegistry.Instance.GetBundle('github-tasks-extension').map((c) => c.Id);
        expect(ids).toContain('github-tasks-extension.GH1');
        expect(ids).toContain('github-tasks-extension.GH2');
        expect(ids).toContain('github-tasks-extension.GH3');
    });
});
