import { mkdir, mkdtemp, readFile, writeFile } from 'node:fs/promises';
import { createServer } from 'node:http';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { parseEnv } from 'node:util';
import { parse } from 'yaml';
import { describe, expect, it, vi } from 'vitest';
import { ManagedHermes, managedRules, withManagedRules } from './runtime';
import type { Bot } from '@nekodot/protocol';
import * as cli from './cli';

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
  // This is the configuration-only test. Native gateway activation is exercised by
  // the real statistics journey with a fresh profile, not by this health server.
  const reloaded = vi.spyOn(runtime.gateway('default'), 'reloadPlugins').mockResolvedValue();
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
    reloaded,
    close: () =>
      new Promise<void>((resolve, reject) =>
        server.close((error) => (error ? reject(error) : resolve())),
      ),
  };
}

it('profile metadata edits retain all saved native credentials, selected route and learned SOUL', async () => {
  const { home, runtime, bot, apiPort, close, reloaded } = await existingProfile(
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
    expect(reloaded).toHaveBeenCalledOnce();
    await runtime.configureBot(bot, false, 'smart');
    expect(reloaded).toHaveBeenCalledOnce();
  } finally {
    await runtime.close();
    await close();
  }
});

it.each(['null', '{}'])(
  'enables the native gateway with an empty secrets section (%s)',
  async (secrets) => {
    const { home, runtime, bot, close } = await existingProfile(
      `gateway: false\nsecrets: ${secrets}\n`,
    );
    try {
      await runtime.configureBot(bot, false);
      expect(parse(await readFile(join(home, 'config.yaml'), 'utf8'))).toMatchObject({
        gateway: { multiplex_profiles: true },
        platform_toolsets: { api_server: ['hermes-api-server', 'clarify', 'nekodot-secrets'] },
      });
    } finally {
      await runtime.close();
      await close();
    }
  },
);

it('keeps disabled approvals as a string for the native YAML reader after profile edits', async () => {
  const { home, runtime, bot, close } = await existingProfile('approvals:\n  mode: off\n');
  try {
    await runtime.configureBot(bot, false);
    expect(
      parse(await readFile(join(home, 'config.yaml'), 'utf8'), { version: '1.1' }),
    ).toMatchObject({
      approvals: { mode: 'off' },
    });
    await runtime.configureBot(bot, false, 'manual');
    await runtime.configureBot(bot, false, 'off');
    expect(
      parse(await readFile(join(home, 'config.yaml'), 'utf8'), { version: '1.1' }),
    ).toMatchObject({
      approvals: { mode: 'off' },
    });
  } finally {
    await runtime.close();
    await close();
  }
});

it.each([undefined, '', 'high', 'none', false])(
  'uses xhigh only for unset profile reasoning (%s)',
  async (effort) => {
    const { home, runtime, bot, close } = await existingProfile(
      effort === undefined ? '{}' : `agent:\n  reasoning_effort: ${JSON.stringify(effort)}\n`,
    );
    try {
      await runtime.configureBot(bot, false);
      const config = parse(await readFile(join(home, 'config.yaml'), 'utf8'));
      expect(config.agent.reasoning_effort).toBe(
        effort === undefined || effort === '' ? 'xhigh' : effort,
      );
    } finally {
      await runtime.close();
      await close();
    }
  },
);

it('reports the same approval mode as the native boolean normalizer', async () => {
  const { runtime, close } = await existingProfile('{}');
  const read = vi.spyOn(cli, 'runHermesCli');
  try {
    for (const [native, expected] of [
      [false, 'off'],
      [true, 'manual'],
      ['smart', 'smart'],
    ] as const) {
      read.mockResolvedValueOnce(JSON.stringify(native));
      expect(await runtime.approvalMode('default')).toBe(expected);
    }
  } finally {
    read.mockRestore();
    await runtime.close();
    await close();
  }
});

describe('nekodot managed SOUL rules', () => {
  const bot = { displayName: '笔笔', handle: 'bibi' } as Bot;
  it('leaves execution progress to the native task display', () => {
    expect(managedRules(bot)).toContain('Do not narrate internal delegation');
    expect(managedRules(bot)).toContain('real task status separately');
  });
  it('replaces only the managed block and keeps what the user wrote', () => {
    const soul = `My own notes.\n\n${managedRules({ ...bot, handle: 'old' } as Bot)}`;
    const next = withManagedRules(soul, managedRules(bot));
    expect(next.startsWith('My own notes.')).toBe(true);
    expect(next.split('<!-- nekodot managed:').length).toBe(2);
    expect(next).toContain('@bibi');
  });
  it('appends the block to a SOUL.md that has none', () => {
    expect(withManagedRules('Plain soul.\n', managedRules(bot))).toMatch(
      /^Plain soul\.\n\n<!-- nekodot managed:/,
    );
  });
});
