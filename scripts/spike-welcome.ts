import { mkdtemp, mkdir, readFile, writeFile, appendFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { parseArgs, parseEnv } from 'node:util';
import { setTimeout as delay } from 'node:timers/promises';
import { randomUUID } from 'node:crypto';
import { ManagedHermes } from '../apps/node/src/hermes/runtime';
import { NodeApplication } from '../apps/node/src/app';
import type { Bot, Conversation } from '@nekodot/protocol';
import type { GatewayFrame } from '../apps/node/src/hermes/gateway';

const { values } = parseArgs({ options: { root: { type: 'string' } } });
const root = resolve(values.root ?? process.cwd());
if (process.platform !== 'linux')
  throw new Error('Run this isolated welcome journey in WSL/Linux.');
const reference = JSON.parse(
  await readFile(join(root, '.runtime/hermes-last-spike.json'), 'utf8'),
) as { source: string; runtime: string };
const env = parseEnv(await readFile(join(root, '.env'), 'utf8'));
if (!env.NEKODOT_PROVIDER_BASE_URL || !env.NEKODOT_PROVIDER_MODEL || !env.NEKODOT_PROVIDER_API_KEY)
  throw new Error('The local custom provider configuration is incomplete.');
const home = await mkdtemp(join(tmpdir(), 'nekodot-welcome-'));
const reportRoot = join(root, '.runtime/side-phase-5');
await mkdir(reportRoot, { recursive: true });
const runtime = new ManagedHermes({
  home: join(home, 'hermes'),
  source: reference.source,
  runtime: reference.runtime,
  apiPort: 19682,
  onLog: (text) => {
    void appendFile(join(home, 'hermes.log'), text);
  },
});
let app = new NodeApplication(join(home, 'node'), runtime);
const frames: GatewayFrame[] = [];
let creations = 0;
const nativeGateway = runtime.gateway.bind(runtime);
const wrappedGateways = new WeakSet<object>();
runtime.gateway = (profile) => {
  const gateway = nativeGateway(profile);
  if (wrappedGateways.has(gateway)) return gateway;
  const rpc = gateway.rpc.bind(gateway);
  gateway.rpc = ((method: string, params: Record<string, unknown>, timeoutMs?: number) => {
    if (method === 'prompt.submit') creations++;
    return rpc(method, params, timeoutMs);
  }) as typeof gateway.rpc;
  gateway.listeners.add((frame) => frames.push(frame));
  wrappedGateways.add(gateway);
  return gateway;
};
try {
  await runtime.start();
  await app.handle({
    method: 'providers.set',
    params: {
      kind: 'custom',
      name: 'Journey API',
      baseUrl: env.NEKODOT_PROVIDER_BASE_URL,
      apiKey: env.NEKODOT_PROVIDER_API_KEY,
    },
  });
  const { bot, conversation } = (await app.handle({
    method: 'bots.create',
    params: {
      sourceId: (await app.providers.list()).sources[0]!.sourceId,
      displayName: 'Maple',
      handle: 'maple',
      role: 'You are Maple, a helpful research and coding assistant. Use concise English for this isolated introduction.',
      model: env.NEKODOT_PROVIDER_MODEL,
      avatar: { shape: 'dot', color: '#E8603C' },
    },
  })) as { bot: Bot; conversation: Conversation };
  const deadline = Date.now() + 180_000;
  while (app.database.runs().length && Date.now() < deadline) await delay(200);
  const messages = app.database.messages(conversation.conversationId);
  const reply = messages.find((message) => message.kind === 'text' && message.content.welcome);
  const runId = reply && app.database.messageRun(reply.messageId);
  if (!runId) throw new Error('No real welcome run was created.');
  const storedSession = app.database.hermesSession(conversation.conversationId);
  if (!storedSession) throw new Error('Welcome session was not persisted.');
  const gateway = runtime.gateway(bot.botId);
  const session = await gateway.rpc<{ session_id: string; stored_session_id: string }>(
    'session.resume',
    { session_id: storedSession.storedSessionId },
  );
  const state = await gateway.rpc<{
    outcome?: string | null;
    result?: { final_response?: string };
  }>('prompt.receipt', {
    session_id: session.session_id,
    admission_id: runId,
    include_result: true,
  });
  const output = state.result?.final_response ?? '';
  await writeFile(join(home, 'capture.json'), JSON.stringify({ frames, state, messages }, null, 2));
  if (
    state.outcome !== 'completed' ||
    !output.includes('Maple') ||
    !/[?？]/.test(output) ||
    session.stored_session_id !== storedSession.storedSessionId
  )
    throw new Error(
      'The actual welcome did not complete with an introduction and a question; private capture retained.',
    );
  const catalog = await app.commands.catalog(bot.botId);
  const profileCommand = catalog.commands.find((command) => command.name === '/profile');
  if (!profileCommand) throw new Error('Hermes Gateway command catalog omitted /profile.');
  const profileOperation = (await app.handle({
    method: 'commands.execute',
    params: {
      botId: bot.botId,
      conversationId: conversation.conversationId,
      command: '/profile',
      clientMsgId: randomUUID(),
    },
  })) as { operationId: string };
  const commandDeadline = Date.now() + 30_000;
  while (
    app.operations.get(profileOperation.operationId).status === 'running' &&
    Date.now() < commandDeadline
  )
    await delay(100);
  const profileResult = app.operations.get(profileOperation.operationId);
  if (profileResult.status !== 'done' || !profileResult.detail.includes(bot.botId))
    throw new Error('Hermes Gateway /profile command did not complete in this Bot session.');
  const messagesBeforeRestore = app.database.messages(conversation.conversationId);
  if (messagesBeforeRestore.some((message) => message.author.type === 'user'))
    throw new Error('A welcome must not manufacture a user message.');
  await app.close();
  app = new NodeApplication(join(home, 'node'), runtime);
  await app.resume();
  await app.handle({ method: 'sync.snapshot', params: {} });
  await app.handle({ method: 'sync.since', params: { seq: 0 } });
  const restored = app.database.messages(conversation.conversationId);
  if (creations !== 1 || restored.length !== messagesBeforeRestore.length)
    throw new Error('Welcome was duplicated after restore/sync.');
  await writeFile(
    join(reportRoot, 'canonical-session-welcome.json'),
    JSON.stringify(
      {
        environment: 'isolated WSL Ubuntu 24.04',
        outcome: state.outcome,
        realProfile: true,
        realIntroductionAndTaskQuestion: true,
        createdRuns: creations,
        commandCatalogProfileScoped: Boolean(profileCommand),
        profileCommandCompleted: profileResult.status === 'done',
        manufacturedUserMessages: 0,
        restoreAndSyncCreatedRuns: 0,
        nativeSessionMatchesDm: session.stored_session_id === storedSession.storedSessionId,
      },
      null,
      2,
    ) + '\n',
  );
  console.log(
    'Real Hermes welcome and Gateway /profile completed; restore/sync kept message count stable with one model run. Isolated environment retained.',
  );
} finally {
  await app.close();
  await runtime.close();
}
