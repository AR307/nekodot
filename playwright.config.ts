import { defineConfig } from '@playwright/test';
const webPort = Number(process.env.PLAYWRIGHT_WEB_PORT ?? 4318);
const webUrl = `http://127.0.0.1:${webPort}`;
export default defineConfig({
  testDir: './tests/browser',
  use: { baseURL: webUrl, browserName: 'chromium', channel: 'msedge' },
  webServer: {
    command: `pnpm --filter @nekodot/web dev --host 127.0.0.1 --port ${webPort} --strictPort`,
    url: webUrl,
    reuseExistingServer: !process.env.CI,
  },
});
