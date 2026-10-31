import { expect, it } from 'vitest';
import { createHash, generateKeyPairSync, verify } from 'node:crypto';
import { mkdir, mkdtemp, readFile, writeFile } from 'node:fs/promises';
import { resolve, join } from 'node:path';
import { execFileSync } from 'node:child_process';
import { nodeReleaseSchema } from '@nekodot/protocol';

it('stamps a publisher build, verifies its manifest and refuses missing placeholders or keys', async () => {
  await mkdir('.runtime/node-update-tests', { recursive: true });
  const home = await mkdtemp(resolve('.runtime/node-update-tests/release-'));
  await mkdir(join(home, 'dist/distribution'), { recursive: true });
  const keys = generateKeyPairSync('ed25519');
  const keyFile = join(home, 'test-private.pem');
  await writeFile(keyFile, keys.privateKey.export({ type: 'pkcs8', format: 'pem' }));
  const artifact = join(home, 'dist/distribution/nekodot-node.cjs');
  await writeFile(
    artifact,
    "const version='__NEKODOT_NODE_VERSION__'; const key='__NEKODOT_RELEASE_KEY__';",
  );
  const command = [resolve('scripts/release-node.mjs'), '20261031010000'];
  const env = { ...process.env, NEKODOT_RELEASE_KEY_FILE: keyFile };
  execFileSync(process.execPath, command, { cwd: home, env, stdio: 'pipe' });
  const release = nodeReleaseSchema.parse(
    JSON.parse(await readFile(join(home, 'dist/distribution/nekodot-node.json'), 'utf8')),
  );
  expect(
    createHash('sha256')
      .update(await readFile(artifact))
      .digest('hex'),
  ).toBe(release.sha256);
  expect(
    verify(
      null,
      Buffer.from(`nekodot-node:${release.version}:${release.sha256}`),
      keys.publicKey,
      Buffer.from(release.signature, 'base64'),
    ),
  ).toBe(true);
  expect(() =>
    execFileSync(process.execPath, command, { cwd: home, env, stdio: 'pipe' }),
  ).toThrow();
  expect(() =>
    execFileSync(process.execPath, command, {
      cwd: home,
      env: { ...env, NEKODOT_RELEASE_KEY_FILE: '' },
      stdio: 'pipe',
    }),
  ).toThrow();
});
