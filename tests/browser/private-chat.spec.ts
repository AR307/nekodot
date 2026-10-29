import { expect, test } from '@playwright/test';
import { mkdtemp } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { randomUUID } from 'node:crypto';
import { setTimeout as delay } from 'node:timers/promises';
import { startFakeHermes, recordedManagementRuntime } from '@nekodot/fake-hermes';
import { createRelay } from '../../apps/relay/src/server';
import { pairNode } from '../../apps/node/src/pair';
import { NodeApplication } from '../../apps/node/src/app';
import { HermesApi } from '../../apps/node/src/hermes/api';
import { connectRelay } from '../../apps/node/src/connection';
import type { HermesRuntime } from '../../apps/node/src/hermes/runtime';
import type { Bot } from '../../packages/protocol/src/entities';
import type { NodeCredentials } from '../../apps/node/src/connection';
import type { ApprovalMode } from '../../packages/protocol/src/entities';

const relayPort = 4319;
const relayUrl = `http://127.0.0.1:${relayPort}`;
const hermesKey = 'playwright-hermes-key';
test.setTimeout(90000);

const services: {
  relay?: Awaited<ReturnType<typeof createRelay>>;
  fake?: Awaited<ReturnType<typeof startFakeHermes>>;
  app?: NodeApplication;
  connection?: ReturnType<typeof connectRelay>;
  credentials?: NodeCredentials;
  nodeHome?: string;
  secondApp?: NodeApplication;
  secondConnection?: ReturnType<typeof connectRelay>;
} = {};

test.beforeAll(async () => {
  services.fake = await startFakeHermes({
    fixturesDirectory: join(process.cwd(), 'docs/fixtures'),
    profiles: ['default'],
    apiKey: hermesKey,
    allowProfileCreate: true,
    eventDelayMs: 120,
    models: {
      provider: 'custom',
      providers: [
        {
          slug: 'custom',
          models: ['recorded-model', 'another-model', 'custom-model-id'],
          is_current: true,
        },
        { slug: 'unconfigured', models: ['not-this-provider'] },
      ],
    },
  });
  services.relay = await createRelay({
    dataDir: await mkdtemp(join(tmpdir(), 'nekodot-browser-relay-')),
    jwtSecret: 'isolated-browser-test-secret',
    publicUrl: relayUrl,
  });
  await services.relay.app.listen({ host: '127.0.0.1', port: relayPort });
});

test.afterAll(async () => {
  services.connection?.close();
  services.secondConnection?.close();
  if (services.secondApp) await services.secondApp.close();
  if (services.app) await services.app.close();
  if (services.relay) await services.relay.app.close();
  if (services.fake) await services.fake.close();
});

