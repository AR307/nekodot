import { lazy, Suspense, useCallback, useEffect, useState } from 'react';
import type { Attachment, Bot, Operation } from '@nekodot/protocol';
import { callNode } from '../relay-connection';
import { selectNodeData, useAppStore } from '../store';
import { Icon, SpinnerDots } from '../ui';
import type { Texts } from '../shared';
import { relayUrl } from '../relay-url';
import { OperationProgress } from './operations';
import { android, saveDownload, shareFile } from '../native';
const PdfPreview = lazy(() =>
  import('./pdf-preview').then((module) => ({ default: module.PdfPreview })),
);

export function readableMessageText(text: string) {
  return text.replace(/(?:^|\n)\s*MEDIA:\s*(?:"[^"]+"|'[^']+'|[^\r\n]+)(?=\r?\n|$)/g, '').trim();
}

async function fetchFile(nodeId: string, fileId: string) {
  const response = await fetch(
    relayUrl(`/api/nodes/${encodeURIComponent(nodeId)}/files/${fileId}`),
    {
      headers: { Authorization: 'Bearer ' + localStorage.getItem('nekodot-token') },
    },
  );
  if (!response.ok) {
    const value = (await response.json()) as { error?: { message?: string } };
    throw new Error(value.error?.message ?? 'File transfer failed');
  }
  return response.blob();
}
export function FileCard({ file, t, onSource }: { file: Attachment; t: Texts; onSource?(): void }) {
  const nodeId = useAppStore((state) => state.selectedNodeId)!;
  const [preview, setPreview] = useState<{ url?: string; text?: string }>();
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  useEffect(
    () => () => {
      if (preview?.url) URL.revokeObjectURL(preview.url);
    },
    [preview],
  );
  async function open(download = false, share = false) {
    setBusy(true);
    setError('');
    try {
      const blob = await fetchFile(nodeId, file.fileId);
      if (share) await shareFile(blob, file.name);
      else if (download) await saveDownload(blob, file.name);
      else if (file.mime.startsWith('text/')) setPreview({ text: await blob.text() });
      else setPreview({ url: URL.createObjectURL(blob) });
    } catch (e) {
      setError(e instanceof Error ? e.message : t.failed);
    } finally {
      setBusy(false);
    }
  }
  const canPreview = /^(image\/|text\/|application\/pdf$)/.test(file.mime);
  return (
    <>
      <article className="file-card">
        <span className="file-kind">
          {file.mime.startsWith('image/')
            ? 'IMG'
            : file.mime === 'application/pdf'
              ? 'PDF'
              : file.mime.startsWith('text/')
                ? 'TXT'
                : 'FILE'}
        </span>
        <div className="file-info">
          <strong title={file.name}>{file.name}</strong>
          <small>
            {file.available
              ? `${file.size < 1024 ? file.size + ' B' : file.size < 1048576 ? (file.size / 1024).toFixed(1) + ' KB' : (file.size / 1048576).toFixed(1) + ' MB'} · ${new Date(file.sentAt).toLocaleDateString()}`
              : t.fileUnavailable}
          </small>
        </div>
        <div className="file-actions">
          {busy ? (
            <SpinnerDots />
          ) : (
            <>
              {canPreview && (
                <button
                  className="text-button"
                  disabled={!file.available}
                  onClick={() => void open()}
                >
                  {t.preview}
                </button>
              )}
              <button
                className="text-button"
                disabled={!file.available}
                onClick={() => void open(true)}
              >
                {t.download}
              </button>
              {onSource && (
                <button className="text-button" onClick={onSource}>
                  {t.sourceMessage}
                </button>
              )}
              {android && (
                <button
                  className="text-button"
                  disabled={!file.available}
                  onClick={() => void open(false, true)}
                >
                  {t.shareFile}
                </button>
              )}
            </>
          )}
        </div>
        {error && (
          <p className="form-error" role="alert">
            {error}
          </p>
        )}
      </article>
      {preview && (
        <div className="file-preview-backdrop" onClick={() => setPreview(undefined)}>
          <section
            className="file-preview"
            role="dialog"
            aria-modal="true"
            aria-label={file.name}
            onClick={(e) => e.stopPropagation()}
          >
            <header>
              <strong>{file.name}</strong>
              <button
                className="icon-button"
                aria-label={t.close}
                onClick={() => setPreview(undefined)}
              >
                <Icon name="close" />
              </button>
            </header>
            {preview.text !== undefined ? (
              <pre>{preview.text}</pre>
            ) : file.mime === 'application/pdf' ? (
              <Suspense fallback={<SpinnerDots />}>
                <PdfPreview title={file.name} url={preview.url!} />
              </Suspense>
            ) : file.mime === 'image/svg+xml' ? (
              <iframe title={file.name} sandbox="" src={preview.url} />
            ) : (
              <img alt={file.name} src={preview.url} />
            )}
          </section>
        </div>
      )}
    </>
  );
}
export function MessageFiles({
  botId,
  messageId,
  t,
}: {
  botId: string;
  messageId: string;
  t: Texts;
}) {
  const [files, setFiles] = useState<Attachment[]>([]);
  const [error, setError] = useState('');
  useEffect(() => {
    void callNode('files.list', { botId, messageId })
      .then((v) => setFiles(v.files))
      .catch((e: Error) => setError(e.message));
  }, [botId, messageId]);
  return (
    <div className="message-files">
      {files.map((file) => (
        <FileCard key={file.fileId} file={file} t={t} />
      ))}
      {error && <p className="form-error">{error}</p>}
    </div>
  );
}
export function LibraryPanel({
  bot,
  t,
  onSource,
}: {
  bot: Bot;
  t: Texts;
  onSource(file: Attachment): void;
}) {
  const [search, setSearch] = useState('');
  const [type, setType] = useState('');
  const [files, setFiles] = useState<Attachment[]>();
  const [operation, setOperation] = useState<Operation>();
  const [error, setError] = useState('');
  const online = useAppStore(selectNodeData).online;
  const load = useCallback(async () => {
    try {
      setFiles((await callNode('files.list', { botId: bot.botId, search, type })).files);
      setError('');
    } catch (e) {
      setError(e instanceof Error ? e.message : t.failed);
    }
  }, [bot.botId, search, type, t.failed]);
  useEffect(() => {
    if (online)
      void callNode('files.list', { botId: bot.botId, search, type })
        .then((value) => setFiles(value.files))
        .catch((e: Error) => setError(e.message));
  }, [online, bot.botId, search, type]);
  async function backfill() {
    try {
      setOperation(await callNode('files.backfill', { botId: bot.botId }));
    } catch (e) {
      setError(e instanceof Error ? e.message : t.failed);
    }
  }
  return (
    <section className="detail-section">
      <h3>{t.botLibrary}</h3>
      <p className="muted">{t.fileCopyHint}</p>
      <div className="library-filters">
        <input
          aria-label={t.fileSearch}
          placeholder={t.fileSearch}
          value={search}
          onChange={(e) => setSearch(e.target.value)}
        />
        <select aria-label={t.allFileTypes} value={type} onChange={(e) => setType(e.target.value)}>
          <option value="">{t.allFileTypes}</option>
          <option value="image/">{t.images}</option>
          <option value="application/pdf">PDF</option>
          <option value="text/">{t.textFiles}</option>
          <option value="other">{t.otherFiles}</option>
        </select>
      </div>
      <div className="section-actions">
        <button
          className="text-button"
          disabled={!online || operation?.status === 'running'}
          onClick={() => void backfill()}
        >
          {t.backfillFiles}
        </button>
        <button className="text-button" disabled={!online} onClick={() => void load()}>
          {t.refresh}
        </button>
      </div>
      {operation && (
        <OperationProgress
          key={operation.operationId}
          initial={operation}
          t={t}
          onFinished={load}
        />
      )}
      {error && (
        <p className="form-error" role="alert">
          {error}
        </p>
      )}
      {!files ? (
        <SpinnerDots />
      ) : files.length ? (
        files.map((file) => (
          <FileCard key={file.fileId} file={file} t={t} onSource={() => onSource(file)} />
        ))
      ) : (
        <p className="empty-state">{t.noFiles}</p>
      )}
    </section>
  );
}
