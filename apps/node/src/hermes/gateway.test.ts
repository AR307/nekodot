import { AddressInfo } from 'node:net';
import { once } from 'node:events';
import { expect, it } from 'vitest';
import { WebSocketServer } from 'ws';
import { HermesGateway } from './gateway';

it('speaks Hermes gateway-v1 RPC, delivers events, and answers server requests', async () => {
  const server = new WebSocketServer({
    host: '127.0.0.1',
    port: 0,
    handleProtocols: (protocols) =>
      protocols.has('hermes-gateway-v1') ? 'hermes-gateway-v1' : false,
  });
  await once(server, 'listening');
  const address = server.address() as AddressInfo;
  let resolveServerRequest!: (value: unknown) => void;
  const serverRequestReply = new Promise<unknown>((resolve) => (resolveServerRequest = resolve));
  server.on('connection', (socket) => {
    socket.send(
      JSON.stringify({
        jsonrpc: '2.0',
        method: 'event',
        params: { type: 'gateway.ready', payload: { session_authority: true } },
      }),
    );
    socket.on('message', (raw) => {
      const frame = JSON.parse(raw.toString()) as {
        id: number | string;
        method?: string;
        result?: unknown;
      };
      if (frame.method === 'session.list') {
        socket.send(JSON.stringify({ jsonrpc: '2.0', id: frame.id, result: { sessions: [] } }));
        socket.send(
          JSON.stringify({
            jsonrpc: '2.0',
            id: 'server-request-1',
            method: 'client.notice',
            params: { message: 'attached' },
          }),
        );
      } else resolveServerRequest(frame.result);
    });
  });

  let ticketProfile = '';
  const gateway = new HermesGateway(
    async () => ({
      profile_id: 'bot-profile',
      instance_id: 'instance-1',
      api_origin: `http://127.0.0.1:${address.port}`,
      runtime_protocol: 1,
    }),
    async (endpoint) => {
      ticketProfile = endpoint.profile_id;
      return 'single-use-ticket';
    },
  );
  const ready = new Promise<void>((resolve) => {
    gateway.listeners.add((frame) => {
      if (frame.type === 'gateway.ready') resolve();
    });
  });
  gateway.onRequest = async (method, params) => ({ method, ...params });

  try {
    expect(await gateway.rpc('session.list', { profile: 'bot-profile' })).toEqual({ sessions: [] });
    await ready;
    expect(ticketProfile).toBe('bot-profile');
    expect(await serverRequestReply).toEqual({ method: 'client.notice', message: 'attached' });
  } finally {
    gateway.close();
    for (const client of server.clients) client.terminate();
    await new Promise<void>((resolve) => server.close(() => resolve()));
  }
}, 30_000);
