import { useEffect } from 'react';
import {
  envelopeSchema,
  eventSchema,
  liveSchema,
  type RpcMethod,
  type RpcParams,
  type PersistedEvent,
  type LiveEvent,
} from '@nekodot/protocol';
import { cancelRpcRequests, newEnvelope, resolveRpc, rpc } from './api';
import { useAppStore } from './store';

let activeSocket: WebSocket | null = null;
let clientReady = false;
type ConnectionWaiter = {
  resolve(socket: WebSocket): void;
  reject(error: Error): void;
  timeout: number;
};
const connectionWaiters = new Set<ConnectionWaiter>();

function waitForClientSocket() {
  if (clientReady && activeSocket?.readyState === WebSocket.OPEN)
    return Promise.resolve(activeSocket);
  return new Promise<WebSocket>((resolve, reject) => {
    const waiter: ConnectionWaiter = {
      timeout: 0,
      resolve: (socket) => {
        window.clearTimeout(waiter.timeout);
        connectionWaiters.delete(waiter);
        resolve(socket);
      },
      reject: (error) => {
        window.clearTimeout(waiter.timeout);
        connectionWaiters.delete(waiter);
        reject(error);
      },
    };
    waiter.timeout = window.setTimeout(
      () =>
        waiter.reject(
          new Error('Connection is recovering. Your draft is kept; retry after reconnecting.'),
        ),
      30_000,
    );
    connectionWaiters.add(waiter);
  });
}

function setClientReady(socket: WebSocket) {
  if (activeSocket !== socket) return;
  clientReady = true;
  for (const waiter of [...connectionWaiters]) waiter.resolve(socket);
}

function rejectConnectionWaiters(error: Error) {
  for (const waiter of [...connectionWaiters]) waiter.reject(error);
}

export async function callNode<M extends RpcMethod>(method: M, params: RpcParams<M>) {
  const { selectedNodeId } = useAppStore.getState();
  if (!selectedNodeId) throw new Error('Select a computer before sending.');
  const socket = await waitForClientSocket();
  if (socket !== activeSocket || socket.readyState !== WebSocket.OPEN)
    throw new Error('Computer disconnected. Your draft is kept; retry after reconnecting.');
  return rpc(socket, selectedNodeId, method, params);
}

export function loadConversation(conversationId: string) {
  const nodeId = useAppStore.getState().selectedNodeId;
  return callNode('messages.list', { conversationId, limit: 50 }).then(({ messages }) => {
    if (nodeId) useAppStore.getState().setMessages(nodeId, conversationId, messages);
    return messages;
  });
}

