import { mkdtemp } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { expect, it, vi } from 'vitest';
import { NodeDatabase, type RunRecord } from '../database';
import { RunControls } from './controls';
import { ExecutionFlows } from '../flow';
import { Notifications } from '../notifications';
import type { HermesRuntime } from '../hermes/runtime';

it('answers a task A approval while task B is also working in the same chat, and restores both after reopen', async () => {
  const directory = await mkdtemp(join(tmpdir(), 'nekodot-tasks-'));
  let db = new NodeDatabase(directory);
  const runs: RunRecord[] = ['A', 'B'].map((id) => ({
    role: 'execution',
    taskId: id,
    executionId: id,
    conversationId: 'chat',
    botId: 'nk-bot',
    inputMessageId: 'input-' + id,
    runId: 'run-' + id,
    sessionId: 'session-' + id,
    executionGeneration: 1,
    lastSeq: 0,
    state: 'waiting_approval',
  }));
  for (const run of runs) db.saveRun(run);
  const rpc = vi.fn(async () => ({ status: 'resolved' }));
  const controls = new RunControls(
    db,
    { gateway: () => ({ rpc }) } as unknown as HermesRuntime,
    new ExecutionFlows(db),
    new Notifications(db),
    () => {},
    async () => {},
  );
  controls.restoreNativePrompts(runs[0]!, [
    { kind: 'approval', prompt_id: 'approve-A', execution_generation: 1 },
  ]);
  const approval = db.approval('run-A', 'approve-A')!;
  await controls.respondToApproval({ messageId: approval.messageId, choice: 'once' });
  expect(rpc).toHaveBeenCalledWith(
    'approval.respond',
    expect.objectContaining({ session_id: 'session-A', prompt_id: 'approve-A' }),
  );
  expect(db.runs().find((run) => run.taskId === 'B')?.state).toBe('waiting_approval');
  expect(db.message(approval.messageId)).toMatchObject({ taskId: 'A', taskRole: 'execution' });
  db.db.close();
  db = new NodeDatabase(directory);
  expect(db.runs().map((run) => run.inputMessageId)).toEqual(['input-A', 'input-B']);
  expect(db.taskMessages('A')).toHaveLength(1);
  expect(db.taskMessages('B')).toHaveLength(0);
  db.db.close();
});
