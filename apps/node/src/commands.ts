import { z } from 'zod';
import type { HermesRuntime } from './hermes/runtime';
import type { NodeDatabase } from './database';
import { openNativeSession } from './hermes/session';
import { HermesGatewayError } from './hermes/gateway';
import { NodeFault } from './fault';
import { BotSessions, sessionCommandNames, type CommandResult } from './session-commands';
import { commandControl, controlCommandNames } from './command-controls';
import { hostCommand, hostCommandNames } from './host-commands';

const catalogSchema = z.object({
  pairs: z.array(z.tuple([z.string(), z.string()])),
  commands: z.record(z.string(), z.object({ desktop: z.string().nullable().optional() })),
  skills: z.record(z.string(), z.unknown()),
  canon: z.record(z.string(), z.string()),
  categories: z.array(
    z.object({ name: z.string(), pairs: z.array(z.tuple([z.string(), z.string()])) }),
  ),
  warning: z.string().optional(),
});
const directiveSchema = z.object({
  output: z.string().optional(),
  warning: z.string().optional(),
  type: z.enum(['exec', 'plugin', 'alias', 'send', 'skill', 'prefill', 'navigate']).optional(),
  message: z.string().optional(),
  target: z.string().optional(),
  notice: z.string().optional(),
  display: z.string().optional(),
});
// v0.22.5 commands.catalog describes all surfaces, not slash.exec support.
// These are the owner's session_commands.py handlers; other built-ins need an
// explicit native RPC or client UI adapter. Skills/quick/plugin entries stay dynamic.
const gatewayCommands = new Set(
  `help commands status context version whoami usage insights
  profile diff memory kanban topup suggestions bundles skills title goal subgoal loop heartbeat
  review refine debug curator login autoprune plan learn init moa blueprint egress reasoning voice
  approvals codex-runtime footer busy verbose yolo fast personality approve deny toolsets platforms cron`
    .split(/\s+/)
    .map((name) => '/' + name),
);
const pageCommands: Record<string, string> = {
  '/config': 'settings',
  '/model': 'model',
  '/plugins': 'plugins',
  '/subscription': 'subscription',
  '/journey': 'journey',
  '/hatch': 'hatch',
  '/import': 'profile-import',
};
const clientCommands = new Set([
  '/copy',
  '/image',
  '/paste',
  '/focus',
  '/density',
  '/timestamps',
  '/skin',
  '/statusbar',
  '/battery',
  '/redraw',
  '/quit',
]);
const adaptedCommands = new Set([
  ...clientCommands,
  ...sessionCommandNames,
  ...controlCommandNames,
  ...hostCommandNames,
  ...Object.keys(pageCommands),
  '/history',
  '/agents',
  '/tools',
  '/reload-skills',
  '/reload',
  '/prompt',
  '/palette',
  '/pet',
  '/login',
  '/skills',
  '/cron',
]);
const unavailableReasons: Record<string, string> = {
  '/handoff': 'Hermes v0.22.5 does not expose handoff on canonical gateway sessions.',
  '/mouse': 'Terminal mouse-capture setting. App mouse and touch use native controls.',
  '/indicator': 'Terminal prompt indicator. App uses its own running-state display.',
};

/** Discovery and execution remain in Hermes, against the Bot's existing session. */
export class BotCommands {
  readonly sessions: BotSessions;
  constructor(
    private readonly database: NodeDatabase,
    private readonly hermes: HermesRuntime,
  ) {
    this.sessions = new BotSessions(database, hermes);
  }

  private async discover(botId: string) {
    const catalog = catalogSchema.parse(
      await this.hermes.gateway(botId).rpc('commands.catalog', { profile: botId }),
    );
    const dynamic = new Set(
      catalog.categories
        .filter((category) => ['User commands', 'Plugin commands'].includes(category.name))
        .flatMap((category) => category.pairs.map(([name]) => name)),
    );
    return {
      commands: catalog.pairs
        .filter(
          ([name]) => adaptedCommands.has(name) || catalog.commands[name]?.desktop !== 'hidden',
        )
        .map(([name, description]) => ({
          name,
          description,
          availability: adaptedCommands.has(name)
            ? 'app'
            : gatewayCommands.has(name) || dynamic.has(name) || Object.hasOwn(catalog.skills, name)
              ? 'available'
              : catalog.commands[name]?.desktop === 'terminal' || name === '/mouse'
                ? 'terminal'
                : 'not-integrated',
          ...(unavailableReasons[name] ? { unavailableReason: unavailableReasons[name] } : {}),
          skill:
            Object.hasOwn(catalog.skills, name) || Object.hasOwn(catalog.skills, name.slice(1)),
        })),
      warning: catalog.warning ?? '',
      aliases: catalog.canon,
    };
  }