export function RelayConnection() {
  const token = useAppStore((state) => state.token);
  const selectedNodeId = useAppStore((state) => state.selectedNodeId);

  useEffect(() => {
    if (!token || !selectedNodeId) return;
    let stopped = false;
    let socket: WebSocket | undefined;
    let timer: number | undefined;
    let reconnectDelay = 1000;
    let syncing = false;
    type Update = { type: 'event'; payload: PersistedEvent } | { type: 'live'; payload: LiveEvent };
    const queue: Update[] = [];

    const handleUpdate = (message: Update) => {
      if (syncing) {
        queue.push(message);
        return;
      }
      if (message.type === 'event')
        useAppStore.getState().applyEvent(selectedNodeId, message.payload);
      else useAppStore.getState().applyLive(selectedNodeId, message.payload);
    };

    const synchronize = async (currentSocket: WebSocket) => {
      if (currentSocket.readyState !== WebSocket.OPEN || syncing) return;
      syncing = true;
      try {
        const store = useAppStore.getState();
        const existing = store.nodes[selectedNodeId];
        if (!existing || existing.seq === 0) {
          const snapshot = await rpc(currentSocket, selectedNodeId, 'sync.snapshot', {});
          useAppStore.getState().setSnapshot(selectedNodeId, snapshot);
        } else {
          const since = await rpc(currentSocket, selectedNodeId, 'sync.since', {
            seq: existing.seq,
          });
          if (since.resyncRequired) {
            const snapshot = await rpc(currentSocket, selectedNodeId, 'sync.snapshot', {});
            useAppStore.getState().setSnapshot(selectedNodeId, snapshot);
          } else {
            for (const event of since.events)
              useAppStore.getState().applyEvent(selectedNodeId, event);
          }
        }
        const current = useAppStore.getState();
        const activeConversation =
          current.selectedConversationId ??
          current.nodes[selectedNodeId]?.conversations[0]?.conversationId;
        if (activeConversation) {
          useAppStore.getState().setSelectedConversation(activeConversation);
          await loadConversation(activeConversation);
        }
        if (activeSocket === currentSocket)
          useAppStore.getState().setNodeOnline(selectedNodeId, true);
        syncing = false;
        const buffered = queue.splice(0);
        for (const update of buffered
          .filter((item) => item.type === 'event')
          .sort((a, b) => a.payload.seq - b.payload.seq))
          handleUpdate(update);
        for (const update of buffered.filter((item) => item.type === 'live')) handleUpdate(update);
      } catch {
        if (activeSocket === currentSocket)
          useAppStore.getState().setNodeOnline(selectedNodeId, false);
      } finally {
        syncing = false;
      }
    };

    const connect = () => {
      if (stopped) return;
      window.clearTimeout(timer);
      const currentSocket = new WebSocket(
        window.location.origin.replace(/^http/, 'ws') + '/ws/client',
      );
      socket = currentSocket;
      activeSocket = currentSocket;
      clientReady = false;
      currentSocket.onopen = () =>
        currentSocket.send(JSON.stringify(newEnvelope('hello', { token })));
      currentSocket.onmessage = (event) => {
        const message = envelopeSchema.parse(JSON.parse(String(event.data)));
        if (message.type === 'ping') {
          currentSocket.send(JSON.stringify(newEnvelope('pong', {})));
        } else if (message.type === 'hello.ok') {
          reconnectDelay = 1000;
          setClientReady(currentSocket);
          void synchronize(currentSocket);
        } else if (message.type === 'rpc.res') {
          if (message.replyTo) resolveRpc(message.replyTo, message.payload);
        } else if (message.type === 'node.status' && message.nodeId === selectedNodeId) {
          const online = (message.payload as { online: boolean }).online;
          useAppStore.getState().setNodeOnline(selectedNodeId, online);
          if (online) void synchronize(currentSocket);
        } else if (
          (message.type === 'event' || message.type === 'live') &&
          message.nodeId === selectedNodeId
        ) {
          handleUpdate(
            message.type === 'event'
              ? { type: 'event', payload: eventSchema.parse(message.payload) }
              : { type: 'live', payload: liveSchema.parse(message.payload) },
          );
        }
      };
      currentSocket.onclose = () => {
        if (activeSocket !== currentSocket) return;
        activeSocket = null;
        clientReady = false;
        cancelRpcRequests();
        if (!stopped) {
          timer = window.setTimeout(connect, reconnectDelay);
          reconnectDelay = Math.min(reconnectDelay * 2, 30_000);
        }
      };
      currentSocket.onerror = () => currentSocket.close();
    };
    const resumeConnection = () => {
      if (document.visibilityState !== 'visible') return;
      if (socket?.readyState === WebSocket.OPEN) {
        reconnectDelay = 1000;
        socket.close(1000, 'Client resumed');
      } else if (socket?.readyState !== WebSocket.CONNECTING) connect();
    };
    connect();
    window.addEventListener('pageshow', resumeConnection);
    window.addEventListener('online', resumeConnection);
    document.addEventListener('visibilitychange', resumeConnection);
    return () => {
      stopped = true;
      window.clearTimeout(timer);
      window.removeEventListener('pageshow', resumeConnection);
      window.removeEventListener('online', resumeConnection);
      document.removeEventListener('visibilitychange', resumeConnection);
      if (activeSocket === socket) {
        activeSocket = null;
        clientReady = false;
      }
      rejectConnectionWaiters(
        new Error('Connection changed. Your draft is kept; retry after reconnecting.'),
      );
      socket?.close();
      cancelRpcRequests();
    };
  }, [token, selectedNodeId]);

  return null;
}
