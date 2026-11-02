import { createHash } from 'node:crypto';
import { lstat, readFile } from 'node:fs/promises';
import net from 'node:net';
import { basename, dirname, join } from 'node:path';
import { WebSocket } from 'ws';

export interface GatewayEndpoint {
  profile_id: string;
  instance_id: string;
  api_origin: string;
  runtime_protocol: number;
  control_home?: string | null;
}

export interface GatewayFrame {
  type: string;
  session_id?: string;
  payload?: Record<string, unknown>;
  seq?: number;
  replay_epoch?: string;
  admission_id?: string;
  execution_generation?: number;
}

export class HermesGatewayError extends Error {
  constructor(
    readonly reason: string,
    readonly code?: number,
    readonly data?: unknown,
  ) {
    const detail = data && typeof data === 'object' && 'detail' in data ? data.detail : undefined;
    super(typeof detail === 'string' && detail ? `${reason}: ${detail}` : reason);
    this.name = 'HermesGatewayError';
  }
}

type Pending = {
  resolve(value: unknown): void;
  reject(error: Error): void;
};

const protocol = 'hermes-gateway-v1';
const ticketPrefix = 'hermes-gateway-ticket.';

async function controlSocket(home: string) {
  const direct = join(home, 'gateway.sock');
  try {
    if ((await lstat(direct)).isSocket()) return direct;
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code !== 'ENOENT') throw error;
  }
  const pointer = (await readFile(join(home, 'gateway.sock.path'), 'utf8')).trim();
  const hash = createHash('sha256').update(home).digest('hex').slice(0, 16);
  if (
    !pointer.startsWith('/') ||
    basename(dirname(pointer)) !== `hermes-gw-${hash}` ||
    basename(pointer) !== 'control.sock'
  )
    throw new Error('Hermes gateway control socket is invalid');
  return pointer;
}

async function mintTicket(endpoint: GatewayEndpoint) {
  const home = endpoint.profile_id;
  const socketPath = await controlSocket(endpoint.control_home ?? home);
  return new Promise<string>((resolve, reject) => {
    const socket = net.createConnection(socketPath);
    let buffer = '';
    const timeout = setTimeout(
      () => socket.destroy(new Error('Hermes gateway ticket timed out')),
      5000,
    );
    socket.once('error', () => reject(new Error('Hermes gateway ticket request failed')));
    socket.once('connect', () =>
      socket.write(
        JSON.stringify({
          protocol: 1,
          id: 1,
          verb: 'session-ticket',
          params: {
            profile_id: home,
            instance_id: endpoint.instance_id,
            purpose: 'interactive',
          },
        }) + '\n',
      ),
    );
    socket.on('data', (chunk) => {
      buffer += chunk.toString();
      if (buffer.length > 65536)
        return socket.destroy(new Error('Hermes gateway ticket response is too large'));
      const end = buffer.indexOf('\n');
      if (end < 0) return;
      clearTimeout(timeout);
      try {
        const response = JSON.parse(buffer.slice(0, end)) as {
          ok?: boolean;
          protocol?: number;
          id?: number;
          result?: { profile_id?: string; instance_id?: string; ticket?: string };
        };
        const grant = response.result;
        if (
          !response.ok ||
          response.protocol !== 1 ||
          response.id !== 1 ||
          grant?.profile_id !== home ||
          grant.instance_id !== endpoint.instance_id ||
          !grant.ticket
        )
          throw new Error('Hermes gateway refused a session ticket');
        resolve(grant.ticket);
      } catch (error) {
        reject(
          error instanceof Error ? error : new Error('Invalid Hermes gateway ticket response'),
        );
      }
      socket.destroy();
    });
  });
}

/** One profile-scoped connection to Hermes' canonical session authority. */
export class HermesGateway {
  private socket?: WebSocket;
  private connecting?: Promise<WebSocket>;
  private sequence = 0;
  private openedGeneration = 0;
  private pending = new Map<number, Pending>();
  readonly listeners = new Set<(frame: GatewayFrame) => void>();
  onRequest?: (method: string, params: Record<string, unknown>) => Promise<unknown>;

  constructor(
    private readonly endpoint: () => Promise<GatewayEndpoint>,
    private readonly ticket = mintTicket,
  ) {}

  get generation() {
    return this.openedGeneration;
  }

  /** Native command sockets are unattached viewers (required by Hermes cron writes). */
  fork() {
    return new HermesGateway(this.endpoint, this.ticket);
  }

