import { mkdtemp, readFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { expect, it } from 'vitest';
import { startFakeHermes, recordedManagementRuntime } from '@nekodot/fake-hermes';
import { NodeApplication } from './app';
import { HermesApi } from './hermes/api';
import type { HermesRuntime } from './hermes/runtime';

it('two custom APIs survive app restart; each profile keeps its selected route and only its credential', async () => {
  const home = await mkdtemp(join(tmpdir(), 'nekodot-source-journey-'));
  const key = 'test-only-management';
  const fixture = JSON.parse(
    await readFile(join(process.cwd(), 'docs/fixtures/providers-native.json'), 'utf8'),
  ) as { info: { model: string } };
  const fake = await startFakeHermes({
    fixturesDirectory: join(process.cwd(), 'docs/fixtures'),
    profiles: ['default'],
    apiKey: key,
    allowProfileCreate: true,
  });
  const runtime: HermesRuntime = {
    ...recordedManagementRuntime(fake.url, key, home, fake.pluginCatalog),
    start: async () => {},
    close: async () => {},
    approvalMode: async () => 'manual',
    configureBot: async () => {},
    api: async (profile) => new HermesApi(fake.url + '/p/' + profile, key),
  };
  let app = new NodeApplication(home, runtime);
  try {
    const sources = await Promise.all(
      ['Research', 'Writing'].map((name, i) =>
        app.providers.set({
          kind: 'custom',
          name,
          baseUrl: `https://source-${i}.example.test/v1`,
          apiKey: 'test-only-source-' + i,
        }),
      ),
    );
    expect(new Set(sources.map((source) => source.sourceId)).size).toBe(2);
    expect((await app.providers.list()).oauth.length).toBeGreaterThan(1);
    const bots = [];
    for (const [i, source] of sources.entries()) {
      const created = await app.bots.create({
        sourceId: source.sourceId,
        displayName: source.name,
        handle: 'source-' + i,
        role: 'Test specialist',
        model: fixture.info.model,
        avatar: { shape: 'dot', color: '#E8603C' },
        modelSettings: { contextLength: i === 0 ? 64000 : null },
      });
      bots.push(created.bot);
      const config = await runtime.management.request<{
        model: { provider: string };
        providers: Record<string, { key_env: string }>;
      }>('/api/config', created.bot.botId);
      expect(config.model.provider).toBe(source.provider);
      const env = await runtime.environment(created.bot.botId);
      expect(Object.values(env)).toEqual(['test-only-source-' + i]);
      expect(Object.keys(config.providers)).toEqual([source.provider]);
      expect(
        (await app.providers.models({ sourceId: source.sourceId })).models.length,
      ).toBeGreaterThan(0);
    }
    const first = bots[0]!;
    const source = sources[0]!;
    expect(await app.providers.info(first.botId)).toMatchObject({
      configuredContext: 64000,
      detectedMaxOutput: null,
    });
    expect((await app.providers.info(first.botId)).compression.count).toBeNull();
    await runtime.management.request('/api/test/compression', first.botId, {
      method: 'POST',
      body: '{}',
    });
    expect((await app.providers.info(first.botId)).compression).toMatchObject({
      count: 1,
      effectiveThresholdTokens: 54400,
    });
    expect((await app.providers.info(bots[1]!.botId)).compression.count).toBeNull();
    await app.providers.set({
      kind: 'custom',
      sourceId: source.sourceId,
      name: 'Research renamed',
      baseUrl: source.baseUrl!,
    });
    expect((await app.providers.list()).sources).toHaveLength(2);
    await app.providers.set({
      kind: 'custom',
      sourceId: source.sourceId,
      name: 'Research renamed',
      baseUrl: source.baseUrl!,
      apiKey: 'rotated-test-only',
    });
    expect(Object.values(await runtime.environment(first.botId))).toEqual(['test-only-source-0']);
    await app.providers.configureBot(first);
    expect(Object.values(await runtime.environment(first.botId))).toEqual(['rotated-test-only']);
    expect(Object.values(await runtime.environment(bots[1]!.botId))).toEqual([
      'test-only-source-1',
    ]);
    await app.bots.update({ botId: first.botId, modelSettings: { contextLength: null } });
    expect(await app.providers.info(first.botId)).toMatchObject({
      configuredContext: null,
      effectiveContext: 1050000,
    });
    expect(app.database.setting('provider')).toBeUndefined();
    expect(JSON.stringify(await app.providers.list())).not.toContain('rotated-test-only');
    await app.close();
    app = new NodeApplication(home, runtime);
    expect(app.database.bot(first.botId)?.sourceId).toBe(source.sourceId);
    expect((await app.providers.list()).sources).toHaveLength(2);
    expect((await app.providers.info(first.botId)).effectiveContext).toBe(1050000);
    await expect(app.providers.models({ sourceId: 'custom:not-present' })).rejects.toThrow(
      'no longer available',
    );
    const authorization = await app.providers.authorize({
      provider: 'openai-codex',
      action: 'start',
    });
    const pending = await app.providers.authorize({
      provider: 'openai-codex',
      action: 'poll',
      sessionId: String(authorization.session_id),
    });
    expect(pending.status).toBe('pending');
    const approved = await app.providers.authorize({
      provider: 'openai-codex',
      action: 'poll',
      sessionId: String(authorization.session_id),
    });
    expect(approved.status).toBe('approved');
    expect((await app.providers.list()).sources.map((source) => source.kind)).toEqual([
      'custom',
      'custom',
      'oauth',
    ]);
    expect(
      (await app.providers.models({ sourceId: 'oauth:openai-codex' })).models.length,
    ).toBeGreaterThan(0);
    const oauthBot = await app.bots.create({
      sourceId: 'oauth:openai-codex',
      displayName: 'Quartz',
      handle: 'quartz',
      role: 'Test specialist',
      model: 'gpt-6.1-sol',
      avatar: { shape: 'dot', color: '#E8603C' },
    });
    expect(await app.providers.info(oauthBot.bot.botId)).toMatchObject({
      detectedContext: 272000,
      detectedMaxOutput: 128000,
    });
    expect(await runtime.environment(oauthBot.bot.botId)).toEqual({});
    expect(Object.values(await runtime.environment(bots[1]!.botId))).toEqual([
      'test-only-source-1',
    ]);
  } finally {
    await app.close();
    runtime.management.close();
    await fake.close();
  }
});
