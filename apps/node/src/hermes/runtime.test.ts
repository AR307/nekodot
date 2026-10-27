import { mkdtemp, readFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { parseEnv } from 'node:util';
import { parse } from 'yaml';
import { expect, it } from 'vitest';
import { ManagedHermes } from './runtime';

it('writes one current provider to the private managed env and config before any bot exists', async () => {
  const directory = await mkdtemp(join(tmpdir(), 'nekodot-provider-files-'));
  const home = join(directory, 'hermes');
  const runtime = new ManagedHermes({ home, runtime: join(directory, 'pm') });
  await runtime.configureProvider(
    {
      kind: 'custom',
      baseUrl: 'https://models.example.test/v1',
      apiKey: 'test-custom-key-1234',
      defaultModel: 'chosen-model',
    },
    [],
  );
  const customEnv = parseEnv(await readFile(join(home, '.env'), 'utf8'));
  const raw = await readFile(join(home, 'config.yaml'), 'utf8');
  expect(customEnv.NEKODOT_PROVIDER_API_KEY).toBe('test-custom-key-1234');
  expect(customEnv.API_SERVER_KEY).toHaveLength(64);
  expect(raw).not.toContain('test-custom-key-1234');
  expect(parse(raw)).toMatchObject({
    gateway: { multiplex_profiles: true },
    model: { provider: 'custom', default: 'chosen-model', api_key: '${NEKODOT_PROVIDER_API_KEY}' },
  });
  await runtime.configureProvider(
    { kind: 'openrouter', apiKey: 'test-router-key-5678', defaultModel: 'vendor/chosen-model' },
    [],
  );
  const routerEnv = parseEnv(await readFile(join(home, '.env'), 'utf8'));
  expect(routerEnv.API_SERVER_KEY).toBe(customEnv.API_SERVER_KEY);
  expect(routerEnv.OPENROUTER_API_KEY).toBe('test-router-key-5678');
  expect(routerEnv.NEKODOT_PROVIDER_API_KEY).toBeUndefined();
  expect(parse(await readFile(join(home, 'config.yaml'), 'utf8'))).toMatchObject({
    model: {
      provider: 'openrouter',
      default: 'vendor/chosen-model',
      api_key: '${OPENROUTER_API_KEY}',
      base_url: 'https://openrouter.ai/api/v1',
    },
  });
});
