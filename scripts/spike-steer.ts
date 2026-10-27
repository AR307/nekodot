import { appendFile, mkdir, readFile, writeFile } from 'node:fs/promises';
import { randomUUID } from 'node:crypto';
import { join, resolve } from 'node:path';
import { parseEnv } from 'node:util';
import { parseArgs } from 'node:util';
import { setTimeout as delay } from 'node:timers/promises';
import { HermesApi } from '../apps/node/src/hermes/api';
import { spawnHermesCli, type HermesLaunch } from '../apps/node/src/hermes/cli';
import type { SseFrame } from '../apps/node/src/hermes/sse';

const { values } = parseArgs({ options: { root: { type: 'string' } } });
const root = resolve(values.root ?? process.cwd());
if (process.platform !== 'linux')
  throw new Error('Run the isolated Hermes steer check in WSL/Linux.');
const runtimeNote = JSON.parse(
  await readFile(join(root, '.runtime/hermes-last-spike.json'), 'utf8'),
) as {
  home: string;
  profile: string;
  source: string;
  runtime: string;
  dataRoot: string;
};
const home = runtimeNote.home;
const profile = runtimeNote.profile;
const source = runtimeNote.source;
const runtimeDir = runtimeNote.runtime;
const secrets = parseEnv(await readFile(join(home, 'profiles', profile, '.env'), 'utf8'));
const apiKey = secrets.API_SERVER_KEY;
if (!apiKey) throw new Error('The retained isolated Hermes profile has no API_SERVER_KEY.');
const modelKey = secrets.NEKODOT_PROVIDER_API_KEY;
const openrouterKey = secrets.OPENROUTER_API_KEY;
if (!modelKey && !openrouterKey)
  throw new Error('The isolated Hermes profile has no configured model key.');
const launch: HermesLaunch = {
  command: 'bash',
  prefixArgs: [join(source, 'scripts/run-in-hermes-env'), 'python', join(source, 'hermes')],
  cwd: source,
  home,
  runtimeDir,
};
const api = new HermesApi('http://127.0.0.1:18642/p/' + profile, apiKey);
const gateway = spawnHermesCli(launch, ['gateway', 'run']);
const logPath = join(root, '.runtime/hermes-steer-spike.log');
const redact = (input: string) => {
  let result = input;
  for (const [secret, label] of [
    [apiKey, '<bot-key>'],
    [modelKey ?? '', '<provider-key>'],
    [openrouterKey ?? '', '<provider-key>'],
    [home, '<hermes-home>'],
    [source, '<hermes-source>'],
    [runtimeDir, '<pm-runtime>'],
    [runtimeNote.dataRoot, '<spike-root>'],
  ] as const)
    if (secret) result = result.split(secret).join(label);
  return result.replace(/Bearer\s+[^\s"\\]+/gi, 'Bearer <redacted>');
};
const log = (chunk: Buffer) => void appendFile(logPath, redact(chunk.toString()));
gateway.stdout?.on('data', log);
gateway.stderr?.on('data', log);
const frames: SseFrame[] = [];
const states: Record<string, unknown> = {};
let steerResponse: { run_id: string; accepted: boolean } | undefined;
const steerId = randomUUID();

try {
  let healthy = false;
  for (let attempt = 0; attempt < 90; attempt++) {
    if (gateway.exitCode !== null)
      throw new Error('Isolated Hermes gateway exited before becoming healthy.');
    if (
      await api.health().then(
        () => true,
        () => false,
      )
    ) {
      healthy = true;
      break;
    }
    await delay(1000);
  }
  if (!healthy)
    throw new Error('Isolated Hermes gateway did not become healthy within 90 seconds.');

  const created = await api.createRun(
    'Use the terminal tool once to execute `sleep 8; printf NEKODOT_STEER_TOOL_ONCE`. After the command completes, do not run any more tools. End your response with exactly NEKODOT_STEER_INITIAL.',
    'nk_dm_steer_' + randomUUID(),
    steerId,
    'This is an isolated integration check. Only run the exact harmless terminal command requested. Do not create or modify files.',
  );
  states.created = { run_id: created.run_id, status: created.status };
  let toolCount = 0;
  for await (const frame of api.events(created.run_id)) {
    frames.push(frame);
    if (frame.event === 'tool.started') {
      toolCount++;
      if (toolCount !== 1) throw new Error('The isolated task started more than one tool.');
      await delay(500);
      states.beforeSteer = await api.state(created.run_id);
      steerResponse = await api.steer(
        created.run_id,
        'Keep the same run. Do not start any additional tool. Ignore the requested initial ending and finish with exactly NEKODOT_STEER_OK.',
      );
      states.steerResponse = steerResponse;
      if (!steerResponse.accepted || steerResponse.run_id !== created.run_id)
        throw new Error('Hermes did not accept steering on the existing run.');
    }
  }
  const final = await api.state(created.run_id);
  states.final = final;
  states.toolCount = toolCount;
  if (
    toolCount !== 1 ||
    final.run_id !== created.run_id ||
    final.status !== 'completed' ||
    !final.output?.includes('NEKODOT_STEER_OK')
  )
    throw new Error('Real steer did not preserve the run and return the requested final response.');

  const fixtures = join(root, 'docs/fixtures');
  await mkdir(fixtures, { recursive: true });
  await writeFile(
    join(fixtures, 'runs-steer.sse'),
    redact(frames.map((frame) => frame.raw).join('')),
  );
  await writeFile(
    join(fixtures, 'runs-steer.state.json'),
    redact(JSON.stringify(states, null, 2)) + '\n',
  );
  console.log(
    'Real Hermes steer passed: accepted on the existing run, one tool execution, expected final marker.',
  );
  console.log('Recorded sanitized SSE and state fixtures under docs/fixtures.');
} catch (error) {
  console.error(
    'Real Hermes steer did not pass: ' +
      redact(error instanceof Error ? error.message : String(error)),
  );
  process.exitCode = 1;
} finally {
  gateway.kill('SIGTERM');
  await Promise.race([
    new Promise<void>((resolveExit) => gateway.once('exit', () => resolveExit())),
    delay(30000),
  ]);
  if (gateway.exitCode === null) gateway.kill('SIGKILL');
  if (steerResponse)
    console.log('Steer response recorded; the retained isolated runtime was not removed.');
}
