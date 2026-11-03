import { it, expect } from 'vitest';
import { mkdtemp, mkdir, writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import { createRelay } from './server';

it('serves versions and downloads without an account-level server update action', async () => {
  await mkdir('.runtime/product-updates', { recursive: true });
  const home = await mkdtemp('.runtime/product-updates/test-');
  const distribution = join(home, 'distribution');
  const directory = join(distribution, 'releases/0.3.1-7');
  await mkdir(directory, { recursive: true });
  const relay = await createRelay({
    dataDir: join(home, 'data'),
    jwtSecret: 'update-test-local-only',
    publicUrl: 'http://127.0.0.1',
    distributionDirectory: distribution,
  });
  const url = await relay.app.listen({ host: '127.0.0.1', port: 0 });
  try {
    expect(await (await fetch(url + '/api/releases')).json()).toMatchObject({
      relay: { version: '0.3.0' },
      latest: null,
    });
    const bytes = Buffer.from('real transfer boundary bytes');
    await writeFile(join(directory, 'nekodot-windows-x64.exe'), bytes);
    const manifest = {
      schema: 1,
      version: '0.3.1',
      build: 7,
      publishedAt: new Date().toISOString(),
      notes: 'Test release',
      artifacts: {
        windows: { path: 'releases/0.3.1-7/nekodot-windows-x64.exe', size: bytes.length, build: 7 },
        android: { path: 'releases/0.3.1-7/nekodot-android-arm64.apk', size: 1024, build: 2007 },
        relay: {
          path: 'releases/0.3.1-7/nekodot-relay.tar',
          size: 1024,
          build: 7,
          image: 'nekodot-relay:0.3.1-7',
        },
      },
    };
    await writeFile(join(distribution, 'latest.json'), JSON.stringify(manifest));
    const check = await fetch(url + '/api/releases');
    expect(check.headers.get('cache-control')).toBe('no-store');
    expect(await check.json()).toMatchObject({ latest: manifest });
    const download = await fetch(url + '/downloads/' + manifest.artifacts.windows.path);
    expect(Buffer.from(await download.arrayBuffer())).toEqual(bytes);
    expect((await fetch(url + '/downloads/releases/0.3.1-7/private.json')).status).toBe(404);
    expect((await fetch(url + '/api/releases/apply', { method: 'POST' })).status).toBe(404);
    await writeFile(join(distribution, 'latest.json'), '{invalid');
    expect((await fetch(url + '/api/releases')).status).toBe(500);
    expect((await fetch(url + '/health')).status).toBe(200);
  } finally {
    await relay.app.close();
  }
});
