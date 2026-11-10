import { randomUUID } from 'node:crypto';
import type { NativeModelOverride, NodeDatabase } from './database';
import type { HermesRuntime } from './hermes/runtime';
import { openNativeSession, type NativeSessionSnapshot } from './hermes/session';
import { NodeFault } from './fault';

export const sessionCommandNames = new Set(['/undo', '/retry', '/compress', '/save']);

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
  modelOverride?: NativeModelOverride;
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
    const dm = this.conversation(botId),
      gateway = this.hermes.gateway(botId);
    const current = await openNativeSession(this.database, this.hermes, botId, dm.conversationId);
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
      ['/undo', '/retry'].includes(name) &&
      (current.running || this.database.runs().some((run) => run.botId === botId))
    )
      throw new NodeFault(
        'conflict',
        'Finish or stop this Bot’s current task before changing its session.',
      );
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
