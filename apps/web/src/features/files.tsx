import { AnimatedList } from '../components/ui/animated-list';
import { Dialog } from '../components/ui/dialog';
import { lazy, Suspense, useCallback, useEffect, useRef, useState } from 'react';
import { createPortal } from 'react-dom';
import type { Attachment, Bot, Operation } from '@nekodot/protocol';
import { callNode } from '../relay-connection';
import { selectNodeData, useAppStore } from '../store';
import { Icon, LoadingText } from '../ui';
import type { Texts } from '../shared';
import { relayUrl } from '../relay-url';
import { OperationProgress } from './operations';
import { android, saveDownload, shareFile } from '../native';
import { StateView } from '../components/ui/state-view';
const PdfPreview = lazy(() =>
  import('./pdf-preview').then((module) => ({ default: module.PdfPreview })),
);

export async function uploadChatFile(file: File, conversationId: string, nodeId: string) {
  const checkNode = () => {
    if (useAppStore.getState().selectedNodeId !== nodeId)
      throw new Error('Computer changed. Retry in the original conversation.');
  };
  checkNode();
  const { importId } = await callNode('imports.create', {});
  for (let offset = 0; offset < file.size || offset === 0; offset += 196608) {
    checkNode();
    const url = new URL(relayUrl(`/api/nodes/${encodeURIComponent(nodeId)}/imports/${importId}`));
    url.search = new URLSearchParams({ path: file.name, offset: String(offset) }).toString();
    const response = await fetch(url, {
      method: 'PUT',
      headers: {
        Authorization: 'Bearer ' + useAppStore.getState().token,
        'Content-Type': 'application/octet-stream',
      },
      body: file.slice(offset, offset + 196608),
      signal: AbortSignal.timeout(30_000),
    });
    if (!response.ok) throw new Error(`Upload HTTP ${response.status}`);
  }
  checkNode();
  return callNode('files.receive', { conversationId, importId, path: file.name });
}

export function DraftAttachment({
  file,
  nodeId,
  t,
  disabled,
  onRemove,
}: {
  file: Attachment;
  nodeId: string;
  t: Texts;
  disabled: boolean;
  onRemove(): void;
}) {
  const [image, setImage] = useState('');
  const dialog = useRef<HTMLDialogElement>(null);
  useEffect(() => {
    if (!file.mime.startsWith('image/')) return;
    let active = true,
      url = '';
    void fetchFile(nodeId, file.fileId)
      .then((blob) => {
        if (active) {
          url = URL.createObjectURL(blob);
          setImage(url);
        }
      })
      .catch(() => {
        /* FileCard shows the actual download error when opened. */
      });
    return () => {
      active = false;
      if (url) URL.revokeObjectURL(url);
    };
  }, [nodeId, file.fileId, file.mime]);
  return (
    <>
      <span className="prompt-attachment">
        <button
          type="button"
          className="prompt-thumbnail"
          aria-label={`${t.preview}: ${file.name}`}
          onClick={() => dialog.current?.showModal()}
        >
          {image ? <img src={image} alt={file.name} /> : <Icon name="doc" />}
        </button>
        <span title={file.name}>{file.name}</span>
        <button
          type="button"
          disabled={disabled}
          aria-label={`${t.close}: ${file.name}`}
          onClick={onRemove}
        >
          <Icon name="close" />
        </button>
      </span>
      {createPortal(
        <dialog className="draft-preview" ref={dialog} aria-label={file.name}>
          <button
            type="button"
            className="icon-button"
            aria-label={t.close}
            onClick={() => dialog.current?.close()}
          >
            <Icon name="close" />
          </button>
          {image && <img className="draft-preview-image" src={image} alt={file.name} />}
          <FileCard file={file} t={t} />
        </dialog>,
        document.body,
      )}
    </>
  );
}

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
            <LoadingText />
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
        <Dialog
          className="file-preview"
          backdropClassName="file-preview-backdrop"
          label={file.name}
          onClose={() => setPreview(undefined)}
        >
          <header>
            <strong>{file.name}</strong>
            <button
              className="icon-button dialog-close"
              aria-label={t.close}
              onClick={() => setPreview(undefined)}
            >
              <Icon name="close" />
            </button>
          </header>
          {preview.text !== undefined ? (
            <pre tabIndex={0}>{preview.text}</pre>
          ) : file.mime === 'application/pdf' ? (
            <Suspense fallback={<LoadingText />}>
              <PdfPreview title={file.name} url={preview.url!} />
            </Suspense>
          ) : file.mime === 'image/svg+xml' ? (
            <iframe title={file.name} sandbox="" src={preview.url} />
          ) : (
            <img alt={file.name} src={preview.url} />
          )}
        </Dialog>
      )}
    </>
  );
}
export function MessageFiles({ ids, t }: { ids: string[]; t: Texts }) {
  const [files, setFiles] = useState<Attachment[]>([]);
  const [error, setError] = useState('');
  useEffect(() => {
    void Promise.all(ids.map((fileId) => callNode('files.get', { fileId })))
      .then(setFiles)
      .catch((e: Error) => setError(e.message));
  }, [ids]);
  return (
    <AnimatedList className="message-files">
      {files.map((file) => (
        <FileCard key={file.fileId} file={file} t={t} />
      ))}
      {error && <p className="form-error">{error}</p>}
    </AnimatedList>
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
        <LoadingText />
      ) : files.length ? (
        <AnimatedList>
          {files.map((file) => (
            <FileCard key={file.fileId} file={file} t={t} onSource={() => onSource(file)} />
          ))}
        </AnimatedList>
      ) : (
        <StateView kind="empty" compact message={t.noFiles} />
      )}
    </section>
  );
}
