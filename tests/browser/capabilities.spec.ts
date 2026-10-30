import { expect, test } from '@playwright/test';
import { mkdtemp, writeFile, mkdir, readFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { randomUUID } from 'node:crypto';
import { startFakeHermes, recordedManagementRuntime } from '@nekodot/fake-hermes';
import { createRelay } from '../../apps/relay/src/server';
import { seedVerifiedAccount } from '../support/account';
import { NodeApplication } from '../../apps/node/src/app';
import { pairNode } from '../../apps/node/src/pair';
import { connectRelay } from '../../apps/node/src/connection';
import { HermesApi } from '../../apps/node/src/hermes/api';
import type { HermesRuntime } from '../../apps/node/src/hermes/runtime';

test('Bot details, native memory editing, library download, extension catalog and per-bot toggles in Edge', async ({
  page,
}) => {
  test.setTimeout(120000);
  const home = await mkdtemp(join(tmpdir(), 'nekodot-capabilities-browser-'));
  const key = 'capabilities-replay-key';
  const fake = await startFakeHermes({
    fixturesDirectory: join(process.cwd(), 'docs/fixtures'),
    profiles: ['default'],
    apiKey: key,
    allowProfileCreate: true,
  });
  const relay = await createRelay({
    dataDir: join(home, 'relay'),
    jwtSecret: 'capabilities-browser-secret',
    publicUrl: 'http://127.0.0.1:4370',
    webDirectory: join(process.cwd(), 'apps/web/dist'),
  });
  await relay.app.listen({ host: '127.0.0.1', port: 4370 });
  const runtime: HermesRuntime = {
    ...recordedManagementRuntime(fake.url, key, home, fake.pluginCatalog),
    start: async () => {},
    close: async () => {},
    approvalMode: async () => 'manual',
    configureBot: async (bot) => {
      await fetch(fake.url + '/test/profiles', {
        method: 'POST',
        headers: { Authorization: 'Bearer ' + key, 'Content-Type': 'application/json' },
        body: JSON.stringify({ profile: bot.botId }),
      });
    },
    api: async (profile) => new HermesApi(fake.url + '/p/' + profile, key),
  };
  const app = new NodeApplication(join(home, 'node'), runtime);
  let connection: ReturnType<typeof connectRelay> | undefined;
  const errors: string[] = [];
  page.on('pageerror', (e) => errors.push(e.message));
  try {
    const email = `extensions-${randomUUID()}@example.test`;
    await seedVerifiedAccount(relay.database, email, 'journey-password-123');
    const auth = await relay.app.inject({
      method: 'POST',
      url: '/api/auth/login',
      payload: {
        email,
        password: 'journey-password-123',
      },
    });
    const token = auth.json().token as string;
    const code = await relay.app.inject({
      method: 'POST',
      url: '/api/pairing-codes',
      headers: { authorization: 'Bearer ' + token },
    });
    const credentials = await pairNode(
      join(home, 'node'),
      'http://127.0.0.1:4370',
      code.json().code,
      'Capability computer',
    );
    await app.handle({
      method: 'providers.set',
      params: {
        kind: 'custom',
        name: 'Journey API',
        baseUrl: 'https://example.test/v1',
        apiKey: 'test-provider',
      },
    });
    const { bot, conversation } = await app.bots.create({
      sourceId: (await app.providers.list()).sources[0]!.sourceId,
      displayName: 'Maple',
      handle: 'maple',
      role: 'Helpful bot',
      model: 'recorded-model',
      avatar: { shape: 'dot', color: '#E8603C' },
    });
    await app.bots.create({
      sourceId: (await app.providers.list()).sources[0]!.sourceId,
      displayName: 'Cedar',
      handle: 'cedar',
      role: 'Another bot',
      model: 'recorded-model',
      avatar: { shape: 'dot', color: '#2F9E8F' },
    });
    const fileId = randomUUID(),
      messageId = randomUUID(),
      now = new Date().toISOString();
    const file = {
      fileId,
      botId: bot.botId,
      conversationId: conversation.conversationId,
      messageId,
      name: '中文报告.txt',
      mime: 'text/plain',
      size: Buffer.byteLength('CAPABILITY-DOWNLOAD'),
      sentAt: now,
      available: true,
    };
    const stored = join(home, 'node', 'library', fileId);
    await mkdir(join(home, 'node', 'library'));
    await writeFile(stored, 'CAPABILITY-DOWNLOAD');
    app.database.db
      .prepare('INSERT INTO attachments VALUES(?,?,?,?,?,?)')
      .run(fileId, bot.botId, messageId, 'MEDIA:/report.txt', stored, JSON.stringify(file));
    app.database.putMessage({
      messageId,
      conversationId: conversation.conversationId,
      seq: 0,
      author: { type: 'bot', id: bot.botId },
      kind: 'text',
      status: 'done',
      createdAt: now,
      content: { text: 'Delivered report', files: [fileId] },
    });
    connection = connectRelay({
      credentials,
      handleRpc: (req) => app.handle(req),
      handleTransfer: (req) => app.files.transfer(req),
    });
    app.onEvent = connection.event;
    app.onLive = connection.live;
    await page.addInitScript(
      ({ token, nodeId, conversationId }) => {
        localStorage.setItem('nekodot-token', token);
        localStorage.setItem('nekodot-node', nodeId);
        localStorage.setItem('nekodot-conversation-' + nodeId, conversationId);
      },
      { token, nodeId: credentials.nodeId, conversationId: conversation.conversationId },
    );
    await page.goto('http://127.0.0.1:4370');
    await expect(page.locator('.bot-row')).toHaveCount(2);
    await page.locator('.bot-row').filter({ hasText: 'Maple' }).click();
    await page.locator('.chat-title').click();
    await expect(page.getByText('还没有定时任务，可以直接在聊天中告诉 Bot。')).toBeVisible();
    await page.locator('.details-tabs').getByRole('button', { name: '记忆', exact: true }).click();
    await expect(page.locator('#native-memory-editor')).toBeVisible();
    await page
      .locator('.document-tabs')
      .getByRole('button', { name: 'USER.md', exact: true })
      .click();
    await page.locator('#native-memory-editor').fill('Prefer concise status notes: MAPLE');
    await page
      .locator('.details-scroll')
      .getByRole('button', { name: '保存', exact: true })
      .click();
    await expect(page.getByText('记忆已保存', { exact: true })).toBeVisible();
    await page
      .locator('.details-tabs')
      .getByRole('button', { name: '资料库', exact: true })
      .click();
    await expect(page.locator('.details-scroll .file-card')).toHaveCount(1);
    await page
      .locator('.details-scroll .file-card')
      .getByRole('button', { name: '预览', exact: true })
      .click();
    await expect(page.locator('.file-preview pre')).toHaveText('CAPABILITY-DOWNLOAD');
    await page.locator('.file-preview').getByRole('button', { name: '关闭', exact: true }).click();
    const pending = page.waitForEvent('download');
    await page
      .locator('.details-scroll .file-card')
      .getByRole('button', { name: '下载', exact: true })
      .click();
    const download = await pending;
    const target = join(home, 'download.txt');
    await download.saveAs(target);
    expect(await readFile(target, 'utf8')).toBe('CAPABILITY-DOWNLOAD');
    await page
      .locator('.details-header')
      .getByRole('button', { name: '关闭', exact: true })
      .click();
    await page.getByRole('button', { name: 'Skills', exact: true }).click();
    await expect(page.locator('.extension-card')).not.toHaveCount(0, { timeout: 30000 });
    await page.getByLabel('搜索名称、分类或说明').fill('claude-code');
    await page.locator('.extension-card').first().click();
    await expect(page.locator('.extension-preview')).toContainText('claude-code');
    await expect(page.getByText('没有提供仓库信息')).toBeVisible();
    await page.getByRole('button', { name: '完整内容', exact: true }).click();
    await expect(page.locator('.extension-full-content .skill-content')).toContainText(
      'claude-code',
    );
    await page.getByRole('button', { name: '返回上页', exact: true }).click();
    await expect(page.getByLabel('搜索名称、分类或说明')).toHaveValue('claude-code');
    await page
      .locator('.extension-bot-state')
      .filter({ hasText: 'Maple' })
      .getByRole('button', { name: '停用', exact: true })
      .click();
    await expect(page.locator('.extensions-page>.operation-card')).toHaveClass(/operation-done/);
    await page
      .locator('.extension-detail>header')
      .getByRole('button', { name: '关闭', exact: true })
      .click();
    const states = (await app.extensions.list('skills')).entries.find(
      (row) => row.id === 'claude-code',
    )!.states;
    expect(states.find((row) => row.botId === bot.botId)?.enabled).toBe(false);
    expect(states.filter((row) => row.enabled)).toHaveLength(1);
    await page.getByLabel('搜索名称、分类或说明').fill('agent-merge-conflict-arbiter');
    await page.locator('.extension-card').click();
    await expect(page.locator('.extension-repository')).toHaveAttribute(
      'href',
      'https://github.com/NousResearch/hermes-agent',
    );
    await expect(page.locator('.extension-preview')).toContainText('agent-merge-conflict-arbiter');
    await page
      .locator('.extension-detail>header')
      .getByRole('button', { name: '关闭', exact: true })
      .click();
    await page.getByRole('button', { name: '插件', exact: true }).click();
    await expect(page.locator('.extensions-page h1')).toHaveText('插件');
    await expect(page.locator('.extension-card')).not.toHaveCount(0);
    expect((await app.extensions.list('plugins')).entries.length).toBeGreaterThan(800);
    await page.getByLabel('搜索名称、分类或说明').fill('docs-probe');
    await page.locator('.extension-card').click();
    await expect(page.locator('.extension-preview')).toContainText('Native documentation probe');
    await expect(page.locator('.extension-files')).toContainText('README.md');
    await expect(page.locator('.extension-detail .extension-icon-image')).toHaveAttribute(
      'src',
      /^data:image\/svg\+xml/,
    );
    await expect(page.getByText('没有提供仓库信息')).toBeVisible();
    await page.getByRole('button', { name: '完整内容', exact: true }).click();
    await expect(page.locator('.extension-full-content')).toContainText('does not execute tools');
    await page.setViewportSize({ width: 1440, height: 900 });
    await page.screenshot({
      path: 'docs/evidence/side-phase3-plugin-document-1440.png',
      animations: 'disabled',
    });
    await page.getByRole('button', { name: '返回上页', exact: true }).click();
    await page
      .locator('.extension-detail>header')
      .getByRole('button', { name: '关闭', exact: true })
      .click();
    await page.getByLabel('搜索名称、分类或说明').fill('');
    for (const width of [1440, 768, 390]) {
      await page.setViewportSize({ width, height: 900 });
      await page.evaluate(
        () =>
          new Promise<void>((resolve) =>
            requestAnimationFrame(() => requestAnimationFrame(() => resolve())),
          ),
      );
      const firstCard = page.locator('.extension-card').first();
      const bounds = await firstCard.boundingBox();
      expect(bounds).not.toBeNull();
      expect(bounds!.x).toBeGreaterThanOrEqual(0);
      expect(bounds!.x + bounds!.width).toBeLessThanOrEqual(width);
      expect(
        await firstCard
          .locator(':scope > p')
          .evaluate((paragraph) => getComputedStyle(paragraph).overflowWrap),
      ).toBe('anywhere');
      await page.screenshot({
        path: `.runtime/side-phase-3/native-evidence/extension-grid-${width}.png`,
        animations: 'disabled',
      });
      expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(
        true,
      );
      await firstCard.click();
      const detail = page.locator('.extension-detail');
      const detailBounds = await detail.boundingBox();
      expect(detailBounds!.x).toBeGreaterThanOrEqual(0);
      expect(detailBounds!.x + detailBounds!.width).toBeLessThanOrEqual(width);
      await detail
        .locator(':scope > header')
        .getByRole('button', { name: '关闭', exact: true })
        .click();
    }
    expect(errors).toEqual([]);
  } finally {
    connection?.close();
    runtime.management.close();
    await app.close();
    await fake.close();
    await relay.app.close();
  }
});
