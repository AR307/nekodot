import { createServer } from 'node:http';
import { mkdtemp } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { expect, it } from 'vitest';
import { recordedManagementRuntime, startFakeHermes } from '@nekodot/fake-hermes';
import { rpcRequestSchema } from '@nekodot/protocol';
import { NodeApplication } from './app';
import { HermesApi } from './hermes/api';
import type { HermesRuntime } from './hermes/runtime';

it('keeps a queued native run with null generation actionable after an unknown_execution SSE error', async () => {
  const key = 'queued-test-only';
  const home = await mkdtemp(join(tmpdir(), 'nekodot-queued-execution-'));
  const recorded = await startFakeHermes({
    fixturesDirectory: join(process.cwd(), 'docs/fixtures'),
    apiKey: key,
    profiles: ['default'],
  });
  let status = 'queued';
  const requests: string[] = [];
  const server = createServer((request, response) => {
    requests.push(request.method + ' ' + request.url);
    if (request.url?.endsWith('/events')) {
      response.setHeader('Content-Type', 'text/event-stream');
      if (!request.headers['last-event-id'])
        response.write(
          'data: ' +
            JSON.stringify({
              event: 'run.failed',
              run_id: 'queued-run',
              timestamp: Date.now(),
              seq: 0,
              error: 'unknown_execution',
            }) +
            '\n\n',
        );
      response.end();
      return;
    }
    if (request.method === 'POST' && request.url?.endsWith('/stop')) status = 'cancelled';
    response.setHeader('Content-Type', 'application/json');
    response.end(
      JSON.stringify({
        run_id: 'queued-run',
        status,
        admission_id: 'queued-admission',
        execution_generation: null,
        session_id: 'nk_dm_private-chat',
        output: '',
        pending_controls: [],
      }),
    );
  });
  await new Promise<void>((resolve) => server.listen(0, '127.0.0.1', resolve));
  const address = server.address();
  if (!address || typeof address === 'string') throw new Error('Missing test address');
  const runtime: HermesRuntime = {
    ...recordedManagementRuntime(recorded.url, key, home, recorded.pluginCatalog),
    start: async () => {},
    close: async () => {},
    configureBot: async () => {},
    approvalMode: async () => 'manual',
    api: async () => new HermesApi('http://127.0.0.1:' + address.port, key),
  };
  const app = new NodeApplication(home, runtime);
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
  app.database.saveRun({
    conversationId: 'private-chat',
    botId: 'nk-abcdef',
    runId: 'queued-run',
    inputMessageId: 'original-message',
    state: 'thinking',
    lastSeq: -1,
  });
  try {
    await app.resume();
    await expect.poll(() => app.database.runs()[0]?.lastSeq).toBe(0);
    expect(app.database.runs()[0]?.state).toBe('thinking');
    expect(app.database.messages('private-chat')).toHaveLength(0);
    await app.handle(
      rpcRequestSchema.parse({ method: 'runs.stop', params: { conversationId: 'private-chat' } }),
    );
    await expect.poll(() => app.database.runs().length).toBe(0);
    expect(app.database.messages('private-chat')).toEqual(
      expect.arrayContaining([expect.objectContaining({ kind: 'text', status: 'cancelled' })]),
    );
    expect(requests.filter((r) => r === 'POST /v1/runs/queued-run/stop')).toHaveLength(1);
    expect(requests.some((r) => r.includes('resolve-unknown') || r === 'POST /v1/runs')).toBe(
      false,
    );
  } finally {
    await app.close();
    server.closeAllConnections();
    await new Promise<void>((resolve) => server.close(() => resolve()));
    await recorded.close();
  }
});
