import { randomUUID } from 'node:crypto';
import { WebSocket } from 'ws';
import { routineDeliverySchema } from '@nekodot/protocol';
import type { Routines } from './routines';
import { NodeFault } from './fault';
import { HermesGatewayError } from './hermes/gateway';
import type { SharedUserMemory } from './user-memory';
import type { NodeUsage } from './usage';
import type { NodeConnectors } from './connectors';
import type { ConnectorAuthorization } from '@nekodot/protocol';
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
  protocolTimings,
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
  version: string;
  onUpdate?: () => void;
  handleRpc: (request: ReturnType<typeof rpcRequestSchema.parse>) => Promise<unknown>;
  handleTransfer?: (request: TransferRequest) => Promise<TransferResponse>;
  onReady?: () => void | Promise<void>;
  onStatus?: (online: boolean) => void;
  onError?: (message: string) => void;
  onTunnel?: (request: TunnelOpen) => void;
  onNotifyAck?: (id: string) => void;
  userMemory?: SharedUserMemory;
  routines?: Routines;
  usage?: NodeUsage;
  connectors?: NodeConnectors;
}
export function connectRelay(options: NodeConnectionOptions) {
  let socket: WebSocket;
  let closing = false;
  let timer: ReturnType<typeof setTimeout> | undefined;
  let delay = 1000;
  let ready = false;
  const routeRequests = new Map<
    string,
    { resolve(): void; reject(error: Error): void; timer: ReturnType<typeof setTimeout> }
  >();
  const memoryRequests = new Map<
    string,
    { resolve(value: UserMemoryState): void; reject(error: Error): void }
  >();
  const connectorRequests = new Map<
    string,
    {
      resolve(value: unknown): void;
      reject(error: Error): void;
      timer: ReturnType<typeof setTimeout>;
    }
  >();
  function send(envelope: Envelope) {
    if (socket?.readyState === WebSocket.OPEN) socket.send(JSON.stringify(envelope));
  }
  function frame(type: Envelope['type'], payload: unknown): Envelope {
    return { v: 1, id: randomUUID(), type, nodeId: options.credentials.nodeId, payload };
  }
  if (options.connectors)
    options.connectors.request = (input) => {
      if (!ready) return Promise.reject(new NodeFault('unavailable', 'Relay is disconnected'));
      const message = frame('connectors.req', input);
      return new Promise((resolve, reject) => {
        const timer = setTimeout(() => {
          connectorRequests.delete(message.id);
          reject(
            new NodeFault(
              'timeout',
              'Connector response was not confirmed. Do not retry writes automatically.',
            ),
          );
        }, 110_000);
        connectorRequests.set(message.id, { resolve, reject, timer });
        send(message);
      });
    };
  if (options.usage)
    options.usage.publish = (records) => {
      if (!ready) return Promise.reject(new NodeFault('unavailable', 'Relay is disconnected'));
      const request = frame('usage.batch', { records });
      return new Promise<void>((resolve, reject) => {
        const timer = setTimeout(() => {
          routeRequests.delete(request.id);
          reject(new NodeFault('timeout', 'Usage sync timed out'));
        }, 30_000);
        routeRequests.set(request.id, { resolve, reject, timer });
        send(request);
      });
    };
  if (options.routines)
    options.routines.onRoutes = (routes) => {
      if (!ready) return Promise.reject(new NodeFault('unavailable', 'Relay is disconnected'));
      const request = frame('routine.routes', routes);
      return new Promise<void>((resolve, reject) => {
        const timer = setTimeout(() => {
          routeRequests.delete(request.id);
          reject(new NodeFault('timeout', 'Webhook route registration timed out'));
        }, 30_000);
        routeRequests.set(request.id, { resolve, reject, timer });
        send(request);
      });
    };
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
    const current = (socket = new WebSocket(
      options.credentials.relayUrl.replace(/^http/, 'ws').replace(/\/$/, '') + '/ws/node',
      { handshakeTimeout: protocolTimings.rpcTimeoutMs },
    ));
    let lastFrame = Date.now();
    const heartbeat = setInterval(() => {
      if (Date.now() - lastFrame > 65_000) current.terminate();
    }, 15_000);
    function send(envelope: Envelope) {
      if (current === socket && current.readyState === WebSocket.OPEN)
        current.send(JSON.stringify(envelope));
    }
    socket.on('open', () =>
      send(frame('hello', { nodeToken: options.credentials.nodeToken, version: options.version })),
    );
    socket.on('message', (raw) => {
      if (current !== socket) return;
      lastFrame = Date.now();
      let envelope: Envelope;
      try {
        envelope = envelopeSchema.parse(JSON.parse(raw.toString()));
      } catch {
        current.close(1008, 'Invalid relay message');
        return;
      }
      void receive().catch((error: unknown) => {
        if (current !== socket) return;
        options.onError?.(error instanceof Error ? error.message : 'Relay synchronization failed');
        current.close(1011, 'Synchronization interrupted');
      });
      async function receive() {
        if (envelope.type === 'ping') {
          send(frame('pong', {}));
          return;
        }
        if (envelope.type === 'hello.ok') {
          const hello = payloadSchemas['hello.ok'].parse(envelope.payload);
          options.routines?.setPublicUrl(hello.publicUrl);
          delay = 1000;
          ready = true;
          options.userMemory?.online(true);
          options.usage?.online(true);
          options.onStatus?.(true);
          await options.routines?.syncRoutes();
          await options.onReady?.();
          return;
        }
        if (envelope.type === 'usage.refresh' && options.usage) {
          const ok = await options.usage.sync().then(
            () => true,
            () => false,
          );
          send({ ...frame('usage.refreshed', { ok }), replyTo: envelope.id });
          return;
        }
        if (envelope.type === 'connectors.res') {
          const response = envelope.payload as {
            ok: boolean;
            result?: unknown;
            error?: { code: string; message: string };
          };
          const waiter = connectorRequests.get(envelope.replyTo!);
          if (waiter) {
            connectorRequests.delete(envelope.replyTo!);
            clearTimeout(waiter.timer);
            if (response.ok) waiter.resolve(response.result);
            else
              waiter.reject(
                new NodeFault('unavailable', `${response.error?.code}: ${response.error?.message}`),
              );
          }
          return;
        }
        if (envelope.type === 'connectors.changed') {
          await options.connectors?.changed(
            (envelope.payload as { authorization?: ConnectorAuthorization }).authorization,
          );
          return;
        }
        if (envelope.type === 'routine.routes.ack' || envelope.type === 'usage.ack') {
          const waiter = routeRequests.get(envelope.replyTo!);
          if (waiter) {
            clearTimeout(waiter.timer);
            routeRequests.delete(envelope.replyTo!);
            waiter.resolve();
          }
          return;
        }
        if (envelope.type === 'routine.deliver' && options.routines) {
          const input = routineDeliverySchema.parse(envelope.payload);
          const result = await options.routines.deliver(input).catch((error) => ({
            status: error instanceof NodeFault && error.code === 'not_found' ? 404 : 503,
            body: { error: 'Native webhook is unavailable' },
          }));
          send({ ...frame('routine.receipt', result), replyTo: envelope.id });
          return;
        }
        if (envelope.type === 'node.update') {
          payloadSchemas['node.update'].parse(envelope.payload);
          options.onUpdate?.();
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
            error: {
              code: 'invalid_params',
              message:
                'Invalid RPC arguments: ' +
                parsed.error.issues
                  .map((issue) => `${issue.path.join('.') || 'request'}: ${issue.message}`)
                  .join('; '),
            },
          };
        else {
          try {
            payload = { ok: true, result: await options.handleRpc(parsed.data) };
          } catch (error) {
            const code =
              error instanceof NodeFault
                ? error.code
                : error instanceof HermesGatewayError
                  ? 'unavailable'
                  : 'internal_error';
            const message =
              error instanceof NodeFault || error instanceof HermesGatewayError
                ? error.message
                : 'Node request failed';
            payload = { ok: false, error: { code, message } };
          }
        }
        send({ ...frame('rpc.res', payload), replyTo: envelope.id });
      }
    });
    socket.on('error', (error) => {
      if (current !== socket) return;
      options.onError?.(error.message);
      current.terminate();
    });
    socket.on('close', (code, reason) => {
      clearInterval(heartbeat);
      if (current !== socket) return;
      ready = false;
      for (const waiter of routeRequests.values()) {
        clearTimeout(waiter.timer);
        waiter.reject(new NodeFault('unavailable', 'Relay disconnected'));
      }
      routeRequests.clear();
      options.userMemory?.online(false);
      options.usage?.online(false);
      for (const waiter of memoryRequests.values())
        waiter.reject(
          new NodeFault('unavailable', 'Relay disconnected. User memory is kept locally.'),
        );
      memoryRequests.clear();
      for (const waiter of connectorRequests.values()) {
        clearTimeout(waiter.timer);
        waiter.reject(
          new NodeFault(
            'unavailable',
            'Relay disconnected. An uncertain connector write must not be retried automatically.',
          ),
        );
      }
      connectorRequests.clear();
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
