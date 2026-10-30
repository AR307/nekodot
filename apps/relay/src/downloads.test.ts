import { seedVerifiedAccount } from '../../../tests/support/account';
import { it, expect } from 'vitest';
import { mkdtemp, mkdir, copyFile, writeFile, readFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { build } from 'esbuild';
import { createRelay } from './server';

it('downloads the installer and standalone node, then pairs outside the checkout', async () => {
  const directory = await mkdtemp(join(tmpdir(), 'nekodot-download-'));
  const distribution = join(directory, 'distribution');
  await mkdir(distribution);
  await copyFile('deploy/install.sh', join(distribution, 'install.sh'));
  await build({
    entryPoints: [resolve('apps/node/src/index.ts')],
    outfile: join(distribution, 'nekodot-node.cjs'),
    bundle: true,
    platform: 'node',
    format: 'cjs',
    target: 'node24',
  });
  const relay = await createRelay({
    dataDir: join(directory, 'relay'),
    jwtSecret: 'standalone-download-test-secret',
    publicUrl: 'http://127.0.0.1:4329',
    distributionDirectory: distribution,
  });
  await seedVerifiedAccount(relay.database, 'install@example.test', 'install-password');
  const base = await relay.app.listen({ host: '127.0.0.1', port: 0 });
  try {
    for (const name of ['nekodot-windows-x64.exe', 'nekodot-android-arm64.apk']) {
      const unpublished = await fetch(base + '/downloads/' + name);
      expect(unpublished.status).toBe(404);
      expect(await unpublished.json()).toMatchObject({ error: { code: 'not_found' } });
    }
    const signup = await fetch(base + '/api/auth/login', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ email: 'install@example.test', password: 'install-password' }),
    });
    const { token } = (await signup.json()) as { token: string };
    const pairing = await fetch(base + '/api/pairing-codes', {
      method: 'POST',
      headers: { Authorization: 'Bearer ' + token },
    });
    const { code, installCommand } = (await pairing.json()) as {
      code: string;
      installCommand: string;
    };
    expect(installCommand).toContain('/install.sh');
    expect(installCommand).toContain('--pair ' + code);
    const installer = await fetch(base + '/install.sh');
    expect(installer.headers.get('cache-control')).toBe('no-store');
    const installerBody = await installer.text();
    expect(installerBody).toContain("relay='http://127.0.0.1:4329'");
    expect(installerBody).toContain('--relay-ssh-known-hosts');
    const artifact = join(directory, 'nekodot-node.cjs');
    await writeFile(artifact, await (await fetch(base + '/downloads/nekodot-node.cjs')).text());
    const home = join(directory, 'node');
    await promisify(execFile)(
      process.execPath,
      [artifact, 'pair', '--relay', base, '--code', code],
      {
        cwd: directory,
        env: { ...process.env, NEKODOT_HOME: home },
      },
    );
    const saved = JSON.parse(await readFile(join(home, 'node.json'), 'utf8')) as { nodeId: string };
    const me = await fetch(base + '/api/me', { headers: { Authorization: 'Bearer ' + token } });
    expect(await me.json()).toMatchObject({ nodes: [{ nodeId: saved.nodeId }] });
  } finally {
    await relay.app.close();
  }
}, 20000);
