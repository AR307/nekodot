import { expect, it, vi } from 'vitest';
import { defaultSessionReasoning, type NativeSessionSnapshot } from './session';
import type { HermesGateway } from './gateway';

const session = (effort: string | null, running = false): NativeSessionSnapshot => ({
  info: { reasoning_effort: effort },
  session_id: 'live-chat',
  stored_session_id: 'stored-chat',
  replay_epoch: 'epoch',
  last_sequence: 8,
  running,
  execution_generation: 3,
  revision: 5,
});

it('sets an unset resumed conversation to xhigh and reports the native result', async () => {
  const actual = session('xhigh');
  actual.info!.reasoning_effort_wire = 'xhigh';
  const rpc = vi.fn().mockResolvedValueOnce({}).mockResolvedValueOnce(actual);
  const gateway = { rpc } as unknown as HermesGateway;
  expect(await defaultSessionReasoning(gateway, session(null))).toEqual(actual);
  expect(rpc.mock.calls[0]).toEqual([
    'session.mutate',
    {
      session_id: 'live-chat',
      request_id: expect.any(String),
      expected_revision: 5,
      expected_generation: 3,
      operation: 'reasoning',
      payload: { effort: 'xhigh' },
    },
  ]);
});

it.each(['low', 'high', 'none', 'max'])('preserves the user choice %s', async (effort) => {
  const rpc = vi.fn();
  const current = session(effort);
  expect(await defaultSessionReasoning({ rpc } as unknown as HermesGateway, current)).toBe(current);
  expect(rpc).not.toHaveBeenCalled();
});

it('does not mutate an in-flight turn', async () => {
  const rpc = vi.fn();
  const current = session(null, true);
  await defaultSessionReasoning({ rpc } as unknown as HermesGateway, current);
  expect(rpc).not.toHaveBeenCalled();
});
