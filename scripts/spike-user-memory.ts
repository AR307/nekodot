import { mkdtemp, mkdir, readFile, writeFile, appendFile } from 'node:fs/promises';
import { homedir } from 'node:os';
import { join, resolve } from 'node:path';
import { randomUUID } from 'node:crypto';
import { parseArgs, parseEnv } from 'node:util';
import { setTimeout as delay } from 'node:timers/promises';
import { USER_MEMORY_SEPARATOR } from '@nekodot/protocol';
import { createRelay } from '../apps/relay/src/server';
import { ManagedHermes } from '../apps/node/src/hermes/runtime';
import { NodeApplication } from '../apps/node/src/app';
import { pairNode } from '../apps/node/src/pair';
import { connectRelay } from '../apps/node/src/connection';
import { seedVerifiedAccount } from '../tests/support/account';

// Real isolated Linux journey. Credentials and raw native responses stay private.
const { values } = parseArgs({ options: { root: { type: 'string' } } });
const root = resolve(values.root ?? process.cwd());
if (process.platform !== 'linux') throw new Error('Run this journey in isolated WSL/Linux.');
const reference = JSON.parse(
  await readFile(join(root, '.runtime/hermes-last-spike.json'), 'utf8'),
) as { source: string; runtime: string };
const env = parseEnv(await readFile(join(root, '.env'), 'utf8'));
if (!env.NEKODOT_PROVIDER_BASE_URL || !env.NEKODOT_PROVIDER_MODEL || !env.NEKODOT_PROVIDER_API_KEY)
  throw new Error('Local custom API settings are incomplete.');
