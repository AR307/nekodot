import { mkdtemp, mkdir, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { randomUUID } from 'node:crypto';
import { startFakeHermes, recordedManagementRuntime } from '@nekodot/fake-hermes';
import { createRelay } from '../../apps/relay/src/server';
import { NodeApplication } from '../../apps/node/src/app';
import { pairNode } from '../../apps/node/src/pair';
import { connectRelay } from '../../apps/node/src/connection';
import { HermesApi } from '../../apps/node/src/hermes/api';
import type { HermesRuntime } from '../../apps/node/src/hermes/runtime';
import { seedVerifiedAccount } from './account';

/** Opt-in Flutter journey environment. Never imported by the product. */
const home = await mkdtemp(join(tmpdir(), 'nekodot-native-extensions-'));
const key = randomUUID(),
  password = randomUUID();
const email = `native-${randomUUID()}@example.test`;
const relayUrl = 'http://127.0.0.1:4383';
const fake = await startFakeHermes({
  fixturesDirectory: join(process.cwd(), 'docs/fixtures'),
  profiles: ['default'],
  apiKey: key,
  allowProfileCreate: true,
});
const relay = await createRelay({
  dataDir: join(home, 'relay'),
  jwtSecret: randomUUID(),
  publicUrl: relayUrl,
});
await relay.app.listen({ host: '127.0.0.1', port: 4383 });
await seedVerifiedAccount(relay.database, email, password);
const login = await relay.app.inject({
  method: 'POST',
  url: '/api/auth/login',
  payload: { email, password },
});
const code = await relay.app.inject({
  method: 'POST',
  url: '/api/pairing-codes',
  headers: { authorization: 'Bearer ' + login.json().token },
});
const credentials = await pairNode(
  join(home, 'node'),
  relayUrl,
  code.json().code,
  'Native replay computer',
);
const runtime: HermesRuntime = {
  ...recordedManagementRuntime(fake.url, key, home, fake.pluginCatalog),
  start: async () => {},
  close: async () => {},
  configureProvider: async () => {},
  approvalMode: async () => 'manual',
  models: async () => ({ models: ['recorded-model'] }),
  api: async (profile) => new HermesApi(fake.url + '/p/' + profile, key),
  configureBot: async (bot) => {
    await fetch(fake.url + '/test/profiles', {
      method: 'POST',
      headers: { Authorization: 'Bearer ' + key, 'Content-Type': 'application/json' },
      body: JSON.stringify({ profile: bot.botId }),
    });
  },
};
const app = new NodeApplication(join(home, 'node'), runtime);
await app.handle({
  method: 'providers.set',
  params: {
    kind: 'custom',
    baseUrl: 'https://example.test/v1',
    apiKey: 'recorded-test-only',
    defaultModel: 'recorded-model',
  },
});
await app.bots.create({
  displayName: 'Maple',
  handle: 'maple',
  role: 'Documentation journey',
  model: 'recorded-model',
  avatar: { shape: 'dot', color: '#E8603C' },
});
const connection = connectRelay({
  credentials,
  handleRpc: (request) => app.handle(request),
  handleTransfer: (request) => app.files.transfer(request),
});
app.onEvent = connection.event;
app.onLive = connection.live;
await mkdir('.runtime/side-phase-3/private', { recursive: true });
await writeFile(
  '.runtime/side-phase-3/private/native-extensions.json',
  JSON.stringify(
    { RELAY_URL: relayUrl, QA_EMAIL: email, QA_PASSWORD: password, QA_NODE: credentials.nodeId },
    null,
    2,
  ),
);
console.log(
  'Isolated native replay ready on loopback 4383; generated credentials are in the private Dart-defines file. This is recorded management replay, not real-model acceptance.',
);
async function close() {
  connection.close();
  runtime.management.close();
  await app.close();
  await fake.close();
  await relay.app.close();
}
process.once('SIGINT', () => {
  void close();
});
process.once('SIGTERM', () => {
  void close();
});
