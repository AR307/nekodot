import { createHash, createPublicKey, verify } from 'node:crypto';
import { copyFileSync, existsSync, mkdirSync, renameSync, writeFileSync } from 'node:fs';
import { readFile, writeFile } from 'node:fs/promises';
import { join, resolve } from 'node:path';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { nodeReleaseSchema } from '@nekodot/protocol';

interface UpdateOptions {
  home: string;
  relayUrl: string;
  version: string;
  releaseKey: string;
  file: string;
  idle(): boolean;
  restart(): Promise<void>;
  log(message: string): void;
}

export class NodeUpdater {
  private working = false;
  private closed = false;
  private failedAt = 0;
  private timer?: ReturnType<typeof setTimeout>;
  private wake?: () => void;
  constructor(private readonly options: UpdateOptions) {}

  async confirmReady() {
    this.recycle('update-pending');
    this.recycle('update-tried');
  }

  close() {
    this.closed = true;
    clearTimeout(this.timer);
    this.wake?.();
  }

  private recycle(name: string) {
    const file = join(this.options.home, 'bin', name);
    if (!existsSync(file)) return;
    const directory = join(this.options.home, 'bin/recycle');
    mkdirSync(directory, { recursive: true, mode: 0o700 });
    renameSync(file, join(directory, `${name}-${Date.now()}`));
  }

  async offer() {
    const o = this.options;
    if (
      !/^\d{14}$/.test(o.version) ||
      resolve(o.file) !== resolve(o.home, 'bin/nekodot-node.cjs') ||
      this.closed ||
      this.working ||
      (this.failedAt && Date.now() - this.failedAt < 600_000)
    )
      return;
    this.working = true;
    try {
      const key = createPublicKey({
        key: Buffer.from(o.releaseKey, 'base64'),
        type: 'spki',
        format: 'der',
      });
      const base = o.relayUrl.replace(/\/$/, '');
      const manifest = async () => {
        const response = await fetch(base + '/downloads/nekodot-node.json', {
          signal: AbortSignal.timeout(30_000),
        });
        if (!response.ok) throw new Error('Release manifest download failed');
        const release = nodeReleaseSchema.parse(await response.json());
        if (
          !verify(
            null,
            Buffer.from(`nekodot-node:${release.version}:${release.sha256}`),
            key,
            Buffer.from(release.signature, 'base64'),
          )
        )
          throw new Error('Release signature is invalid');
        return release;
      };
      let rejected = '';
      try {
        rejected = (await readFile(join(o.home, 'bin/update-rejected'), 'utf8')).trim();
      } catch (error) {
        if (!(error instanceof Error && 'code' in error && error.code === 'ENOENT')) throw error;
      }
      while (!this.closed) {
        const release = await manifest();
        if (release.version <= o.version || release.version <= rejected) return;
        const response = await fetch(base + '/downloads/nekodot-node.cjs', {
          signal: AbortSignal.timeout(30_000),
        });
        if (!response.ok || !response.body) throw new Error('Node bundle download failed');
        const chunks: Uint8Array[] = [];
        let size = 0;
        const reader = response.body.getReader();
        while (true) {
          const { done, value } = await reader.read();
          if (done) break;
          size += value.length;
          if (size > 32 * 1024 * 1024) {
            await reader.cancel();
            throw new Error('Node bundle exceeds 32 MB');
          }
          chunks.push(value);
        }
        const bundle = Buffer.concat(chunks);
        if (createHash('sha256').update(bundle).digest('hex') !== release.sha256)
          throw new Error('Node bundle does not match its signed manifest');
        const next = o.file + '.next';
        await writeFile(next, bundle, { mode: 0o700 });
        const check = promisify(execFile)(process.execPath, ['--check', '--input-type=commonjs'], {
          timeout: 30_000,
        });
        check.child.stdin!.end(bundle);
        await check;
        o.log(`Node release ${release.version} downloaded; waiting for idle`);
        while (!this.closed && !o.idle())
          await new Promise<void>((ok) => {
            this.wake = ok;
            this.timer = setTimeout(ok, 30_000);
          });
        if (this.closed) return;
        if ((await manifest()).version !== release.version) continue;
        if (!o.idle()) continue;
        // Keep this small local switch synchronous: no new RPC can start between idle and shutdown.
        copyFileSync(o.file, o.file + '.previous');
        writeFileSync(join(o.home, 'bin/update-pending'), release.version + '\n', { mode: 0o600 });
        this.recycle('update-tried');
        renameSync(next, o.file);
        o.log(`Switching to Node release ${release.version}`);
        await o.restart();
        return;
      }
    } catch (error) {
      this.failedAt = Date.now();
      o.log(
        `Node update failed; current service kept: ${error instanceof Error ? error.message : 'Unknown error'}`,
      );
    } finally {
      this.working = false;
    }
  }
}
