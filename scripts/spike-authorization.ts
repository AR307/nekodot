import { readFile, writeFile, appendFile, mkdir, access } from 'node:fs/promises';
import { join, resolve } from 'node:path';
import { parseArgs } from 'node:util';
import { setTimeout as delay } from 'node:timers/promises';
import { ManagedHermes } from '../apps/node/src/hermes/runtime';
import { NodeApplication } from '../apps/node/src/app';
import type { RpcResult } from '@nekodot/protocol';

const { values } = parseArgs({
  options: { root: { type: 'string' }, provider: { type: 'string', default: 'openai-codex' } },
});
const root = resolve(values.root ?? process.cwd());
if (process.platform !== 'linux') throw new Error('Use the isolated WSL/Linux environment.');
const { home } = JSON.parse(
  await readFile(join(root, '.runtime/side-phase-3/providers-last.json'), 'utf8'),
) as { home: string };
const reference = JSON.parse(
  await readFile(join(root, '.runtime/hermes-last-spike.json'), 'utf8'),
) as { source: string; runtime: string };
const runtime = new ManagedHermes({
  home: join(home, 'hermes'),
  source: reference.source,
  runtime: reference.runtime,
  apiPort: 19706,
  managementPort: 19707,
  onLog: (text) => {
    void appendFile(join(home, 'authorization.log'), text);
  },
});
const app = new NodeApplication(join(home, 'node'), runtime);
const capture: Record<string, unknown> = {};
try {
  await runtime.start();
  const started = await app.providers.authorize({ provider: values.provider!, action: 'start' });
  capture.start = started;
  await mkdir(join(root, '.runtime/side-phase-3/private'), { recursive: true });
  await writeFile(
    join(root, '.runtime/side-phase-3/private/authorization-session.json'),
    JSON.stringify(started),
  );
  console.log(
    JSON.stringify({
      verification_url: started.verification_url,
      user_code: started.user_code,
      expires_in: started.expires_in,
      status: started.status,
    }),
  );
  if (!started.session_id) throw new Error('Native authorization did not return a device session');
  let state = started;
  const polls: RpcResult<'providers.authorize'>[] = [];
  const until = Date.now() + Number(started.expires_in ?? 900) * 1000;
  while (Date.now() < until) {
    await delay(Math.max(3, Number(started.poll_interval ?? 5)) * 1000);
    state = await app.providers.authorize({
      provider: values.provider!,
      action: 'poll',
      sessionId: String(started.session_id),
    });
    polls.push(state);
    if (state.status !== 'pending') break;
  }
  capture.polls = polls;
  const authorized = (await app.providers.list()).sources.find(
    (source) => source.sourceId === 'oauth:' + values.provider,
  );
  if (!authorized) {
    console.log('Native authorization ended with status: ' + String(state.status));
    throw new Error('Authorization was not completed');
  }
  const options = await app.providers.models({ sourceId: authorized.sourceId, refresh: true });
  capture.options = options;
  const model = options.models[0];
  if (!model) throw new Error('The authorized account returned no models');
  const created = (await app.handle({
    method: 'bots.create',
    params: {
      sourceId: authorized.sourceId,
      displayName: 'Quartz',
      handle: 'oauth-quartz',
      model,
      role: 'You are Quartz, a helpful concise assistant. Introduce yourself in English.',
      avatar: { shape: 'dot', color: '#5B7CE6' },
    },
  })) as RpcResult<'bots.create'>;
  const deadline = Date.now() + 240_000;
  while (app.database.runs().length && Date.now() < deadline) await delay(200);
  const reply = app.database.messages(created.conversation.conversationId).at(-1);
  if (reply?.kind !== 'text' || reply.status !== 'done')
    throw new Error('The authorized profile did not complete its real welcome');
  capture.reply = reply;
  capture.nativeInfo = await runtime.management.request('/api/model/info', created.bot.botId);
  capture.profileAuthorization = await runtime.management.request<{
    providers: { id: string; status: { logged_in: boolean } }[];
  }>('/api/providers/oauth', created.bot.botId);
  const hasInheritedGrant = (
    capture.profileAuthorization as { providers: { id: string; status: { logged_in: boolean } }[] }
  ).providers.some((entry) => entry.id === values.provider && entry.status.logged_in);
  const rootGrantExists = await access(join(runtime.profileHome('default'), 'auth.json')).then(
    () => true,
    () => false,
  );
  const profileGrantExists = await access(
    join(runtime.profileHome(created.bot.botId), 'auth.json'),
  ).then(
    () => true,
    () => false,
  );
  if (!rootGrantExists || !hasInheritedGrant || profileGrantExists)
    throw new Error('The expected native root-grant inheritance was not observed');
  capture.sources = await app.providers.list();
  const custom = app.database.bots().find((bot) => bot.sourceId?.startsWith('custom:'));
  if (!custom) throw new Error('The existing custom-source profile is missing');
  const dm = app.database
    .conversations()
    .find((conversation) => conversation.kind === 'dm' && conversation.botId === custom.botId)!;
  await app.handle({
    method: 'messages.send',
    params: {
      conversationId: dm.conversationId,
      clientMsgId: 'custom-after-oauth',
      text: 'Reply with CUSTOM_SOURCE_STILL_READY only. Do not use tools.',
    },
  });
  const customUntil = Date.now() + 240_000;
  while (app.database.runs().length && Date.now() < customUntil) await delay(200);
  const customReply = app.database.messages(dm.conversationId).at(-1);
  if (
    customReply?.kind !== 'text' ||
    customReply.status !== 'done' ||
    !customReply.content.text.includes('CUSTOM_SOURCE_STILL_READY')
  )
    throw new Error('The custom source did not stay usable after OAuth');
  capture.customReply = customReply;
  await writeFile(join(home, 'authorization-capture.json'), JSON.stringify(capture, null, 2));
  // Account identifiers and every native token preview remain private.
  const safe = JSON.stringify(
    {
      start: capture.start,
      polls: polls.filter(
        (poll, index) => polls.findIndex((entry) => entry.status === poll.status) === index,
      ),
      options,
      info: capture.nativeInfo,
    },
    (key, value: unknown) =>
      /^(token_preview|api_key_preview|access_token|refresh_token|account_email|user_code|verification_url|session_id)$/.test(
        key,
      )
        ? '<redacted>'
        : value,
    2,
  );
  await writeFile(join(root, 'docs/fixtures/oauth-codex-native.json'), safe + '\n');
  await writeFile(
    join(root, 'docs/evidence/side-phase3-oauth-native.json'),
    JSON.stringify(
      {
        provider: values.provider,
        nativeDeviceAuthorization: state.status,
        oauthProfileWelcome: reply.status,
        customApiAfterAuthorization: customReply.status,
        customSources: (await app.providers.list()).sources.filter(
          (source) => source.kind === 'custom',
        ).length,
        rootGrantExists,
        profileGrantExists,
        profileReportsAuthorized: hasInheritedGrant,
      },
      null,
      2,
    ) + '\n',
  );
  console.log(
    'Native OAuth and custom API coexistence passed with real model replies. Private environment retained.',
  );
} finally {
  await writeFile(join(home, 'authorization-capture.json'), JSON.stringify(capture, null, 2));
  await app.close();
  await runtime.close();
}
