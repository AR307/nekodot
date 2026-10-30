import { useCallback, useEffect, useState } from 'react';
import type { Attachment, Bot, MemoryDocument, Operation, RpcResult } from '@nekodot/protocol';
import { callNode } from '../relay-connection';
import { BotAvatar, Icon, Segmented, SpinnerDots } from '../ui';
import { selectNodeData, useAppStore } from '../store';
import type { Texts } from '../shared';
import { OperationProgress } from './operations';
import { LibraryPanel } from './files';
import { ModelInformation } from './model-info';
import { SharedUserMemoryPanel } from './user-memory';

export function BotDetails({
  bot,
  t,
  onClose,
  onEdit,
  onSource,
  onScreen,
}: {
  bot: Bot;
  t: Texts;
  onClose(): void;
  onEdit(): void;
  onSource(file: Attachment): void;
  onScreen(): void;
}) {
  const [tab, setTab] = useState<'details' | 'memory' | 'library'>('details');
  const nodeId = useAppStore((state) => state.selectedNodeId);
  const online = useAppStore(selectNodeData).online;
  return (
    <div className="details-backdrop" onClick={onClose}>
      <section
        className="bot-details"
        role="dialog"
        aria-modal="true"
        aria-label={`${bot.displayName} · ${t.botDetails}`}
        onClick={(event) => event.stopPropagation()}
        key={nodeId}
      >
        <header className="details-header">
          <BotAvatar color={bot.avatar.color} size={48} />
          <div>
            <h2>{bot.displayName}</h2>
            <small>
              @{bot.handle} · {bot.model}
            </small>
          </div>
          <button
            className="icon-button"
            onClick={onScreen}
            aria-label={t.screenTitle}
            title={t.screenTitle}
          >
            <Icon name="monitor" />
          </button>
          <button className="icon-button" onClick={onClose} aria-label={t.close}>
            <Icon name="close" />
          </button>
        </header>
        <div className="details-tabs">
          <Segmented<typeof tab>
            id="details-tab"
            label={t.botDetails}
            value={tab}
            onChange={setTab}
            options={[
              { value: 'details', label: t.botDetails },
              { value: 'memory', label: t.botMemory },
              { value: 'library', label: t.botLibrary },
            ]}
          />
        </div>
        {!online && <p className="offline-strip">{t.offline}</p>}
        <div className="details-scroll">
          {tab === 'details' ? (
            <BotInfo bot={bot} t={t} onEdit={onEdit} />
          ) : tab === 'memory' ? (
            <MemoryPanel bot={bot} t={t} />
          ) : (
            <LibraryPanel bot={bot} t={t} onSource={onSource} />
          )}
        </div>
      </section>
    </div>
  );
}

