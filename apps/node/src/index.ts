#!/usr/bin/env node
import pino from 'pino';
import { homedir } from 'node:os';
import { join } from 'node:path';
import { readFile, mkdir, appendFile } from 'node:fs/promises';
import { parseArgs } from 'node:util';
import { nodeCredentialsSchema } from '@nekodot/protocol';
import { pairNode } from './pair';
import { ManagedHermes } from './hermes/runtime';
import { connectRelay } from './connection';
import { NodeApplication } from './app';

async function main() {
  const { values, positionals } = parseArgs({
    allowPositionals: true,
    options: {
      relay: { type: 'string' },
      code: { type: 'string' },
      name: { type: 'string' },
      'hermes-source': { type: 'string' },
      'hermes-runtime': { type: 'string' },
    },
  });
  const home = process.env.NEKODOT_HOME ?? join(homedir(), '.nekodot');
  if (positionals[0] === 'pair') {
    if (!values.relay || !values.code)
      throw new Error('Usage: nekodot-node pair --relay <url> --code <code>');
    await pairNode(home, values.relay, values.code, values.name);
    console.log('Paired. Run nekodot-node run, then return to the web app.');
  } else if (positionals[0] === 'run') {
    const credentials = nodeCredentialsSchema.parse(
      JSON.parse(await readFile(join(home, 'node.json'), 'utf8')),
    );
    const log = pino();
    await mkdir(join(home, 'logs'), { recursive: true, mode: 0o700 });
    const appRef: { current?: NodeApplication } = {};
    const runtime = new ManagedHermes({
      home: join(home, 'hermes'),
      source: values['hermes-source'] ?? process.env.NEKODOT_HERMES_SOURCE,
      runtime:
        values['hermes-runtime'] ??
        process.env.NEKODOT_HERMES_RUNTIME ??
        join(home, 'hermes-runtime'),
      onReady: () => {
        void appRef.current?.resume();
      },
      onLog: (line) => {
        void appendFile(join(home, 'logs', 'hermes.log'), line);
      },
    });
    await runtime.start();
    const app = new NodeApplication(home, runtime);
    appRef.current = app;
    const connection = connectRelay({
      credentials,
      handleRpc: (request) => app.handle(request),
      onReady: () => app.activities(),
      onStatus: (online) => log.info({ service: 'nekodot-node', online }),
    });
    app.onEvent = connection.event;
    app.onLive = connection.live;
    await app.resume();
    let closing = false;
    for (const signal of ['SIGINT', 'SIGTERM'] as const)
      process.on(signal, () => {
        void shutdown();
      });
    async function shutdown() {
      if (closing) return;
      closing = true;
      connection.close();
      await runtime.close();
      await app.close();
    }
  } else console.log('nekodot-node pair --relay <url> --code <code> | nekodot-node run');
}
void main().catch(() => {
  console.error('Node startup failed. Check pairing credentials, runtime paths and local logs.');
  process.exitCode = 1;
});
