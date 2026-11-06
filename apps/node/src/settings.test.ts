import { mkdtemp } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { expect, it } from 'vitest';
import { startFakeHermes, recordedManagementRuntime } from '@nekodot/fake-hermes';
import { rpcRequestSchema } from '@nekodot/protocol';
import { NodeApplication } from './app';
import type { HermesRuntime } from './hermes/runtime';

it('keeps Bot settings on one profile and shared settings on every profile', async () => {
  const home = await mkdtemp(join(tmpdir(), 'nekodot-hermes-settings-'));
  const key = 'test-only-management';
  const fake = await startFakeHermes({
    fixturesDirectory: join(process.cwd(), 'tests/fixtures'),
    profiles: ['default'],
    apiKey: key,
    allowProfileCreate: true,
  });
  const runtime: HermesRuntime = {
    ...recordedManagementRuntime(fake.url, key, home, fake.pluginCatalog),
    start: async () => {},
    close: async () => {},
    approvalMode: async () => 'manual',
    syncRules: async () => {},
    configureBot: async () => {},
  };
  const nativeRequest = runtime.management.request.bind(runtime.management);
  const schema = {
    category_order: ['general', 'compression', 'agent'],
    fields: {
      'compression.enabled': {
        type: 'boolean',
        description: 'Enable native context compression',
        category: 'compression',
      },
      'agent.api_key': {
        type: 'string',
        description: 'Sensitive value',
        category: 'agent',
      },
      model: {
        type: 'string',
        description: 'Default model',
        category: 'general',
      },
      model_context_length: {
        type: 'number',
        description: 'Context window override',
        category: 'general',
      },
      timezone: {
        type: 'select',
        description: 'Timezone',
        category: 'general',
        options: ['UTC', 'Asia/Shanghai'],
      },
      'proxy.enabled': {
        type: 'boolean',
        description: 'Use a proxy',
        category: 'network',
      },
      'logging.level': {
        type: 'select',
        description: 'Log level',
        category: 'logging',
        options: ['INFO', 'DEBUG'],
      },
    },
  };
  runtime.management.request = async <T>(path: string, profile?: string, init?: RequestInit) =>
    path === '/api/config/schema' ? (schema as T) : nativeRequest<T>(path, profile, init);
  const app = new NodeApplication(home, runtime);
  try {
    const source = await app.providers.set({
      kind: 'custom',
      name: 'Settings fixture',
      baseUrl: 'https://settings.example.test/v1',
      apiKey: 'test-only-settings-key',
    });
    const createBot = (displayName: string, handle: string) =>
      app.bots.create({
        sourceId: source.sourceId,
        displayName,
        handle,
        role: 'Profile settings test',
        model: 'test-model',
        avatar: { shape: 'dot', color: '#E8603C' },
      });
    const first = await createBot('Settings A', 'settings-a');
    const second = await createBot('Settings B', 'settings-b');
    const request = (method: string, params: unknown) => rpcRequestSchema.parse({ method, params });

    await runtime.management.request('/api/config', first.bot.botId, {
      method: 'PUT',
      body: JSON.stringify({ config: { agent: { api_key: 'never-return-this' } } }),
    });
    const firstSettings = (await app.handle(
      request('hermes.settings.get', { botId: first.bot.botId }),
    )) as {
      fields: {
        key: string;
        value: unknown;
        sensitive: boolean;
        editable: boolean;
        configured: boolean;
      }[];
    };
    expect(firstSettings.fields).toContainEqual({
      key: 'agent.api_key',
      type: 'string',
      description: 'Sensitive value',
      category: 'agent',
      group: 'run',
      value: null,
      sensitive: true,
      editable: false,
      configured: true,
    });
    expect(firstSettings.fields.find((field) => field.key === 'model')?.editable).toBe(false);
    expect(
      firstSettings.fields.find((field) => field.key === 'model_context_length')?.editable,
    ).toBe(false);

    await app.handle(
      request('hermes.settings.set', {
        botId: first.bot.botId,
        key: 'compression.enabled',
        value: false,
      }),
    );
    const firstConfig = await runtime.management.request<Record<string, unknown>>(
      '/api/config?include_defaults=true',
      first.bot.botId,
    );
    const secondConfig = await runtime.management.request<Record<string, unknown>>(
      '/api/config?include_defaults=true',
      second.bot.botId,
    );
    expect((firstConfig.compression as Record<string, unknown>).enabled).toBe(false);
    expect((secondConfig.compression as Record<string, unknown>).enabled).toBe(true);
    await expect(
      app.handle(
        request('hermes.settings.set', {
          botId: first.bot.botId,
          key: 'agent.api_key',
          value: 'must-not-be-writable-here',
        }),
      ),
    ).rejects.toThrow('Manage credentials in Hermes provider settings');
    await expect(
      app.handle(
        request('hermes.settings.set', {
          botId: first.bot.botId,
          key: 'not.a.hermes.setting',
          value: true,
        }),
      ),
    ).rejects.toThrow('Hermes setting is not available');
    await expect(
      app.handle(
        request('hermes.settings.set', {
          botId: first.bot.botId,
          key: 'model',
          value: 'a-different-model',
        }),
      ),
    ).rejects.toThrow('Manage model settings in the Bot editor');

    // Installation settings leave the Bot page and are written to every profile at once.
    expect(firstSettings.fields.map((field) => field.key)).not.toContain('timezone');
    await expect(
      app.handle(
        request('hermes.settings.set', {
          botId: first.bot.botId,
          key: 'timezone',
          value: 'Asia/Shanghai',
        }),
      ),
    ).rejects.toThrow('change it in app settings');
    // Settings nekodot does not use are hidden and refused, whatever the Bot.
    expect(firstSettings.fields.map((field) => field.key)).not.toContain('logging.level');
    await expect(
      app.handle(request('hermes.shared.set', { key: 'logging.level', value: 'DEBUG' })),
    ).rejects.toThrow('not available');
    const shared = (await app.handle(request('hermes.shared.get', {}))) as {
      fields: { key: string; group: string }[];
    };
    expect(shared.fields.map((field) => [field.key, field.group])).toEqual([
      ['timezone', 'general'],
      ['proxy.enabled', 'network'],
    ]);
    await expect(
      app.handle(request('hermes.shared.set', { key: 'compression.enabled', value: false })),
    ).rejects.toThrow('change it on that Bot');
    await expect(
      app.handle(request('hermes.shared.set', { key: 'timezone', value: 'Mars/Base' })),
    ).rejects.toThrow('Value does not match the Hermes setting');
    expect(
      await app.handle(request('hermes.shared.set', { key: 'timezone', value: 'Asia/Shanghai' })),
    ).toEqual({ key: 'timezone', saved: true, profiles: 3 });
    const level = async (profile: string) =>
      (
        await runtime.management.request<Record<string, unknown>>(
          '/api/config?include_defaults=true',
          profile,
        )
      ).timezone;
    expect([
      await level('default'),
      await level(first.bot.botId),
      await level(second.bot.botId),
    ]).toEqual(['Asia/Shanghai', 'Asia/Shanghai', 'Asia/Shanghai']);
    const third = await createBot('Settings C', 'settings-c');
    expect(await level(third.bot.botId)).toBe('Asia/Shanghai');
  } finally {
    await app.close();
    runtime.management.close();
    await fake.close();
  }
});
