import js from '@eslint/js';
import tseslint from 'typescript-eslint';
import globals from 'globals';
import reactHooks from 'eslint-plugin-react-hooks';
export default tseslint.config(
  {
    ignores: [
      '**/dist/**',
      '**/node_modules/**',
      '.runtime/**',
      // Claude Code worktrees and local launch settings, never project source.
      '.claude/**',
      'opus-video/**',
      'docs/references/**',
      'design/**',
      'docs/fixtures/**',
      'playwright-report/**',
      'test-results/**',
      '.env*',
      '**/target/**',
      'apps/native/build/**',
      'apps/native/.dart_tool/**',
      'apps/native/windows/flutter/ephemeral/**',
      'apps/client/src-tauri/gen/**',
      'release/**',
      '**/.tauri/**',
      'packages/tauri-plugin-nekodot/android/build/**',
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
  {
    files: ['apps/site/**/*.js'],
    languageOptions: { sourceType: 'script', globals: globals.browser },
  },
  {
    files: ['apps/web/src/**/*.{ts,tsx}'],
    plugins: { 'react-hooks': reactHooks },
    rules: reactHooks.configs.recommended.rules,
  },
);
