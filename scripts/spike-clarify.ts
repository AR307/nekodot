import { appendFile, mkdir, readFile, writeFile } from 'node:fs/promises';
import { randomUUID } from 'node:crypto';
import { join, resolve } from 'node:path';
import { parseArgs, parseEnv } from 'node:util';
import { setTimeout as delay } from 'node:timers/promises';
import { HermesApi } from '../apps/node/src/hermes/api';
import { runHermesCli, spawnHermesCli } from '../apps/node/src/hermes/cli';
import type { SseFrame } from '../apps/node/src/hermes/sse';

const { values } = parseArgs({ options: { root: { type: 'string' } } });
const root = resolve(values.root ?? process.cwd());
if (process.platform !== 'linux') throw new Error('Run the isolated clarify check in WSL/Linux.');
const note = JSON.parse(await readFile(join(root, '.runtime/hermes-last-spike.json'), 'utf8')) as {
  home: string;
  profile: string;
  source: string;
  runtime: string;
  dataRoot: string;
};
const env = parseEnv(await readFile(join(note.home, 'profiles', note.profile, '.env'), 'utf8'));
if (!env.API_SERVER_KEY) throw new Error('The isolated profile has no API server key.');
const redact = (raw: string) => {
  let text = raw;
  for (const value of [note.home, note.source, note.runtime, note.dataRoot, ...Object.values(env)])
    if (value && value.length > 8) text = text.replaceAll(value, '<redacted>');
  return text.replace(/Bearer\s+[^\s"\\]+/gi, 'Bearer <redacted>');
};
const launch = {
  command: 'bash',
  prefixArgs: [
    join(note.source, 'scripts/run-in-hermes-env'),
    'python',
    join(note.source, 'hermes'),
  ],
  cwd: note.source,
  home: note.home,
  runtimeDir: note.runtime,
};
await runHermesCli(launch, [
  '--profile',
  note.profile,
  'config',
  'set',
  'platform_toolsets.api_server',
  '["hermes-api-server","clarify"]',
]);
const gateway = spawnHermesCli(launch, ['gateway', 'run']);
const log = (data: Buffer) =>
  void appendFile(join(root, '.runtime/hermes-clarify-spike.log'), redact(data.toString()));
gateway.stdout?.on('data', log);
gateway.stderr?.on('data', log);
const api = new HermesApi('http://127.0.0.1:18642/p/' + note.profile, env.API_SERVER_KEY);
try {
  let healthy = false;
  for (let i = 0; i < 90; i++) {
    if (
      await api.health().then(
        () => true,
        () => false,
      )
    ) {
      healthy = true;
      break;
    }
    if (gateway.exitCode !== null) throw new Error('Isolated gateway exited.');
    await delay(1000);
  }
  if (!healthy) throw new Error('Isolated gateway did not start.');
  const created = await api.createRun(
    'Use the clarify tool now to ask: Which harmless test label should I use? Offer exactly two choices: Amber and Teal. Wait for my answer. After I answer, reply with exactly NEKODOT_CLARIFY_OK followed by the selected label. Do not use any other tool.',
    'nk_clarify_' + randomUUID(),
    randomUUID(),
  );
  const frames: SseFrame[] = [];
  let pending, response;
  for await (const frame of api.events(created.run_id, -1, AbortSignal.timeout(180_000))) {
    frames.push(frame);
    if (frame.event === 'clarify.request') {
      pending = await api.state(created.run_id);
      const control = pending.pending_controls?.find((c) => c.kind === 'clarify');
      if (!control) throw new Error('Hermes did not expose the native pending question.');
      response = await api.clarify(
        created.run_id,
        control.prompt_id,
        control.execution_generation ?? pending.execution_generation ?? 0,
        'Amber',
      );
    }
  }
  const final = await api.state(created.run_id);
  await writeFile(
    join(root, '.runtime/hermes-clarify-attempt.json'),
    redact(
      JSON.stringify(
        { events: frames.map((frame) => frame.data), pending, response, final },
        null,
        2,
      ),
    ),
  );
  if (
    !pending ||
    !response ||
    final.status !== 'completed' ||
    !final.output?.includes('NEKODOT_CLARIFY_OK') ||
    !final.output.includes('Amber')
  )
    throw new Error('The real native clarify round trip did not complete.');
  await mkdir(join(root, 'docs/fixtures'), { recursive: true });
  await writeFile(
    join(root, 'docs/fixtures/runs-clarify.sse'),
    redact(frames.map((f) => f.raw).join('')),
  );
  await writeFile(
    join(root, 'docs/fixtures/runs-clarify.state.json'),
    redact(JSON.stringify({ created, pending, response, final }, null, 2)) + '\n',
  );
  console.log(
    'Real Hermes clarify passed: native question, choice accepted, same run completed. Sanitized fixtures recorded.',
  );
} catch (error) {
  console.error(redact(error instanceof Error ? error.message : String(error)));
  process.exitCode = 1;
} finally {
  gateway.kill('SIGTERM');
  if (gateway.exitCode === null)
    await Promise.race([new Promise<void>((r) => gateway.once('exit', () => r())), delay(30_000)]);
  if (gateway.exitCode === null) gateway.kill('SIGKILL');
}
