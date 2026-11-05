import { mkdtemp } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { setTimeout as delay } from 'node:timers/promises';
import { expect, it } from 'vitest';
import { startFakeHermes, recordedManagementRuntime } from '@nekodot/fake-hermes';
import type { RpcResult } from '@nekodot/protocol';
import { NodeApplication } from './app';
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
    additionalFixtures: ['group-failed'],
    scenarioFor: () => {
      if (!failNext) return undefined;
      failNext = false;
      return 'group-failed';
    },
  });
  let failNext = false;
  const runtime: HermesRuntime = {
    ...recordedManagementRuntime(fake.url, key, home, fake.pluginCatalog),
    start: async () => {},
    close: async () => {},
    approvalMode: async () => 'manual',
    syncRules: async () => {},
    configureBot: async (bot) => {
      await fetch(fake.url + '/test/profiles', {
        method: 'POST',
        headers: { Authorization: 'Bearer ' + key, 'Content-Type': 'application/json' },
        body: JSON.stringify({ profile: bot.botId }),
      });
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
        sourceId: (await app.providers.list()).sources[0]!.sourceId,
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
      params: {
        kind: 'custom',
        name: 'Journey API',
        baseUrl: 'https://example.test/v1',
        apiKey: 'recorded-test-only',
      },
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
    expect(fake.inspectRuns()).toHaveLength(2);
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
    expect(fake.inspectRuns()).toHaveLength(3);
  } finally {
    runtime.management.close();
    await app.close();
    await fake.close();
  }
});

it('A message sent during the introduction is queued behind it once, even before Hermes admits it', async () => {
  const home = await mkdtemp(join(tmpdir(), 'nekodot-welcome-queue-'));
  const key = 'welcome-queue-test-only';
  const fake = await startFakeHermes({
    fixturesDirectory: join(process.cwd(), 'docs/fixtures'),
    profiles: ['default'],
    apiKey: key,
    allowProfileCreate: true,
    eventDelayMs: 10,
  });
  const base = recordedManagementRuntime(fake.url, key, home, fake.pluginCatalog);
  // A new Bot's gateway is cold: hold the introduction before Hermes admits it.
  let admit!: () => void;
  const admission = new Promise<void>((resolve) => (admit = resolve));
  const submits: Record<string, unknown>[] = [];
  const runtime: HermesRuntime = {
    ...base,
    start: async () => {},
    close: async () => {},
    approvalMode: async () => 'manual',
    syncRules: async () => {},
    configureBot: async (bot) => {
      await fetch(fake.url + '/test/profiles', {
        method: 'POST',
        headers: { Authorization: 'Bearer ' + key, 'Content-Type': 'application/json' },
        body: JSON.stringify({ profile: bot.botId }),
      });
    },
    gateway: (profile) => {
      const gateway = base.gateway(profile);
      return Object.assign(Object.create(gateway) as typeof gateway, {
        rpc: (async (method, params, timeoutMs) => {
          if (method === 'prompt.submit') {
            await admission;
            submits.push(params);
          }
          return gateway.rpc(method, params, timeoutMs);
        }) as typeof gateway.rpc,
      });
    },
  };
  const app = new NodeApplication(home, runtime);
  try {
    await app.handle({
      method: 'providers.set',
      params: {
        kind: 'custom',
        name: 'Journey API',
        baseUrl: 'https://example.test/v1',
        apiKey: 'recorded-test-only',
      },
    });
    const created = (await app.handle({
      method: 'bots.create',
      params: {
        sourceId: (await app.providers.list()).sources[0]!.sourceId,
        displayName: 'Maple',
        handle: 'maple',
        role: 'Helpful assistant',
        model: 'recorded-model',
        avatar: { shape: 'dot', color: '#E8603C' },
      },
    })) as RpcResult<'bots.create'>;
    const conversationId = created.conversation.conversationId;
    const params = {
      conversationId,
      text: 'hello, please read my notes first.',
      clientMsgId: 'early',
    };
    const sent = app.handle({ method: 'messages.send', params });
    // The client resends the same draft after its request timed out.
    const resent = app.handle({ method: 'messages.send', params });
    await delay(50);
    expect(app.database.runs()[0]?.runId).toBeUndefined();
    expect(app.database.byClient('early')).toBeUndefined();
    admit();
    const [first, second] = (await Promise.all([sent, resent])) as { messageId: string }[];
    expect(second).toEqual(first);

    const deadline = Date.now() + 8000;
    while (app.database.runs().length && Date.now() < deadline) await delay(10);
    expect(app.database.runs()).toHaveLength(0);
    const history = app.database.messages(conversationId);
    expect(history[0]).toMatchObject({ status: 'done', content: { welcome: true } });
    expect(history.filter((m) => m.author.type === 'user')).toMatchObject([
      { messageId: first!.messageId, content: { text: params.text, queue: 'running' } },
    ]);
    // The introduction is submitted first; the user's message is a native queued prompt after it.
    expect(submits).toMatchObject([
      { text: expect.stringContaining('You have just been created') },
      { text: params.text, input_id: first!.messageId, queued: true },
    ]);
    expect(submits[0]).not.toHaveProperty('queued');
    expect(fake.inspectRuns()).toHaveLength(2);
    expect(fake.inspectRuns().every((run) => !run.steers.length)).toBe(true);
  } finally {
    runtime.management.close();
    await app.close();
    await fake.close();
  }
});
