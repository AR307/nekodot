import { randomBytes, randomUUID } from 'node:crypto';
import { setTimeout as delay } from 'node:timers/promises';
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
import { ModelCatalog } from './model-catalog';
import { openNativeSession, type NativeSessionSnapshot } from './hermes/session';
import type { Operations } from './operations';
import type { NativeAdmission } from './execution/types';

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
  readonly catalog: ModelCatalog;
  constructor(
    readonly hermes: HermesRuntime,
    readonly database: NodeDatabase,
  ) {
    this.catalog = new ModelCatalog(database);
  }

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
        apiMode: (config.providers?.[entry.id]?.api_mode ?? '') as ProviderSource['apiMode'],
      };
    });
    for (const entry of authorization.providers)
      if (entry.status.logged_in)
        sources.push({
          sourceId: 'oauth:' + entry.id,
          kind: 'oauth',
          name: entry.name,
          // Claude Code is an account card; Hermes executes it through Anthropic.
          provider: entry.id === 'claude-code' ? 'anthropic' : entry.id,
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
          api_mode: input.apiMode ?? previous?.apiMode ?? '',
          discover_models: true,
        },
      },
    });
    if (previous) await this.reapply(previous.sourceId);
    return this.source('custom:' + id);
  }

  /** Profiles hold a copy of their source; a changed source reaches its Bots here, not per run. */
  private async reapply(sourceId: string) {
    for (const bot of this.database.bots())
      if (!bot.archived && bot.sourceId === sourceId) await this.configureBot(bot);
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
    if (input.action === 'poll') {
      if (status.status === 'approved') await this.reapply('oauth:' + input.provider);
      return status;
    }
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

  async describe(input: RpcParams<'models.describe'>) {
    const source = await this.source(input.sourceId);
    return {
      ...(await this.catalog.describe(source.provider, input.model, source.baseUrl, input.refresh)),
      apiMode: source.apiMode,
    };
  }

  test(input: RpcParams<'providers.test'>, operations: Operations) {
    return operations.start('provider-test', [], async (operation) => {
      const source = await this.source(input.sourceId);
      if (source.kind === 'custom') {
        const config = await this.config('default');
        const key = String(config.providers?.[source.provider]?.key_env ?? '');
        const validation = await this.hermes.management.request<{ ok: boolean; message: string }>(
          '/api/providers/custom-endpoints/validate',
          'default',
          {
            method: 'POST',
            body: JSON.stringify({
              name: source.name,
              base_url: source.baseUrl,
              model: input.model,
              api_mode: source.apiMode,
              api_key: (await this.hermes.environment('default'))[key],
            }),
          },
        );
        if (!validation.ok) throw new NodeFault('unavailable', validation.message);
      }
      // A successful /models or route probe is not a successful model call. Test through Hermes, without tools.
      const gateway = this.hermes.gateway('default');
      const session = await gateway.rpc<NativeSessionSnapshot>('session.create', {
        profile: 'default',
        source: 'gui',
        hidden: true,
        request_id: randomUUID(),
        provider: source.provider,
        model: input.model,
        toolsets: [],
        ignore_rules: true,
        max_turns: 1,
        run_budget: 85,
      });
      const admission = await gateway.rpc<NativeAdmission>('prompt.submit', {
        session_id: session.session_id,
        text: 'Reply with OK only. Do not use tools.',
        submission_id: randomUUID(),
        input_id: randomUUID(),
      });
      const deadline = Date.now() + 90_000;
      while (Date.now() < deadline) {
        const receipt = await gateway.rpc<NativeAdmission>('prompt.receipt', {
          session_id: session.session_id,
          admission_id: admission.admission_id,
          include_result: true,
        });
        if (receipt.status === 'terminal') {
          if (
            receipt.outcome !== 'completed' ||
            receipt.result?.failed ||
            !receipt.result?.final_response?.trim()
          )
            throw new NodeFault(
              'unavailable',
              receipt.result?.final_response || String(receipt.outcome),
            );
          operation.detail = 'Connection test passed';
          const actual = await gateway.rpc<NativeSessionSnapshot>('session.resume', {
            session_id: session.stored_session_id,
            defer_history: true,
            omit_messages: true,
          });
          operation.results = [
            {
              botId: 'default',
              ok: true,
              detail: 'Connection test passed',
              native: {
                sourceId: source.sourceId,
                model: input.model,
                sessionId: session.stored_session_id,
                provider: actual.info?.provider,
                actualModel: actual.info?.model,
                apiMode: actual.info?.api_mode ?? '',
              },
            },
          ];
          return;
        }
        await delay(500);
      }
      throw new NodeFault('unavailable', 'Connection test timed out');
    });
  }

  private async reasoningSession(botId: string) {
    const bot = this.database.bot(botId);
    if (!bot || bot.archived) throw new NodeFault('not_found', 'Bot not found');
    const dm = this.database.conversations().find((c) => c.kind === 'dm' && c.botId === botId)!;
    const existing = this.database.hermesSession(dm.conversationId);
    // A read-only control must not advance the execution subscriber's replay cursor.
    if (existing)
      return this.hermes.gateway(botId).rpc<NativeSessionSnapshot>('session.resume', {
        session_id: existing.storedSessionId,
        defer_history: true,
        omit_messages: true,
      });
    return openNativeSession(this.database, this.hermes, botId, dm.conversationId);
  }
  private async reasoningInfo(
    snapshot: NativeSessionSnapshot,
  ): Promise<RpcResult<'models.reasoning.get'>> {
    const info = snapshot.info!;
    const source = (await this.list()).sources.find((s) => s.provider === info.provider);
    const metadata = await this.catalog.describe(
      info.provider ?? '',
      info.model ?? '',
      source?.baseUrl,
    );
    const levels = [...metadata.reasoningLevels];
    // Hermes advertises ultra only on its Codex app-server route, not generic Responses.
    if (
      info.provider === 'openai-codex' &&
      info.api_mode === 'codex_app_server' &&
      levels.includes('max') &&
      !levels.includes('ultra')
    )
      levels.push('ultra');
    return {
      sessionId: snapshot.session_id,
      model: info.model ?? '',
      provider: info.provider ?? '',
      apiMode: info.api_mode ?? '',
      effort: info.reasoning_effort || null,
      wireEffort: info.reasoning_effort_wire || null,
      levels,
    };
  }
  async reasoning(botId: string) {
    return this.reasoningInfo(await this.reasoningSession(botId));
  }
  async setReasoning(input: RpcParams<'models.reasoning.set'>) {
    const session = await this.reasoningSession(input.botId);
    if (session.session_id !== input.sessionId)
      throw new NodeFault('conflict', 'The active session changed');
    if (session.running) throw new NodeFault('conflict', 'Wait for the current turn to finish');
    const info = await this.reasoningInfo(session);
    if (input.effort !== null && !info.levels.includes(input.effort))
      throw new NodeFault('invalid_params', 'This model does not list that reasoning level');
    await this.hermes.gateway(input.botId).rpc('session.mutate', {
      session_id: session.session_id,
      request_id: randomUUID(),
      expected_revision: session.revision,
      expected_generation: session.execution_generation,
      operation: 'reasoning',
      payload: { effort: input.effort },
    });
    return this.reasoning(input.botId);
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
