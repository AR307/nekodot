import { randomUUID } from 'node:crypto';
import type { Server } from 'node:http';
import { WebSocket, WebSocketServer } from 'ws';
import { envelopeSchema, payloadSchemas, protocolTimings, type Envelope } from '@nekodot/protocol';
import type { RelayDatabase, NodeRow } from './database';

const frame = (type: Envelope['type'], payload: unknown, nodeId?: string): Envelope => ({
  v: 1,
  id: randomUUID(),
  type,
  payload,
  ...(nodeId ? { nodeId } : {}),
});
const send = (socket: WebSocket, value: Envelope) => {
  if (socket.readyState === WebSocket.OPEN) socket.send(JSON.stringify(value));
};
interface Client {
  socket: WebSocket;
  userId: string;
}
export function registerRouting(
  server: Server,
  database: RelayDatabase,
  authenticate: (token: string) => Promise<{ user_id: string }>,
) {
  const wss = new WebSocketServer({ noServer: true });
  const clients = new Set<Client>();
  const nodes = new Map<string, WebSocket>();
  const pending = new Map<
    string,
    { socket: WebSocket; nodeId: string; timer: ReturnType<typeof setTimeout> }
  >();
  function broadcast(userId: string, value: Envelope) {
    for (const client of clients) if (client.userId === userId) send(client.socket, value);
  }
  function clearPending(nodeId: string) {
    for (const [id, p] of pending)
      if (p.nodeId === nodeId) {
        clearTimeout(p.timer);
        pending.delete(id);
        send(p.socket, {
          ...frame(
            'rpc.res',
            { ok: false, error: { code: 'unavailable', message: 'Node disconnected' } },
            nodeId,
          ),
          replyTo: id,
        });
      }
  }
  server.on('upgrade', (request, socket, head) => {
    if (!['/ws/client', '/ws/node'].includes(request.url ?? '')) {
      socket.destroy();
      return;
    }
    wss.handleUpgrade(request, socket, head, (ws) => wss.emit('connection', ws, request));
  });
  wss.on('connection', (socket, request) => {
    const isNode = request.url === '/ws/node';
    let node: NodeRow | undefined;
    let client: Client | undefined;
    let authenticating = false;
    let lastPong = Date.now();
    const helloTimer = setTimeout(
      () => socket.close(1008, 'Hello required'),
      protocolTimings.helloMs,
    );
    const heartbeat = setInterval(() => {
      if (Date.now() - lastPong > protocolTimings.pongTimeoutMs) socket.terminate();
      else if (node || client) send(socket, frame('ping', {}));
    }, protocolTimings.pingMs);
    socket.on('message', (raw) => {
      void receive().catch(() => socket.close(1008, 'Invalid request or credentials'));
      async function receive() {
        const envelope = envelopeSchema.parse(JSON.parse(raw.toString()));
        if (!node && !client) {
          if (envelope.type !== 'hello' || authenticating) throw new Error('Hello required');
          authenticating = true;
          if (isNode) {
            const hello = payloadSchemas.hello.parse(envelope.payload);
            if (!('nodeToken' in hello)) throw new Error('Node token required');
            node = database.nodeByToken(hello.nodeToken);
            if (!node) throw new Error('Unknown node');
            nodes.get(node.node_id)?.close(1000, 'Reconnected');
            nodes.set(node.node_id, socket);
          } else {
            const hello = payloadSchemas.hello.parse(envelope.payload);
            if (!('token' in hello)) throw new Error('User token required');
            const user = await authenticate(hello.token);
            if (socket.readyState !== WebSocket.OPEN) return;
            client = { socket, userId: user.user_id };
            clients.add(client);
          }
          clearTimeout(helloTimer);
          send(socket, frame('hello.ok', {}));
          if (node) broadcast(node.user_id, frame('node.status', { online: true }, node.node_id));
          return;
        }
        if (envelope.type === 'pong') {
          payloadSchemas.pong.parse(envelope.payload);
          lastPong = Date.now();
          return;
        }
        if (client && envelope.type === 'rpc.req') {
          const nodeId = envelope.nodeId!;
          let error: { code: string; message: string } | undefined;
          if (!database.owns(client.userId, nodeId))
            error = { code: 'forbidden', message: 'Node is not yours' };
          else if (!nodes.has(nodeId)) error = { code: 'unavailable', message: 'Node is offline' };
          else if (pending.has(envelope.id))
            error = { code: 'conflict', message: 'Request already pending' };
          if (error) {
            send(socket, {
              ...frame('rpc.res', { ok: false, error }, nodeId),
              replyTo: envelope.id,
            });
            return;
          }
          const timer = setTimeout(() => {
            pending.delete(envelope.id);
            send(socket, {
              ...frame(
                'rpc.res',
                { ok: false, error: { code: 'timeout', message: 'Node request timed out' } },
                nodeId,
              ),
              replyTo: envelope.id,
            });
          }, protocolTimings.rpcTimeoutMs);
          pending.set(envelope.id, { socket, nodeId, timer });
          send(nodes.get(nodeId)!, envelope);
        } else if (node && envelope.type === 'rpc.res') {
          const p = pending.get(envelope.replyTo!);
          if (p?.nodeId === node.node_id) {
            clearTimeout(p.timer);
            pending.delete(envelope.replyTo!);
            send(p.socket, { ...envelope, nodeId: node.node_id });
          }
        } else if (node && ['event', 'live'].includes(envelope.type)) {
          broadcast(node.user_id, { ...envelope, nodeId: node.node_id });
        } else throw new Error('Invalid direction');
      }
    });
    socket.on('close', () => {
      clearTimeout(helloTimer);
      clearInterval(heartbeat);
      if (client) clients.delete(client);
      if (node && nodes.get(node.node_id) === socket) {
        nodes.delete(node.node_id);
        clearPending(node.node_id);
        broadcast(node.user_id, frame('node.status', { online: false }, node.node_id));
      }
      for (const [id, p] of pending)
        if (p.socket === socket) {
          clearTimeout(p.timer);
          pending.delete(id);
        }
    });
    socket.on('error', () => socket.terminate());
  });
  return {
    online: (id: string) => nodes.has(id),
    revoke: (id: string) => nodes.get(id)?.close(1008, 'Node unpaired'),
    close: () => {
      for (const p of pending.values()) clearTimeout(p.timer);
      pending.clear();
      for (const ws of wss.clients) ws.terminate();
      wss.close();
    },
  };
}
