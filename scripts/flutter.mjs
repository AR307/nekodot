import { spawn } from 'node:child_process';
import { resolve, delimiter } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('..', import.meta.url));
const sdk = process.env.FLUTTER_ROOT ?? resolve(root, '.runtime/side-phase-3/flutter');
const env = {
  ...process.env,
  FLUTTER_ROOT: sdk,
  PUB_CACHE: process.env.PUB_CACHE ?? resolve(root, '.runtime/side-phase-3/pub-cache'),
  FLUTTER_SUPPRESS_ANALYTICS: 'true',
  CI: 'true',
  RUSTUP_TOOLCHAIN: process.env.RUSTUP_TOOLCHAIN ?? '1.90.0',
  JAVA_HOME: process.env.JAVA_HOME ?? 'D:/Android studio/jbr',
  ANDROID_HOME: process.env.ANDROID_HOME ?? resolve(process.env.LOCALAPPDATA, 'Android/Sdk'),
  PATH: [resolve(sdk, 'bin'), resolve(sdk, 'bin/cache/dart-sdk/bin'), process.env.PATH].join(
    delimiter,
  ),
};
const [tool = 'flutter', ...args] = process.argv.slice(2);
const command =
  tool === 'bridge'
    ? resolve(root, '.runtime/side-phase-3/rust-tools/bin/flutter_rust_bridge_codegen.exe')
    : resolve(sdk, 'bin', process.platform === 'win32' ? `${tool}.bat` : tool);
const child = spawn(command, args, {
  cwd: resolve(root, 'apps/native'),
  env,
  stdio: 'inherit',
  shell: process.platform === 'win32' && tool !== 'bridge',
});
child.on('error', (error) => {
  console.error(error.message);
  process.exitCode = 1;
});
child.on('exit', (code) => {
  process.exitCode = code ?? 1;
});
