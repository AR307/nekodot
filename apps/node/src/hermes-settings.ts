import { z } from 'zod';
import type { RpcParams, RpcResult } from '@nekodot/protocol';
import type { NodeDatabase } from './database';
import type { HermesRuntime } from './hermes/runtime';
import { NodeFault } from './fault';

const sensitiveSettingName =
  /(?:^|[._-])(?:.*(?:api[_-]?key|secret|password|credential|private[_-]?key)|(?:access|refresh|auth)?[_-]?token)$/i;

interface NativeSetting {
  type: string;
  description?: string;
  category?: string;
  options?: unknown[];
  clearable?: boolean;
}
interface NativeSettingsSchema {
  fields: Record<string, NativeSetting>;
  category_order: string[];
}

/**
 * Where a Hermes setting lives in the product, by the first segment of its key. Bot groups are
 * the kinds on a Bot's settings page; shared groups describe the installation and messaging
 * integrations, so they are set once in the app and kept the same on every profile.
 */
const botGroups: Record<string, string[]> = {
  model: [
    'model',
    'model_context_length',
    'fallback_providers',
    'fallback',
    'compression',
    'auxiliary',
    'prompt_caching',
    'moa',
  ],
  tools: [
    'toolsets',
    'terminal',
    'browser',
    'web',
    'vision',
    'code_execution',
    'computer_use',
    'bot_desktop',
    'x_search',
    'delegation',
    'tools',
    'tool_output',
    'lsp',
    'worktrees',
    'mcp',
    'mcp_discovery_timeout',
    'mcp_single_query_discovery_timeout',
    'skills',
    'file_read_max_chars',
    'context_file_max_chars',
    'context_file_read_timeout',
    'prefill_messages_file',
  ],
  memory: ['memory', 'curator', 'sessions', 'session', 'checkpoints', 'context'],
  security: [
    'approvals',
    'security',
    'privacy',
    'tool_loop_guardrails',
    'command_allowlist',
    'hooks_auto_accept',
  ],
  voice: ['tts', 'stt', 'voice', 'wake_word'],
  run: ['agent', 'cron', 'goals', 'loops', 'streaming'],
};
const sharedGroups: Record<string, string[]> = {
  services: [
    'openrouter',
    'bedrock',
    'vertex',
    'nous',
    'model_catalog',
    'models_dev',
    'local_runtime',
  ],
  channels: [
    'discord',
    'telegram',
    'slack',
    'matrix',
    'mattermost',
    'gateway',
    'hosted_rooms',
    'bot_mode',
    'kanban',
  ],
  credentials: ['secrets', 'vault', 'auth'],
  network: ['network', 'proxy'],
  interface: [
    'display',
    'dashboard',
    'human_delay',
    'desktop',
    'webapp',
    'paste_collapse_threshold',
    'paste_collapse_threshold_fallback',
    'paste_collapse_char_threshold',
  ],
  general: [
    'timezone',
    'updates',
    'database',
    'runtime',
    'logging',
    'monitoring',
    'telemetry',
    'doctor',
    'onboarding',
    'plugins',
    'attachments',
    'max_concurrent_sessions',
    'max_live_sessions',
  ],
};
const index = (groups: Record<string, string[]>) =>
  new Map(Object.entries(groups).flatMap(([group, prefixes]) => prefixes.map((p) => [p, group])));
const botGroup = index(botGroups);
const sharedGroup = index(sharedGroups);
const prefix = (key: string) => key.split('.')[0]!;
const isShared = (key: string) => sharedGroup.has(prefix(key));
/**
 * Hermes settings this product does not use: messaging channels it does not run, the terminal and
 * desktop presentation, Hermes's own updates and diagnostics, and features outside nekodot. They are
 * hidden from the app and refused on write; Hermes keeps its defaults for them.
 */
const unusedPrefixes = new Set([
  'discord',
  'telegram',
  'slack',
  'matrix',
  'mattermost',
  'gateway',
  'hosted_rooms',
  'bot_mode',
  'kanban',
  'display',
  'dashboard',
  'human_delay',
  'desktop',
  'webapp',
  'paste_collapse_threshold',
  'paste_collapse_threshold_fallback',
  'paste_collapse_char_threshold',
  'updates',
  'doctor',
  'onboarding',
  'telemetry',
  'monitoring',
  'logging',
  'database',
  'runtime',
  'wake_word',
  'goals',
  'loops',
  'x_search',
  'lsp',
  'worktrees',
  'hooks_auto_accept',
  'openrouter',
  'bedrock',
  'vertex',
  'local_runtime',
]);
const isUnused = (key: string) => unusedPrefixes.has(prefix(key));
/** Settings Hermes added after this table was written stay with the Bot until classified. */
const groupOf = (key: string) =>
  sharedGroup.get(prefix(key)) ?? botGroup.get(prefix(key)) ?? 'other';

type Json = z.infer<ReturnType<typeof z.json>>;

const sharedKey = 'hermes.shared';

/** Reads and writes Hermes's own profile settings; Hermes keeps the values. */
export class HermesSettings {
  constructor(
    readonly hermes: HermesRuntime,
    readonly database: NodeDatabase,
  ) {}

  private request<T>(path: string, profile: string, init?: RequestInit) {
    return this.hermes.management.request<T>(path, profile, init);
  }
  private save(profile: string, config: Record<string, unknown>) {
    return this.request('/api/config', profile, {
      method: 'PUT',
      body: JSON.stringify({ config }),
    });
  }
  private profiles() {
    // Archived Bots keep their profile, so they come back with the installation's settings.
    return ['default', ...this.database.allBots().map((bot) => bot.botId)];
  }

