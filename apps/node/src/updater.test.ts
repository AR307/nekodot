import { expect, it, vi } from 'vitest';
import { createHash, generateKeyPairSync, sign } from 'node:crypto';
import { createServer } from 'node:http';
import { mkdir, mkdtemp, writeFile, readFile } from 'node:fs/promises';
import { existsSync } from 'node:fs';
import { resolve, join } from 'node:path';
import { NodeUpdater } from './updater';

it('keeps running on bad releases, waits for work and switches with recoverable markers', async () => {
  await mkdir('.runtime/node-update-tests', { recursive: true });
  const home = await mkdtemp(resolve('.runtime/node-update-tests/updater-'));
  await mkdir(join(home, 'bin'));
  const file = join(home, 'bin/nekodot-node.cjs');
  const original = "console.log('old service');";
  await writeFile(file, original);
  const keys = generateKeyPairSync('ed25519');
  const releaseKey = keys.publicKey.export({ type: 'spki', format: 'der' }).toString('base64');
  let body = "console.log('new service');";
  const release = (version = '20261031020000') => {
    const sha256 = createHash('sha256').update(body).digest('hex');
    return {
      version,
      sha256,
      signature: sign(
        null,
        Buffer.from(`nekodot-node:${version}:${sha256}`),
        keys.privateKey,
      ).toString('base64'),
    };
  };
  let manifest = release();
  let downloads = 0,
    requests = 0,
    restarts = 0,
    idle = false;
  const server = createServer((req, res) => {
    requests++;
    if (req.url?.endsWith('.json')) res.end(JSON.stringify(manifest));
    else {
      downloads++;
      res.end(body);
    }
  });
  await new Promise<void>((ok) => server.listen(0, '127.0.0.1', ok));
  const port = (server.address() as { port: number }).port;
  const logs: string[] = [];
  const options = {
    home,
    relayUrl: `http://127.0.0.1:${port}`,
    version: '20261031010000',
    releaseKey,
    file,
    idle: () => idle,
    log: (message: string) => logs.push(message),
    restart: async () => {
      expect(await readFile(file + '.previous', 'utf8')).toBe(original);
      expect((await readFile(join(home, 'bin/update-pending'), 'utf8')).trim()).toBe(
        manifest.version,
      );
      expect(existsSync(join(home, 'bin/update-tried'))).toBe(false);
      expect(await readFile(file, 'utf8')).toBe(body);
      restarts++;
    },
  };
  const tryOffer = async () => {
    const updater = new NodeUpdater(options);
    await updater.offer();
    updater.close();
  };
  try {
    for (const changed of [{ version: 'development' }, { file: join(home, 'dev.cjs') }]) {
      await new NodeUpdater({ ...options, ...changed }).offer();
    }
    expect(requests).toBe(0);
    manifest.signature = Buffer.alloc(64).toString('base64');
    await tryOffer();
    expect(downloads).toBe(0);
    manifest = release(options.version);
    await tryOffer();
    expect(downloads).toBe(0);
    manifest = release();
    await writeFile(join(home, 'bin/update-rejected'), manifest.version);
    await tryOffer();
    expect(downloads).toBe(0);
    await writeFile(join(home, 'bin/update-rejected'), '20261031000000');
    body += '\n// tampered';
    await tryOffer();
    expect(restarts).toBe(0);
    expect(await readFile(file, 'utf8')).toBe(original);
    manifest = release();
    const updater = new NodeUpdater(options);
    const realSetTimeout = globalThis.setTimeout;
    const clock = vi
      .spyOn(globalThis, 'setTimeout')
      .mockImplementation((...args: Parameters<typeof setTimeout>) => {
        const [fn, ms, ...rest] = args;
        return realSetTimeout(fn, ms === 30_000 ? 30 : ms, ...rest);
      });
    try {
      const updating = updater.offer();
      await expect.poll(() => logs.some((l) => l.includes('waiting for idle'))).toBe(true);
      expect(restarts).toBe(0);
      expect(existsSync(file + '.previous')).toBe(false);
      // A changed signed release while waiting is downloaded again before switching.
      body = "console.log('latest service');";
      manifest = release('20261031030000');
      await writeFile(join(home, 'bin/update-tried'), 'old marker');
      idle = true;
      await updating;
      expect(restarts).toBe(1);
      await updater.confirmReady();
      expect(existsSync(join(home, 'bin/update-pending'))).toBe(false);
      expect(existsSync(join(home, 'bin/recycle'))).toBe(true);
    } finally {
      clock.mockRestore();
      updater.close();
    }
  } finally {
    server.closeAllConnections();
    await new Promise<void>((ok) => server.close(() => ok()));
  }
});
