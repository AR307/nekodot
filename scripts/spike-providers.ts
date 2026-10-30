import { mkdtemp, mkdir, readFile, writeFile, appendFile } from 'node:fs/promises';
import { homedir } from 'node:os';
import { join, resolve } from 'node:path';
import { parseArgs, parseEnv } from 'node:util';
import { setTimeout as delay } from 'node:timers/promises';
import { ManagedHermes } from '../apps/node/src/hermes/runtime';
import { NodeApplication } from '../apps/node/src/app';
import type { Bot, Conversation, RpcResult } from '@nekodot/protocol';

const { values } = parseArgs({
  options: { root: { type: 'string' }, compression: { type: 'boolean' } },
});
const root = resolve(values.root ?? process.cwd());
if (process.platform !== 'linux') throw new Error('Run this isolated journey in WSL/Linux.');
const reference = JSON.parse(
  await readFile(join(root, '.runtime/hermes-last-spike.json'), 'utf8'),
) as { source: string; runtime: string };
const env = parseEnv(await readFile(join(root, '.env'), 'utf8'));
if (!env.NEKODOT_PROVIDER_BASE_URL || !env.NEKODOT_PROVIDER_MODEL || !env.NEKODOT_PROVIDER_API_KEY)
  throw new Error('Local custom API settings are incomplete');
