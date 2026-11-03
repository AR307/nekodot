import { copyFile, mkdir, readFile, stat, writeFile, rename } from 'node:fs/promises';
import { resolve, join } from 'node:path';
import { execFileSync } from 'node:child_process';

const args = process.argv.slice(2);
const option = (name) => {
  const index = args.indexOf('--' + name);
  return index === -1 ? undefined : args[index + 1];
};
const root = resolve(import.meta.dirname, '..');
const pubspec = await readFile(join(root, 'apps/native/pubspec.yaml'), 'utf8');
const [, version, number] = pubspec.match(/^version: (\d+\.\d+\.\d+)\+(\d+)$/m) ?? [];
const product = JSON.parse(await readFile(join(root, 'package.json'), 'utf8'));
if (version !== product.version || !number)
  throw new Error('Root and Flutter release versions must match');
const image = option('image');
if (!image || !/^nekodot-relay:[a-zA-Z0-9_.-]+$/.test(image))
  throw new Error('Pass --image nekodot-relay:<tag> and --relay <docker save .tar>');
const inputs = {
  windows: option('windows') ?? join(root, 'dist/native/nekodot_' + version + '_x64-setup.exe'),
  android:
    option('android') ??
    join(root, 'dist/native/nekodot_' + version + '+' + number + '_android-arm64.apk'),
  relay: option('relay'),
};
if (!inputs.relay) throw new Error('Missing --relay <docker save .tar>');
for (const file of Object.values(inputs)) {
  if ((await stat(file)).size === 0) throw new Error('Empty artifact: ' + file);
}
const aapt = option('aapt') ?? 'aapt';
const apk = execFileSync(aapt, ['dump', 'badging', inputs.android], { encoding: 'utf8' });
const [, appId, androidBuild, androidVersion] =
  apk.match(/package: name='([^']+)' versionCode='(\d+)' versionName='([^']+)'/) ?? [];
if (appId !== 'app.nekodot.client' || androidVersion !== version)
  throw new Error('Android package must match the product application ID and release version');
const directory = resolve(option('output') ?? join(root, 'dist/distribution'));
const releasePath = 'releases/' + version + '-' + number;
// A version/build is immutable. A rebuild needs a higher build number.
await mkdir(join(directory, 'releases'), { recursive: true });
await mkdir(join(directory, releasePath));
const artifacts = {};
for (const [platform, file] of Object.entries(inputs)) {
  const name = {
    windows: 'nekodot-windows-x64.exe',
    android: 'nekodot-android-arm64.apk',
    relay: 'nekodot-relay.tar',
  }[platform];
  const path = releasePath + '/' + name;
  await copyFile(file, join(directory, path));
  artifacts[platform] = {
    path,
    size: (await stat(file)).size,
    build: platform === 'android' ? Number(androidBuild) : Number(number),
    ...(platform === 'relay' ? { image } : {}),
  };
}
const manifest = {
  schema: 1,
  version,
  build: Number(number),
  publishedAt: new Date().toISOString(),
  notes: option('notes') ? await readFile(option('notes'), 'utf8') : '',
  artifacts,
};
await writeFile(join(directory, 'latest.json.next'), JSON.stringify(manifest, null, 2) + '\n');
await rename(join(directory, 'latest.json.next'), join(directory, 'latest.json'));
console.log('Release manifest prepared locally: ' + join(directory, 'latest.json'));
