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
  const [bootError, setBootError] = useState('');
  const [dark, setDark] = useState(localStorage.getItem('nekodot-theme') === 'dark');
  const t: Texts = language === 'zh' ? zh : en;

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
        else setBootError(t.relayUnavailable);
      })
      .finally(() => {
        if (!cancelled) setLoadedToken(token);
      });
    return () => {
      cancelled = true;
    };
  }, [token, setMe, setScreen, setSelectedNode, setToken, t.relayUnavailable]);

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
            <p role="alert">{bootError}</p>
            <button className="secondary-button" onClick={() => location.reload()}>
              {t.retry}
            </button>
          </>
        ) : (
          <SpinnerDots />
        )}
      </div>
    );
  const selectedNode = me.nodes.find((node) => node.nodeId === selectedNodeId);
  const showPair = screen === 'pair' || me.nodes.length === 0;
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
          nodeName={selectedNode?.name ?? t.chooseNode}
          onLanguage={() => setLanguage(language === 'zh' ? 'en' : 'zh')}
        />
      )}
    </div>
  );
}
