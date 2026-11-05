import { randomBytes } from 'node:crypto';
import {
  hermesModelOptionsSchema,
  type Bot,
  type ProviderSource,
  type RpcParams,
  type RpcResult,
} from '@nekodot/protocol';
import type { NodeDatabase } from './database';
import type { HermesRuntime } from './hermes/runtime';
import { NodeFault } from './fault';

interface NativeEndpoint {
  id: string;
  name: string;
  base_url: string;
  has_api_key: boolean;
}
interface NativeAuthorization {
  id: string;
  name: string;
  status: { logged_in: boolean };
  [key: string]: unknown;
}
interface NativeConfig {
  providers?: Record<string, Record<string, unknown>>;
  model?: { context_length?: number | null };
  compression?: { enabled?: boolean; threshold?: number; threshold_tokens?: number | null };
  [key: string]: unknown;
}
/** Owns source selection only. Credentials, grants, discovery and execution belong to Hermes. */
export class Providers {
  constructor(
    readonly hermes: HermesRuntime,
    readonly database: NodeDatabase,
  ) {}

  async list(): Promise<RpcResult<'providers.list'>> {
    const [custom, authorization, config, env] = await Promise.all([
      this.hermes.management.request<{ endpoints: NativeEndpoint[] }>(
        '/api/providers/custom-endpoints',
        'default',
      ),
      this.hermes.management.request<{ providers: NativeAuthorization[] }>(
        '/api/providers/oauth',
        'default',
      ),
      this.config('default'),
      this.hermes.environment('default'),
    ]);
    const sources: ProviderSource[] = custom.endpoints.map((entry) => {
      const key = String(config.providers?.[entry.id]?.key_env ?? '');
      const secret = env[key];
      return {
        sourceId: 'custom:' + entry.id,
        kind: 'custom',
        name: entry.name,
        provider: entry.id,
        baseUrl: entry.base_url,
        ...(secret ? { apiKeyLast4: secret.slice(-4) } : {}),
        ready: entry.has_api_key,
      };
    });
    for (const entry of authorization.providers)
      if (entry.status.logged_in)
        sources.push({
          sourceId: 'oauth:' + entry.id,
          kind: 'oauth',
          name: entry.name,
          provider: entry.id,
          ready: true,
        });
    // The native catalog includes status previews but never grants/refresh tokens.
    return { sources, oauth: authorization.providers as RpcResult<'providers.list'>['oauth'] };
  }

  private config(profile: string, defaults = false) {
    return this.hermes.management.request<NativeConfig>(
      '/api/config?include_defaults=' + defaults,
      profile,
    );
  }
  private saveConfig(profile: string, config: Record<string, unknown>) {
    return this.hermes.management.request('/api/config', profile, {
      method: 'PUT',
      body: JSON.stringify({ config }),
    });
  }
  private saveSecret(profile: string, key: string, value: string) {
    return this.hermes.management.request('/api/env', profile, {
      method: 'PUT',
      body: JSON.stringify({ key, value }),
    });
  }
  async source(sourceId: string) {
    const source = (await this.list()).sources.find((entry) => entry.sourceId === sourceId);
    if (!source) throw new NodeFault('not_found', 'Model source is no longer available');
    if (!source.ready) throw new NodeFault('invalid_params', 'Configure this source first');
    return source;
  }

  async set(input: RpcParams<'providers.set'>): Promise<ProviderSource> {
    const previous = input.sourceId
      ? (await this.list()).sources.find((source) => source.sourceId === input.sourceId)
      : undefined;
    if (input.sourceId && !previous) throw new NodeFault('not_found', 'Custom source not found');
    if (previous && previous.kind !== 'custom')
      throw new NodeFault('invalid_params', 'This is not a custom API source');
    const id = previous?.provider ?? 'nkapi-' + randomBytes(5).toString('hex');
    const config = await this.config('default');
    const key = String(
      config.providers?.[id]?.key_env ?? 'NEKODOT_SOURCE_' + id.replaceAll('-', '_').toUpperCase(),
    );
    if (!input.apiKey && !(await this.hermes.environment('default'))[key])
      throw new NodeFault('invalid_params', 'Enter an API key for this source');
    if (input.apiKey) await this.saveSecret('default', key, input.apiKey);
    await this.saveConfig('default', {
      providers: {
        [id]: {
          name: input.name,
          base_url: input.baseUrl,
          key_env: key,
          api_mode: 'chat_completions',
          discover_models: true,
        },
      },
    });
    return this.source('custom:' + id);
  }

