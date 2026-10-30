import { mkdtemp, mkdir, readFile, writeFile, appendFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { parseArgs, parseEnv } from 'node:util';
import { setTimeout as delay } from 'node:timers/promises';
import { ManagedHermes } from '../apps/node/src/hermes/runtime';
import { NodeApplication } from '../apps/node/src/app';
import type { Bot, Conversation } from '@nekodot/protocol';
import type { SseFrame } from '../apps/node/src/hermes/sse';

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
await mkdir(join(root, '.runtime/side-phase-3'), { recursive: true });
const runtime = new ManagedHermes({
  home: join(home, 'hermes'),
  source: reference.source,
  runtime: reference.runtime,
  apiPort: 19682,
  managementPort: 19683,
  onLog: (text) => {
    void appendFile(join(home, 'hermes.log'), text);
  },
});
let app = new NodeApplication(join(home, 'node'), runtime);
const frames: SseFrame[] = [];
let creations = 0;
const nativeApi = runtime.api.bind(runtime);
runtime.api = async (profile) => {
  const api = await nativeApi(profile);
  const create = api.createRun.bind(api),
    events = api.events.bind(api);
  api.createRun = async (...args) => {
    creations++;
    return create(...args);
  };
  api.events = async function* (...args) {
    for await (const frame of events(...args)) {
      frames.push(frame);
      yield frame;
    }
  };
  return api;
};
const redact = (value: unknown) => {
  let text = JSON.stringify(value, null, 2);
  for (const secret of [home, reference.source, reference.runtime, ...Object.values(env)])
    if (secret && secret.length > 4) text = text.replaceAll(secret, '<redacted>');
  return text;
};
try {
  await runtime.start();
  await app.handle({
    method: 'providers.set',
    params: {
      kind: 'custom',
      baseUrl: env.NEKODOT_PROVIDER_BASE_URL,
      apiKey: env.NEKODOT_PROVIDER_API_KEY,
      defaultModel: env.NEKODOT_PROVIDER_MODEL,
    },
  });
  const { bot, conversation } = (await app.handle({
    method: 'bots.create',
    params: {
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
  const state = await (await nativeApi(bot.botId)).state(runId);
  await writeFile(join(home, 'capture.json'), JSON.stringify({ frames, state, messages }, null, 2));
  if (
    state.status !== 'completed' ||
    !state.output?.includes('Maple') ||
    !/[?？]/.test(state.output)
  )
    throw new Error(
      'The actual welcome did not complete with an introduction and a question; private capture retained.',
    );
  if (messages.some((message) => message.author.type === 'user'))
    throw new Error('A welcome must not manufacture a user message.');
  await app.close();
  app = new NodeApplication(join(home, 'node'), runtime);
  await app.resume();
  await app.handle({ method: 'sync.snapshot', params: {} });
  await app.handle({ method: 'sync.since', params: { seq: 0 } });
  const restored = app.database.messages(conversation.conversationId);
  if (creations !== 1 || restored.length !== messages.length)
    throw new Error('Welcome was duplicated after restore/sync.');
  const fixture = join(root, 'docs/fixtures/runs-welcome');
  await writeFile(
    fixture + '.sse',
    frames
      .map(
        (frame) =>
          `id: ${frame.data.seq}\nevent: ${frame.data.event}\ndata: ${redact(frame.data).replace(/\n\s*/g, '')}\n\n`,
      )
      .join(''),
  );
  await writeFile(fixture + '.state.json', redact({ final: state }) + '\n');
  await writeFile(
    join(root, 'docs/evidence/side-phase3-welcome-native.json'),
    JSON.stringify(
      {
        environment: 'isolated WSL Ubuntu 24.04',
        status: state.status,
        realProfile: true,
        realIntroductionAndTaskQuestion: true,
        createdRuns: creations,
        manufacturedUserMessages: 0,
        restoreAndSyncCreatedRuns: 0,
        nativeSessionMatchesDm: state.session_id === 'nk_dm_' + conversation.conversationId,
      },
      null,
      2,
    ) + '\n',
  );
  console.log(
    'Real Hermes welcome completed once; no user bubble; restore/sync did not create another run. Isolated environment retained.',
  );
} finally {
  await app.close();
  await runtime.close();
}
