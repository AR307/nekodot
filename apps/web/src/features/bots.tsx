import { useEffect, useRef, useState, type FormEvent } from 'react';
import { AnimatePresence, motion, useReducedMotion } from 'motion/react';
import type { ApprovalMode, Bot, Conversation, ProviderSource } from '@nekodot/protocol';
import { avatarShapes } from '@nekodot/protocol';
import { callNode } from '../relay-connection';
import { selectNodeData, useAppStore } from '../store';
import { BotAvatar, Icon, SpinnerDots, ease } from '../ui';
import { avatarColors, fill, type Texts } from '../shared';
import { ModelPicker, useModelOptions } from './models';
import { Sheet } from './sheet';

function handleFromName(name: string) {
  return (
    name
      .normalize('NFKD')
      .toLowerCase()
      .replace(/[^a-z0-9-]+/g, '-')
      .replace(/^-+|-+$/g, '')
      .slice(0, 24) || 'assistant'
  );
}

export function BotDialog({
  t,
  value,
  onClose,
  onSaved,
}: {
  t: Texts;
  value?: Bot;
  onClose(): void;
  onSaved(bot?: Bot, conversation?: Conversation): void;
}) {
  const node = useAppStore(selectNodeData);
  const [name, setName] = useState(value?.displayName ?? '');
  const [handle, setHandle] = useState(value?.handle ?? '');
  const [role, setRole] = useState(value?.role ?? '');
  const loadedRole = useRef(value?.role ?? '');
  const [model, setModel] = useState(value?.model ?? '');
  const [color, setColor] = useState(value?.avatar.color ?? avatarColors[0]!);
  const [shape, setShape] = useState<(typeof avatarShapes)[number]>(value?.avatar.shape ?? 'dot');
  const [advanced, setAdvanced] = useState(false);
  const [sourceId, setSourceId] = useState(value?.sourceId ?? '');
  const [sources, setSources] = useState<ProviderSource[]>([]);
  const [contextLength, setContextLength] = useState(
    value?.modelSettings?.contextLength?.toString() ?? '',
  );
  const catalog = useModelOptions(node.online, sourceId);
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);
  const [approvalMode, setApprovalMode] = useState<ApprovalMode>('manual');
  const [permissionsReady, setPermissionsReady] = useState(!value);
  const reduceMotion = useReducedMotion();
  const effectiveHandle = handle || handleFromName(name);

  useEffect(() => {
    void callNode('providers.list', {})
      .then(({ sources }) => {
        setSources(sources.filter((entry) => entry.ready));
        if (!value) setSourceId(sources.find((entry) => entry.ready)?.sourceId ?? '');
      })
      .catch((e: Error) => setError(e.message));
  }, [value]);

  useEffect(() => {
    if (!value) return;
    void Promise.all([
      callNode('bots.permissions.get', { botId: value.botId }),
      callNode('memory.get', { botId: value.botId }),
    ])
      .then(([{ mode }, memory]) => {
        const soul = memory.documents.find((doc) => doc.name === 'SOUL.md')!;
        const identity = soul.content
          .replace(/<!-- nekodot managed:[\s\S]*?<!-- end nekodot managed -->\n?/, '')
          .trimEnd();
        loadedRole.current = identity;
        setRole(identity);
        setApprovalMode(mode);
        setPermissionsReady(true);
      })
      .catch((reason: unknown) => setError(reason instanceof Error ? reason.message : t.saveError));
  }, [value, t.saveError]);

  async function submit(event: FormEvent) {
    event.preventDefault();
    setBusy(true);
    setError('');
    try {
      if (value) {
        if (role !== loadedRole.current)
          await callNode('memory.save', { botId: value.botId, name: 'SOUL.md', content: role });
        const result = await callNode('bots.update', {
          botId: value.botId,
          displayName: name,
          handle: effectiveHandle,
          model,
          ...(sourceId ? { sourceId } : {}),
          modelSettings: { contextLength: contextLength ? Number(contextLength) : null },
          approvalMode,
          avatar: { shape, color },
        });
        onSaved(result.bot);
      } else {
        const result = await callNode('bots.create', {
          displayName: name,
          handle: effectiveHandle,
          role,
          model,
          sourceId,
          modelSettings: { contextLength: contextLength ? Number(contextLength) : null },
          approvalMode,
          avatar: { shape, color },
        });
        onSaved(result.bot, result.conversation);
      }
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : t.saveError);
    } finally {
      setBusy(false);
    }
  }

  async function archive() {
    if (!value) return;
    setBusy(true);
    try {
      await callNode('bots.archive', { botId: value.botId });
      onSaved();
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : t.saveError);
    } finally {
      setBusy(false);
    }
  }

  const disabled = busy || !node.online || !permissionsReady || (!value && !sourceId);
  return (
    <Sheet
      className="bot-dialog"
      title={value ? t.editBot : t.newBot}
      titleId="bot-dialog-title"
      closeLabel={t.close}
      onClose={onClose}
      onSubmit={(event) => void submit(event)}
      footer={
        value ? (
          <>
            <button
              type="button"
              className="archive-button"
              disabled={busy}
              onClick={() => void archive()}
            >
              {t.archive}
            </button>
            <button type="button" className="secondary-button" onClick={onClose}>
              {t.cancel}
            </button>
            <button className="primary-button" disabled={disabled}>
              {busy && <SpinnerDots />}
              {t.save}
            </button>
          </>
        ) : (
          <button className="primary-button full-button" disabled={disabled}>
            {busy && <SpinnerDots />}
            {name.trim() ? fill(t.createNamed, { name: name.trim() }) : t.createBot}
          </button>
        )
      }
    >
      <div className="avatar-stage" aria-hidden="true">
        <motion.span
          key={shape + color}
          className="avatar-stage-pet"
          initial={reduceMotion ? false : { scale: 0.86, rotate: -4 }}
          animate={{ scale: 1, rotate: 0 }}
          transition={{ type: 'spring', stiffness: 420, damping: 16 }}
        >
          <BotAvatar color={color} shape={shape} size={88} />
        </motion.span>
        <span className="avatar-stage-glow" style={{ background: color }} />
        <strong>{name.trim() || t.unnamedBot}</strong>
        <small>@{effectiveHandle}</small>
      </div>
      <label className="field">
        {t.name}
        <input
          required
          autoFocus
          value={name}
          onChange={(event) => setName(event.target.value)}
          placeholder="Mochi"
        />
      </label>
      <fieldset className="field">
        <legend>{t.avatarShape}</legend>
        <div className="avatar-shapes">
          {avatarShapes.map((option, index) => (
            <button
              type="button"
              className={option === shape ? 'selected' : ''}
              key={option}
              aria-label={t.shapeNames[index] + (option === shape ? ` (${t.selected})` : '')}
              aria-pressed={option === shape}
              onClick={() => setShape(option)}
            >
              <BotAvatar color={color} shape={option} size={30} />
            </button>
          ))}
        </div>
      </fieldset>
      <fieldset className="field">
        <legend>{t.avatarColor}</legend>
        <div className="color-swatches">
          {avatarColors.map((swatch, index) => (
            <button
              type="button"
              className={swatch === color ? 'selected' : ''}
              key={swatch}
              aria-label={t.colorNames[index] + (swatch === color ? ` (${t.selected})` : '')}
              aria-pressed={swatch === color}
              onClick={() => setColor(swatch)}
            >
              <span style={{ backgroundColor: swatch }} />
              {swatch === color && (
                <motion.i
                  layoutId="swatch-ring"
                  transition={
                    reduceMotion ? { duration: 0 } : { type: 'spring', stiffness: 520, damping: 34 }
                  }
                />
              )}
            </button>
          ))}
        </div>
      </fieldset>
      <label className="field">
        {t.role}
        <textarea
          rows={3}
          value={role}
          onChange={(event) => setRole(event.target.value)}
          placeholder={t.rolePlaceholder}
        />
        <small>{t.roleHint}</small>
      </label>
      <label className="field">
        {t.modelSource}
        <select
          aria-label={t.modelSource}
          value={sourceId}
          onChange={(event) => {
            setSourceId(event.target.value);
            setModel('');
          }}
          required={!value}
        >
          <option value="" disabled>
            {t.chooseSource}
          </option>
          {sources.map((source) => (
            <option key={source.sourceId} value={source.sourceId}>
              {source.name}
            </option>
          ))}
        </select>
        {!sources.length && <small>{t.waitingForProvider}</small>}
      </label>
      <ModelPicker
        t={t}
        value={model}
        onChange={setModel}
        catalog={catalog}
        disabled={!node.online || !sourceId}
        required
      />
      <label className="field">
        {t.toolPermissions}
        <select
          value={approvalMode}
          disabled={!permissionsReady}
          onChange={(event) => setApprovalMode(event.target.value as ApprovalMode)}
        >
          <option value="manual">{t.permissionsManual}</option>
          <option value="smart">{t.permissionsSmart}</option>
          <option value="off">{t.permissionsOff}</option>
        </select>
        <small className={approvalMode === 'off' ? 'permission-notice' : undefined}>
          {approvalMode === 'off'
            ? t.permissionsOffHelp
            : approvalMode === 'smart'
              ? t.permissionsSmartHelp
              : t.permissionsManualHelp}
        </small>
      </label>
      <div className="advanced">
        <button
          type="button"
          className="advanced-toggle"
          aria-expanded={advanced}
          onClick={() => setAdvanced(!advanced)}
        >
          {t.advanced}
          <Icon name="chevronDown" />
        </button>
        <AnimatePresence initial={false}>
          {advanced && (
            <motion.div
              className="advanced-body"
              initial={{ height: 0, opacity: 0 }}
              animate={{ height: 'auto', opacity: 1 }}
              exit={{ height: 0, opacity: 0 }}
              transition={{ duration: reduceMotion ? 0.1 : 0.24, ease }}
            >
              <label className="field advanced-field">
                {t.contextOverride}
                <input
                  aria-label={t.contextOverride}
                  type="number"
                  min="1"
                  step="1"
                  value={contextLength}
                  onChange={(event) => setContextLength(event.target.value)}
                  placeholder={t.nativeAuto}
                />
                <small>{t.capacityHint}</small>
              </label>
              <label className="field advanced-field">
                @ {t.handle}
                <span className="input-prefix">
                  <i>@</i>
                  <input
                    required
                    pattern="[a-z0-9-]{1,24}"
                    value={effectiveHandle}
                    onChange={(event) => setHandle(event.target.value)}
                  />
                </span>
                <small>{t.handleHint}</small>
              </label>
            </motion.div>
          )}
        </AnimatePresence>
      </div>
      {error && (
        <p className="form-error" role="alert">
          {error}
        </p>
      )}
      {!node.online && (
        <p className="form-error" role="status">
          {t.offlineCreateHint}
        </p>
      )}
    </Sheet>
  );
}
