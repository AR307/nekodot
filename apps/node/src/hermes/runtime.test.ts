import { mkdir, mkdtemp, readFile, writeFile } from 'node:fs/promises';
import { createServer } from 'node:http';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { parseEnv } from 'node:util';
import { parse } from 'yaml';
import { expect, it } from 'vitest';
import { ManagedHermes } from './runtime';
import type { Bot } from '@nekodot/protocol';

async function existingProfile(config: string) {
  const directory = await mkdtemp(join(tmpdir(), 'nekodot-native-config-'));
  const home = join(directory, 'hermes');
  await mkdir(home, { recursive: true });
  await writeFile(join(home, 'config.yaml'), config);
  await writeFile(join(home, 'SOUL.md'), 'Learned identity\n');
  await writeFile(
    join(home, '.env'),
    '# >>> nekodot managed >>>\nAPI_SERVER_KEY="existing-native-key"\nNEKODOT_PROVIDER_API_KEY="preserved-provider-key"\n# <<< nekodot managed <<<\nEXTERNAL_KEY="unrelated-key"\n',
  );
  const server = createServer((request, response) => {
    if (
      request.url === '/p/default/health' &&
      request.headers.authorization === 'Bearer existing-native-key'
    ) {
      response.writeHead(200, { 'Content-Type': 'application/json' }).end('{}');
      return;
    }
    response.writeHead(404).end();
  });
  await new Promise<void>((resolve) => server.listen(0, '127.0.0.1', resolve));
  const address = server.address();
  if (!address || typeof address === 'string') throw new Error('Missing health-test address');
  const apiPort = address.port;
  const runtime = new ManagedHermes({ home, runtime: join(directory, 'pm'), apiPort });
  const bot: Bot = {
    botId: 'default',
    displayName: 'Updated name',
    handle: 'updated',
    role: 'Learned identity',
    model: 'native-model',
    avatar: { shape: 'dot', color: '#E8603C' },
    archived: false,
    createdAt: new Date().toISOString(),
  };
  return {
    home,
    runtime,
    bot,
    apiPort,
    close: () =>
      new Promise<void>((resolve, reject) =>
        server.close((error) => (error ? reject(error) : resolve())),
      ),
  };
}

it('profile metadata edits retain all saved native credentials, selected route and learned SOUL', async () => {
  const { home, runtime, bot, apiPort, close } = await existingProfile(
    'model:\n  provider: source-a\n  default: chosen-model\nproviders:\n  source-a:\n    key_env: SOURCE_A_KEY\n',
  );
  try {
    await runtime.configureBot(bot, false, 'smart');
    const env = parseEnv(await readFile(join(home, '.env'), 'utf8'));
    expect(env).toMatchObject({
      API_SERVER_KEY: 'existing-native-key',
      NEKODOT_PROVIDER_API_KEY: 'preserved-provider-key',
      EXTERNAL_KEY: 'unrelated-key',
      API_SERVER_PORT: String(apiPort),
    });
    expect(parse(await readFile(join(home, 'config.yaml'), 'utf8'))).toMatchObject({
      model: { provider: 'source-a', default: 'chosen-model' },
      approvals: { mode: 'smart' },
    });
    expect(await readFile(join(home, 'SOUL.md'), 'utf8')).toContain('Learned identity');
  } finally {
    await runtime.close();
    await close();
  }
});

it('enables the native multiplex gateway without replacing a profile route', async () => {
  const { home, runtime, bot, close } = await existingProfile('gateway: false\n');
  try {
    await runtime.configureBot(bot, false);
    expect(parse(await readFile(join(home, 'config.yaml'), 'utf8'))).toMatchObject({
      gateway: { multiplex_profiles: true },
      platform_toolsets: { api_server: ['hermes-api-server', 'clarify'] },
    });
  } finally {
    await runtime.close();
    await close();
  }
});
