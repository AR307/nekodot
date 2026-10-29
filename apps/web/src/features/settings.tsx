import { useEffect, useState, type FormEvent, type ReactNode } from 'react';
import { AnimatePresence, motion, useReducedMotion } from 'motion/react';
import type { RpcResult } from '@nekodot/protocol';
import { fetchMe, relayRequest } from '../api';
import { callNode } from '../relay-connection';
import { useAppStore } from '../store';
import { Icon, SpinnerDots, StatusDot, ease } from '../ui';
import type { Texts } from '../shared';
import { ModelPicker, useModelOptions } from './models';
import { NotificationSettings } from './notifications';
import { writeClipboard } from '../native';
type Provider = NonNullable<RpcResult<'providers.get'>>;

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
  const [provider, setProvider] = useState<Provider | null>(null);
  const [kind, setKind] = useState<'openrouter' | 'custom'>('custom');
  const [key, setKey] = useState('');
  const [baseUrl, setBaseUrl] = useState('');
  const [defaultModel, setDefaultModel] = useState('');
  const [saving, setSaving] = useState(false);
  const [message, setMessage] = useState('');
  const [error, setError] = useState('');
  const [nodeError, setNodeError] = useState('');
  const [copied, setCopied] = useState('');
  const [confirmArchive, setConfirmArchive] = useState<string | null>(null);
  const reduceMotion = useReducedMotion();
  const selectedNode = me?.nodes.find((item) => item.nodeId === selectedNodeId);
  const catalog = useModelOptions(Boolean(selectedNode?.online));

  useEffect(() => {
    if (!selectedNode?.online) return;
    void callNode('providers.get', {})
      .then((value) => {
        setProvider(value);
        if (value) {
          setKind(value.kind);
          setBaseUrl(value.baseUrl ?? '');
          setDefaultModel(value.defaultModel ?? '');
        }
      })
      .catch((reason: unknown) => setError(reason instanceof Error ? reason.message : t.saveError));
  }, [selectedNode?.online, selectedNodeId, t.saveError]);

  async function saveProvider(event: FormEvent) {
    event.preventDefault();
    setSaving(true);
    setMessage('');
    setError('');
    try {
      const value = await callNode(
        'providers.set',
        kind === 'custom'
          ? {
              kind,
              ...(key ? { apiKey: key } : {}),
              baseUrl: baseUrl.trim().replace(/\/+$/, ''),
              ...(defaultModel ? { defaultModel } : {}),
            }
          : { kind, ...(key ? { apiKey: key } : {}), ...(defaultModel ? { defaultModel } : {}) },
      );
      setProvider(value);
      setKey('');
      setMessage(t.providerSaved);
      await catalog.reload(true);
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : t.saveError);
    } finally {
      setSaving(false);
    }
  }

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
        <SettingsCard title={t.provider} help={t.providerHelp}>
          <form className="provider-form" onSubmit={(event) => void saveProvider(event)}>
            <div className="provider-switch" role="group" aria-label={t.provider}>
              {(['openrouter', 'custom'] as const).map((option) => (
                <button
                  key={option}
                  type="button"
                  aria-pressed={kind === option}
                  className={kind === option ? 'selected' : ''}
                  onClick={() => setKind(option)}
                >
                  {kind === option && (
                    <motion.span
                      className="segmented-thumb"
                      layoutId="provider-kind"
                      transition={
                        reduceMotion
                          ? { duration: 0 }
                          : { type: 'spring', stiffness: 500, damping: 38 }
                      }
                    />
                  )}
                  <span>{option === 'openrouter' ? t.openrouter : t.customProvider}</span>
                </button>
              ))}
            </div>
            {kind === 'custom' && (
              <label>
                {t.baseUrl}
                <input
                  type="url"
                  required
                  value={baseUrl}
                  onChange={(event) => setBaseUrl(event.target.value)}
                  placeholder="https://api.example.com/v1"
                />
              </label>
            )}
            <label>
              {t.apiKey}
              <input
                type="password"
                required={provider?.kind !== kind}
                value={key}
                onChange={(event) => setKey(event.target.value)}
                placeholder={provider ? `••••••••${provider.apiKeyLast4}` : t.keyPlaceholder}
                autoComplete="new-password"
              />
            </label>
            {provider && (
              <p className="saved-key">
                <Icon name="check" />
                <span>
                  {t.keySaved} ····{provider.apiKeyLast4}
                </span>
                {provider.kind === kind && <small>{t.keepKeyHint}</small>}
              </p>
            )}
            <ModelPicker
              t={t}
              label={t.defaultModel}
              value={defaultModel}
              onChange={setDefaultModel}
              catalog={catalog}
              disabled={!selectedNode?.online || !provider}
            />
            {error && <p className="form-error">{error}</p>}
            {!selectedNode?.online && <p className="form-error">{t.offlineCreateHint}</p>}
            <div className="settings-card-footer">
              {message && (
                <p className="success-message">
                  <Icon name="check" />
                  {message}
                </p>
              )}
              <button
                className="primary-button"
                disabled={saving || (!key && provider?.kind !== kind) || !selectedNode?.online}
              >
                {saving && <SpinnerDots />}
                {t.saveProvider}
              </button>
            </div>
          </form>
        </SettingsCard>
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
        <SettingsCard title={t.accountSection}>
          <div className="account-row">
            <span className="profile-initial">{me?.user.email.slice(0, 1).toUpperCase()}</span>
            <span>
              <small>{t.signedInAs}</small>
              <strong>{me?.user.email}</strong>
            </span>
            <button className="secondary-button" onClick={() => setToken(null)}>
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
