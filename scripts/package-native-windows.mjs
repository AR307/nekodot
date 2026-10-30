import { access, mkdir, readFile, readdir } from 'node:fs/promises';
import { execFileSync, spawn } from 'node:child_process';
import { join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('..', import.meta.url));
if (process.platform !== 'win32') throw new Error('Package the Windows installer on Windows x64.');
const pubspec = await readFile(join(root, 'apps/native/pubspec.yaml'), 'utf8');
const [, version, build] = pubspec.match(/^version: (\d+\.\d+\.\d+)\+(\d+)$/m) ?? [];
if (!version || !build)
  throw new Error('pubspec.yaml must have a release version and build number.');
const bundle = join(root, 'apps/native/build/windows/x64/runner/Release');
await access(join(bundle, 'nekodot_native.exe'));
const nsis = process.env.MAKENSIS ?? join(process.env.LOCALAPPDATA, 'tauri/NSIS/makensis.exe');
await access(nsis);
const vswhere = join(
  process.env['ProgramFiles(x86)'],
  'Microsoft Visual Studio/Installer/vswhere.exe',
);
const visualStudio = execFileSync(
  vswhere,
  [
    '-latest',
    '-requires',
    'Microsoft.VisualStudio.Component.VC.Tools.x86.x64',
    '-property',
    'installationPath',
  ],
  { encoding: 'utf8' },
).trim();
const runtimes = join(visualStudio, 'VC/Redist/MSVC');
const runtimeVersion = (await readdir(runtimes))
  .filter((name) => /^\d+(\.\d+)+$/.test(name))
  .sort((a, b) => b.localeCompare(a, 'en', { numeric: true }))[0];
if (!runtimeVersion)
  throw new Error('Install the official Visual Studio x64 C++ redistributable files.');
const redist = join(runtimes, runtimeVersion, 'x64/Microsoft.VC143.CRT');
await access(join(redist, 'vcruntime140.dll'));
const output = resolve(root, `dist/native/nekodot_${version}_x64-setup.exe`);
await mkdir(join(root, 'dist/native'), { recursive: true });
const child = spawn(
  nsis,
  [
    '/V2',
    '/INPUTCHARSET',
    'UTF8',
    `/DROOT=${root}`,
    `/DBUNDLE=${bundle}`,
    `/DVC_REDIST=${redist}`,
    `/DVERSION=${version}`,
    `/DNUMERIC_VERSION=${version}.${build}`,
    `/DOUTPUT=${output}`,
    join(root, 'deploy/native/windows.nsi'),
  ],
  { cwd: root, stdio: 'inherit' },
);
child.on('error', (error) => {
  console.error(error.message);
  process.exitCode = 1;
});
child.on('exit', (code) => {
  process.exitCode = code ?? 1;
  if (code === 0) console.log(`Unsigned Windows installer: ${output}`);
});
