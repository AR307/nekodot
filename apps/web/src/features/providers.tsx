import { useEffect, useState, type FormEvent } from 'react';
import type { ProviderSource, RpcResult } from '@nekodot/protocol';
import { callNode } from '../relay-connection';
import { selectNodeData, useAppStore } from '../store';
import type { Texts } from '../shared';
import { SpinnerDots } from '../ui';

export function ProviderSettings({ t }: { t: Texts }) {
  const node = useAppStore(selectNodeData);
  const nodeId = useAppStore((state) => state.selectedNodeId);
  const [data, setData] = useState<RpcResult<'providers.list'>>({ sources: [], oauth: [] });
  const [revision, setRevision] = useState(0);
  const [source, setSource] = useState<ProviderSource>();
  const [name, setName] = useState('');
  const [baseUrl, setBaseUrl] = useState('');
  const [key, setKey] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const [message, setMessage] = useState('');
  useEffect(() => {
    let active = true;
    if (node.online)
      void callNode('providers.list', {})
        .then((value) => {
          if (active) setData(value);
        })
        .catch((e: Error) => {
          if (active) setError(e.message);
        });
    return () => {
      active = false;
    };
  }, [nodeId, node.online, revision]);
  async function save(event: FormEvent) {
    event.preventDefault();
    setBusy(true);
    setError('');
    setMessage('');
    try {
      const value = await callNode('providers.set', {
        kind: 'custom',
        ...(source ? { sourceId: source.sourceId } : {}),
        name,
        baseUrl: baseUrl.trim(),
        ...(key ? { apiKey: key } : {}),
      });
      setKey('');
      setSource(value);
      setRevision((v) => v + 1);
      const catalog = await callNode('models.options', { sourceId: value.sourceId, refresh: true });
      setMessage(
        t.providerSaved +
          ' · ' +
          t.modelsLoaded.replace('{count}', String(catalog.models.length)) +
          (catalog.warning ? ' · ' + catalog.warning : ''),
      );
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setBusy(false);
    }
  }
  return (
    <>
      <section className="settings-card">
        <div className="settings-card-heading">
          <div>
            <h2>{t.authorizedServices}</h2>
            <p>{t.sourceHelp}</p>
          </div>
        </div>
        <div className="source-list">
          {data.oauth.map((entry) => (
            <Authorization
              key={String(entry.id)}
              entry={entry}
              t={t}
              refresh={() => setRevision((v) => v + 1)}
            />
          ))}
        </div>
      </section>
      <section className="settings-card">
        <div className="settings-card-heading">
          <div>
            <h2>{t.customSources}</h2>
            <p>{t.customSourceHelp}</p>
          </div>
        </div>
        <div className="source-list">
          {data.sources
            .filter((entry) => entry.kind === 'custom')
            .map((entry) => (
              <button
                type="button"
                className="secondary-button source-row"
                key={entry.sourceId}
                onClick={() => {
                  setSource(entry);
                  setName(entry.name);
                  setBaseUrl(entry.baseUrl ?? '');
                  setKey('');
                  setMessage('');
                }}
              >
                <strong>{entry.name}</strong>
                <small>
                  {entry.baseUrl} · ••••{entry.apiKeyLast4}
                </small>
              </button>
            ))}
        </div>
        <form className="provider-form" onSubmit={(event) => void save(event)}>
          <label>
            {t.name}
            <input required value={name} onChange={(e) => setName(e.target.value)} />
          </label>
          <label>
            {t.baseUrl}
            <input
              type="url"
              required
              value={baseUrl}
              onChange={(e) => setBaseUrl(e.target.value)}
              placeholder="https://api.example.com/v1"
            />
          </label>
          <label>
            {t.apiKey}
            <input
              type="password"
              autoComplete="new-password"
              required={!source}
              value={key}
              onChange={(e) => setKey(e.target.value)}
              placeholder={source ? t.keepKeyHint : t.keyPlaceholder}
            />
          </label>
          {source && (
            <p className="saved-key">
              {t.keySaved} · ••••{source.apiKeyLast4}
            </p>
          )}
          <div className="settings-card-footer">
            {source && (
              <button
                type="button"
                className="secondary-button"
                onClick={() => {
                  setSource(undefined);
                  setName('');
                  setBaseUrl('');
                  setKey('');
                  setMessage('');
                }}
              >
                {t.addSource}
              </button>
            )}
            <button className="primary-button" disabled={busy || !node.online}>
              {busy && <SpinnerDots />}
              {t.saveFetchModels}
            </button>
          </div>
          {message && (
            <p className="success-message" role="status">
              {message}
            </p>
          )}
          {error && (
            <p className="form-error" role="alert">
              {error}
            </p>
          )}
          {!node.online && <p className="form-error">{t.offlineCreateHint}</p>}
        </form>
      </section>
    </>
  );
}

