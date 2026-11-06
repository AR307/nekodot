import { copyFile, mkdir, readFile, stat, writeFile } from 'node:fs/promises';
import { dirname, join, resolve } from 'node:path';

// Build on each target host, then stage its metadata and archive beside Node downloads.
const args = process.argv.slice(2);
const index = args.indexOf('--output');
const directory = resolve(index < 0 ? 'dist/distribution' : args.splice(index, 2)[1]);
const recipe = JSON.parse(await readFile('deploy/hermes-runtime-recipe.json', 'utf8'));
if (!args.length) throw new Error('Pass the target JSON files produced by build-hermes-runtime.py');
for (const input of args) {
  const metadata = JSON.parse(await readFile(input, 'utf8'));
  if (
    metadata.version !== recipe.version ||
    metadata.commit !== recipe.commit ||
    !['win32-x64', 'linux-x64', 'darwin-arm64'].includes(metadata.target)
  )
    throw new Error('Runtime does not match the selected recipe: ' + input);
  const archive = join(dirname(input), metadata.archive);
  if ((await stat(archive)).size !== metadata.bytes)
    throw new Error('Incomplete archive: ' + archive);
  const destination = join(directory, 'hermes', recipe.version);
  await mkdir(destination, { recursive: true });
  const name = metadata.target + '.tar.gz';
  await copyFile(archive, join(destination, name));
  await writeFile(
    join(destination, metadata.target + '.json'),
    JSON.stringify({ ...metadata, archive: name }, null, 2) + '\n',
  );
  console.log(metadata.target + ': ' + metadata.bytes + ' bytes staged locally');
}
