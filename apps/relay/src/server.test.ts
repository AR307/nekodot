import { seedVerifiedAccount } from '../../../tests/support/account';
import { it, expect } from 'vitest';
import { mkdtemp } from 'node:fs/promises';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { randomUUID } from 'node:crypto';
import { WebSocket } from 'ws';
import { createRelay } from './server';
import type { Envelope } from '@nekodot/protocol';

async function channel(url: string, payload: unknown) {
  const socket = new WebSocket(url);
  const queue: Envelope[] = [];
  let receiver: ((e: Envelope) => void) | undefined;
  socket.on('message', (raw) => {
    const value = JSON.parse(raw.toString()) as Envelope;
    if (receiver) {
      const resolve = receiver;
      receiver = undefined;
      resolve(value);
    } else queue.push(value);
  });
  const next = () =>
    queue.length
      ? Promise.resolve(queue.shift()!)
      : new Promise<Envelope>((resolve) => {
          receiver = resolve;
        });
  await new Promise<void>((resolve, reject) => {
    socket.once('open', resolve);
    socket.once('error', reject);
  });
  socket.send(JSON.stringify({ v: 1, id: randomUUID(), type: 'hello', payload }));
  expect((await next()).type).toBe('hello.ok');
  return { socket, next };
}

it('registers, pairs and routes only owner traffic; unpair revokes the live node', async () => {
  const relay = await createRelay({
    dataDir: await mkdtemp(join(tmpdir(), 'nekodot-relay-')),
    jwtSecret: 'isolated-relay-test-secret',
    publicUrl: 'http://127.0.0.1:4319',
  });
  await seedVerifiedAccount(relay.database, 'owner@example.test', 'owner-password');
  await seedVerifiedAccount(relay.database, 'other@example.test', 'other-password');
  const base = await relay.app.listen({ host: '127.0.0.1', port: 0 });
  const sockets: WebSocket[] = [];
  async function post(path: string, body: unknown, token?: string) {
    return fetch(base + path, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        ...(token ? { Authorization: 'Bearer ' + token } : {}),
      },
      body: JSON.stringify(body),
    });
  }
  try {
    const owner = (await (
      await post('/api/auth/login', { email: 'owner@example.test', password: 'owner-password' })
    ).json()) as { token: string };
    expect(owner.token).toBeTypeOf('string');
    const login = await post('/api/auth/login', {
      email: 'owner@example.test',
      password: 'owner-password',
    });
    expect(login.status).toBe(200);
    expect(
      (await post('/api/auth/login', { email: 'owner@example.test', password: 'wrong-password' }))
        .status,
    ).toBe(401);
    const stranger = (await (
      await post('/api/auth/login', { email: 'other@example.test', password: 'other-password' })
    ).json()) as { token: string };
    const pairing = (await (await post('/api/pairing-codes', {}, owner.token)).json()) as {
      code: string;
      installCommand: string;
    };
    expect(pairing.installCommand).toContain(pairing.code);
    const paired = (await (
      await post('/api/pair', { code: pairing.code, nodeName: 'My workstation', platform: 'linux' })
    ).json()) as { nodeId: string; nodeToken: string };
    expect(
      (await post('/api/pair', { code: pairing.code, nodeName: 'Other', platform: 'linux' }))
        .status,
    ).toBe(400);
    const client = await channel(base.replace('http', 'ws') + '/ws/client', { token: owner.token });
    sockets.push(client.socket);
    const other = await channel(base.replace('http', 'ws') + '/ws/client', {
      token: stranger.token,
    });
    sockets.push(other.socket);
    const node = await channel(base.replace('http', 'ws') + '/ws/node', {
      nodeToken: paired.nodeToken,
      version: '1',
    });
    sockets.push(node.socket);
    expect((await client.next()).type).toBe('node.status');
    const request = {
      v: 1 as const,
      id: randomUUID(),
      type: 'rpc.req' as const,
      nodeId: paired.nodeId,
      payload: { method: 'sync.snapshot', params: {} },
    };
    client.socket.send(JSON.stringify(request));
    expect((await node.next()).id).toBe(request.id);
    node.socket.send(
      JSON.stringify({
        v: 1,
        id: randomUUID(),
        type: 'rpc.res',
        replyTo: request.id,
        payload: { ok: true, result: { from: 'node' } },
      }),
    );
    expect((await client.next()).payload).toEqual({ ok: true, result: { from: 'node' } });
    other.socket.send(JSON.stringify({ ...request, id: randomUUID() }));
    expect((await other.next()).payload).toMatchObject({ ok: false, error: { code: 'forbidden' } });
    const me = (await (
      await fetch(base + '/api/me', { headers: { Authorization: 'Bearer ' + owner.token } })
    ).json()) as { nodes: { online: boolean }[] };
    expect(me.nodes[0]?.online).toBe(true);
    const denied = await fetch(base + '/api/nodes/' + paired.nodeId, {
      method: 'DELETE',
      headers: { Authorization: 'Bearer ' + stranger.token },
    });
    expect(denied.status).toBe(404);
    const closed = new Promise<void>((resolve) => node.socket.once('close', () => resolve()));
    expect(
      (
        await fetch(base + '/api/nodes/' + paired.nodeId, {
          method: 'DELETE',
          headers: { Authorization: 'Bearer ' + owner.token },
        })
      ).status,
    ).toBe(200);
    await closed;
    expect(relay.database.nodeByToken(paired.nodeToken)).toBeUndefined();
  } finally {
    for (const socket of sockets) socket.terminate();
    await relay.app.close();
  }
});
