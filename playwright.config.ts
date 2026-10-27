import { defineConfig } from '@playwright/test';
export default defineConfig({
  testDir: './tests/browser',
  use: { baseURL: 'http://127.0.0.1:4318', browserName: 'chromium', channel: 'msedge' },
  webServer: {
    command: 'pnpm --filter @nekodot/web dev --host 127.0.0.1 --port 4318',
    url: 'http://127.0.0.1:4318',
    reuseExistingServer: !process.env.CI,
  },
});
