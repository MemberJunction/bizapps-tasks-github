import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    environment: 'node',
    setupFiles: ['./src/__tests__/vitest.setup.ts'],
    include: ['src/**/__tests__/**/*.test.ts'],
  },
});
