import { mkdtemp } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { expect, it } from 'vitest';
import type { UsageRecord, Bot } from '@nekodot/protocol';
import { NodeDatabase } from './database';
import { NodeUsage } from './usage';
import type { HermesRuntime } from './hermes/runtime';

it('attributes group turns sharing a private session by native execution and retries unacknowledged batches', async () => {
  const db = new NodeDatabase(await mkdtemp(join(tmpdir(), 'nekodot-usage-')));
  const bot: Bot = {
    botId: 'nk-aaaaaa',
    displayName: 'Blue',
    handle: 'blue',
    avatar: { shape: 'dot', color: '#347BDD' },
    role: '',
    model: 'gpt-6.1-sol',
    archived: false,
    createdAt: new Date().toISOString(),
  };
  db.putBot(bot);
  db.putConversation({
    conversationId: 'private',
    kind: 'dm',
    botId: bot.botId,
    createdAt: bot.createdAt,
  });
  db.putGroup(
    {
      groupId: 'group',
      name: 'Research',
      botIds: [bot.botId, 'nk-bbbbbb'],
      leadBotId: bot.botId,
      archived: false,
      createdAt: bot.createdAt,
    },
    { conversationId: 'group-chat', kind: 'group', groupId: 'group', createdAt: bot.createdAt },
  );
  db.saveHermesSession({
    conversationId: 'private',
    botId: bot.botId,
    storedSessionId: 'native',
    replayEpoch: 'e',
    lastSequence: 0,
  });
  db.saveRun({
    conversationId: 'group-chat',
    botId: bot.botId,
    groupId: 'group',
    runId: 'admitted',
    inputMessageId: 'in',
    state: 'thinking',
    lastSeq: 0,
  });
  db.db.exec('CREATE TABLE routines(data TEXT)');
  const tokens = { input: 100, output: 20, cacheRead: 400, cacheWrite: 0 };
  const native = [
    {
      seq: 1,
      id: 'call',
      at: Date.now() / 1000,
      tokens,
      sessionId: 'native',
      executionId: 'admission:admitted',
      lineage: ['native'],
    },
  ];
  const schedule = { ...native[0]!, seq: 2, id: 'cron-call', jobId: 'job' };
  let scheduled = false;
  const runtime = {
    gateway: () => ({
      rpc: async (name: string, params: { session_id: string; arg: string }) => {
        expect(name).toBe('command.dispatch');
        expect(params.session_id).toBe('native');
        return {
          output: JSON.stringify(
            scheduled ? [schedule] : JSON.parse(params.arg).after ? [] : native,
          ),
        };
      },
    }),
    management: {
      request: async () => [{ id: 'job', name: 'Scheduled report' }],
    },
  } as unknown as HermesRuntime;
  const usage = new NodeUsage(db, runtime);
  const batches: UsageRecord[][] = [];
  let reject = true;
  usage.publish = async (rows) => {
    if (reject) throw new Error('disconnected');
    batches.push(rows);
  };
  usage.online(true);
  await expect(usage.sync()).rejects.toThrow('disconnected');
  expect(db.setting('usage-cursor:' + bot.botId)).toBeUndefined();
  reject = false;
  await usage.sync();
  expect(batches[0]![0]!.entity).toMatchObject({ kind: 'group', name: 'Research', group: true });
  expect(batches[0]![0]!.tokens).toEqual(tokens);
  expect(db.setting('usage-cursor:' + bot.botId)).toBe(1);
  await usage.sync();
  expect(batches[1]).toEqual([]);
  // The same schedule before and after adding a webhook stays in one statistics item.
  const collectSchedule = async () => {
    scheduled = true;
    await usage.sync();
    return batches.at(-1)![0]!.entity;
  };
  const beforeWebhook = await collectSchedule();
  db.db.prepare('INSERT INTO routines VALUES(?)').run(
    JSON.stringify({
      routineId: 'hook-id',
      botId: bot.botId,
      name: 'Scheduled report',
      cronJobId: 'job',
      route: 'hook-route',
    }),
  );
  const afterWebhook = await collectSchedule();
  expect(beforeWebhook.id).toBe(bot.botId + ':cron:job');
  expect(afterWebhook.id).toBe(beforeWebhook.id);
  expect(afterWebhook.kind).toBe('routine');
  await usage.close();
  db.db.close();
});
