import { randomBytes } from 'node:crypto';
import { mkdir, readFile, writeFile, access, chmod, readdir } from 'node:fs/promises';
import { join } from 'node:path';
import { parseEnv } from 'node:util';
import { setTimeout as delay } from 'node:timers/promises';
import type { ChildProcess } from 'node:child_process';
import { parseDocument } from 'yaml';
import { approvalModeSchema, type ApprovalMode, type Bot } from '@nekodot/protocol';
import { HermesManagement } from './management';
import { HermesGateway, type GatewayEndpoint } from './gateway';
import { runHermesCli, spawnHermesCli, type HermesLaunch } from './cli';
import { installRoutinePlugin } from './routines-plugin';
import { installSecretsPlugin } from './secrets-plugin';
import { installUsagePlugin } from './usage-plugin';

export interface HermesRuntime {
  start(): Promise<void>;
  close(): Promise<void>;
  configureBot(
    bot: Bot,
    create: boolean,
    approvalMode?: ApprovalMode,
    previousRole?: string,
  ): Promise<void>;
  /** Brings the nekodot-managed rules in a Bot's SOUL.md up to date; writes only when they differ. */
  syncRules(bot: Bot): Promise<void>;
  approvalMode(profile: string): Promise<ApprovalMode>;
  gateway(profile: string): HermesGateway;
  environment(profile: string): Promise<NodeJS.Dict<string>>;
  management: HermesManagement;
  profileHome(profile: string): string;
  cli(profile: string, args: string[]): Promise<string>;
  restart(): Promise<void>;
  configureScreen(profile: string): Promise<void>;
  webhookUrl?: string;
}
export interface RuntimeOptions {
  home: string;
  source?: string;
  /** Official Hermes launcher (`hermes.exe` / `.hermes/bin/hermes`) of a desktop-managed checkout. */
  launcher?: string;
  /** Plugin bridge address served by Routines; defaults to the node home socket. */
  bridge?: string;
  runtime: string;
  apiPort?: number;
  managementPort?: number;
  onReady?: () => void;
  onLog?: (line: string) => void;
}
/** What nekodot asks of every Bot, kept in SOUL.md between its markers. */
export function managedRules(bot: Bot) {
  return `<!-- nekodot managed: do not edit below -->
You are "${bot.displayName}", a member of the user's nekodot team. Your handle is @${bot.handle}.
- Reply in the language the user writes in.
- Before each tool call or command, write one short line in that language saying what you are doing now, without your name: in Chinese start it with 正在 (for example 正在查看推文), in English with a verb ending in -ing (for example Checking the tweets). The app shows this progress line only beside your name, not in chat. Keep a natural acknowledgement or substantive answer separate from progress; do not repeat your progress in user-facing replies. Keep it under twelve words and write it in the same message as the call.
- For API keys, passwords, private keys and one-time codes: read the nekodot-secrets skill and request encrypted delivery cards. Never request values in chat or print them. Website logins use this profile's native vault and browser_vault. CAPTCHAs and other human verification require screen takeover. Payments are not supported by confidential delivery.
- In group chats, keep replies short. To hand work to a teammate, write @their-handle and say exactly what you need.
- When configuring a scheduled task, explain which actions need authorization and ask the user how to handle them, unless they already specified a rule. Support ask, auto-allow and auto-deny, optionally by timezone, weekday and time windows. Use the user's natural-language answer to configure the rule yourself through the nekodot-routines skill and hermes routine approvals; do not send them to a settings form or ask them to write JSON. New tasks wait paused for this answer; ask is the default. Never silently choose auto-allow or auto-deny. Resume the task after saving the confirmed rule unless the user asked to keep it paused.
- To create webhook routines, read the nekodot-routines skill. Ask the user to open the task card and approve secure credential delivery. Never request or print the webhook secret in chat.
<!-- end nekodot managed -->
`;
}

/** SOUL.md with its nekodot-managed block replaced, or the block appended when there is none. */
export function withManagedRules(soul: string, rules: string) {
  return soul.includes('<!-- nekodot managed:')
    ? soul.replace(/<!-- nekodot managed:[\s\S]*?<!-- end nekodot managed -->\n?/, rules)
    : soul.trimEnd() + '\n\n' + rules;
}

