import { expect, test } from '@playwright/test';
import { mkdtemp } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { randomUUID } from 'node:crypto';
import { startFakeHermes, recordedManagementRuntime } from '@nekodot/fake-hermes';
import { createRelay } from '../../apps/relay/src/server';
import { seedVerifiedAccount } from '../support/account';
import { pairNode } from '../../apps/node/src/pair';
import { NodeApplication } from '../../apps/node/src/app';
import { HermesApi } from '../../apps/node/src/hermes/api';
import { connectRelay } from '../../apps/node/src/connection';
import type { HermesRuntime } from '../../apps/node/src/hermes/runtime';

test('Edge manages coexisting sources, selects a source in the Bot form, and shows native model information', async ({
  page,
}) => {
  test.setTimeout(120000);
  const home = await mkdtemp(join(tmpdir(), 'nekodot-source-browser-'));
  const key = randomUUID(),
    email = `source-${randomUUID()}@example.test`,
    password = randomUUID();
  const url = 'http://127.0.0.1:4387';
  const fake = await startFakeHermes({
    fixturesDirectory: join(process.cwd(), 'docs/fixtures'),
    profiles: ['default'],
    apiKey: key,
    allowProfileCreate: true,
  });
  const relay = await createRelay({
    dataDir: join(home, 'relay'),
    jwtSecret: randomUUID(),
    publicUrl: url,
    webDirectory: join(process.cwd(), 'apps/web/dist'),
  });
  await relay.app.listen({ host: '127.0.0.1', port: 4387 });
  await seedVerifiedAccount(relay.database, email, password);
  const login = await relay.app.inject({
    method: 'POST',
    url: '/api/auth/login',
    payload: { email, password },
  });
  const pairing = await relay.app.inject({
    method: 'POST',
    url: '/api/pairing-codes',
    headers: { authorization: 'Bearer ' + login.json().token },
    payload: {},
  });
  const credentials = await pairNode(
    join(home, 'node'),
    url,
    pairing.json().code,
    'Source journey computer',
  );
  const runtime: HermesRuntime = {
    ...recordedManagementRuntime(fake.url, key, home, fake.pluginCatalog),
    start: async () => {},
    close: async () => {},
    approvalMode: async () => 'manual',
    api: async (profile) => new HermesApi(fake.url + '/p/' + profile, key),
    configureBot: async (bot, create) => {
      if (create)
        await fetch(fake.url + '/test/profiles', {
          method: 'POST',
          headers: { Authorization: 'Bearer ' + key, 'Content-Type': 'application/json' },
          body: JSON.stringify({ profile: bot.botId }),
        });
    },
  };
  const app = new NodeApplication(join(home, 'node'), runtime);
  const connection = connectRelay({
    credentials,
    handleRpc: (request) => app.handle(request),
    onReady: () => app.activities(),
  });
  app.onEvent = connection.event;
  app.onLive = connection.live;
  const errors: string[] = [];
  page.on('pageerror', (error) => errors.push(error.message));
  try {
    await page.goto(url);
    await page.getByRole('button', { name: '已有账号？登录', exact: true }).click();
    await page.getByLabel('邮箱', { exact: true }).fill(email);
    await page.getByLabel('密码', { exact: true }).fill(password);
    await page.getByRole('button', { name: '继续', exact: true }).click();
    await expect(page.locator('.node-picker summary')).toContainText('Source journey computer');
    await page.locator('.sidebar-header button[aria-label="设置"]').click();
    await expect(page.getByRole('heading', { name: '授权登录', exact: true })).toBeVisible();
    await expect(page.getByLabel('默认模型（可选）')).toHaveCount(0);
    await expect(page.getByLabel('可用模型')).toHaveCount(0);
    const authorization = page
      .locator('.authorization-card')
      .filter({ hasText: 'ChatGPT or Codex Subscription' });
    await authorization.getByRole('button', { name: '开始授权', exact: true }).click();
    await expect(authorization.locator('.authorization-session')).toContainText('TEST-ONLY');
    await expect(authorization.locator('small')).toContainText('已授权', { timeout: 15000 });
    expect(
      (await app.providers.models({ sourceId: 'oauth:openai-codex' })).models.length,
    ).toBeGreaterThan(0);
    for (const name of ['Research API', 'Writing API']) {
      if (name === 'Writing API')
        await page.getByRole('button', { name: '新增来源', exact: true }).click();
      await page.getByLabel('名字', { exact: true }).fill(name);
      await page.getByLabel('API 地址', { exact: true }).fill('https://models.example.test/v1');
      await page.getByLabel('API Key', { exact: true }).fill('test-only-' + name);
      await page.getByRole('button', { name: '保存并获取模型', exact: true }).click();
      await expect(page.locator('.success-message')).toContainText('已保存');
    }
    await expect(page.locator('.source-row')).toHaveCount(2);
    for (const width of [390, 768, 1440]) {
      await page.setViewportSize({ width, height: 1000 });
      expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(
        true,
      );
      await page.screenshot({
        path: `docs/evidence/side-phase3-sources-${width}.png`,
        fullPage: true,
      });
    }
    await page.getByRole('button', { name: '返回团队', exact: true }).click();
    await page.getByRole('button', { name: '新建 bot', exact: true }).last().click();
    await page.getByLabel('名字', { exact: true }).fill('Maple');
    await page.getByLabel('它负责什么？').fill('Practical research assistant');
    await page.getByLabel('模型来源', { exact: true }).selectOption({ label: 'Writing API' });
    await expect(page.getByLabel('可用模型').locator('option')).not.toHaveCount(0);
    await page.getByLabel('模型', { exact: true }).fill('recorded-model');
    await page.getByRole('button', { name: '高级设置', exact: true }).click();
    await page.getByLabel('上下文覆盖值（可选）', { exact: true }).fill('64000');
    await page.getByLabel('上下文覆盖值（可选）', { exact: true }).scrollIntoViewIfNeeded();
    await page.waitForTimeout(350);
    await page.screenshot({ path: 'docs/evidence/side-phase3-source-bot-form.png' });
    await page.getByRole('button', { name: '创建 Maple', exact: true }).click();
    await expect(page.locator('.welcome-introduction')).toContainText('Maple');
    await expect(page.locator('.run-banner')).toHaveCount(0);
    const bot = app.database.bots()[0]!;
    expect(bot.sourceId).toBe(
      (await app.providers.list()).sources.find((source) => source.name === 'Writing API')!
        .sourceId,
    );
    await page.reload();
    await expect(page.locator('.welcome-introduction')).toHaveCount(1);
    await page.locator('.chat-header .chat-title').click();
    await expect(page.getByRole('heading', { name: '模型与压缩', exact: true })).toBeVisible();
    await expect(page.locator('.model-limits')).toContainText('64000');
    await page.waitForTimeout(350);
    await page.screenshot({ path: 'docs/evidence/side-phase3-model-information.png' });
    expect(errors).toEqual([]);
  } finally {
    connection.close();
    runtime.management.close();
    await app.close();
    await fake.close();
    await relay.app.close();
  }
});
