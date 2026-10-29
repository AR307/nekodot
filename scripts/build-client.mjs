import { spawn } from 'node:child_process';
import { mkdir, readFile, writeFile, copyFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { join, relative } from 'node:path';
import { parseArgs } from 'node:util';

const root = fileURLToPath(new URL('..', import.meta.url));
const { positionals, values } = parseArgs({
  allowPositionals: true,
  options: { relay: { type: 'string' }, debug: { type: 'boolean' }, target: { type: 'string' } },
});
const platform = positionals[0];
if (!['windows', 'android'].includes(platform)) throw new Error('Choose windows or android');
if (platform === 'android' && !values.debug && values.target && values.target !== 'aarch64')
  throw new Error('Product Android releases use aarch64; use --debug for emulator targets');
const relay = new URL(values.relay ?? process.env.NEKODOT_RELAY_URL ?? '');
if (relay.protocol !== 'https:' || relay.username || relay.password || relay.pathname !== '/')
  throw new Error('Set NEKODOT_RELAY_URL to the product HTTPS origin (no credentials or path)');
const env = {
  ...process.env,
  NEKODOT_NODE_BINARY: process.execPath,
  VITE_NEKODOT_RELAY_URL: relay.origin,
  VITE_NEKODOT_NATIVE: '1',
};
const cli = join(root, 'apps/client/node_modules/@tauri-apps/cli/tauri.js');
const work = join(root, '.runtime/side-stage-2');
await mkdir(join(work, 'private'), { recursive: true });
const frontend = join(work, `frontend-${platform}-${Date.now()}`);
const config = join(work, 'client-config.json');
await writeFile(
  config,
  JSON.stringify({
    build: {
      frontendDist: relative(join(root, 'apps/client/src-tauri'), frontend).replaceAll('\\', '/'),
    },
    app: {
      security: {
        csp: `default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data: blob:; font-src 'self' data:; frame-src 'self' blob:; worker-src 'self' blob:; connect-src 'self' ipc: http://ipc.localhost https://ipc.localhost ${relay.origin} ${relay.origin.replace('https:', 'wss:')}`,
      },
    },
  }),
);
function run(command, args, cwd = root) {
  return new Promise((resolve, reject) => {
    const child = spawn(command, args, { cwd, env, stdio: 'inherit', shell: false });
    child.on('error', reject);
    child.on('exit', (code) =>
      code === 0 ? resolve() : reject(new Error(`Build step failed (${code})`)),
    );
  });
}
await run(
  process.execPath,
  [join(root, 'node_modules/vite/bin/vite.js'), 'build', '--outDir', frontend],
  join(root, 'apps/web'),
);
if (platform === 'android') {
  const firebase = join(work, 'private/google-services.json');
  const settings = JSON.parse(await readFile(firebase, 'utf8'));
  if (
    !settings.client.some(
      (c) => c.client_info?.android_client_info?.package_name === 'app.nekodot.client',
    )
  )
    throw new Error('Firebase configuration must contain app.nekodot.client');
  await copyFile(
    firebase,
    join(root, 'apps/client/src-tauri/gen/android/app/google-services.json'),
  );
  if (
    !values.debug &&
    !(
      env.NEKODOT_ANDROID_KEYSTORE &&
      env.NEKODOT_ANDROID_KEY_ALIAS &&
      env.NEKODOT_ANDROID_STORE_PASSWORD &&
      env.NEKODOT_ANDROID_KEY_PASSWORD
    )
  )
    throw new Error(
      'Android release requires the four NEKODOT_ANDROID signing environment variables',
    );
}
await run(
  process.execPath,
  [
    cli,
    ...(platform === 'android'
      ? ['android', 'build', '--apk', '--target', values.target ?? 'aarch64']
      : ['build', '--bundles', 'nsis']),
    '--config',
    config,
    ...(values.debug ? ['--debug'] : []),
  ],
  join(root, 'apps/client'),
);
if (!values.debug) {
  const version = JSON.parse(
    await readFile(join(root, 'apps/client/src-tauri/tauri.conf.json'), 'utf8'),
  ).version;
  const artifact =
    platform === 'windows'
      ? join(
          root,
          `apps/client/src-tauri/target/release/bundle/nsis/nekodot_${version}_x64-setup.exe`,
        )
      : join(
          root,
          'apps/client/src-tauri/gen/android/app/build/outputs/apk/universal/release/app-universal-release.apk',
        );
  const name = platform === 'windows' ? 'nekodot-windows-x64.exe' : 'nekodot-android-arm64.apk';
  for (const destination of ['release', 'dist/distribution']) {
    await mkdir(join(root, destination), { recursive: true });
    await copyFile(artifact, join(root, destination, name));
  }
}
