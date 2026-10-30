import { mkdtemp } from 'node:fs/promises';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { once } from 'node:events';
import { hash, argon2id } from 'argon2';
import { SMTPServer } from 'smtp-server';
import { it, expect } from 'vitest';
import { WebSocket } from 'ws';
import { randomUUID } from 'node:crypto';
import { createRelay } from './server';

it('uses real local SMTP for signup, code limits/replay, legacy verification, revoked sessions and password recovery', async () => {
  const mail: string[] = [];
  const smtp = new SMTPServer({
    disabledCommands: ['AUTH', 'STARTTLS'],
    onData(stream, _session, callback) {
      let body = '';
      stream.on('data', (chunk) => {
        body += String(chunk);
      });
      stream.on('end', () => {
        mail.push(body);
        callback();
      });
    },
  });
  smtp.listen(0, '127.0.0.1');
  await once(smtp.server, 'listening');
  const address = smtp.server.address();
  if (!address || typeof address === 'string') throw new Error('SMTP not listening');
  const relay = await createRelay({
    dataDir: await mkdtemp(join(tmpdir(), 'nekodot-email-')),
    jwtSecret: 'local-email-test-secret',
    publicUrl: 'http://127.0.0.1',
    smtp: {
      host: '127.0.0.1',
      port: address.port,
      secure: false,
      user: '',
      password: '',
      from: 'nekodot@example.test',
    },
  });
  const base = await relay.app.listen({ port: 0, host: '127.0.0.1' });
  const call = (path: string, body: unknown, token?: string, forwarded?: string) =>
    relay.app.inject({
      method: 'POST',
      url: '/api/auth/' + path,
      headers: {
        'content-type': 'application/json',
        ...(token ? { authorization: 'Bearer ' + token } : {}),
        ...(forwarded ? { 'x-forwarded-for': forwarded } : {}),
      },
      payload: JSON.stringify(body),
    });
  const user = { email: 'owner@example.test', password: 'a-real-local-test-password' };
  const getCode = () => mail.at(-1)!.match(/\b\d{6}\b/)![0];
  try {
    expect((await call('signup', user)).statusCode).toBe(400);
    expect(relay.database.userByEmail(user.email)).toBeUndefined();
    expect((await call('code', { email: user.email, purpose: 'signup' })).statusCode).toBe(200);
    const first = getCode();
    expect(
      JSON.stringify(relay.database.db.prepare('SELECT * FROM email_codes').all()),
    ).not.toContain(first);
    expect((await call('code', { email: user.email, purpose: 'signup' })).statusCode).toBe(429);
    for (let i = 0; i < 5; i++)
      expect(
        (await call('signup', { ...user, code: first === '999999' ? '888888' : '999999' }))
          .statusCode,
      ).toBe(400);
    expect((await call('signup', { ...user, code: first })).statusCode).toBe(400);
    relay.database.db.prepare('UPDATE email_sends SET sent_at=sent_at-61000').run();
    await call('code', { email: user.email, purpose: 'signup' });
    const second = getCode();
    if (first !== second)
      expect((await call('signup', { ...user, code: first })).statusCode).toBe(400);
    const created = await call('signup', { ...user, code: second });
    expect(created.statusCode).toBe(200);
    const token = created.json<{ token: string }>().token;
    expect((await call('signup', { ...user, code: second })).statusCode).toBe(400);
    const socket = new WebSocket(base.replace('http', 'ws') + '/ws/client');
    await once(socket, 'open');
    const hello = once(socket, 'message');
    socket.send(JSON.stringify({ v: 1, id: randomUUID(), type: 'hello', payload: { token } }));
    expect(JSON.parse(String((await hello)[0])).type).toBe('hello.ok');
    const closed = once(socket, 'close');
    expect((await call('logout', {}, token)).statusCode).toBe(200);
    expect((await closed)[0]).toBe(4401);
    expect(
      (await relay.app.inject({ url: '/api/me', headers: { authorization: 'Bearer ' + token } }))
        .statusCode,
    ).toBe(401);
    const login = (await call('login', user)).json<{ token: string }>().token;
    await call('code', { email: user.email, purpose: 'reset' });
    // Reset codes are subject to the same email-wide resend window.
    relay.database.db.prepare('UPDATE email_sends SET sent_at=sent_at-61000').run();
    await call('code', { email: user.email, purpose: 'reset' });
    const reset = getCode();
    expect(
      (
        await call('password/reset', {
          email: user.email,
          password: 'new-local-password',
          code: reset,
        })
      ).statusCode,
    ).toBe(200);
    expect(
      (await relay.app.inject({ url: '/api/me', headers: { authorization: 'Bearer ' + login } }))
        .statusCode,
    ).toBe(401);
    const legacyId = relay.database.createUser(
      'legacy@example.test',
      await hash('legacy-password', { type: argon2id }),
    );
    const legacy = { email: 'legacy@example.test', password: 'legacy-password' };
    expect((await call('login', legacy)).json()).toMatchObject({
      error: { code: 'verification_required' },
    });
    await call('code', { ...legacy, purpose: 'verify' });
    expect((await call('verify', { ...legacy, code: getCode() })).statusCode).toBe(200);
    expect(relay.database.userByEmail(legacy.email)?.user_id).toBe(legacyId);
    const existingCount = mail.length;
    expect(
      (await call('code', { email: 'missing@example.test', purpose: 'reset' })).json(),
    ).toEqual({ sent: true, retryAfter: 60 });
    expect(mail).toHaveLength(existingCount);
    // A client-supplied forwarding header cannot change the rate-limit identity.
    expect(
      (
        await call(
          'code',
          { email: 'missing@example.test', purpose: 'reset' },
          undefined,
          '8.8.8.8',
        )
      ).statusCode,
    ).toBe(429);
    expect(relay.database.db.prepare('SELECT DISTINCT ip FROM email_sends').all()).toEqual([
      { ip: '127.0.0.1' },
    ]);
  } finally {
    await relay.app.close();
    await new Promise<void>((resolve) => smtp.close(() => resolve()));
  }
}, 30_000);
