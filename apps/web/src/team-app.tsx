import { useEffect, useState } from 'react';
import zh from './i18n/zh';
import en from './i18n/en';
import { fetchMe, relayRequest } from './api';
import { RelayConnection } from './relay-connection';
import { useAppStore } from './store';
import { SpinnerDots, Wordmark } from './ui';
import type { Texts } from './shared';
import { AuthPage } from './features/auth';
import { PairScreen } from './features/pairing';
import { SettingsPage } from './features/settings';
import { TeamPage } from './features/team';
import { backgroundApp, clientLifecycle, native } from './native';
import { remoteZh, remoteEn } from './i18n/client-copy';

const nativeTexts = { zh: { ...zh, ...remoteZh }, en: { ...en, ...remoteEn } };

export function App() {
  const token = useAppStore((state) => state.token);
  const language = useAppStore((state) => state.language);
  const me = useAppStore((state) => state.me);
  const screen = useAppStore((state) => state.screen);
  const selectedNodeId = useAppStore((state) => state.selectedNodeId);
  const setToken = useAppStore((state) => state.setToken);
  const setMe = useAppStore((state) => state.setMe);
  const setScreen = useAppStore((state) => state.setScreen);
  const setSelectedNode = useAppStore((state) => state.setSelectedNode);
  const setLanguage = useAppStore((state) => state.setLanguage);
  const [loadedToken, setLoadedToken] = useState(token ? '' : null);
  const [bootError, setBootError] = useState(false);
  const [dark, setDark] = useState(localStorage.getItem('nekodot-theme') === 'dark');
  const t: Texts = native ? nativeTexts[language] : language === 'zh' ? zh : en;
  useEffect(() => {
    let disposed = false;
    let cleanup: (() => void) | undefined;
    void clientLifecycle().then((value) => {
      if (disposed) value();
      else cleanup = value;
    });
    const back = () => {
      const state = useAppStore.getState();
      if (state.screen !== 'home') state.setScreen('home');
      else if (state.selectedConversationId) state.setSelectedConversation(null);
      else void backgroundApp();
    };
    window.addEventListener('nekodot:back', back);
    return () => {
      disposed = true;
      cleanup?.();
      window.removeEventListener('nekodot:back', back);
    };
  }, []);

  useEffect(() => {
    document.documentElement.lang = language;
  }, [language]);

  useEffect(() => {
    document.documentElement.dataset.theme = dark ? 'dark' : 'light';
    localStorage.setItem('nekodot-theme', dark ? 'dark' : 'light');
  }, [dark]);

  useEffect(() => {
    if (!token) return;
    let cancelled = false;
    relayRequest<Awaited<ReturnType<typeof fetchMe>>>('/me')
      .then((value) => {
        if (cancelled) return;
        setMe(value);
        value.nodes.forEach((node) =>
          useAppStore.getState().setNodeOnline(node.nodeId, node.online),
        );
        const savedNode = useAppStore.getState().selectedNodeId;
        if (!value.nodes.some((node) => node.nodeId === savedNode && node.online))
          setSelectedNode(
            value.nodes.find((node) => node.online)?.nodeId ?? value.nodes[0]?.nodeId ?? null,
          );
        if (!value.nodes.length) setScreen('pair');
      })
      .catch((reason: unknown) => {
        if (cancelled) return;
        if (reason instanceof Error && 'status' in reason && reason.status === 401) setToken(null);
        else setBootError(true);
      })
      .finally(() => {
        if (!cancelled) setLoadedToken(token);
      });
    return () => {
      cancelled = true;
    };
  }, [token, setMe, setScreen, setSelectedNode, setToken]);

  if (!token)
    return (
      <AuthPage
        t={t}
        language={language}
        onToggleLanguage={() => setLanguage(language === 'zh' ? 'en' : 'zh')}
      />
    );
  if (!me || loadedToken !== token)
    return (
      <div className="boot-screen">
        <Wordmark />
        {bootError ? (
          <>
            <p role="alert">{t.relayUnavailable}</p>
            <button className="secondary-button" onClick={() => location.reload()}>
              {t.retry}
            </button>
          </>
        ) : (
          <SpinnerDots />
        )}
      </div>
    );
  const showPair = screen === 'pair';
  return (
    <div className="app-shell" data-theme={dark ? 'dark' : 'light'}>
      <RelayConnection />
      {showPair ? (
        <PairScreen
          t={t}
          onBack={() => setScreen('home')}
          onLanguage={() => setLanguage(language === 'zh' ? 'en' : 'zh')}
        />
      ) : screen === 'settings' ? (
        <SettingsPage
          key={selectedNodeId}
          t={t}
          dark={dark}
          setDark={setDark}
          onHome={() => setScreen('home')}
          onLanguage={() => setLanguage(language === 'zh' ? 'en' : 'zh')}
        />
      ) : (
        <TeamPage
          key={selectedNodeId}
          t={t}
          onLanguage={() => setLanguage(language === 'zh' ? 'en' : 'zh')}
        />
      )}
    </div>
  );
}
