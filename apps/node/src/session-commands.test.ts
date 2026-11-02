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

it('branches using the native receipt and saves the resumed branch for the next message', async () => {
  const snapshot = {
    session_id: 'parent-live',
    stored_session_id: 'parent-stored',
    replay_epoch: 'epoch',
    last_sequence: 7,
    revision: 3,
    execution_generation: 2,
    running: false,
  };
  const rpc = vi.fn(async (method: string, params: Record<string, unknown>) => {
    if (method === 'session.create') return snapshot;
    if (method === 'session.mutate') return { branched_session_id: 'native-branch' };
    if (method === 'session.resume' && params.session_id === 'native-branch')
      return { ...snapshot, session_id: 'branch-live', stored_session_id: 'native-branch' };
    throw new Error('Unexpected session call');
  });
  const saveHermesSession = vi.fn();
  const database = {
    conversations: () => [{ kind: 'dm', botId: 'bot', conversationId: 'dm' }],
    hermesSession: () => undefined,
    saveHermesSession,
    runs: () => [],
  } as unknown as NodeDatabase;
  const sessions = new BotSessions(database, {
    gateway: () => ({ rpc }),
  } as unknown as HermesRuntime);
  const result = await sessions.execute('bot', '/branch', 'Keep the parent', 'request-id');
  expect(result.output).toContain('Branched Hermes session: branch-live');
  expect(rpc).toHaveBeenCalledWith(
    'session.mutate',
    {
      session_id: 'parent-live',
      request_id: 'request-id',
      expected_revision: 3,
      expected_generation: 2,
      operation: 'branch',
      payload: { title: 'Keep the parent' },
    },
    15 * 60_000,
  );
  expect(saveHermesSession).toHaveBeenLastCalledWith({
    conversationId: 'dm',
    botId: 'bot',
    storedSessionId: 'native-branch',
    replayEpoch: 'epoch',
    lastSequence: 7,
  });
});
