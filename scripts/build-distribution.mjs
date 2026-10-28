import { build } from 'esbuild';
import { mkdir, copyFile, readFile, writeFile } from 'node:fs/promises';
import { resolve } from 'node:path';

await mkdir('dist/distribution', { recursive: true });
await copyFile('apps/node/dist/index.cjs', 'dist/distribution/nekodot-node.cjs');
await copyFile('deploy/install.sh', 'dist/distribution/install.sh');
await build({
  entryPoints: ['apps/relay/src/index.ts'],
  outfile: 'dist/relay/index.mjs',
  bundle: true,
  platform: 'node',
  format: 'esm',
  target: 'node24',
  packages: 'external',
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
