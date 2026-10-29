import { randomUUID } from 'node:crypto';
import { WebSocket } from 'ws';
import { NodeFault } from '../fault';

export interface ManagementEvent {
  type: string;
  session_id?: string;
  payload?: Record<string, unknown>;
}

/** Official headless Hermes management surface; chat stays on the Runs API. */
export class HermesManagement {
  private socket?: WebSocket;
  private connecting?: Promise<WebSocket>;
  private pending = new Map<
    string,
    { resolve(value: unknown): void; reject(error: Error): void }
  >();
  readonly listeners = new Set<(event: ManagementEvent) => void>();
  constructor(
    readonly baseUrl: string,
    private readonly token: string,
  ) {}

  async request<T>(path: string, profile?: string, init?: RequestInit): Promise<T> {
    return (await (await this.response(path, profile, init)).json()) as T;
  }
  async response(path: string, profile?: string, init?: RequestInit): Promise<Response> {
    const url = new URL(this.baseUrl + path);
    if (profile) url.searchParams.set('profile', profile);
    const response = await fetch(url, {
      ...init,
      headers: {
        'Content-Type': 'application/json',
        'X-Hermes-Session-Token': this.token,
        ...init?.headers,
      },
      signal: init?.signal ?? AbortSignal.timeout(30_000),
    });
    if (!response.ok) {
      const detail = (await response.json().catch(() => ({}))) as { detail?: string };
      throw new NodeFault(
        response.status === 404 ? 'not_found' : 'unavailable',
        typeof detail.detail === 'string'
          ? detail.detail
          : `Hermes management HTTP ${response.status}`,
      );
    }
    return response;
  }

  private async connect(): Promise<WebSocket> {
    if (this.socket?.readyState === WebSocket.OPEN) return this.socket;
    if (this.connecting) return this.connecting;
    this.connecting = new Promise((resolve, reject) => {
      const socket = new WebSocket(
        this.baseUrl.replace(/^http/, 'ws') + '/api/ws?token=' + encodeURIComponent(this.token),
        {
          headers: { 'X-Hermes-Session-Token': this.token },
          handshakeTimeout: 10_000,
        },
      );
      this.socket = socket;
      socket.once('open', () => resolve(socket));
      socket.once('error', reject);
      socket.on('message', (raw) => {
        const message = JSON.parse(raw.toString()) as {
          id?: string;
          result?: unknown;
          error?: { message: string };
          method?: string;
          params?: ManagementEvent;
        };
        if (message.id) {
          const waiter = this.pending.get(message.id);
          if (waiter) {
            this.pending.delete(message.id);
            if (message.error) waiter.reject(new NodeFault('unavailable', message.error.message));
            else waiter.resolve(message.result);
          }
        } else if (message.method === 'event' && message.params) {
          for (const listener of this.listeners) listener(message.params);
        }
      });
      socket.on('close', () => {
        for (const waiter of this.pending.values())
          waiter.reject(new NodeFault('unavailable', 'Hermes management disconnected'));
        this.pending.clear();
        for (const listener of this.listeners) listener({ type: 'management.disconnected' });
      });
    });
    try {
      return await this.connecting;
    } finally {
      this.connecting = undefined;
    }
  }

  async rpc<T>(method: string, params: Record<string, unknown>, timeoutMs = 30_000): Promise<T> {
    const socket = await this.connect();
    const id = randomUUID();
    return new Promise<T>((resolve, reject) => {
      const timer = setTimeout(() => {
        this.pending.delete(id);
        reject(new NodeFault('unavailable', 'Hermes management request timed out'));
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
  }
  displaySocket(ticket: string) {
    return new WebSocket(
      this.baseUrl.replace(/^http/, 'ws') +
        '/api/display/ws?display_ticket=' +
        encodeURIComponent(ticket),
      { headers: { 'X-Hermes-Session-Token': this.token }, handshakeTimeout: 10_000 },
    );
  }
}
