import { cp, mkdir, readFile, readdir, writeFile, access } from 'node:fs/promises';
import { basename, dirname, join, resolve, sep } from 'node:path';
import { unzipSync } from 'fflate';
import { parse } from 'yaml';
import type { Extension, Operation, RpcParams } from '@nekodot/protocol';
import type { NodeDatabase } from './database';
import type { BotService } from './bots';
import type { HermesRuntime } from './hermes/runtime';
import type { Operations } from './operations';
import { NodeFault } from './fault';

type NativeRow = Record<string, unknown>;
interface PluginField {
  key: string;
  type: string;
  env?: string;
}
const strings = (value: unknown): string[] => (Array.isArray(value) ? value.map(String) : []);

export class Extensions {
  constructor(
    readonly database: NodeDatabase,
    readonly bots: BotService,
    readonly hermes: HermesRuntime,
    readonly operations: Operations,
  ) {}
  async list(kind: 'skills' | 'plugins') {
    const bots = this.database.bots();
    const entries = new Map<string, Extension>();
    const profile = bots[0]?.botId ?? 'default';
    const catalog: NativeRow[] =
      kind === 'skills'
        ? (
            await this.hermes.management.request<{ skills: NativeRow[] }>(
              '/api/skills/hub/official',
              profile,
            )
          ).skills
        : (
            JSON.parse(await this.hermes.cli(profile, ['plugins', 'search', '--json'])) as {
              results: NativeRow[];
            }
          ).results;
    for (const row of catalog) {
      const id = String(row.name);
      const capabilities = row.capabilities as { requires_env?: string[] } | undefined;
      entries.set(id, {
        id,
        name: String(row.title || row.name),
        description: String(row.description ?? ''),
        category: String(row.category ?? 'general'),
        source: String(row.tier ?? row.source ?? 'official'),
        identifier: String(row.identifier ?? row.name),
        platforms: strings(row.platforms),
        dependencies: strings(capabilities?.requires_env),
        desktop: false,
        states: [],
        native: row,
      });
    }
    await Promise.all(
      bots.map(async (bot) => {
        const rows: NativeRow[] =
          kind === 'skills'
            ? await this.hermes.management.request('/api/skills', bot.botId)
            : (
                await this.hermes.management.rpc<{ plugins: NativeRow[] }>('plugins.manage', {
                  profile: bot.botId,
                  action: 'list',
                })
              ).plugins;
        for (const row of rows) {
          const id = String(row.catalog_name ?? row.name);
          let entry = entries.get(id);
          if (!entry) {
            entry = {
              id,
              name: String(row.name),
              description: String(row.description ?? ''),
              category: String(row.category ?? 'general'),
              source: String(row.provenance ?? row.source ?? 'local'),
              platforms: strings(row.platforms),
              dependencies: strings(row.python_dependencies),
              desktop: Boolean(row.has_desktop_half),
              states: [],
              native: row,
            };
            entries.set(id, entry);
          }
          entry.desktop ||= Boolean(row.has_desktop_half);
          entry.states.push({
            botId: bot.botId,
            installed: true,
            enabled: kind === 'skills' ? row.enabled !== false : row.status === 'enabled',
            status:
              kind === 'skills'
                ? row.enabled === false
                  ? 'disabled'
                  : 'enabled'
                : String(row.status),
          });
          // Full native metadata is profile-specific; redacted secret fields never contain their value.
          entry.native = {
            ...entry.native,
            installed: { ...(entry.native.installed as NativeRow | undefined), [bot.botId]: row },
          };
        }
      }),
    );
    return { entries: [...entries.values()].sort((a, b) => a.name.localeCompare(b.name)) };
  }
  async content(input: RpcParams<'extensions.content'>) {
    if (input.botId) this.bots.get(input.botId);
    const profile = input.botId ?? 'default';
    if (input.identifier) {
      const result = await this.hermes.management.request<{ skill_md: string }>(
        '/api/skills/hub/preview?identifier=' + encodeURIComponent(input.identifier),
        profile,
      );
      return { content: result.skill_md };
    }
    const result = await this.hermes.management.request<{ content: string } & NativeRow>(
      '/api/skills/content?name=' + encodeURIComponent(input.name),
      profile,
    );
    return { content: result.content };
  }
  private batch(kind: string, botIds: string[], work: (botId: string) => Promise<NativeRow>) {
    for (const id of botIds) this.bots.get(id);
    return this.operations.start(kind, botIds, async (operation) => {
      for (const botId of botIds) {
        try {
          const native = await work(botId);
          const ok = native.ok !== false;
          operation.results.push({
            botId,
            ok,
            detail: String(
              native.output ??
                native.error ??
                (native.restart_required
                  ? 'Hermes requires a restart'
                  : native.missing_env
                    ? 'Configuration required: ' + strings(native.missing_env).join(', ')
                    : 'Hermes applied this change. Activation details are shown below.'),
            ),
            native,
          });
        } catch (e) {
          operation.results.push({
            botId,
            ok: false,
            detail: e instanceof Error ? e.message : 'Hermes operation failed',
          });
        }
        operation.detail = `${operation.results.length}/${botIds.length} profiles processed`;
        this.operations.save(operation);
      }
    });
  }
  install(input: RpcParams<'extensions.install'>) {
    return this.batch('extensions.install', input.botIds, async (botId) => {
      if (input.importId) return this.installLocal(input.kind, botId, input.importId);
      if (input.kind === 'skills')
        return {
          output: await this.hermes.cli(botId, ['skills', 'install', input.identifier!, '--yes']),
        };
      const identifier = input.identifier!;
      return this.hermes.management.rpc<NativeRow>(
        'plugins.manage',
        {
          profile: botId,
          action: 'install',
          ...(identifier.includes('/') || identifier.includes(':')
            ? { identifier }
            : { catalog_name: identifier }),
          enable: true,
        },
        15 * 60_000,
      );
    });
  }
  toggle(input: RpcParams<'extensions.toggle'>) {
    return this.batch('extensions.toggle', input.botIds, async (botId) => {
      if (input.kind === 'skills')
        return this.hermes.management.request('/api/skills/toggle', botId, {
          method: 'PUT',
          body: JSON.stringify({ name: input.name, enabled: input.enabled, profile: botId }),
        });
      return this.hermes.management.rpc(
        'plugins.manage',
        { profile: botId, action: 'toggle', key: input.name, enable: input.enabled },
        120000,
      );
    });
  }
  configure(input: RpcParams<'extensions.configure'>): Operation {
    return this.batch('extensions.configure', [input.botId], async (botId) => {
      const { plugins } = await this.hermes.management.rpc<{ plugins: NativeRow[] }>(
        'plugins.manage',
        { profile: botId, action: 'list' },
      );
      const plugin = plugins.find((row) => row.key === input.name || row.name === input.name);
      if (!plugin) throw new NodeFault('not_found', 'Plugin not found in this profile');
      const fields = (plugin.settings_schema ?? []) as PluginField[];
      const values: RpcParams<'extensions.configure'>['values'] = {};
      for (const [key, value] of Object.entries(input.values)) {
        const field = fields.find((row) => row.key === key);
        if (!field) throw new NodeFault('invalid_params', 'Unknown plugin configuration field');
        if (field.type === 'secret') {
          if (value && field.env)
            await this.hermes.management.request('/api/env', botId, {
              method: 'PUT',
              body: JSON.stringify({ key: field.env, value: String(value), profile: botId }),
            });
        } else values[key] = value;
      }
      return this.hermes.management.rpc('plugins.manage', {
        profile: botId,
        action: 'settings',
        key: input.name,
        values,
      });
    });
  }
  private async installLocal(
    kind: 'skills' | 'plugins',
    botId: string,
    importId: string,
  ): Promise<NativeRow> {
    let root = join(this.database.directory, 'imports', importId);
    const uploaded = await readdir(root);
    if (uploaded.length === 1 && uploaded[0]!.toLowerCase().endsWith('.zip')) {
      const files = unzipSync(await readFile(join(root, uploaded[0]!)));
      const expanded = join(root, 'expanded');
      await mkdir(expanded, { recursive: true });
      for (const [name, bytes] of Object.entries(files)) {
        if (name.endsWith('/')) continue;
        const path = resolve(expanded, name);
        if (!path.startsWith(resolve(expanded) + sep))
          throw new NodeFault('invalid_params', 'ZIP entry leaves its package');
        await mkdir(dirname(path), { recursive: true });
        await writeFile(path, bytes);
      }
      root = expanded;
    }
    const marker = kind === 'skills' ? 'SKILL.md' : 'plugin.yaml';
    const find = async (directory: string): Promise<string[]> => {
      const children = await readdir(directory, { withFileTypes: true });
      if (
        children.some(
          (row) =>
            row.name === marker ||
            (kind === 'plugins' && ['plugin.json', 'hermes.plugin.json'].includes(row.name)),
        )
      )
        return [directory];
      return (
        await Promise.all(
          children
            .filter((row) => row.isDirectory() && row.name !== '.git')
            .map((row) => find(join(directory, row.name))),
        )
      ).flat();
    };
    const packages = await find(root);
    if (!packages.length)
      throw new NodeFault(
        'invalid_params',
        kind === 'skills' ? 'No SKILL.md found' : 'No native plugin manifest found',
      );
    const installed: string[] = [];
    let last: NativeRow = {};
    for (const directory of packages) {
      let name: string;
      if (kind === 'skills') {
        const skill = await readFile(join(directory, 'SKILL.md'), 'utf8');
        const front = /^---\r?\n([\s\S]*?)\r?\n---/.exec(skill);
        name = String(
          front
            ? ((parse(front[1]!) as { name?: string })?.name ?? basename(directory))
            : basename(directory),
        );
        if (name === 'expanded' || name === importId)
          name = 'imported-skill-' + importId.slice(0, 8);
      } else {
        const names = await readdir(directory);
        const manifest = names.find((row) =>
          ['plugin.yaml', 'plugin.json', 'hermes.plugin.json'].includes(row),
        )!;
        const raw = await readFile(join(directory, manifest), 'utf8');
        const data = (manifest.endsWith('.yaml') ? parse(raw) : JSON.parse(raw)) as {
          name: string;
        };
        name = data.name;
      }
      if (!/^[a-zA-Z0-9][a-zA-Z0-9_.-]*$/.test(name))
        throw new NodeFault('invalid_params', 'Package needs a simple native name');
      const destination = join(this.hermes.profileHome(botId), kind, name);
      if (
        await access(destination).then(
          () => true,
          () => false,
        )
      )
        throw new NodeFault(
          'conflict',
          'This profile already has ' + name + '. Existing files were kept.',
        );
      await mkdir(dirname(destination), { recursive: true });
      await cp(directory, destination, { recursive: true, errorOnExist: true, force: false });
      if (kind === 'skills')
        last = await this.hermes.management.request('/api/skills/toggle', botId, {
          method: 'PUT',
          body: JSON.stringify({ name, enabled: true, profile: botId }),
        });
      else
        last = await this.hermes.management.rpc(
          'plugins.manage',
          { profile: botId, action: 'toggle', key: name, enable: true },
          15 * 60_000,
        );
      installed.push(name);
    }
    return { ...last, output: 'Imported: ' + installed.join(', ') };
  }
}
