import { useState, type FormEvent } from 'react';
import { AnimatePresence, motion, useReducedMotion } from 'motion/react';
import type { Group } from '@nekodot/protocol';
import { callNode } from '../relay-connection';
import { selectNodeData, useAppStore } from '../store';
import { BotAvatar, SpinnerDots } from '../ui';
import type { Texts } from '../shared';
import { Sheet } from './sheet';

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
  const candidates = node.bots.filter((bot) => !bot.archived);
  const chosen = botIds
    .map((botId) => node.bots.find((bot) => bot.botId === botId))
    .filter((bot) => bot !== undefined);

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

  const disabled = busy || !node.online || botIds.length < 2 || !leadBotId;
  return (
    <Sheet
      className="bot-dialog group-dialog"
      title={value ? t.editGroup : t.newGroup}
      titleId="group-dialog-title"
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
            {t.createGroup}
          </button>
        )
      }
    >
      <div className="group-stage" aria-hidden="true">
        <span className="group-stage-dots">
          <AnimatePresence initial={false} mode="popLayout">
            {chosen.length ? (
              chosen.map((bot) => (
                <motion.i
                  key={bot.botId}
                  layout
                  style={{ background: bot.avatar.color }}
                  initial={reduceMotion ? { opacity: 0 } : { opacity: 0, scale: 0.4 }}
                  animate={{ opacity: 1, scale: 1 }}
                  exit={reduceMotion ? { opacity: 0 } : { opacity: 0, scale: 0.4 }}
                  transition={
                    reduceMotion
                      ? { duration: 0.1 }
                      : { type: 'spring', stiffness: 480, damping: 24 }
                  }
                />
              ))
            ) : (
              <motion.i key="empty" className="is-empty" layout />
            )}
          </AnimatePresence>
        </span>
        <strong>{name.trim() || t.unnamedGroup}</strong>
      </div>
      <label className="field">
        {t.groupName}
        <input required autoFocus value={name} onChange={(event) => setName(event.target.value)} />
      </label>
      <fieldset className="field group-member-picker">
        <legend>
          {t.members} <small>{botIds.length}/6</small>
        </legend>
        <p className="field-hint">{t.groupMemberHint}</p>
        <div className="member-grid">
          {candidates.map((bot) => {
            const selected = botIds.includes(bot.botId);
            return (
              <label className={`member-option${selected ? ' selected' : ''}`} key={bot.botId}>
                <BotAvatar color={bot.avatar.color} size={32} />
                <span>
                  <strong>
                    {bot.displayName}
                    {bot.botId === leadBotId && <em className="lead-chip">{t.leadChip}</em>}
                  </strong>
                  <small>
                    @{bot.handle}
                    {bot.role ? ' · ' + bot.role : ''}
                  </small>
                </span>
                <input type="checkbox" checked={selected} onChange={() => toggle(bot.botId)} />
              </label>
            );
          })}
        </div>
      </fieldset>
      <label className="field">
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
        <small>{value ? t.groupEditHint : t.leadHint}</small>
      </label>
      {error && (
        <p className="form-error" role="alert">
          {error}
        </p>
      )}
    </Sheet>
  );
}
