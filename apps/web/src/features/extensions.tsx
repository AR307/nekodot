import { useCallback, useEffect, useRef, useState, type InputHTMLAttributes } from 'react';
import {
  transferChunkBytes,
  type Extension,
  type Operation,
  type Bot,
  type RpcParams,
  type RpcResult,
} from '@nekodot/protocol';
import { callNode } from '../relay-connection';
import { selectNodeData, useAppStore } from '../store';
import { BotAvatar, Icon, SpinnerDots } from '../ui';
import type { Texts } from '../shared';
import { OperationProgress } from './operations';
import { relayUrl } from '../relay-url';
import { native, android, chooseImportFiles } from '../native';
import { Markdown } from './markdown';

export function ExtensionsPage({ kind, t }: { kind: 'skills' | 'plugins'; t: Texts }) {
  const node = useAppStore(selectNodeData);
  const nodeId = useAppStore((state) => state.selectedNodeId)!;
  const [entries, setEntries] = useState<Extension[]>();
  const [search, setSearch] = useState('');
  const [category, setCategory] = useState('');
  const [error, setError] = useState('');
  const [selected, setSelected] = useState<string>();
  const [importOpen, setImportOpen] = useState(false);
  const [identifier, setIdentifier] = useState('');
  const [botIds, setBotIds] = useState<string[]>([]);
  const [operation, setOperation] = useState<Operation>();
  const [upload, setUpload] = useState('');
  const [busy, setBusy] = useState(false);
  const [content, setContent] = useState<RpcResult<'extensions.content'>>();
  const [contentError, setContentError] = useState('');
  const [fullContent, setFullContent] = useState(false);
  const filesRef = useRef<HTMLInputElement>(null);
  const folderRef = useRef<HTMLInputElement>(null);
  const activeBots = node.bots.filter((bot) => !bot.archived);
  const load = useCallback(async () => {
    try {
      setEntries((await callNode('extensions.list', { kind })).entries);
      setError('');
    } catch (e) {
      setError(e instanceof Error ? e.message : t.failed);
    }
  }, [kind, t.failed]);
  const completed = useCallback(
    (value: Operation) => {
      setOperation(value);
      void load();
    },
    [load],
  );
  useEffect(() => {
    if (!node.online) return;
    void callNode('extensions.list', { kind })
      .then((value) => setEntries(value.entries))
      .catch((e: Error) => setError(e.message));
    void callNode('operations.list', {})
      .then((value) =>
        setOperation(value.operations.find((op) => op.kind.startsWith('extensions.'))),
      )
      .catch((e: Error) => setError(e.message));
  }, [kind, node.online]);
  const entry = entries?.find((row) => row.id === selected);
  useEffect(() => {
    if (!entry || !node.online) return;
    let current = true;
    const installed = entry.states.find((row) => row.installed);
    void callNode('extensions.content', {
      kind,
      name: entry.id,
      botId: installed?.botId,
      ...(!installed && entry.identifier ? { identifier: entry.identifier } : {}),
    }).then(
      (value) => current && setContent(value),
      (e: Error) => current && setContentError(e.message),
    );
    return () => {
      current = false;
    };
  }, [entry, kind, node.online]);
  const filtered = entries?.filter(
    (row) =>
      (!category || row.category === category) &&
      (!search ||
        `${row.name} ${row.description} ${row.category}`
          .toLowerCase()
          .includes(search.toLowerCase())),
  );
  function sourceLabel(source: string) {
    return ['official', 'builtin', 'bundled'].includes(source)
      ? source === 'official'
        ? t.officialSource
        : t.builtinSource
      : ['community', 'verified'].includes(source)
        ? t.communitySource
        : ['local', 'user'].includes(source)
          ? t.localSource
          : source;
  }
  async function install(importId?: string) {
    setBusy(true);
    setError('');
    try {
      setOperation(
        await callNode('extensions.install', {
          kind,
          botIds,
          ...(importId ? { importId } : { identifier: identifier.trim() }),
        }),
      );
      setImportOpen(false);
    } catch (e) {
      setError(e instanceof Error ? e.message : t.failed);
    } finally {
      setBusy(false);
    }
  }
  async function importFiles(files: FileList | File[] | null) {
    if (!files?.length || !botIds.length) return;
    setBusy(true);
    setError('');
    try {
      const { importId } = await callNode('imports.create', {});
      let done = 0;
      const total = Array.from(files).reduce((n, file) => n + file.size, 0);
      for (const file of Array.from(files)) {
        const path = file.webkitRelativePath || file.name;
        for (let offset = 0; offset < file.size || offset === 0; offset += transferChunkBytes) {
          const body = await file.slice(offset, offset + transferChunkBytes).arrayBuffer();
          const response = await fetch(
            relayUrl(
              `/api/nodes/${encodeURIComponent(nodeId)}/imports/${importId}?` +
                new URLSearchParams({ path, offset: String(offset) }),
            ),
            {
              method: 'PUT',
              headers: {
                Authorization: 'Bearer ' + localStorage.getItem('nekodot-token'),
                'Content-Type': 'application/octet-stream',
              },
              body,
            },
          );
          if (!response.ok) {
            const value = (await response.json()) as { error?: { message?: string } };
            throw new Error(value.error?.message ?? 'Upload failed');
          }
          done += body.byteLength;
          setUpload(
            `${t.uploading} ${total ? Math.round((done / total) * 100) : 100}% · ${file.name}`,
          );
        }
      }
      await install(importId);
      setUpload('');
    } catch (e) {
      setError(e instanceof Error ? e.message : t.failed);
    } finally {
      setBusy(false);
    }
  }
  async function chooseFiles(directory: boolean) {
    try {
      await importFiles(await chooseImportFiles(directory));
    } catch (e) {
      setError(e instanceof Error ? e.message : t.failed);
    }
  }
  async function toggle(botId: string, enabled: boolean) {
    if (!entry) return;
    try {
      const row = (entry.native.installed as Record<string, { key?: string }> | undefined)?.[botId];
      setOperation(
        await callNode('extensions.toggle', {
          kind,
          botIds: [botId],
          name: kind === 'plugins' ? (row?.key ?? entry.id) : entry.id,
          enabled,
        }),
      );
    } catch (e) {
      setError(e instanceof Error ? e.message : t.failed);
    }
  }
  function openInstall(value?: Extension) {
    setIdentifier(value?.identifier ?? '');
    setBotIds([]);
    setImportOpen(true);
    setError('');
  }
  async function restart() {
    try {
      setOperation(await callNode('hermes.restart', {}));
    } catch (e) {
      setError(e instanceof Error ? e.message : t.failed);
    }
  }
  return (
    <div className="extensions-page">
      <header className="extensions-header">
        <div>
          <span className="eyebrow">HERMES / {kind.toUpperCase()}</span>
          <h1>{kind === 'skills' ? t.skillsPage : t.pluginsPage}</h1>
          <p className="muted">{t.extensionTiming}</p>
        </div>
        <button
          className="primary-button"
          disabled={!node.online || !activeBots.length}
          onClick={() => openInstall()}
        >
          <Icon name="plus" />
          {t.importExtension}
        </button>
      </header>
      <div className="extensions-toolbar">
        <input
          aria-label={t.extensionSearch}
          placeholder={t.extensionSearch}
          value={search}
          onChange={(e) => setSearch(e.target.value)}
        />
        <select
          aria-label={t.allCategories}
          value={category}
          onChange={(e) => setCategory(e.target.value)}
        >
          <option value="">{t.allCategories}</option>
          {[...new Set(entries?.map((row) => row.category))].sort().map((value) => (
            <option key={value}>{value}</option>
          ))}
        </select>
        <button className="text-button" disabled={!node.online} onClick={() => void load()}>
          {t.refresh}
        </button>
      </div>
      {!node.online && <p className="offline-strip">{t.offline}</p>}
      {error && (
        <p className="form-error" role="alert">
          {error}
        </p>
      )}
      {!activeBots.length && <p className="empty-state">{t.noBotForExtensions}</p>}
      {operation && (
        <OperationProgress
          key={operation.operationId}
          initial={operation}
          t={t}
          onFinished={completed}
        />
      )}
      {operation?.results.some((row) => row.native?.restart_required) && (
        <p className="restart-notice">
          {t.restartHint}
          <button className="text-button" onClick={() => void restart()}>
            {t.restartHermes}
          </button>
        </p>
      )}
      <div className="extension-grid">
        {!entries ? (
          <SpinnerDots />
        ) : !filtered?.length ? (
          <p className="empty-state">{t.noExtensions}</p>
        ) : (
          filtered.map((row) => (
            <button
              className="extension-card"
              key={row.id}
              onClick={() => {
                setSelected(row.id);
                setContent(undefined);
                setContentError('');
                setFullContent(false);
              }}
            >
              <div className="extension-card-heading">
                <span className={`extension-mark ${kind}`}>
                  <ExtensionIcon icon={row.icon} kind={kind} />
                </span>
                <span className="source-badge">{sourceLabel(row.source)}</span>
              </div>
              <h3>{row.name}</h3>
              <p>{row.description}</p>
              <footer>
                <span>{row.category}</span>
                <span>
                  {row.states.length
                    ? `${row.states.filter((state) => state.enabled).length} / ${activeBots.length} ${t.enabled}`
                    : t.notInstalled}
                </span>
              </footer>
            </button>
          ))
        )}
      </div>
      {entry && (
        <div className="dialog-backdrop extension-overlay" onClick={() => setSelected(undefined)}>
          <section
            className="extension-detail"
            style={fullContent ? { display: 'none' } : undefined}
            role="dialog"
            aria-modal="true"
            aria-label={entry.name}
            onClick={(e) => e.stopPropagation()}
          >
            <header>
              <span className="source-badge">{sourceLabel(entry.source)}</span>
              <button
                className="icon-button"
                aria-label={t.close}
                onClick={() => setSelected(undefined)}
              >
                <Icon name="close" />
              </button>
            </header>
            <div className="extension-detail-scroll">
              <h2>{entry.name}</h2>
              <span className={`extension-mark ${kind}`}>
                <ExtensionIcon icon={content?.icon ?? entry.icon} kind={kind} />
              </span>
              <p className="preserve-lines">{entry.description}</p>
              {content?.repository || entry.repository ? (
                <a
                  className="extension-repository"
                  href={content?.repository ?? entry.repository}
                  target="_blank"
                  rel="noreferrer noopener"
                >
                  {content?.repository ?? entry.repository}
                </a>
              ) : (
                <p className="muted">{t.noRepository}</p>
              )}
              {entry.desktop && <p className="scope-badge">{t.desktopOnly}</p>}
              {entry.platforms.length > 0 && (
                <p>
                  {t.platformRequirements}: {entry.platforms.join(', ')}
                </p>
              )}
              {entry.dependencies.length > 0 && (
                <p>
                  {t.dependencies}: {entry.dependencies.join(', ')}
                </p>
              )}
              <div className="section-actions">
                {content?.content && (
                  <button className="secondary-button" onClick={() => setFullContent(true)}>
                    {t.extensionContents}
                  </button>
                )}
                {entry.identifier && (
                  <button className="primary-button" onClick={() => openInstall(entry)}>
                    {t.installExtension}
                  </button>
                )}
              </div>
              {contentError && (
                <p className="form-error" role="alert">
                  {contentError}
                </p>
              )}
              {content ? (
                <>
                  <div className="skill-content extension-preview">
                    {content.content ? (
                      <Markdown
                        text={content.content}
                        copyLabel={t.copyText}
                        copiedLabel={t.copied}
                      />
                    ) : (
                      t.noExtensionDocument
                    )}
                  </div>
                  <ul className="extension-files">
                    {content.files.map((file) => (
                      <li key={file}>{file}</li>
                    ))}
                  </ul>
                </>
              ) : (
                !contentError && <SpinnerDots />
              )}
              <h3>{t.installedStates}</h3>
              {activeBots.map((bot) => {
                const state = entry.states.find((row) => row.botId === bot.botId);
                return (
                  <div className="extension-bot-state" key={bot.botId}>
                    <BotAvatar color={bot.avatar.color} size={30} />
                    <div>
                      <strong>{bot.displayName}</strong>
                      <small>{state ? state.status : t.notInstalled}</small>
                    </div>
                    {state?.installed && (
                      <button
                        className="text-button"
                        disabled={!node.online}
                        onClick={() => void toggle(bot.botId, !state.enabled)}
                      >
                        {state.enabled ? t.disableExtension : t.enableExtension}
                      </button>
                    )}
                  </div>
                );
              })}
              {kind === 'plugins' && (
                <PluginConfiguration
                  entry={entry}
                  bots={activeBots}
                  t={t}
                  onOperation={setOperation}
                />
              )}
            </div>
          </section>
          {fullContent && content && (
            <section
              className="extension-full-content"
              role="dialog"
              aria-modal="true"
              aria-label={t.extensionContents}
              onClick={(e) => e.stopPropagation()}
            >
              <header>
                <button
                  className="icon-button"
                  aria-label={t.backPage}
                  onClick={() => setFullContent(false)}
                >
                  <Icon name="back" />
                </button>
                <h2>{entry.name}</h2>
              </header>
              <div className="extension-detail-scroll">
                <div className="skill-content">
                  <Markdown text={content.content} copyLabel={t.copyText} copiedLabel={t.copied} />
                </div>
                <ul className="extension-files">
                  {content.files.map((file) => (
                    <li key={file}>{file}</li>
                  ))}
                </ul>
              </div>
            </section>
          )}
        </div>
      )}
      {importOpen && (
        <div
          className="dialog-backdrop extension-import-overlay"
          onClick={() => !busy && setImportOpen(false)}
        >
          <section
            className="extension-import"
            role="dialog"
            aria-modal="true"
            aria-label={t.importExtension}
            onClick={(e) => e.stopPropagation()}
          >
            <header>
              <h2>{t.installExtension}</h2>
              <button
                className="icon-button"
                aria-label={t.close}
                disabled={busy}
                onClick={() => setImportOpen(false)}
              >
                <Icon name="close" />
              </button>
            </header>
            <div className="extension-import-body">
              <p className="muted">{t.importHelp}</p>
              <label>{t.selectBots}</label>
              <div className="bot-install-picker">
                {activeBots.map((bot) => (
                  <label key={bot.botId}>
                    <input
                      type="checkbox"
                      checked={botIds.includes(bot.botId)}
                      onChange={(e) =>
                        setBotIds(
                          e.target.checked
                            ? [...botIds, bot.botId]
                            : botIds.filter((id) => id !== bot.botId),
                        )
                      }
                    />
                    <BotAvatar color={bot.avatar.color} size={28} />
                    {bot.displayName}
                  </label>
                ))}
              </div>
              <label>
                {t.gitSource}
                <input
                  value={identifier}
                  onChange={(e) => setIdentifier(e.target.value)}
                  placeholder={t.gitPlaceholder}
                />
              </label>
              <button
                className="primary-button"
                disabled={busy || !botIds.length || !identifier.trim() || !node.online}
                onClick={() => void install()}
              >
                {busy ? <SpinnerDots /> : t.installExtension}
              </button>
              <div className="import-local">
                <button
                  className="secondary-button"
                  disabled={busy || !botIds.length || !node.online}
                  onClick={() => (native ? void chooseFiles(false) : filesRef.current?.click())}
                >
                  {t.selectFiles}
                </button>
                {!android && (
                  <button
                    className="secondary-button"
                    disabled={busy || !botIds.length || !node.online}
                    onClick={() => (native ? void chooseFiles(true) : folderRef.current?.click())}
                  >
                    {t.selectFolder}
                  </button>
                )}
                <input
                  hidden
                  ref={filesRef}
                  type="file"
                  multiple
                  accept={kind === 'skills' ? '.md,.zip' : '.zip'}
                  onChange={(e) => void importFiles(e.target.files)}
                />
                <input
                  hidden
                  ref={folderRef}
                  type="file"
                  multiple
                  {...({ webkitdirectory: '' } as InputHTMLAttributes<HTMLInputElement>)}
                  onChange={(e) => void importFiles(e.target.files)}
                />
              </div>
              {upload && <p role="status">{upload}</p>}
              {error && (
                <p role="alert" className="form-error">
                  {error}
                </p>
              )}
            </div>
          </section>
        </div>
      )}
    </div>
  );
}
function ExtensionIcon({ icon, kind }: { icon?: string; kind: 'skills' | 'plugins' }) {
  return icon && /^(https:\/\/|data:image\/)/.test(icon) ? (
    <img className="extension-icon-image" src={icon} alt="" />
  ) : icon && [...icon].length <= 8 ? (
    <span>{icon}</span>
  ) : (
    <Icon name={kind === 'skills' ? 'spark' : 'plugin'} />
  );
}
interface SettingField {
  key: string;
  label: string;
  type: string;
  description: string;
  value?: unknown;
  default?: unknown;
  choices?: string[];
  required?: boolean;
  has_value?: boolean;
}
function PluginConfiguration({
  entry,
  bots,
  t,
  onOperation,
}: {
  entry: Extension;
  bots: Bot[];
  t: Texts;
  onOperation(value: Operation): void;
}) {
  const [botId, setBotId] = useState(entry.states[0]?.botId ?? '');
  const [values, setValues] = useState<Record<string, string | number | boolean>>({});
  const [error, setError] = useState('');
  const row = (
    entry.native.installed as
      Record<string, { settings_schema?: SettingField[]; key?: string }> | undefined
  )?.[botId];
  const fields = row?.settings_schema ?? [];
  async function save() {
    try {
      const submitted: RpcParams<'extensions.configure'>['values'] = {};
      for (const [key, value] of Object.entries(values))
        submitted[key] =
          fields.find((field) => field.key === key)?.type === 'json'
            ? JSON.parse(String(value))
            : value;
      onOperation(
        await callNode('extensions.configure', {
          botId,
          name: row?.key ?? entry.id,
          values: submitted,
        }),
      );
      setValues({});
      setError('');
    } catch (e) {
      setError(e instanceof Error ? e.message : t.failed);
    }
  }
  if (!entry.states.length) return null;
  return (
    <section className="plugin-configuration">
      <h3>{t.extensionConfiguration}</h3>
      <select
        aria-label={t.selectBots}
        value={botId}
        onChange={(e) => {
          setBotId(e.target.value);
          setValues({});
        }}
      >
        {entry.states.map((state) => (
          <option key={state.botId} value={state.botId}>
            {bots.find((bot) => bot.botId === state.botId)?.displayName}
          </option>
        ))}
      </select>
      {fields.map((field) => (
        <label key={field.key}>
          {field.label || field.key}
          {field.type === 'boolean' ? (
            <input
              type="checkbox"
              checked={Boolean(values[field.key] ?? field.value)}
              onChange={(e) => setValues({ ...values, [field.key]: e.target.checked })}
            />
          ) : field.type === 'enum' ? (
            <select
              value={String(values[field.key] ?? field.value ?? '')}
              onChange={(e) => setValues({ ...values, [field.key]: e.target.value })}
            >
              {field.choices?.map((value) => (
                <option key={value}>{value}</option>
              ))}
            </select>
          ) : field.type === 'json' ? (
            <textarea
              value={String(
                values[field.key] ?? JSON.stringify(field.value ?? field.default ?? {}, null, 2),
              )}
              onChange={(e) => setValues({ ...values, [field.key]: e.target.value })}
            />
          ) : (
            <input
              type={
                field.type === 'secret' ? 'password' : field.type === 'number' ? 'number' : 'text'
              }
              autoComplete="off"
              placeholder={field.type === 'secret' ? t.secretPlaceholder : undefined}
              value={String(
                values[field.key] ?? (field.type === 'secret' ? '' : (field.value ?? '')),
              )}
              onChange={(e) =>
                setValues({
                  ...values,
                  [field.key]: field.type === 'number' ? Number(e.target.value) : e.target.value,
                })
              }
            />
          )}
          <small className="muted">{field.description}</small>
        </label>
      ))}
      {fields.length > 0 && (
        <button
          className="secondary-button"
          disabled={!Object.keys(values).length}
          onClick={() => void save()}
        >
          {t.save}
        </button>
      )}
      {error && <p className="form-error">{error}</p>}
    </section>
  );
}