function Authorization({
  entry,
  t,
  refresh,
}: {
  entry: RpcResult<'providers.list'>['oauth'][number];
  t: Texts;
  refresh(): void;
}) {
  const [session, setSession] = useState<RpcResult<'providers.authorize'>>();
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);
  const status = entry.status as { logged_in?: boolean; source_label?: string } | undefined;
  async function action(action: 'start' | 'poll' | 'cancel' | 'disconnect') {
    setBusy(true);
    setError('');
    try {
      const result = await callNode('providers.authorize', {
        provider: String(entry.id),
        action,
        ...(session?.session_id ? { sessionId: String(session.session_id) } : {}),
      });
      if (action === 'cancel' || action === 'disconnect') setSession(undefined);
      else setSession((previous) => ({ status: 'pending', ...previous, ...result }));
      if (result.status === 'approved' || action === 'disconnect') refresh();
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setBusy(false);
    }
  }
  useEffect(() => {
    if (!session?.session_id || (session.status && session.status !== 'pending')) return;
    const timer = setTimeout(
      () => void action('poll'),
      Math.max(3, Number(session.poll_interval ?? 5)) * 1000,
    );
    return () => clearTimeout(timer);
    // Poll follows the native session interval, not a separate token/refresh implementation.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [session]);
  return (
    <div className="authorization-card">
      <strong>{String(entry.name ?? entry.id)}</strong>
      <small>
        {status?.logged_in ? t.authorized : t.notAuthorized} {status?.source_label ?? ''}
      </small>
      {entry.flow !== 'device_code' ? (
        <>
          <p className="muted">{t.terminalAuthorization}</p>
          <code>{String(entry.cli_command ?? '')}</code>
        </>
      ) : (
        !status?.logged_in && (
          <button
            type="button"
            className="secondary-button"
            disabled={busy || Boolean(session?.session_id && session.status === 'pending')}
            onClick={() => void action('start')}
          >
            {t.startAuthorization}
          </button>
        )
      )}
      {typeof entry.docs_url === 'string' && (
        <a href={entry.docs_url} target="_blank" rel="noreferrer">
          {t.authorizationGuide}
        </a>
      )}
      {status?.logged_in && entry.disconnectable === true && (
        <button
          type="button"
          className="quiet-button"
          disabled={busy}
          onClick={() => void action('disconnect')}
        >
          {t.disconnectAuthorization}
        </button>
      )}
      {session && (
        <div className="authorization-session">
          {session.status === 'pending' && Boolean(session.user_code) && (
            <strong>{String(session.user_code)}</strong>
          )}
          {session.status === 'pending' && typeof session.verification_url === 'string' && (
            <a href={session.verification_url} target="_blank" rel="noreferrer">
              {t.openAuthorization}
            </a>
          )}
          <p role="status">
            {session.status === 'approved'
              ? t.authorized
              : session.status === 'pending'
                ? t.awaitingAuthorization
                : String(session.error_message ?? session.status ?? '')}
          </p>
          {Boolean(session.session_id) && session.status === 'pending' && (
            <button
              type="button"
              className="quiet-button"
              disabled={busy}
              onClick={() => void action('cancel')}
            >
              {t.cancel}
            </button>
          )}
        </div>
      )}
      {error && (
        <p className="form-error" role="alert">
          {error}
        </p>
      )}
    </div>
  );
}
