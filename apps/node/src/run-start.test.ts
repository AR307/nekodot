import { mkdtemp } from 'node:fs/promises';
import { randomUUID } from 'node:crypto';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { setTimeout as delay } from 'node:timers/promises';
import { expect, it, vi } from 'vitest';
import { startFakeHermes, recordedManagementRuntime } from '@nekodot/fake-hermes';
import type { Bot, RpcResult } from '@nekodot/protocol';
import { NodeApplication } from './app';
import { NodeFault } from './fault';
import type { HermesRuntime } from './hermes/runtime';

async function setup(fixtures: string[]) {
  const key = 'run-start-test-only';
  const schedule: string[] = [];
  const fake = await startFakeHermes({
    fixturesDirectory: join(process.cwd(), 'tests/fixtures'),
    profiles: ['default'],
    apiKey: key,
    allowProfileCreate: true,
    eventDelayMs: 5,
    additionalFixtures: fixtures,
    scenarioFor: () => schedule.shift(),
  });
  const home = await mkdtemp(join(tmpdir(), 'nekodot-run-start-'));
  const base = recordedManagementRuntime(fake.url, key, home, fake.pluginCatalog);
  const hooks: {
    probeHangs: boolean;
    probes: number;
    submitFailure?: Error;
  } = { probeHangs: false, probes: 0 };
  // Live failure: Hermes `/api/model/set` probes the provider catalog and can outlast Node's 30 s abort.
  const request = base.management.request.bind(base.management);
  base.management.request = ((path: string, profile?: string, init?: RequestInit) => {
    if (hooks.probeHangs && path === '/api/model/set') {
      hooks.probes += 1;
      return new Promise(() => {});
    }
    return request(path, profile, init);
  }) as typeof base.management.request;
  const runtime: HermesRuntime = {
    ...base,
    start: async () => {},
    close: async () => {},
    approvalMode: async () => 'manual',
    syncRules: async () => {},
    configureBot: async (bot: Bot) => {
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
          const failure = hooks.submitFailure;
          if (method === 'prompt.submit' && failure) {
            hooks.submitFailure = undefined;
            throw failure;
          }
          return gateway.rpc(method, params, timeoutMs);
        }) as typeof gateway.rpc,
      });
    },
  };
  const app = new NodeApplication(home, runtime);
  const until = async (condition: () => boolean) => {
    const deadline = Date.now() + 8000;
    while (!condition() && Date.now() < deadline) await delay(10);
    expect(condition()).toBe(true);
  };
  const source = await app.providers.set({
    kind: 'custom',
    name: 'Run start API',
    baseUrl: 'https://api.example.test/v1',
    apiKey: 'run-start-source-test-only',
  });
  const create = async (displayName: string, handle: string) =>
    (await app.handle({
      method: 'bots.create',
      params: {
        sourceId: source.sourceId,
        displayName,
        handle,
        role: 'Group specialist',
        model: 'test-model',
        avatar: { shape: 'dot', color: '#E8603C' },
      },
    })) as RpcResult<'bots.create'>;
  const close = async () => {
    runtime.management.close();
    await app.close();
    await fake.close();
  };
  return { app, fake, hooks, schedule, until, create, close };
}

it('a relay turn never waits on the provider model probe: run start does not re-apply the model', async () => {
  const { app, fake, hooks, schedule, until, create, close } = await setup([
    'group-researcher',
    'group-writer',
  ]);
  try {
    const lead = (await create('Researcher', 'researcher')).bot;
    const writer = (await create('Writer', 'writer')).bot;
    await until(() => app.database.runs().length === 0);
    const { group } = (await app.handle({
      method: 'groups.create',
      params: { name: 'Relay', botIds: [lead.botId, writer.botId], leadBotId: lead.botId },
    })) as RpcResult<'groups.create'>;
    const conversation = app.database
      .conversations()
      .find((item) => item.kind === 'group' && item.groupId === group.groupId)!;

    hooks.probeHangs = true;
    const configured = vi.spyOn(app.providers, 'configureBot');
    const before = fake.inspectRuns().length;
    schedule.push('group-researcher', 'group-writer');
    await app.handle({
      method: 'messages.send',
      params: {
        conversationId: conversation.conversationId,
        text: 'Start a member handoff.',
        clientMsgId: randomUUID(),
      },
    });
    await until(() => app.database.chain(conversation.conversationId) === undefined);

    expect(
      fake
        .inspectRuns()
        .slice(before)
        .map((run) => run.profile),
    ).toEqual([lead.botId, writer.botId]);
    const history = app.database.messages(conversation.conversationId);
    expect(history.filter((message) => message.status === 'failed')).toEqual([]);
    expect(history.filter((message) => message.author.type === 'bot')).toHaveLength(2);
    expect(configured).not.toHaveBeenCalled();
    expect(hooks.probes).toBe(0);

    // A member whose run cannot start is reported, and the relay continues with the next member.
    const next = fake.inspectRuns().length;
    hooks.submitFailure = new Error('Hermes gateway request timed out');
    schedule.push('group-writer');
    await app.handle({
      method: 'messages.send',
      params: {
        conversationId: conversation.conversationId,
        text: '@everyone Continue when the lead cannot start.',
        clientMsgId: randomUUID(),
      },
    });
    await until(() => app.database.chain(conversation.conversationId) === undefined);
    expect(
      fake
        .inspectRuns()
        .slice(next)
        .map((run) => run.profile),
    ).toEqual([writer.botId]);
    const after = app.database.messages(conversation.conversationId).slice(history.length);
    expect(after).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          author: { type: 'bot', id: lead.botId },
          status: 'failed',
          content: expect.objectContaining({ failureCode: 'run_start' }),
        }),
        expect.objectContaining({ kind: 'system', status: 'done' }),
        expect.objectContaining({ author: { type: 'bot', id: writer.botId }, status: 'done' }),
      ]),
    );
  } finally {
    await close();
  }
});

it('a run that cannot start records a code the client localizes, and a timeout says so', async () => {
  const { app, hooks, until, create, close } = await setup([]);
  try {
    const { conversation } = await create('Maple', 'maple');
    await until(() => app.database.runs().length === 0);
    const send = async (failure: Error) => {
      hooks.submitFailure = failure;
      await app.handle({
        method: 'messages.send',
        params: {
          conversationId: conversation.conversationId,
          text: 'Summarize the notes.',
          clientMsgId: randomUUID(),
        },
      });
      await until(() => app.database.runs().length === 0);
      return app.database.messages(conversation.conversationId).at(-1)!;
    };
    expect(await send(new Error('Hermes gateway request timed out'))).toMatchObject({
      status: 'failed',
      content: {
        failureCode: 'run_start',
        failureReason: 'Could not start this run. Check the provider and try again.',
      },
    });
    expect(
      await send(new NodeFault('timeout', 'Hermes did not respond in time. Try again.')),
    ).toMatchObject({ status: 'failed', content: { failureCode: 'timeout' } });
    const other = await send(
      new NodeFault('invalid_params', 'Custom source has no saved credential'),
    );
    expect(other).toMatchObject({
      status: 'failed',
      content: { failureReason: 'Custom source has no saved credential' },
    });
    expect(other.kind === 'text' && other.content.failureCode).toBeUndefined();
  } finally {
    await close();
  }
});