function BotInfo({ bot, t, onEdit }: { bot: Bot; t: Texts; onEdit(): void }) {
  const [jobs, setJobs] = useState<Record<string, unknown>[]>();
  const [runs, setRuns] = useState<Record<string, unknown>[]>();
  const [error, setError] = useState('');
  const online = useAppStore(selectNodeData).online;
  useEffect(() => {
    if (online)
      void callNode('bots.jobs', { botId: bot.botId })
        .then((value) => {
          setJobs(value.jobs);
          setError('');
        })
        .catch((e: Error) => setError(e.message));
  }, [bot.botId, online]);
  async function history(job: Record<string, unknown>) {
    try {
      const value = await callNode('bots.jobs.runs', {
        botId: bot.botId,
        jobId: String(job.id ?? job.job_id),
      });
      setRuns(value.runs);
    } catch (e) {
      setError(e instanceof Error ? e.message : t.failed);
    }
  }
  return (
    <>
      <section className="detail-section">
        <div className="section-heading">
          <h3>{t.botDetails}</h3>
          <button className="secondary-button" onClick={onEdit}>
            {t.editBot}
          </button>
        </div>
        <p className="preserve-lines">{bot.role}</p>
        <small className="muted">
          {t.nativeProfile}: {bot.botId}
        </small>
      </section>
      <ModelInformation botId={bot.botId} t={t} />
      <section className="detail-section">
        <h3>{t.scheduledTasks}</h3>
        <p className="muted">{t.scheduledReadOnly}</p>
        {error && (
          <p className="form-error" role="alert">
            {error}
          </p>
        )}
        {!jobs ? (
          <SpinnerDots />
        ) : !jobs.length ? (
          <p className="empty-state">{t.noScheduledTasks}</p>
        ) : (
          jobs.map((job) => {
            const schedule = job.schedule as
              { display?: string; run_at?: string; timezone?: string } | undefined;
            const stamp = String(job.next_run_at ?? job.last_run_at ?? schedule?.run_at ?? '');
            const zone =
              job.timezone ?? schedule?.timezone ?? stamp.match(/([+-]\d{2}:\d{2}|Z)$/)?.[0];
            const fields: [string, unknown][] = [
              [t.jobSchedule, job.schedule_display ?? schedule?.display],
              [
                t.jobTimezone,
                zone === 'Z'
                  ? 'UTC'
                  : zone
                    ? String(zone).startsWith('+') || String(zone).startsWith('-')
                      ? 'UTC' + zone
                      : zone
                    : '—',
              ],
              [t.jobStatus, job.enabled ? t.enabled : t.disabled],
              [t.jobNextRun, job.next_run_at ?? '—'],
              [t.jobLastRun, job.last_run_at ?? '—'],
              [t.jobLastResult, job.last_status ?? '—'],
            ];
            return (
              <article className="native-card" key={String(job.id ?? job.job_id)}>
                <strong>{String(job.name ?? job.prompt ?? job.id)}</strong>
                {Boolean(job.name) && typeof job.prompt === 'string' && (
                  <p className="preserve-lines">{job.prompt}</p>
                )}
                <dl>
                  {fields.map(([label, value]) => (
                    <div key={String(label)}>
                      <dt>{label}</dt>
                      <dd>{String(value ?? '—')}</dd>
                    </div>
                  ))}
                </dl>
                <button className="text-button" onClick={() => void history(job)}>
                  {t.executionHistory}
                </button>
              </article>
            );
          })
        )}
      </section>
      {runs && (
        <section className="detail-section">
          <h3>{t.executionHistory}</h3>
          {runs.length ? (
            runs.map((run, i) => {
              const started = run.started_at ?? run.created_at;
              return (
                <article className="native-card" key={String(run.id ?? i)}>
                  <strong>
                    {String(run.end_reason ?? (run.is_active ? t.operationRunning : t.completed))}
                  </strong>
                  {started !== undefined && (
                    <p className="muted">
                      {new Date(
                        typeof started === 'number' ? started * 1000 : String(started),
                      ).toLocaleString()}
                    </p>
                  )}
                  <p className="preserve-lines">{String(run.preview ?? run.title ?? '')}</p>
                </article>
              );
            })
          ) : (
            <p className="muted">{t.noResults}</p>
          )}
        </section>
      )}
    </>
  );
}

