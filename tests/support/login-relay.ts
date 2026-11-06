import { mkdir, writeFile } from 'node:fs/promises';
import { resolve, join } from 'node:path';
import { randomBytes } from 'node:crypto';
import { hash, argon2id } from 'argon2';
import { createRelay } from '../../apps/relay/src/server';

// Dedicated real Relay for native login journeys; never uses production accounts.
const directory = resolve(process.env.QA_DATA_DIR ?? '.runtime/core-refactor/login');
const port = Number(process.env.QA_PORT ?? 4475);
await mkdir(directory, { recursive: true });
const relay = await createRelay({
  dataDir: directory,
  jwtSecret: randomBytes(32).toString('hex'),
  publicUrl: `http://127.0.0.1:${port}`,
});
const email = `login-${Date.now()}@example.test`;
const password = randomBytes(24).toString('hex');
const user = relay.database.createUser(email, await hash(password, { type: argon2id }));
relay.database.verifyEmail(user);
await writeFile(
  join(directory, 'defines.json'),
  JSON.stringify({ RELAY_URL: `http://127.0.0.1:${port}`, QA_EMAIL: email, QA_PASSWORD: password }),
);
await relay.app.listen({ port, host: '127.0.0.1' });
console.log(`Isolated login Relay listening on 127.0.0.1:${port}`);
for (const signal of ['SIGINT', 'SIGTERM'] as const)
  process.once(signal, () => void relay.app.close());
