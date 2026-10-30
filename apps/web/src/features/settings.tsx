import { useState, type ReactNode } from 'react';
import { AnimatePresence, motion, useReducedMotion } from 'motion/react';

import { fetchMe, relayRequest } from '../api';

import { useAppStore } from '../store';
import { Icon, StatusDot, ease } from '../ui';
import type { Texts } from '../shared';
import { ProviderSettings } from './providers';
import { NotificationSettings } from './notifications';
import { writeClipboard } from '../native';

export function SettingsPage({
  t,
  dark,
  setDark,
  onHome,
  onLanguage,
}: {
  t: Texts;
  dark: boolean;
  setDark(value: boolean): void;
  onHome(): void;
  onLanguage(): void;
}) {
  const me = useAppStore((state) => state.me);
  const setToken = useAppStore((state) => state.setToken);
  const selectedNodeId = useAppStore((state) => state.selectedNodeId);
  const [error, setError] = useState('');
  const [nodeError, setNodeError] = useState('');
  const [copied, setCopied] = useState('');
  const [confirmArchive, setConfirmArchive] = useState<string | null>(null);
  const reduceMotion = useReducedMotion();
  async function createPairing() {
    setNodeError('');
    try {
      const result = await relayRequest<{
        code: string;
        expiresAt: string;
        installCommand: string;
      }>('/pairing-codes', { method: 'POST', body: '{}' });
      useAppStore.getState().setPairing(result);
      useAppStore.getState().setScreen('pair');
    } catch (reason) {
      setNodeError(reason instanceof Error ? reason.message : t.saveError);
    }
  }

  async function unpair(nodeId: string) {
    try {
      await relayRequest<Record<string, never>>('/nodes/' + nodeId, { method: 'DELETE' });
      const next = await fetchMe();
      useAppStore.getState().setMe(next);
      if (selectedNodeId === nodeId)
        useAppStore.getState().setSelectedNode(next.nodes[0]?.nodeId ?? null);
      setConfirmArchive(null);
    } catch (reason) {
      setNodeError(reason instanceof Error ? reason.message : t.saveError);
    }
  }

  return (
    <main className="settings-page">
      <header className="page-top">
        <button className="icon-button" onClick={onHome} aria-label={t.home}>
          <Icon name="back" />
        </button>
        <span className="page-top-spacer" />
        <button className="quiet-button language-button" onClick={onLanguage}>
          <Icon name="globe" />
          {t.language}
        </button>
      </header>
      <motion.div
        className="settings-body"
        initial={reduceMotion ? false : { opacity: 0, y: 10 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ duration: 0.32, ease }}
      >
        <h1>{t.settingsTitle}</h1>
        <ProviderSettings key={selectedNodeId} t={t} />
        <SettingsCard
          title={t.nodesTitle}
          action={
            <button className="secondary-button" onClick={() => void createPairing()}>
              <Icon name="plus" />
              {t.addComputer}
            </button>
          }
        >
          <div className="node-list">
            {me?.nodes.map((item) => (
              <div
                className={`node-row${item.nodeId === selectedNodeId ? ' is-current' : ''}`}
                key={item.nodeId}
              >
                <span className="node-icon">
                  <Icon name={item.platform === 'linux' ? 'server' : 'laptop'} />
                  <StatusDot state={item.online ? 'ok' : 'offline'} />
                </span>
                <span>
                  <strong>{item.name}</strong>
                  <small>
                    {item.platform} · {item.online ? t.connected : t.offline}
                  </small>
                </span>
                <button
                  className="quiet-button"
                  title={t.copyRunCommand}
                  onClick={() => {
                    setCopied(item.nodeId);
                    void writeClipboard('pnpm node:run');
                  }}
                >
                  {copied === item.nodeId ? t.copied : 'CLI'}
                </button>
                <button className="unlink-button" onClick={() => setConfirmArchive(item.nodeId)}>
                  {t.unpair}
                </button>
              </div>
            ))}
          </div>
          {nodeError && <p className="form-error">{nodeError}</p>}
        </SettingsCard>
        <SettingsCard title={t.appearance} help={t.appearanceHelp}>
          <div className="theme-row">
            <span className={dark ? '' : 'is-on'}>{t.themeLight}</span>
            <button
              className={`theme-toggle${dark ? ' is-dark' : ''}`}
              role="switch"
              aria-checked={dark}
              onClick={() => setDark(!dark)}
              aria-label={t.toggleTheme}
            >
              <motion.span
                layout
                transition={
                  reduceMotion ? { duration: 0 } : { type: 'spring', stiffness: 600, damping: 34 }
                }
              >
                <Icon name={dark ? 'moon' : 'sun'} />
              </motion.span>
            </button>
            <span className={dark ? 'is-on' : ''}>{t.themeDark}</span>
          </div>
        </SettingsCard>
        <NotificationSettings t={t} />
        {error && <p className="form-error">{error}</p>}
        <SettingsCard title={t.accountSection}>
          <div className="account-row">
            <span className="profile-initial">{me?.user.email.slice(0, 1).toUpperCase()}</span>
            <span>
              <small>{t.signedInAs}</small>
              <strong>{me?.user.email}</strong>
            </span>
            <button
              className="secondary-button"
              onClick={() =>
                void relayRequest('/auth/logout', { method: 'POST', body: '{}' })
                  .then(() => setToken(null))
                  .catch((reason: unknown) =>
                    setError(reason instanceof Error ? reason.message : t.saveError),
                  )
              }
            >
              {t.logout}
            </button>
          </div>
        </SettingsCard>
      </motion.div>
      <AnimatePresence>
        {confirmArchive && (
          <motion.div
            className="confirm-strip"
            role="alertdialog"
            aria-label={t.unpair}
            initial={{ opacity: 0, y: 16, x: '-50%' }}
            animate={{ opacity: 1, y: 0, x: '-50%' }}
            exit={{ opacity: 0, y: 12, x: '-50%' }}
            transition={{ duration: reduceMotion ? 0.1 : 0.22, ease }}
          >
            <span>
              <strong>
                {t.unpair} · {me?.nodes.find((item) => item.nodeId === confirmArchive)?.name}
              </strong>
              <small>{t.unpairConfirm}</small>
            </span>
            <button className="quiet-button" onClick={() => setConfirmArchive(null)}>
              {t.cancel}
            </button>
            <button className="danger-button" onClick={() => void unpair(confirmArchive)}>
              {t.unpair}
            </button>
          </motion.div>
        )}
      </AnimatePresence>
    </main>
  );
}

function SettingsCard({
  title,
  help,
  action,
  children,
}: {
  title: string;
  help?: string;
  action?: ReactNode;
  children: ReactNode;
}) {
  return (
    <section className="settings-card">
      <div className="settings-card-heading">
        <div>
          <h2>{title}</h2>
          {help && <p>{help}</p>}
        </div>
        {action}
      </div>
      {children}
    </section>
  );
}
