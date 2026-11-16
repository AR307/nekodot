import { mkdir, mkdtemp, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { expect, it } from 'vitest';
import type { Bot, ConnectorAuthorization } from '@nekodot/protocol';
import { NodeConnectors } from './connectors';
import { NodeDatabase, type RunRecord } from './database';
import type { HermesRuntime } from './hermes/runtime';

it('asks for an account in the chat that needs it and continues there once the turn is over', async () => {
  const home = await mkdtemp(join(tmpdir(), 'nekodot-connectors-'));
  const db = new NodeDatabase(home);
  const botId = 'nk-abcdef';
  db.putBot({ botId, handle: 'mailer', displayName: 'Mailer', archived: false } as Bot);
  await mkdir(join(home, botId, 'plugins', 'nekodot-secrets'), { recursive: true });
  await writeFile(join(home, botId, 'plugins', 'nekodot-secrets', 'bridge.token'), 'token\n');
  const hermes = { profileHome: (id: string) => join(home, id) } as unknown as HermesRuntime;
  const connectors = new NodeConnectors(db, hermes);
  const pending: ConnectorAuthorization = {
    authorizationId: 'auth-1',
    connectionId: 'conn-1',
    service: { serviceId: 'mail', name: 'Mail', authMethods: ['oauth'] },
    status: 'pending',
    url: 'https://example.com/authorize',
    expiresAt: new Date(Date.now() + 600_000).toISOString(),
  };
  let authorization = pending;
  connectors.request = async () => authorization;
  const continued: { request: { sessionId: string; conversationId: string }; text: string }[] = [];
  connectors.onContinue = async (request, _submission, text) => {
    continued.push({ request, text });
  };
  const run: RunRecord = {
    conversationId: 'dm',
    botId,
    runId: 'admission-1',
    sessionId: 'runtime-1',
    storedSessionId: 'stored-1',
    inputMessageId: 'user-1',
    lastSeq: 0,
    state: 'tool',
    native: true,
  };
  db.saveRun(run);
  const result = (await connectors.local({
    action: 'connector',
    botId,
    sessionId: 'runtime-1',
    admissionId: 'admission-1',
    callId: 'call-1',
    token: 'token',
    request: { operation: 'authorize', serviceId: 'mail' },
  })) as { awaitingUser: boolean; instruction: string };
  expect(result.awaitingUser).toBe(true);
  expect(result.instruction).not.toMatch(/main Dot|task/i);
  const card = db.message('connector:' + `${botId}:runtime-1:admission-1:call-1`);
  expect(card).toMatchObject({ conversationId: 'dm', kind: 'connector', status: 'streaming' });
  expect(card?.taskRole).toBeUndefined();

  // Authorized while the turn that asked is still running: it waits for the turn to end.
  authorization = { ...pending, status: 'active' };
  await connectors.changed(authorization);
  expect(continued).toHaveLength(0);
  db.saveRun({ ...run, state: 'idle' });
  await connectors.settled();
  expect(continued).toHaveLength(1);
  expect(continued[0]!.request).toMatchObject({ conversationId: 'dm', sessionId: 'stored-1' });
  expect(continued[0]!.text).toContain('now authorized');
  await connectors.settled();
  expect(continued).toHaveLength(1);
  db.db.close();
});
