import { useEffect } from 'react';
import { create } from 'zustand';
import { addPluginListener } from '@tauri-apps/api/core';
import {
  isPermissionGranted,
  requestPermission,
  sendNotification,
  onAction,
} from '@tauri-apps/plugin-notification';
import { type TaskNotification } from '@nekodot/protocol';
import { android, appActive, native, nativeCommand } from '../native';
import { relayRequest } from '../api';
import { relayUrl } from '../relay-url';
import { useAppStore } from '../store';
import { useDrafts } from '../drafts';
import zh from '../i18n/zh';
import en from '../i18n/en';
import type { Texts } from '../shared';

interface Destination {
  nodeId: string;
  conversationId: string;
}
const state = create<{ enabled: boolean; error: string }>(() => ({ enabled: false, error: '' }));
const seen = new Set<string>();
let deviceId = localStorage.getItem('nekodot-device');
if (!deviceId) {
  deviceId = crypto.randomUUID();
  localStorage.setItem('nekodot-device', deviceId);
}
let pendingDestination: Destination | undefined;

function navigate(destination: Destination) {
  const store = useAppStore.getState();
  if (!store.me) {
    pendingDestination = destination;
    return;
  }
  if (!store.me.nodes.some((node) => node.nodeId === destination.nodeId)) return;
  store.setSelectedNode(destination.nodeId);
  store.setSelectedConversation(destination.conversationId);
  store.setScreen('home');
}
export async function showTaskNotification(signal: TaskNotification & Destination) {
  if (!native || seen.has(signal.notificationId)) return;
  seen.add(signal.notificationId);
  const store = useAppStore.getState();
  if (
    !store.token ||
    (appActive() &&
      document.hasFocus() &&
      store.screen === 'home' &&
      store.selectedNodeId === signal.nodeId &&
      store.selectedConversationId === signal.conversationId)
  )
    return;
  if (!state.getState().enabled) return;
  const t = store.language === 'zh' ? zh : en;
  const body = {
    approval: t.notificationApproval,
    completed: t.notificationCompleted,
    failed: t.notificationFailed,
  }[signal.kind];
  sendNotification({
    title: 'nekodot',
    body,
    channelId: 'nekodot_tasks',
    extra: { nodeId: signal.nodeId, conversationId: signal.conversationId },
  });
}
async function registerDevice() {
  if (!native || !useAppStore.getState().token) return;
  if (!(await isPermissionGranted())) {
    state.setState({ enabled: false });
    return;
  }
  if (android) {
    const status = await relayRequest<{ available: boolean; reason?: string }>(
      '/notifications/status',
    );
    if (!status.available) throw new Error(status.reason);
    const { token } = await nativeCommand<{ token: string }>('push_token');
    await relayRequest('/devices', {
      method: 'POST',
      body: JSON.stringify({ deviceId, token, platform: 'android' }),
    });
  }
  state.setState({ enabled: true, error: '' });
}
export function ClientNotifications() {
  const token = useAppStore((s) => s.token);
  const me = useAppStore((s) => s.me);
  const nodeId = useAppStore((s) => s.selectedNodeId);
  const conversationId = useAppStore((s) => s.selectedConversationId);
  useEffect(() => {
    if (!native || !token) return;
    const register = () => {
      void registerDevice().catch((e: Error) =>
        state.setState({ enabled: false, error: e.message }),
      );
    };
    register();
    window.addEventListener('nekodot:resume', register);
    return () => {
      window.removeEventListener('nekodot:resume', register);
    };
  }, [token]);
  useEffect(() => {
    if (!android) return;
    void nativeCommand('focus_conversation', {
      nodeId: token ? nodeId : null,
      conversationId: token ? conversationId : null,
    });
  }, [nodeId, conversationId, token]);
  useEffect(() => {
    if (me && pendingDestination) {
      const target = pendingDestination;
      pendingDestination = undefined;
      navigate(target);
    }
  }, [me]);
  useEffect(() => {
    if (!native) return;
    let disposed = false;
    const cleanups: (() => void)[] = [];
    async function setup() {
      if (android) {
        for (const [event, handler] of [
          [
            'notification',
            (signal: TaskNotification & Destination) => {
              void showTaskNotification(signal);
            },
          ],
          ['notificationClick', navigate],
          [
            'token',
            () => {
              void registerDevice().catch((e: Error) =>
                state.setState({ error: e.message, enabled: false }),
              );
            },
          ],
        ] as const) {
          const listener = await addPluginListener('nekodot', event, handler);
          if (disposed) void listener.unregister();
          else
            cleanups.push(() => {
              void listener.unregister();
            });
        }
        const target = await nativeCommand<Partial<Destination>>('take_notification');
        if (target.nodeId && target.conversationId) navigate(target as Destination);
      }
      const unlisten = await onAction((action) => {
        const extra = action.notification?.extra as Partial<Destination> | undefined;
        if (extra?.nodeId && extra.conversationId) navigate(extra as Destination);
      });
      if (disposed) void unlisten.unregister();
      else
        cleanups.push(() => {
          void unlisten.unregister();
        });
    }
    void setup().catch((e: Error) => state.setState({ error: e.message }));
    return () => {
      disposed = true;
      cleanups.forEach((cleanup) => cleanup());
    };
  }, []);
  useEffect(
    () =>
      useAppStore.subscribe((current, previous) => {
        if (previous.token && !current.token) {
          useDrafts.getState().clear();
          seen.clear();
          state.setState({ enabled: false });
          if (android) {
            void fetch(relayUrl('/api/devices/' + deviceId), {
              method: 'DELETE',
              headers: { Authorization: 'Bearer ' + previous.token },
            });
            void nativeCommand('clear_push_token');
          }
        }
      }),
    [],
  );
  return null;
}
export function NotificationSettings({ t }: { t: Texts }) {
  const enabled = state((s) => s.enabled);
  const error = state((s) => s.error);
  if (!native) return null;
  async function enable() {
    try {
      if (!(await isPermissionGranted()) && (await requestPermission()) !== 'granted')
        throw new Error(t.notificationUnavailable);
      await registerDevice();
    } catch (e) {
      state.setState({ error: e instanceof Error ? e.message : t.notificationUnavailable });
    }
  }
  return (
    <section className="settings-card">
      <h2>{t.notifications}</h2>
      <p>{enabled ? t.notificationEnabled : t.notificationUnavailable}</p>
      <button className="secondary-button" onClick={() => void enable()}>
        {t.enableNotifications}
      </button>
      {error && (
        <p role="alert" className="form-error">
          {error}
        </p>
      )}
    </section>
  );
}
