import { randomUUID } from 'node:crypto';
import type { NodeDatabase } from './database';
import type { HermesRuntime } from './hermes/runtime';
import { openNativeSession, type NativeSessionSnapshot } from './hermes/session';
import { NodeFault } from './fault';

export const sessionCommandNames = new Set([
  '/new',
  '/clear',
  '/resume',
  '/sessions',
  '/branch',
  '/undo',
  '/retry',
  '/compress',
  '/save',
]);

export interface CommandResult {
  type?:
    | 'exec'
    | 'plugin'
    | 'alias'
    | 'send'
    | 'skill'
    | 'prefill'
    | 'navigate'
    | 'export'
    | 'client'
    | 'queue';
  output?: string;
  warning?: string;
  notice?: string;
  display?: string;
  message?: string;
  target?: string;
  content?: string;
  filename?: string;
  artifact?: string;
}

/** Session identity and transcript edits are owned by Hermes, not the product history. */
export class BotSessions {
  constructor(
    private readonly database: NodeDatabase,
    private readonly hermes: HermesRuntime,
  ) {}

  private conversation(botId: string) {
    const dm = this.database
      .conversations()
      .find((row) => row.kind === 'dm' && row.botId === botId);
    if (!dm) throw new NodeFault('not_found', 'Bot conversation not found');
    return dm;
  }

  async list(botId: string) {
    const current = this.database.hermesSession(this.conversation(botId).conversationId);
    // Hermes splits its picker into live canonical routes and closed/stored history.
    const feeds = await Promise.all(
      ['live', 'stored'].map((scope) =>
        this.hermes.gateway(botId).rpc<{ sessions: Record<string, unknown>[] }>('session.list', {
          scope,
          include_hidden: true,
          limit: 200,
        }),
      ),
    );
    const sessions = new Map<string, Record<string, unknown>>();
    for (const feed of feeds)
      for (const row of feed.sessions) {
        const id = String(row.session_id ?? row.id);
        if (!sessions.has(id)) sessions.set(id, row);
      }
    return {
      sessions: [...sessions.values()].sort((a, b) => Number(b.started_at) - Number(a.started_at)),
      currentSessionId: current?.storedSessionId ?? '',
    };
  }

  async history(botId: string, sessionId: string) {
    const gateway = this.hermes.gateway(botId);
    const session = await gateway.rpc<NativeSessionSnapshot>('session.resume', {
      session_id: sessionId,
      defer_history: true,
      omit_messages: true,
    });
    return gateway.rpc<{ messages: Record<string, unknown>[] }>('session.history', {
      session_id: session.session_id,
    });
  }

