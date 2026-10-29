import { DatabaseSync } from 'node:sqlite';
import { randomBytes, randomUUID, createHash } from 'node:crypto';
import { mkdirSync } from 'node:fs';
import { join } from 'node:path';

export interface UserRow {
  user_id: string;
  email: string;
  password_hash: string;
}
export interface NodeRow {
  node_id: string;
  user_id: string;
  name: string;
  platform: string;
}
export const tokenDigest = (token: string) => createHash('sha256').update(token).digest('hex');

export class RelayDatabase {
  readonly db: DatabaseSync;
  constructor(directory: string) {
    mkdirSync(directory, { recursive: true, mode: 0o700 });
    this.db = new DatabaseSync(join(directory, 'relay.db'));
    this.db.exec(`
      PRAGMA journal_mode=WAL;
      CREATE TABLE IF NOT EXISTS users(user_id TEXT PRIMARY KEY,email TEXT UNIQUE NOT NULL,password_hash TEXT NOT NULL);
      CREATE TABLE IF NOT EXISTS nodes(node_id TEXT PRIMARY KEY,user_id TEXT NOT NULL,name TEXT NOT NULL,platform TEXT NOT NULL,token_hash TEXT UNIQUE NOT NULL,revoked INTEGER NOT NULL DEFAULT 0);
      CREATE TABLE IF NOT EXISTS pairing_codes(code TEXT PRIMARY KEY,user_id TEXT NOT NULL,expires_at INTEGER NOT NULL,used INTEGER NOT NULL DEFAULT 0);
      PRAGMA user_version=1;
    `);
  }
  userByEmail(email: string) {
    return this.db.prepare('SELECT * FROM users WHERE email=?').get(email) as unknown as
      UserRow | undefined;
  }
  userById(id: string) {
    return this.db.prepare('SELECT * FROM users WHERE user_id=?').get(id) as unknown as
      UserRow | undefined;
  }
  createUser(email: string, hash: string) {
    const userId = randomUUID();
    this.db.prepare('INSERT INTO users VALUES(?,?,?)').run(userId, email, hash);
    return userId;
  }
  nodes(userId: string) {
    return this.db
      .prepare('SELECT node_id,user_id,name,platform FROM nodes WHERE user_id=? AND revoked=0')
      .all(userId) as unknown as NodeRow[];
  }
  nodeByToken(token: string) {
    return this.db
      .prepare('SELECT node_id,user_id,name,platform FROM nodes WHERE token_hash=? AND revoked=0')
      .get(tokenDigest(token)) as unknown as NodeRow | undefined;
  }
  owns(userId: string, nodeId: string) {
    return !!this.db
      .prepare('SELECT node_id FROM nodes WHERE user_id=? AND node_id=? AND revoked=0')
      .get(userId, nodeId);
  }
  pairingCode(userId: string) {
    const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    const chars = [...randomBytes(8)].map((n) => alphabet[n % alphabet.length]).join('');
    const code = chars.slice(0, 4) + '-' + chars.slice(4);
    const expiresAt = Date.now() + 30 * 60_000;
    this.db.prepare('INSERT INTO pairing_codes VALUES(?,?,?,0)').run(code, userId, expiresAt);
    return { code, expiresAt: new Date(expiresAt).toISOString() };
  }
  extendPairingCode(userId: string, code: string) {
    const row = this.db
      .prepare(
        'UPDATE pairing_codes SET expires_at=MAX(expires_at,?)+? WHERE code=? AND user_id=? AND used=0 RETURNING expires_at',
      )
      .get(Date.now(), 30 * 60_000, code, userId) as { expires_at: number } | undefined;
    return row ? { code, expiresAt: new Date(row.expires_at).toISOString() } : undefined;
  }
  pair(code: string, name: string, platform: string) {
    this.db.exec('BEGIN IMMEDIATE');
    try {
      const row = this.db
        .prepare('SELECT user_id FROM pairing_codes WHERE code=? AND expires_at>? AND used=0')
        .get(code, Date.now()) as { user_id: string } | undefined;
      if (!row) {
        this.db.exec('ROLLBACK');
        return undefined;
      }
      const nodeId = randomUUID();
      const nodeToken = randomBytes(32).toString('hex');
      this.db.prepare('UPDATE pairing_codes SET used=1 WHERE code=?').run(code);
      this.db
        .prepare('INSERT INTO nodes(node_id,user_id,name,platform,token_hash) VALUES(?,?,?,?,?)')
        .run(nodeId, row.user_id, name, platform, tokenDigest(nodeToken));
      this.db.exec('COMMIT');
      return { nodeId, nodeToken };
    } catch (error) {
      this.db.exec('ROLLBACK');
      throw error;
    }
  }
  revoke(userId: string, nodeId: string) {
    this.db.prepare('UPDATE nodes SET revoked=1 WHERE user_id=? AND node_id=?').run(userId, nodeId);
  }
}
