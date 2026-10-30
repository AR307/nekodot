import { mkdtemp } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { randomUUID } from 'node:crypto';
import { setTimeout as delay } from 'node:timers/promises';
import { describe, expect, it } from 'vitest';
import { startFakeHermes, recordedManagementRuntime } from '@nekodot/fake-hermes';
import {
  rpcRequestSchema,
  type Bot,
  type Conversation,
  type TaskNotification,
} from '@nekodot/protocol';
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
      models: {
        provider: 'custom',
        providers: [{ slug: 'custom', models: ['test-model'], is_current: true }],
      },
    });
    const home = await mkdtemp(join(tmpdir(), 'nekodot-node-journey-'));
    const profiles = new Set(['default']);
    let provider: ProviderInput | undefined;
    const runtime: HermesRuntime = {
      ...recordedManagementRuntime(relay.url, testKey, home, relay.pluginCatalog),
      start: async () => {},
      close: async () => {},
      approvalMode: async () => 'manual',
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
      models: async () => new HermesApi(relay.url + '/p/default', testKey).models(),
    };
    const app = new NodeApplication(home, runtime);
    const notifications: TaskNotification[] = [];
    app.notifications.onSend = (signal) => notifications.push(signal);
    const request = (method: string, params: unknown) => rpcRequestSchema.parse({ method, params });
    try {
      expect((await app.extensions.list('skills')).entries.length).toBeGreaterThan(0);
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

      const { bot, conversation } = (await app.handle(
        request('bots.create', {
          displayName: 'Mochi',
          handle: 'mochi',
          avatar: { shape: 'dot', color: '#E8603C' },
          role: 'A practical assistant',
          model: 'test-model',
        }),
      )) as { bot: Bot; conversation: Conversation };
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
      expect(notifications.map((signal) => signal.kind)).toEqual(['completed']);

      await send('runs-clarify');
      await waitFor(() =>
        messages().some((message) => message.kind === 'question' && message.status === 'streaming'),
      );
      const question = messages().find(
        (message) => message.kind === 'question' && message.status === 'streaming',
      );
      if (question?.kind !== 'question') throw new Error('Native question was not shown.');
      expect(question.content.choices).toContain('Teal');
      expect(
        app.database.runs().find((run) => run.conversationId === conversation.conversationId)
          ?.state,
      ).toBe('waiting_question');
      await expect(send('This must not become a steer while waiting')).rejects.toThrow();
      await app.handle(
        request('questions.respond', { messageId: question.messageId, answer: 'Amber' }),
      );
      await waitFor(() =>
        messages().some(
          (message) =>
            message.kind === 'text' &&
            message.status === 'done' &&
            message.content.text === 'NEKODOT_CLARIFY_OK Amber',
        ),
      );
      expect(messages().find((message) => message.messageId === question.messageId)).toMatchObject({
        status: 'done',
        content: { answer: 'Amber' },
      });
      await expect(
        app.handle(request('questions.respond', { messageId: question.messageId, answer: 'Teal' })),
      ).rejects.toThrow();

      const toolScenario = await send('runs-tools-approval');
      void toolScenario;
      await waitFor(() =>
        messages().some((message) => message.kind === 'approval' && message.status === 'streaming'),
      );
      const pending = messages().find(
        (message) => message.kind === 'approval' && message.status === 'streaming',
      );
      expect(pending?.kind).toBe('approval');
      expect(notifications.at(-1)?.kind).toBe('approval');
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
      ).toEqual(['clarify', 'read_file', 'patch']);
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

      const noticesBeforeStop = notifications.length;
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
      expect(notifications).toHaveLength(noticesBeforeStop);

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
      expect(relay.inspectRuns().filter((run) => run.profile === bot.botId)).toHaveLength(6);
      await waitFor(
        () =>
          !app.database.runs().some((run) => run.conversationId === conversation.conversationId),
      );
      const runText = app.database
        .messagesForRun(lastRun.runId)
        .filter(
          (message) =>
            (message.kind === 'text' || message.kind === 'commentary') &&
            message.author.type === 'bot',
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

describe('Node group journeys with the recorded Hermes HTTP service', () => {
  it('manages groups, relays recorded replies, resumes a run, and clears queued work on steer or stop', async () => {
    const schedule: string[] = [];
    const relay = await startFakeHermes({
      fixturesDirectory: join(process.cwd(), 'docs/fixtures'),
      profiles: ['default'],
      apiKey: testKey,
      allowProfileCreate: true,
      eventDelayMs: 5,
      additionalFixtures: [
        'group-lead',
        'group-target-1',
        'group-target-2',
        'group-researcher',
        'group-writer',
        'group-self-outsider',
        'group-nonfinal-mentions',
        'group-loop-researcher',
        'group-loop-writer',
        'group-steer',
        'group-stop',
        'group-failed',
      ],
      scenarioFor: () => schedule.shift(),
    });
    const home = await mkdtemp(join(tmpdir(), 'nekodot-node-group-'));
    const profiles = new Set(['default']);
    const runtime: HermesRuntime = {
      ...recordedManagementRuntime(relay.url, testKey, home, relay.pluginCatalog),
      start: async () => {},
      close: async () => {},
      approvalMode: async () => 'manual',
      configureProvider: async () => {},
      configureBot: async (bot: Bot) => {
        if (profiles.has(bot.botId)) return;
        const response = await fetch(relay.url + '/test/profiles', {
          method: 'POST',
          headers: { Authorization: 'Bearer ' + testKey, 'Content-Type': 'application/json' },
          body: JSON.stringify({ profile: bot.botId }),
        });
        expect(response.status).toBe(201);
        profiles.add(bot.botId);
      },
      api: async (profile) => new HermesApi(relay.url + '/p/' + profile, testKey),
      models: async () => ({ models: [] }),
    };
    let app = new NodeApplication(home, runtime);
    const request = (method: string, params: unknown) => rpcRequestSchema.parse({ method, params });
    const waitFor = async (condition: () => boolean) => {
      const started = Date.now();
      while (!condition()) {
        if (Date.now() - started > 8000) throw new Error('Timed out waiting for group replay.');
        await delay(10);
      }
    };
    try {
      await app.handle(
        request('providers.set', {
          kind: 'custom',
          apiKey: 'group-provider-secret',
          baseUrl: 'https://api.example.test/v1',
          defaultModel: 'test-model',
        }),
      );
      const createBot = async (displayName: string, handle: string) =>
        (await app.handle(
          request('bots.create', {
            displayName,
            handle,
            avatar: { shape: 'dot', color: '#E8603C' },
            role: 'Group specialist',
            model: 'test-model',
          }),
        )) as { bot: Bot };
      const lead = await createBot('Researcher', 'researcher');
      const writer = await createBot('Writer', 'writer');
      const reviewer = await createBot('Reviewer', 'reviewer');
      const privateConversation = app.database
        .conversations()
        .find((item) => item.kind === 'dm' && item.botId === lead.bot.botId);
      if (!privateConversation || privateConversation.kind !== 'dm')
        throw new Error('Lead private conversation missing.');
      const privateRunsBefore = relay.inspectRuns().length;
      schedule.push('runs-basic');
      await app.handle(
        request('messages.send', {
          conversationId: privateConversation.conversationId,
          text: 'Remember this private note: the project color is amber.',
          clientMsgId: randomUUID(),
        }),
      );
      await waitFor(() => relay.inspectRuns().length > privateRunsBefore);
      await waitFor(
        () =>
          !app.database
            .runs()
            .some((run) => run.conversationId === privateConversation.conversationId),
      );
      const privateSessionId = relay.inspectRuns().at(-1)?.sessionId;
      expect(privateSessionId).toBe(`nk_dm_${privateConversation.conversationId}`);

      const created = (await app.handle(
        request('groups.create', {
          name: 'Research room',
          botIds: [lead.bot.botId, writer.bot.botId],
          leadBotId: lead.bot.botId,
        }),
      )) as { group: { groupId: string } };
      const conversation = app.database
        .conversations()
        .find((item) => item.kind === 'group' && item.groupId === created.group.groupId);
      if (!conversation || conversation.kind !== 'group')
        throw new Error('Group conversation missing.');
      const groupRunOffset = relay.inspectRuns().length;

      const send = (text: string) =>
        app.handle(
          request('messages.send', {
            conversationId: conversation.conversationId,
            text,
            clientMsgId: randomUUID(),
          }),
        );
      const waitIdle = () =>
        waitFor(() => app.database.chain(conversation.conversationId) === undefined);
      schedule.push('group-lead');
      await app.handle(
        request('messages.send', {
          conversationId: conversation.conversationId,
          text: 'runs-basic',
          clientMsgId: randomUUID(),
        }),
      );
      await waitIdle();
      let groupRuns = relay
        .inspectRuns()
        .slice(groupRunOffset)
        .filter((run) => run.profile === lead.bot.botId || run.profile === writer.bot.botId);
      expect(groupRuns).toHaveLength(1);
      expect(groupRuns[0]?.profile).toBe(lead.bot.botId);
      expect(groupRuns[0]?.sessionId).toBe(privateSessionId);

      schedule.push('group-target-1', 'group-target-2');
      await app.handle(
        request('messages.send', {
          conversationId: conversation.conversationId,
          text: 'hello @writer @researcher @writer @outsider',
          clientMsgId: randomUUID(),
        }),
      );
      await waitIdle();
      groupRuns = relay
        .inspectRuns()
        .slice(groupRunOffset)
        .filter((run) => run.profile === lead.bot.botId || run.profile === writer.bot.botId);
      expect(groupRuns.map((run) => run.profile)).toEqual([
        lead.bot.botId,
        writer.bot.botId,
        lead.bot.botId,
      ]);
      expect(groupRuns.map((run) => run.sessionId)).toEqual([
        `nk_dm_${privateConversation.conversationId}`,
        `nk_dm_${
          app.database
            .conversations()
            .find((item) => item.kind === 'dm' && item.botId === writer.bot.botId)!.conversationId
        }`,
        `nk_dm_${privateConversation.conversationId}`,
      ]);
      expect(
        app.database
          .messages(conversation.conversationId)
          .filter((message) => message.kind === 'text').length,
      ).toBeGreaterThan(4);

      expect(groupRuns[1]?.input).toContain('New messages since your last turn:');
      expect(groupRuns[1]?.instructions).toContain('Researcher (@researcher) — Group specialist');
      expect(groupRuns[2]?.input).not.toContain('User: runs-basic');
      expect(groupRuns[2]?.input).toContain('Writer (@writer): PHASE2_TARGET_OK');
      await expect(
        app.handle(request('bots.archive', { botId: lead.bot.botId })),
      ).rejects.toMatchObject({ code: 'conflict' });

      let before = relay.inspectRuns().length;
      schedule.push('group-researcher', 'group-writer');
      await send('Start a member handoff.');
      await waitIdle();
      expect(
        relay
          .inspectRuns()
          .slice(before)
          .map((run) => run.profile),
      ).toEqual([lead.bot.botId, writer.bot.botId]);
      schedule.push('group-self-outsider');
      before = relay.inspectRuns().length;
      await send('Check mentions of self and outsiders.');
      await waitIdle();
      expect(relay.inspectRuns().slice(before)).toHaveLength(1);

      schedule.push('group-nonfinal-mentions');
      before = relay.inspectRuns().length;
      await send('Mention a teammate only in the progress note and terminal preview.');
      await waitIdle();
      const nonfinalRuns = relay.inspectRuns().slice(before);
      expect(nonfinalRuns).toHaveLength(1);
      const nonfinalMessages = app.database.messagesForRun(nonfinalRuns[0]!.runId);
      expect(
        nonfinalMessages.some(
          (message) => message.kind === 'commentary' && message.content.text.includes('@writer'),
        ),
      ).toBe(true);
      expect(
        nonfinalMessages.some(
          (message) => message.kind === 'tool' && message.content.preview.includes('@writer'),
        ),
      ).toBe(true);

      schedule.push('group-failed', 'group-writer');
      before = relay.inspectRuns().length;
      await send('@researcher @writer Continue if the first member fails.');
      await waitIdle();
      expect(relay.inspectRuns().slice(before)).toHaveLength(2);
      expect(
        app.database
          .messages(conversation.conversationId)
          .some(
            (message) =>
              message.kind === 'system' && message.content.text.includes('could not complete'),
          ),
      ).toBe(true);

      schedule.push('group-steer');
      before = relay.inspectRuns().length;
      await send('@researcher @writer Start the recorded steer task.');
      await waitFor(() => app.database.runs().some((run) => run.state === 'tool'));
      const activeId = app.database.runs()[0]!.runId;
      await app.close();
      app = new NodeApplication(home, runtime);
      await app.resume();
      expect(app.database.runs()[0]?.runId).toBe(activeId);
      expect(app.database.chain(conversation.conversationId)?.queue).toEqual([writer.bot.botId]);
      await send('Keep the same run and use the new final instruction.');
      await waitIdle();
      expect(relay.inspectRuns().slice(before)).toHaveLength(1);
      expect(relay.inspectRuns().at(-1)).toMatchObject({ runId: activeId, toolStarts: 1 });
      expect(relay.inspectRuns().at(-1)?.steers).toHaveLength(1);

      schedule.push('group-stop');
      before = relay.inspectRuns().length;
      await send('@researcher @writer Start a long task.');
      await waitFor(() => app.database.runs().some((run) => run.state === 'tool'));
      await app.handle(request('runs.stop', { conversationId: conversation.conversationId }));
      await waitFor(() => app.database.runs().length === 0);
      expect(app.database.chain(conversation.conversationId)).toBeUndefined();
      expect(relay.inspectRuns().slice(before)).toHaveLength(1);
      expect(
        app.database
          .messagesForRun(relay.inspectRuns().at(-1)!.runId)
          .find((message) => message.kind === 'tool')?.status,
      ).toBe('cancelled');

      before = relay.inspectRuns().length;
      schedule.push(
        'group-loop-researcher',
        'group-loop-writer',
        'group-loop-researcher',
        'group-loop-writer',
        'group-loop-researcher',
        'group-loop-writer',
      );
      await send('Follow the loop policy.');
      await app.handle(
        request('groups.update', {
          groupId: created.group.groupId,
          name: 'Edited research room',
          leadBotId: writer.bot.botId,
        }),
      );
      await waitIdle();
      expect(relay.inspectRuns().slice(before)).toHaveLength(6);
      expect(
        app.database
          .messages(conversation.conversationId)
          .some(
            (message) =>
              message.kind === 'system' && message.content.text.includes('paused after 6'),
          ),
      ).toBe(true);
      schedule.push('group-lead');
      before = relay.inspectRuns().length;
      await send('Reply without mentions.');
      await waitIdle();
      expect(relay.inspectRuns().slice(before)[0]?.profile).toBe(writer.bot.botId);
      expect(relay.inspectRuns().at(-1)?.input).toContain('Edited research room');

      const other = (await app.handle(
        request('groups.create', {
          name: 'Review room',
          botIds: [lead.bot.botId, reviewer.bot.botId],
          leadBotId: reviewer.bot.botId,
        }),
      )) as { group: { groupId: string } };
      const otherConversation = app.database
        .conversations()
        .find((item) => item.kind === 'group' && item.groupId === other.group.groupId)!;
      before = relay.inspectRuns().length;
      schedule.push('runs-tools-approval', 'group-lead', 'group-writer');
      await send('@researcher @writer Wait for the protected-file approval.');
      await waitFor(() => app.database.runs().some((run) => run.state === 'waiting_approval'));
      await app.handle(
        request('groups.update', {
          groupId: created.group.groupId,
          botIds: [lead.bot.botId, reviewer.bot.botId],
          leadBotId: reviewer.bot.botId,
        }),
      );
      expect(
        app.database.chain(conversation.conversationId)?.roster.map((bot) => bot.botId),
      ).toEqual([lead.bot.botId, writer.bot.botId]);
      await app.handle(
        request('messages.send', {
          conversationId: otherConversation.conversationId,
          text: 'Complete another group while the first one waits.',
          clientMsgId: randomUUID(),
        }),
      );
      await waitFor(() => !app.database.chain(otherConversation.conversationId));
      expect(app.database.runs()).toHaveLength(1);
      expect(app.database.runs()[0]?.state).toBe('waiting_approval');
      await app.close();
      app = new NodeApplication(home, runtime);
      await app.resume();
      expect(app.database.chain(conversation.conversationId)?.queue).toEqual([writer.bot.botId]);
      const approval = app.database
        .messages(conversation.conversationId)
        .find((message) => message.kind === 'approval' && message.status === 'streaming')!;
      await app.handle(
        request('approvals.respond', { messageId: approval.messageId, choice: 'once' }),
      );
      await waitIdle();
      expect(
        relay
          .inspectRuns()
          .slice(before)
          .map((run) => run.profile),
      ).toEqual([lead.bot.botId, reviewer.bot.botId, writer.bot.botId]);
      schedule.push('group-lead');
      await send('Use the updated members for this new message.');
      await waitIdle();
      expect(relay.inspectRuns().at(-1)?.profile).toBe(reviewer.bot.botId);
      await app.handle(request('groups.archive', { groupId: other.group.groupId }));
      await app.handle(request('groups.archive', { groupId: created.group.groupId }));
      expect(app.database.groups()).toHaveLength(0);
      expect(app.database.conversation(conversation.conversationId)).toBeDefined();
      await expect(send('Archived group')).rejects.toMatchObject({ code: 'not_found' });
      const privateRunsAfterGroup = relay.inspectRuns().length;
      schedule.push('runs-basic');
      await app.handle(
        request('messages.send', {
          conversationId: privateConversation.conversationId,
          text: 'Back in private chat, recall the note from our group conversation.',
          clientMsgId: randomUUID(),
        }),
      );
      await waitFor(() => relay.inspectRuns().length > privateRunsAfterGroup);
      await waitFor(
        () =>
          !app.database
            .runs()
            .some((run) => run.conversationId === privateConversation.conversationId),
      );
      expect(relay.inspectRuns().at(-1)?.sessionId).toBe(privateSessionId);
      await app.handle(request('bots.archive', { botId: lead.bot.botId }));
      expect(app.database.bot(lead.bot.botId)?.archived).toBe(true);
      expect(schedule).toHaveLength(0);
    } finally {
      await app.close();
      await relay.close();
    }
  });
});
