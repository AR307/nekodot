import { z } from 'zod';
import type { HermesRuntime } from './hermes/runtime';
import type { NodeDatabase } from './database';
import { openNativeSession } from './hermes/session';
import { NodeFault } from './fault';

const catalogSchema = z.object({
  pairs: z.array(z.tuple([z.string(), z.string()])),
  commands: z.record(z.string(), z.object({ desktop: z.string().nullable().optional() })),
  skills: z.record(z.string(), z.unknown()),
  warning: z.string().optional(),
});
const directiveSchema = z.object({
  output: z.string().optional(),
  warning: z.string().optional(),
  type: z.enum(['exec', 'plugin', 'alias', 'send', 'skill', 'prefill']).optional(),
  message: z.string().optional(),
  target: z.string().optional(),
  notice: z.string().optional(),
  display: z.string().optional(),
});
// These need a client-owned native session switch/rewind; a slash worker
// cannot change which Hermes session the chat displays.
const sessionUiCommands = new Set([
  '/new',
  '/reset',
  '/branch',
  '/fork',
  '/resume',
  '/sessions',
  '/undo',
  '/retry',
]);

/** Discovery and execution remain in Hermes, against the Bot's existing session. */
export class BotCommands {
  constructor(
    private readonly database: NodeDatabase,
    private readonly hermes: HermesRuntime,
  ) {}

  async catalog(botId: string) {
    const catalog = catalogSchema.parse(
      await this.hermes.gateway(botId).rpc('commands.catalog', { profile: botId }),
    );
    return {
      commands: catalog.pairs
        .filter(([name]) => catalog.commands[name]?.desktop !== 'hidden')
        .map(([name, description]) => ({
          name,
          description,
          availability: sessionUiCommands.has(name)
            ? 'native-ui'
            : (catalog.commands[name]?.desktop ?? 'available'),
          skill:
            Object.hasOwn(catalog.skills, name) || Object.hasOwn(catalog.skills, name.slice(1)),
        })),
      warning: catalog.warning ?? '',
    };
  }

  async execute(botId: string, command: string) {
    const dm = this.database.conversations().find((c) => c.kind === 'dm' && c.botId === botId);
    if (!dm) throw new NodeFault('not_found', 'Bot conversation not found');
    const catalog = await this.catalog(botId);
    const name = command.split(/\s/, 1)[0]!;
    const entry = catalog.commands.find((row) => row.name === name);
    if (entry?.availability === 'native-ui')
      throw new NodeFault(
        'invalid_params',
        'This command requires the Hermes native session UI; the current conversation has not been changed.',
      );
    if (entry?.availability === 'terminal')
      throw new NodeFault('invalid_params', 'This Hermes command requires its native terminal.');
    if (name === '/profile' && command.slice(name.length).trim())
      throw new NodeFault(
        'invalid_params',
        'Each Bot uses its own Hermes profile. Select a different Bot to switch profiles.',
      );
    const gateway = this.hermes.gateway(botId);
    const session = await openNativeSession(this.database, this.hermes, botId, dm.conversationId);
    const result = await gateway.rpc(
      entry?.skill ? 'command.dispatch' : 'slash.exec',
      entry?.skill
        ? {
            session_id: session.session_id,
            name: name.slice(1),
            arg: command.slice(name.length).trim(),
          }
        : { session_id: session.session_id, command },
      15 * 60_000,
    );
    return directiveSchema.parse(result);
  }
}
