import { mkdir, writeFile, chmod } from 'node:fs/promises';
import { join } from 'node:path';
import { hostname, platform } from 'node:os';
import type { NodeCredentials } from './connection';
import { pairResponseSchema } from '@nekodot/protocol';

export async function pairNode(home: string, relayUrl: string, code: string, name = hostname()) {
  const response = await fetch(relayUrl.replace(/\/$/, '') + '/api/pair', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ code, nodeName: name, platform: platform() }),
    signal: AbortSignal.timeout(30000),
  });
  if (!response.ok)
    throw new Error(
      'Pairing failed (' + response.status + '); generate a new code in the web app.',
    );
  const value = pairResponseSchema.parse(await response.json());
  const credentials: NodeCredentials = { relayUrl: relayUrl.replace(/\/$/, ''), ...value };
  await mkdir(home, { recursive: true, mode: 0o700 });
  const path = join(home, 'node.json');
  await writeFile(path, JSON.stringify(credentials, null, 2) + '\n', { mode: 0o600 });
  await chmod(path, 0o600);
  return credentials;
}
