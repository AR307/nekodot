import { randomBytes } from 'node:crypto';
import { mkdir, readFile, writeFile, access, chmod } from 'node:fs/promises';
import { join } from 'node:path';
import { parseEnv } from 'node:util';
import { setTimeout as delay } from 'node:timers/promises';
import type { ChildProcess } from 'node:child_process';
import { parseDocument } from 'yaml';
import type { Bot, RpcParams, RpcResult } from '@nekodot/protocol';
import { HermesApi } from './api';
import { runHermesCli, spawnHermesCli, type HermesLaunch } from './cli';

export type ProviderInput = RpcParams<'providers.set'>;
export type ProviderOutput = NonNullable<RpcResult<'providers.get'>>;
export interface HermesRuntime {
  start(): Promise<void>;
  close(): Promise<void>;
  configureProvider(provider: ProviderInput, bots: Bot[]): Promise<void>;
  configureBot(bot: Bot, create: boolean): Promise<void>;
  api(profile: string): Promise<HermesApi>;
  models(): Promise<unknown>;
}
export interface RuntimeOptions {
  home: string;
  source?: string;
  runtime: string;
  onReady?: () => void;
  onLog?: (line: string) => void;
}
const begin = '# >>> nekodot managed >>>';
const end = '# <<< nekodot managed <<<';

