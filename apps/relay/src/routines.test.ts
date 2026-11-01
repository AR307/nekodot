import { createHash, randomUUID } from 'node:crypto';
import { mkdtemp } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { WebSocket } from 'ws';
import { expect, it } from 'vitest';
import { seedVerifiedAccount } from '../../../tests/support/account';
import { createRelay } from './server';
import type { Envelope } from '@nekodot/protocol';

it('authenticates public hooks, forwards an unchanged request ID only to the owner node and returns the native receipt', async () => {
  const relay = await createRelay({
    dataDir: await mkdtemp(join(tmpdir(), 'nekodot-hook-relay-')),
    jwtSecret: 'isolated-qa-secret',
    publicUrl: 'https://example.test',
  });
  await seedVerifiedAccount(relay.database, 'owner@example.test', 'owner-password');
  await seedVerifiedAccount(relay.database, 'other@example.test', 'other-password');
  const base = await relay.app.listen({ host: '127.0.0.1', port: 0 });
  const post = (path: string, body: unknown, token?: string) =>
    fetch(base + path, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        ...(token ? { Authorization: 'Bearer ' + token } : {}),
      },
      body: JSON.stringify(body),
    });
  const owner = (await (
    await post('/api/auth/login', { email: 'owner@example.test', password: 'owner-password' })
  ).json()) as { token: string };
  const pairing = (await (await post('/api/pairing-codes', {}, owner.token)).json()) as {
    code: string;
  };
  const paired = (await (
    await post('/api/pair', { code: pairing.code, nodeName: 'QA Linux', platform: 'linux' })
  ).json()) as { nodeId: string; nodeToken: string };
  const socket = new WebSocket(base.replace(/^http/, 'ws') + '/ws/node');
  const received: Envelope[] = [];
  const credential = 'public-hook-secret';
  const routineId = randomUUID();
  const digest = createHash('sha256').update(credential).digest('hex');
  let onFrame: ((frame: Envelope) => void) | undefined;
  socket.on('message', (raw) => {
    const frame = JSON.parse(raw.toString()) as Envelope;
    received.push(frame);
    onFrame?.(frame);
    if (frame.type === 'routine.deliver')
      socket.send(
        JSON.stringify({
          v: 1,
          id: randomUUID(),
          type: 'routine.receipt',
          replyTo: frame.id,
          nodeId: paired.nodeId,
          payload: { status: 200, body: { status: 'ignored', reason: 'filter' } },
        }),
      );
  });
  const next = (type: Envelope['type']) =>
    new Promise<void>((resolve) => {
      if (received.some((f) => f.type === type)) return resolve();
      onFrame = (f) => {
        if (f.type === type) {
          onFrame = undefined;
          resolve();
        }
      };
    });
  try {
    await new Promise<void>((resolve, reject) => {
      socket.once('open', resolve);
      socket.once('error', reject);
    });
    socket.send(
      JSON.stringify({
        v: 1,
        id: randomUUID(),
        type: 'hello',
        payload: { nodeToken: paired.nodeToken, version: 'development' },
      }),
    );
    await next('hello.ok');
    expect(received.find((f) => f.type === 'hello.ok')?.payload).toEqual({
      publicUrl: 'https://example.test',
    });
    socket.send(
      JSON.stringify({
        v: 1,
        id: randomUUID(),
        type: 'routine.routes',
        nodeId: paired.nodeId,
        payload: [{ routineId, botId: 'nk-abcdef', digest, enabled: true }],
      }),
    );
    await next('routine.routes.ack');
    expect((await post('/hooks/' + routineId, { event_type: 'scan' }, 'wrong')).status).toBe(401);
    expect((await post('/hooks/not-an-id', {}, credential)).status).toBe(400);
    const response = await fetch(base + '/hooks/' + routineId, {
      method: 'POST',
      headers: {
        Authorization: 'Bearer ' + credential,
        'Content-Type': 'application/json',
        'X-Request-ID': 'stable-scan-001',
      },
      body: JSON.stringify({ event_type: 'scan', message: 'harmless' }),
    });
    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({ status: 'ignored', reason: 'filter' });
    expect(received.find((f) => f.type === 'routine.deliver')?.payload).toMatchObject({
      routineId,
      requestId: 'stable-scan-001',
      body: JSON.stringify({ event_type: 'scan', message: 'harmless' }),
    });
    expect(
      JSON.stringify(relay.database.db.prepare('SELECT * FROM routine_routes').all()),
    ).not.toContain('harmless');
    // A different account cannot query the owner's secrets through ordinary RPC.
    const other = (await (
      await post('/api/auth/login', { email: 'other@example.test', password: 'other-password' })
    ).json()) as { token: string };
    const stranger = new WebSocket(base.replace(/^http/, 'ws') + '/ws/client');
    await new Promise<void>((resolve, reject) => {
      stranger.once('open', resolve);
      stranger.once('error', reject);
    });
    const denied = new Promise<Envelope>((resolve) => {
      stranger.on('message', (raw) => {
        const frame = JSON.parse(raw.toString()) as Envelope;
        if (frame.type === 'hello.ok')
          stranger.send(
            JSON.stringify({
              v: 1,
              id: randomUUID(),
              type: 'rpc.req',
              nodeId: paired.nodeId,
              payload: {
                method: 'routines.credentials',
                params: { botId: 'nk-abcdef', routineId },
              },
            }),
          );
        else if (frame.type === 'rpc.res') resolve(frame);
      });
    });
    stranger.send(
      JSON.stringify({ v: 1, id: randomUUID(), type: 'hello', payload: { token: other.token } }),
    );
    expect((await denied).payload).toMatchObject({ ok: false, error: { code: 'forbidden' } });
    stranger.close();
    await new Promise<void>((resolve) => {
      socket.once('close', resolve);
      socket.close();
    });
    expect((await post('/hooks/' + routineId, {}, credential)).status).toBe(503);
    await fetch(base + '/api/nodes/' + paired.nodeId, {
      method: 'DELETE',
      headers: { Authorization: 'Bearer ' + owner.token },
    });
    expect((await post('/hooks/' + routineId, {}, credential)).status).toBe(403);
  } finally {
    socket.close();
    await relay.app.close();
  }
});
