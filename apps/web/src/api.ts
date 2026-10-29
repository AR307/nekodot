import {
  envelopeSchema,
  rpcRequestSchema,
  rpcResponseSchema,
  type Envelope,
  type RpcMethod,
  type RpcParams,
  type RpcResult,
} from '@nekodot/protocol';
import { relayUrl } from './relay-url';

export async function relayRequest<T>(path: string, init: RequestInit = {}): Promise<T> {
  const response = await fetch(relayUrl('/api' + path), {
    ...init,
    headers: {
      ...(init.body !== undefined ? { 'Content-Type': 'application/json' } : {}),
      ...(localStorage.getItem('nekodot-token')
        ? { Authorization: 'Bearer ' + localStorage.getItem('nekodot-token') }
        : {}),
      ...init.headers,
    },
  });
  const value = (await response.json()) as { error?: { message?: string } } & T;
  if (!response.ok)
    throw Object.assign(new Error(value.error?.message ?? 'Request failed'), {
      status: response.status,
    });
  return value;
}

export function newEnvelope(type: Envelope['type'], payload: unknown, nodeId?: string): Envelope {
  return {
    v: 1,
    id: crypto.randomUUID(),
    type,
    payload,
    ...(nodeId ? { nodeId } : {}),
  };
}

export function checkedEnvelope(value: unknown) {
  return envelopeSchema.parse(value);
}

export async function rpc<M extends RpcMethod>(
  socket: WebSocket,
  nodeId: string,
  method: M,
  params: RpcParams<M>,
) {
  const request = rpcRequestSchema.parse({ method, params });
  const envelope = newEnvelope('rpc.req', request, nodeId);
  const response = await new Promise<unknown>((resolve, reject) => {
    const timeout = window.setTimeout(() => {
      pending.delete(envelope.id);
      reject(new Error('Node request timed out'));
    }, 30_000);
    pending.set(envelope.id, {
      resolve: (value) => {
        window.clearTimeout(timeout);
        resolve(value);
      },
      reject: () => {
        window.clearTimeout(timeout);
        reject(new Error('Computer disconnected. Your draft is kept; reconnect to send it.'));
      },
    });
    try {
      socket.send(JSON.stringify(envelope));
    } catch {
      window.clearTimeout(timeout);
      pending.delete(envelope.id);
      reject(new Error('Computer disconnected. Your draft is kept; reconnect to send it.'));
    }
  });
  const parsed = rpcResponseSchema(method).parse(response);
  if (!parsed.ok) throw new Error(parsed.error.message);
  return parsed.result as RpcResult<M>;
}

const pending = new Map<string, { resolve(value: unknown): void; reject(): void }>();
export function resolveRpc(replyTo: string, payload: unknown) {
  const resolve = pending.get(replyTo);
  if (!resolve) return;
  pending.delete(replyTo);
  resolve.resolve(payload);
}

export function cancelRpcRequests() {
  for (const request of pending.values()) request.reject();
  pending.clear();
}

export function fetchMe() {
  return relayRequest<import('@nekodot/protocol').Me>('/me');
}
