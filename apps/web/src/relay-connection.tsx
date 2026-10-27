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

const relayUrl = (
  localStorage.getItem('nekodot-relay-url') ??
  import.meta.env.VITE_RELAY_URL ??
  window.location.origin
).replace(/\/$/, '');
let activeSocket: WebSocket | null = null;

export function callNode<M extends RpcMethod>(method: M, params: RpcParams<M>) {
  const { selectedNodeId } = useAppStore.getState();
  if (!activeSocket || activeSocket.readyState !== WebSocket.OPEN || !selectedNodeId)
    return Promise.reject(new Error('Computer is not connected'));
  return rpc(activeSocket, selectedNodeId, method, params);
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

    const synchronize = async () => {
      if (!socket || syncing) return;
      syncing = true;
      try {
        const store = useAppStore.getState();
        const existing = store.nodes[selectedNodeId];
        if (!existing || existing.seq === 0) {
          const snapshot = await rpc(socket, selectedNodeId, 'sync.snapshot', {});
          useAppStore.getState().setSnapshot(selectedNodeId, snapshot);
        } else {
          const since = await rpc(socket, selectedNodeId, 'sync.since', { seq: existing.seq });
          if (since.resyncRequired) {
            const snapshot = await rpc(socket, selectedNodeId, 'sync.snapshot', {});
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
        syncing = false;
        const buffered = queue.splice(0);
        for (const update of buffered
          .filter((item) => item.type === 'event')
          .sort((a, b) => a.payload.seq - b.payload.seq))
          handleUpdate(update);
        for (const update of buffered.filter((item) => item.type === 'live')) handleUpdate(update);
      } catch {
        useAppStore.getState().setNodeOnline(selectedNodeId, false);
      } finally {
        syncing = false;
      }
    };

    const connect = () => {
      if (stopped) return;
      socket = new WebSocket(relayUrl.replace(/^http/, 'ws') + '/ws/client');
      activeSocket = socket;
      socket.onopen = () => socket?.send(JSON.stringify(newEnvelope('hello', { token })));
      socket.onmessage = (event) => {
        const message = envelopeSchema.parse(JSON.parse(String(event.data)));
        if (message.type === 'ping') {
          socket?.send(JSON.stringify(newEnvelope('pong', {})));
        } else if (message.type === 'hello.ok') {
          reconnectDelay = 1000;
          void synchronize();
        } else if (message.type === 'rpc.res') {
          if (message.replyTo) resolveRpc(message.replyTo, message.payload);
        } else if (message.type === 'node.status' && message.nodeId === selectedNodeId) {
          const online = (message.payload as { online: boolean }).online;
          useAppStore.getState().setNodeOnline(selectedNodeId, online);
          if (online) void synchronize();
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
      socket.onclose = () => {
        useAppStore.getState().setNodeOnline(selectedNodeId, false);
        if (activeSocket === socket) activeSocket = null;
        cancelRpcRequests();
        if (!stopped) {
          timer = window.setTimeout(connect, reconnectDelay);
          reconnectDelay = Math.min(reconnectDelay * 2, 30_000);
        }
      };
      socket.onerror = () => socket?.close();
    };
    connect();
    return () => {
      stopped = true;
      window.clearTimeout(timer);
      if (activeSocket === socket) activeSocket = null;
      socket?.close();
      cancelRpcRequests();
    };
  }, [token, selectedNodeId]);

  return null;
}
