import { createHash } from 'node:crypto';
import { platform, release } from 'node:os';
import { WebSocket } from 'ws';
import { z } from 'zod';
import type { RpcParams, ScreenStatus, TunnelOpen } from '@nekodot/protocol';
import type { HermesRuntime } from './hermes/runtime';
import type { ManagementEvent } from './hermes/management';
import type { BotService } from './bots';
import type { Operations } from './operations';
import type { NodeCredentials } from './connection';
import { NodeFault } from './fault';

const nativeLeaseSchema = z.object({
  holder: z.enum(['agent', 'human']),
  viewer_hash: z.string().nullable().optional(),
  epoch: z.number(),
});
const nativeStatusSchema = z.object({
  supported: z.boolean(),
  installed: z.boolean(),
  running: z.boolean(),
  geometry: z.string(),
  missing: z.array(z.string()),
  install_command: z.string().nullable().optional(),
  blocker: z.string().nullable().optional(),
  profile_key: z.string(),
  lease: nativeLeaseSchema,
});
type NativeStatus = z.infer<typeof nativeStatusSchema>;
interface ScreenSession {
  botId: string;
  viewerId?: string;
  viewerHash?: string;
  sockets?: [WebSocket, WebSocket?];
}

/** A product adapter for Hermes-owned displays; no agent or control lifecycle lives here. */
export class BotScreens {
  readonly available = platform() === 'linux' && !/microsoft/i.test(release());
  onStatus: (status: ScreenStatus) => void = () => {};
  private readonly sessions = new Map<string, ScreenSession>();
  private readonly statuses = new Map<string, NativeStatus>();
  private readonly profileKeys = new Map<string, string>();
  constructor(
    private readonly hermes: HermesRuntime,
    private readonly bots: BotService,
    private readonly operations: Operations,
  ) {
    hermes.management.listeners.add(this.handleEvent);
  }
  private handleEvent = (event: ManagementEvent) => {
    if (event.type === 'management.disconnected') {
      for (const session of this.sessions.values()) {
        session.viewerId = undefined;
        session.viewerHash = undefined;
        session.sockets?.forEach((socket) => socket?.terminate());
      }
      return;
    }
    if (!['display.status', 'display.lease'].includes(event.type)) return;
    const botId = this.profileKeys.get(String(event.payload?.profile_key));
    if (!botId) return;
    if (event.type === 'display.status') {
      this.publish(botId, nativeStatusSchema.parse(event.payload));
    } else {
      const status = this.statuses.get(botId);
      const lease = nativeLeaseSchema.parse(event.payload?.lease);
      if (status && lease.epoch >= status.lease.epoch) this.publish(botId, { ...status, lease });
    }
  };
  private publicStatus(botId: string, status?: NativeStatus): ScreenStatus {
    const controllerSessionId =
      status?.lease.holder === 'human'
        ? [...this.sessions].find(
            ([, session]) =>
              session.botId === botId && session.viewerHash === status.lease.viewer_hash,
          )?.[0]
        : undefined;
    return {
      botId,
      available: this.available && (status?.supported ?? true),
      installed: status?.installed ?? false,
      running: status?.running ?? false,
      geometry: status?.geometry ?? '1440x900',
      missing: status?.missing ?? [],
      holder: status?.lease.holder ?? 'agent',
      ...(controllerSessionId ? { controllerSessionId } : {}),
      ...(status?.install_command ? { installCommand: status.install_command } : {}),
      ...(!this.available
        ? { blocker: 'Screen access currently supports Linux VPS nodes only.' }
        : status?.blocker
          ? { blocker: status.blocker }
          : {}),
    };
  }
  private publish(botId: string, status: NativeStatus) {
    const previous = this.statuses.get(botId);
    if (previous && previous.lease.epoch > status.lease.epoch)
      status = { ...status, lease: previous.lease };
    this.statuses.set(botId, status);
    this.profileKeys.set(status.profile_key, botId);
    const result = this.publicStatus(botId, status);
    this.onStatus(result);
    return result;
  }
  async status(botId: string): Promise<ScreenStatus> {
    this.bots.get(botId);
    if (!this.available) return this.publicStatus(botId);
    return this.publish(
      botId,
      nativeStatusSchema.parse(
        await this.hermes.management.rpc('display.status', { profile: botId }),
      ),
    );
  }
  start(botId: string) {
    this.bots.get(botId);
    if (!this.available) throw new NodeFault('unavailable', 'Screen access requires a Linux VPS.');
    return this.operations.start('screen.start', [botId], async (operation) => {
      await this.hermes.configureScreen(botId);
      const result = await this.hermes.management.rpc('display.start', { profile: botId }, 120_000);
      this.publish(botId, nativeStatusSchema.parse(result));
      operation.detail = 'Hermes screen is running.';
    });
  }
  stop(botId: string, force = false) {
    this.bots.get(botId);
    return this.operations.start('screen.stop', [botId], async (operation) => {
      const result = await this.hermes.management.rpc(
        'display.stop',
        { profile: botId, force },
        120_000,
      );
      this.publish(botId, nativeStatusSchema.parse(result));
      operation.detail = 'Hermes screen stopped. Browser data is retained.';
    });
  }
  async control(input: RpcParams<'screen.control'>) {
    this.bots.get(input.botId);
    const session = input.sessionId ? this.sessions.get(input.sessionId) : undefined;
    if (input.action !== 'force-release' && (!session?.viewerId || session.botId !== input.botId))
      throw new NodeFault('conflict', 'Reconnect this screen before changing control.');
    await this.hermes.management.rpc(
      input.action === 'take' ? 'display.lease.acquire' : 'display.lease.release',
      {
        profile: input.botId,
        ...(input.action === 'force-release' ? { force: true } : { viewer_id: session!.viewerId }),
      },
    );
    return this.status(input.botId);
  }
  openTunnel(credentials: NodeCredentials, request: TunnelOpen) {
    const old = this.sessions.get(request.sessionId);
    old?.sockets?.forEach((socket) => socket?.terminate());
    const session: ScreenSession = old?.botId === request.botId ? old : { botId: request.botId };
    this.sessions.set(request.sessionId, session);
    const relay = new WebSocket(
      credentials.relayUrl.replace(/^http/, 'ws').replace(/\/$/, '') + '/ws/tunnel-node',
      { handshakeTimeout: 10_000 },
    );
    session.sockets = [relay];
    relay.on('error', () => relay.terminate());
    relay.once('open', () => {
      relay.send(JSON.stringify({ tunnelId: request.tunnelId, nodeToken: credentials.nodeToken }));
      relay.pause();
      void attach().catch((error: unknown) =>
        relay.close(
          1011,
          (error instanceof Error ? error.message : 'Screen connection failed').slice(0, 120),
        ),
      );
    });
    const attach = async () => {
      this.bots.get(request.botId);
      if (!this.available)
        throw new NodeFault('unavailable', 'Screen access requires a Linux VPS.');
      const observed = await this.hermes.management.rpc('display.observe', {
        profile: request.botId,
        ...(session.viewerId ? { viewer_id: session.viewerId } : {}),
      });
      const value = z
        .object({ ticket: z.string(), viewer_id: z.string() })
        .and(nativeStatusSchema)
        .parse(observed);
      if (relay.readyState !== WebSocket.OPEN) return;
      session.viewerId = value.viewer_id;
      // Hermes publishes this identity in its native lease; this is not a file integrity check.
      session.viewerHash = createHash('sha256').update(value.viewer_id).digest('hex').slice(0, 12);
      this.publish(request.botId, value);
      const native = this.hermes.management.displaySocket(value.ticket);
      session.sockets = [relay, native];
      native.on('open', () => relay.resume());
      native.on('error', () => relay.close(1011, 'Hermes screen connection failed'));
      native.on('message', (data) => {
        if (relay.readyState !== WebSocket.OPEN) return;
        native.pause();
        relay.send(data, { binary: true }, () => native.resume());
      });
      relay.on('message', (data, binary) => {
        if (!binary) return relay.close(1003, 'Screen frames must be binary');
        if (native.readyState !== WebSocket.OPEN) return;
        relay.pause();
        native.send(data, { binary: true }, () => relay.resume());
      });
      native.on('close', (code, reason) => {
        if (code === 1006 || code === 1005) relay.terminate();
        else relay.close(code, reason.toString());
      });
      relay.on('close', (code, reason) => {
        if (code === 1000 || code === 1001) {
          native.close(code, reason.toString());
          if (this.sessions.get(request.sessionId) === session)
            this.sessions.delete(request.sessionId);
        } else native.terminate();
      });
    };
  }
  close() {
    this.hermes.management.listeners.delete(this.handleEvent);
    for (const session of this.sessions.values())
      session.sockets?.forEach((socket) => socket?.terminate());
    this.sessions.clear();
  }
}