const begin = '# >>> nekodot managed >>>';
const end = '# <<< nekodot managed <<<';

export class ManagedHermes implements HermesRuntime {
  private child?: ChildProcess;
  private managementChild?: ChildProcess;
  readonly management: HermesManagement;
  private closing = false;
  private launch: HermesLaunch;
  private apiPort: number;
  readonly webhookUrl: string;
  private secrets = new Set<string>();
  private gateways = new Map<string, HermesGateway>();
  readonly bridge: string;
  constructor(readonly options: RuntimeOptions) {
    this.bridge = options.bridge ?? join(options.home, '..', 'routines.sock');
    this.apiPort = options.apiPort ?? 18642;
    this.webhookUrl = 'http://127.0.0.1:' + (this.apiPort + 2);
    const token = randomBytes(32).toString('hex');
    this.secrets.add(token);
    this.management = new HermesManagement(
      'http://127.0.0.1:' + (options.managementPort ?? this.apiPort + 1),
      token,
    );
    this.launch = options.launcher
      ? {
          command: options.launcher,
          cwd: options.home,
          home: options.home,
          runtimeDir: options.runtime,
        }
      : options.source
        ? {
            command: 'bash',
            prefixArgs: ['scripts/run-in-hermes-env', 'python', 'hermes'],
            cwd: options.source,
            home: options.home,
            runtimeDir: options.runtime,
          }
        : { command: 'hermes', cwd: options.home, home: options.home, runtimeDir: options.runtime };
    this.launch.env = { HERMES_DASHBOARD_SESSION_TOKEN: token };
  }
  profileHome(profile: string) {
    return profile === 'default' ? this.options.home : join(this.options.home, 'profiles', profile);
  }
  async environment(profile: string) {
    const path = join(this.profileHome(profile), '.env');
    const env = await access(path).then(
      () => readFile(path, 'utf8').then(parseEnv),
      () => ({}) as Record<string, string>,
    );
    for (const [key, value] of Object.entries(env))
      if (value && /KEY|TOKEN|PASSWORD|SECRET|^NEKODOT_SOURCE_/.test(key)) this.secrets.add(value);
    return env;
  }
  gateway(profile: string) {
    let gateway = this.gateways.get(profile);
    if (!gateway) {
      gateway = new HermesGateway(async () => {
        const result = JSON.parse(await this.cli(profile, ['gateway', 'ensure', '--json'])) as {
          state?: string;
          reason_code?: string;
          endpoint?: GatewayEndpoint;
        };
        if (result.state !== 'ready' || !result.endpoint)
          throw new Error('Hermes gateway is not ready for profile ' + profile);
        return result.endpoint;
      });
      this.gateways.set(profile, gateway);
    }
    return gateway;
  }
  private async writeEnv(profile: string) {
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
    const managed =
      old.match(/# >>> nekodot managed >>>([\s\S]*?)# <<< nekodot managed <<</)?.[1] ?? '';
    const values: Record<string, string> = {
      ...parseEnv(managed),
      API_SERVER_KEY: apiKey,
      API_SERVER_ENABLED: 'true',
      API_SERVER_HOST: '127.0.0.1',
      API_SERVER_PORT: String(this.apiPort),
    };
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
  private async config(profile: string, approvalMode?: ApprovalMode) {
    const directory = this.profileHome(profile);
    await mkdir(directory, { recursive: true, mode: 0o700 });
    const path = join(directory, 'config.yaml');
    const raw = await access(path).then(
      () => readFile(path, 'utf8'),
      () => '{}',
    );
    // Hermes reads YAML with PyYAML: string values such as "off" must stay strings.
    const document = parseDocument(raw, { compat: 'yaml-1.1' });
    if (document.errors.length) throw new Error('Hermes config is not valid YAML');
    const apiTools = document.toJS().platform_toolsets?.api_server as string[] | undefined;
    document.setIn(
      ['platform_toolsets', 'api_server'],
      [...new Set([...(apiTools ?? ['hermes-api-server']), 'clarify', 'nekodot-secrets'])],
    );
    if (approvalMode) document.setIn(['approvals', 'mode'], approvalMode);
    document.setIn(['approvals', 'cron_require_policy'], true);
    if (profile === 'default') {
      document.setIn(['platforms', 'webhook', 'enabled'], true);
      document.setIn(['platforms', 'webhook', 'extra', 'host'], '127.0.0.1');
      document.setIn(['platforms', 'webhook', 'extra', 'port'], this.apiPort + 2);
      const gateway = document.get('gateway');
      if (gateway && typeof gateway === 'object' && !Array.isArray(gateway))
        document.setIn(['gateway', 'multiplex_profiles'], true);
      else document.set('gateway', { multiplex_profiles: true });
    }
    await installRoutinePlugin(directory);
    await installSecretsPlugin(directory);
    const usageChanged = await installUsagePlugin(directory);
    const enabled = document.toJS().plugins?.enabled as string[] | undefined;
    document.setIn(
      ['plugins', 'enabled'],
      [...new Set([...(enabled ?? []), 'nekodot-routines', 'nekodot-secrets', 'nekodot-usage'])],
    );
    document.setIn(['plugins', 'entries', 'nekodot-routines', 'socket'], this.bridge);
    document.setIn(['plugins', 'entries', 'nekodot-secrets', 'socket'], this.bridge);
    if (document.hasIn(['secrets', 'nekodot'])) document.deleteIn(['secrets', 'nekodot']);
    await writeFile(path, document.toString(), { mode: 0o600 });
    return usageChanged;
  }
  async configureBot(
    bot: Bot,
    create: boolean,
    approvalMode?: ApprovalMode,
    previousRole?: string,
  ) {
    if (create) await runHermesCli(this.launch, ['profile', 'create', bot.botId, '--no-alias']);
    await this.writeEnv(bot.botId);
    const usageChanged = await this.config(bot.botId, approvalMode);
    const rules = managedRules(bot);
    const path = join(this.profileHome(bot.botId), 'SOUL.md');
    let soul = create ? bot.role + '\n\n' : await readFile(path, 'utf8');
    if (!create && previousRole !== undefined) {
      if (
        !soul.startsWith(previousRole) ||
        !/^\s*(?:\r?\n|$)/.test(soul.slice(previousRole.length))
      )
        throw new Error(
          'SOUL.md changed outside the saved role. Review it in Bot memory before changing the role.',
        );
      soul = bot.role + soul.slice(previousRole.length);
    }
    await writeFile(path, withManagedRules(soul, rules));
    await this.waitHealthy(bot.botId);
    if (usageChanged) await this.gateway(bot.botId).reloadPlugins();
  }
  async syncRules(bot: Bot) {
    const path = join(this.profileHome(bot.botId), 'SOUL.md');
    const soul = await readFile(path, 'utf8');
    const next = withManagedRules(soul, managedRules(bot));
    if (next !== soul) await writeFile(path, next);
  }
  async approvalMode(profile: string): Promise<ApprovalMode> {
    const output = await runHermesCli(this.launch, [
      '--profile',
      profile,
      'config',
      'get',
      'approvals.mode',
      '--json',
    ]);
    const value: unknown = JSON.parse(output.trim());
    // Hermes v0.22.6's native normalizer explicitly accepts YAML booleans.
    return approvalModeSchema.parse(value === false ? 'off' : value === true ? 'manual' : value);
  }
  async configureScreen(profile: string) {
    const path = join(this.profileHome(profile), 'config.yaml');
    const document = parseDocument(await readFile(path, 'utf8'), { compat: 'yaml-1.1' });
    if (document.errors.length) throw new Error('Hermes config is not valid YAML');
    document.setIn(['browser', 'headed'], true);
    document.setIn(['bot_desktop', 'geometry'], '1440x900');
    document.setIn(['bot_desktop', 'auto_start'], false);
    const toolsets = document.toJS().platform_toolsets?.api_server as string[] | undefined;
    document.setIn(
      ['platform_toolsets', 'api_server'],
      [...new Set([...(toolsets ?? ['hermes-api-server']), 'computer_use'])],
    );
    await writeFile(path, document.toString(), { mode: 0o600 });
  }
  private async waitHealthy(profile: string) {
    const env = await this.environment(profile);
    const apiKey = env.API_SERVER_KEY;
    if (!apiKey) throw new Error('Hermes profile has no API key');
    for (let attempt = 0; attempt < 90; attempt++) {
      if (this.closing) throw new Error('Hermes runtime closed');
      const healthy = await fetch(
        'http://127.0.0.1:' + this.apiPort + '/p/' + profile + '/health',
        { headers: { Authorization: 'Bearer ' + apiKey }, signal: AbortSignal.timeout(3000) },
      ).then(
        async (response) => {
          if (!response.ok) return false;
          await response.body?.cancel();
          return true;
        },
        () => false,
      );
      if (healthy) return;
      await delay(500);
    }
    throw new Error('Hermes profile did not become healthy: ' + profile);
  }
  async start() {
    try {
      await this.writeEnv('default');
      await this.config('default');
      const profiles = await readdir(join(this.options.home, 'profiles'), {
        withFileTypes: true,
      }).catch(() => []);
      for (const profile of profiles) if (profile.isDirectory()) await this.config(profile.name);
      this.launchGateway(1000);
      await this.waitHealthy('default');
      this.launchManagement(1000);
      await this.waitManagement();
    } catch (error) {
      await this.close();
      throw error;
    }
  }
  cli(profile: string, args: string[]) {
    return runHermesCli(this.launch, ['--profile', profile, ...args]);
  }
  private async waitManagement() {
    for (let attempt = 0; attempt < 90; attempt++) {
      if (this.closing) throw new Error('Hermes runtime closed');
      try {
        await this.management.request('/api/profiles');
        return;
      } catch {
        await delay(500);
      }
    }
    throw new Error('Hermes management did not become healthy');
  }
  private launchManagement(backoff: number) {
    if (this.closing) return;
    const child = spawnHermesCli(this.launch, [
      'serve',
      '--host',
      '127.0.0.1',
      '--port',
      String(this.options.managementPort ?? this.apiPort + 1),
      '--isolated',
    ]);
    this.managementChild = child;
    const log = (data: Buffer) => {
      let line = data.toString();
      for (const secret of this.secrets) line = line.replaceAll(secret, '[redacted]');
      this.options.onLog?.(line);
    };
    child.stdout?.on('data', log);
    child.stderr?.on('data', log);
    child.on('error', () => this.options.onLog?.('Hermes management could not start.'));
    child.once('exit', () => {
      if (!this.closing && this.managementChild === child)
        setTimeout(() => this.launchManagement(Math.min(backoff * 2, 30000)), backoff);
    });
  }
  /** POSIX gateways drain on SIGTERM; on Windows a signal is TerminateProcess, so ask Hermes to stop. */
  private async stop(child: ChildProcess | undefined, gateway: boolean, grace: number) {
    if (!child || child.exitCode !== null || child.signalCode !== null) return;
    const exited = new Promise<void>((resolve) => child.once('exit', () => resolve()));
    if (gateway && process.platform === 'win32')
      void runHermesCli(this.launch, ['gateway', 'stop', '--yes']).catch((error: unknown) =>
        this.options.onLog?.(
          'Hermes gateway stop failed: ' + (error instanceof Error ? error.message : '') + '\n',
        ),
      );
    else child.kill('SIGTERM');
    await Promise.race([exited, delay(grace)]);
    if (child.exitCode === null && child.signalCode === null) {
      child.kill('SIGKILL');
      await exited;
    }
  }
  async restart() {
    const children = [this.child, this.managementChild];
    this.child = undefined;
    this.managementChild = undefined;
    this.management.close();
    await this.stop(children[0], true, 40000);
    await this.stop(children[1], false, 10000);
    this.launchGateway(1000);
    await this.waitHealthy('default');
    this.launchManagement(1000);
    await this.waitManagement();
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
      if (!this.closing && this.child === child)
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
    for (const gateway of this.gateways.values()) gateway.close();
    this.gateways.clear();
    this.management.close();
    await this.stop(this.child, true, process.platform === 'win32' ? 40000 : 10000);
    await this.stop(this.managementChild, false, 10000);
  }
}
