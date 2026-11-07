import { mkdtemp } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { expect, it, vi } from 'vitest';
import { recordedManagementRuntime, startFakeHermes } from '@nekodot/fake-hermes';
import type { LiveEvent, TaskNotification } from '@nekodot/protocol';
import { NodeApplication } from './app';
import type { HermesRuntime } from './hermes/runtime';
import type { GatewayFrame } from './hermes/gateway';

it('warns on silent execution, ignores other admissions, clears on progress and never interrupts', async () => {
  const home = await mkdtemp(join(tmpdir(), 'nekodot-stall-'));
  const recorded = await startFakeHermes({
    fixturesDirectory: join(process.cwd(), 'tests/fixtures'),
    apiKey: 'stall-test',
    profiles: ['default'],
  });
  const base = recordedManagementRuntime(recorded.url, 'stall-test', home, recorded.pluginCatalog);
  const gateway = base.gateway('nk-abcdef');
  const original = gateway.rpc.bind(gateway);
  const methods: string[] = [];
  const frames: GatewayFrame[] = [];
  let receipt = 'started';
  let seq = 0;
  gateway.rpc = async <T>(method: string, params: Record<string, unknown>): Promise<T> => {
    methods.push(method);
    if (method === 'session.events.since')
      return {
        events: frames.filter((frame) => frame.seq! > Number(params.last_sequence)),
        replay_epoch: 'stall-epoch',
        latest_seq: seq,
      } as T;
    if (method === 'prompt.receipt')
      return {
        status: receipt,
        admission_id: 'silent',
        outcome: 'completed',
        result: { final_response: 'finished' },
      } as T;
    return original<T>(method, params);
  };
  const runtime: HermesRuntime = {
    ...base,
    start: async () => {},
    close: async () => {},
    syncRules: async () => {},
    configureBot: async () => {},
    approvalMode: async () => 'manual',
    gateway: () => gateway,
  };
  const app = new NodeApplication(home, runtime);
  const live: LiveEvent[] = [];
  const notifications: TaskNotification[] = [];
  app.onLive = (event) => live.push(event);
  app.notifications.onSend = (event) => notifications.push(event);
  const createdAt = new Date().toISOString();
  app.database.putBot({
    botId: 'nk-abcdef',
    displayName: 'Silent Bot',
    handle: 'silent',
    avatar: { shape: 'dot', color: '#E8603C' },
    role: 'Assistant',
    model: 'test',
    archived: false,
    createdAt,
  });
  app.database.putConversation({
    conversationId: 'chat',
    kind: 'dm',
    botId: 'nk-abcdef',
    createdAt,
  });
  const session = await original<{
    session_id: string;
    stored_session_id: string;
    replay_epoch: string;
    last_sequence: number;
  }>('session.create', {
    source: 'gui',
    title: 'Silent test',
    hidden: true,
    follow_profile_config: true,
    request_id: 'silent-test',
  });
  app.database.saveRun({
    conversationId: 'chat',
    botId: 'nk-abcdef',
    runId: 'silent',
    sessionId: session.session_id,
    storedSessionId: session.stored_session_id,
    replayEpoch: session.replay_epoch,
    submissionId: 'submitted',
    inputMessageId: 'input',
    state: 'thinking',
    lastSeq: session.last_sequence,
  });
  seq = session.last_sequence;
  const realNow = Date.now.bind(Date);
  let offset = 0;
  const clock = vi.spyOn(Date, 'now').mockImplementation(() => realNow() + offset);
  try {
    await app.resume();
    await expect
      .poll(() => methods.filter((m) => m === 'session.events.since').length)
      .toBeGreaterThan(0);
    offset = 301_000;
    frames.push({ type: 'background.note', seq: ++seq, admission_id: 'other', payload: {} });
    await expect.poll(() => notifications.filter((n) => n.kind === 'stalled').length).toBe(1);
    expect(live.at(-1)).toMatchObject({ kind: 'activity', stalled: true, state: 'thinking' });
    expect(app.database.runs()).toHaveLength(1);
    frames.push({ type: 'progress', seq: ++seq, admission_id: 'silent', payload: {} });
    await expect.poll(() => live.at(-1)).toMatchObject({ kind: 'activity', state: 'thinking' });
    await expect
      .poll(() => live.at(-1) && 'stalled' in live.at(-1)!, { timeout: 5000 })
      .toBe(false);
    expect(app.database.db.prepare('SELECT count(*) as n FROM notification_outbox').get()?.n).toBe(
      0,
    );
    frames.push({
      type: 'approval.request',
      seq: ++seq,
      admission_id: 'silent',
      payload: { prompt_id: 'permission', command: 'echo safe', choices: ['once', 'deny'] },
    });
    await expect.poll(() => live.at(-1)).toMatchObject({ state: 'waiting_approval' });
    offset += 301_000;
    const beforeWait = methods.length;
    await expect.poll(() => methods.length, { timeout: 5000 }).toBeGreaterThan(beforeWait + 3);
    expect(notifications.filter((n) => n.kind === 'stalled')).toHaveLength(1);
    frames.push({
      type: 'approval.settled',
      seq: ++seq,
      admission_id: 'silent',
      payload: { prompt_id: 'permission' },
    });
    await expect.poll(() => live.at(-1)).toMatchObject({ state: 'thinking' });
    frames.push({
      type: 'clarify.request',
      seq: ++seq,
      admission_id: 'silent',
      payload: { prompt_id: 'answer', question: 'Which file?', choices: ['a', 'b'] },
    });
    await expect.poll(() => live.at(-1)).toMatchObject({ state: 'waiting_question' });
    offset += 301_000;
    const beforeQuestion = methods.length;
    await expect.poll(() => methods.length, { timeout: 5000 }).toBeGreaterThan(beforeQuestion + 3);
    expect(notifications.filter((n) => n.kind === 'stalled')).toHaveLength(1);
    receipt = 'terminal';
    await expect.poll(() => app.database.runs().length).toBe(0);
    expect(notifications.filter((n) => n.kind === 'stalled')).toHaveLength(1);
    expect(methods).not.toContain('prompt.cancel');
    expect(methods).not.toContain('prompt.submit');
  } finally {
    clock.mockRestore();
    await app.close();
    await recorded.close();
  }
});