  private async fields(profile: string, shared: boolean) {
    const [schema, config] = await Promise.all([
      this.request<NativeSettingsSchema>('/api/config/schema', profile),
      this.request<Record<string, unknown>>('/api/config?include_defaults=true', profile),
    ]);
    const fields = Object.entries(schema.fields)
      .filter(([key]) => isShared(key) === shared && !isUnused(key))
      .map(([key, field]) => {
        const path = key === 'model_context_length' ? [key] : key.split('.');
        const current = path.reduce<unknown>(
          (value, part) =>
            value && typeof value === 'object' && !Array.isArray(value)
              ? (value as Record<string, unknown>)[part]
              : undefined,
          config,
        );
        const sensitive = sensitiveSettingName.test(key);
        const editable = !sensitive && key !== 'model' && key !== 'model_context_length';
        return {
          key,
          type: field.type,
          description: field.description ?? key,
          category: field.category ?? 'general',
          group: groupOf(key),
          ...(field.options
            ? { options: field.options.map((option) => z.json().parse(option)) }
            : {}),
          ...(field.clearable !== undefined ? { clearable: field.clearable } : {}),
          value: z.json().parse(sensitive ? null : (current ?? null)),
          sensitive,
          editable,
          configured: current !== undefined && current !== null && current !== '',
        };
      });
    return { categories: schema.category_order, fields };
  }

  /** The schema entry for a write, after the checks every write shares. */
  private async checked(profile: string, key: string, value: Json) {
    const schema = await this.request<NativeSettingsSchema>('/api/config/schema', profile);
    const field = schema.fields[key];
    if (!field || isUnused(key))
      throw new NodeFault('not_found', 'Hermes setting is not available');
    if (sensitiveSettingName.test(key))
      throw new NodeFault('invalid_params', 'Manage credentials in Hermes provider settings');
    if (key === 'model' || key === 'model_context_length')
      throw new NodeFault('invalid_params', 'Manage model settings in the Bot editor');
    const valid =
      (field.type === 'boolean' && typeof value === 'boolean') ||
      (field.type === 'number' && typeof value === 'number' && Number.isFinite(value)) ||
      (field.type === 'string' && typeof value === 'string') ||
      (field.type === 'select' &&
        ((field.options ?? []).some((option) => option === value) ||
          (field.clearable === true && value === null))) ||
      (field.type === 'list' && Array.isArray(value)) ||
      (field.type === 'object' &&
        typeof value === 'object' &&
        value !== null &&
        !Array.isArray(value));
    if (!valid) throw new NodeFault('invalid_params', 'Value does not match the Hermes setting');
  }

  private bot(botId: string) {
    const bot = this.database.bot(botId);
    if (!bot || bot.archived) throw new NodeFault('not_found', 'Bot not found');
    return bot;
  }

  async get(botId: string): Promise<RpcResult<'hermes.settings.get'>> {
    this.bot(botId);
    return { botId, scope: 'Hermes profile', ...(await this.fields(botId, false)) };
  }

  async set(input: RpcParams<'hermes.settings.set'>) {
    this.bot(input.botId);
    if (isShared(input.key))
      throw new NodeFault(
        'invalid_params',
        'This setting applies to every Bot; change it in app settings',
      );
    await this.checked(input.botId, input.key, input.value);
    await this.save(input.botId, nested(input.key, input.value));
    return { key: input.key, saved: true as const };
  }

  async shared(): Promise<RpcResult<'hermes.shared.get'>> {
    return { scope: 'All Bot profiles', ...(await this.fields('default', true)) };
  }

  async setShared(input: RpcParams<'hermes.shared.set'>) {
    if (!isShared(input.key))
      throw new NodeFault(
        'invalid_params',
        'This setting belongs to one Bot; change it on that Bot',
      );
    await this.checked('default', input.key, input.value);
    const profiles = this.profiles();
    for (const profile of profiles) await this.save(profile, nested(input.key, input.value));
    // Recorded only once every profile has it, so a failed write can simply be repeated.
    this.database.setSetting(sharedKey, {
      ...this.database.setting<Record<string, Json>>(sharedKey),
      [input.key]: input.value,
    });
    return { key: input.key, saved: true as const, profiles: profiles.length };
  }

  /** Gives a new or imported profile the installation's shared settings. */
  async applyShared(botId: string) {
    const values = this.database.setting<Record<string, Json>>(sharedKey) ?? {};
    const config = Object.entries(values).reduce<Record<string, unknown>>(
      (merged, [key, value]) => merge(merged, nested(key, value)),
      {},
    );
    if (Object.keys(config).length) await this.save(botId, config);
  }
}

function nested(key: string, value: Json): Record<string, unknown> {
  return key
    .split('.')
    .toReversed()
    .reduce<unknown>((inner, part) => ({ [part]: inner }), value) as Record<string, unknown>;
}

function merge(into: Record<string, unknown>, from: Record<string, unknown>) {
  for (const [key, value] of Object.entries(from)) {
    const existing = into[key];
    into[key] = isRecord(existing) && isRecord(value) ? merge({ ...existing }, value) : value;
  }
  return into;
}

const isRecord = (value: unknown): value is Record<string, unknown> =>
  typeof value === 'object' && value !== null && !Array.isArray(value);
