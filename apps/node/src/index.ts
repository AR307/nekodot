#!/usr/bin/env node
import pino from 'pino';
import { execFile } from 'node:child_process';
import { homedir } from 'node:os';
import { join } from 'node:path';
import { readFile, mkdir, appendFile } from 'node:fs/promises';
import { parseArgs } from 'node:util';
import { nodeCredentialsSchema } from '@nekodot/protocol';
import { pairNode } from './pair';
import { ManagedHermes } from './hermes/runtime';
import { connectRelay } from './connection';
import { NodeApplication } from './app';
import { NodeUpdater } from './updater';
import { bridgeEndpoint } from './bridge';
import { nodeVersion, releaseKey, isRelease } from './release';
import { NodeUsage } from './usage';

async function main() {
  const { values, positionals } = parseArgs({
    allowPositionals: true,
    options: {
      relay: { type: 'string' },
      code: { type: 'string' },
      name: { type: 'string' },
      'hermes-source': { type: 'string' },
      'hermes-runtime': { type: 'string' },
      'hermes-launcher': { type: 'string' },
      desktop: { type: 'boolean' },
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
    const desktop = values.desktop === true;
    await mkdir(join(home, 'logs'), { recursive: true, mode: 0o700 });
    const parts: {
      app?: NodeApplication;
      updater?: NodeUpdater;
      connection?: ReturnType<typeof connectRelay>;
      usage?: NodeUsage;
    } = {};
    const bridge = bridgeEndpoint(home);
    const runtime = new ManagedHermes({
      home: join(home, 'hermes'),
      apiPort: Number(process.env.NEKODOT_HERMES_API_PORT ?? 18642),
      source: values['hermes-source'] ?? process.env.NEKODOT_HERMES_SOURCE,
      launcher: values['hermes-launcher'] ?? process.env.NEKODOT_HERMES_LAUNCHER,
      bridge,
      runtime:
        values['hermes-runtime'] ??
        process.env.NEKODOT_HERMES_RUNTIME ??
        join(home, 'hermes-runtime'),
      onReady: () => {
        void parts.app?.resume();
      },
      onLog: (line) => {
        void appendFile(join(home, 'logs', 'hermes.log'), line);
      },
    });
    let stopping: Promise<void> | undefined;
    const shutdown = () =>
      (stopping ??= (async () => {
        report('stopping');
        parts.updater?.close();
        parts.connection?.close();
        await parts.usage?.close();
        await parts.app?.close();
        await runtime.close();
      })());
    // Registered before Hermes starts so a stop during a long first boot still reaps its children.
    for (const signal of ['SIGINT', 'SIGTERM'] as const)
      process.on(signal, () => {
        void shutdown();
      });
    if (desktop) {
      // The desktop client owns this process: a closed stdin means the client is gone.
      const stop = () =>
        void shutdown().finally(() => {
          report('stopped');
          process.exit(0);
        });
      process.stdin.setEncoding('utf8');
      process.stdin.on('data', (chunk: string) => {
        if (chunk.split('\n').some((line) => line.trim() === 'stop')) stop();
      });
      process.stdin.once('end', stop);
      process.stdin.once('close', stop);
    }
    function report(state: string, detail?: string) {
      if (desktop) process.stdout.write(JSON.stringify({ desktop: { state, detail } }) + '\n');
    }
    report('starting');
    log.info({ service: 'nekodot-node' }, 'Starting Hermes before connecting to Relay');
    await runtime.start();
    const app = new NodeApplication(home, runtime, desktop);
    parts.app = app;
    const usage = (parts.usage = new NodeUsage(app.database, runtime));
    usage.onError = (message) => log.error({ service: 'nekodot-node', message });
    app.routines.onError = (message) => log.error({ service: 'nekodot-node', message });
    await app.routines.start(bridge);
    const updater = (parts.updater = new NodeUpdater({
      home,
      relayUrl: credentials.relayUrl,
      version: nodeVersion,
      releaseKey,
      file: typeof __filename === 'string' ? __filename : '',
      idle: () => app.idle,
      restart: async () => {
        await shutdown();
        process.exit(75);
      },
      log: (message) => log.info({ service: 'nekodot-node' }, message),
    }));
    const connection = (parts.connection = connectRelay({
      credentials,
      version: nodeVersion,
      onUpdate: () => {
        if (isRelease) void updater.offer();
      },
      handleRpc: (request) => {
        app.secrets.bind(credentials.nodeId);
        return app.handle(request);
      },
      userMemory: app.userMemory,
      connectors: app.connectors,
      routines: app.routines,
      usage,
      handleTransfer: (request) => app.files.transfer(request),
      onTunnel: (request) => app.screens.openTunnel(credentials, request),
      onReady: async () => {
        await updater.confirmReady();
        if (process.env.NOTIFY_SOCKET)
          execFile(
            'systemd-notify',
            ['--ready', '--status=Connected to nekodot Relay'],
            (error) => {
              if (error) log.error('Could not notify systemd that the node is ready');
            },
          );
        app.activities();
        app.notifications.flush();
      },
      onNotifyAck: (id) => app.notifications.acknowledge(id),
      onStatus: (online) => {
        log.info({ service: 'nekodot-node', online });
        if (!stopping) report(online ? 'online' : 'offline');
      },
      onError: (message) => log.error({ service: 'nekodot-node', message }),
    }));
    app.onEvent = connection.event;
    app.onLive = connection.live;
    app.notifications.onSend = connection.notify;
    await app.resume();
  } else
    console.log(
      'nekodot-node pair --relay <url> --code <code> | nekodot-node run [--desktop] [--hermes-launcher <path>]',
    );
}
void main().catch((reason: unknown) => {
  const detail = reason instanceof Error ? reason.message : 'Unknown startup error';
  console.error('Node startup failed:', detail);
  if (process.argv.includes('--desktop'))
    process.stdout.write(JSON.stringify({ desktop: { state: 'failed', detail } }) + '\n');
  process.exitCode = 1;
});
