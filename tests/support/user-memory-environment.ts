import { randomUUID } from 'node:crypto';
import type { Bot, Conversation } from '@nekodot/protocol';
import { mkdtemp, writeFile, mkdir } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { setTimeout as delay } from 'node:timers/promises';
import { startFakeHermes, recordedManagementRuntime } from '@nekodot/fake-hermes';
import { createRelay } from '../../apps/relay/src/server';
import { NodeApplication } from '../../apps/node/src/app';
import { pairNode } from '../../apps/node/src/pair';
import { connectRelay } from '../../apps/node/src/connection';
import { HermesApi } from '../../apps/node/src/hermes/api';
import type { HermesRuntime } from '../../apps/node/src/hermes/runtime';
import { seedVerifiedAccount } from './account';

/** Three independent native-management replays; two computers share one account. */
export async function userMemoryEnvironment(port = 0) {
  const home = await mkdtemp(join(tmpdir(), 'nekodot-shared-user-'));
  const relay = await createRelay({
    dataDir: join(home, 'relay'),
    jwtSecret: randomUUID(),
    publicUrl: 'http://127.0.0.1',
    webDirectory: join(process.cwd(), 'apps/web/dist'),
  });
  const url = await relay.app.listen({ host: '127.0.0.1', port });
  const accounts = [];
  for (let i = 0; i < 2; i++) {
    const email = `memory-${randomUUID()}@example.test`,
      password = randomUUID();
    await seedVerifiedAccount(relay.database, email, password);
    const login = await relay.app.inject({
      method: 'POST',
      url: '/api/auth/login',
      payload: { email, password },
    });
    accounts.push({ email, password, token: login.json().token as string });
  }
  const nodes: {
    bot: Bot;
    conversation: Conversation;
    runtime: HermesRuntime;
    credentials: Awaited<ReturnType<typeof pairNode>>;
    write(content: string, name?: string): Promise<unknown>;
    read(name?: string): Promise<string>;
    fake: Awaited<ReturnType<typeof startFakeHermes>>;
    readonly app: NodeApplication;
    disconnect(): Promise<void>;
    reconnect(): void;
    restart(): Promise<void>;
    close(): Promise<void>;
  }[] = [];
  for (let i = 0; i < 3; i++) {
    const key = randomUUID(),
      nodeHome = join(home, 'node-' + i);
    const fake = await startFakeHermes({
      fixturesDirectory: join(process.cwd(), 'docs/fixtures'),
      profiles: ['default'],
      apiKey: key,
      allowProfileCreate: true,
    });
    const runtime: HermesRuntime = {
      ...recordedManagementRuntime(fake.url, key, nodeHome, fake.pluginCatalog),
      start: async () => {},
      close: async () => {},
      approvalMode: async () => 'manual',
      api: async (profile) => new HermesApi(fake.url + '/p/' + profile, key),
      configureBot: async (bot, create) => {
        if (create)
          await fetch(fake.url + '/test/profiles', {
            method: 'POST',
            headers: { Authorization: 'Bearer ' + key, 'Content-Type': 'application/json' },
            body: JSON.stringify({ profile: bot.botId }),
          });
      },
    };
    let app = new NodeApplication(nodeHome, runtime);
    const source = await app.providers.set({
      kind: 'custom',
      name: 'Recorded API',
      baseUrl: 'https://models.example.test/v1',
      apiKey: 'test-only-memory',
    });
    const { bot, conversation } = await app.bots.create({
      displayName: ['Maple', 'Cedar', 'Quartz'][i]!,
      handle: 'memory-' + i,
      role: 'Independent native profile',
      model: 'recorded-model',
      sourceId: source.sourceId,
      avatar: { shape: 'dot', color: '#E8603C' },
    });
    const memoryPath = (name: string) => join(runtime.profileHome(bot.botId), 'memories', name);
    const write = (content: string, name = 'USER.md') =>
      runtime.management.request('/api/fs/write-text', bot.botId, {
        method: 'POST',
        body: JSON.stringify({ profile: bot.botId, path: memoryPath(name), content }),
      });
    const read = async (name = 'USER.md') =>
      (
        await runtime.management.request<{ text: string }>(
          '/api/fs/read-text?path=' + encodeURIComponent(memoryPath(name)),
          bot.botId,
        )
      ).text;
    await write(
      i === 0 ? 'Prefers concise answers.' : i === 1 ? 'Uses metric units.' : 'OTHER_ACCOUNT_ONLY',
    );
    const code = await relay.app.inject({
      method: 'POST',
      url: '/api/pairing-codes',
      headers: { authorization: 'Bearer ' + accounts[i < 2 ? 0 : 1]!.token },
    });
    const credentials = await pairNode(
      nodeHome,
      url,
      code.json().code,
      ['Computer A', 'Computer B', 'Other account computer'][i],
    );
    const connect = () => {
      const connection = connectRelay({
        version: 'development',
        credentials,
        handleRpc: (request) => app.handle(request),
        userMemory: app.userMemory,
      });
      app.onEvent = connection.event;
      app.onLive = connection.live;
      return connection;
    };
    let connection = connect();
    nodes.push({
      bot,
      conversation,
      runtime,
      credentials,
      write,
      read,
      fake,
      get app() {
        return app;
      },
      disconnect: async () => {
        connection.close();
        while (app.userMemory.view().connected) await delay(10);
      },
      reconnect: () => {
        connection = connect();
      },
      restart: async () => {
        connection.close();
        await app.close();
        app = new NodeApplication(nodeHome, runtime);
        connection = connect();
      },
      close: async () => {
        connection.close();
        await app.close();
        runtime.management.close();
        await fake.close();
      },
    });
  }
  const until = Date.now() + 10_000;
  while (nodes.some((node) => !node.app.userMemory.view().shared) && Date.now() < until)
    await delay(20);
  return {
    home,
    url,
    relay,
    accounts,
    nodes,
    close: async () => {
      for (const node of nodes) await node.close();
      await relay.app.close();
    },
  };
}

if (process.argv.includes('--serve')) {
  const environment = await userMemoryEnvironment(4388);
  await mkdir('.runtime/side-phase-3/private', { recursive: true });
  await writeFile(
    '.runtime/side-phase-3/private/native-user-memory.json',
    JSON.stringify({
      RELAY_URL: environment.url,
      QA_EMAIL: environment.accounts[0]!.email,
      QA_PASSWORD: environment.accounts[0]!.password,
      QA_NODE: environment.nodes[0]!.credentials.nodeId,
    }),
  );
  console.log(
    'Shared-memory QA environment on loopback 4388; private credentials retained. Recorded replay is not real-model acceptance.',
  );
  for (const signal of ['SIGTERM', 'SIGINT'])
    process.once(signal, () => {
      void environment.close();
    });
}
