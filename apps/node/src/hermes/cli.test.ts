import { mkdtemp } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { expect, it } from 'vitest';
import { runHermesCli } from './cli';

it('passes the isolated profile environment without letting Hermes announce Node service readiness', async () => {
  const directory = await mkdtemp(join(tmpdir(), 'nekodot-cli-ready-'));
  const output = await runHermesCli(
    {
      command: process.execPath,
      cwd: directory,
      home: join(directory, 'hermes'),
      runtimeDir: join(directory, 'runtime'),
      env: { NOTIFY_SOCKET: '/run/test-node-notification' },
    },
    [
      '-e',
      'console.log(JSON.stringify({home:process.env.HERMES_HOME,runtime:process.env.HERMES_RUNTIME_DIR,notify:process.env.NOTIFY_SOCKET??null}))',
    ],
  );
  expect(JSON.parse(output)).toEqual({
    home: join(directory, 'hermes'),
    runtime: join(directory, 'runtime'),
    notify: null,
  });
});