function MemoryPanel({ bot, t }: { bot: Bot; t: Texts }) {
  const [data, setData] = useState<RpcResult<'memory.get'>>();
  const [name, setName] = useState<MemoryDocument>('SOUL.md');
  const [drafts, setDrafts] = useState<Partial<Record<MemoryDocument, string>>>({});
  const [focus, setFocus] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const [notice, setNotice] = useState('');
  const [operation, setOperation] = useState<Operation>();
  const [reviewId, setReviewId] = useState('');
  const [reviewKind, setReviewKind] = useState<'memory' | 'skills'>('memory');
  const online = useAppStore(selectNodeData).online;
  const load = useCallback(async () => {
    try {
      setData(await callNode('memory.get', { botId: bot.botId }));
      setError('');
    } catch (e) {
      setError(e instanceof Error ? e.message : t.failed);
    }
  }, [bot.botId, t.failed]);
  useEffect(() => {
    if (!online) return;
    void callNode('memory.get', { botId: bot.botId })
      .then(setData)
      .catch((e: Error) => setError(e.message));
    void callNode('operations.list', {})
      .then((value) =>
        setOperation(
          value.operations.find(
            (op) => op.kind === 'memory.refine' && op.botIds.includes(bot.botId),
          ),
        ),
      )
      .catch((e: Error) => setError(e.message));
  }, [online, bot.botId]);
  const document = data?.documents.find((doc) => doc.name === name);
  async function save() {
    if (name === 'USER.md') return;
    setBusy(true);
    setNotice('');
    try {
      await callNode('memory.save', {
        botId: bot.botId,
        name,
        content: drafts[name] ?? document?.content ?? '',
      });
      setDrafts((previous) => {
        const next = { ...previous };
        delete next[name];
        return next;
      });
      await load();
      setNotice(t.memorySaved);
    } catch (e) {
      setError(e instanceof Error ? e.message : t.saveError);
    } finally {
      setBusy(false);
    }
  }
  async function refine() {
    setBusy(true);
    try {
      setOperation(await callNode('memory.refine', { botId: bot.botId, focus }));
    } catch (e) {
      setError(e instanceof Error ? e.message : t.failed);
    } finally {
      setBusy(false);
    }
  }
  async function review(action: 'approve' | 'reject') {
    setBusy(true);
    try {
      const result = await callNode('memory.review', {
        botId: bot.botId,
        kind: reviewKind,
        reviewId,
        action,
      });
      setNotice(result.output);
      setReviewId('');
      await load();
    } catch (e) {
      setError(e instanceof Error ? e.message : t.failed);
    } finally {
      setBusy(false);
    }
  }
  return (
    <>
      <section className="detail-section">
        <h3>{t.nativeMemory}</h3>
        <p className="muted">{t.memoryTiming}</p>
        <div className="document-tabs">
          {(['SOUL.md', 'MEMORY.md', 'USER.md'] as const).map((doc) => (
            <button
              key={doc}
              className={name === doc ? 'selected' : ''}
              onClick={() => setName(doc)}
            >
              {doc}
            </button>
          ))}
        </div>
        <p className="muted">
          {name === 'SOUL.md'
            ? t.soulDescription
            : name === 'MEMORY.md'
              ? t.memoryDescription
              : t.userDescription}
        </p>
        {name === 'USER.md' ? (
          <SharedUserMemoryPanel t={t} online={online} />
        ) : data ? (
          <>
            <label className="sr-only" htmlFor="native-memory-editor">
              {name}
            </label>
            <textarea
              id="native-memory-editor"
              className="memory-editor"
              spellCheck={false}
              value={drafts[name] ?? document?.content ?? ''}
              onChange={(e) => setDrafts({ ...drafts, [name]: e.target.value })}
            />
            <div className="section-actions">
              <button
                className="secondary-button"
                disabled={!online || busy}
                onClick={() => void load()}
              >
                {t.refresh}
              </button>
              <button
                className="primary-button"
                disabled={!online || busy || drafts[name] === undefined}
                onClick={() => void save()}
              >
                {busy ? <SpinnerDots /> : t.save}
              </button>
            </div>
          </>
        ) : (
          <SpinnerDots />
        )}
        {error && (
          <p className="form-error" role="alert">
            {error}
          </p>
        )}
        {notice && <p className="inline-success">{notice}</p>}
      </section>
      <section className="detail-section">
        <h3>{t.refineMemory}</h3>
        <p className="muted">{t.refineDescription}</p>
        <label>
          {t.refineFocus}
          <textarea
            value={focus}
            onChange={(e) => setFocus(e.target.value)}
            placeholder={t.refinePlaceholder}
            rows={3}
          />
        </label>
        <button
          className="secondary-button"
          disabled={!online || busy || operation?.status === 'running'}
          onClick={() => void refine()}
        >
          {t.refineMemory}
        </button>
        {operation && (
          <OperationProgress
            key={operation.operationId}
            initial={operation}
            t={t}
            onFinished={load}
          />
        )}
      </section>
      {data?.pending && (
        <section className="detail-section">
          <h3>{t.pendingReview}</h3>
          <pre className="native-output">{data.pending}</pre>
          <div className="review-actions">
            <select
              aria-label={t.reviewKind}
              value={reviewKind}
              onChange={(e) => setReviewKind(e.target.value as 'memory' | 'skills')}
            >
              <option value="memory">{t.botMemory}</option>
              <option value="skills">Skills</option>
            </select>
            <input
              aria-label={t.reviewId}
              value={reviewId}
              onChange={(e) => setReviewId(e.target.value)}
              placeholder={t.reviewId}
            />
            <button
              className="secondary-button"
              disabled={busy || !online || !reviewId}
              onClick={() => void review('approve')}
            >
              {t.applyChange}
            </button>
            <button
              className="quiet-button"
              disabled={busy || !online || !reviewId}
              onClick={() => void review('reject')}
            >
              {t.deny}
            </button>
          </div>
        </section>
      )}
    </>
  );
}
