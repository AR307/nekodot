import { seedVerifiedAccount } from '../../../tests/support/account';
import { it, expect } from 'vitest';
import { mkdtemp } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { randomUUID } from 'node:crypto';
import { WebSocket } from 'ws';
import { createRelay } from './server';
import type { Envelope } from '@nekodot/protocol';

it('registers an App device, isolates owners and acknowledges a deduplicated task notice', async () => {
  const relay = await createRelay({
    dataDir: await mkdtemp(join(tmpdir(), 'nekodot-app-device-')),
    jwtSecret: 'app-device-journey-secret',
    publicUrl: 'https://product.example',
    clientOrigins: ['https://tauri.localhost'],
  });
  await seedVerifiedAccount(relay.database, 'app-owner@example.test', 'owner-password');
  await seedVerifiedAccount(relay.database, 'app-other@example.test', 'other-password');
  const base = await relay.app.listen({ host: '127.0.0.1', port: 0 });
  const sockets: WebSocket[] = [];
  async function request(path: string, body: unknown, token?: string, method = 'POST') {
    return fetch(base + path, {
      method,
      headers: {
        'Content-Type': 'application/json',
        Origin: 'https://tauri.localhost',
        ...(token ? { Authorization: 'Bearer ' + token } : {}),
      },
      body: JSON.stringify(body),
    });
  }
  async function socket(payload: unknown) {
    const ws = new WebSocket(
      base.replace('http', 'ws') +
        ('/ws/' + ('nodeToken' in (payload as object) ? 'node' : 'client')),
    );
    sockets.push(ws);
    const messages: Envelope[] = [];
    let receive: ((value: Envelope) => void) | undefined;
    ws.on('message', (data) => {
      const value = JSON.parse(data.toString()) as Envelope;
      if (receive) {
        const current = receive;
        receive = undefined;
        current(value);
      } else messages.push(value);
    });
    const next = () =>
      messages.length
        ? Promise.resolve(messages.shift()!)
        : new Promise<Envelope>((resolve) => (receive = resolve));
    await new Promise<void>((resolve, reject) => {
      ws.once('open', resolve);
      ws.once('error', reject);
    });
    ws.send(JSON.stringify({ v: 1, id: randomUUID(), type: 'hello', payload }));
    expect((await next()).type).toBe('hello.ok');
    return { ws, next, messages };
  }
  try {
    const ownerResponse = await request('/api/auth/login', {
      email: 'app-owner@example.test',
      password: 'owner-password',
    });
    expect(ownerResponse.headers.get('access-control-allow-origin')).toBe(
      'https://tauri.localhost',
    );
    const owner = (await ownerResponse.json()) as { token: string };
    const other = (await (
      await request('/api/auth/login', {
        email: 'app-other@example.test',
        password: 'other-password',
      })
    ).json()) as { token: string };
    const deviceId = randomUUID();
    expect(
      (
        await request('/api/devices', {
          deviceId,
          token: 'test-only-fcm-token',
          platform: 'android',
        })
      ).status,
    ).toBe(401);
    expect(
      (
        await request(
          '/api/devices',
          { deviceId, token: 'test-only-fcm-token', platform: 'android' },
          owner.token,
        )
      ).status,
    ).toBe(200);
    for (const body of [
      { deviceId, token: 'a-different-device-token', platform: 'android' },
      { deviceId: randomUUID(), token: 'test-only-fcm-token', platform: 'android' },
    ]) {
      expect((await request('/api/devices', body, other.token)).status).toBe(409);
    }
    await fetch(base + '/api/devices/' + deviceId, {
      method: 'DELETE',
      headers: { Authorization: 'Bearer ' + other.token },
    });
    expect(relay.database.db.prepare('SELECT device_id FROM devices').all()).toHaveLength(1);
    const status = await (
      await fetch(base + '/api/notifications/status', {
        headers: { Authorization: 'Bearer ' + owner.token },
      })
    ).json();
    expect(status).toMatchObject({ available: false });
    const pair = (await (await request('/api/pairing-codes', {}, owner.token)).json()) as {
      code: string;
    };
    const credentials = (await (
      await request('/api/pair', { code: pair.code, nodeName: 'Product server', platform: 'linux' })
    ).json()) as { nodeId: string; nodeToken: string };
    const node = await socket({ nodeToken: credentials.nodeToken, version: '1.0.0' });
    const client = await socket({ token: owner.token });
    const stranger = await socket({ token: other.token });
    const signal = {
      notificationId: 'run:recorded-run',
      conversationId: 'private-chat',
      kind: 'completed',
      displayName: 'Acceptance Bot',
      preview: 'A real final reply preview',
    };
    const send = () =>
      node.ws.send(JSON.stringify({ v: 1, id: randomUUID(), type: 'notify', payload: signal }));
    send();
    expect((await client.next()).payload).toEqual(signal);
    expect((await node.next()).type).toBe('notify.ack');
    send();
    expect((await node.next()).type).toBe('notify.ack');
    expect(client.messages).toHaveLength(0);
    expect(stranger.messages).toHaveLength(0);
    expect(relay.database.db.prepare('SELECT * FROM notification_delivery').all()).toHaveLength(1);
    expect(
      JSON.stringify(relay.database.db.prepare('SELECT * FROM notification_delivery').all()),
    ).not.toContain(signal.preview);
    await fetch(base + '/api/devices/' + deviceId, {
      method: 'DELETE',
      headers: { Authorization: 'Bearer ' + owner.token },
    });
    expect(relay.database.db.prepare('SELECT device_id FROM devices').all()).toHaveLength(0);
  } finally {
    sockets.forEach((socket) => socket.terminate());
    await relay.app.close();
  }
});
