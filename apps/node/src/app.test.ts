import { mkdtemp } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { randomUUID } from 'node:crypto';
import { setTimeout as delay } from 'node:timers/promises';
import { describe, expect, it } from 'vitest';
import { startFakeHermes } from '@nekodot/fake-hermes';
import { rpcRequestSchema, type Bot } from '@nekodot/protocol';
import { NodeApplication } from './app';
import { HermesApi } from './hermes/api';
import type { HermesRuntime, ProviderInput } from './hermes/runtime';

const testKey = 'test-only-hermes-key';

describe('Node private-chat journeys with the recorded Hermes HTTP service', () => {
  it('creates a profile and DM, replays text, tool approval, denial, stop, idempotency, and in-run steer', async () => {
    const relay = await startFakeHermes({
      fixturesDirectory: join(process.cwd(), 'docs/fixtures'),
      profiles: ['default'],
      apiKey: testKey,
      allowProfileCreate: true,
      eventDelayMs: 30,
      models: { models: [{ id: 'test-model', name: 'Recorded test model' }] },
    });
    const home = await mkdtemp(join(tmpdir(), 'nekodot-node-journey-'));
    const profiles = new Set(['default']);
    let provider: ProviderInput | undefined;
    const runtime: HermesRuntime = {
      start: async () => {},
      close: async () => {},
      configureProvider: async (value) => {
        provider = value;
      },
      configureBot: async (bot: Bot) => {
        if (!profiles.has(bot.botId)) {
          const response = await fetch(relay.url + '/test/profiles', {
            method: 'POST',
            headers: { Authorization: 'Bearer ' + testKey, 'Content-Type': 'application/json' },
            body: JSON.stringify({ profile: bot.botId }),
          });
          expect(response.status).toBe(201);
          profiles.add(bot.botId);
        }
      },
      api: async (profile) => new HermesApi(relay.url + '/p/' + profile, testKey),
      models: async () =>
        await (
          await fetch(relay.url + '/p/default/api/model/options', {
            headers: { Authorization: 'Bearer ' + testKey },
          })
        ).json(),
    };
    const app = new NodeApplication(home, runtime);
    const request = (method: string, params: unknown) => rpcRequestSchema.parse({ method, params });
    try {
      const secret = 'provider-secret-never-returned';
      const configured = (await app.handle(
        request('providers.set', {
          kind: 'custom',
          apiKey: secret,
          baseUrl: 'https://api.example.test/v1',
          defaultModel: 'test-model',
        }),
      )) as { apiKeyLast4: string };
      expect(configured).toEqual({
        kind: 'custom',
        baseUrl: 'https://api.example.test/v1',
        defaultModel: 'test-model',
        apiKeyLast4: 'rned',
      });
      expect(JSON.stringify(app.database.setting('provider'))).not.toContain(secret);
      expect(provider?.apiKey).toBe(secret);

      const { bot } = (await app.handle(
        request('bots.create', {
          displayName: 'Mochi',
          handle: 'mochi',
          avatar: { shape: 'dot', color: '#E8603C' },
          role: 'A practical assistant',
          model: 'test-model',
        }),
      )) as { bot: Bot };
      const conversation = app.database.conversations()[0];
      if (!conversation) throw new Error('Bot conversation was not created.');
      expect(conversation).toMatchObject({ kind: 'dm', botId: bot.botId });
      expect(((await runtime.models()) as { models: unknown[] }).models).toHaveLength(1);

      const start = async (text: string) => {
        const clientMsgId = randomUUID();
        const result = (await app.handle(
          request('messages.send', {
            conversationId: conversation.conversationId,
            text,
            clientMsgId,
          }),
        )) as { messageId: string };
        expect(
          await app.handle(
            request('messages.send', {
              conversationId: conversation.conversationId,
              text,
              clientMsgId,
            }),
          ),
        ).toEqual(result);
        return result;
      };
      const waitFor = async (condition: () => boolean) => {
        const started = Date.now();
        while (!condition()) {
          if (Date.now() - started > 8000)
            throw new Error('Timed out waiting for the recorded Hermes journey.');
          await delay(10);
        }
      };
      const messages = () => app.database.messages(conversation.conversationId);
      const send = (text: string) =>
        app.handle(
          request('messages.send', {
            conversationId: conversation.conversationId,
            text,
            clientMsgId: randomUUID(),
          }),
        );

      const basic = await start('runs-basic');
      await waitFor(() =>
        messages().some(
          (message) =>
            message.kind === 'text' &&
            message.status === 'done' &&
            message.content.text === 'NEKODOT_PHASE0_OK',
        ),
      );
      expect(messages().find((message) => message.messageId === basic.messageId)?.author.type).toBe(
        'user',
      );

      const toolScenario = await send('runs-tools-approval');
      void toolScenario;
      await waitFor(() =>
        messages().some((message) => message.kind === 'approval' && message.status === 'streaming'),
      );
      const pending = messages().find(
        (message) => message.kind === 'approval' && message.status === 'streaming',
      );
      expect(pending?.kind).toBe('approval');
      if (pending?.kind !== 'approval') throw new Error('Approval card was not created.');
      await app.handle(
        request('approvals.respond', { messageId: pending.messageId, choice: 'once' }),
      );
      await waitFor(() =>
        messages().some(
          (message) =>
            message.kind === 'text' && message.content.text.includes('NEKODOT_APPROVAL_OK'),
        ),
      );
      expect(
        messages()
          .filter((message) => message.kind === 'tool')
          .map((message) => message.content.tool),
      ).toEqual(['read_file', 'patch']);
      expect(messages().find((message) => message.messageId === pending.messageId)?.status).toBe(
        'done',
      );

      await send('runs-approval-deny');
      await waitFor(() =>
        messages().some((message) => message.kind === 'approval' && message.status === 'streaming'),
      );
      const denied = messages().find(
        (message) => message.kind === 'approval' && message.status === 'streaming',
      );
      if (denied?.kind !== 'approval') throw new Error('Denial card was not created.');
      await app.handle(
        request('approvals.respond', { messageId: denied.messageId, choice: 'deny' }),
      );
      await waitFor(() =>
        messages().some(
          (message) =>
            message.kind === 'text' &&
            message.status === 'done' &&
            message.content.text.includes('denied by the user'),
        ),
      );
      expect(
        messages().find((message) => message.messageId === denied.messageId)?.content,
      ).toMatchObject({ choice: 'deny' });

      await send('runs-stop');
      await waitFor(() =>
        messages().some(
          (message) =>
            message.kind === 'tool' &&
            message.content.tool === 'terminal' &&
            message.status === 'streaming',
        ),
      );
      await app.handle(request('runs.stop', { conversationId: conversation.conversationId }));
      await waitFor(
        () =>
          !app.database.runs().some((run) => run.conversationId === conversation.conversationId),
      );
      expect(
        messages().some((message) => message.kind === 'text' && message.status === 'cancelled'),
      ).toBe(true);

      const steer = await send('same run steer approval');
      const steerMessage = steer as { messageId: string };
      await waitFor(() => {
        const input = messages().find((message) => message.messageId === steerMessage.messageId);
        const runId = input && app.database.messageRun(input.messageId);
        return (
          !!runId &&
          messages().some(
            (message) =>
              message.kind === 'tool' &&
              message.content.tool === 'terminal' &&
              app.database.messageRun(message.messageId) === runId,
          )
        );
      });
      const secondInstruction = await send('Please keep the same run and explain what you found.');
      expect(secondInstruction).toHaveProperty('messageId');
      const lastRun = relay.inspectRuns().at(-1)!;
      expect(lastRun.steers).toEqual(['Please keep the same run and explain what you found.']);
      expect(relay.inspectRuns().filter((run) => run.profile === bot.botId)).toHaveLength(5);
      await waitFor(
        () =>
          !app.database.runs().some((run) => run.conversationId === conversation.conversationId),
      );
      const runText = messages().filter(
        (message) => message.kind === 'text' && message.author.type === 'bot',
      );
      expect(runText.length).toBeGreaterThanOrEqual(2);
      expect(runText.at(-1)).toMatchObject({ content: { text: 'NEKODOT_STEER_OK' } });
      expect(relay.inspectRuns().at(-1)?.toolStarts).toBe(1);
      expect(runText.slice(-2).map((message) => message.status)).toEqual(['done', 'done']);
      expect(
        relay
          .inspectRuns()
          .filter((run) => run.profile === bot.botId)
          .at(-1)?.runId,
      ).toBe(lastRun.runId);

      const snapshot = (await app.handle(request('sync.snapshot', {}))) as { headSeq: number };
      const sync = (await app.handle(request('sync.since', { seq: 0 }))) as {
        events: unknown[];
        headSeq: number;
      };
      expect(snapshot.headSeq).toBe(sync.headSeq);
      expect(sync.events.length).toBeGreaterThan(10);
      expect(messages().length).toBeGreaterThan(10);
    } finally {
      await app.close();
      await relay.close();
    }
  });
});
