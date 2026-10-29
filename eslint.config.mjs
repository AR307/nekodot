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
      'docs/references/**',
      'design/**',
      'docs/fixtures/**',
      'playwright-report/**',
      'test-results/**',
      '.env*',
      '**/target/**',
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
    languageOptions: { globals: { ...globals.node, ...globals.browser } },
  },
  {
    files: ['apps/web/src/**/*.{ts,tsx}'],
    plugins: { 'react-hooks': reactHooks },
    rules: reactHooks.configs.recommended.rules,
  },
);
