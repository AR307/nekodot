import type { HermesRuntime } from './hermes/runtime';
import type { HermesSessionRecord, NodeDatabase } from './database';
import type { HermesGateway, GatewayFrame } from './hermes/gateway';
import type { NativeSessionSnapshot } from './hermes/session';

/** Observe Hermes-owned turns (loop, heartbeat and goal continuations); never submit work. */
export class NativeActivity {
  private timer?: ReturnType<typeof setTimeout>;
  private polling?: Promise<void>;
  private closed = false;
  private attached = new Map<string, { generation: number; replayEpoch: string }>();
  private listeners = new Map<HermesGateway, (frame: GatewayFrame) => void>();
  private scopes = new Map<string, HermesSessionRecord>();
  private unavailable = new Set<string>();

  constructor(
    private readonly database: NodeDatabase,
    private readonly hermes: HermesRuntime,
    private readonly onAdmission: (
      session: HermesSessionRecord,
      frame: GatewayFrame,
      replayEpoch: string,
    ) => void,
  ) {}

  start() {
    if (this.closed || this.timer || this.polling) return;
    this.polling = this.poll().finally(() => {
      this.polling = undefined;
      if (!this.closed)
        this.timer = setTimeout(() => {
          this.timer = undefined;
          this.start();
        }, 1000);
    });
  }

  private async poll() {
    const bots = this.database.bots().filter((bot) => !bot.archived);
    const results = await Promise.allSettled(
      bots.map(async (bot) => {
        const gateway = this.hermes.gateway(bot.botId);
        const sessions = this.database.hermesSessions().filter((s) => s.botId === bot.botId);
        for (const session of sessions) this.scopes.set(session.storedSessionId, session);
        if (!this.listeners.has(gateway)) {
          const listener = (frame: GatewayFrame) => {
            const session = frame.session_id && this.scopes.get(frame.session_id);
            const attached = session && this.attached.get(session.storedSessionId);
            if (session && attached && this.relevant(frame)) {
              this.onAdmission(session, frame, frame.replay_epoch ?? attached.replayEpoch);
            }
          };
          this.listeners.set(gateway, listener);
          gateway.listeners.add(listener);
        }
        const live = await gateway.rpc<{ sessions: { session_id: string; running: boolean }[] }>(
          'session.list',
          { include_hidden: true, limit: 200 },
        );
        const running = new Set(live.sessions.filter((s) => s.running).map((s) => s.session_id));
        for (const session of sessions) {
          let attachment = this.attached.get(session.storedSessionId);
          if (!attachment || attachment.generation !== gateway.generation) {
            const snapshot = await gateway.rpc<NativeSessionSnapshot>('session.resume', {
              session_id: session.storedSessionId,
              omit_messages: true,
              defer_history: true,
            });
            attachment = { generation: gateway.generation, replayEpoch: snapshot.replay_epoch };
            this.attached.set(session.storedSessionId, attachment);
          } else if (!running.has(session.storedSessionId)) continue;
          const key = 'native-events:' + session.storedSessionId;
          const cursor = this.database.setting<{ epoch: string; sequence: number }>(key);
          const replay = await gateway.rpc<{
            events: GatewayFrame[];
            replay_epoch: string;
            latest_seq: number;
          }>('session.events.since', {
            session_id: session.storedSessionId,
            replay_epoch: cursor?.epoch ?? session.replayEpoch,
            last_sequence: cursor?.sequence ?? session.lastSequence,
          });
          if (this.closed) return;
          for (const frame of replay.events) {
            if (this.relevant(frame)) {
              this.onAdmission(session, frame, attachment.replayEpoch);
            }
          }
          this.database.setSetting(key, {
            epoch: replay.replay_epoch,
            sequence: replay.latest_seq,
          });
        }
      }),
    );
    for (const [index, result] of results.entries()) {
      const botId = bots[index]!.botId;
      if (result.status === 'rejected') {
        if (!this.unavailable.has(botId))
          console.warn('Native session observation unavailable for Bot', botId);
        this.unavailable.add(botId);
      } else this.unavailable.delete(botId);
    }
  }

  private relevant(frame: GatewayFrame) {
    return [
      'message.delta',
      'message.interim',
      'tool.start',
      'approval.request',
      'clarify.request',
      'message.complete',
      'review.summary',
    ].includes(frame.type);
  }
  async close() {
    this.closed = true;
    clearTimeout(this.timer);
    await this.polling;
    for (const [gateway, listener] of this.listeners) gateway.listeners.delete(listener);
    this.listeners.clear();
  }
}
