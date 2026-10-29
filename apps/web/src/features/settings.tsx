import { useEffect, useState, type FormEvent } from 'react';
import type { RpcResult } from '@nekodot/protocol';
import { fetchMe, relayRequest } from '../api';
import { callNode } from '../relay-connection';
import { useAppStore } from '../store';
import { Icon, SpinnerDots, Wordmark } from '../ui';
import type { Texts } from '../shared';
import { ModelPicker, useModelOptions } from './models';
import { NotificationSettings } from './notifications';
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
      <header className="settings-header">
        <button className="icon-button" onClick={onHome} aria-label={t.home}>
          <Icon name="chevron" />
        </button>
        <Wordmark />
        <span>{t.settingsTitle}</span>
        <button
          className="quiet-button language-button"
          onClick={onLanguage}
          aria-label={t.language}
        >
          {t.language}
        </button>
      </header>
      <section className="settings-body">
        <span className="eyebrow">
          <i /> NEKODOT · SETTINGS
        </span>
        <h1>{t.settingsTitle}</h1>
        <form className="settings-card" onSubmit={(event) => void saveProvider(event)}>
          <div className="settings-card-heading">
            <div>
              <h2>{t.provider}</h2>
              <p>{t.providerHelp}</p>
            </div>
            <span className="settings-mark">↗</span>
          </div>
          <div className="provider-switch">
            <button
              type="button"
              className={kind === 'openrouter' ? 'selected' : ''}
              onClick={() => setKind('openrouter')}
            >
              {t.openrouter}
            </button>
            <button
              type="button"
              className={kind === 'custom' ? 'selected' : ''}
              onClick={() => setKind('custom')}
            >
              {t.customProvider}
            </button>
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
          {provider?.kind === kind && <small className="muted">{t.keepKeyHint}</small>}
          <ModelPicker
            t={t}
            label={t.defaultModel}
            value={defaultModel}
            onChange={setDefaultModel}
            catalog={catalog}
            disabled={!selectedNode?.online || !provider}
          />
          {provider && (
            <p className="saved-key">
              {t.keySaved} ····{provider.apiKeyLast4}
            </p>
          )}
          {message && <p className="success-message">{message}</p>}
          {error && <p className="form-error">{error}</p>}
          <div className="settings-card-footer">
            <button
              className="primary-button"
              disabled={saving || (!key && provider?.kind !== kind) || !selectedNode?.online}
            >
              {saving ? <SpinnerDots /> : t.saveProvider}
              <Icon name="arrow" />
            </button>
          </div>
          {!selectedNode?.online && <p className="form-error">{t.offlineCreateHint}</p>}
        </form>
        <section className="settings-card">
          <div className="settings-card-heading">
            <div>
              <h2>{t.nodesTitle}</h2>
              <p>{t.chooseComputer}</p>
            </div>
            <button className="secondary-button" onClick={() => void createPairing()}>
              <Icon name="plus" />
              {t.addComputer}
            </button>
          </div>
          <div className="node-list">
            {me?.nodes.map((item) => (
              <div className="node-row" key={item.nodeId}>
                <span className={`node-icon ${item.online ? 'online' : ''}`}>
                  <Icon name="laptop" />
                </span>
                <span>
                  <strong>{item.name}</strong>
                  <small>
                    {item.platform} · {item.online ? t.connected : t.offline}
                  </small>
                </span>
                <button
                  className="quiet-button"
                  onClick={() => {
                    setCopied(item.nodeId);
                    void navigator.clipboard.writeText('pnpm node:run');
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
        </section>
        <section className="settings-card settings-options">
          <div>
            <h2>{t.appearance}</h2>
            <p>{t.appearanceHelp}</p>
          </div>
          <button
            className={`theme-toggle${dark ? ' is-dark' : ''}`}
            onClick={() => setDark(!dark)}
            aria-label={t.toggleTheme}
          >
            <span />
          </button>
        </section>
        <NotificationSettings t={t} />
        <section className="settings-card account-card">
          <div>
            <h2>{me?.user.email}</h2>
            <p>{t.language}</p>
          </div>
          <button className="secondary-button" onClick={() => setToken(null)}>
            {t.logout}
          </button>
        </section>
        {confirmArchive && (
          <div className="confirm-strip">
            <span>
              {t.unpair} · {me?.nodes.find((item) => item.nodeId === confirmArchive)?.name}
            </span>
            <button className="unlink-button" onClick={() => setConfirmArchive(null)}>
              {t.cancel}
            </button>
            <button className="danger-button" onClick={() => void unpair(confirmArchive)}>
              {t.unpair}
            </button>
          </div>
        )}
      </section>
    </main>
  );
}
