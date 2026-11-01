import { mkdtemp } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { expect, it } from 'vitest';
import { recordedManagementRuntime, startFakeHermes } from '@nekodot/fake-hermes';
import { rpcRequestSchema } from '@nekodot/protocol';
import { NodeApplication } from './app';
import { HermesGatewayError } from './hermes/gateway';
import type { HermesRuntime } from './hermes/runtime';

it('keeps a queued gateway admission actionable after a replay error and cancels without replaying it', async () => {
  const key = 'queued-test-only';
  const home = await mkdtemp(join(tmpdir(), 'nekodot-queued-execution-'));
  const recorded = await startFakeHermes({
    fixturesDirectory: join(process.cwd(), 'docs/fixtures'),
    apiKey: key,
    profiles: ['default'],
  });
  const baseRuntime = recordedManagementRuntime(recorded.url, key, home, recorded.pluginCatalog);
  let failReplay = true;
  let cancelled = false;
  let replayErrorSeen = false;
  const runtime: HermesRuntime = {
    ...baseRuntime,
    start: async () => {},
    close: async () => {},
    configureBot: async () => {},
    approvalMode: async () => 'manual',
    gateway: (profile) => {
      const gateway = baseRuntime.gateway(profile);
      const originalRpc = gateway.rpc.bind(gateway);
      gateway.rpc = async <T>(method: string, params: Record<string, unknown>): Promise<T> => {
        if (method === 'prompt.receipt' && params.admission_id === 'queued-admission')
          return {
            admission_id: 'queued-admission',
            status: cancelled ? 'terminal' : 'queued',
            outcome: cancelled ? 'cancelled' : null,
            execution_generation: null,
          } as T;
        if (method === 'session.events.since' && failReplay) {
          failReplay = false;
          throw new HermesGatewayError('unknown_execution', -32000);
        }
        if (method === 'prompt.cancel' && params.admission_id === 'queued-admission') {
          cancelled = true;
          return { admission_id: 'queued-admission', status: 'cancelled' } as T;
        }
        return originalRpc<T>(method, params);
      };
      return gateway;
    },
  };
  const app = new NodeApplication(home, runtime);
  app.onLive = (event) => {
    if (event.kind === 'activity' && event.connection === 'reconnecting') replayErrorSeen = true;
  };
  const createdAt = new Date().toISOString();
  app.database.putBot({
    botId: 'nk-abcdef',
    displayName: 'Queue Bot',
    handle: 'queue',
    avatar: { shape: 'dot', color: '#E8603C' },
    role: 'Assistant',
    model: 'test-model',
    archived: false,
    createdAt,
  });
  app.database.putConversation({
    conversationId: 'private-chat',
    kind: 'dm',
    botId: 'nk-abcdef',
    createdAt,
  });
  const session = await baseRuntime.gateway('nk-abcdef').rpc<{
    session_id: string;
    stored_session_id: string;
    replay_epoch: string;
    last_sequence: number;
  }>('session.create', {
    source: 'gui',
    title: 'Queued recovery test',
    hidden: true,
    follow_profile_config: true,
    request_id: 'queued-recovery-session',
  });
  app.database.saveHermesSession({
    conversationId: 'private-chat',
    botId: 'nk-abcdef',
    storedSessionId: session.stored_session_id,
    replayEpoch: session.replay_epoch,
    lastSequence: session.last_sequence,
  });
  app.database.saveRun({
    conversationId: 'private-chat',
    botId: 'nk-abcdef',
    runId: 'queued-admission',
    sessionId: session.session_id,
    storedSessionId: session.stored_session_id,
    replayEpoch: session.replay_epoch,
    submissionId: 'queued-submission',
    inputMessageId: 'original-message',
    state: 'thinking',
    lastSeq: session.last_sequence,
  });
  try {
    await app.resume();
    await expect.poll(() => replayErrorSeen).toBe(true);
    expect(app.database.runs()[0]?.state).toBe('thinking');
    expect(app.database.messages('private-chat')).toHaveLength(0);
    await app.handle(
      rpcRequestSchema.parse({ method: 'runs.stop', params: { conversationId: 'private-chat' } }),
    );
    await expect.poll(() => app.database.runs().length).toBe(0);
    expect(app.database.messages('private-chat')).toEqual(
      expect.arrayContaining([expect.objectContaining({ kind: 'text', status: 'cancelled' })]),
    );
    expect(cancelled).toBe(true);
    expect(recorded.inspectRuns()).toHaveLength(0);
  } finally {
    await app.close();
    await recorded.close();
  }
});
