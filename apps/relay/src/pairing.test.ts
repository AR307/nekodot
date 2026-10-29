import { expect, it } from 'vitest';
import { mkdtemp } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { createRelay } from './server';

it('keeps the same install code valid through a long installation and only lets its owner extend it', async () => {
  const relay = await createRelay({
    dataDir: await mkdtemp(join(tmpdir(), 'nekodot-long-install-')),
    jwtSecret: 'isolated-pairing-test-secret',
    publicUrl: 'http://127.0.0.1',
  });
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
      await post('/auth/signup', {
        email: 'installer@example.test',
        password: 'installation-test-password',
      })
    ).json()) as { token: string };
    const other = (await (
      await post('/auth/signup', {
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