  async authorize(
    input: RpcParams<'providers.authorize'>,
  ): Promise<RpcResult<'providers.authorize'>> {
    const catalog = (await this.list()).oauth;
    if (!catalog.some((entry) => entry.id === input.provider))
      throw new NodeFault('not_found', 'Authorization service is not in the Hermes catalog');
    const base = '/api/providers/oauth/';
    const provider = encodeURIComponent(input.provider);
    if (input.action === 'start')
      return this.hermes.management.request(base + provider + '/start', 'default', {
        method: 'POST',
        body: '{}',
      });
    if (input.action === 'disconnect')
      return this.hermes.management.request(base + provider, 'default', { method: 'DELETE' });
    if (!input.sessionId)
      throw new NodeFault('invalid_params', 'Authorization session is required');
    const session = encodeURIComponent(input.sessionId);
    // Check the native provider/profile binding before cancelling a session as well.
    const status = await this.hermes.management.request<RpcResult<'providers.authorize'>>(
      base + provider + '/poll/' + session,
      'default',
    );
    if (input.action === 'poll') return status;
    return this.hermes.management.request(base + 'sessions/' + session, 'default', {
      method: 'DELETE',
    });
  }

  async models(input: RpcParams<'models.options'>): Promise<RpcResult<'models.options'>> {
    const source = await this.source(input.sourceId);
    const options = hermesModelOptionsSchema.parse(
      await this.hermes.management.request(
        '/api/model/options?include_unconfigured=false&refresh=' + Boolean(input.refresh),
        'default',
      ),
    );
    const row = options.providers.find((entry) => entry.slug === source.provider);
    return {
      models: [...new Set(row?.models ?? [])],
      ...(row?.warning ? { warning: row.warning } : {}),
    };
  }

  private async prepareSource(profile: string, sourceId: string) {
    const source = await this.source(sourceId);
    if (source.kind === 'custom') {
      const id = source.provider;
      const entry = (await this.config('default')).providers?.[id];
      const key = String(entry?.key_env ?? '');
      const secret = (await this.hermes.environment('default'))[key];
      if (!entry || !secret)
        throw new NodeFault('invalid_params', 'Custom source has no saved credential');
      await this.saveSecret(profile, key, secret);
      await this.saveConfig(profile, { providers: { [id]: entry } });
    }
    // OAuth grants stay in the project root. Hermes inherits and rotates the original grant;
    // copying auth.json into profiles would invalidate single-use refresh tokens.
    return source;
  }

  async assign(input: RpcParams<'models.assign'>): Promise<RpcResult<'models.assign'>> {
    const bot = this.database.bot(input.botId);
    if (!bot || bot.archived) throw new NodeFault('not_found', 'Bot not found');
    const schema = await this.hermes.management.request<{
      fields: Record<string, { type: string }>;
    }>('/api/config/schema', input.botId);
    if (
      !/^(auxiliary\.[^.]+|delegation|cron)\.model$/.test(input.key) ||
      schema.fields[input.key]?.type !== 'string'
    )
      throw new NodeFault('invalid_params', 'This model slot is not editable');
    const source = await this.prepareSource(input.botId, input.sourceId);
    const entry = (await this.config(input.botId)).providers?.[source.provider];
    const endpoint =
      source.kind === 'custom'
        ? {
            base_url: source.baseUrl,
            api_key: (await this.hermes.environment(input.botId))[String(entry?.key_env)],
          }
        : {};
    if (input.key.startsWith('auxiliary.')) {
      await this.hermes.management.request('/api/model/set', input.botId, {
        method: 'POST',
        body: JSON.stringify({
          scope: 'auxiliary',
          task: input.key.split('.')[1],
          provider: source.provider,
          model: input.model,
          ...endpoint,
        }),
      });
    } else if (input.key === 'cron.model') {
      await this.saveConfig(input.botId, {
        cron: { model: input.model, model_provider: source.provider },
      });
    } else {
      await this.saveConfig(input.botId, {
        delegation: {
          provider: source.provider,
          model: input.model,
          base_url: source.baseUrl ?? '',
          api_key: endpoint.api_key ?? '',
        },
      });
    }
    return { saved: true };
  }

