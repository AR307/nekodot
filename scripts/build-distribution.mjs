import { build } from 'esbuild';
import { mkdir, copyFile, readFile, writeFile, rename } from 'node:fs/promises';
import { resolve } from 'node:path';

await mkdir('dist/distribution', { recursive: true });
// Retain stale manifests privately instead of serving them with a new bundle.
try {
  await mkdir('.runtime/recycle', { recursive: true });
  await rename(
    'dist/distribution/nekodot-node.json',
    `.runtime/recycle/nekodot-node-${Date.now()}.json`,
  );
} catch (error) {
  if (error.code !== 'ENOENT') throw error;
}
await copyFile('apps/node/dist/index.cjs', 'dist/distribution/nekodot-node.cjs');
const runtime = JSON.parse(await readFile('deploy/hermes-runtime-recipe.json', 'utf8'));
await writeFile(
  'dist/distribution/install.sh',
  (await readFile('deploy/install.sh', 'utf8')).replaceAll(
    '__NEKODOT_HERMES_RUNTIME__',
    runtime.version,
  ),
);
const pubspec = await readFile('apps/native/pubspec.yaml', 'utf8');
const buildNumber = pubspec.match(/^version: \d+\.\d+\.\d+\+(\d+)$/m)?.[1];
if (!buildNumber) throw new Error('Native release build number is missing');
await build({
  entryPoints: ['apps/relay/src/index.ts'],
  outfile: 'dist/relay/index.mjs',
  bundle: true,
  platform: 'node',
  format: 'esm',
  target: 'node24',
  packages: 'external',
  define: { 'process.env.NEKODOT_BUILD_NUMBER': JSON.stringify(buildNumber) },
  alias: { '@nekodot/protocol': resolve('packages/protocol/src/index.ts') },
});
const manifest = JSON.parse(await readFile('apps/relay/package.json', 'utf8'));
const { '@nekodot/protocol': workspace, ...dependencies } = manifest.dependencies;
void workspace;
await writeFile(
  'dist/relay/package.json',
  JSON.stringify(
    { name: 'nekodot-relay-runtime', private: true, type: 'module', dependencies },
    null,
    2,
  ) + '\n',
);
