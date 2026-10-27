import { useEffect, useState, type FormEvent } from 'react';
import type { RpcResult } from '@nekodot/protocol';
import { fetchMe, relayRequest } from '../api';
import { callNode } from '../relay-connection';
import { useAppStore } from '../store';
import { Icon, SpinnerDots, Wordmark } from '../ui';
import type { Texts } from '../shared';
type Provider = NonNullable<RpcResult<'providers.get'>>;

export function SettingsPage({
  t,
  dark,
  setDark,
  onHome,
}: {
  t: Texts;
  dark: boolean;
  setDark(value: boolean): void;
  onHome(): void;
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
      .catch(() => {});
  }, [selectedNode?.online, selectedNodeId]);

  async function saveProvider(event: FormEvent) {
    event.preventDefault();
    setSaving(true);
    setMessage('');
    setError('');
    try {
      const value = await callNode(
        'providers.set',
        kind === 'custom'
          ? { kind, apiKey: key, baseUrl, ...(defaultModel ? { defaultModel } : {}) }
          : { kind, apiKey: key, ...(defaultModel ? { defaultModel } : {}) },
      );
      setProvider(value);
      setKey('');
      setMessage(`${t.keySaved} ····${value.apiKeyLast4}`);
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
              required
              value={key}
              onChange={(event) => setKey(event.target.value)}
              placeholder={provider ? `••••••••${provider.apiKeyLast4}` : t.keyPlaceholder}
              autoComplete="new-password"
            />
          </label>
          <label>
            {t.defaultModel}
            <input
              value={defaultModel}
              onChange={(event) => setDefaultModel(event.target.value)}
              placeholder={t.modelPlaceholder}
            />
          </label>
          {provider && (
            <p className="saved-key">
              {t.keySaved} ····{provider.apiKeyLast4}
            </p>
          )}
          {message && <p className="success-message">{message}</p>}
          {error && <p className="form-error">{error}</p>}
          <div className="settings-card-footer">
            <button className="primary-button" disabled={saving || !key || !selectedNode?.online}>
              {saving ? <SpinnerDots /> : t.saveProvider}
              <Icon name="arrow" />
            </button>
          </div>
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
