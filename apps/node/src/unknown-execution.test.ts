import { createServer } from 'node:http';
import { mkdtemp } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { randomUUID } from 'node:crypto';
import { setTimeout as delay } from 'node:timers/promises';
import { expect, it } from 'vitest';
import { recordedManagementRuntime, startFakeHermes } from '@nekodot/fake-hermes';
import { rpcRequestSchema, type Bot, type Conversation } from '@nekodot/protocol';
import { NodeApplication } from './app';
import { HermesApi } from './hermes/api';
import type { HermesRuntime } from './hermes/runtime';

it.each(['dm', 'group'] as const)(
  '%s preserves a lost execution across restart until Stop acknowledges it, then accepts a new task',
  async (kind) => {
    const key = 'recovery-test-only';
    const home = await mkdtemp(join(tmpdir(), 'nekodot-unknown-execution-'));
    const profiles = ['default', 'nk-abcdef', 'nk-ghijkl'];
    const recorded = await startFakeHermes({
      fixturesDirectory: join(process.cwd(), 'docs/fixtures'),
      profiles,
      apiKey: key,
      eventDelayMs: 1,
    });
    let recovered = false;
    let refuseResolution = true;
    const resolutions: unknown[] = [];
    const unexpected: string[] = [];
    const server = createServer(async (request, response) => {
      response.setHeader('Content-Type', 'application/json');
      if (request.headers.authorization !== 'Bearer ' + key) {
        response.writeHead(401).end('{}');
        return;
      }
      if (request.method === 'GET' && request.url === '/v1/runs/lost-run') {
        response.end(
          JSON.stringify({
            run_id: 'lost-run',
            status: 'unknown',
            admission_id: 'lost-admission',
            execution_generation: 4,
            output: '',
            pending_controls: [],
          }),
        );
        return;
      }
      if (request.method === 'POST' && request.url === '/v1/runs/lost-run/resolve-unknown') {
        let body = '';
        for await (const part of request) body += String(part);
        resolutions.push(JSON.parse(body));
        if (refuseResolution) {
          response.writeHead(503).end(JSON.stringify({ error: { code: 'storage_unavailable' } }));
        } else {
          recovered = true;
          response.end(
            JSON.stringify({ run_id: 'lost-run', status: 'terminal', outcome: 'interrupted' }),
          );
        }
        return;
      }
      unexpected.push(request.method + ' ' + request.url);
      response.writeHead(409).end(JSON.stringify({ error: { code: 'unknown_execution' } }));
    });
    await new Promise<void>((resolve) => server.listen(0, '127.0.0.1', resolve));
    const address = server.address();
    if (!address || typeof address === 'string') throw new Error('Missing test address');
    const recoveryUrl = 'http://127.0.0.1:' + address.port;
    const runtime: HermesRuntime = {
      ...recordedManagementRuntime(recorded.url, key, home, recorded.pluginCatalog),
      start: async () => {},
      close: async () => {},
      approvalMode: async () => 'manual',
      configureBot: async () => {},
      api: async (profile) =>
        new HermesApi(recovered ? recorded.url + '/p/' + profile : recoveryUrl, key),
    };
    let app = new NodeApplication(home, runtime);
    const request = (method: string, params: unknown) => rpcRequestSchema.parse({ method, params });
    const createdAt = new Date().toISOString();
    try {
      const source = await app.providers.set({
        kind: 'custom',
        name: 'Recorded API',
        apiKey: 'test-only',
        baseUrl: 'https://api.example.test/v1',
      });
      const bot: Bot = {
        botId: 'nk-abcdef',
        displayName: 'Recovery Bot',
        handle: 'recovery',
        avatar: { shape: 'dot', color: '#E8603C' },
        role: 'Assistant',
        model: 'test-model',
        sourceId: source.sourceId,
        archived: false,
        createdAt,
      };
      app.database.putBot(bot);
      app.database.putBot({ ...bot, botId: 'nk-ghijkl', handle: 'teammate' });
      const dm: Conversation = {
        conversationId: 'private-chat',
        kind: 'dm',
        botId: bot.botId,
        createdAt,
      };
      app.database.putConversation(dm);
      let conversation: Conversation = dm;
      if (kind === 'group') {
        const group = {
          groupId: 'recovery-group',
          name: 'Recovery group',
          botIds: ['nk-abcdef', 'nk-ghijkl'],
          leadBotId: bot.botId,
          archived: false,
          createdAt,
        };
        conversation = {
          conversationId: 'group-chat',
          kind: 'group',
          groupId: group.groupId,
          createdAt,
        };
        app.database.putGroup(group, conversation);
        app.database.saveChain({
          notificationId: 'lost-chain',
          conversationId: conversation.conversationId,
          group,
          roster: app.database.bots(),
          queue: ['nk-ghijkl'],
          count: 1,
          cursorByBot: {},
          active: true,
          currentBotId: bot.botId,
        });
      }
      app.database.putMessage(
        {
          messageId: 'partial-reply',
          conversationId: conversation.conversationId,
          seq: 0,
          author: { type: 'bot', id: bot.botId },
          kind: 'text',
          status: 'streaming',
          createdAt,
          content: { text: 'Already completed work stays here.' },
        },
        { runId: 'lost-run' },
        {
          conversationId: conversation.conversationId,
          botId: bot.botId,
          runId: 'lost-run',
          ...(kind === 'group' ? { groupId: 'recovery-group' } : {}),
          lastSeq: 3,
          state: 'tool',
          inputMessageId: 'original-task',
          textMessageId: 'partial-reply',
        },
      );
      await app.resume();
      expect(app.database.runs()[0]?.state).toBe('unknown');
      expect(recorded.inspectRuns()).toHaveLength(0);
      await expect(
        app.handle(
          request('messages.send', {
            conversationId: conversation.conversationId,
            text: 'Do not lose this draft.',
            clientMsgId: randomUUID(),
          }),
        ),
      ).rejects.toMatchObject({ code: 'conflict', message: expect.stringContaining('Click Stop') });
      expect(app.database.messages(conversation.conversationId)).toHaveLength(1);
      await app.close();
      app = new NodeApplication(home, runtime);
      await app.resume();
      expect(app.database.runs()[0]?.state).toBe('unknown');
      expect(app.database.messages(conversation.conversationId)).toHaveLength(1);

      const stop = () =>
        app.handle(request('runs.stop', { conversationId: conversation.conversationId }));
      await expect(stop()).rejects.toMatchObject({ code: 'unavailable' });
      expect(app.database.runs()[0]?.state).toBe('unknown');
      if (kind === 'group')
        expect(app.database.chain(conversation.conversationId)?.queue).toEqual(['nk-ghijkl']);
      refuseResolution = false;
      await stop();
      expect(resolutions).toEqual([
        { admission_id: 'lost-admission', execution_generation: 4 },
        { admission_id: 'lost-admission', execution_generation: 4 },
      ]);
      expect(unexpected).toEqual([]);
      expect(app.database.runs()).toHaveLength(0);
      expect(app.database.chain(conversation.conversationId)).toBeUndefined();
      expect(app.database.message('partial-reply')).toMatchObject({
        status: 'cancelled',
        content: { text: 'Already completed work stays here.' },
      });
      expect(recorded.inspectRuns()).toHaveLength(0);

      await app.handle(
        request('messages.send', {
          conversationId: conversation.conversationId,
          text: 'runs-basic',
          clientMsgId: randomUUID(),
        }),
      );
      await expect.poll(() => app.database.runs().length).toBe(0);
      expect(recorded.inspectRuns()).toHaveLength(1);
      expect(recorded.inspectRuns()[0]).toMatchObject({
        profile: bot.botId,
        sessionId: 'nk_dm_private-chat',
      });
      expect(app.database.messages(conversation.conversationId)).toEqual(
        expect.arrayContaining([
          expect.objectContaining({
            kind: 'text',
            status: 'done',
            content: { text: 'NEKODOT_PHASE0_OK' },
          }),
        ]),
      );
    } finally {
      await app.close();
      server.closeAllConnections();
      await new Promise<void>((resolve) => server.close(() => resolve()));
      await recorded.close();
      await delay(0);
    }
  },
);