  async execute(
    botId: string,
    name: string,
    arg: string,
    requestId: string = randomUUID(),
  ): Promise<CommandResult> {
    if (name === '/sessions' || (name === '/resume' && !arg))
      return { type: 'navigate' as const, target: 'sessions' };
    const dm = this.conversation(botId),
      gateway = this.hermes.gateway(botId);
    const current = await openNativeSession(this.database, this.hermes, botId, dm.conversationId);
    const persist = (session: NativeSessionSnapshot) => {
      this.database.saveHermesSession({
        conversationId: dm.conversationId,
        botId,
        storedSessionId: session.stored_session_id,
        replayEpoch: session.replay_epoch,
        lastSequence: session.last_sequence,
      });
    };
    const mutate = (operation: string, payload: Record<string, unknown>) =>
      gateway.rpc<{
        branched_session_id?: string;
        target_message?: { content: string };
        status?: string;
        summary?: unknown;
        lines?: string[];
      }>(
        'session.mutate',
        {
          session_id: current.session_id,
          request_id: requestId,
          expected_revision: current.revision,
          expected_generation: current.execution_generation,
          operation,
          payload,
        },
        15 * 60_000,
      );
    if (
      ['/new', '/clear', '/resume', '/branch', '/undo', '/retry'].includes(name) &&
      (current.running || this.database.runs().some((run) => run.botId === botId))
    )
      throw new NodeFault(
        'conflict',
        'Finish or stop this Bot’s current task before changing its session.',
      );
    if (name === '/new' || name === '/clear') {
      const session = await gateway.rpc<NativeSessionSnapshot>('session.create', {
        profile: botId,
        source: 'gui',
        follow_profile_config: true,
        request_id: requestId,
        ...(arg ? { title: arg } : {}),
      });
      persist(session);
      return {
        output: `New Hermes session: ${session.session_id}\nPrevious sessions and nekodot messages are retained. Future messages use the new context.`,
      };
    }
    if (name === '/resume') {
      const { sessions } = await this.list(botId);
      const found = sessions.find((row) => row.session_id === arg || row.id === arg);
      const session = await gateway.rpc<NativeSessionSnapshot>(
        'session.resume',
        found
          ? {
              session_id: String(found.session_id ?? found.id),
              defer_history: true,
              omit_messages: true,
            }
          : { title: arg, defer_history: true, omit_messages: true },
      );
      if (session.running)
        throw new NodeFault(
          'conflict',
          'That Hermes session is running. Stop or finish it before switching.',
        );
      persist(session);
      return {
        output: `Resumed Hermes session: ${session.session_id}\nOpen /history to read its actual context. Existing nekodot messages are retained.`,
      };
    }
    if (name === '/branch') {
      const title = arg.replace(/^--here(?:\s+|$)/, '').trim();
      const receipt = await mutate('branch', title ? { title } : {});
      const session = await gateway.rpc<NativeSessionSnapshot>('session.resume', {
        session_id: receipt.branched_session_id,
        defer_history: true,
        omit_messages: true,
      });
      persist(session);
      return {
        output: `Branched Hermes session: ${session.session_id}\nThe parent transcript is retained. Future messages use the branch.`,
      };
    }
    if (name === '/undo' || name === '/retry') {
      const count = arg ? Number(arg) : 1;
      if (!Number.isInteger(count) || count < 1 || (name === '/retry' && arg))
        throw new NodeFault('invalid_params', 'Usage: /undo [positive turn count] or /retry');
      const snapshot = await gateway.rpc<NativeSessionSnapshot>('session.resume', {
        session_id: current.session_id,
      });
      const users = (snapshot.messages ?? []).filter((row) => row.role === 'user');
      const target = users.at(-count);
      if (!target?.row_id)
        throw new NodeFault('invalid_params', 'No such user turn in the current Hermes context.');
      if (typeof target.content !== 'string')
        throw new NodeFault(
          'invalid_params',
          'This turn contains attachments. Use a new message with the original files; no context was changed.',
        );
      const receipt = await mutate('rewind', { target_message_id: target.row_id });
      const message = receipt.target_message!;
      return {
        type: name === '/retry' ? ('send' as const) : ('prefill' as const),
        message: message.content,
        output:
          'Hermes context rewound. Existing nekodot messages and tool effects are retained; this does not roll back files.',
      };
    }
    if (name === '/compress') {
      const receipt = await mutate('compress', arg ? { focus: arg } : {});
      return {
        output: `Hermes compression (${receipt.status ?? 'applied'})\n${
          receipt.lines?.join('\n') ?? JSON.stringify(receipt.summary ?? {})
        }`,
      };
    }
    if (name === '/save') {
      if (!arg)
        return {
          output:
            'Usage: /save <json|md|html> [filename] [redact]. The App saves the native export on your device.',
        };
      const parts = arg.split(/\s+/),
        format = parts.shift()!;
      const redact = parts.at(-1) === 'redact';
      if (redact) parts.pop();
      if (!['json', 'md', 'html'].includes(format))
        throw new NodeFault('invalid_params', 'Export format: json, md, html.');
      const exported = await gateway.rpc<{ content: string; filename: string }>('session.export', {
        session_id: current.session_id,
        format,
        redact,
      });
      // A filename is local to the client; never accept a server-side destination path.
      return {
        type: 'export' as const,
        content: exported.content,
        filename: (parts.join(' ') || exported.filename).split(/[\\/]/).at(-1)!,
        output: 'Native Hermes export is ready to save on this device.',
      };
    }
    throw new NodeFault('invalid_params', 'Unknown session command');
  }
}
