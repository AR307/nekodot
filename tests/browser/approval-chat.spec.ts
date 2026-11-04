import { expect, test } from '@playwright/test';
import { randomUUID } from 'node:crypto';
import { mkdtemp } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { recordedManagementRuntime, startFakeHermes } from '@nekodot/fake-hermes';
import { createRelay } from '../../apps/relay/src/server';
import { NodeApplication } from '../../apps/node/src/app';
import { connectRelay } from '../../apps/node/src/connection';
import { pairNode } from '../../apps/node/src/pair';
import { seedVerifiedAccount } from '../support/account';
import type { HermesRuntime } from '../../apps/node/src/hermes/runtime';

test('recorded approvals persist and collapse in private and group chats', async ({ page }) => {
  test.setTimeout(90000);
  const home = await mkdtemp(join(tmpdir(), 'nekodot-approval-chat-'));
  const key = randomUUID();
  const schedule: string[] = [];
  const fake = await startFakeHermes({
    fixturesDirectory: join(process.cwd(), 'docs/fixtures'),
    profiles: ['default'],
    apiKey: key,
    allowProfileCreate: true,
    eventDelayMs: 20,
    scenarioFor: () => schedule.shift(),
  });
  const relay = await createRelay({
    dataDir: join(home, 'relay'),
    jwtSecret: randomUUID(),
    publicUrl: 'http://127.0.0.1',
    webDirectory: join(process.cwd(), 'apps/web/dist'),
  });
  const relayUrl = await relay.app.listen({ host: '127.0.0.1', port: 0 });
  let app: NodeApplication | undefined;
  let connection: ReturnType<typeof connectRelay> | undefined;
  try {
    const email = `approval-${randomUUID()}@example.test`;
    const password = randomUUID();
    await seedVerifiedAccount(relay.database, email, password);
    const login = await relay.app.inject({
      method: 'POST',
      url: '/api/auth/login',
      payload: { email, password },
    });
    const token = login.json().token as string;
    const pairing = await relay.app.inject({
      method: 'POST',
      url: '/api/pairing-codes',
      headers: { authorization: 'Bearer ' + token },
    });
    const credentials = await pairNode(
      join(home, 'node'),
      relayUrl,
      pairing.json().code,
      'Approval QA',
    );
    const runtime: HermesRuntime = {
      ...recordedManagementRuntime(fake.url, key, home, fake.pluginCatalog),
      start: async () => {},
      close: async () => {},
      approvalMode: async () => 'manual',
      configureBot: async (bot, create) => {
        if (create)
          await fetch(fake.url + '/test/profiles', {
            method: 'POST',
            headers: { Authorization: 'Bearer ' + key, 'Content-Type': 'application/json' },
            body: JSON.stringify({ profile: bot.botId }),
          });
      },
    };
    app = new NodeApplication(join(home, 'node'), runtime);
    await app.handle({
      method: 'providers.set',
      params: {
        kind: 'custom',
        name: 'Recorded approval QA',
        baseUrl: 'https://example.test/v1',
        apiKey: 'test-only',
      },
    });
    const sourceId = (await app.providers.list()).sources[0]!.sourceId;
    for (const name of ['Maple', 'Willow'])
      await app.bots.create({
        sourceId,
        displayName: name,
        handle: name.toLowerCase(),
        role: 'Approval QA',
        model: 'recorded-model',
        avatar: { shape: 'dot', color: '#E8603C' },
      });
    const bots = app.database.bots();
    app.groups.create({
      name: 'Approval group',
      botIds: bots.map((bot) => bot.botId),
      leadBotId: bots[0]!.botId,
    });
    connection = connectRelay({
      version: 'development',
      credentials,
      handleRpc: (request) => app!.handle(request),
      onReady: () => app!.activities(),
    });
    app.onEvent = connection.event;
    app.onLive = connection.live;
    await app.resume();
    await page.addInitScript(
      ({ token, nodeId }) => {
        localStorage.setItem('nekodot-token', token);
        localStorage.setItem('nekodot-node', nodeId);
      },
      { token, nodeId: credentials.nodeId },
    );
    await page.goto(relayUrl);

    for (const kind of ['dm', 'group'] as const) {
      const conversation = app.database.conversations().find((item) => item.kind === kind)!;
      await page.evaluate(
        ({ nodeId, conversationId }) => {
          localStorage.setItem('nekodot-conversation-' + nodeId, conversationId);
        },
        { nodeId: credentials.nodeId, conversationId: conversation.conversationId },
      );
      await page.reload();
      const composer = page.locator('.composer textarea');
      for (const [scenario, button, result] of [
        ['runs-tools-approval', '允许一次', '已允许一次'],
        ['runs-approval-deny', '拒绝', '已拒绝'],
      ]) {
        schedule.push(scenario!);
        await composer.fill(scenario!);
        await composer.press('Enter');
        const card = page.locator('.approval-card').last();
        await expect(card.getByRole('button', { name: button!, exact: true })).toBeEnabled();
        await page.reload();
        await expect(card.getByRole('button', { name: button!, exact: true })).toBeEnabled();
        await card.getByRole('button', { name: button!, exact: true }).click();
        await expect(card.getByRole('status')).toContainText(result!);
        await expect(card.getByRole('button')).toHaveCount(0);
        await expect(page.locator('.run-banner')).toHaveCount(0);
        await page.reload();
        await expect(card.getByRole('status')).toContainText(result!);
        await expect(card.getByRole('button')).toHaveCount(0);
      }
    }
  } finally {
    connection?.close();
    await app?.close();
    await relay.app.close();
    await fake.close();
  }
});