  async catalog(botId: string) {
    const { commands, warning } = await this.discover(botId);
    return { commands, warning };
  }

  async execute(botId: string, command: string, requestId?: string): Promise<CommandResult> {
    const dm = this.database.conversations().find((c) => c.kind === 'dm' && c.botId === botId);
    if (!dm) throw new NodeFault('not_found', 'Bot conversation not found');
    const catalog = await this.discover(botId);
    const typedName = command.split(/\s/, 1)[0]!.toLowerCase();
    const name = catalog.aliases[typedName] ?? typedName;
    const arg = command.slice(typedName.length).trim();
    const entry = catalog.commands.find((row) => row.name === name);
    if (!entry || entry.availability === 'not-integrated')
      throw new NodeFault(
        'invalid_params',
        `${name} needs a client adapter that is not connected yet. No conversation or task was changed.`,
      );
    if (entry?.availability === 'terminal')
      throw new NodeFault('invalid_params', 'This Hermes command requires its native terminal.');
    if (clientCommands.has(name)) return { type: 'client', target: name, message: arg };
    if (hostCommandNames.has(name))
      return hostCommand(this.database, this.hermes, botId, name, arg);
    if (name === '/login' && !arg) return { type: 'navigate', target: 'sources' };
    if (name === '/hatch') return { type: 'navigate', target: 'hatch', message: arg };
    if (name === '/journey') {
      if (!arg || arg === 'list') return { type: 'navigate', target: 'journey' };
      if (arg.startsWith('edit '))
        return { type: 'navigate', target: 'journey', message: arg.slice(5).trim() };
      throw new NodeFault(
        'invalid_params',
        'Usage: /journey [list|edit <entry-id>]. Deletion is not offered.',
      );
    }
    if (name === '/pet') {
      if (!arg || arg === 'list') return { type: 'navigate', target: 'pets' };
      const gateway = this.hermes.gateway(botId);
      if (arg === 'toggle') {
        const info = await gateway.rpc<{ enabled: boolean; active: string }>('pet.gallery', {
          profile: botId,
        });
        if (!info.enabled && !info.active) return { type: 'navigate', target: 'pets' };
        await gateway.rpc(info.enabled ? 'pet.disable' : 'pet.select', {
          profile: botId,
          ...(info.enabled ? {} : { slug: info.active }),
        });
      } else if (arg.startsWith('scale ')) {
        const scale = Number(arg.slice(6));
        if (!Number.isFinite(scale) || scale <= 0)
          throw new NodeFault('invalid_params', 'Usage: /pet scale <positive number>');
        await gateway.rpc('pet.scale', { profile: botId, scale });
      } else {
        await gateway.rpc('pet.select', { profile: botId, slug: arg }, 120_000);
      }
      return { output: 'Hermes profile pet setting saved.', type: 'navigate', target: 'pets' };
    }
    if (sessionCommandNames.has(name)) return this.sessions.execute(botId, name, arg, requestId);
    if (
      controlCommandNames.has(name) ||
      (name === '/model' && arg && arg !== '--refresh') ||
      (name === '/agents' && arg) ||
      (name === '/tools' && arg && arg !== 'list')
    )
      return commandControl(this.database, this.hermes, botId, name, arg);
    if (name === '/profile' && arg)
      throw new NodeFault(
        'invalid_params',
        'Each Bot uses its own Hermes profile. Select a different Bot to switch profiles.',
      );
    if (name === '/skills' && /^(install|search|browse|inspect)(?:\s|$)/.test(arg)) {
      const [action, ...query] = arg.split(/\s+/);
      const result = await this.hermes.management.rpc<Record<string, unknown>>(
        'skills.manage',
        {
          profile: botId,
          action,
          query: query.join(' '),
        },
        15 * 60_000,
      );
      return { output: JSON.stringify(result, null, 2) };
    }
    if (pageCommands[name]) {
      if (arg && arg !== '--refresh')
        throw new NodeFault(
          'invalid_params',
          `Use ${name} without arguments to open its App page.`,
        );
      return { type: 'navigate' as const, target: pageCommands[name]! };
    }
    if (name === '/prompt' || name === '/palette')
      return { type: 'prefill' as const, message: name === '/palette' ? '/' : arg };
    const gateway = this.hermes.gateway(botId);
    const session = await openNativeSession(this.database, this.hermes, botId, dm.conversationId);
    const params = { session_id: session.session_id };
    if (name === '/cron' && arg && arg !== 'list') {
      if (/^(remove|rm|delete|prune)(?:\s|$)/.test(arg))
        throw new NodeFault(
          'invalid_params',
          'Task deletion requires separate authorization. Use /cron pause <id> to keep its data.',
        );
      const commandSocket = gateway.fork();
      try {
        return directiveSchema.parse(
          await commandSocket.rpc('slash.exec', { ...params, command }, 15 * 60_000),
        );
      } finally {
        commandSocket.close();
      }
    }
    if (name === '/history') {
      if (arg) throw new NodeFault('invalid_params', 'Usage: /history');
      const history = z
        .object({
          messages: z.array(
            z.object({
              role: z.string(),
              text: z.string().nullable().optional(),
              hidden: z.boolean().optional(),
            }),
          ),
        })
        .parse(await gateway.rpc('session.history', params));
      const turns = history.messages.filter(
        (row) => !row.hidden && ['user', 'assistant'].includes(row.role) && row.text?.trim(),
      );
      return {
        output: turns.length
          ? `Hermes history (${turns.length})\n\n` +
            turns.map((row) => `${row.role === 'user' ? 'User' : 'Bot'}: ${row.text}`).join('\n\n')
          : 'No conversation history yet.',
      };
    }
    if (name === '/agents') {
      if (arg)
        throw new NodeFault('invalid_params', 'Usage: /agents (active subagents and processes)');
      const [agents, processes] = await Promise.all([
        gateway.rpc<{ subagents: { status?: string; goal?: string; subagent_id?: string }[] }>(
          'subagent.list',
          params,
        ),
        gateway.rpc<{ processes: { status?: string; command?: string; session_id?: string }[] }>(
          'process.list',
          params,
        ),
      ]);
      return {
        output:
          [
            ...agents.subagents.map(
              (row) => `Agent ${row.subagent_id} [${row.status ?? 'running'}]: ${row.goal ?? ''}`,
            ),
            ...processes.processes.map(
              (row) =>
                `Process ${row.session_id} [${row.status ?? 'running'}]: ${row.command ?? ''}`,
            ),
          ].join('\n') || 'No active subagents or processes in this Hermes session.',
      };
    }
    if (name === '/tools') {
      if (arg && arg !== 'list')
        throw new NodeFault(
          'invalid_params',
          'Use /tools to list session tools. Configure toolsets in the Bot settings.',
        );
      const tools = await gateway.rpc<{
        total: number;
        sections: { name: string; tools: { name: string; description: string }[] }[];
      }>('tools.show', params);
      return {
        output:
          `Hermes tools (${tools.total})\n\n` +
          tools.sections
            .map(
              (section) =>
                `[${section.name}]\n` +
                section.tools.map((tool) => `${tool.name}: ${tool.description}`).join('\n'),
            )
            .join('\n\n'),
      };
    }
    if (name === '/reload-skills' || name === '/reload') {
      if (arg) throw new NodeFault('invalid_params', `Usage: ${name}`);
      if (name === '/reload-skills')
        return directiveSchema.parse(await gateway.rpc('skills.reload', params));
      const result = await gateway.rpc<{ updated: number }>('reload.env', params);
      return {
        output: `Hermes environment reloaded (${result.updated} updated). Existing agents keep their credentials until a new session.`,
      };
    }
    const result = await gateway
      .rpc(
        entry?.skill ? 'command.dispatch' : 'slash.exec',
        entry?.skill
          ? {
              session_id: session.session_id,
              name: name.slice(1),
              arg,
            }
          : { session_id: session.session_id, command },
        15 * 60_000,
      )
      .catch((error: unknown) => {
        if (error instanceof HermesGatewayError && error.reason === 'unsupported_command')
          throw new NodeFault(
            'invalid_params',
            `${name}: Hermes does not support these arguments on a gateway session. ${
              error.message === error.reason
                ? 'Use the corresponding App page or server terminal.'
                : error.message
            }`,
          );
        throw error;
      });
    return directiveSchema.parse(result);
  }
}
