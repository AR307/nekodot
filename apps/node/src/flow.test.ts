import { mkdtemp } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { afterEach, expect, it } from 'vitest';
import { flowSnapshotSchema } from '@nekodot/protocol';
import { NodeDatabase, type GroupChainRecord, type RunRecord } from './database';
import { ExecutionFlows } from './flow';

const databases: NodeDatabase[] = [];
afterEach(() => {
  for (const db of databases.splice(0)) db.db.close();
});
async function scene() {
  const db = new NodeDatabase(await mkdtemp(join(tmpdir(), 'nekodot-flow-')));
  databases.push(db);
  db.putConversation({
    conversationId: 'dm',
    kind: 'dm',
    botId: 'nk-aaaaaa',
    createdAt: new Date().toISOString(),
  });
  db.saveHermesSession({
    conversationId: 'dm',
    botId: 'nk-aaaaaa',
    storedSessionId: 'session',
    replayEpoch: 'epoch',
    lastSequence: 0,
  });
  const run: RunRecord = {
    conversationId: 'dm',
    botId: 'nk-aaaaaa',
    runId: 'first',
    storedSessionId: 'session',
    lastSeq: 0,
    state: 'thinking',
    inputMessageId: 'user',
  };
  return { db, run, flow: new ExecutionFlows(db) };
}

it('shows real call identities, overlapping tools, approval and reply without copying contents', async () => {
  const { db, run, flow } = await scene();
  flow.start(run);
  flow.phase(run, 'thinking', 1); // generating arguments is not executing a tool
  expect(flow.get('dm')!.steps.map((s) => s.kind)).toEqual(['bot', 'thinking']);
  flow.tool(run, 'read-1', 'read_file', 'read-message');
  flow.tool(run, 'search-2', 'web_search', 'search-message');
  const calls = flow.get('dm')!.steps.filter((s) => s.tool);
  expect(calls[0]!.after).toEqual(calls[1]!.after);
  expect(calls.map((s) => s.state)).toEqual(['running', 'running']);
  flow.toolEnd(run, 'search-2', 'done', 4);
  flow.prompt(run, 'approval', 'permission', 'approval-card');
  expect(calls[0]!.state).toBe('waiting');
  flow.settle(run, 'approval', 'permission', true);
  flow.toolEnd(run, 'read-1', 'failed', 6);
  flow.phase(run, 'reply', 7, 'reply-message');
  const before = db.head();
  flow.phase(run, 'reply', 8, 'reply-message');
  expect(db.head()).toBe(before);
  flow.finish(run, 'done');
  expect(flow.get('dm')!.steps.find((s) => s.kind === 'approval')!.state).toBe('cancelled');
  expect(flow.get('dm')!.steps.filter((s) => s.kind === 'reply')).toHaveLength(1);
  expect(flowSnapshotSchema.parse(flow.get('dm'))).toEqual(flow.get('dm'));
  expect(new ExecutionFlows(db).get('dm')).toEqual(flow.get('dm'));
});

it('keeps the current graph while queued or steered, replaces it only on actual start, and clears on session switch', async () => {
  const { db, run, flow } = await scene();
  flow.start(run);
  const seq = db.head();
  flow.start({ ...run, inputMessageId: 'steer' });
  flow.start({ ...run, runId: 'second', queue: 'queued' });
  expect(db.head()).toBe(seq);
  flow.tool(run, 'script', 'terminal', 'tool-message');
  flow.finish(run, 'done');
  expect(flow.get('dm')!.steps.at(-1)!.state).toBe('unknown');
  flow.start({ ...run, runId: 'second', queue: 'started' });
  expect(flow.get('dm')!.steps.every((s) => s.runId === 'second')).toBe(true);
  db.saveHermesSession({ ...db.hermesSession('dm')!, storedSessionId: 'new-session' });
  expect(flow.get('dm')).toBeNull();
  flow.sessionChanged('dm');
  expect(flow.get('dm')!.steps).toEqual([]);
});

it('keeps A to B to A as three real group turns, queue avatars only, and actual final state', async () => {
  const { db, run, flow } = await scene();
  db.putConversation({
    conversationId: 'group-chat',
    kind: 'group',
    groupId: 'group',
    createdAt: new Date().toISOString(),
  });
  const chain: GroupChainRecord = {
    conversationId: 'group-chat',
    notificationId: 'chain',
    group: {
      groupId: 'group',
      name: 'Team',
      botIds: ['nk-aaaaaa', 'nk-bbbbbb'],
      leadBotId: 'nk-aaaaaa',
      createdAt: new Date().toISOString(),
      archived: false,
    },
    roster: [],
    queue: ['nk-bbbbbb'],
    count: 1,
    cursorByBot: {},
    active: true,
  };
  db.saveChain(chain);
  const first = { ...run, conversationId: 'group-chat', groupId: 'group' };
  flow.start(first);
  expect(flow.get('group-chat')!.queuedBotIds).toEqual(['nk-bbbbbb']);
  expect(flow.get('group-chat')!.steps.some((s) => s.botId === 'nk-bbbbbb')).toBe(false);
  flow.finish(first, 'done');
  const second = { ...first, botId: 'nk-bbbbbb', runId: 'second' };
  chain.queue = ['nk-aaaaaa'];
  db.saveChain(chain);
  flow.start(second);
  flow.finish(second, 'done');
  chain.queue = [];
  db.saveChain(chain);
  flow.start({ ...first, runId: 'third' });
  expect(
    flow
      .get('group-chat')!
      .steps.filter((s) => s.kind === 'bot')
      .map((s) => s.botId),
  ).toEqual(['nk-aaaaaa', 'nk-bbbbbb', 'nk-aaaaaa']);
  flow.finish({ ...first, runId: 'third' }, 'cancelled');
  flow.group(chain, 'cancelled');
  expect(flow.get('group-chat')!.state).toBe('cancelled');
  expect(flow.get('group-chat')!.queuedBotIds).toEqual([]);
});
