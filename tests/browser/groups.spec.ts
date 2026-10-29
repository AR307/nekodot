import { expect, test } from '@playwright/test';
import { mkdtemp } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { randomUUID } from 'node:crypto';
import { startFakeHermes, recordedManagementRuntime } from '@nekodot/fake-hermes';
import { createRelay } from '../../apps/relay/src/server';
import { pairNode } from '../../apps/node/src/pair';
import { NodeApplication } from '../../apps/node/src/app';
import { HermesApi } from '../../apps/node/src/hermes/api';
import { connectRelay } from '../../apps/node/src/connection';
import type { HermesRuntime } from '../../apps/node/src/hermes/runtime';

test('Edge creates and edits a group, relays recorded members, resumes approvals, steers, stops, and archives', async ({
  page,
}) => {
  test.setTimeout(240000);
  const relayUrl = 'http://127.0.0.1:4340';
  const key = 'group-browser-test-key';
  const schedule: string[] = [];
  const fake = await startFakeHermes({
    fixturesDirectory: join(process.cwd(), 'docs/fixtures'),
    profiles: ['default'],
    apiKey: key,
    allowProfileCreate: true,
    eventDelayMs: 40,
    additionalFixtures: [
      'group-lead',
      'group-researcher',
      'group-writer',
      'group-steer',
      'group-stop',
    ],
    scenarioFor: () => schedule.shift(),
  });
  const relay = await createRelay({
    dataDir: await mkdtemp(join(tmpdir(), 'nekodot-group-relay-')),
    jwtSecret: 'group-browser-secret',
    publicUrl: relayUrl,
    webDirectory: join(process.cwd(), 'apps/web/dist'),
  });
  await relay.app.listen({ host: '127.0.0.1', port: 4340 });
  let app: NodeApplication | undefined;
  let connection: ReturnType<typeof connectRelay> | undefined;
  let rejectNextControl = false;
  const errors: string[] = [];
  page.on('pageerror', (error) => errors.push(error.message));
  try {
    await page.goto(relayUrl);
    await page.getByLabel('邮箱').fill(`groups-${randomUUID()}@example.test`);
    await page.getByLabel('密码').fill('group-browser-password');
    await page.getByRole('button', { name: '继续', exact: true }).click();
    await expect(page.locator('.pair-wait')).toBeVisible();
    const code = (await page.locator('.pair-wait').innerText()).match(
      /[A-HJ-NP-Z2-9]{4}-[A-HJ-NP-Z2-9]{4}/,
    )![0];
    const home = await mkdtemp(join(tmpdir(), 'nekodot-group-browser-'));
    const credentials = await pairNode(home, relayUrl, code, 'Group test computer');
    const runtime: HermesRuntime = {
      ...recordedManagementRuntime(fake.url, key, home, fake.pluginCatalog),
      start: async () => {},
      close: async () => {},
      approvalMode: async () => 'manual',
      configureProvider: async () => {},
      configureBot: async (bot, create) => {
        if (create)
          await fetch(fake.url + '/test/profiles', {
            method: 'POST',
            headers: { Authorization: 'Bearer ' + key, 'Content-Type': 'application/json' },
            body: JSON.stringify({ profile: bot.botId }),
          });
      },
      api: async (profile) => {
        const apiKey = rejectNextControl ? 'rejected-control-key' : key;
        rejectNextControl = false;
        return new HermesApi(fake.url + '/p/' + profile, apiKey);
      },
      models: async () => ({ models: [] }),
    };
    const connect = () => {
      connection = connectRelay({
        credentials,
        handleRpc: (request) => app!.handle(request),
        onReady: () => app!.activities(),
      });
      app!.onEvent = connection.event;
      app!.onLive = connection.live;
    };
    app = new NodeApplication(home, runtime);
    connect();
    await expect(page.locator('.node-picker summary')).toContainText('Group test computer');
    await page.locator('.sidebar-header button[aria-label="设置"]').click();
    await page.getByLabel('API 地址').fill('https://test.example/v1');
    await page.getByLabel('API Key', { exact: true }).fill('test-only-provider-key');
    await page.getByRole('button', { name: '保存并获取模型' }).click();
    await expect(page.locator('.saved-key')).toBeVisible();
    await page.getByRole('button', { name: '返回团队' }).click();
    for (const [name, handle] of [
      ['Researcher', 'researcher'],
      ['Writer', 'writer'],
    ]) {
      await page.getByRole('button', { name: '新建 bot', exact: true }).last().click();
      await page.getByLabel('名字', { exact: true }).fill(name!);
      await page.getByLabel('它负责什么？').fill('A group specialist.');
      await page.getByLabel('模型', { exact: true }).fill('recorded-model');
      await page.getByRole('button', { name: '高级设置' }).click();
      await page.locator('.advanced-field input').fill(handle!);
      await page
        .locator('.bot-dialog')
        .getByRole('button', { name: `创建 ${name!}` })
        .click();
      await expect(page.locator('.chat-title')).toContainText(name!);
      if (handle === 'researcher') {
        schedule.push('runs-basic');
        await page.locator('.composer textarea').fill('Remember our private discussion.');
        await page.locator('.send-button').click();
        await expect(
          page.locator('.bot-copy').filter({ hasText: 'NEKODOT_PHASE0_OK' }),
        ).toBeVisible();
        await expect(page.locator('.run-banner')).toHaveCount(0, { timeout: 15000 });
      }
    }
    const researcher = app.database.bots().find((bot) => bot.handle === 'researcher')!;
    const researcherConversation = app.database
      .conversations()
      .find(
        (conversation) => conversation.kind === 'dm' && conversation.botId === researcher.botId,
      )!;
    const privateSessionId = fake.inspectRuns()[0]!.sessionId;
    expect(privateSessionId).toBe(`nk_dm_${researcherConversation.conversationId}`);
    await page.getByRole('button', { name: '新建群组', exact: true }).last().click();
    await page.getByLabel('群组名称').fill('Research studio');
    await page.locator('.member-option').filter({ hasText: 'Researcher' }).locator('input').check();
    await expect(page.getByRole('button', { name: '创建群组', exact: true })).toBeDisabled();
    await page.locator('.member-option').filter({ hasText: 'Writer' }).locator('input').check();
    await page.screenshot({ path: 'docs/evidence/phase2-new-group.png', animations: 'disabled' });
    await page.getByRole('button', { name: '创建群组', exact: true }).click();
    await page.locator('.group-row').first().click();
    await expect(page.locator('.chat-title')).toContainText('Research studio');
    const send = async (text: string) => {
      await page.locator('.composer textarea').fill(text);
      await page.locator('.send-button').click();
    };
    const idle = () => expect(page.locator('.run-banner')).toHaveCount(0, { timeout: 15000 });
    schedule.push('group-lead');
    await send('A lead reply without mentions.');
    await expect(page.locator('.stream-cursor')).toBeVisible();
    await expect(page.locator('.chain-progress')).toContainText('1 / 6');
    await page.screenshot({ path: 'docs/evidence/phase2-streaming.png', animations: 'disabled' });
    await idle();
    expect(fake.inspectRuns()).toHaveLength(2);
    const groupSessionId = fake.inspectRuns().at(-1)!.sessionId;
    expect(groupSessionId).toBe(privateSessionId);
    await page.locator('.composer textarea').fill('@w');
    await expect(page.getByRole('listbox', { name: '@ 群成员' })).toBeVisible();
    await page.getByRole('option', { name: /Writer/ }).click();
    await expect(page.locator('.composer textarea')).toHaveValue('@writer ');
    await page.locator('.composer textarea').fill('');
    schedule.push('group-researcher', 'group-writer');
    await send('Let the researcher hand off to the writer.');
    await expect(page.locator('.bot-copy').filter({ hasText: 'PHASE2_RELAY_OK' })).toBeVisible();
    await idle();
    expect(fake.inspectRuns()).toHaveLength(4);
    await expect(page.locator('.handoff-tag')).toContainText('@writer');
    await expect(
      page.locator('.message-author').filter({ hasText: 'Writer @writer' }),
    ).toBeVisible();
    await page.reload();
    await expect(page.locator('.bot-copy').filter({ hasText: 'PHASE2_RELAY_OK' })).toBeVisible();

    schedule.push('runs-tools-approval');
    await send('A protected-file approval for the lead.');
    await expect(page.locator('.approval-card')).toBeVisible();
    await page.locator('.composer textarea').fill('Draft while waiting');
    await expect(page.locator('.send-button')).toBeDisabled();
    await page.reload();
    await expect(
      page.locator('.approval-card button').filter({ hasText: '允许一次' }),
    ).toBeVisible();
    connection!.close();
    await app.close();
    app = new NodeApplication(home, runtime);
    connect();
    await app.resume();
    await expect(page.locator('.chat-status')).toContainText('等你确认');
    await page.locator('.approval-card').getByRole('button', { name: '允许一次' }).click();
    await idle();

    schedule.push('group-steer');
    await send('@researcher @writer A task to steer.');
    await expect(page.locator('.tool-card').filter({ hasText: 'terminal' }).last()).toBeVisible();
    const runId = fake.inspectRuns().at(-1)!.runId;
    connection!.close();
    await expect(page.locator('.chat-status')).toContainText('电脑离线');
    connect();
    await expect(page.locator('.chat-status')).toContainText('正在运行工具');
    rejectNextControl = true;
    await send('Keep this run and use the added instruction.');
    await expect(page.locator('.inline-error')).toContainText('Hermes HTTP 401');
    await expect(page.locator('.composer textarea')).toHaveValue(
      'Keep this run and use the added instruction.',
    );
    await send('Keep this run and use the added instruction.');
    await expect(page.getByText('已向当前回合补充指令', { exact: true })).toBeVisible();
    await idle();
    expect(fake.inspectRuns().at(-1)).toMatchObject({ runId, toolStarts: 1 });
    expect(fake.inspectRuns()).toHaveLength(6);
    schedule.push('group-stop');
    await send('@researcher @writer A long task.');
    await expect(page.locator('.run-banner')).toBeVisible();
    await expect.poll(() => app!.database.runs()[0]?.state).toBe('tool');
    await page.getByRole('button', { name: '全部停止', exact: true }).click();
    await idle();
    expect(fake.inspectRuns()).toHaveLength(7);
    await expect(page.locator('.tool-card').last().locator('.tool-status')).toContainText('已停止');

    await page.locator('.chat-title').click();
    await page.getByLabel('群组名称').fill('Edited studio');
    await page.locator('.group-dialog select').selectOption({ label: 'Writer (@writer)' });
    await page.locator('.group-dialog').getByRole('button', { name: '保存', exact: true }).click();
    await expect(page.locator('.chat-title')).toContainText('Edited studio');
    await expect(page.locator('.chat-title')).toContainText('主答: Writer');
    for (const width of [1440, 768, 390]) {
      await page.setViewportSize({ width, height: 900 });
      await page.screenshot({
        path: `docs/evidence/phase2-chat-${width}.png`,
        animations: 'disabled',
      });
      expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(
        true,
      );
      await expect(page.locator('.composer')).toBeInViewport();
    }
    await page.setViewportSize({ width: 1440, height: 900 });
    await page.emulateMedia({ reducedMotion: 'reduce' });
    await page.locator('.sidebar-header button[aria-label="设置"]').click();
    await page.getByRole('button', { name: '切换主题' }).click();
    await page.getByRole('button', { name: '返回团队' }).click();
    await page.locator('.language-button').click();
    await expect(page.locator('.chat-title')).toContainText('Lead: Writer');
    await expect(page.locator('.app-shell')).toHaveAttribute('data-theme', 'dark');
    await page.screenshot({
      path: 'docs/evidence/phase2-dark-en-reduced.png',
      animations: 'disabled',
    });
    await page.setViewportSize({ width: 1440, height: 900 });
    await page.locator('.chat-title').click();
    await page.getByRole('button', { name: 'Archive', exact: true }).click();
    await expect(page.locator('.group-row')).toHaveCount(0);
    await page.locator('.bot-row').filter({ hasText: 'Researcher' }).click();
    schedule.push('runs-basic');
    await send('Back in private chat, recall the group discussion.');
    await expect(page.locator('.bot-copy').filter({ hasText: 'NEKODOT_PHASE0_OK' })).toBeVisible();
    await idle();
    expect(fake.inspectRuns().at(-1)).toMatchObject({
      profile: researcher.botId,
      sessionId: privateSessionId,
    });
    expect(
      app.database.messages(
        app.database.conversations().find((item) => item.kind === 'group')!.conversationId,
      ).length,
    ).toBeGreaterThan(5);
    expect(errors).toEqual([]);
  } finally {
    connection?.close();
    if (app) await app.close();
    await relay.app.close();
    await fake.close();
  }
});
