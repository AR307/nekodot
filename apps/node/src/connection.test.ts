import { it, expect } from 'vitest';
import { once } from 'node:events';
import { mkdtemp, readFile } from 'node:fs/promises';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { randomUUID } from 'node:crypto';
import { createServer, connect, type AddressInfo, type Socket } from 'node:net';
import { WebSocket, WebSocketServer } from 'ws';
import { nodeCredentialsSchema, rpcResponseSchema, type Envelope } from '@nekodot/protocol';
import { createRelay } from '../../relay/src/server';
import { seedVerifiedAccount } from '../../../tests/support/account';
import { pairNode } from './pair';
import { connectRelay } from './connection';
import { NodeDatabase } from './database';

it('reconnects after the Relay hello deadline while keeping the paired node', async () => {
  const relay = await createRelay({
    dataDir: await mkdtemp(join(tmpdir(), 'nekodot-hello-timeout-')),
    jwtSecret: 'hello-timeout-test-secret',
    publicUrl: 'http://localhost',
  });
  const base = await relay.app.listen({ host: '127.0.0.1', port: 0 });
  const userId = await seedVerifiedAccount(relay.database, 'hello@example.test', 'test-password');
  const pair = relay.database.pairingCode(userId);
  const credentials = relay.database.pair(pair.code, 'Test server', 'linux')!;
  const proxy = new WebSocketServer({ host: '127.0.0.1', port: 0 });
  await once(proxy, 'listening');
  let attempts = 0;
  const closures: number[] = [];
  proxy.on('connection', (client) => {
    const first = ++attempts === 1;
    const upstream = new WebSocket(base.replace('http', 'ws') + '/ws/node');
    const opened = once(upstream, 'open');
    client.on('message', (data, binary) => {
      // Lose only the first hello after a successful WebSocket upgrade.
      if (!first) void opened.then(() => upstream.send(data, { binary }));
    });
    upstream.on('message', (data, binary) => client.send(data, { binary }));
    upstream.on('close', (code, reason) => {
      closures.push(code);
      client.close(code, reason);
    });
    client.on('close', () => upstream.close());
  });
  let ready!: () => void;
  const online = new Promise<void>((resolve) => {
    ready = resolve;
  });
  const connection = connectRelay({
    credentials: {
      ...credentials,
      relayUrl: `http://127.0.0.1:${(proxy.address() as AddressInfo).port}`,
    },
    version: 'development',
    onReady: ready,
    handleRpc: async () => ({}),
  });
  try {
    await online;
    expect(closures).toEqual([1013]);
    expect(attempts).toBe(2);
    expect(relay.routing.online(credentials.nodeId)).toBe(true);
    expect(relay.database.owns(userId, credentials.nodeId)).toBe(true);
  } finally {
    connection.close();
    for (const client of proxy.clients) client.terminate();
    await new Promise<void>((resolve) => proxy.close(() => resolve()));
    await relay.app.close();
  }
});

it('recovers a stalled Relay handshake and serves paired, persisted state', async () => {
  const home = await mkdtemp(join(tmpdir(), 'nekodot-node-pair-'));
  const relay = await createRelay({
    dataDir: join(home, 'relay'),
    jwtSecret: 'node-pair-integration-secret',
    publicUrl: 'http://localhost',
  });
  const base = await relay.app.listen({ host: '127.0.0.1', port: 0 });
  await seedVerifiedAccount(relay.database, 'node@example.test', 'node-password');
  const signup = await relay.app.inject({
    method: 'POST',
    url: '/api/auth/login',
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
  let attempts = 0;
  const peers = new Set<Socket>();
  const proxy = createServer((socket) => {
    peers.add(socket);
    socket.on('close', () => peers.delete(socket));
    // Reproduce an intermediary accepting TCP but never completing the first upgrade.
    if (++attempts === 1) return;
    const upstream = connect(Number(new URL(base).port), '127.0.0.1');
    peers.add(upstream);
    upstream.on('close', () => peers.delete(upstream));
    socket.pipe(upstream).pipe(socket);
    socket.on('error', () => upstream.destroy());
    upstream.on('error', () => socket.destroy());
  });
  await new Promise<void>((resolve) => proxy.listen(0, '127.0.0.1', resolve));
  const failures: string[] = [];
  const connection = connectRelay({
    version: 'development',
    credentials: {
      ...credentials,
      relayUrl: `http://127.0.0.1:${(proxy.address() as AddressInfo).port}`,
    },
    onReady: ready,
    onError: (message) => failures.push(message),
    handleRpc: async () => ({
      bots: database.bots(),
      groups: [],
      conversations: [],
      latest: [],
      flows: [],
      tasks: [],
      spaces: [],
      headSeq: database.head(),
      node: { platform: 'linux', computerUse: false, host: 'server', desktopControl: null },
    }),
  });
  await online;
  expect(attempts).toBe(2);
  expect(failures).toContain('Opening handshake has timed out');
  const me = await relay.app.inject({
    url: '/api/me',
    headers: { authorization: 'Bearer ' + token },
  });
  expect(me.json<{ nodes: { online: boolean }[] }>().nodes[0]?.online).toBe(true);
  const socket = new WebSocket(base.replace('http', 'ws') + '/ws/client');
  await new Promise<void>((resolve) => socket.once('open', resolve));
  const hello = new Promise<void>((resolve) => socket.once('message', () => resolve()));
  socket.send(JSON.stringify({ v: 1, id: randomUUID(), type: 'hello', payload: { token } }));
  await hello;
  const invalidId = randomUUID();
  const invalidResponse = new Promise<Envelope>((resolve) =>
    socket.on('message', (raw) => {
      const envelope = JSON.parse(raw.toString()) as Envelope;
      if (envelope.replyTo === invalidId) resolve(envelope);
    }),
  );
  socket.send(
    JSON.stringify({
      v: 1,
      id: invalidId,
      type: 'rpc.req',
      nodeId: credentials.nodeId,
      payload: {
        method: 'bots.create',
        params: {
          displayName: '小鱼',
          handle: '@Maple',
          avatar: { shape: 'dot', color: '#E8603C' },
          role: '',
          sourceId: 'custom:research',
          model: '',
        },
      },
    }),
  );
  const invalid = rpcResponseSchema('bots.create').parse((await invalidResponse).payload);
  expect(invalid).toMatchObject({
    ok: false,
    error: {
      code: 'invalid_params',
      message: 'Invalid RPC arguments: params.model: Choose a model or enter its model ID',
    },
  });
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
  for (const peer of peers) peer.destroy();
  await new Promise<void>((resolve) => proxy.close(() => resolve()));
  database.db.close();
  await relay.app.close();
}, 45000);
