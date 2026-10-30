import { useEffect, useState } from 'react';
import { USER_MEMORY_SEPARATOR, type UserMemoryView } from '@nekodot/protocol';
import { callNode } from '../relay-connection';
import type { Texts } from '../shared';
import { SpinnerDots } from '../ui';

export function SharedUserMemoryPanel({ t, online }: { t: Texts; online: boolean }) {
  const [data, setData] = useState<UserMemoryView>();
  const [draft, setDraft] = useState<string>();
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const [saved, setSaved] = useState(false);
  useEffect(() => {
    if (online)
      void callNode('memory.user.get', {})
        .then(setData)
        .catch((e: Error) => setError(e.message));
  }, [online]);
  const state = data?.shared;
  const imports = state?.imports.filter((item) => !item.reviewed) ?? [];
  const conflicts = state?.conflicts.filter((item) => !item.resolved) ?? [];
  const combine = (texts: string[]) =>
    [
      ...new Set(
        texts
          .flatMap((text) => text.split(USER_MEMORY_SEPARATOR))
          .map((text) => text.trim())
          .filter(Boolean),
      ),
    ].join(USER_MEMORY_SEPARATOR);
  const content = draft ?? combine([state?.content ?? '', ...imports.map((item) => item.content)]);
  async function refresh() {
    try {
      setData(await callNode('memory.user.get', {}));
      setError('');
    } catch (e) {
      setError((e as Error).message);
    }
  }
  async function save() {
    if (!state) return;
    setBusy(true);
    setError('');
    setSaved(false);
    try {
      setData(
        await callNode('memory.user.save', {
          revision: state.revision,
          content,
          reviewedImports: imports.map((item) => item.id),
          reviewedConflicts: conflicts.map((item) => item.id),
        }),
      );
      setDraft(undefined);
      setSaved(true);
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setBusy(false);
    }
  }
  return (
    <div className="shared-user-memory">
      <h4>{t.sharedUserMemory}</h4>
      <p className="muted">{t.sharedUserMemoryHelp}</p>
      {state && (
        <small>
          {t.memoryRevision} {state.revision}
        </small>
      )}
      {imports.length > 0 && (
        <section className="memory-proposals">
          <h4>{t.memoryImportReview}</h4>
          <p>{t.memoryImportHelp}</p>
          {imports.map((item) => (
            <details key={item.id}>
              <summary>
                {item.name} · {item.botId}
              </summary>
              <pre>{item.content}</pre>
            </details>
          ))}
        </section>
      )}
      {conflicts.length > 0 && (
        <section className="memory-proposals" role="status">
          <h4>{t.memoryConflictReview}</h4>
          <p>{t.memoryConflictHelp}</p>
          {conflicts.map((item) => (
            <details key={item.id} open>
              <summary>
                {item.name} · {item.botId}
              </summary>
              <strong>{t.memoryBase}</strong>
              <pre>{item.base || '∅'}</pre>
              <strong>{t.memoryCurrent}</strong>
              <pre>{item.current || '∅'}</pre>
              <strong>{t.memoryIncoming}</strong>
              <pre>{item.incoming || '∅'}</pre>
              <button
                className="secondary-button"
                onClick={() => setDraft(combine([content, item.incoming]))}
              >
                {t.memoryKeepBoth}
              </button>
            </details>
          ))}
        </section>
      )}
      {state ? (
        <>
          <label className="sr-only" htmlFor="shared-user-memory-editor">
            {t.sharedUserMemory}
          </label>
          <textarea
            id="shared-user-memory-editor"
            className="memory-editor"
            value={content}
            spellCheck={false}
            onChange={(e) => {
              setDraft(e.target.value);
              setSaved(false);
            }}
          />
          <div className="section-actions">
            <button
              className="secondary-button"
              disabled={!online || busy}
              onClick={() => void refresh()}
            >
              {t.refresh}
            </button>
            <button
              className="primary-button"
              disabled={!online || !data?.connected || busy}
              onClick={() => void save()}
            >
              {busy ? (
                <SpinnerDots />
              ) : imports.length || conflicts.length || !state.initialized ? (
                t.confirmSharedMemory
              ) : (
                t.save
              )}
            </button>
          </div>
        </>
      ) : (
        <p>{online ? <SpinnerDots /> : t.offlineCreateHint}</p>
      )}
      {!data?.connected && <p className="muted">{t.memorySyncOffline}</p>}
      {(error || data?.error) && (
        <p className="form-error" role="alert">
          {error || data?.error}
        </p>
      )}
      {saved && (
        <p className="success-message" role="status">
          {t.memorySaved}
        </p>
      )}
      {state &&
        (state.imports.some((item) => item.reviewed) ||
          state.conflicts.some((item) => item.resolved)) && (
          <details className="memory-proposals">
            <summary>{t.memoryHistory}</summary>
            {state.imports
              .filter((item) => item.reviewed)
              .map((item) => (
                <details key={item.id}>
                  <summary>{item.name} · USER.md</summary>
                  <pre>{item.content}</pre>
                </details>
              ))}
            {state.conflicts
              .filter((item) => item.resolved)
              .map((item) => (
                <details key={item.id}>
                  <summary>{item.name}</summary>
                  <strong>{t.memoryBase}</strong>
                  <pre>{item.base || '∅'}</pre>
                  <strong>{t.memoryCurrent}</strong>
                  <pre>{item.current || '∅'}</pre>
                  <strong>{t.memoryIncoming}</strong>
                  <pre>{item.incoming || '∅'}</pre>
                </details>
              ))}
          </details>
        )}
    </div>
  );
}