  async configureBot(bot: Bot) {
    // Existing profiles keep their native route until the user explicitly selects a source.
    if (!bot.sourceId) return;
    const source = await this.prepareSource(bot.botId, bot.sourceId);
    await this.hermes.management.request('/api/model/set', bot.botId, {
      method: 'POST',
      body: JSON.stringify({
        scope: 'main',
        provider: source.provider,
        model: bot.model,
        confirm_expensive_model: true,
      }),
    });
    if (bot.modelSettings?.contextLength !== undefined)
      await this.saveConfig(bot.botId, {
        model_context_length: bot.modelSettings.contextLength ?? 0,
      });
  }

  async info(botId: string): Promise<RpcResult<'models.info'>> {
    const bot = this.database.bot(botId);
    if (!bot || bot.archived) throw new NodeFault('not_found', 'Bot not found');
    const [info, config, telemetry] = await Promise.all([
      this.hermes.management.request<{
        model: string;
        provider: string;
        auto_context_length: number;
        config_context_length: number;
        effective_context_length: number;
        capabilities: { max_output_tokens?: number };
      }>('/api/model/info', botId),
      this.config(botId, true),
      this.hermes.management.request<{ lines: string[] }>(
        '/api/logs?file=agent&search=context%20compression%20attempt%20telemetry&lines=500',
        botId,
      ),
    ]);
    const positive = (value: number | undefined) => (value && value > 0 ? value : null);
    const records = telemetry.lines.flatMap((line) => {
      const payload = line.match(/context compression attempt telemetry: (\{.*\})/);
      if (!payload) return [];
      const attempt = JSON.parse(payload[1]!) as Record<string, string | number | boolean | null>;
      const fields = [
        'attempt_id',
        'session_id',
        'main_model',
        'main_context_limit',
        'effective_threshold',
        'trigger_source',
        'method',
        'commit_status',
        'tokens_before',
        'tokens_after',
        'messages_before',
        'messages_after',
        'total_duration_ms',
        'split_status',
      ];
      return [
        Object.fromEntries(
          fields.filter((key) => key in attempt).map((key) => [key, attempt[key]!]),
        ),
      ];
    });
    const actualTrigger = records.findLast(
      (record) =>
        record.main_model === info.model &&
        record.main_context_limit === info.effective_context_length,
    )?.effective_threshold;
    return {
      model: info.model,
      provider: info.provider,
      detectedContext: positive(info.auto_context_length),
      configuredContext: positive(info.config_context_length),
      effectiveContext: positive(info.effective_context_length),
      detectedMaxOutput: positive(info.capabilities.max_output_tokens),
      configuredMaxOutput: null,
      contextSource: 'Hermes native resolver (provider metadata/catalog; not a measured limit)',
      outputSource:
        'Hermes native capabilities metadata; no supported output override in this version',
      compression: {
        enabled: config.compression?.enabled ?? true,
        threshold: config.compression?.threshold ?? null,
        thresholdTokens: config.compression?.threshold_tokens ?? null,
        effectiveThresholdTokens: typeof actualTrigger === 'number' ? actualTrigger : null,
        count: records.length
          ? records.filter((record) => record.commit_status === 'committed').length
          : null,
        records,
        note: 'Recent Hermes compression telemetry (up to 500 records), not a lifetime total. No records means unknown, not zero. The effective trigger is the last native measurement for this model/context, not a client estimate.',
      },
    };
  }
}
