import { mkdtemp } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { setTimeout as delay } from 'node:timers/promises';
import { expect, it } from 'vitest';
import { startFakeHermes, recordedManagementRuntime } from '@nekodot/fake-hermes';
import type { RpcResult } from '@nekodot/protocol';
import { NodeApplication } from './app';
import { HermesApi } from './hermes/api';
import type { HermesRuntime } from './hermes/runtime';

it('A new profile introduces itself once, survives restart, and only explicitly retries a failed introduction', async () => {
  const home = await mkdtemp(join(tmpdir(), 'nekodot-welcome-journey-'));
  const key = 'welcome-test-only';
  const fake = await startFakeHermes({
    fixturesDirectory: join(process.cwd(), 'docs/fixtures'),
    profiles: ['default'],
    apiKey: key,
    allowProfileCreate: true,
    eventDelayMs: 10,
  });
  let failNext = false;
  const runtime: HermesRuntime = {
    ...recordedManagementRuntime(fake.url, key, home, fake.pluginCatalog),
    start: async () => {},
    close: async () => {},
    configureProvider: async () => {},
    approvalMode: async () => 'manual',
    models: async () => ({ models: ['recorded-model'] }),
    configureBot: async (bot) => {
      await fetch(fake.url + '/test/profiles', {
        method: 'POST',
        headers: { Authorization: 'Bearer ' + key, 'Content-Type': 'application/json' },
        body: JSON.stringify({ profile: bot.botId }),
      });
    },
    api: async (profile) => {
      const api = new HermesApi(fake.url + '/p/' + profile, key);
      if (failNext) {
        failNext = false;
        api.createRun = async () => {
          throw new Error('Installation journey: gateway temporarily unavailable');
        };
      }
      return api;
    },
  };
  let app = new NodeApplication(home, runtime);
  const wait = async () => {
    const deadline = Date.now() + 8000;
    while (app.database.runs().length && Date.now() < deadline) await delay(10);
    expect(app.database.runs()).toHaveLength(0);
  };
  const create = async (handle: string) =>
    (await app.handle({
      method: 'bots.create',
      params: {
        displayName: 'Maple',
        handle,
        role: 'Helpful assistant',
        model: 'recorded-model',
        avatar: { shape: 'dot', color: '#E8603C' },
      },
    })) as RpcResult<'bots.create'>;
  try {
    await app.handle({
      method: 'providers.set',
      params: { kind: 'custom', baseUrl: 'https://example.test/v1', apiKey: 'recorded-test-only' },
    });
    const first = await create('maple');
    const started = Date.now() + 8000;
    while (!app.database.runs()[0]?.runId && Date.now() < started) await delay(10);
    expect(app.database.runs()[0]?.runId).toBeTruthy();
    await app.close();
    app = new NodeApplication(home, runtime);
    await app.resume();
    await wait();
    const history = app.database.messages(first.conversation.conversationId);
    expect(history).toHaveLength(1);
    expect(history[0]).toMatchObject({
      author: { type: 'bot', id: first.bot.botId },
      status: 'done',
      content: { welcome: true },
    });
    expect(fake.inspectRuns()).toHaveLength(1);
    await app.close();
    app = new NodeApplication(home, runtime);
    await app.resume();
    await app.handle({ method: 'sync.snapshot', params: {} });
    await app.handle({ method: 'sync.since', params: { seq: 0 } });
    expect(app.database.messages(first.conversation.conversationId)).toEqual(history);
    expect(fake.inspectRuns()).toHaveLength(1);
    await expect(
      app.handle({ method: 'bots.welcome.retry', params: { messageId: history[0]!.messageId } }),
    ).rejects.toThrow('not waiting for a retry');

    failNext = true;
    const second = await create('cedar');
    await wait();
    const failed = app.database.messages(second.conversation.conversationId)[0]!;
    expect(failed).toMatchObject({
      status: 'failed',
      content: { welcome: true, failureReason: expect.any(String) },
    });
    expect(fake.inspectRuns()).toHaveLength(1);
    await app.handle({ method: 'bots.welcome.retry', params: { messageId: failed.messageId } });
    await expect(
      app.handle({ method: 'bots.welcome.retry', params: { messageId: failed.messageId } }),
    ).rejects.toThrow('not waiting for a retry');
    await wait();
    const retried = app.database.messages(second.conversation.conversationId);
    expect(retried).toHaveLength(2);
    expect(retried[0]).toMatchObject({ messageId: failed.messageId, status: 'failed' });
    expect(retried[1]).toMatchObject({ status: 'done', content: { welcome: true } });
    expect(retried.some((m) => m.author.type === 'user')).toBe(false);
    expect(fake.inspectRuns()).toHaveLength(2);
  } finally {
    runtime.management.close();
    await app.close();
    await fake.close();
  }
});
