import { cp, mkdir, mkdtemp, readFile, symlink, writeFile } from 'node:fs/promises';
import { execFileSync } from 'node:child_process';
import { join, resolve } from 'node:path';

const root = resolve(import.meta.dirname, '..');
const platform = process.argv[2];
if (
  !['macos', 'linux'].includes(platform) ||
  process.platform !== (platform === 'macos' ? 'darwin' : 'linux')
)
  throw new Error('Run package-native-posix.mjs macos|linux on the target host.');
if (process.arch !== (platform === 'macos' ? 'arm64' : 'x64'))
  throw new Error('Supported hosts are macOS Apple Silicon and Ubuntu x64.');
const pubspec = await readFile(join(root, 'apps/native/pubspec.yaml'), 'utf8');
const [, version, build] = pubspec.match(/^version: ([0-9.]+)\+([0-9]+)$/m) ?? [];
if (!version || !build) throw new Error('Missing product version.');
const dist = join(root, 'dist/native');
await mkdir(dist, { recursive: true });
// Keep packaging work for inspection; no cleanup touches user data or another build.
const stage = await mkdtemp(join(dist, platform + '-package-'));
if (platform === 'macos') {
  const app = join(stage, 'nekoDOT.app');
  await cp(join(root, 'apps/native/build/macos/Build/Products/Release/nekoDOT.app'), app, {
    recursive: true,
  });
  const identity = process.env.NEKODOT_APPLE_SIGNING_IDENTITY;
  if (identity) {
    execFileSync(
      'codesign',
      ['--force', '--deep', '--options', 'runtime', '--sign', identity, app],
      { stdio: 'inherit' },
    );
    const profile = process.env.NEKODOT_APPLE_NOTARY_PROFILE;
    if (profile) {
      const archive = join(stage, 'notarize.zip');
      execFileSync('ditto', ['-c', '-k', '--keepParent', app, archive], { stdio: 'inherit' });
      execFileSync(
        'xcrun',
        ['notarytool', 'submit', archive, '--keychain-profile', profile, '--wait'],
        { stdio: 'inherit' },
      );
      execFileSync('xcrun', ['stapler', 'staple', app], { stdio: 'inherit' });
    }
  }
  await symlink('/Applications', join(stage, 'Applications'));
  const output = join(dist, 'nekoDOT_' + version + '+' + build + '_macos-arm64.dmg');
  // Only include the application and Applications shortcut, not notary artifacts.
  const imageRoot = await mkdtemp(join(dist, 'dmg-'));
  await cp(app, join(imageRoot, 'nekoDOT.app'), { recursive: true });
  await symlink('/Applications', join(imageRoot, 'Applications'));
  execFileSync(
    'hdiutil',
    ['create', '-volname', 'nekoDOT', '-srcfolder', imageRoot, '-format', 'UDZO', output],
    { stdio: 'inherit' },
  );
  console.log(
    output +
      (identity
        ? ' (Developer ID signed)'
        : ' (no Developer ID or notarization; local testing only)'),
  );
} else {
  const bundle = join(stage, 'opt/nekodot');
  await cp(join(root, 'apps/native/build/linux/x64/release/bundle'), bundle, { recursive: true });
  await mkdir(join(stage, 'usr/bin'), { recursive: true });
  await symlink('/opt/nekodot/nekoDOT', join(stage, 'usr/bin/nekoDOT'));
  await mkdir(join(stage, 'usr/share/applications'), { recursive: true });
  await writeFile(
    join(stage, 'usr/share/applications/app.nekodot.client.desktop'),
    [
      '[Desktop Entry]',
      'Type=Application',
      'Name=nekoDOT',
      'Exec=nekoDOT',
      'Icon=app.nekodot.client',
      'Terminal=false',
      'Categories=Network;Utility;',
      'StartupWMClass=app.nekodot.client',
      '',
    ].join('\n'),
  );
  const icons = join(stage, 'usr/share/icons/hicolor/256x256/apps');
  await mkdir(icons, { recursive: true });
  await cp(join(root, 'apps/native/assets/nekodot.png'), join(icons, 'app.nekodot.client.png'));
  await mkdir(join(stage, 'DEBIAN'));
  await writeFile(
    join(stage, 'DEBIAN/control'),
    [
      'Package: nekodot',
      'Version: ' + version + '-' + build,
      'Architecture: amd64',
      'Maintainer: nekoDOT contributors',
      'Section: net',
      'Priority: optional',
      'Depends: libc6 (>= 2.39), libstdc++6, libgtk-3-0t64, libsecret-1-0, libx11-6, libxi6, libepoxy0, liblzma5, libpulse0, libatomic1, gnome-keyring, git, curl, ca-certificates',
      'Description: Native nekoDOT client with optional local Hermes Bots',
      '',
    ].join('\n'),
  );
  const output = join(dist, 'nekoDOT_' + version + '+' + build + '_linux-x64.deb');
  execFileSync('dpkg-deb', ['--root-owner-group', '--build', stage, output], { stdio: 'inherit' });
  console.log(output);
}
