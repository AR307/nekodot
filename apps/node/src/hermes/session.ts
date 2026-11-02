import type { NodeDatabase } from '../database';
import type { HermesRuntime } from './runtime';

export interface NativeSessionSnapshot {
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
  const snapshot = existing
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
  database.saveHermesSession({
    conversationId,
    botId,
    storedSessionId: snapshot.stored_session_id,
    replayEpoch: snapshot.replay_epoch,
    lastSequence: snapshot.last_sequence,
  });
  return snapshot;
}
