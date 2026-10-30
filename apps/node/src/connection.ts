import { randomUUID } from 'node:crypto';
import { WebSocket } from 'ws';
import { NodeFault } from './fault';
import type { SharedUserMemory } from './user-memory';
import {
  envelopeSchema,
  rpcRequestSchema,
  type Envelope,
  type LiveEvent,
  type PersistedEvent,
  transferRequestSchema,
  type TransferRequest,
  type TransferResponse,
  tunnelOpenSchema,
  type TunnelOpen,
  type TaskNotification,
  payloadSchemas,
  userMemoryResponseSchema,
  type UserMemoryState,
} from '@nekodot/protocol';

export interface NodeCredentials {
  relayUrl: string;
  nodeId: string;
  nodeToken: string;
}
export interface NodeConnectionOptions {
  credentials: NodeCredentials;
  handleRpc: (request: ReturnType<typeof rpcRequestSchema.parse>) => Promise<unknown>;
  handleTransfer?: (request: TransferRequest) => Promise<TransferResponse>;
  onReady?: () => void;
  onStatus?: (online: boolean) => void;
  onError?: (message: string) => void;
  onTunnel?: (request: TunnelOpen) => void;
  onNotifyAck?: (id: string) => void;
  userMemory?: SharedUserMemory;
}
export function connectRelay(options: NodeConnectionOptions) {
  let socket: WebSocket;
  let closing = false;
  let timer: ReturnType<typeof setTimeout> | undefined;
  let delay = 1000;
  let ready = false;
  const memoryRequests = new Map<
    string,
    { resolve(value: UserMemoryState): void; reject(error: Error): void }
  >();
  function send(envelope: Envelope) {
    if (socket?.readyState === WebSocket.OPEN) socket.send(JSON.stringify(envelope));
  }
  function frame(type: Envelope['type'], payload: unknown): Envelope {
    return { v: 1, id: randomUUID(), type, nodeId: options.credentials.nodeId, payload };
  }
  options.userMemory?.bind(options.credentials.nodeId, (request) => {
    if (!ready || socket?.readyState !== WebSocket.OPEN)
      return Promise.reject(
        new NodeFault('unavailable', 'Relay is disconnected. User memory is kept locally.'),
      );
    const message = frame('memory.user.req', request);
    return new Promise<UserMemoryState>((resolve, reject) => {
      const timer = setTimeout(() => {
        memoryRequests.delete(message.id);
        reject(new NodeFault('timeout', 'User memory sync timed out. Local files are kept.'));
      }, 30_000);
      memoryRequests.set(message.id, {
        resolve: (value) => {
          clearTimeout(timer);
          resolve(value);
        },
        reject: (error) => {
          clearTimeout(timer);
          reject(error);
        },
      });
      send(message);
    });
  });
  function connect() {
    socket = new WebSocket(
      options.credentials.relayUrl.replace(/^http/, 'ws').replace(/\/$/, '') + '/ws/node',
    );
    socket.on('open', () =>
      send(frame('hello', { nodeToken: options.credentials.nodeToken, version: '1.0.0' })),
    );
    socket.on('message', (raw) => {
      void receive().catch(() => socket.close(1008, 'Invalid relay message'));
      async function receive() {
        const envelope = envelopeSchema.parse(JSON.parse(raw.toString()));
        if (envelope.type === 'ping') {
          send(frame('pong', {}));
          return;
        }
        if (envelope.type === 'hello.ok') {
          delay = 1000;
          ready = true;
          options.userMemory?.online(true);
          options.onStatus?.(true);
          options.onReady?.();
          return;
        }
        if (envelope.type === 'memory.user.res') {
          const response = userMemoryResponseSchema.parse(envelope.payload);
          const waiter = memoryRequests.get(envelope.replyTo!);
          memoryRequests.delete(envelope.replyTo!);
          if (response.ok) waiter?.resolve(response.result);
          else waiter?.reject(new NodeFault(response.error.code, response.error.message));
          return;
        }
        if (envelope.type === 'memory.user.changed') {
          void options.userMemory?.sync();
          return;
        }
        if (envelope.type === 'transfer.req' && options.handleTransfer) {
          let payload: TransferResponse;
          try {
            payload = await options.handleTransfer(transferRequestSchema.parse(envelope.payload));
          } catch (error) {
            payload = {
              ok: false,
              error: error instanceof NodeFault ? error.message : 'File transfer failed',
            };
          }
          send({ ...frame('transfer.res', payload), replyTo: envelope.id });
          return;
        }
        if (envelope.type === 'tunnel.open') {
          options.onTunnel?.(tunnelOpenSchema.parse(envelope.payload));
          return;
        }
        if (envelope.type === 'notify.ack') {
          const value = payloadSchemas['notify.ack'].parse(envelope.payload);
          options.onNotifyAck?.(value.notificationId);
          return;
        }
        if (envelope.type !== 'rpc.req') return;
        const parsed = rpcRequestSchema.safeParse(envelope.payload);
        let payload: unknown;
        if (!parsed.success)
          payload = {
            ok: false,
            error: { code: 'invalid_params', message: 'Invalid RPC arguments' },
          };
        else {
          try {
            payload = { ok: true, result: await options.handleRpc(parsed.data) };
          } catch (error) {
            const code = error instanceof NodeFault ? error.code : 'internal_error';
            const message = error instanceof NodeFault ? error.message : 'Node request failed';
            payload = { ok: false, error: { code, message } };
          }
        }
        send({ ...frame('rpc.res', payload), replyTo: envelope.id });
      }
    });
    socket.on('error', (error) => {
      options.onError?.(error.message);
      socket.close();
    });
    socket.on('close', (code, reason) => {
      ready = false;
      options.userMemory?.online(false);
      for (const waiter of memoryRequests.values())
        waiter.reject(
          new NodeFault('unavailable', 'Relay disconnected. User memory is kept locally.'),
        );
      memoryRequests.clear();
      if (!closing) options.onError?.(`Relay connection closed (${code}): ${reason.toString()}`);
      options.onStatus?.(false);
      if (!closing && code !== 1008) {
        timer = setTimeout(connect, delay);
        delay = Math.min(delay * 2, 30000);
      }
    });
  }
  connect();
  return {
    event: (event: PersistedEvent) => send(frame('event', event)),
    live: (live: LiveEvent) => send(frame('live', live)),
    notify: (value: TaskNotification) => send(frame('notify', value)),
    close: () => {
      closing = true;
      clearTimeout(timer);
      socket?.terminate();
    },
    socket: () => socket,
  };
}
