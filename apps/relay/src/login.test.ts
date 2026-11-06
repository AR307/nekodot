import { mkdtemp } from 'node:fs/promises';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { hash, argon2id } from 'argon2';
import { expect, it } from 'vitest';
import { createRelay } from './server';

it('authenticates login attempts independently of new-password rules over HTTP', async () => {
  const relay = await createRelay({
    dataDir: await mkdtemp(join(tmpdir(), 'nekodot-login-')),
    jwtSecret: 'isolated-login-test',
    publicUrl: 'http://127.0.0.1',
  });
  const email = 'login@example.test';
  const password = 'correct-test-password';
  const user = relay.database.createUser(email, await hash(password, { type: argon2id }));
  relay.database.verifyEmail(user);
  const origin = await relay.app.listen({ port: 0, host: '127.0.0.1' });
  const login = (address: string, value: string) =>
    fetch(origin + '/api/auth/login', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ email: address, password: value }),
    });
  try {
    for (const [address, value] of [
      [email, 'x'],
      [email, 'incorrect-long-password'],
      ['missing@example.test', 'incorrect-long-password'],
    ]) {
      const response = await login(address!, value!);
      expect(response.status).toBe(401);
      expect(await response.json()).toEqual({
        error: { code: 'unauthorized', message: 'Email or password incorrect' },
      });
    }
    expect((await login(email, '')).status).toBe(400);
    const response = await login(email, password);
    expect(response.status).toBe(200);
    const session = (await response.json()) as { token: string };
    const me = await fetch(origin + '/api/me', {
      headers: { Authorization: 'Bearer ' + session.token },
    });
    expect(me.status).toBe(200);
    const signup = await fetch(origin + '/api/auth/signup', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ email: 'new@example.test', password: 'x', code: '123456' }),
    });
    expect(signup.status).toBe(400);
    expect(relay.database.userByEmail('new@example.test')).toBeUndefined();
  } finally {
    await relay.app.close();
  }
});
