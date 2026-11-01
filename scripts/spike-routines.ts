/** Opt-in real Hermes harness. All paths and credentials come from a private JSON file. */
import { readFile, writeFile, mkdir } from 'node:fs/promises';
import { join } from 'node:path';
import { appendFileSync } from 'node:fs';
import { ManagedHermes } from '../apps/node/src/hermes/runtime';
import { NodeApplication } from '../apps/node/src/app';
import { connectRelay } from '../apps/node/src/connection';
import { pairNode } from '../apps/node/src/pair';
import { nodeCredentialsSchema } from '../packages/protocol/src/index';

const configuration = JSON.parse(await readFile(process.argv[2]!, 'utf8')) as {
  home: string;
  source: string;
  runtime: string;
  providerFile: string;
  relayUrl: string;
  email: string;
  password: string;
  apiPort: number;
};
const q = configuration;
await mkdir(q.home, { recursive: true, mode: 0o700 });
const runtime = new ManagedHermes({
  home: join(q.home, 'hermes'),
  source: q.source,
  runtime: q.runtime,
  apiPort: q.apiPort,
  // Deliberately no model, endpoint, token or native response in normal harness output.
  onLog: (line) => appendFileSync(join(q.home, 'hermes-private.log'), line, { mode: 0o600 }),
});
async function post(path: string, body: unknown, token?: string) {
  const response = await fetch(q.relayUrl + path, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      ...(token ? { Authorization: 'Bearer ' + token } : {}),
    },
    body: JSON.stringify(body),
  });
  if (!response.ok) throw new Error('Harness HTTP ' + response.status + ' at ' + path);
  return (await response.json()) as Record<string, string>;
}
const login = await post('/api/auth/login', { email: q.email, password: q.password });
let credentials;
try {
  credentials = JSON.parse(await readFile(join(q.home, 'node.json'), 'utf8'));
} catch (error) {
  if ((error as NodeJS.ErrnoException).code !== 'ENOENT') throw error;
  const code = await post('/api/pairing-codes', {}, login.token);
  credentials = await pairNode(q.home, q.relayUrl, code.code!, 'Routine acceptance');
}
await runtime.start();
const app = new NodeApplication(q.home, runtime);
await app.routines.start();
const connection = connectRelay({
  credentials: nodeCredentialsSchema.parse(credentials),
  version: 'development',
  routines: app.routines,
  userMemory: app.userMemory,
  handleRpc: (request) => app.handle(request),
  handleTransfer: (request) => app.files.transfer(request),
  onReady: async () => {
    app.activities();
    app.notifications.flush();
  },
  onNotifyAck: (id) => app.notifications.acknowledge(id),
  onError: () => console.error('QA Relay connection error; inspect isolated state.'),
});
app.onEvent = connection.event;
app.onLive = connection.live;
app.notifications.onSend = connection.notify;
if (!app.database.bots().length) {
  // The dedicated private source is supplied explicitly; no other profile is adopted.
  const provider = JSON.parse(await readFile(q.providerFile, 'utf8')) as {
    baseUrl: string;
    apiKey: string;
    model: string;
  };
  const saved = await app.providers.set({
    kind: 'custom',
    name: 'Routine acceptance API',
    baseUrl: provider.baseUrl,
    apiKey: provider.apiKey,
  });
  await app.handle({
    method: 'bots.create',
    params: {
      displayName: 'Routine QA',
      handle: 'routine-qa',
      role: 'Follow the user’s routine instructions precisely. Use the nekodot-routines skill for webhook tasks.',
      sourceId: saved.sourceId,
      model: provider.model,
      approvalMode: 'smart',
      avatar: { shape: 'dot', color: '#E8603C' },
    },
  });
}
await app.resume();
const bot = app.database.bots()[0]!;
const conversation = app.database
  .conversations()
  .find((c) => c.kind === 'dm' && c.botId === bot.botId)!;
await writeFile(
  join(q.home, 'qa-client.json'),
  JSON.stringify({
    RELAY_URL: q.relayUrl,
    QA_EMAIL: q.email,
    QA_PASSWORD: q.password,
    QA_NODE: credentials.nodeId,
    QA_BOT: bot.botId,
    QA_CONVERSATION: conversation.conversationId,
  }),
  { mode: 0o600 },
);
console.log('Real routine harness ready. Private candidate client configuration saved.');
for (const signal of ['SIGINT', 'SIGTERM'] as const)
  process.once(signal, () => {
    void (async () => {
      connection.close();
      await app.close();
      await runtime.close();
    })();
  });
