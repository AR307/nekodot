import { seedVerifiedAccount } from '../../../tests/support/account';
import { expect, it } from 'vitest';
import { randomUUID } from 'node:crypto';
import { once } from 'node:events';
import { mkdtemp } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { WebSocket } from 'ws';
import { payloadSchemas, type Envelope } from '@nekodot/protocol';
import { createRelay } from './server';

it('keeps the same install code valid through a long installation and only lets its owner extend it', async () => {
  const relay = await createRelay({
    dataDir: await mkdtemp(join(tmpdir(), 'nekodot-long-install-')),
    jwtSecret: 'isolated-pairing-test-secret',
    publicUrl: 'http://127.0.0.1',
  });
  await seedVerifiedAccount(relay.database, 'installer@example.test', 'installation-test-password');
  await seedVerifiedAccount(relay.database, 'other@example.test', 'installation-test-password');
  const base = await relay.app.listen({ host: '127.0.0.1', port: 0 });
  const post = (path: string, body: unknown, token?: string) =>
    fetch(base + '/api' + path, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        ...(token ? { Authorization: `Bearer ${token}` } : {}),
      },
      body: JSON.stringify(body),
    });
  try {
    const owner = (await (
      await post('/auth/login', {
        email: 'installer@example.test',
        password: 'installation-test-password',
      })
    ).json()) as { token: string };
    const other = (await (
      await post('/auth/login', {
        email: 'other@example.test',
        password: 'installation-test-password',
      })
    ).json()) as { token: string };
    const pairing = (await (await post('/pairing-codes', {}, owner.token)).json()) as {
      code: string;
      expiresAt: string;
      installCommand: string;
    };
    expect(Date.parse(pairing.expiresAt) - Date.now()).toBeGreaterThan(29 * 60_000);
    const extended = (await (
      await post(`/pairing-codes/${pairing.code}/extend`, {}, owner.token)
    ).json()) as { code: string; expiresAt: string };
    expect(extended.code).toBe(pairing.code);
    expect(Date.parse(extended.expiresAt) - Date.parse(pairing.expiresAt)).toBe(30 * 60_000);
    expect((await post(`/pairing-codes/${pairing.code}/extend`, {}, other.token)).status).toBe(404);
    relay.database.db
      .prepare('UPDATE pairing_codes SET expires_at=? WHERE code=?')
      .run(Date.now() - 1000, pairing.code);
    expect(
      (
        await post('/pair', {
          code: pairing.code,
          nodeName: 'Install still running',
          platform: 'linux',
        })
      ).status,
    ).toBe(400);
    expect((await post(`/pairing-codes/${pairing.code}/extend`, {}, owner.token)).status).toBe(200);
    const paired = await post('/pair', {
      code: pairing.code,
      nodeName: 'Installed server',
      platform: 'linux',
    });
    expect(paired.status).toBe(200);
    expect(((await paired.json()) as { nodeId: string }).nodeId).toBeTruthy();
    expect((await post(`/pairing-codes/${pairing.code}/extend`, {}, owner.token)).status).toBe(404);
  } finally {
    await relay.app.close();
  }
});

it('gives a node a pairing code for its owner when its Dot adds a computer in a sandbox', async () => {
  const relay = await createRelay({
    dataDir: await mkdtemp(join(tmpdir(), 'nekodot-node-pairing-')),
    jwtSecret: 'isolated-pairing-test-secret',
    publicUrl: 'https://relay.example/',
  });
  await seedVerifiedAccount(relay.database, 'owner@example.test', 'installation-test-password');
  const base = await relay.app.listen({ host: '127.0.0.1', port: 0 });
  const post = (path: string, body: unknown, token?: string) =>
    fetch(base + '/api' + path, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        ...(token ? { Authorization: `Bearer ${token}` } : {}),
      },
      body: JSON.stringify(body),
    });
  const node = new WebSocket(base.replace('http', 'ws') + '/ws/node');
  const opened = once(node, 'open');
  try {
    const owner = (await (
      await post('/auth/login', {
        email: 'owner@example.test',
        password: 'installation-test-password',
      })
    ).json()) as { token: string };
    const first = (await (await post('/pairing-codes', {}, owner.token)).json()) as {
      code: string;
    };
    const credentials = (await (
      await post('/pair', { code: first.code, nodeName: 'VPS', platform: 'linux' })
    ).json()) as { nodeId: string; nodeToken: string };
    await opened;
    const send = (type: string, payload: unknown) => {
      const id = randomUUID();
      node.send(JSON.stringify({ v: 1, id, type, payload }));
      return id;
    };
    const next = async () => JSON.parse(String((await once(node, 'message'))[0])) as Envelope;
    send('hello', { nodeToken: credentials.nodeToken, version: 'test' });
    expect((await next()).type).toBe('hello.ok');

    const id = send('pairing.req', {});
    const answer = await next();
    expect(answer).toMatchObject({ type: 'pairing.res', replyTo: id });
    const result = payloadSchemas['pairing.res'].parse(answer.payload);
    if (!result.ok) throw new Error(result.error.message);
    expect(result.result.sandboxCommand).toBe(
      `curl -fsSL 'https://relay.example/install.sh' | bash -s -- --pair ${result.result.code} --sandbox`,
    );
    const added = await post('/pair', {
      code: result.result.code,
      nodeName: 'Sandbox',
      platform: 'linux',
    });
    expect(added.status).toBe(200);
    const me = (await (
      await fetch(base + '/api/me', { headers: { Authorization: `Bearer ${owner.token}` } })
    ).json()) as { nodes: { name: string }[] };
    expect(me.nodes.map((n) => n.name).sort()).toEqual(['Sandbox', 'VPS']);
  } finally {
    node.close();
    await relay.app.close();
  }
});
