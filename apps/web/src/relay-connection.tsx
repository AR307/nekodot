import { useEffect } from 'react';
import {
  envelopeSchema,
  eventSchema,
  liveSchema,
  notificationSchema,
  type RpcMethod,
  type RpcParams,
  type PersistedEvent,
  type LiveEvent,
} from '@nekodot/protocol';
import { cancelRpcRequests, fetchMe, newEnvelope, resolveRpc, rpc } from './api';
import { useAppStore } from './store';
import { relaySocketUrl } from './relay-url';
import { showTaskNotification } from './features/notifications';
import { android, appActive } from './native';

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

/** Fetch the newest few messages of conversations not loaded yet, for list previews. */
function loadPreviews(nodeId: string) {
  const node = useAppStore.getState().nodes[nodeId];
  for (const conversation of node?.conversations ?? []) {
    if (node?.messages[conversation.conversationId]?.length) continue;
    void callNode('messages.list', { conversationId: conversation.conversationId, limit: 6 })
      .then(({ messages }) =>
        useAppStore.getState().setMessages(nodeId, conversation.conversationId, messages),
      )
      .catch(() => {
        // Previews are decorative; the conversation loads in full when opened.
      });
  }
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

    const refreshMe = () => {
      void fetchMe()
        .then((me) => {
          if (!stopped && useAppStore.getState().token === token) useAppStore.getState().setMe(me);
        })
        .catch(() => console.warn('Could not refresh computer information from Relay'));
    };

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
        loadPreviews(selectedNodeId);
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
      const currentSocket = new WebSocket(relaySocketUrl('/ws/client'));
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
          useAppStore.getState().setSocketReady(true);
          refreshMe();
          void synchronize(currentSocket);
        } else if (message.type === 'notify' && message.nodeId) {
          void showTaskNotification({
            ...notificationSchema.parse(message.payload),
            nodeId: message.nodeId,
          });
        } else if (message.type === 'rpc.res') {
          if (message.replyTo) resolveRpc(message.replyTo, message.payload);
        } else if (message.type === 'node.status' && message.nodeId) {
          const online = (message.payload as { online: boolean }).online;
          useAppStore.getState().setNodeOnline(message.nodeId, online);
          if (online) {
            refreshMe();
            if (message.nodeId === selectedNodeId) void synchronize(currentSocket);
          }
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
      currentSocket.onclose = (event) => {
        if (activeSocket !== currentSocket) return;
        activeSocket = null;
        clientReady = false;
        useAppStore.getState().setSocketReady(false);
        cancelRpcRequests();
        if (event.code === 4401) {
          useAppStore.getState().setToken(null);
          return;
        }
        if (!stopped && (!android || appActive())) {
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
    const pauseConnection = () => {
      if (android) {
        window.clearTimeout(timer);
        socket?.close(4002, 'App backgrounded');
      }
    };
    connect();
    window.addEventListener('pageshow', resumeConnection);
    window.addEventListener('online', resumeConnection);
    window.addEventListener('nekodot:pause', pauseConnection);
    document.addEventListener('visibilitychange', resumeConnection);
    return () => {
      stopped = true;
      window.clearTimeout(timer);
      window.removeEventListener('pageshow', resumeConnection);
      window.removeEventListener('online', resumeConnection);
      window.removeEventListener('nekodot:pause', pauseConnection);
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
