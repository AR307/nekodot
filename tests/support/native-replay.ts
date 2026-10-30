import { mkdtemp, mkdir, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { randomUUID } from 'node:crypto';
import { setTimeout as delay } from 'node:timers/promises';
import { startFakeHermes, recordedManagementRuntime } from '@nekodot/fake-hermes';
import { createRelay } from '../../apps/relay/src/server';
import { NodeApplication } from '../../apps/node/src/app';
import { pairNode } from '../../apps/node/src/pair';
import { connectRelay } from '../../apps/node/src/connection';
import { HermesApi } from '../../apps/node/src/hermes/api';
import type { HermesRuntime } from '../../apps/node/src/hermes/runtime';
import type { ApprovalMode, Bot } from '@nekodot/protocol';
import { seedVerifiedAccount } from './account';

/** Opt-in Flutter journey environment. Never imported by the product. */
const welcome = process.argv.includes('--welcome');
const sources = process.argv.includes('--sources');
const journey = process.argv.includes('--journey');
const home = await mkdtemp(join(tmpdir(), 'nekodot-native-replay-'));
const key = randomUUID(),
  password = randomUUID();
const email = `native-${randomUUID()}@example.test`;
const port = journey ? 4389 : sources ? 4386 : welcome ? 4385 : 4383;
const relayUrl = 'http://127.0.0.1:' + port;
const modes = new Map<string, ApprovalMode>();
let researcher: Bot | undefined;
const fake = await startFakeHermes({
  fixturesDirectory: join(process.cwd(), 'docs/fixtures'),
  profiles: ['default'],
  apiKey: key,
  allowProfileCreate: true,
  ...(journey
    ? {
        eventDelayMs: 30,
        additionalFixtures: ['group-researcher', 'group-writer', 'group-failed'],
        scenarioFor: (input: { instructions?: string; input: string }, profile: string) =>
          input.instructions?.startsWith('Group members:')
            ? profile === researcher?.botId
              ? 'group-researcher'
              : 'group-writer'
            : input.input === 'group-failed'
              ? 'group-failed'
              : undefined,
      }
    : {}),
});
const relay = await createRelay({
  dataDir: join(home, 'relay'),
  jwtSecret: randomUUID(),
  publicUrl: relayUrl,
});
if (journey)
  relay.app.get('/qa/inspect', async () => ({
    runs: fake.inspectRuns(),
    modes: Object.fromEntries(modes),
  }));
await relay.app.listen({ host: '127.0.0.1', port });
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
const failedIntroductions = new Set<string>();
const runtime: HermesRuntime = {
  ...recordedManagementRuntime(fake.url, key, home, fake.pluginCatalog),
  start: async () => {},
  close: async () => {},
  approvalMode: async (profile) => modes.get(profile) ?? 'manual',
  api: async (profile) => {
    const api = new HermesApi(fake.url + '/p/' + profile, key);
    if (failedIntroductions.delete(profile))
      api.createRun = async () => {
        throw new Error('The test gateway is unavailable');
      };
    return api;
  },
  configureBot: async (bot, create, approvalMode) => {
    if (approvalMode) modes.set(bot.botId, approvalMode);
    if (welcome && create && bot.handle === 'retry-intro') failedIntroductions.add(bot.botId);
    await fetch(fake.url + '/test/profiles', {
      method: 'POST',
      headers: { Authorization: 'Bearer ' + key, 'Content-Type': 'application/json' },
      body: JSON.stringify({ profile: bot.botId }),
    });
  },
};
const app = new NodeApplication(join(home, 'node'), runtime);
if (!sources)
  await app.handle({
    method: 'providers.set',
    params: {
      kind: 'custom',
      name: 'Journey API',
      baseUrl: 'https://example.test/v1',
      apiKey: 'recorded-test-only',
    },
  });
if (!welcome && !sources) {
  const sourceId = (await app.providers.list()).sources[0]!.sourceId;
  researcher = (
    await app.bots.create({
      sourceId,
      displayName: 'Maple',
      handle: journey ? 'researcher' : 'maple',
      role: 'Documentation journey',
      model: 'recorded-model',
      avatar: { shape: 'dot', color: '#E8603C' },
      ...(journey ? { approvalMode: 'smart' as const } : {}),
    })
  ).bot;
  if (journey) {
    await app.bots.create({
      sourceId,
      displayName: 'Willow',
      handle: 'writer',
      role: 'Writing specialist',
      model: 'recorded-model',
      avatar: { shape: 'dot', color: '#2F9E8F' },
      approvalMode: 'off',
    });
    const conversation = app.database
      .conversations()
      .find((item) => item.kind === 'dm' && item.botId === researcher!.botId)!;
    const fileId = randomUUID(),
      messageId = randomUUID();
    const storage = join(home, 'node/library');
    await mkdir(storage, { recursive: true });
    const content = '原生文件验收：你好，nekodot。\nNative file acceptance.\n';
    await writeFile(join(storage, fileId), content);
    const attachment = {
      fileId,
      botId: researcher.botId,
      conversationId: conversation.conversationId,
      messageId,
      name: '原生验收.txt',
      mime: 'text/plain',
      size: Buffer.byteLength(content),
      sentAt: new Date().toISOString(),
      available: true,
    };
    app.database.db
      .prepare('INSERT INTO attachments VALUES(?,?,?,?,?,?)')
      .run(
        fileId,
        researcher.botId,
        messageId,
        '/test/原生验收.txt',
        join(storage, fileId),
        JSON.stringify(attachment),
      );
    // Synthetic file-transfer specimen, not a recorded model answer.
    app.database.putMessage({
      messageId,
      conversationId: conversation.conversationId,
      seq: 0,
      author: { type: 'bot', id: researcher.botId },
      status: 'done',
      createdAt: attachment.sentAt,
      kind: 'text',
      content: { text: 'File transfer test specimen', files: [fileId] },
    });
  }
}
const connection = connectRelay({
  credentials,
  handleRpc: async (request) => {
    const result = await app.handle(request);
    if (journey && request.method === 'messages.send') await delay(1200);
    return result;
  },
  userMemory: app.userMemory,
  handleTransfer: (request) => app.files.transfer(request),
});
app.onEvent = connection.event;
app.onLive = connection.live;
await mkdir('.runtime/side-phase-3/private', { recursive: true });
await writeFile(
  `.runtime/side-phase-3/private/native-${journey ? 'journey' : sources ? 'sources' : welcome ? 'welcome' : 'extensions'}.json`,
  JSON.stringify(
    { RELAY_URL: relayUrl, QA_EMAIL: email, QA_PASSWORD: password, QA_NODE: credentials.nodeId },
    null,
    2,
  ),
);
console.log(
  `Isolated native replay ready on loopback ${port}; generated credentials are in the private Dart-defines file. Recorded replay is not real-model acceptance.`,
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
