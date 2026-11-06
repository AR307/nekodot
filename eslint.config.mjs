import js from '@eslint/js';
import tseslint from 'typescript-eslint';
import globals from 'globals';
export default tseslint.config(
  {
    ignores: [
      // Kept on the maintainers' computers only, never committed.
      'docs/**',
      'design/**',
      'apps/site/**',
      'opus-video/**',
      '**/dist/**',
      '**/node_modules/**',
      '.runtime/**',
      'tests/fixtures/**',
      // Claude Code worktrees and local launch settings, never project source.
      '.claude/**',
      'playwright-report/**',
      'test-results/**',
      '.env*',
      '**/target/**',
      'apps/native/build/**',
      'apps/native/.dart_tool/**',
      'apps/native/windows/flutter/ephemeral/**',
      'release/**',
    ],
  },
  js.configs.recommended,
  ...tseslint.configs.recommended,
  {
    files: ['**/*.{ts,tsx,mjs}'],
    languageOptions: {
      globals: { ...globals.node, ...globals.browser },
      // Nested checkouts (e.g. worktrees) must not change which tsconfig root is used.
      parserOptions: { tsconfigRootDir: import.meta.dirname },
    },
  },
);