test('a real browser account pairs a node, configures a bot, and runs private chat controls', async ({
  page,
  context,
}) => {
  await context.grantPermissions(['clipboard-read', 'clipboard-write']);
  await page.goto('/');

  await expect(page.getByRole('heading', { name: '创建账号' })).toBeVisible();
  const userEmail = `browser-${randomUUID()}@example.test`;
  await page.getByLabel('邮箱').fill(userEmail);
  await page.getByLabel('密码').fill('nekodot-browser-password');
  await page.getByRole('button', { name: '继续' }).click();

  await expect(page.getByRole('heading', { name: '添加电脑' })).toBeVisible();
  await expect(page.locator('.pair-wait')).toContainText(/[A-HJ-NP-Z2-9]{4}-[A-HJ-NP-Z2-9]{4}/);
  const pairText = await page.locator('.pair-wait').innerText();
  const code = pairText.match(/[A-HJ-NP-Z2-9]{4}-[A-HJ-NP-Z2-9]{4}/)?.[0];
  expect(code).toBeTruthy();
  await page.getByRole('button', { name: '复制命令' }).click();
  await expect(page.getByRole('button', { name: '已复制' })).toBeVisible();
  const pairCommand = await page.locator('.command-box code').innerText();
  expect(pairCommand).toContain(code!);
  await page.getByRole('button', { name: '延长 30 分钟' }).click();
  await expect(page.locator('.pair-wait')).toContainText(/59:\d{2}|60:00/);
  await expect(page.locator('.command-box code')).toHaveText(pairCommand);
  for (const width of [390, 768, 1440]) {
    await page.setViewportSize({ width, height: 900 });
    await expect(page.getByRole('button', { name: '延长 30 分钟' })).toBeInViewport();
    expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(
      true,
    );
    await page.screenshot({ path: `docs/evidence/pairing-fix-${width}.png`, fullPage: true });
  }
  await page.getByRole('button', { name: '返回团队', exact: true }).click();
  await expect(page.locator('.pair-page')).toHaveCount(0);
  await expect(
    page.getByRole('heading', { name: '还没有绑定服务器。', exact: true }),
  ).toBeVisible();
  await page
    .locator('.welcome-panel')
    .getByRole('button', { name: '添加电脑', exact: true })
    .click();
  await expect(page.locator('.command-box code')).toHaveText(pairCommand);
  await page.screenshot({ path: 'docs/evidence/phase1-pairing.png', fullPage: true });

  services.nodeHome = await mkdtemp(join(tmpdir(), 'nekodot-browser-node-'));
  services.credentials = await pairNode(services.nodeHome, relayUrl, code!, 'Acceptance computer');
  const profiles = new Set(['default']);
  const permissionModes = new Map<string, ApprovalMode>();
  const runtime: HermesRuntime = {
    ...recordedManagementRuntime(
      services.fake!.url,
      hermesKey,
      services.nodeHome!,
      services.fake!.pluginCatalog,
    ),
    start: async () => {},
    close: async () => {},
    approvalMode: async (profile) => permissionModes.get(profile) ?? 'manual',
    configureProvider: async () => {},
    configureBot: async (bot: Bot, create: boolean, mode?: ApprovalMode) => {
      if (mode) permissionModes.set(bot.botId, mode);
      if (create && !profiles.has(bot.botId)) {
        const response = await fetch(services.fake!.url + '/test/profiles', {
          method: 'POST',
          headers: { Authorization: `Bearer ${hermesKey}`, 'Content-Type': 'application/json' },
          body: JSON.stringify({ profile: bot.botId }),
        });
        expect(response.status).toBe(201);
        profiles.add(bot.botId);
      }
    },
    api: async (profile) => new HermesApi(`${services.fake!.url}/p/${profile}`, hermesKey),
    models: async () => new HermesApi(`${services.fake!.url}/p/default`, hermesKey).models(),
  };
  services.app = new NodeApplication(services.nodeHome, runtime);
  const connectNode = () => {
    services.connection = connectRelay({
      credentials: services.credentials!,
      handleRpc: (request) => services.app!.handle(request),
      onReady: () => services.app?.activities(),
    });
    services.app!.onEvent = services.connection.event;
    services.app!.onLive = services.connection.live;
  };
  connectNode();
  await services.app.resume();

  await expect(page.locator('.node-picker summary')).toContainText('Acceptance computer', {
    timeout: 12000,
  });
  await page.locator('.sidebar-header button[aria-label="设置"]').click();
  await expect(page.getByRole('heading', { name: '模型提供方' })).toBeVisible();
  await page.getByLabel('API 地址').fill('https://models.example.test/v1');
  await page.getByLabel('API Key').fill('browser-only-secret-9472');
  await page.getByLabel('默认模型（可选）').fill('recorded-model');
  await page.getByRole('button', { name: '保存并获取模型' }).click();
  await expect(page.getByText('已保存密钥 ····9472').first()).toBeVisible();
  await expect(page.getByLabel('可用模型').locator('option')).toHaveCount(4);
  await expect(page.getByLabel('可用模型')).not.toContainText('not-this-provider');
  await page.getByLabel('可用模型').selectOption('another-model');
  await expect(page.getByLabel('默认模型（可选）')).toHaveValue('another-model');
  await page.getByLabel('默认模型（可选）').fill('recorded-model');
  await page.getByRole('button', { name: '保存并获取模型' }).click();
  await expect(page.locator('.success-message')).toBeVisible();
  expect(JSON.stringify(services.app.database.setting('provider'))).not.toContain(
    'browser-only-secret-9472',
  );
  await page.screenshot({ path: 'docs/evidence/phase1-settings.png', fullPage: true });

  await page.getByRole('button', { name: '返回团队' }).click();
  await page.setViewportSize({ width: 1440, height: 900 });
  const resizer = page.getByRole('separator', { name: '调整侧栏宽度' });
  await resizer.focus();
  await resizer.press('ArrowRight');
  await expect(resizer).toHaveAttribute('aria-valuenow', '300');
  const logoBox = await page.locator('.sidebar-header .wordmark').boundingBox();
  expect(logoBox!.x).toBeGreaterThanOrEqual(0);
  expect(logoBox!.x + logoBox!.width).toBeLessThan(300);
  await expect(page.getByRole('heading', { name: '团队', exact: true })).toHaveCount(0);
  await page.setViewportSize({ width: 1024, height: 600 });
  await page.getByRole('button', { name: '新建 bot' }).last().click();
  await page.screenshot({ path: 'docs/evidence/phase1-new-bot.png', animations: 'disabled' });
  await page.getByLabel('名字').fill('Mochi');
  await page.getByLabel('它负责什么？').fill('A friendly assistant for everyday planning.');
  await page.getByLabel(/工具权限/).selectOption('smart');
  await expect(page.getByLabel('可用模型')).toBeVisible();
  await page.getByLabel('可用模型').selectOption('recorded-model');
  await expect(page.getByLabel('模型', { exact: true })).toHaveValue('recorded-model');
  await page.getByRole('button', { name: '高级设置' }).click();
  await page.locator('.advanced-field input').fill('mochi');
  expect(
    await page.locator('.dialog-body').evaluate((el) => el.scrollHeight > el.clientHeight),
  ).toBe(true);
  await expect(page.locator('.bot-dialog footer')).toBeInViewport();
  await page.screenshot({
    path: 'docs/evidence/fix-bot-dialog-scroll.png',
    animations: 'disabled',
  });
  await page.locator('.bot-dialog').getByRole('button', { name: '创建 Mochi' }).click();
  const bot = services.app.database.bots()[0]!;
  expect(permissionModes.get(bot.botId)).toBe('smart');
  await page.setViewportSize({ width: 1440, height: 900 });
  await expect(page.getByRole('button', { name: /Mochi/ }).first()).toBeVisible();
  await page.getByRole('button', { name: /Mochi/ }).first().click();
  await expect(page.locator('.chat-header')).toContainText('Mochi');

  const composer = page.locator('.composer textarea');
  const originalHandle = services.app.handle.bind(services.app);
  let dropFirstReply = true;
  let sendAttempts = 0;
  services.app.handle = async (request) => {
    const result = await originalHandle(request);
    if (dropFirstReply && request.method === 'messages.send') {
      dropFirstReply = false;
      sendAttempts += 1;
      services.connection!.close();
      await delay(20);
    }
    return result;
  };
  await page.evaluate(() => window.dispatchEvent(new PageTransitionEvent('pageshow')));
  await composer.fill('Hello, please give me a short greeting.');
  await composer.press('Enter');
  await expect(page.locator('.inline-error')).toBeVisible();
  await expect(composer).toHaveValue('Hello, please give me a short greeting.');
  expect(sendAttempts).toBe(1);
  services.app.handle = originalHandle;
  connectNode();
  await expect(page.locator('.chat-status')).not.toContainText('电脑离线');
  await composer.press('Enter');
  await expect(page.locator('.stream-cursor')).toBeVisible();
  await page.screenshot({
    path: 'docs/evidence/phase1-chat-streaming.png',
    animations: 'disabled',
  });
  await expect(page.locator('.bot-copy').filter({ hasText: 'NEKODOT_PHASE0_OK' })).toBeVisible({
    timeout: 10000,
  });
  expect(services.fake!.inspectRuns()).toHaveLength(1);
  await expect(page.locator('.run-banner')).toHaveCount(0, { timeout: 10000 });

  const pageErrors: string[] = [];
  page.on('pageerror', (error) => pageErrors.push(error.message));
  const resumedSocket = page.waitForEvent('websocket', { timeout: 10000 });
  await page.evaluate(() => window.dispatchEvent(new PageTransitionEvent('pageshow')));
  const socket = await resumedSocket;
  expect(socket.url()).toContain('/ws/client');
  await expect(page.locator('.chat-status')).not.toContainText('电脑离线');
  expect(pageErrors).toEqual([]);

  await composer.fill('Please demonstrate a protected-file approval.');
  await composer.press('Enter');
  await expect(page.locator('.approval-card')).toBeVisible({ timeout: 10000 });
  await page.screenshot({ path: 'docs/evidence/phase1-approval.png', fullPage: true });
  const pendingRun = services.fake!.inspectRuns().at(-1)!.runId;
  await page.reload();
  await expect(
    page.locator('.approval-card').last().getByRole('button', { name: '允许一次' }),
  ).toBeVisible();
  await expect(page.locator('.run-banner')).toContainText('等你确认');
  services.connection!.close();
  await services.app.close();
  services.app = new NodeApplication(services.nodeHome, runtime);
  connectNode();
  await services.app.resume();
  await expect(page.locator('.chat-status')).toContainText('等你确认');
  expect(services.fake!.inspectRuns().at(-1)!.runId).toBe(pendingRun);
  await page.getByRole('button', { name: '允许一次' }).click();
  await expect(page.locator('.bot-copy').filter({ hasText: 'NEKODOT_APPROVAL_OK' })).toBeVisible({
    timeout: 10000,
  });
  await expect(page.locator('.run-banner')).toHaveCount(0, { timeout: 10000 });
  await page.locator('.tool-summary').first().click();
  await expect(page.locator('.tool-result')).toBeVisible();
  await page.screenshot({
    path: 'docs/evidence/phase1-tools-expanded.png',
    animations: 'disabled',
  });

  await composer.fill('Please demonstrate an approval denial and do not retry.');
  await composer.press('Enter');
  await expect(
    page.locator('.approval-card').last().getByRole('button', { name: '拒绝' }),
  ).toBeVisible({ timeout: 10000 });
  await page.locator('.approval-card').last().getByRole('button', { name: '拒绝' }).click();
  await expect(page.locator('.bot-copy').filter({ hasText: 'denied by the user' })).toBeVisible({
    timeout: 10000,
  });
  await expect(page.locator('.run-banner')).toHaveCount(0, { timeout: 10000 });

  await composer.fill('Please start a long task so I can stop it.');
  await composer.press('Enter');
  await expect(page.locator('.tool-card').filter({ hasText: 'terminal' }).last()).toBeVisible({
    timeout: 10000,
  });
  await page.getByRole('button', { name: /停止/ }).click();
  await expect(page.locator('.message-state').filter({ hasText: '已停止' })).toBeVisible({
    timeout: 10000,
  });
  await expect(page.locator('.run-banner')).toHaveCount(0, { timeout: 10000 });

  await composer.fill('Please demonstrate Hermes steer with a same run instruction.');
  await composer.press('Enter');
  await expect(page.locator('.tool-card').filter({ hasText: 'sleep 8' })).toBeVisible({
    timeout: 10000,
  });
  const sameRun = services.fake!.inspectRuns().at(-1)!;
  await page.reload();
  await expect(page.locator('.run-banner')).toContainText('正在运行工具');
  services.connection!.close();
  await expect(page.locator('.chat-status')).toContainText('电脑离线');
  connectNode();
  await expect(page.locator('.run-banner')).toContainText('正在运行工具');
  await composer.fill('Keep the same run and explain the protected test result.');
  await composer.press('Enter');
  await expect(page.getByText('已向当前回合补充指令')).toBeVisible({ timeout: 5000 });
  await expect(page.locator('.bot-copy').filter({ hasText: 'NEKODOT_STEER_OK' })).toBeVisible({
    timeout: 10000,
  });
  const steered = services.fake!.inspectRuns().at(-1)!;
  expect(steered.runId).toBe(sameRun.runId);
  expect(steered.steers).toEqual(['Keep the same run and explain the protected test result.']);
  expect(steered.toolStarts).toBe(1);
  const allMessages = services.app.database.messages(
    services.app.database.conversations()[0]!.conversationId,
  );
  expect(
    allMessages.filter((message) => message.kind === 'tool').map((message) => message.content.tool),
  ).toContain('read_file');

  await page.reload();
  await expect(page.locator('.chat-header')).toContainText('Mochi');
  await expect(page.locator('.bot-copy').filter({ hasText: 'NEKODOT_STEER_OK' })).toBeVisible({
    timeout: 10000,
  });
  await page.locator('.bot-copy').filter({ hasText: 'NEKODOT_STEER_OK' }).scrollIntoViewIfNeeded();
  await page.setViewportSize({ width: 1440, height: 900 });
  await page.screenshot({ path: 'docs/evidence/phase1-chat-desktop.png', animations: 'disabled' });
  await page.setViewportSize({ width: 390, height: 844 });
  await expect(page.locator('.chat-column')).toBeVisible();
  const composerBox = await page.locator('.composer').boundingBox();
  expect(composerBox!.x + composerBox!.width).toBeLessThanOrEqual(390);
  expect(
    await page
      .locator('.message-scroll')
      .evaluate((element) => element.scrollWidth <= element.clientWidth),
  ).toBe(true);
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true);
  await page.screenshot({ path: 'docs/evidence/phase1-chat-mobile.png', animations: 'disabled' });
  await page.setViewportSize({ width: 768, height: 1000 });
  await expect(page.locator('.team-sidebar')).toBeHidden();
  await page.screenshot({ path: 'docs/evidence/phase1-chat-tablet.png', animations: 'disabled' });
  await page.getByRole('button', { name: '返回团队', exact: true }).click();
  await expect(page.locator('.team-sidebar')).toBeVisible();
  await page.screenshot({ path: 'docs/evidence/phase1-team.png', animations: 'disabled' });

  await page.setViewportSize({ width: 1440, height: 900 });
  services.connection!.close();
  await expect(page.locator('.chat-status')).toContainText('电脑离线');
  for (let index = 0; index < 1001; index++)
    services.app.database.putBot({ ...bot, displayName: 'Mochi restored' });
  connectNode();
  await expect(page.locator('.chat-header')).toContainText('Mochi restored');
  await expect(page.locator('.bot-copy').filter({ hasText: 'NEKODOT_STEER_OK' })).toBeVisible();
  await page.locator('.sidebar-header button[aria-label="设置"]').click();
  await page.getByLabel('切换主题', { exact: true }).click();
  await page.emulateMedia({ reducedMotion: 'reduce' });
  await page.getByRole('button', { name: 'English', exact: true }).click();
  await expect(page.getByRole('heading', { name: 'Model provider', exact: true })).toBeVisible();
  await page.screenshot({
    path: 'docs/evidence/phase1-settings-dark-en.png',
    animations: 'disabled',
    fullPage: true,
  });
  await page.getByRole('button', { name: 'Back to team' }).click();
  await page.screenshot({ path: 'docs/evidence/phase1-chat-dark-en.png', animations: 'disabled' });
  await page.locator('.chat-title').click();
  await page.locator('.bot-details').getByRole('button', { name: 'Edit bot', exact: true }).click();
  await page.getByLabel('Name', { exact: true }).fill('Mochi edited');
  await page.locator('.color-swatches button').nth(1).click();
  const permissionSelect = page.locator('.bot-dialog select').last();
  await permissionSelect.selectOption('off');
  await page.locator('.bot-dialog').getByRole('button', { name: 'Save', exact: true }).click();
  await expect(page.locator('.chat-title')).toContainText('Mochi edited');
  expect(permissionModes.get(bot.botId)).toBe('off');
  await page.locator('.chat-title').click();
  await page.locator('.bot-details').getByRole('button', { name: 'Edit bot', exact: true }).click();
  await expect(page.locator('.bot-dialog select').last()).toHaveValue('off');
  await page.locator('.bot-dialog select').last().selectOption('manual');
  await page.locator('.bot-dialog').getByRole('button', { name: 'Save', exact: true }).click();
  expect(permissionModes.get(bot.botId)).toBe('manual');
  await page.reload();
  await expect(page.locator('.chat-title')).toContainText('Mochi edited');
  const conversationId = services.app.database.conversations()[0]!.conversationId;
  for (let index = 0; index < 55; index++)
    services.app.database.putMessage({
      messageId: randomUUID(),
      conversationId,
      seq: 0,
      author: { type: 'user' },
      kind: 'text',
      status: 'done',
      createdAt: new Date().toISOString(),
      content: { text: `Earlier-history pagination note ${index}` },
    });
  await page.reload();
  await expect(page.getByRole('button', { name: 'Load earlier messages' })).toBeVisible();
  await page.getByRole('button', { name: 'Load earlier messages' }).click();
  await expect(page.locator('.bot-copy').filter({ hasText: 'NEKODOT_STEER_OK' })).toBeVisible();

  await page.locator('.sidebar-header button[aria-label="Settings"]').click();
  await page.getByRole('button', { name: 'Add computer', exact: true }).click();
  await expect(page.getByRole('heading', { name: 'Add computer', exact: true })).toBeVisible();
  await expect(page.locator('.pair-wait')).toContainText(/[A-HJ-NP-Z2-9]{4}-[A-HJ-NP-Z2-9]{4}/);
  const secondPairText = await page.locator('.pair-wait').innerText();
  const secondCode = secondPairText.match(/[A-HJ-NP-Z2-9]{4}-[A-HJ-NP-Z2-9]{4}/)?.[0];
  expect(secondCode).toBeTruthy();
  const secondHome = await mkdtemp(join(tmpdir(), 'nekodot-browser-second-node-'));
  const secondCredentials = await pairNode(secondHome, relayUrl, secondCode!, 'Second computer');
  services.secondApp = new NodeApplication(secondHome, runtime);
  services.secondConnection = connectRelay({
    credentials: secondCredentials,
    handleRpc: (request) => services.secondApp!.handle(request),
    onReady: () => services.secondApp!.activities(),
  });
  services.secondApp.onEvent = services.secondConnection.event;
  services.secondApp.onLive = services.secondConnection.live;
  await services.secondApp.resume();
  await expect(page.locator('.node-picker summary')).toContainText('Second computer', {
    timeout: 10000,
  });
  await expect(page.locator('.bot-row')).toHaveCount(0);
  await expect(page.locator('.welcome-panel')).toContainText('Create a bot');
  await page.getByLabel('Computer', { exact: true }).click();
  await page.getByRole('menuitemradio', { name: /Acceptance computer/ }).click();
  await expect(page.locator('.chat-title')).toContainText('Mochi edited');
  await expect(page.locator('.bot-row')).toHaveCount(1);
  await page.locator('.sidebar-header button[aria-label="Settings"]').click();
  await page
    .locator('.node-row')
    .filter({ hasText: 'Second computer' })
    .getByRole('button', { name: 'Unpair computer', exact: true })
    .click();
  await page
    .locator('.confirm-strip')
    .getByRole('button', { name: 'Unpair computer', exact: true })
    .click();
  await expect(page.locator('.node-row')).toHaveCount(1);
  await page.getByRole('button', { name: 'Back to team' }).click();
  await page.locator('.chat-title').click();
  await page.locator('.bot-details').getByRole('button', { name: 'Edit bot', exact: true }).click();
  await page.locator('.bot-dialog').getByRole('button', { name: 'Archive', exact: true }).click();
  await expect(page.locator('.bot-row')).toHaveCount(0);
  await page.reload();
  await expect(page.locator('.bot-row')).toHaveCount(0);

  await page.locator('.sidebar-header button[aria-label="Settings"]').click();
  await page.getByRole('button', { name: 'Sign out', exact: true }).click();
  await page.getByRole('button', { name: 'Already have an account? Sign in' }).click();
  await page.getByLabel('Email', { exact: true }).fill(userEmail);
  await page.getByLabel('Password', { exact: true }).fill('nekodot-browser-password');
  await page.getByRole('button', { name: 'Continue', exact: true }).click();
  await expect(page.locator('.team-sidebar')).toBeVisible();
  await expect(page.locator('.node-menu button[role="menuitemradio"]')).toHaveCount(1);
  await expect(page.locator('.bot-row')).toHaveCount(0);

  expect(
    services.app.database.messages(services.app.database.conversations()[0]!.conversationId).length,
  ).toBeGreaterThan(15);
  expect(services.app.database.setting('provider')).toMatchObject({ apiKeyLast4: '9472' });
  expect(services.fake!.inspectRuns().filter((run) => run.profile === bot.botId)).toHaveLength(5);
  await delay(20);
});
