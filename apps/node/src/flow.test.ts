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
  db.saveTask({
    taskId: 'task',
    conversationId: 'dm',
    botId: 'nk-aaaaaa',
    title: 'Requirement',
    inputMessageId: 'user',
    executionId: 'first',
    source: 'chat',
    state: 'running',
    createdAt: new Date().toISOString(),
    updatedAt: new Date().toISOString(),
  });
  const run: RunRecord = {
    role: 'execution',
    taskId: 'task',
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
  flow.settle(run, 'approval', 'permission', 'unknown');
  expect(flow.get('dm')!.steps.at(-1)!.state).toBe('unknown');
  flow.settle(run, 'approval', 'permission', 'cancelled');
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

it('keeps the current graph while queued or steered, replaces it only on actual start, and keeps another task isolated', async () => {
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
  expect(flow.get('dm')!.steps.every((s) => s.runId === 'second')).toBe(true);
  db.saveTask({ ...db.task('task')!, taskId: 'other' });
  flow.start({ ...run, taskId: 'other', runId: 'third' });
  expect(flow.get('dm', 'task')!.steps.every((s) => s.runId === 'second')).toBe(true);
  expect(flow.get('dm', 'other')!.steps.every((s) => s.runId === 'third')).toBe(true);
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
    taskId: 'g-task',
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
  db.saveTask({
    ...db.task('task')!,
    taskId: 'g-task',
    conversationId: 'group-chat',
    source: 'group',
    groupChainId: 'chain',
  });
  db.saveChain(chain);
  const first = {
    ...run,
    conversationId: 'group-chat',
    groupId: 'group',
    groupChainId: 'chain',
    taskId: 'g-task',
  };
  flow.start(first);
  flow.plan(first, {
    revision: 1,
    todos: [{ id: 'task', content: 'Find sources', status: 'in_progress' }],
  });
  flow.tool(first, 'search', 'web_search', 'search-message');
  flow.toolEnd(first, 'search', 'done', 2);
  flow.plan(first, {
    revision: 2,
    todos: [{ id: 'task', content: 'Find sources', status: 'completed' }],
  });
  expect(flow.get('group-chat')!.queuedBotIds).toEqual(['nk-bbbbbb']);
  expect(flow.get('group-chat')!.steps.some((s) => s.botId === 'nk-bbbbbb')).toBe(false);
  flow.finish(first, 'done');
  const second = { ...first, botId: 'nk-bbbbbb', runId: 'second' };
  chain.queue = ['nk-aaaaaa'];
  db.saveChain(chain);
  flow.start(second);
  flow.plan(second, {
    revision: 1,
    todos: [{ id: 'task', content: 'Analyse sources', status: 'in_progress' }],
  });
  flow.tool(second, 'analyse', 'execute_code', 'analysis-message');
  expect(flow.get('group-chat')!.steps.find((s) => s.tool === 'execute_code')!.parentStepId).toBe(
    'second:plan:task',
  );
  expect(flow.get('group-chat')!.steps.find((s) => s.title === 'Find sources')!.state).toBe('done');
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

it('groups actual actions beneath native plan items without pre-executing pending items', async () => {
  const { db, run, flow } = await scene();
  flow.start(run);
  flow.tool(run, 'plan-call', 'todo_list', 'plan-message');
  flow.toolEnd(run, 'plan-call', 'done', 2);
  flow.plan(run, {
    revision: 1,
    todos: [
      { id: 'read', content: 'Read data', status: 'in_progress' },
      { id: 'write', content: 'Write report', status: 'pending' },
      { id: 'check', content: 'Check report', status: 'pending', parent: 'write' },
    ],
  });
  flow.tool(run, 'read-call', 'read_file', 'read-message');
  expect(flow.get('dm')!.steps.find((s) => s.tool === 'read_file')!.parentStepId).toBe(
    'first:plan:read',
  );
  expect(flow.get('dm')!.steps.find((s) => s.title === 'Write report')!.state).toBe('pending');
  expect(flow.get('dm')!.steps.find((s) => s.title === 'Check report')!.parentStepId).toBe(
    'first:plan:write',
  );
  flow.toolEnd(run, 'read-call', 'done', 4);
  flow.plan(run, {
    revision: 2,
    todos: [
      { id: 'read', content: 'Read data', status: 'completed' },
      { id: 'write', content: 'Write report', status: 'in_progress' },
      { id: 'check', content: 'Check report', status: 'pending', parent: 'write' },
    ],
  });
  flow.tool(run, 'write-call', 'write_file', 'write-message');
  const write = flow.get('dm')!.steps.find((s) => s.tool === 'write_file')!;
  expect(write.parentStepId).toBe('first:plan:write');
  expect(write.after.every((id) => !id.includes(':plan:'))).toBe(true);
  flow.toolEnd(run, 'write-call', 'done', 6);
  flow.finish(run, 'done');
  expect(flow.get('dm')!.steps.find((s) => s.title === 'Read data')!.state).toBe('done');
  expect(flow.get('dm')!.steps.find((s) => s.title === 'Write report')!.state).toBe('unknown');
  expect(flow.get('dm')!.steps.find((s) => s.title === 'Check report')!.state).toBe('pending');
  expect(flowSnapshotSchema.parse(new ExecutionFlows(db).get('dm'))).toEqual(flow.get('dm'));
  flow.start({ ...run, runId: 'next' });
  expect(flow.get('dm')!.steps.some((s) => s.kind === 'plan')).toBe(false);
});
