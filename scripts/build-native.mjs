import { copyFile, mkdir, readFile } from 'node:fs/promises';
import { spawn } from 'node:child_process';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('..', import.meta.url));
const [platform, ...args] = process.argv.slice(2);
const value = (name) => {
  const index = args.indexOf('--' + name);
  return index < 0 ? undefined : args[index + 1];
};
if (!['android', 'windows'].includes(platform))
  throw new Error(
    'Usage: node scripts/build-native.mjs windows|android [--debug] [--signing <private JSON>] [--firebase <google-services.json>]',
  );
const env = { ...process.env };
const debug = args.includes('--debug');
const targetPlatform = value('target-platform') ?? 'android-arm64';
const abi = { 'android-arm64': 'arm64-v8a', 'android-x64': 'x86_64' }[targetPlatform];
if (platform === 'android') {
  if (!abi) throw new Error('Choose android-arm64 or android-x64 for this Android package.');
  const signing = value('signing') ?? env.NEKODOT_ANDROID_SIGNING_CONFIG;
  if (signing) Object.assign(env, JSON.parse(await readFile(resolve(signing), 'utf8')));
  if (
    !debug &&
    ![
      'NEKODOT_ANDROID_KEYSTORE',
      'NEKODOT_ANDROID_KEY_ALIAS',
      'NEKODOT_ANDROID_STORE_PASSWORD',
      'NEKODOT_ANDROID_KEY_PASSWORD',
    ].every((key) => env[key])
  )
    throw new Error('Android release requires the existing private signing configuration.');
  const firebase = value('firebase') ?? env.NEKODOT_FIREBASE_CONFIG;
  if (!firebase)
    throw new Error('Pass --firebase <private google-services.json> for this Android build.');
  const config = JSON.parse(await readFile(resolve(firebase), 'utf8'));
  if (
    !config.client?.some(
      (client) => client.client_info?.android_client_info?.package_name === 'app.nekodot.client',
    )
  )
    throw new Error('Firebase configuration must target app.nekodot.client.');
  await copyFile(resolve(firebase), resolve(root, 'apps/native/android/app/google-services.json'));
}
const relay = value('relay') ?? env.NEKODOT_RELAY_URL ?? 'https://nekodot.com';
if (new URL(relay).protocol !== 'https:') throw new Error('Product builds require HTTPS.');
const command = [
  'scripts/flutter.mjs',
  'flutter',
  'build',
  platform === 'android' ? 'apk' : 'windows',
  debug ? '--debug' : '--release',
  `--dart-define=RELAY_URL=${relay}`,
];
if (platform === 'android') {
  command.push('--target-platform', targetPlatform);
  // Dependencies can bundle other ABIs; let Flutter package only the selected ABI.
  if (!debug) command.push('--split-per-abi');
}
const child = spawn(process.execPath, command, { cwd: root, env, stdio: 'inherit' });
child.on('error', (error) => {
  console.error(error.message);
  process.exitCode = 1;
});
child.on('exit', async (code) => {
  process.exitCode = code ?? 1;
  if (code !== 0 || debug) return;
  if (platform === 'windows') {
    const installer = spawn(process.execPath, ['scripts/package-native-windows.mjs'], {
      cwd: root,
      env,
      stdio: 'inherit',
    });
    installer.on('error', (error) => {
      console.error(error.message);
      process.exitCode = 1;
    });
    installer.on('exit', (result) => {
      process.exitCode = result ?? 1;
    });
  } else {
    const pubspec = await readFile(resolve(root, 'apps/native/pubspec.yaml'), 'utf8');
    const version = pubspec.match(/^version: (\S+)$/m)?.[1];
    await mkdir(resolve(root, 'dist/native'), { recursive: true });
    const output = resolve(root, `dist/native/nekodot_${version}_${targetPlatform}.apk`);
    await copyFile(
      resolve(root, `apps/native/build/app/outputs/flutter-apk/app-${abi}-release.apk`),
      output,
    );
    console.log(`Signed Android APK: ${output}`);
  }
});
