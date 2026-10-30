import { randomBytes } from 'node:crypto';
import { mkdir, readFile, writeFile, access, chmod, readdir } from 'node:fs/promises';
import { join } from 'node:path';
import { parseEnv } from 'node:util';
import { setTimeout as delay } from 'node:timers/promises';
import type { ChildProcess } from 'node:child_process';
import { parseDocument } from 'yaml';
import { approvalModeSchema, type ApprovalMode, type Bot } from '@nekodot/protocol';
import { HermesApi } from './api';
import { HermesManagement } from './management';
import { runHermesCli, spawnHermesCli, type HermesLaunch } from './cli';

export interface HermesRuntime {
  start(): Promise<void>;
  close(): Promise<void>;
  configureBot(
    bot: Bot,
    create: boolean,
    approvalMode?: ApprovalMode,
    previousRole?: string,
  ): Promise<void>;
  approvalMode(profile: string): Promise<ApprovalMode>;
  api(profile: string): Promise<HermesApi>;
  environment(profile: string): Promise<NodeJS.Dict<string>>;
  management: HermesManagement;
  profileHome(profile: string): string;
  cli(profile: string, args: string[]): Promise<string>;
  restart(): Promise<void>;
  configureScreen(profile: string): Promise<void>;
}
export interface RuntimeOptions {
  home: string;
  source?: string;
  runtime: string;
  apiPort?: number;
  managementPort?: number;
  onReady?: () => void;
  onLog?: (line: string) => void;
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
  private secrets = new Set<string>();
  constructor(readonly options: RuntimeOptions) {
    this.apiPort = options.apiPort ?? 18642;
    const token = randomBytes(32).toString('hex');
    this.secrets.add(token);
    this.management = new HermesManagement(
      'http://127.0.0.1:' + (options.managementPort ?? this.apiPort + 1),
      token,
    );
    this.launch = options.source
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
  async api(profile: string) {
    const env = await this.environment(profile);
    if (!env.API_SERVER_KEY) throw new Error('Hermes profile has no API key');
    this.secrets.add(env.API_SERVER_KEY);
    return new HermesApi('http://127.0.0.1:' + this.apiPort + '/p/' + profile, env.API_SERVER_KEY);
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
    const document = parseDocument(raw);
    if (document.errors.length) throw new Error('Hermes config is not valid YAML');
    const apiTools = document.toJS().platform_toolsets?.api_server as string[] | undefined;
    document.setIn(
      ['platform_toolsets', 'api_server'],
      [...new Set([...(apiTools ?? ['hermes-api-server']), 'clarify'])],
    );
    if (approvalMode) document.setIn(['approvals', 'mode'], approvalMode);
    if (profile === 'default') {
      const gateway = document.get('gateway');
      if (gateway && typeof gateway === 'object' && !Array.isArray(gateway))
        document.setIn(['gateway', 'multiplex_profiles'], true);
      else document.set('gateway', { multiplex_profiles: true });
    }
    await writeFile(path, document.toString(), { mode: 0o600 });
  }
  async configureBot(
    bot: Bot,
    create: boolean,
    approvalMode?: ApprovalMode,
    previousRole?: string,
  ) {
    if (create) await runHermesCli(this.launch, ['profile', 'create', bot.botId, '--no-alias']);
    await this.writeEnv(bot.botId);
    await this.config(bot.botId, approvalMode);
    const rules = `<!-- nekodot managed: do not edit below -->\nYou are "${bot.displayName}", a member of the user's nekodot team. Your handle is @${bot.handle}.\n- Reply in the language the user writes in.\n- For passwords, 2FA codes, CAPTCHAs and payments: stop and ask the user to take over the screen. Never type these yourself.\n- In group chats, keep replies short. To hand work to a teammate, write @their-handle and say exactly what you need.\n<!-- end nekodot managed -->\n`;
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
    soul = soul.includes('<!-- nekodot managed:')
      ? soul.replace(/<!-- nekodot managed:[\s\S]*?<!-- end nekodot managed -->\n?/, rules)
      : soul.trimEnd() + '\n\n' + rules;
    await writeFile(path, soul);
    await this.waitHealthy(bot.botId);
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
    return approvalModeSchema.parse(JSON.parse(output.trim()));
  }
  async configureScreen(profile: string) {
    const path = join(this.profileHome(profile), 'config.yaml');
    const document = parseDocument(await readFile(path, 'utf8'));
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
  async restart() {
    const children = [this.child, this.managementChild];
    this.child = undefined;
    this.managementChild = undefined;
    this.management.close();
    for (const child of children)
      if (child && child.exitCode === null) {
        child.kill('SIGTERM');
        await new Promise<void>((resolve) => child.once('exit', () => resolve()));
      }
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
    this.management.close();
    for (const child of [this.child, this.managementChild]) {
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
}
