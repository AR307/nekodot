import { createHash, createPrivateKey, createPublicKey, sign } from 'node:crypto';
import { readFile, writeFile } from 'node:fs/promises';

const keyFile = process.env.NEKODOT_RELEASE_KEY_FILE;
if (!keyFile) throw new Error('Set NEKODOT_RELEASE_KEY_FILE to your private Ed25519 PEM file.');
const key = createPrivateKey(await readFile(keyFile));
if (key.asymmetricKeyType !== 'ed25519') throw new Error('An Ed25519 release key is required.');
const version = process.argv[2] ?? new Date().toISOString().replace(/\D/g, '').slice(0, 14);
if (!/^\d{14}$/.test(version)) throw new Error('Use a 14-digit UTC release version.');
const path = 'dist/distribution/nekodot-node.cjs';
const source = await readFile(path, 'utf8');
if (!source.includes('__NEKODOT_NODE_VERSION__') || !source.includes('__NEKODOT_RELEASE_KEY__'))
  throw new Error(
    'Build an unstamped distribution before releasing. Both placeholders are required.',
  );
const publicKey = createPublicKey(key).export({ type: 'spki', format: 'der' }).toString('base64');
const bundle = source
  .replaceAll('__NEKODOT_NODE_VERSION__', version)
  .replaceAll('__NEKODOT_RELEASE_KEY__', publicKey);
const sha256 = createHash('sha256').update(bundle).digest('hex');
const signature = sign(null, Buffer.from(`nekodot-node:${version}:${sha256}`), key).toString(
  'base64',
);
await writeFile(path, bundle);
await writeFile(
  'dist/distribution/nekodot-node.json',
  JSON.stringify({ version, sha256, signature }, null, 2) + '\n',
);
console.log(
  `Signed Node release ${version}. Keep the private key outside the repository and server.`,
);
