import { expect, it, vi } from 'vitest';
import type { NodeDatabase } from './database';
import type { HermesRuntime } from './hermes/runtime';
import { BotSessions } from './session-commands';

it('shows the live session alongside stored sessions without duplicating it', async () => {
  const rpc = vi.fn(async (_method: string, params: { scope: string }) => ({
    sessions:
      params.scope === 'live'
        ? [{ session_id: 'current', title: 'Current work', started_at: 20 }]
        : [
            { session_id: 'previous', title: 'Previous work', started_at: 10 },
            { session_id: 'current', title: 'Current work', started_at: 20 },
          ],
  }));
  const database = {
    conversations: () => [{ kind: 'dm', botId: 'bot', conversationId: 'dm' }],
    hermesSession: () => ({ storedSessionId: 'current' }),
  } as unknown as NodeDatabase;
  const sessions = new BotSessions(database, {
    gateway: () => ({ rpc }),
  } as unknown as HermesRuntime);
  expect(await sessions.list('bot')).toEqual({
    currentSessionId: 'current',
    sessions: [
      { session_id: 'current', title: 'Current work', started_at: 20 },
      { session_id: 'previous', title: 'Previous work', started_at: 10 },
    ],
  });
});

it('compresses the coordinator context without switching its native session', async () => {
  const snapshot = {
    session_id: 'parent-live',
    stored_session_id: 'parent-stored',
    replay_epoch: 'epoch',
    last_sequence: 7,
    revision: 3,
    execution_generation: 2,
    running: false,
  };
  const rpc = vi.fn(async (method: string) => {
    if (method === 'session.create') return snapshot;
    if (method === 'session.mutate') return { status: 'applied', lines: ['Compressed context'] };
    throw new Error('Unexpected session call');
  });
  const saveHermesSession = vi.fn();
  const database = {
    conversations: () => [{ kind: 'dm', botId: 'bot', conversationId: 'dm' }],
    hermesSession: () => undefined,
    setting: () => undefined,
    setSetting: vi.fn(),
    messages: () => [],
    saveHermesSession,
    runs: () => [],
  } as unknown as NodeDatabase;
  const sessions = new BotSessions(database, {
    gateway: () => ({ rpc }),
  } as unknown as HermesRuntime);
  const result = await sessions.execute('bot', '/compress', 'Keep decisions', 'request-id');
  expect(result.output).toContain('Compressed context');
  expect(rpc).toHaveBeenCalledWith(
    'session.mutate',
    {
      session_id: 'parent-live',
      request_id: 'request-id',
      expected_revision: 3,
      expected_generation: 2,
      operation: 'compress',
      payload: { focus: 'Keep decisions' },
    },
    15 * 60_000,
  );
  expect(saveHermesSession).toHaveBeenLastCalledWith({
    conversationId: 'dm',
    botId: 'bot',
    storedSessionId: 'parent-stored',
    replayEpoch: 'epoch',
    lastSequence: 7,
  });
  await expect(sessions.execute('bot', '/branch', '')).rejects.toThrow('Unknown session command');
});
