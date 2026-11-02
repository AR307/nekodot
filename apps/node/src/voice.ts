import { randomUUID } from 'node:crypto';
import type { NodeDatabase } from './database';
import type { HermesRuntime } from './hermes/runtime';
import type { HermesGateway } from './hermes/gateway';
import { openNativeSession } from './hermes/session';
import { NodeFault } from './fault';

/** Each recorder owns a native transport; two devices never mix microphone PCM. */
export class BotVoice {
  private readonly listeners = new Map<
    string,
    {
      botId: string;
      gateway: HermesGateway;
      timer: ReturnType<typeof setTimeout>;
      detected?: Record<string, unknown>;
    }
  >();
  constructor(
    private readonly database: NodeDatabase,
    private readonly hermes: HermesRuntime,
  ) {}

  async status(botId: string) {
    return this.hermes.gateway(botId).rpc<Record<string, unknown>>('wake.status', {
      profile: botId,
      surface: 'gui',
      client_capture: true,
    });
  }
  async start(botId: string) {
    const dm = this.database
      .conversations()
      .find((row) => row.kind === 'dm' && row.botId === botId)!;
    const session = await openNativeSession(this.database, this.hermes, botId, dm.conversationId);
    const gateway = this.hermes.gateway(botId).fork();
    const result = await gateway
      .rpc<Record<string, unknown>>('wake.start', {
        profile: botId,
        surface: 'gui',
        client_capture: true,
        persist: true,
        session_id: session.session_id,
      })
      .catch((error) => {
        gateway.close();
        throw error;
      });
    if (!result.started) {
      gateway.close();
      return result;
    }
    const listenerId = randomUUID();
    const owner = { botId, gateway, timer: setTimeout(() => this.stop(listenerId), 30_000) } as {
      botId: string;
      gateway: HermesGateway;
      timer: ReturnType<typeof setTimeout>;
      detected?: Record<string, unknown>;
    };
    gateway.listeners.add((frame) => {
      if (frame.type === 'wake.detected') owner.detected = frame.payload;
    });
    this.listeners.set(listenerId, owner);
    return { ...result, listenerId };
  }
  async feed(botId: string, listenerId: string, pcm: string) {
    const owner = this.listeners.get(listenerId);
    if (!owner || owner.botId !== botId)
      throw new NodeFault(
        'not_found',
        'This native microphone listener has ended. Start it again explicitly.',
      );
    clearTimeout(owner.timer);
    owner.timer = setTimeout(() => this.stop(listenerId), 30_000);
    const result = await owner.gateway.rpc<Record<string, unknown>>('wake.feed', {
      profile: botId,
      pcm,
      sample_rate: 16000,
    });
    const detected = owner.detected;
    owner.detected = undefined;
    return { ...result, ...(detected ? { detected } : {}) };
  }
  stop(listenerId: string, botId?: string) {
    const owner = this.listeners.get(listenerId);
    if (!owner) return {};
    if (botId && owner.botId !== botId)
      throw new NodeFault('not_found', 'Microphone listener not found');
    clearTimeout(owner.timer);
    this.listeners.delete(listenerId);
    // Hermes releases ownership on transport close, including network failures.
    owner.gateway.close();
    return {};
  }
  transcribe(botId: string, audio: string) {
    return this.hermes.management.request<Record<string, unknown>>('/api/audio/transcribe', botId, {
      method: 'POST',
      body: JSON.stringify({ data_url: audio, mime_type: 'audio/wav' }),
      signal: AbortSignal.timeout(120_000),
    });
  }
  close() {
    for (const listenerId of this.listeners.keys()) this.stop(listenerId);
  }
}
