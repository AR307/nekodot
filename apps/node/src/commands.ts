import { z } from 'zod';
import type { HermesRuntime } from './hermes/runtime';
import type { NodeDatabase } from './database';
import { openNativeSession } from './hermes/session';
import { HermesGatewayError } from './hermes/gateway';
import { NodeFault } from './fault';

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
};
const adaptedCommands = new Set([
  ...Object.keys(pageCommands),
  '/history',
  '/agents',
  '/tools',
  '/reload-skills',
  '/reload',
  '/prompt',
  '/palette',
]);

/** Discovery and execution remain in Hermes, against the Bot's existing session. */
export class BotCommands {
  constructor(
    private readonly database: NodeDatabase,
    private readonly hermes: HermesRuntime,
  ) {}

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
              : catalog.commands[name]?.desktop === 'terminal'
                ? 'terminal'
                : 'not-integrated',
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

  async execute(botId: string, command: string) {
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
    if (name === '/profile' && arg)
      throw new NodeFault(
        'invalid_params',
        'Each Bot uses its own Hermes profile. Select a different Bot to switch profiles.',
      );
    if (pageCommands[name]) {
      if (arg)
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
              (row) => `Agent [${row.status ?? 'running'}]: ${row.goal ?? row.subagent_id}`,
            ),
            ...processes.processes.map(
              (row) => `Process [${row.status ?? 'running'}]: ${row.command ?? row.session_id}`,
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
