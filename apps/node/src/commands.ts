import { discoverCommands, parseCommand } from './command-catalog';
import { clientAction, pageCommands } from './command-client';
import { isSettingsCommand, settingsCommand } from './command-settings';
import { z } from 'zod';
import type { HermesRuntime } from './hermes/runtime';
import type { NodeDatabase } from './database';
import { openNativeSession } from './hermes/session';
import { HermesGatewayError } from './hermes/gateway';
import { NodeFault } from './fault';
import { BotSessions, sessionCommandNames, type CommandResult } from './session-commands';
import { commandControl, controlCommandNames } from './command-controls';
import { hostCommand, hostCommandNames } from './host-commands';
const directiveSchema = z.object({
  output: z.string().optional(),
  warning: z.string().optional(),
  type: z.enum(['exec', 'plugin', 'alias', 'send', 'skill', 'prefill', 'navigate']).optional(),
  message: z.string().optional(),
  target: z.string().optional(),
  notice: z.string().optional(),
  display: z.string().optional(),
});

/** Discovery and execution remain in Hermes, against the Bot's existing session. */
export class BotCommands {
  readonly sessions: BotSessions;
  constructor(
    private readonly database: NodeDatabase,
    private readonly hermes: HermesRuntime,
  ) {
    this.sessions = new BotSessions(database, hermes);
  }

  async catalog(botId: string) {
    const { commands, warning } = await discoverCommands(this.hermes, botId);
    return { commands, warning };
  }

  async execute(botId: string, command: string, requestId?: string): Promise<CommandResult> {
    const dm = this.database.conversations().find((c) => c.kind === 'dm' && c.botId === botId);
    if (!dm) throw new NodeFault('not_found', 'Bot conversation not found');
    const catalog = await discoverCommands(this.hermes, botId);
    const { name, arg } = parseCommand(command, catalog.aliases);
    const entry = catalog.commands.find((row) => row.name === name);
    if (!entry || entry.availability === 'not-integrated')
      throw new NodeFault(
        'invalid_params',
        `${entry?.unavailableReason ?? `${name} needs a client adapter that is not connected yet.`} No conversation or task was changed.`,
      );
    if (entry?.availability === 'terminal')
      throw new NodeFault('invalid_params', 'This Hermes command requires its native terminal.');
    if (name === '/heartbeat' && arg && !['status', 'pause', 'stop', 'off', 'clear'].includes(arg))
      throw new NodeFault(
        'unavailable',
        'Hermes v0.22.5 saves local-session heartbeats but does not execute them. Creation/resume is unavailable; status, pause and stop still use native state. No task was created or changed.',
      );
    if (name === '/help') {
      const query = arg.toLowerCase();
      const entries = catalog.commands.filter((row) =>
        query === 'skills'
          ? row.skill
          : `${row.name} ${row.description}`.toLowerCase().includes(query),
      );
      return {
        output:
          entries
            .map((row) => `${row.name}: ${row.unavailableReason ?? row.description}`)
            .join('\n\n') || 'No matching Hermes commands.',
      };
    }
    const action = clientAction(name, arg);
    if (action) return action;
    if (isSettingsCommand(name, arg)) return settingsCommand(this.hermes, botId, name, arg);
    if (hostCommandNames.has(name))
      return hostCommand(this.database, this.hermes, botId, name, arg);
    if (sessionCommandNames.has(name)) return this.sessions.execute(botId, name, arg, requestId);
    if (
      controlCommandNames.has(name) ||
      (name === '/model' && arg && arg !== '--refresh') ||
      (name === '/agents' && arg)
    )
      return commandControl(this.database, this.hermes, botId, name, arg);
    if (name === '/profile' && arg)
      throw new NodeFault(
        'invalid_params',
        'Each Bot uses its own Hermes profile. Select a different Bot to switch profiles.',
      );
    if (pageCommands[name]) {
      if (arg && arg !== '--refresh')
        throw new NodeFault(
          'invalid_params',
          `Use ${name} without arguments to open its App page.`,
        );
      return { type: 'navigate' as const, target: pageCommands[name]! };
    }
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
    if (name === '/moa' && arg) {
      const config = await this.hermes.management.request<{ moa: { default_preset: string } }>(
        '/api/config?include_defaults=true',
        botId,
      );
      // Canonical /moa commits its route on this admission, like the official CLI.
      // slash.exec alone only prepares the messaging adapter's transient override.
      return {
        type: 'send',
        message: arg,
        display: command,
        modelOverride: { model: config.moa.default_preset, provider: 'moa' },
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
