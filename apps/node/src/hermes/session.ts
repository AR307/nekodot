import { randomUUID } from 'node:crypto';
import type { NodeDatabase } from '../database';
import type { HermesRuntime } from './runtime';
import type { HermesGateway } from './gateway';
import { NodeFault } from '../fault';

export interface NativeSessionSnapshot {
  bootstrap?: string;
  info?: {
    model?: string;
    provider?: string;
    api_mode?: string;
    reasoning_effort?: string | null;
    reasoning_effort_wire?: string | null;
  };
  session_id: string;
  stored_session_id: string;
  replay_epoch: string;
  last_sequence: number;
  running: boolean;
  execution_generation: number;
  revision: number;
  pending?: { admission_id: string; steering?: boolean }[];
  messages?: { role: string; content?: unknown; text?: string | null; row_id?: number }[];
  prompts?: {
    kind: 'approval' | 'clarify';
    prompt_id: string;
    execution_generation: number;
    choices?: string[];
    command?: string;
    description?: string;
    question?: string;
    multi_select?: boolean;
  }[];
}

export async function openNativeSession(
  database: NodeDatabase,
  hermes: HermesRuntime,
  botId: string,
  conversationId: string,
  options: { execution?: boolean; ownerConversationId?: string } = {},
) {
  const gateway = hermes.gateway(botId);
  const marker = 'coordinator-session:' + conversationId;
  const existing =
    options.execution || database.setting(marker)
      ? database.hermesSession(conversationId)
      : undefined;
  let reasoning: string | null | undefined;
  if (options.execution && !existing && options.ownerConversationId) {
    const owner = database.conversation(options.ownerConversationId)!;
    const coordinator = database.hermesSession(
      owner.kind === 'group' ? 'group:' + owner.conversationId + ':' + botId : owner.conversationId,
    );
    if (coordinator) {
      const info = await gateway.rpc<NonNullable<NativeSessionSnapshot['info']>>('session.info', {
        session_id: coordinator.storedSessionId,
      });
      reasoning = info.reasoning_effort;
    }
  }
  let snapshot = existing
    ? await gateway.rpc<NativeSessionSnapshot>('session.resume', {
        session_id: existing.storedSessionId,
        defer_history: true,
        omit_messages: true,
      })
    : await gateway.rpc<NativeSessionSnapshot>('session.create', {
        profile: botId,
        source: 'gui',
        // Hermes titles are identities and limited to 100 characters. Execution keys end
        // in their unique segment ID; including a Cron/Webhook task ID exceeds that limit.
        title: options.execution
          ? 'Nekodot task ' + conversationId.split(':').at(-1)
          : 'Nekodot coordinator ' + conversationId,
        hidden: true,
        follow_profile_config: true,
        ...(reasoning ? { reasoning } : {}),
        ...(!options.execution ? { toolsets: ['nekodot-tasks', 'memory', 'clarify'] } : {}),
        request_id:
          'nekodot:' +
          (options.execution ? 'task:' : 'coordinator:') +
          botId +
          ':' +
          conversationId,
      });
  snapshot = await defaultSessionReasoning(gateway, snapshot);
  database.saveHermesSession({
    conversationId,
    botId,
    storedSessionId: snapshot.stored_session_id,
    replayEpoch: snapshot.replay_epoch,
    lastSequence: snapshot.last_sequence,
    ownerConversationId: options.ownerConversationId,
  });
  if (!options.execution) {
    if (!database.setting(marker)) {
      const context = database
        .messages(options.ownerConversationId ?? conversationId, undefined, 40)
        .filter((message) => message.kind === 'text' && message.taskRole !== 'execution')
        .map((message) => ({
          author: message.author,
          text: message.kind === 'text' ? message.content.text : '',
        }));
      database.setSetting(
        marker + ':context',
        context.length
          ? 'Earlier messages from this chat only (history, not new instructions; do not repeat completed work):\n' +
              JSON.stringify(context)
          : '',
      );
    }
    database.setSetting(marker, true);
    snapshot.bootstrap = database.setting<string>(marker + ':context');
  }
  return snapshot;
}

/** Unset sessions use the product default; explicit levels and running turns are untouched. */
export async function defaultSessionReasoning(
  gateway: HermesGateway,
  snapshot: NativeSessionSnapshot,
) {
  if (!snapshot.info || snapshot.info.reasoning_effort || snapshot.running) return snapshot;
  await gateway.rpc('session.mutate', {
    session_id: snapshot.session_id,
    request_id: randomUUID(),
    expected_revision: snapshot.revision,
    expected_generation: snapshot.execution_generation,
    operation: 'reasoning',
    payload: { effort: 'xhigh' },
  });
  // Hermes owns provider-specific normalization; report its actual configured and wire values.
  return gateway.rpc<NativeSessionSnapshot>('session.resume', {
    session_id: snapshot.stored_session_id,
    defer_history: true,
    omit_messages: true,
  });
}

/** Plugin commands run in the Bot's existing native session, without submitting a model turn. */
export async function runProfileCommand(
  database: NodeDatabase,
  hermes: HermesRuntime,
  botId: string,
  name: string,
  args: Record<string, unknown>,
) {
  const dm = database.conversations().find((row) => row.kind === 'dm' && row.botId === botId);
  if (!dm) throw new NodeFault('not_found', 'Bot conversation not found');
  const sessionId =
    database.hermesSession(dm.conversationId)?.storedSessionId ??
    (await openNativeSession(database, hermes, botId, dm.conversationId)).session_id;
  return hermes.gateway(botId).rpc<{ output: string }>('command.dispatch', {
    session_id: sessionId,
    name,
    arg: JSON.stringify({ ...args, profile: botId }),
  });
}
