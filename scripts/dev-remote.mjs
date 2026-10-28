import { execFileSync, spawn } from 'node:child_process';
import { existsSync } from 'node:fs';
import { createServer } from 'node:net';
import { resolve, win32 } from 'node:path';
import { parseArgs } from 'node:util';

const { values } = parseArgs({
  options: {
    ssh: { type: 'string' },
    lan: { type: 'boolean', default: false },
    port: { type: 'string', default: '4318' },
    'no-open': { type: 'boolean', default: false },
  },
});
if (!values.ssh) throw new Error('Usage: pnpm dev:remote --ssh <SSH target> [--lan]');
if (!/^(?:[a-zA-Z0-9_.-]+@)?[a-zA-Z0-9_.-]+$/.test(values.ssh))
  throw new Error('SSH target must be a configured host alias or user@host.');
const relayUrl = 'http://127.0.0.1:4329';
const wslPath = (path) =>
  path
    .replace(/^([A-Za-z]):[\\/]/, (_, drive) => `/mnt/${drive.toLowerCase()}/`)
    .replaceAll('\\', '/');
let wslSshIdentity = '';
let wslKnownHosts = '';
try {
  const config = execFileSync('ssh', ['-G', values.ssh], { encoding: 'utf8', windowsHide: true });
  const configured = (name) =>
    config
      .split(/\r?\n/)
      .filter((line) => line.startsWith(name + ' '))
      .flatMap((line) => line.slice(name.length + 1).split(' '))
      .filter(Boolean);
  const nativePath = (path) =>
    win32.isAbsolute(path)
      ? path
      : path.startsWith('~/')
        ? win32.join(process.env.USERPROFILE ?? '', path.slice(2))
        : win32.resolve(path);
  const identity = configured('identityfile')
    .map(nativePath)
    .find((path) => existsSync(path));
  const knownHosts = configured('userknownhostsfile')
    .map(nativePath)
    .find((path) => existsSync(path));
  if (identity && knownHosts) {
    wslSshIdentity = wslPath(identity);
    wslKnownHosts = wslPath(knownHosts);
  }
} catch {
  // Keep the remote development page available when this SSH profile has no local key file.
}
let ownsTunnel = false;
await new Promise((resolve, reject) => {
  const probe = createServer();
  probe.once('error', async () => {
    try {
      const response = await fetch(relayUrl + '/health', { signal: AbortSignal.timeout(2000) });
      const status = await response.json();
      if (response.ok && status.service === 'nekodot-relay' && status.status === 'ok') resolve();
      else reject(new Error('Local port 4329 is in use by a service that is not nekodot Relay.'));
    } catch {
      reject(
        new Error('Local port 4329 is in use and no healthy nekodot Relay tunnel is available.'),
      );
    }
  });
  probe.listen(4329, '127.0.0.1', () =>
    probe.close(() => {
      ownsTunnel = true;
      resolve();
    }),
  );
});
let closing = false;
let ssh;
let web;
let retry;
let backoff = 1000;
const root = process.cwd();
function startTunnel() {
  console.log('Connecting the SSH tunnel...');
  ssh = spawn(
    'ssh',
    [
      '-N',
      '-o',
      'BatchMode=yes',
      '-o',
      'StrictHostKeyChecking=yes',
      '-o',
      'ExitOnForwardFailure=yes',
      '-o',
      'ServerAliveInterval=15',
      '-o',
      'ServerAliveCountMax=3',
      '-L',
      '127.0.0.1:4329:127.0.0.1:4329',
      values.ssh,
    ],
    { stdio: ['ignore', 'ignore', 'inherit'], windowsHide: true },
  );
  ssh.once('error', (error) => {
    console.error('SSH could not start:', error.message);
    shutdown(1);
  });
  ssh.once('exit', () => {
    if (closing) return;
    console.log('SSH disconnected; reconnecting. The web page stays open.');
    retry = setTimeout(startTunnel, backoff);
    backoff = Math.min(backoff * 2, 30000);
  });
}
function startWeb() {
  const args = [
    resolve(root, 'node_modules/vite/bin/vite.js'),
    '--host',
    values.lan ? '0.0.0.0' : '127.0.0.1',
    '--port',
    values.port,
    '--strictPort',
  ];
  if (!values['no-open']) args.push('--open');
  web = spawn(process.execPath, args, {
    cwd: resolve(root, 'apps/web'),
    env: {
      ...process.env,
      NEKODOT_RELAY_URL: relayUrl,
      NEKODOT_RELAY_SSH: values.ssh,
      NEKODOT_RELAY_SSH_IDENTITY: wslSshIdentity,
      NEKODOT_RELAY_SSH_KNOWN_HOSTS: wslKnownHosts,
    },
    stdio: 'inherit',
    windowsHide: true,
  });
  web.once('error', (error) => {
    console.error(error.message);
    shutdown(1);
  });
  web.once('exit', (code) => shutdown(code ?? 1));
}
function shutdown(code = 0) {
  if (closing) return;
  closing = true;
  clearTimeout(retry);
  clearInterval(health);
  ssh?.kill();
  web?.kill();
  process.exitCode = code;
}
const health = setInterval(async () => {
  try {
    const response = await fetch(relayUrl + '/health', { signal: AbortSignal.timeout(2000) });
    if (!response.ok || closing) return;
    backoff = 1000;
  } catch {
    /* The tunnel supervisor reconnects; keep the existing web process. */
  }
}, 1000);
if (ownsTunnel) startTunnel();
else console.log('Reusing the existing local nekodot Relay tunnel.');
startWeb();
process.on('SIGINT', () => shutdown());
process.on('SIGTERM', () => shutdown());