  private async connect() {
    if (this.socket?.readyState === WebSocket.OPEN) return this.socket;
    if (this.connecting) return this.connecting;
    this.connecting = (async () => {
      const endpoint = await this.endpoint();
      const origin = new URL(endpoint.api_origin);
      if (
        !['127.0.0.1', '[::1]'].includes(origin.hostname) ||
        origin.pathname !== '/' ||
        endpoint.runtime_protocol !== 1 ||
        !endpoint.profile_id ||
        !endpoint.instance_id
      )
        throw new Error('Hermes gateway endpoint is not a valid local session authority');
      const ticket = await this.ticket(endpoint);
      const socket = new WebSocket(
        origin.href.replace(/^http/, 'ws') + 'api/ws',
        [protocol, ticketPrefix + ticket],
        { handshakeTimeout: 10000, maxPayload: 8 * 1024 * 1024 },
      );
      this.socket = socket;
      socket.on('message', (raw) => {
        try {
          this.receive(raw.toString(), socket);
        } catch {
          for (const listener of this.listeners)
            listener({ type: 'gateway.protocol_error', payload: { reason: 'invalid_frame' } });
          socket.close(1002, 'invalid gateway frame');
        }
      });
      socket.on('close', () => {
        if (this.socket === socket) this.socket = undefined;
        for (const waiter of this.pending.values())
          waiter.reject(new Error('Hermes gateway disconnected'));
        this.pending.clear();
        for (const listener of this.listeners) listener({ type: 'gateway.disconnected' });
      });
      socket.on('error', () => {});
      try {
        await new Promise<void>((resolve, reject) => {
          socket.once('open', resolve);
          socket.once('error', () => reject(new Error('Hermes gateway connection failed')));
        });
      } catch (error) {
        if (this.socket === socket) this.socket = undefined;
        socket.close();
        throw error;
      }
      if (socket.protocol !== protocol) {
        if (this.socket === socket) this.socket = undefined;
        socket.close();
        throw new Error('Hermes gateway protocol mismatch');
      }
      this.openedGeneration++;
      return socket;
    })();
    try {
      return await this.connecting;
    } finally {
      this.connecting = undefined;
    }
  }

  private receive(raw: string, socket: WebSocket) {
    const frame = JSON.parse(raw) as {
      id?: number | string;
      result?: unknown;
      error?: { message?: string; code?: number; data?: unknown };
      method?: string;
      params?: unknown;
    };
    if (typeof frame.id === 'number' && this.pending.has(frame.id)) {
      const waiter = this.pending.get(frame.id)!;
      this.pending.delete(frame.id);
      if (frame.error)
        waiter.reject(
          new HermesGatewayError(
            frame.error.message ?? 'Hermes gateway request failed',
            frame.error.code,
            frame.error.data,
          ),
        );
      else waiter.resolve(frame.result);
      return;
    }
    if (frame.method === 'event' && frame.params && typeof frame.params === 'object') {
      const params = frame.params as GatewayFrame;
      for (const listener of this.listeners) listener(params);
      return;
    }
    if (typeof frame.id === 'string' && frame.method && this.onRequest) {
      void this.onRequest(frame.method, (frame.params ?? {}) as Record<string, unknown>).then(
        (result) => {
          if (socket.readyState === WebSocket.OPEN)
            socket.send(JSON.stringify({ jsonrpc: '2.0', id: frame.id, result }));
        },
        (error: unknown) =>
          socket.readyState === WebSocket.OPEN &&
          socket.send(
            JSON.stringify({
              jsonrpc: '2.0',
              id: frame.id,
              error: {
                code: -32000,
                message: error instanceof Error ? error.message : 'Request refused',
              },
            }),
          ),
      );
    }
  }

  async rpc<T>(method: string, params: Record<string, unknown>, timeoutMs = 30000): Promise<T> {
    const socket = await this.connect();
    const id = ++this.sequence;
    return new Promise<T>((resolve, reject) => {
      const timer = setTimeout(() => {
        this.pending.delete(id);
        reject(new Error('Hermes gateway request timed out'));
      }, timeoutMs);
      this.pending.set(id, {
        resolve: (value) => {
          clearTimeout(timer);
          resolve(value as T);
        },
        reject: (error) => {
          clearTimeout(timer);
          reject(error);
        },
      });
      socket.send(JSON.stringify({ jsonrpc: '2.0', id, method, params }));
    });
  }

  close() {
    this.socket?.close();
    this.socket = undefined;
  }
}
