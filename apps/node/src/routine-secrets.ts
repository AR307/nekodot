import { createCipheriv, createDecipheriv, createHash, randomBytes } from 'node:crypto';
import { mkdirSync, readFileSync, writeFileSync, existsSync } from 'node:fs';
import { join } from 'node:path';

/** Only the public webhook credential lives here; Hermes owns its internal credentials. */
export class RoutineSecrets {
  private key: Buffer;
  constructor(home: string) {
    const directory = join(home, 'private');
    mkdirSync(directory, { recursive: true, mode: 0o700 });
    const path = join(directory, 'routines.key');
    if (!existsSync(path)) writeFileSync(path, randomBytes(32), { mode: 0o600, flag: 'wx' });
    this.key = readFileSync(path);
  }
  seal(secret: string) {
    const iv = randomBytes(12);
    const cipher = createCipheriv('aes-256-gcm', this.key, iv);
    const bytes = Buffer.concat([cipher.update(secret, 'utf8'), cipher.final()]);
    return Buffer.concat([iv, cipher.getAuthTag(), bytes]).toString('base64');
  }
  open(value: string) {
    const bytes = Buffer.from(value, 'base64');
    const cipher = createDecipheriv('aes-256-gcm', this.key, bytes.subarray(0, 12));
    cipher.setAuthTag(bytes.subarray(12, 28));
    return Buffer.concat([cipher.update(bytes.subarray(28)), cipher.final()]).toString('utf8');
  }
}
export const routineDigest = (value: string) => createHash('sha256').update(value).digest('hex');
