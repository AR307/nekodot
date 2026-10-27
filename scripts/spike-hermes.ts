import { appendFile, mkdir, mkdtemp, readFile, writeFile } from 'node:fs/promises';
import { randomBytes, randomUUID } from 'node:crypto';
import { resolve, join, dirname } from 'node:path';
import { parseArgs } from 'node:util';
import { setTimeout as delay } from 'node:timers/promises';
import { HermesApi } from '../apps/node/src/hermes/api';
import { runHermesCli, spawnHermesCli, type HermesLaunch } from '../apps/node/src/hermes/cli';
import type { SseFrame } from '../apps/node/src/hermes/sse';
const { values } = parseArgs({
  options: { root: { type: 'string' }, source: { type: 'string' }, runtime: { type: 'string' } },
});
const root = resolve(values.root ?? process.cwd());
if (!values.source || !values.runtime || process.platform !== 'linux')
  throw new Error(
    'Use WSL/Linux and pass --source <official Hermes checkout> --runtime <PM tool store>.',
  );
process.loadEnvFile(join(root, '.env'));
const baseUrl = process.env.NEKODOT_PROVIDER_BASE_URL;
const model = process.env.NEKODOT_PROVIDER_MODEL;
const apiKey = process.env.NEKODOT_PROVIDER_API_KEY;
if (!baseUrl || !model || !apiKey)
  throw new Error('Fill the three NEKODOT_PROVIDER_* values in the ignored .env file first.');
