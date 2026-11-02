import type { HermesRuntime } from './hermes/runtime';
import type { HermesSessionRecord, NodeDatabase } from './database';
import type { GatewayFrame } from './hermes/gateway';
import type { NativeSessionSnapshot } from './hermes/session';

/** Observe Hermes-owned turns (loop, heartbeat and goal continuations); never submit work. */
export class NativeActivity {
  private timer?: ReturnType<typeof setTimeout>;
  private polling?: Promise<void>;
  private closed = false;
  private attached = new Map<string, { generation: number; replayEpoch: string }>();
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
        const dm = this.database
          .conversations()
          .find((row) => row.kind === 'dm' && row.botId === bot.botId);
        const session = dm && this.database.hermesSession(dm.conversationId);
        if (!session) return;
        const gateway = this.hermes.gateway(bot.botId);
        let attachment = this.attached.get(session.storedSessionId);
        if (!attachment || attachment.generation !== gateway.generation) {
          const snapshot = await gateway.rpc<NativeSessionSnapshot>('session.resume', {
            session_id: session.storedSessionId,
            omit_messages: true,
            defer_history: true,
          });
          attachment = { generation: gateway.generation, replayEpoch: snapshot.replay_epoch };
          this.attached.set(session.storedSessionId, attachment);
        }
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
          if (
            [
              'message.delta',
              'message.interim',
              'tool.start',
              'approval.request',
              'clarify.request',
              'message.complete',
              'review.summary',
            ].includes(frame.type)
          ) {
            this.onAdmission(session, frame, attachment.replayEpoch);
          }
        }
        this.database.setSetting(key, { epoch: replay.replay_epoch, sequence: replay.latest_seq });
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

  async close() {
    this.closed = true;
    clearTimeout(this.timer);
    await this.polling;
  }
}
