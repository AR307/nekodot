import {
  createCipheriv,
  createDecipheriv,
  createPrivateKey,
  createPublicKey,
  diffieHellman,
  generateKeyPairSync,
  hkdfSync,
  randomBytes,
} from 'node:crypto';
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import type { SecretEnvelope } from '@nekodot/protocol';

export const secretContext = (nodeId: string, botId: string, requestId: string) =>
  Buffer.from(JSON.stringify(['nekodot-secret-v1', nodeId, botId, requestId]));

/** Per-Bot keys live in private node configuration, never in the database or Relay. */
export class BotSecretKeys {
  constructor(private home: string) {}
  private keys(botId: string) {
    const directory = join(this.home, 'private', 'bot-secrets');
    mkdirSync(directory, { recursive: true, mode: 0o700 });
    const path = join(directory, botId + '.json');
    if (!existsSync(path)) {
      const pair = generateKeyPairSync('x25519');
      writeFileSync(
        path,
        JSON.stringify({
          privateKey: pair.privateKey.export({ type: 'pkcs8', format: 'pem' }),
          storageKey: randomBytes(32).toString('base64'),
        }),
        { mode: 0o600, flag: 'wx' },
      );
    }
    return JSON.parse(readFileSync(path, 'utf8')) as { privateKey: string; storageKey: string };
  }
  publicKey(botId: string) {
    return createPublicKey(this.keys(botId).privateKey)
      .export({ type: 'spki', format: 'der' })
      .subarray(-32)
      .toString('base64');
  }
  decrypt(botId: string, context: Buffer, envelope: SecretEnvelope) {
    const peer = Buffer.from(envelope.publicKey, 'base64');
    const salt = Buffer.from(envelope.salt, 'base64');
    const nonce = Buffer.from(envelope.nonce, 'base64');
    const tag = Buffer.from(envelope.tag, 'base64');
    if (peer.length !== 32 || salt.length !== 32 || nonce.length !== 12 || tag.length !== 16)
      throw new Error('Invalid encrypted delivery');
    const publicKey = createPublicKey({
      key: Buffer.concat([Buffer.from('302a300506032b656e032100', 'hex'), peer]),
      type: 'spki',
      format: 'der',
    });
    const shared = diffieHellman({
      privateKey: createPrivateKey(this.keys(botId).privateKey),
      publicKey,
    });
    const key = hkdfSync('sha256', shared, salt, context, 32);
    const cipher = createDecipheriv('aes-256-gcm', Buffer.from(key), nonce);
    cipher.setAAD(context);
    cipher.setAuthTag(tag);
    return Buffer.concat([
      cipher.update(Buffer.from(envelope.ciphertext, 'base64')),
      cipher.final(),
    ]).toString('utf8');
  }
  seal(botId: string, values: Record<string, string>) {
    const nonce = randomBytes(12);
    const cipher = createCipheriv(
      'aes-256-gcm',
      Buffer.from(this.keys(botId).storageKey, 'base64'),
      nonce,
    );
    cipher.setAAD(Buffer.from(botId));
    const encrypted = Buffer.concat([cipher.update(JSON.stringify(values)), cipher.final()]);
    return Buffer.concat([nonce, cipher.getAuthTag(), encrypted]).toString('base64');
  }
  open(botId: string, sealed: string): Record<string, string> {
    const data = Buffer.from(sealed, 'base64');
    const cipher = createDecipheriv(
      'aes-256-gcm',
      Buffer.from(this.keys(botId).storageKey, 'base64'),
      data.subarray(0, 12),
    );
    cipher.setAAD(Buffer.from(botId));
    cipher.setAuthTag(data.subarray(12, 28));
    return JSON.parse(
      Buffer.concat([cipher.update(data.subarray(28)), cipher.final()]).toString('utf8'),
    );
  }
}
