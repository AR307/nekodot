import { createHmac, randomInt } from 'node:crypto';
import { createTransport } from 'nodemailer';
import { z } from 'zod';
import { HttpFault } from './auth';
import type { RelayDatabase } from './database';

export const smtpSchema = z.strictObject({
  host: z.string().min(1),
  port: z.number().int().positive(),
  secure: z.boolean(),
  user: z.string(),
  password: z.string(),
  from: z.string().min(1),
});
export type SmtpConfiguration = z.infer<typeof smtpSchema>;
export type CodePurpose = 'signup' | 'verify' | 'reset';

/** SMTP is the only production delivery path. A missing configuration never issues a code. */
export class EmailVerification {
  private readonly transport;
  constructor(
    private readonly database: RelayDatabase,
    private readonly secret: string,
    private readonly smtp?: SmtpConfiguration,
  ) {
    this.transport = smtp
      ? createTransport({
          host: smtp.host,
          port: smtp.port,
          secure: smtp.secure,
          ...(smtp.user ? { auth: { user: smtp.user, pass: smtp.password } } : {}),
          requireTLS: !smtp.secure && !['127.0.0.1', 'localhost', '::1'].includes(smtp.host),
          connectionTimeout: 10_000,
          socketTimeout: 20_000,
        })
      : undefined;
    database.db.exec(`
      CREATE TABLE IF NOT EXISTS email_codes(email TEXT NOT NULL,purpose TEXT NOT NULL,digest TEXT NOT NULL,expires_at INTEGER NOT NULL,attempts INTEGER NOT NULL DEFAULT 0,consumed INTEGER NOT NULL DEFAULT 0,PRIMARY KEY(email,purpose));
      CREATE TABLE IF NOT EXISTS email_sends(email TEXT NOT NULL,ip TEXT NOT NULL,sent_at INTEGER NOT NULL);
      CREATE INDEX IF NOT EXISTS email_sends_time ON email_sends(sent_at);
    `);
  }
  private digest(email: string, purpose: CodePurpose, code: string) {
    return createHmac('sha256', this.secret).update(`${purpose}:${email}:${code}`).digest('hex');
  }
  async send(email: string, purpose: CodePurpose, ip: string, eligible: boolean) {
    if (!this.transport || !this.smtp)
      throw new HttpFault('unavailable', 'Email delivery is not configured yet', 503);
    const now = Date.now();
    const recent = this.database.db
      .prepare(
        'SELECT MAX(sent_at) AS latest,COUNT(*) AS count FROM email_sends WHERE email=? AND sent_at>?',
      )
      .get(email, now - 3_600_000) as { latest: number | null; count: number };
    const source = this.database.db
      .prepare('SELECT COUNT(*) AS count FROM email_sends WHERE ip=? AND sent_at>?')
      .get(ip, now - 3_600_000) as { count: number };
    if ((recent.latest && now - recent.latest < 60_000) || recent.count >= 5 || source.count >= 20)
      throw new HttpFault('rate_limited', 'Please wait before requesting another code', 429);
    this.database.db.prepare('INSERT INTO email_sends VALUES(?,?,?)').run(email, ip, now);
    if (!eligible) return;
    const code = randomInt(0, 1_000_000).toString().padStart(6, '0');
    this.database.db
      .prepare(
        `INSERT INTO email_codes VALUES(?,?,?,?,0,0) ON CONFLICT(email,purpose) DO UPDATE SET digest=excluded.digest,expires_at=excluded.expires_at,attempts=0,consumed=0`,
      )
      .run(email, purpose, this.digest(email, purpose, code), now + 600_000);
    try {
      await this.transport.sendMail({
        from: this.smtp.from,
        to: email,
        subject: 'nekodot · 邮箱验证码 / Email verification',
        text: `你的 nekodot 验证码是 ${code}，10 分钟内有效。请勿分享。\nYour nekodot code is ${code}. It expires in 10 minutes. Do not share it.\n\n如果这不是你的操作，请忽略此邮件。\nIf you did not request this, ignore this email.`,
      });
    } catch {
      this.database.db
        .prepare('UPDATE email_codes SET consumed=1 WHERE email=? AND purpose=?')
        .run(email, purpose);
      throw new HttpFault('unavailable', 'Email delivery failed. Please try again later.', 503);
    }
  }
  consume(email: string, purpose: CodePurpose, code: string) {
    const row = this.database.db
      .prepare('SELECT * FROM email_codes WHERE email=? AND purpose=?')
      .get(email, purpose) as
      { digest: string; expires_at: number; attempts: number; consumed: number } | undefined;
    if (!row || row.consumed || row.expires_at <= Date.now() || row.attempts >= 5)
      throw new HttpFault('invalid_code', 'Code is invalid or expired');
    this.database.db
      .prepare('UPDATE email_codes SET attempts=attempts+1 WHERE email=? AND purpose=?')
      .run(email, purpose);
    if (row.digest !== this.digest(email, purpose, code))
      throw new HttpFault('invalid_code', 'Code is invalid or expired');
    this.database.db
      .prepare('UPDATE email_codes SET consumed=1 WHERE email=? AND purpose=?')
      .run(email, purpose);
  }
  close() {
    this.transport?.close();
  }
}
