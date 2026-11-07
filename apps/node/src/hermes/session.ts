import { randomUUID } from 'node:crypto';
import type { NodeDatabase } from '../database';
import type { HermesRuntime } from './runtime';
import type { HermesGateway } from './gateway';

export interface NativeSessionSnapshot {
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
) {
  const gateway = hermes.gateway(botId);
  const existing = database.hermesSession(conversationId);
  let snapshot = existing
    ? await gateway.rpc<NativeSessionSnapshot>('session.resume', {
        session_id: existing.storedSessionId,
        defer_history: true,
        omit_messages: true,
      })
    : await gateway.rpc<NativeSessionSnapshot>('session.create', {
        profile: botId,
        source: 'gui',
        title: 'Nekodot ' + conversationId,
        hidden: true,
        follow_profile_config: true,
        request_id: 'nekodot:' + botId + ':' + conversationId,
      });
  snapshot = await defaultSessionReasoning(gateway, snapshot);
  database.saveHermesSession({
    conversationId,
    botId,
    storedSessionId: snapshot.stored_session_id,
    replayEpoch: snapshot.replay_epoch,
    lastSequence: snapshot.last_sequence,
  });
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