const source = resolve(values.source);
const runtime = resolve(values.runtime);
const dataRoot = await mkdtemp(join(dirname(runtime), 'spike-'));
const home = join(dataRoot, 'hermes');
const work = join(dataRoot, 'workspace');
const fixtures = join(root, 'docs/fixtures');
const privateRoot = join(root, '.runtime');
await Promise.all([
  mkdir(home, { recursive: true }),
  mkdir(work, { recursive: true }),
  mkdir(fixtures, { recursive: true }),
  mkdir(privateRoot, { recursive: true }),
]);
const hubKey = randomBytes(32).toString('hex');
const botKey = randomBytes(32).toString('hex');
const alphabet = 'abcdefghijklmnopqrstuvwxyz234567';
const profile = 'nk-' + [...randomBytes(6)].map((v) => alphabet[v % 32]).join('');
const hotProfile = 'nk-' + [...randomBytes(6)].map((v) => alphabet[v % 32]).join('');
const redact = (value: string) => {
  let text = value;
  for (const [secret, label] of [
    [apiKey, '<provider-key>'],
    [botKey, '<bot-key>'],
    [hubKey, '<hub-key>'],
    [baseUrl, 'https://provider.invalid/v1'],
    [model, '<custom-model>'],
    [dataRoot, '/tmp/nekodot-spike'],
  ] as const)
    text = text.split(secret).join(label);
  return text.replace(/Bearer\s+[^\s"\\]+/gi, 'Bearer <redacted>');
};
const launch: HermesLaunch = {
  command: 'bash',
  prefixArgs: [join(source, 'scripts/run-in-hermes-env'), 'python', join(source, 'hermes')],
  home,
  runtimeDir: runtime,
  cwd: source,
};
const api = new HermesApi('http://127.0.0.1:18642/p/' + profile, botKey);
const config = {
  model: {
    provider: 'custom',
    base_url: baseUrl,
    default: model,
    api_key: '$' + '{NEKODOT_PROVIDER_API_KEY}',
    api_mode: 'chat_completions',
  },
  gateway: { multiplex_profiles: true },
  terminal: { backend: 'local', cwd: work },
  approvals: { mode: 'manual' },
  toolsets: ['terminal', 'file'],
  max_turns: 8,
};
async function configure(dir: string, key: string) {
  await writeFile(join(dir, 'config.yaml'), JSON.stringify(config, null, 2), { mode: 0o600 });
  await writeFile(
    join(dir, '.env'),
    'API_SERVER_ENABLED=true\nAPI_SERVER_HOST=127.0.0.1\nAPI_SERVER_PORT=18642\nAPI_SERVER_KEY=' +
      key +
      '\nNEKODOT_PROVIDER_API_KEY=' +
      apiKey +
      '\n',
    { mode: 0o600 },
  );
}
await configure(home, hubKey);
console.log('Creating isolated Hermes profile...');
await runHermesCli(launch, ['profile', 'create', profile, '--no-alias', '--no-skills']);
await configure(join(home, 'profiles', profile), botKey);
await writeFile(
  join(privateRoot, 'hermes-last-spike.json'),
  JSON.stringify({ dataRoot, home, profile, source, runtime }, null, 2),
);
const gateway = spawnHermesCli(launch, ['gateway', 'run']);
const logPath = join(privateRoot, 'hermes-spike.log');
gateway.stdout?.on('data', (chunk: Buffer) => {
  void appendFile(logPath, redact(chunk.toString()));
});
gateway.stderr?.on('data', (chunk: Buffer) => {
  void appendFile(logPath, redact(chunk.toString()));
});
const result: Record<string, unknown> = {
  nodeVersion: process.version,
  startedAt: new Date().toISOString(),
  sourceCommit: 'a382af23f4c067d23463b5781958684c2cda82bc',
  platform: process.platform,
  profileIsolation: false,
  hotAdd: false,
  scenarios: {},
};
const scenarios: Record<string, unknown> = {};
const states: Record<string, unknown> = {};
try {
  let healthy = false;
  for (let i = 0; i < 120; i++) {
    if (gateway.exitCode !== null)
      throw new Error('Gateway exited before health. See ignored .runtime/hermes-spike.log.');
    const response = await fetch(api.baseUrl + '/health', {
      headers: { Authorization: 'Bearer ' + botKey },
    }).catch(() => undefined);
    if (response?.ok) {
      healthy = true;
      break;
    }
    await delay(1000);
  }
  if (!healthy) throw new Error('Gateway did not become healthy within 120 seconds.');
  result.profileIsolation = true;
  console.log('Gateway and profile healthy; checking hot-add...');
  await runHermesCli(launch, ['profile', 'create', hotProfile, '--no-alias', '--no-skills']);
  await configure(join(home, 'profiles', hotProfile), botKey);
  let hotAdded = false;
  for (let i = 0; i < 40; i++) {
    const response = await fetch('http://127.0.0.1:18642/p/' + hotProfile + '/health', {
      headers: { Authorization: 'Bearer ' + botKey },
    });
    if (response.ok) {
      hotAdded = true;
      break;
    }
    await delay(1000);
  }
  result.hotAdd = hotAdded;
  const instructions =
    'You are executing an authorized isolated nekodot integration test. Follow the exact requested tool action. Never remove files. For a denied file write, do not retry it through any tool or alternative path; report the denial and finish. Use write_file or patch for file changes.';
  async function runScenario(
    name: string,
    input: string,
    choice?: 'once' | 'deny',
    stopOnTool = false,
  ) {
    console.log('Real scenario:', name);
    const created = await api.createRun(input, 'nk_dm_' + randomUUID(), randomUUID(), instructions);
    const frames: SseFrame[] = [];
    let approvalSeen = false;
    let stopSent = false;
    for await (const frame of api.events(created.run_id)) {
      frames.push(frame);
      if (frame.event === 'approval.request' && !stopSent) {
        const state = await api.state(created.run_id);
        states[name + '-pending'] = state;
        const control = state.pending_controls?.find((item) => item.kind === 'approval');
        if (!control) throw new Error('Approval event has no pending control.');
        const generation = control.execution_generation ?? state.execution_generation;
        if (generation === undefined) throw new Error('Approval has no execution generation.');
        approvalSeen = true;
        states[name + '-approval-response'] = await api.approve(
          created.run_id,
          control.prompt_id,
          generation,
          choice ?? 'deny',
        );
      }
      if (stopOnTool && frame.event === 'tool.started' && !stopSent) {
        await delay(1000);
        states[name + '-stop-response'] = await api.stop(created.run_id);
        stopSent = true;
      }
    }
    const state = await api.state(created.run_id);
    states[name + '-final'] = state;
    const record = {
      status: state.status,
      events: frames.map((f) => f.event),
      approvalSeen,
      stopSent,
    };
    scenarios[name] = record;
    await writeFile(join(fixtures, name + '.sse'), redact(frames.map((f) => f.raw).join('')));
    await writeFile(
      join(fixtures, name + '.state.json'),
      redact(
        JSON.stringify({ final: state, pending: states[name + '-pending'] ?? null }, null, 2),
      ) + '\n',
    );
    return { frames, state, approvalSeen, stopSent };
  }
  const basic = await runScenario(
    'runs-basic',
    'Reply with exactly NEKODOT_PHASE0_OK. Do not use tools.',
  );
  if (basic.state.status !== 'completed' || !basic.state.output?.includes('NEKODOT_PHASE0_OK'))
    throw new Error('Real basic response did not pass.');
  const tool = await runScenario(
    'runs-tools',
    'Use the terminal tool to execute printf NEKODOT_TOOL_OK, then report the output.',
  );
  if (tool.state.status !== 'completed' || !tool.frames.some((f) => f.event === 'tool.completed'))
    throw new Error('Real tool scenario did not pass.');
  for (const choice of ['once', 'deny'] as const) {
    const dir = join(work, choice);
    await mkdir(dir);
    await writeFile(join(dir, 'AGENTS.md'), '# Isolated approval probe\n');
    const name = choice === 'once' ? 'runs-tools-approval' : 'runs-approval-deny';
    const approved = await runScenario(
      name,
      'First use read_file to read the full contents of ' +
        join(dir, 'AGENTS.md') +
        '. Then use patch in replace mode to replace its existing line with that same line followed by a new line containing exactly NEKODOT_APPROVAL_OK. This isolated file write requires human approval. If denied, do not retry or use any other tool or path; report denial and finish.',
      choice,
    );
    const changed = (await readFile(join(dir, 'AGENTS.md'), 'utf8')).includes(
      'NEKODOT_APPROVAL_OK',
    );
    scenarios[name] = {
      ...(scenarios[name] as Record<string, unknown>),
      fileChanged: changed,
      fileContent: await readFile(join(dir, 'AGENTS.md'), 'utf8'),
    };
    if (
      !approved.approvalSeen ||
      approved.state.status !== 'completed' ||
      changed !== (choice === 'once')
    )
      throw new Error('Approval ' + choice + ' did not match real file result.');
  }
  const stopped = await runScenario(
    'runs-stop',
    'Use the terminal tool to execute sleep 45; printf NEKODOT_STOP_FINISHED and report the result.',
    undefined,
    true,
  );
  if (!stopped.stopSent || stopped.state.status !== 'cancelled')
    throw new Error('Stop did not settle as cancelled.');
  const started = tool.frames.filter((f) => f.event === 'tool.started');
  result.toolCallIds =
    started.length > 0 && started.every((f) => typeof f.data.tool_call_id === 'string');
  result.scenarios = scenarios;
  result.passed = true;
} catch (error) {
  result.scenarios = scenarios;
  result.passed = false;
  result.error = redact(String(error));
  process.exitCode = 1;
} finally {
  result.finishedAt = new Date().toISOString();
  await writeFile(
    join(fixtures, 'spike-report.json'),
    redact(JSON.stringify(result, null, 2)) + '\n',
  );
  await writeFile(
    join(fixtures, 'run-states.json'),
    redact(JSON.stringify(states, null, 2)) + '\n',
  );
  gateway.kill('SIGTERM');
  await Promise.race([
    new Promise<void>((resolve) => gateway.once('exit', () => resolve())),
    delay(30_000),
  ]);
  if (gateway.exitCode === null) gateway.kill('SIGKILL');
  console.log(JSON.stringify(result, null, 2));
  console.log('Isolated runtime retained; see .runtime/hermes-last-spike.json.');
}
