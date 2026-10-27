import { useEffect, useState, type FormEvent } from 'react';
import { AnimatePresence, motion, useReducedMotion } from 'motion/react';
import type { Bot, Conversation } from '@nekodot/protocol';
import { callNode } from '../relay-connection';
import { selectNodeData, useAppStore } from '../store';
import { BotAvatar, Icon, SpinnerDots } from '../ui';
import { avatarColors, type Texts } from '../shared';

function modelIds(value: unknown): string[] {
  const result = new Set<string>();
  const visit = (item: unknown) => {
    if (Array.isArray(item)) {
      for (const entry of item) {
        if (typeof entry === 'string') result.add(entry);
        else if (entry && typeof entry === 'object') {
          const value = entry as Record<string, unknown>;
          const id = value.id ?? value.model;
          if (typeof id === 'string') result.add(id);
          if (value.models) visit(value.models);
        }
      }
    } else if (item && typeof item === 'object') {
      for (const [key, entry] of Object.entries(item)) {
        if (key === 'models') visit(entry);
        else if (entry && typeof entry === 'object') visit(entry);
      }
    }
  };
  visit(value);
  return [...result];
}

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
  const [model, setModel] = useState(value?.model ?? '');
  const [color, setColor] = useState(value?.avatar.color ?? avatarColors[0]!);
  const [advanced, setAdvanced] = useState(false);
  const [models, setModels] = useState<string[]>([]);
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);
  const reduceMotion = useReducedMotion();

  useEffect(() => {
    void callNode('models.options', {})
      .then((options) => setModels(modelIds(options)))
      .catch(() => {});
  }, []);
  async function submit(event: FormEvent) {
    event.preventDefault();
    setBusy(true);
    setError('');
    try {
      const effectiveHandle = handle || handleFromName(name);
      if (value) {
        const result = await callNode('bots.update', {
          botId: value.botId,
          displayName: name,
          handle: effectiveHandle,
          role,
          model,
          avatar: { shape: 'dot', color },
        });
        onSaved(result.bot);
      } else {
        const result = await callNode('bots.create', {
          displayName: name,
          handle: effectiveHandle,
          role,
          model,
          avatar: { shape: 'dot', color },
        });
        onSaved(result.bot);
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
  return (
    <motion.div
      className="dialog-backdrop"
      initial={{ opacity: 0 }}
      animate={{ opacity: 1 }}
      exit={{ opacity: 0 }}
      transition={{ duration: reduceMotion ? 0.1 : 0.18 }}
      onMouseDown={(event) => {
        if (event.target === event.currentTarget) onClose();
      }}
    >
      <motion.form
        className="bot-dialog"
        initial={{ opacity: 0, y: reduceMotion ? 0 : 18, scale: reduceMotion ? 1 : 0.98 }}
        animate={{ opacity: 1, y: 0, scale: 1 }}
        exit={{ opacity: 0, y: reduceMotion ? 0 : 8 }}
        transition={{ duration: reduceMotion ? 0.1 : 0.22 }}
        onSubmit={(event) => void submit(event)}
      >
        <header>
          <div>
            <span className="eyebrow">
              <i /> NEKO DOT
            </span>
            <h2>{value ? t.editBot : t.newBot}</h2>
          </div>
          <button type="button" className="icon-button" onClick={onClose} aria-label={t.close}>
            <Icon name="close" />
          </button>
        </header>
        <div className="avatar-picker">
          <BotAvatar color={color} size={62} />
          <div>
            <strong>{t.avatarColor}</strong>
            <div className="color-swatches">
              {avatarColors.map((swatch) => (
                <button
                  type="button"
                  className={swatch === color ? 'selected' : ''}
                  key={swatch}
                  style={{ backgroundColor: swatch }}
                  aria-label={swatch}
                  onClick={() => setColor(swatch)}
                />
              ))}
            </div>
          </div>
        </div>
        <label>
          {t.name}
          <input
            required
            autoFocus
            value={name}
            onChange={(event) => setName(event.target.value)}
            placeholder="Mochi"
          />
        </label>
        <label>
          {t.role}
          <textarea
            rows={3}
            value={role}
            onChange={(event) => setRole(event.target.value)}
            placeholder={t.rolePlaceholder}
          />
        </label>
        <label>
          {t.model}
          <input
            required
            list="model-options"
            value={model}
            onChange={(event) => setModel(event.target.value)}
            placeholder={t.modelPlaceholder}
          />
          <datalist id="model-options">
            {models.map((item) => (
              <option value={item} key={item} />
            ))}
          </datalist>
        </label>
        {!models.length && <small className="muted">{t.noModel}</small>}
        <button type="button" className="advanced-toggle" onClick={() => setAdvanced(!advanced)}>
          <Icon name="chevron" />
          {t.advanced}
        </button>
        <AnimatePresence>
          {advanced && (
            <motion.label
              className="advanced-field"
              initial={{ height: 0, opacity: 0 }}
              animate={{ height: 'auto', opacity: 1 }}
              exit={{ height: 0, opacity: 0 }}
            >
              @ {t.handle}
              <input
                required
                pattern="[a-z0-9-]{1,24}"
                value={handle || handleFromName(name)}
                onChange={(event) => setHandle(event.target.value)}
              />
            </motion.label>
          )}
        </AnimatePresence>
        {error && (
          <p className="form-error" role="alert">
            {error}
          </p>
        )}
        <footer>
          {value && (
            <button
              type="button"
              className="archive-button"
              disabled={busy}
              onClick={() => void archive()}
            >
              {t.archive}
            </button>
          )}
          <button type="button" className="secondary-button" onClick={onClose}>
            {t.cancel}
          </button>
          <button className="primary-button" disabled={busy || !node.online}>
            {busy ? <SpinnerDots /> : value ? t.save : t.createBot}
            <Icon name="arrow" />
          </button>
        </footer>
      </motion.form>
    </motion.div>
  );
}
