import { readFile } from 'node:fs/promises';
import { join } from 'node:path';
import { randomUUID } from 'node:crypto';

/** Offline management replay, seeded only from the isolated native source journey. */
export async function providerReplay(directory: string, modelOptions?: unknown) {
  const fixture = JSON.parse(await readFile(join(directory, 'providers-native.json'), 'utf8')) as {
    oauth: { providers: Record<string, unknown>[] };
    options: { providers: { models: string[] }[] };
    info: Record<string, unknown>;
    compressionLogs: { lines: string[] };
    initializationLogs: { lines: string[] };
    config: Record<string, unknown>;
  };
  const configs = new Map<string, Record<string, unknown>>();
  const environments = new Map<string, Record<string, string>>();
  const authorization = JSON.parse(
    await readFile(join(directory, 'oauth-codex-native.json'), 'utf8'),
  ) as {
    start: Record<string, unknown>;
    polls: { status: string; [key: string]: unknown }[];
    options: { models: string[] };
    info: Record<string, unknown>;
  };
  const oauth = structuredClone(fixture.oauth);
  const authorizations = new Map<string, number>();
  const compressed = new Set<string>();
  const config = (profile: string) => {
    if (!configs.has(profile)) configs.set(profile, { providers: {} });
    return configs.get(profile)!;
  };
  const environment = (profile: string) => {
    if (!environments.has(profile)) environments.set(profile, {});
    return environments.get(profile)!;
  };
  const merge = (target: Record<string, unknown>, incoming: Record<string, unknown>) => {
    for (const [key, value] of Object.entries(incoming)) {
      if (value && typeof value === 'object' && !Array.isArray(value)) {
        const current = target[key];
        target[key] = merge(
          current && typeof current === 'object' ? (current as Record<string, unknown>) : {},
          value as Record<string, unknown>,
        );
      } else target[key] = value;
    }
    return target;
  };
  function request(
    url: URL,
    method: string,
    profile: string,
    body: Record<string, unknown>,
  ): unknown {
    const state = config(profile);
    const providers = state.providers as Record<string, Record<string, unknown>>;
    if (url.pathname === '/api/test/environment') return environment(profile);
    if (url.pathname === '/api/test/compression' && method === 'POST') {
      compressed.add(profile);
      return { ok: true };
    }
    if (url.pathname === '/api/config') {
      if (method === 'PUT') {
        merge(state, body.config as Record<string, unknown>);
        return { ok: true };
      }
      return url.searchParams.get('include_defaults') === 'true'
        ? merge(structuredClone(fixture.config), state)
        : state;
    }
    if (url.pathname === '/api/env') {
      environment(profile)[String(body.key)] = String(body.value);
      return { ok: true };
    }
    if (url.pathname === '/api/providers/oauth') return oauth;
    if (url.pathname === '/api/providers/oauth/openai-codex/start' && method === 'POST') {
      const sessionId = 'test-only-' + randomUUID();
      authorizations.set(sessionId, 0);
      return {
        ...authorization.start,
        session_id: sessionId,
        user_code: 'TEST-ONLY',
        verification_url: 'https://authorization.example.test/device',
      };
    }
    if (url.pathname.startsWith('/api/providers/oauth/openai-codex/poll/')) {
      const sessionId = url.pathname.split('/').at(-1)!;
      const index = authorizations.get(sessionId);
      if (index === undefined) return { status: 'error', error_message: 'Unknown test session' };
      const result = authorization.polls[Math.min(index, authorization.polls.length - 1)]!;
      authorizations.set(sessionId, index + 1);
      if (result.status === 'approved') {
        const service = oauth.providers.find((entry) => entry.id === 'openai-codex')!;
        service.status = { ...(service.status as Record<string, unknown>), logged_in: true };
      }
      return { ...result, session_id: sessionId };
    }
    if (url.pathname === '/api/providers/custom-endpoints')
      return {
        endpoints: Object.entries(providers).map(([id, entry]) => ({
          id,
          name: entry.name,
          base_url: entry.base_url,
          has_api_key: Boolean(environment(profile)[String(entry.key_env)]),
        })),
        current: {},
      };
    if (url.pathname === '/api/model/options') {
      const models =
        (modelOptions as typeof fixture.options | undefined)?.providers[0]?.models ??
        fixture.options.providers[0]!.models;
      return {
        provider: (state.model as { provider?: string } | undefined)?.provider ?? '',
        providers: [
          ...Object.keys(providers).map((slug) => ({ slug, models, is_current: false })),
          ...oauth.providers
            .filter((entry) => (entry.status as { logged_in: boolean }).logged_in)
            .map((entry) => ({
              slug: entry.id,
              models: authorization.options.models,
              is_current: false,
            })),
        ],
      };
    }
    if (url.pathname === '/api/model/set') {
      merge(state, { model: { default: body.model, provider: body.provider } });
      return { ok: true, scope: body.scope };
    }
    if (url.pathname === '/api/model/info') {
      const model = state.model as
        { provider?: string; default?: string; context_length?: number } | undefined;
      const info = model?.provider === 'openai-codex' ? authorization.info : fixture.info;
      return {
        ...info,
        model: model?.default ?? '',
        provider: model?.provider ?? '',
        config_context_length: model?.context_length ?? 0,
        effective_context_length: model?.context_length ?? info.auto_context_length,
      };
    }
    if (url.pathname === '/api/logs' && url.searchParams.get('search')?.startsWith('Compression'))
      return compressed.has(profile) ? fixture.compressionLogs : { lines: [] };
    if (
      url.pathname === '/api/logs' &&
      url.searchParams.get('search')?.startsWith('context compression')
    )
      return compressed.has(profile) ? fixture.compressionLogs : { lines: [] };
    if (
      url.pathname === '/api/logs' &&
      url.searchParams.get('search')?.startsWith('Context compressor')
    )
      return compressed.has(profile) ? fixture.initializationLogs : { lines: [] };
    return undefined;
  }
  return { request };
}
