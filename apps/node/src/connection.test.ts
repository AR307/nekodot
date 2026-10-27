import { it, expect } from 'vitest';
import { mkdtemp, readFile } from 'node:fs/promises';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { randomUUID } from 'node:crypto';
import { WebSocket } from 'ws';
import { nodeCredentialsSchema, rpcResponseSchema, type Envelope } from '@nekodot/protocol';
import { createRelay } from '../../relay/src/server';
import { pairNode } from './pair';
import { connectRelay } from './connection';
import { NodeDatabase } from './database';

it('pairs through HTTP, saves private credentials and serves persisted state over Relay', async () => {
  const home = await mkdtemp(join(tmpdir(), 'nekodot-node-pair-'));
  const relay = await createRelay({
    dataDir: join(home, 'relay'),
    jwtSecret: 'node-pair-integration-secret',
    publicUrl: 'http://localhost',
  });
  const base = await relay.app.listen({ host: '127.0.0.1', port: 0 });
  const signup = await relay.app.inject({
    method: 'POST',
    url: '/api/auth/signup',
    payload: { email: 'node@example.test', password: 'node-password' },
  });
  const { token } = signup.json<{ token: string }>();
  const pair = await relay.app.inject({
    method: 'POST',
    url: '/api/pairing-codes',
    headers: { authorization: 'Bearer ' + token },
  });
  const credentials = await pairNode(
    join(home, 'node'),
    base,
    pair.json<{ code: string }>().code,
    'Desk',
  );
  expect(
    nodeCredentialsSchema.parse(JSON.parse(await readFile(join(home, 'node/node.json'), 'utf8'))),
  ).toEqual(credentials);
  let database = new NodeDatabase(join(home, 'node'));
  database.putBot({
    botId: 'nk-abcdef',
    displayName: 'Research',
    handle: 'research',
    avatar: { shape: 'dot', color: '#E8603C' },
    role: 'Help with research',
    model: 'chosen-model',
    archived: false,
    createdAt: new Date().toISOString(),
  });
  database.db.close();
  database = new NodeDatabase(join(home, 'node'));
  let ready!: () => void;
  const online = new Promise<void>((resolve) => {
    ready = resolve;
  });
  const connection = connectRelay({
    credentials,
    onReady: ready,
    handleRpc: async () => ({
      bots: database.bots(),
      groups: [],
      conversations: [],
      headSeq: database.head(),
      node: { platform: 'linux', computerUse: false },
    }),
  });
  await online;
  const socket = new WebSocket(base.replace('http', 'ws') + '/ws/client');
  await new Promise<void>((resolve) => socket.once('open', resolve));
  const hello = new Promise<void>((resolve) => socket.once('message', () => resolve()));
  socket.send(JSON.stringify({ v: 1, id: randomUUID(), type: 'hello', payload: { token } }));
  await hello;
  const id = randomUUID();
  const response = new Promise<Envelope>((resolve) =>
    socket.on('message', (raw) => {
      const e = JSON.parse(raw.toString()) as Envelope;
      if (e.replyTo === id) resolve(e);
    }),
  );
  socket.send(
    JSON.stringify({
      v: 1,
      id,
      type: 'rpc.req',
      nodeId: credentials.nodeId,
      payload: { method: 'sync.snapshot', params: {} },
    }),
  );
  const result = rpcResponseSchema('sync.snapshot').parse((await response).payload);
  expect(result.ok && result.result.bots[0]?.displayName).toBe('Research');
  socket.terminate();
  connection.close();
  database.db.close();
  await relay.app.close();
});
