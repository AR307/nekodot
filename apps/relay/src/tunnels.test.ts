import { seedVerifiedAccount } from '../../../tests/support/account';
import { once } from 'node:events';
import { mkdtemp } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { randomUUID } from 'node:crypto';
import { expect, it } from 'vitest';
import { WebSocket } from 'ws';
import type { Envelope, TunnelOpen, TunnelTicket } from '@nekodot/protocol';
import { createRelay } from './server';

it('opens owner-only single-use screen tickets, forwards bytes and preserves native close semantics', async () => {
  const relay = await createRelay({
    dataDir: await mkdtemp(join(tmpdir(), 'nekodot-screen-relay-')),
    jwtSecret: 'screen-test-secret',
    publicUrl: 'http://127.0.0.1',
  });
  await seedVerifiedAccount(relay.database, 'screen@example.test', 'screen-test-password');
  await seedVerifiedAccount(relay.database, 'other@example.test', 'screen-test-password');
  const base = await relay.app.listen({ host: '127.0.0.1', port: 0 });
  const wsBase = base.replace('http', 'ws');
  const sockets: WebSocket[] = [];
  const post = (url: string, payload: unknown, token?: string) =>
    relay.app.inject({
      method: 'POST',
      url,
      payload: JSON.stringify(payload),
      headers: {
        'content-type': 'application/json',
        ...(token ? { authorization: 'Bearer ' + token } : {}),
      },
    });
  const open = async (path: string) => {
    const socket = new WebSocket(wsBase + path);
    sockets.push(socket);
    await once(socket, 'open');
    return socket;
  };
  try {
    const auth = await post('/api/auth/login', {
      email: 'screen@example.test',
      password: 'screen-test-password',
    });
    const other = await post('/api/auth/login', {
      email: 'other@example.test',
      password: 'screen-test-password',
    });
    const token = auth.json().token as string;
    const code = await post('/api/pairing-codes', {}, token);
    const credentials = (
      await post('/api/pair', {
        code: code.json().code,
        nodeName: 'Screen Linux',
        platform: 'linux',
      })
    ).json() as { nodeId: string; nodeToken: string };
    const request = { nodeId: credentials.nodeId, botId: 'nk-abc234', kind: 'vnc' };
    expect((await post('/api/tunnels', request)).statusCode).toBe(401);
    expect((await post('/api/tunnels', request, other.json().token)).statusCode).toBe(403);
    expect((await post('/api/tunnels', request, token)).statusCode).toBe(503);
    let node = await open('/ws/node');
    let response = once(node, 'message');
    node.send(
      JSON.stringify({
        v: 1,
        id: randomUUID(),
        type: 'hello',
        payload: { nodeToken: credentials.nodeToken, version: 'test' },
      }),
    );
    expect(JSON.parse(String((await response)[0])).type).toBe('hello.ok');

    const ticket = (await post('/api/tunnels', request, token)).json() as TunnelTicket;
    expect(Date.parse(ticket.expiresAt) - Date.now()).toBeGreaterThan(59_000);
    response = once(node, 'message');
    const viewer = await open('/ws/tunnel?ticket=' + ticket.ticket);
    const notification = JSON.parse(String((await response)[0])) as Envelope;
    expect(notification.type).toBe('tunnel.open');
    const payload = notification.payload as TunnelOpen;
    expect(payload).toMatchObject({ botId: request.botId, sessionId: ticket.sessionId });
    const bridge = await open('/ws/tunnel-node');
    bridge.send(JSON.stringify({ tunnelId: payload.tunnelId, nodeToken: credentials.nodeToken }));
    const fromNode = once(viewer, 'message');
    bridge.send(Buffer.from('RFB 003.008\n'));
    expect(Buffer.from((await fromNode)[0]).toString()).toBe('RFB 003.008\n');
    const fromViewer = once(bridge, 'message');
    viewer.send(Buffer.from([5, 1, 2, 3]));
    expect(Buffer.from((await fromViewer)[0])).toEqual(Buffer.from([5, 1, 2, 3]));
    const replay = new WebSocket(wsBase + '/ws/tunnel?ticket=' + ticket.ticket);
    sockets.push(replay);
    expect(
      await new Promise<string>((resolve) => replay.once('error', (e) => resolve(e.message))),
    ).toContain('socket hang up');

    const evicted = once(viewer, 'close');
    bridge.close(4000, 'control-taken');
    expect((await evicted)[0]).toBe(4000);
    const reconnect = (
      await post('/api/tunnels', { ...request, sessionId: ticket.sessionId }, token)
    ).json() as TunnelTicket;
    response = once(node, 'message');
    const again = await open('/ws/tunnel?ticket=' + reconnect.ticket);
    const next = (JSON.parse(String((await response)[0])) as Envelope).payload as TunnelOpen;
    const nextBridge = await open('/ws/tunnel-node');
    nextBridge.send(JSON.stringify({ tunnelId: next.tunnelId, nodeToken: credentials.nodeToken }));
    const ready = once(again, 'message');
    nextBridge.send(Buffer.from('RFB'));
    await ready;
    const clean = once(nextBridge, 'close');
    again.close(1000, 'Viewer closed');
    expect((await clean)[0]).toBe(1000);
    expect(
      (await post('/api/tunnels', { ...request, sessionId: ticket.sessionId }, token)).statusCode,
    ).toBe(409);

    const finalTicket = (await post('/api/tunnels', request, token)).json() as TunnelTicket;
    response = once(node, 'message');
    const finalViewer = await open('/ws/tunnel?ticket=' + finalTicket.ticket);
    const finalPayload = (JSON.parse(String((await response)[0])) as Envelope)
      .payload as TunnelOpen;
    const finalBridge = await open('/ws/tunnel-node');
    finalBridge.send(
      JSON.stringify({ tunnelId: finalPayload.tunnelId, nodeToken: credentials.nodeToken }),
    );
    const finalReady = once(finalViewer, 'message');
    finalBridge.send(Buffer.from('RFB'));
    await finalReady;
    const broken = once(finalBridge, 'close');
    finalViewer.terminate();
    expect((await broken)[0]).toBe(1006);
    expect(
      (await post('/api/tunnels', { ...request, sessionId: finalTicket.sessionId }, token))
        .statusCode,
    ).toBe(200);
    node.terminate();
    await expect
      .poll(async () => (await post('/api/tunnels', request, token)).statusCode)
      .toBe(503);
    node = await open('/ws/node');
    response = once(node, 'message');
    node.send(
      JSON.stringify({
        v: 1,
        id: randomUUID(),
        type: 'hello',
        payload: { nodeToken: credentials.nodeToken, version: 'test' },
      }),
    );
    await response;
    expect(
      (await post('/api/tunnels', { ...request, sessionId: finalTicket.sessionId }, token)).json()
        .sessionId,
    ).toBe(finalTicket.sessionId);

    const logoutTicket = (await post('/api/tunnels', request, token)).json() as TunnelTicket;
    response = once(node, 'message');
    const logoutViewer = await open('/ws/tunnel?ticket=' + logoutTicket.ticket);
    const logoutPayload = (JSON.parse(String((await response)[0])) as Envelope)
      .payload as TunnelOpen;
    const logoutBridge = await open('/ws/tunnel-node');
    logoutBridge.send(
      JSON.stringify({ tunnelId: logoutPayload.tunnelId, nodeToken: credentials.nodeToken }),
    );
    const logoutReady = once(logoutViewer, 'message');
    logoutBridge.send(Buffer.from('RFB'));
    await logoutReady;
    const staleTicket = (await post('/api/tunnels', request, token)).json() as TunnelTicket;
    const viewerClosed = once(logoutViewer, 'close');
    const bridgeClosed = once(logoutBridge, 'close');
    expect((await post('/api/auth/logout', {}, token)).statusCode).toBe(200);
    expect((await viewerClosed)[0]).toBe(4401);
    expect((await bridgeClosed)[0]).toBe(4401);
    const staleViewer = new WebSocket(wsBase + '/ws/tunnel?ticket=' + staleTicket.ticket);
    sockets.push(staleViewer);
    expect(
      await new Promise<string>((resolve) => staleViewer.once('error', (e) => resolve(e.message))),
    ).toContain('socket hang up');
    const replacement = (
      await post('/api/auth/login', {
        email: 'screen@example.test',
        password: 'screen-test-password',
      })
    ).json().token as string;
    const revoked = once(node, 'close');
    await relay.app.inject({
      method: 'DELETE',
      url: '/api/nodes/' + credentials.nodeId,
      headers: { authorization: 'Bearer ' + replacement },
    });
    await revoked;
    expect((await post('/api/tunnels', request, replacement)).statusCode).toBe(403);
  } finally {
    for (const socket of sockets) socket.terminate();
    await relay.app.close();
  }
});
