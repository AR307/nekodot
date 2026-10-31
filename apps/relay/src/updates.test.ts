import { expect, it } from 'vitest';
import { mkdir, mkdtemp, writeFile, rename } from 'node:fs/promises';
import { resolve, join } from 'node:path';
import { randomUUID } from 'node:crypto';
import { WebSocket } from 'ws';
import type { Envelope } from '@nekodot/protocol';
import { createRelay } from './server';
import { seedVerifiedAccount } from '../../../tests/support/account';

it('offers releases on node/client hello, leaves legacy nodes connected and refreshes the manual command', async () => {
  await mkdir('.runtime/node-update-tests', { recursive: true });
  const home = await mkdtemp(resolve('.runtime/node-update-tests/relay-'));
  const release = { version: '20261031020000', sha256: 'ab'.repeat(32), signature: 'test' };
  await writeFile(join(home, 'nekodot-node.json'), JSON.stringify(release));
  const relay = await createRelay({
    dataDir: join(home, 'db'),
    distributionDirectory: home,
    jwtSecret: 'isolated-update-test-secret',
    publicUrl: 'https://relay.example.test',
  });
  const owner = await seedVerifiedAccount(relay.database, 'update@example.test', 'update-password');
  const token = (
    await relay.app.inject({
      method: 'POST',
      url: '/api/auth/login',
      payload: { email: 'update@example.test', password: 'update-password' },
    })
  ).json<{ token: string }>().token;
  const pair = relay.database.pairingCode(owner);
  const credentials = relay.database.pair(pair.code, 'Test server', 'linux')!;
  const base = await relay.app.listen({ host: '127.0.0.1', port: 0 });
  const sockets: WebSocket[] = [];
  async function channel(kind: string, payload: unknown) {
    const socket = new WebSocket(base.replace('http', 'ws') + '/ws/' + kind);
    sockets.push(socket);
    const messages: Envelope[] = [];
    socket.on('message', (raw) => messages.push(JSON.parse(raw.toString()) as Envelope));
    await new Promise<void>((ok) => socket.once('open', ok));
    socket.send(JSON.stringify({ v: 1, id: randomUUID(), type: 'hello', payload }));
    await expect.poll(() => messages[0]?.type).toBe('hello.ok');
    return { socket, messages };
  }
  const me = async () =>
    (
      await relay.app.inject({ url: '/api/me', headers: { authorization: 'Bearer ' + token } })
    ).json<{ nodes: { updateCommand: string | null }[] }>();
  try {
    expect((await fetch(base + '/downloads/nekodot-node.json')).headers.get('cache-control')).toBe(
      'no-store',
    );
    const legacy = await channel('node', { nodeToken: credentials.nodeToken, version: '1.0.0' });
    await channel('client', { token });
    await new Promise((ok) => setTimeout(ok, 100));
    expect(legacy.messages.some((e) => e.type === 'node.update')).toBe(false);
    expect(legacy.socket.readyState).toBe(WebSocket.OPEN);
    expect((await me()).nodes[0]?.updateCommand).toBe(
      "curl -fsSL 'https://relay.example.test/install.sh' | bash",
    );
    const old = await channel('node', {
      nodeToken: credentials.nodeToken,
      version: '20261031010000',
    });
    await expect
      .poll(() => old.messages.find((e) => e.type === 'node.update')?.payload)
      .toEqual({ version: release.version });
    expect((await me()).nodes[0]?.updateCommand).toBeNull();
    const current = await channel('node', {
      nodeToken: credentials.nodeToken,
      version: release.version,
    });
    await new Promise((ok) => setTimeout(ok, 100));
    expect(current.messages.some((e) => e.type === 'node.update')).toBe(false);
    // Publication without a Relay restart is discovered on the next client hello.
    release.version = '20261031030000';
    await writeFile(join(home, 'nekodot-node.json'), JSON.stringify(release));
    await channel('client', { token });
    await expect
      .poll(() => current.messages.filter((e) => e.type === 'node.update').length)
      .toBe(1);
    await rename(join(home, 'nekodot-node.json'), join(home, 'saved-manifest.json'));
    expect((await fetch(base + '/downloads/nekodot-node.json')).status).toBe(404);
    const ahead = await channel('node', {
      nodeToken: credentials.nodeToken,
      version: '20261031040000',
    });
    await channel('client', { token });
    await new Promise((ok) => setTimeout(ok, 100));
    expect(ahead.messages.some((e) => e.type === 'node.update')).toBe(false);
    await writeFile(join(home, 'nekodot-node.json'), '{invalid');
    expect((await fetch(base + '/downloads/nekodot-node.json')).status).toBe(404);
  } finally {
    for (const socket of sockets) socket.terminate();
    await relay.app.close();
  }
});
