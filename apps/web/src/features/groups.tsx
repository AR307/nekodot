import { useState, type FormEvent } from 'react';
import { motion, useReducedMotion } from 'motion/react';
import type { Group } from '@nekodot/protocol';
import { callNode } from '../relay-connection';
import { selectNodeData, useAppStore } from '../store';
import { BotAvatar, Icon, SpinnerDots } from '../ui';
import type { Texts } from '../shared';

export function GroupDialog({
  t,
  value,
  onClose,
  onSaved,
}: {
  t: Texts;
  value?: Group;
  onClose(): void;
  onSaved(): void;
}) {
  const node = useAppStore(selectNodeData);
  const [name, setName] = useState(value?.name ?? '');
  const [botIds, setBotIds] = useState(value?.botIds ?? []);
  const [leadBotId, setLeadBotId] = useState(value?.leadBotId ?? '');
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);
  const reduceMotion = useReducedMotion();

  function toggle(botId: string) {
    const next = botIds.includes(botId) ? botIds.filter((id) => id !== botId) : [...botIds, botId];
    if (next.length > 6) return;
    setBotIds(next);
    if (!next.includes(leadBotId)) setLeadBotId(next[0] ?? '');
  }
  async function submit(event: FormEvent) {
    event.preventDefault();
    setBusy(true);
    setError('');
    try {
      if (value)
        await callNode('groups.update', { groupId: value.groupId, name, botIds, leadBotId });
      else await callNode('groups.create', { name, botIds, leadBotId });
      onSaved();
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : t.saveError);
    } finally {
      setBusy(false);
    }
  }
  async function archive() {
    if (!value) return;
    setBusy(true);
    setError('');
    try {
      await callNode('groups.archive', { groupId: value.groupId });
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
      onMouseDown={(event) => event.target === event.currentTarget && onClose()}
    >
      <motion.form
        className="bot-dialog group-dialog"
        initial={{ opacity: 0, y: reduceMotion ? 0 : 18 }}
        animate={{ opacity: 1, y: 0 }}
        exit={{ opacity: 0, y: reduceMotion ? 0 : 8 }}
        onSubmit={(event) => void submit(event)}
      >
        <header>
          <div>
            <span className="eyebrow">
              <i />
              NEKO DOT
            </span>
            <h2>{value ? t.editGroup : t.newGroup}</h2>
          </div>
          <button type="button" className="icon-button" onClick={onClose} aria-label={t.close}>
            <Icon name="close" />
          </button>
        </header>
        <label>
          {t.groupName}
          <input
            required
            autoFocus
            value={name}
            onChange={(event) => setName(event.target.value)}
          />
        </label>
        <fieldset className="group-member-picker">
          <legend>
            {t.members} <small>{botIds.length}/6</small>
          </legend>
          <p className="muted">{t.groupMemberHint}</p>
          {node.bots
            .filter((bot) => !bot.archived)
            .map((bot) => (
              <label
                className={`member-option${botIds.includes(bot.botId) ? ' selected' : ''}`}
                key={bot.botId}
              >
                <input
                  type="checkbox"
                  checked={botIds.includes(bot.botId)}
                  onChange={() => toggle(bot.botId)}
                />
                <BotAvatar color={bot.avatar.color} size={34} />
                <span>
                  <strong>{bot.displayName}</strong>
                  <small>@{bot.handle}</small>
                </span>
              </label>
            ))}
        </fieldset>
        <label>
          {t.leadBot}
          <select required value={leadBotId} onChange={(event) => setLeadBotId(event.target.value)}>
            <option value="" disabled>
              {t.chooseLead}
            </option>
            {node.bots
              .filter((bot) => botIds.includes(bot.botId))
              .map((bot) => (
                <option key={bot.botId} value={bot.botId}>
                  {bot.displayName} (@{bot.handle})
                </option>
              ))}
          </select>
        </label>
        {value && <small className="muted">{t.groupEditHint}</small>}
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
          <button
            className="primary-button"
            disabled={busy || !node.online || botIds.length < 2 || !leadBotId}
          >
            {busy ? <SpinnerDots /> : value ? t.save : t.createGroup}
            <Icon name="arrow" />
          </button>
        </footer>
      </motion.form>
    </motion.div>
  );
}