const parent = join(homedir(), '.cache/nekodot-memory-acceptance');
await mkdir(parent, { recursive: true, mode: 0o700 });
const home = await mkdtemp(join(parent, 'journey-'));
await writeFile(
  join(root, '.runtime/side-phase-3/user-memory-last.json'),
  JSON.stringify({ home }),
);
const relay = await createRelay({
  dataDir: join(home, 'relay'),
  jwtSecret: randomUUID(),
  publicUrl: 'http://127.0.0.1:19710',
});
const url = await relay.app.listen({ host: '127.0.0.1', port: 19710 });
const runtimes: ManagedHermes[] = [];
const nodes: {
  app: NodeApplication;
  runtime: ManagedHermes;
  credentials: Awaited<ReturnType<typeof pairNode>>;
  connection: ReturnType<typeof connectRelay>;
  botId: string;
  conversationId: string;
  read(name?: string): Promise<string>;
}[] = [];
const capture: Record<string, unknown> = {};
const checks: Record<string, boolean | number | string> = {
  environment: 'isolated WSL Ubuntu 24.04; native Hermes and actual custom model',
};
async function until(condition: () => boolean | Promise<boolean>, label: string) {
  const end = Date.now() + 240_000;
  while (Date.now() < end) {
    if (await condition()) return;
    await delay(250);
  }
  throw new Error('Real shared-memory check timed out: ' + label);
}
const attach = (app: NodeApplication, credentials: Awaited<ReturnType<typeof pairNode>>) => {
  const connection = connectRelay({
    credentials,
    handleRpc: (request) => app.handle(request),
    userMemory: app.userMemory,
  });
  app.onEvent = connection.event;
  app.onLive = connection.live;
  return connection;
};
try {
  const accounts: string[] = [];
  for (let i = 0; i < 2; i++) {
    const email = 'memory-' + randomUUID() + '@example.test',
      password = randomUUID();
    await seedVerifiedAccount(relay.database, email, password);
    const login = await relay.app.inject({
      method: 'POST',
      url: '/api/auth/login',
      payload: { email, password },
    });
    accounts.push(login.json().token);
  }
  for (let i = 0; i < 3; i++) {
    let runtime = runtimes[i];
    if (i < 2) {
      runtime = new ManagedHermes({
        home: join(home, 'hermes-' + i),
        source: reference.source,
        runtime: reference.runtime,
        apiPort: 19712 + i * 2,
        managementPort: 19713 + i * 2,
        onLog: (text) => {
          void appendFile(join(home, 'hermes-' + i + '.log'), text);
        },
      });
      runtimes.push(runtime);
      await runtime.start();
    } else runtime = runtimes[1]!;
    const app = new NodeApplication(join(home, 'node-' + i), runtime!);
    const source = await app.providers.set({
      kind: 'custom',
      name: 'Memory acceptance API',
      baseUrl: env.NEKODOT_PROVIDER_BASE_URL,
      apiKey: env.NEKODOT_PROVIDER_API_KEY,
    });
    const { bot, conversation } = await app.bots.create({
      displayName: ['Maple', 'Cedar', 'Quartz'][i]!,
      handle: 'memory-' + i,
      role: 'Be concise. Use the native memory tool when the user explicitly asks to remember a preference. Keep user facts in user memory and task facts in task memory.',
      sourceId: source.sourceId,
      model: env.NEKODOT_PROVIDER_MODEL,
      avatar: { shape: 'dot', color: '#E8603C' },
    });
    const code = await relay.app.inject({
      method: 'POST',
      url: '/api/pairing-codes',
      headers: { authorization: 'Bearer ' + accounts[i < 2 ? 0 : 1] },
    });
    const credentials = await pairNode(
      join(home, 'node-' + i),
      url,
      code.json().code,
      'Memory computer ' + i,
    );
    const read = async (name = 'USER.md') => {
      try {
        return await readFile(join(runtime!.profileHome(bot.botId), 'memories', name), 'utf8');
      } catch (error) {
        if ((error as NodeJS.ErrnoException).code === 'ENOENT') return '';
        throw error;
      }
    };
    nodes.push({
      app,
      runtime: runtime!,
      credentials,
      connection: attach(app, credentials),
      botId: bot.botId,
      conversationId: conversation.conversationId,
      read,
    });
  }
  const [a, b, other] = nodes;
  await until(
    () =>
      nodes.every(
        (n) => n.app.userMemory.view().connected && n.app.userMemory.view().shared?.initialized,
      ),
    'initial connection',
  );
  const originals = await Promise.all(
    nodes.map(async (n) => ({
      soul: await readFile(join(n.runtime.profileHome(n.botId), 'SOUL.md'), 'utf8'),
      task: await n.read('MEMORY.md'),
    })),
  );
  async function chat(node: typeof a, text: string, label: string) {
    await node!.app.handle({
      method: 'messages.send',
      params: { conversationId: node!.conversationId, clientMsgId: randomUUID(), text },
    });
    await until(() => !node!.app.database.runs().length, label);
    const messages = node!.app.database.messages(node!.conversationId);
    capture[label] = messages;
    const reply = messages.filter((m) => m.kind === 'text' && m.author.type === 'bot').at(-1);
    if (!reply || reply.status !== 'done' || reply.kind !== 'text')
      throw new Error(label + ' failed; see private evidence.');
    return reply.content.text;
  }
  console.log('Real profiles ready; asking native memory to remember a harmless preference.');
  await chat(
    a,
    'Use the native memory tool (target=user, action=add) to remember this exact user fact: "My preferred temperature unit is Celsius. My preference verification tag is MAPLE-USER-SHARED." Do not put this in task memory. Then reply briefly.',
    'nativeWrite',
  );
  await until(
    async () => (await b!.read()).includes('MAPLE-USER-SHARED'),
    'native write reaches second computer',
  );
  checks.nativeMemoryToolUsed = a!.app.database
    .messages(a!.conversationId)
    .some((m) => m.kind === 'tool' && m.content.tool === 'memory');
  checks.crossComputerNativeWrite =
    (await a!.read()).includes('MAPLE-USER-SHARED') &&
    (await b!.read()).includes('MAPLE-USER-SHARED');
  const reply = await chat(
    b,
    'Without using tools: from your user memory, what is my preferred temperature unit and preference verification tag? Give both exactly in one sentence.',
    'independentSessionRead',
  );
  checks.independentNativeSessionRead =
    reply.includes('MAPLE-USER-SHARED') && /Celsius/i.test(reply);
  const aFile = join(a!.runtime.profileHome(a!.botId), 'memories', 'USER.md');
  await a!.runtime.management.request('/api/fs/write-text', a!.botId, {
    method: 'POST',
    body: JSON.stringify({
      profile: a!.botId,
      path: aFile,
      content: (await a!.read()) + USER_MEMORY_SEPARATOR + 'Prefers local times in status reports.',
    }),
  });
  await until(async () => (await b!.read()).includes('Prefers local times'), 'native file watcher');
  checks.nativeFileWatcher = true;
  checks.otherAccountIsolated = !(await other!.read()).includes('MAPLE-USER-SHARED');
  const beforeIds = b!.app.database.messages(b!.conversationId).map((m) => m.messageId);
  b!.connection.close();
  await b!.app.close();
  b!.app = new NodeApplication(join(home, 'node-1'), b!.runtime);
  b!.connection = attach(b!.app, b!.credentials);
  await until(
    () =>
      b!.app.userMemory.view().connected &&
      !!b!.app.userMemory.view().shared?.content.includes('MAPLE-USER-SHARED'),
    'Node restart',
  );
  checks.restartPreservesMemory = (await b!.read()).includes('Prefers local times');
  checks.noRunReplay =
    !b!.app.database.runs().length &&
    JSON.stringify(beforeIds) ===
      JSON.stringify(b!.app.database.messages(b!.conversationId).map((m) => m.messageId));
  checks.botIdentityAndTaskMemoryIndependent = (
    await Promise.all(
      nodes.map(
        async (n, i) =>
          (await readFile(join(n.runtime.profileHome(n.botId), 'SOUL.md'), 'utf8')) ===
            originals[i]!.soul && (await n.read('MEMORY.md')) === originals[i]!.task,
      ),
    )
  ).every(Boolean);
  capture.userFiles = await Promise.all(nodes.map((n) => n.read()));
  capture.shared = a!.app.userMemory.view();
  if (Object.values(checks).some((v) => v === false))
    throw new Error('A real memory check failed; see private evidence.');
  await writeFile(
    join(root, 'docs/evidence/side-phase3-user-memory-native.json'),
    JSON.stringify(checks, null, 2) + '\n',
  );
  console.log(
    'Native memory writes, second-computer reads, file watcher, account isolation and restart passed.',
  );
} finally {
  await writeFile(join(home, 'capture.json'), JSON.stringify({ checks, capture }, null, 2));
  for (const n of nodes) {
    n.connection.close();
    await n.app.close();
  }
  for (const runtime of runtimes) await runtime.close();
  await relay.app.close();
}
