import { randomBytes, randomUUID } from 'node:crypto';
import type { FastifyInstance, FastifyRequest } from 'fastify';
import { WebSocket, WebSocketServer } from 'ws';
import { tunnelRequestSchema, tunnelNodeHelloSchema, type TunnelTicket } from '@nekodot/protocol';
import { HttpFault } from './auth';
import type { RelayDatabase } from './database';
import type { registerRouting } from './routing';

interface ScreenSession {
  userId: string;
  authSessionId?: string;
  nodeId: string;
  botId: string;
  tunnelId?: string;
}
interface Tunnel {
  sessionId: string;
  client: WebSocket;
  node?: WebSocket;
  timer: ReturnType<typeof setTimeout>;
}

/** Authenticated byte forwarding. The native Hermes endpoint owns RFB and control. */
export function registerTunnels(
  app: FastifyInstance,
  database: RelayDatabase,
  authenticate: (request: FastifyRequest) => Promise<{ user_id: string; session_id?: string }>,
  routing: ReturnType<typeof registerRouting>,
) {
  const wss = new WebSocketServer({ noServer: true });
  const sessions = new Map<string, ScreenSession>();
  const tickets = new Map<string, { sessionId: string; timer: ReturnType<typeof setTimeout> }>();
  const tunnels = new Map<string, Tunnel>();
  function closeNode(nodeId: string) {
    for (const [id, session] of sessions) {
      if (session.nodeId !== nodeId) continue;
      const tunnel = session.tunnelId ? tunnels.get(session.tunnelId) : undefined;
      tunnel?.client.terminate();
      tunnel?.node?.terminate();
      session.tunnelId = undefined;
      // A broken node transport does not invalidate its native viewer identity.
      if (!database.owns(session.userId, nodeId)) sessions.delete(id);
    }
  }
  routing.offlineListeners.add(closeNode);
  app.post('/api/tunnels', async (request): Promise<TunnelTicket> => {
    const user = await authenticate(request);
    const parsed = tunnelRequestSchema.safeParse(request.body);
    if (!parsed.success) throw new HttpFault('invalid_params', 'Invalid screen request');
    const { nodeId, botId } = parsed.data;
    if (!database.owns(user.user_id, nodeId))
      throw new HttpFault('forbidden', 'Node is not yours', 403);
    if (!routing.online(nodeId)) throw new HttpFault('unavailable', 'Node is offline', 503);
    const sessionId = parsed.data.sessionId ?? randomUUID();
    const session = sessions.get(sessionId);
    if (
      parsed.data.sessionId &&
      (!session ||
        session.userId !== user.user_id ||
        session.nodeId !== nodeId ||
        session.botId !== botId)
    )
      throw new HttpFault('conflict', 'Screen session expired. Open a new viewer.', 409);
    if (session) session.authSessionId = user.session_id;
    if (!session)
      sessions.set(sessionId, {
        userId: user.user_id,
        authSessionId: user.session_id,
        nodeId,
        botId,
      });
    const ticket = randomBytes(32).toString('base64url');
    const timer = setTimeout(() => {
      tickets.delete(ticket);
      if (!sessions.get(sessionId)?.tunnelId) sessions.delete(sessionId);
    }, 60_000);
    timer.unref();
    tickets.set(ticket, { sessionId, timer });
    return { sessionId, ticket, expiresAt: new Date(Date.now() + 60_000).toISOString() };
  });
  app.server.on('upgrade', (request, socket, head) => {
    const url = new URL(request.url ?? '/', 'http://localhost');
    if (url.pathname !== '/ws/tunnel' && url.pathname !== '/ws/tunnel-node') return;
    if (url.pathname === '/ws/tunnel') {
      const ticket = url.searchParams.get('ticket') ?? '';
      const entry = tickets.get(ticket);
      if (!entry) {
        socket.destroy();
        return;
      }
      clearTimeout(entry.timer);
      tickets.delete(ticket);
      const session = sessions.get(entry.sessionId);
      if (
        !session ||
        (session.authSessionId && !database.session(session.authSessionId, session.userId)) ||
        !database.owns(session.userId, session.nodeId) ||
        !routing.online(session.nodeId)
      ) {
        socket.destroy();
        return;
      }
      wss.handleUpgrade(request, socket, head, (client) => {
        const old = session.tunnelId ? tunnels.get(session.tunnelId) : undefined;
        old?.client.terminate();
        old?.node?.terminate();
        const tunnelId = randomUUID();
        const timer = setTimeout(
          () => client.close(1011, 'Node screen connection timed out'),
          30_000,
        );
        const tunnel: Tunnel = { sessionId: entry.sessionId, client, timer };
        tunnels.set(tunnelId, tunnel);
        session.tunnelId = tunnelId;
        client.pause();
        client.on('error', () => client.terminate());
        client.on('close', (code, reason) => {
          clearTimeout(timer);
          tunnels.delete(tunnelId);
          if (code === 1000 || code === 1001) {
            tunnel.node?.close(code, reason.toString());
            if (session.tunnelId === tunnelId) sessions.delete(entry.sessionId);
          } else tunnel.node?.terminate();
        });
        routing.notifyNode(session.nodeId, 'tunnel.open', {
          tunnelId,
          sessionId: entry.sessionId,
          botId: session.botId,
        });
      });
    } else {
      wss.handleUpgrade(request, socket, head, (node) => {
        const helloTimer = setTimeout(() => node.close(1008, 'Hello required'), 5000);
        node.on('error', () => node.terminate());
        node.once('close', () => clearTimeout(helloTimer));
        node.once('message', (raw, binary) => {
          const parsed = !binary
            ? tunnelNodeHelloSchema.safeParse(parseJson(raw.toString()))
            : undefined;
          const tunnel = parsed?.success ? tunnels.get(parsed.data.tunnelId) : undefined;
          const session = tunnel ? sessions.get(tunnel.sessionId) : undefined;
          const owner = parsed?.success ? database.nodeByToken(parsed.data.nodeToken) : undefined;
          if (!tunnel || !session || owner?.node_id !== session.nodeId || tunnel.node) {
            node.close(1008, 'Invalid tunnel credentials');
            return;
          }
          clearTimeout(helloTimer);
          clearTimeout(tunnel.timer);
          tunnel.node = node;
          const { client } = tunnel;
          for (const [from, to] of [
            [client, node],
            [node, client],
          ] as const) {
            from.on('message', (data, isBinary) => {
              if (!isBinary) {
                from.close(1003, 'Screen frames must be binary');
                return;
              }
              if (to.readyState !== WebSocket.OPEN) return;
              from.pause();
              to.send(data, { binary: true }, () => from.resume());
            });
          }
          node.on('close', (code, reason) => {
            if (code === 1005 || code === 1006) client.terminate();
            else client.close(code, reason.toString());
          });
          client.resume();
        });
      });
    }
  });
  const sessionCheck = setInterval(() => {
    for (const [id, session] of sessions) {
      if (!session.authSessionId || database.session(session.authSessionId, session.userId))
        continue;
      const tunnel = session.tunnelId ? tunnels.get(session.tunnelId) : undefined;
      tunnel?.client.close(4401, 'Session expired');
      tunnel?.node?.close(4401, 'Session expired');
      sessions.delete(id);
    }
  }, 25_000);
  sessionCheck.unref();
  return {
    revokeUser(userId: string, authSessionId?: string) {
      for (const [id, session] of sessions) {
        if (session.userId !== userId || (authSessionId && session.authSessionId !== authSessionId))
          continue;
        const tunnel = session.tunnelId ? tunnels.get(session.tunnelId) : undefined;
        tunnel?.client.close(4401, 'Session revoked');
        tunnel?.node?.close(4401, 'Session revoked');
        sessions.delete(id);
      }
    },
    close() {
      clearInterval(sessionCheck);
      routing.offlineListeners.delete(closeNode);
      for (const entry of tickets.values()) clearTimeout(entry.timer);
      for (const tunnel of tunnels.values()) {
        clearTimeout(tunnel.timer);
        tunnel.client.terminate();
        tunnel.node?.terminate();
      }
      for (const socket of wss.clients) socket.terminate();
      tickets.clear();
      sessions.clear();
      tunnels.clear();
      wss.close();
    },
  };
}

function parseJson(raw: string): unknown {
  try {
    return JSON.parse(raw);
  } catch {
    return undefined;
  }
}