// WSL clears /tmp on shutdown. Keep the isolated acceptance profiles across restarts.
const environments = join(homedir(), '.cache/nekodot-source-acceptance');
await mkdir(environments, { recursive: true, mode: 0o700 });
const home = await mkdtemp(join(environments, 'sources-'));
await mkdir(join(root, '.runtime/side-phase-3'), { recursive: true });
await writeFile(join(root, '.runtime/side-phase-3/providers-last.json'), JSON.stringify({ home }));
const runtime = new ManagedHermes({
  home: join(home, 'hermes'),
  source: reference.source,
  runtime: reference.runtime,
  apiPort: 19702,
  managementPort: 19703,
  onLog: (text) => {
    void appendFile(join(home, 'hermes.log'), text);
  },
});
const app = new NodeApplication(join(home, 'node'), runtime);
const capture: Record<string, unknown> = {};
try {
  await runtime.start();
  console.log('Isolated native backend ready');
  const sources: RpcResult<'providers.set'>[] = [];
  for (const name of ['Research API', 'Writing API']) {
    sources.push(
      await app.providers.set({
        kind: 'custom',
        name,
        baseUrl: env.NEKODOT_PROVIDER_BASE_URL,
        apiKey: env.NEKODOT_PROVIDER_API_KEY,
      }),
    );
  }
  capture.catalog = await app.providers.list();
  capture.nativeOauth = await runtime.management.request('/api/providers/oauth', 'default');
  capture.nativeEndpoints = await runtime.management.request(
    '/api/providers/custom-endpoints',
    'default',
  );
  console.log('Two native sources saved; authorization catalog loaded');
  capture.options = await Promise.all(
    sources.map((source) => app.providers.models({ sourceId: source.sourceId, refresh: true })),
  );
  if ((capture.options as { models: string[] }[]).some((row) => !row.models.length))
    throw new Error('A real source returned no model directory');
  capture.nativeOptions = await runtime.management.request<{
    providers: { slug: string; models: string[] }[];
  }>('/api/model/options?include_unconfigured=false&refresh=true', 'default');
  console.log(
    'Native directory rows',
    (capture.nativeOptions as { providers: { slug: string; models: string[] }[] }).providers.map(
      (row) => ({ slug: row.slug, count: row.models.length }),
    ),
  );
  const bots: Bot[] = [];
  for (const [index, source] of sources.entries()) {
    const { bot, conversation } = (await app.handle({
      method: 'bots.create',
      params: {
        displayName: index === 0 ? 'Maple' : 'Cedar',
        handle: 'sources-' + index,
        role: 'Be concise and helpful. Use English for this isolated test.',
        model: env.NEKODOT_PROVIDER_MODEL,
        sourceId: source.sourceId,
        modelSettings: { contextLength: index === 0 ? 64000 : null },
        avatar: { shape: 'dot', color: '#E8603C' },
      },
    })) as { bot: Bot; conversation: Conversation };
    bots.push(bot);
    const deadline = Date.now() + 240_000;
    while (app.database.runs().length && Date.now() < deadline) await delay(200);
    const messages = app.database.messages(conversation.conversationId);
    const reply = messages.find((message) => message.kind === 'text' && message.content.welcome);
    if (reply?.kind !== 'text' || reply.status !== 'done')
      throw new Error('Native source welcome did not complete');
    capture['bot' + index] = {
      sourceId: bot.sourceId,
      model: bot.model,
      info: await app.providers.info(bot.botId),
      messages,
    };
    console.log('Native source ' + (index + 1) + ' replied; model info loaded');
    const sid = 'nk_dm_' + conversation.conversationId;
    if (index === 0 && values.compression) {
      for (let round = 0; round < 5; round++) {
        const notes = Array.from(
          { length: 260 },
          (_, i) =>
            `Synthetic receipt ${round}-${i}: the local orchard shipment uses a blue crate, aisle ${i % 13}, quantity ${i + 20}, date week ${round + 1}.`,
        ).join('\n');
        await app.handle({
          method: 'messages.send',
          params: {
            conversationId: conversation.conversationId,
            clientMsgId: 'source-compression-' + round,
            text:
              'These are harmless synthetic notes. Do not use tools. Acknowledge in one short line.\n' +
              notes,
          },
        });
        const until = Date.now() + 240_000;
        while (app.database.runs().length && Date.now() < until) await delay(200);
        if (app.database.messages(conversation.conversationId).at(-1)?.status !== 'done')
          throw new Error('Native compression setup round did not finish');
        console.log('Native history setup round ' + (round + 1) + ' completed');
      }
    }
    const resumed = await runtime.management.rpc<{ session_id: string }>('session.resume', {
      profile: bot.botId,
      session_id: sid,
      eager_build: true,
      omit_messages: true,
    });
    capture['stats' + index] = await runtime.management
      .rpc('session.stats', { profile: bot.botId, session_id: sid })
      .catch((error: Error) => ({ error: error.message }));
    capture['usage' + index] = await runtime.management
      .rpc('session.usage', { profile: bot.botId, session_id: resumed.session_id })
      .catch((error: Error) => ({ error: error.message }));
    if (index === 0) {
      capture.nativeInfo = await runtime.management.request('/api/model/info', bot.botId);
      capture.compressRequest = await runtime.management.rpc(
        'slash.exec',
        { profile: bot.botId, session_id: resumed.session_id, command: '/compress' },
        180_000,
      );
      capture.compressionLogs = await runtime.management.request(
        '/api/logs?file=agent&search=Compression&lines=500',
        bot.botId,
      );
      capture.initializationLogs = await runtime.management.request(
        '/api/logs?file=agent&search=Context%20compressor%20initialized&lines=5',
        bot.botId,
      );
      capture.afterCompression = await app.providers.info(bot.botId);
      console.log('Native compress command completed');
    }
  }
  capture.rootConfig = await runtime.management.request(
    '/api/config?include_defaults=false',
    'default',
  );
  capture.defaultConfig = await runtime.management.request(
    '/api/config?include_defaults=true',
    bots[0]!.botId,
  );
  await writeFile(join(home, 'capture.json'), JSON.stringify(capture, null, 2));
  const safe = (value: unknown) => {
    let text = JSON.stringify(
      value,
      (key, item: unknown) =>
        /^(token_preview|api_key_preview|apiKeyLast4)$/.test(key) ? '<redacted>' : item,
      2,
    );
    for (const secret of [
      home,
      reference.source,
      reference.runtime,
      env.NEKODOT_PROVIDER_API_KEY!.slice(-4),
      ...Object.values(env),
    ])
      if (secret && secret.length >= 4) text = text.replaceAll(secret, '<redacted>');
    text = text.replace(/\/root\/[^"\s]*/g, '<private-path>');
    return text;
  };
  // Config and raw logs remain private; only the actual management shapes are recorded.
  await writeFile(
    join(root, 'docs/fixtures/providers-native.json'),
    safe({
      oauth: capture.nativeOauth,
      endpoints: capture.nativeEndpoints,
      options: capture.nativeOptions,
      info: capture.nativeInfo,
      compressionLogs: capture.compressionLogs,
      initializationLogs: capture.initializationLogs,
      config: { compression: (capture.defaultConfig as { compression: unknown }).compression },
      compressRequest: capture.compressRequest,
    }) + '\n',
  );
  await writeFile(
    join(root, 'docs/evidence/side-phase3-sources-native.json'),
    JSON.stringify(
      {
        environment: 'isolated WSL Ubuntu 24.04',
        customSources: sources.length,
        distinctNativeRoutes: new Set(sources.map((source) => source.provider)).size,
        nativeProfiles: bots.length,
        actualWelcomeReplies: bots.length,
        oauthGrantValidation: 'see side-phase3-oauth-native.json (separate authorization spike)',
        credentialsOrEndpointInReport: false,
      },
      null,
      2,
    ) + '\n',
  );
  console.log(
    'Real custom source coexistence passed; private environment retained. OAuth grant acceptance is separate.',
  );
} finally {
  await writeFile(join(home, 'capture.json'), JSON.stringify(capture, null, 2));
  await app.close();
  await runtime.close();
}