export class ManagedHermes implements HermesRuntime {
  private child?: ChildProcess;
  private closing = false;
  private launch: HermesLaunch;
  private secrets = new Set<string>();
  constructor(readonly options: RuntimeOptions) {
    this.launch = options.source
      ? {
          command: 'bash',
          prefixArgs: ['scripts/run-in-hermes-env', 'python', 'hermes'],
          cwd: options.source,
          home: options.home,
          runtimeDir: options.runtime,
        }
      : { command: 'hermes', cwd: options.home, home: options.home, runtimeDir: options.runtime };
  }
  private profileHome(profile: string) {
    return profile === 'default' ? this.options.home : join(this.options.home, 'profiles', profile);
  }
  private async env(profile: string) {
    const path = join(this.profileHome(profile), '.env');
    return await access(path).then(
      () => readFile(path, 'utf8').then(parseEnv),
      () => ({}) as Record<string, string>,
    );
  }
  async api(profile: string) {
    const env = await this.env(profile);
    if (!env.API_SERVER_KEY) throw new Error('Hermes profile has no API key');
    this.secrets.add(env.API_SERVER_KEY);
    return new HermesApi('http://127.0.0.1:18642/p/' + profile, env.API_SERVER_KEY);
  }
  private async writeEnv(profile: string, provider?: ProviderInput) {
    const directory = this.profileHome(profile);
    await mkdir(directory, { recursive: true, mode: 0o700 });
    const path = join(directory, '.env');
    const old = await access(path).then(
      () => readFile(path, 'utf8'),
      () => '',
    );
    const current = parseEnv(old);
    const apiKey = current.API_SERVER_KEY ?? randomBytes(32).toString('hex');
    this.secrets.add(apiKey);
    const values: Record<string, string> = {
      API_SERVER_KEY: apiKey,
      API_SERVER_ENABLED: 'true',
      API_SERVER_HOST: '127.0.0.1',
      API_SERVER_PORT: '18642',
      ...(current.NEKODOT_PROVIDER_API_KEY
        ? { NEKODOT_PROVIDER_API_KEY: current.NEKODOT_PROVIDER_API_KEY }
        : {}),
      ...(current.OPENROUTER_API_KEY ? { OPENROUTER_API_KEY: current.OPENROUTER_API_KEY } : {}),
    };
    if (provider) {
      values[provider.kind === 'custom' ? 'NEKODOT_PROVIDER_API_KEY' : 'OPENROUTER_API_KEY'] =
        provider.apiKey;
      this.secrets.add(provider.apiKey);
    }
    const block =
      begin +
      '\n' +
      Object.entries(values)
        .map(([k, v]) => k + '=' + JSON.stringify(v))
        .join('\n') +
      '\n' +
      end;
    const content = old.includes(begin)
      ? old.replace(/# >>> nekodot managed >>>[\s\S]*?# <<< nekodot managed <<</, block)
      : old.trimEnd() + '\n' + block + '\n';
    await writeFile(path, content, { mode: 0o600 });
    await chmod(path, 0o600);
  }
  private async config(profile: string, provider?: ProviderInput, model?: string) {
    const directory = this.profileHome(profile);
    await mkdir(directory, { recursive: true, mode: 0o700 });
    const path = join(directory, 'config.yaml');
    const raw = await access(path).then(
      () => readFile(path, 'utf8'),
      () => '{}',
    );
    const document = parseDocument(raw);
    if (document.errors.length) throw new Error('Hermes config is not valid YAML');
    if (profile === 'default') document.setIn(['gateway', 'multiplex_profiles'], true);
    if (provider) {
      document.setIn(['model', 'provider'], provider.kind);
      document.setIn(['model', 'default'], model ?? provider.defaultModel ?? '');
      document.setIn(
        ['model', 'base_url'],
        provider.kind === 'custom' ? provider.baseUrl : 'https://openrouter.ai/api/v1',
      );
      document.setIn(
        ['model', 'api_key'],
        provider.kind === 'custom' ? '${NEKODOT_PROVIDER_API_KEY}' : '${OPENROUTER_API_KEY}',
      );
      document.setIn(['model', 'api_mode'], 'chat_completions');
    } else if (model) document.setIn(['model', 'default'], model);
    await writeFile(path, document.toString(), { mode: 0o600 });
  }
  private async currentProvider(): Promise<ProviderInput | undefined> {
    const env = await this.env('default');
    const doc = parseDocument(await readFile(join(this.options.home, 'config.yaml'), 'utf8'));
    const model = (
      doc.toJS() as { model?: { provider?: string; base_url?: string; default?: string } }
    ).model as { provider?: string; base_url?: string; default?: string } | undefined;
    if (model?.provider === 'custom' && env.NEKODOT_PROVIDER_API_KEY)
      return {
        kind: 'custom',
        apiKey: env.NEKODOT_PROVIDER_API_KEY,
        baseUrl: model.base_url!,
        defaultModel: model.default,
      };
    if (model?.provider === 'openrouter' && env.OPENROUTER_API_KEY)
      return { kind: 'openrouter', apiKey: env.OPENROUTER_API_KEY, defaultModel: model.default };
    return undefined;
  }
  async configureProvider(provider: ProviderInput, bots: Bot[]) {
    await this.writeEnv('default', provider);
    await this.config('default', provider);
    for (const bot of bots) {
      await this.writeEnv(bot.botId, provider);
      await this.config(bot.botId, provider, bot.model);
    }
  }
  async configureBot(bot: Bot, create: boolean) {
    if (create)
      await runHermesCli(this.launch, [
        'profile',
        'create',
        bot.botId,
        '--no-alias',
        '--no-skills',
      ]);
    const provider = await this.currentProvider();
    if (!provider) throw new Error('Configure a model provider first');
    await this.writeEnv(bot.botId, provider);
    await this.config(bot.botId, provider, bot.model);
    const rules = `<!-- nekodot managed: do not edit below -->\nYou are "${bot.displayName}", a member of the user's nekodot team. Your handle is @${bot.handle}.\n- Reply in the language the user writes in.\n- For passwords, 2FA codes, CAPTCHAs and payments: stop and ask the user to take over the screen. Never type these yourself.\n- In group chats, keep replies short. To hand work to a teammate, write @their-handle and say exactly what you need.\n<!-- end nekodot managed -->\n`;
    await writeFile(join(this.profileHome(bot.botId), 'SOUL.md'), bot.role + '\n\n' + rules);
    await this.waitHealthy(bot.botId);
  }
  async models() {
    return (await this.api('default')).models();
  }
  private async waitHealthy(profile: string) {
    const api = await this.api(profile);
    for (let attempt = 0; attempt < 90; attempt++) {
      if (this.closing) throw new Error('Hermes runtime closed');
      try {
        await api.health();
        return;
      } catch {
        await delay(500);
      }
    }
    throw new Error('Hermes profile did not become healthy: ' + profile);
  }
  async start() {
    await this.writeEnv('default');
    await this.config('default');
    this.launchGateway(1000);
    await this.waitHealthy('default');
  }
  private launchGateway(backoff: number) {
    if (this.closing) return;
    const child = spawnHermesCli(this.launch, ['gateway', 'run']);
    this.child = child;
    const log = (data: Buffer) => {
      let line = data.toString();
      for (const secret of this.secrets) line = line.replaceAll(secret, '[redacted]');
      this.options.onLog?.(line);
    };
    child.stdout?.on('data', log);
    child.stderr?.on('data', log);
    child.on('error', () =>
      this.options.onLog?.('Hermes gateway could not start; check the configured CLI runtime.'),
    );
    child.once('exit', () => {
      if (!this.closing)
        setTimeout(() => {
          this.launchGateway(Math.min(backoff * 2, 30000));
          void this.waitHealthy('default')
            .then(() => this.options.onReady?.())
            .catch(() => {});
        }, backoff);
    });
  }
  async close() {
    this.closing = true;
    const child = this.child;
    if (child && child.exitCode === null) {
      child.kill('SIGTERM');
      await Promise.race([
        new Promise<void>((resolve) => child.once('exit', () => resolve())),
        delay(10000),
      ]);
      if (child.exitCode === null) child.kill('SIGKILL');
    }
  }
}
