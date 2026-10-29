import { randomUUID } from 'node:crypto';
import { WebSocket } from 'ws';
import { NodeFault } from './fault';
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
  onTunnel?: (request: TunnelOpen) => void;
}
export function connectRelay(options: NodeConnectionOptions) {
  let socket: WebSocket;
  let closing = false;
  let timer: ReturnType<typeof setTimeout> | undefined;
  let delay = 1000;
  function send(envelope: Envelope) {
    if (socket?.readyState === WebSocket.OPEN) socket.send(JSON.stringify(envelope));
  }
  function frame(type: Envelope['type'], payload: unknown): Envelope {
    return { v: 1, id: randomUUID(), type, nodeId: options.credentials.nodeId, payload };
  }
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
          options.onStatus?.(true);
          options.onReady?.();
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
    socket.on('error', () => socket.close());
    socket.on('close', (code) => {
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
    close: () => {
      closing = true;
      clearTimeout(timer);
      socket?.terminate();
    },
    socket: () => socket,
  };
}
