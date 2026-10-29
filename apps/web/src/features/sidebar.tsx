import { useState, type CSSProperties, type ReactNode } from 'react';
import { AnimatePresence, motion, useReducedMotion } from 'motion/react';
import type { Bot, Conversation, Group, Message } from '@nekodot/protocol';
import { selectNodeData, useAppStore, type ActivityState } from '../store';
import {
  BotAvatar,
  GroupDots,
  Icon,
  Kbd,
  Segmented,
  SpinnerDots,
  Wordmark,
  ease,
  type IconName,
} from '../ui';
import { avatarColors, fill, listTime, type Texts } from '../shared';
import { NodePicker } from './node-picker';
import { readableMessageText } from './files';

export type AppView = 'chats' | 'skills' | 'plugins';
export const modKey = /Mac|iPhone|iPad/.test(navigator.userAgent) ? '⌘' : 'Ctrl';

export function TeamSidebar({
  t,
  view,
  activeConversationId,
  onView,
  onOpen,
  onNewBot,
  onNewGroup,
  onPalette,
  onLanguage,
  children,
}: {
  t: Texts;
  view: AppView;
  activeConversationId?: string;
  onView(view: AppView): void;
  onOpen(conversation: Conversation): void;
  onNewBot(): void;
  onNewGroup(): void;
  onPalette(): void;
  onLanguage(): void;
  children?: ReactNode;
}) {
  const me = useAppStore((state) => state.me);
  const node = useAppStore(selectNodeData);
  const socketReady = useAppStore((state) => state.socketReady);
  const setScreen = useAppStore((state) => state.setScreen);
  const [scrolled, setScrolled] = useState(false);
  const activeBots = node.bots.filter((bot) => !bot.archived);
  const canGroup = activeBots.length >= 2 && node.online;
  const views: { value: AppView; label: string; icon: IconName }[] = [
    { value: 'chats', label: t.chatsPage, icon: 'chat' },
    { value: 'skills', label: t.skillsPage, icon: 'spark' },
    { value: 'plugins', label: t.pluginsPage, icon: 'plugin' },
  ];
  const highlight = view === 'chats' ? activeConversationId : undefined;
  const groupBusy = (botId: string) =>
    node.groups.find((group) => {
      const chat = node.conversations.find(
        (entry) => entry.kind === 'group' && entry.groupId === group.groupId,
      );
      const activity = chat && node.activity[chat.conversationId];
      return activity && activity.state !== 'idle' && activity.botId === botId;
    });

  return (
    <aside className="team-sidebar">
      <header className="sidebar-header">
        <Wordmark />
        <h1 className="home-title">{t.team}</h1>
        <div className="sidebar-actions">
          <button className="icon-button compact-only" aria-label={t.search} onClick={onPalette}>
            <Icon name="search" />
          </button>
          <button
            className="icon-button bordered"
            onClick={() => setScreen('settings')}
            aria-label={t.settings}
          >
            <Icon name="settings" />
          </button>
        </div>
      </header>
      <div className={`sidebar-top${scrolled ? ' is-scrolled' : ''}`}>
        <NodePicker t={t} state={!node.online ? 'offline' : socketReady ? 'ok' : 'connecting'} />
        <button className="search-trigger" onClick={onPalette}>
          <Icon name="search" />
          <span>{t.searchJump}</span>
          <Kbd>{modKey} K</Kbd>
        </button>
        <Segmented id="app-view" label="nekodot" value={view} options={views} onChange={onView} />
      </div>
      <div
        className="sidebar-conversations"
        onScroll={(event) => setScrolled(event.currentTarget.scrollTop > 2)}
      >
        <section className="list-section" aria-label={t.botsSection}>
          <div className="bot-list-heading">
            <span>
              {t.botsSection} · {activeBots.length}
            </span>
            <button className="tiny-icon" onClick={onNewBot} aria-label={t.newBot}>
              <Icon name="plus" />
            </button>
          </div>
          <div className="bot-list">
            {activeBots.map((bot, index) => {
              const chat = node.conversations.find(
                (entry) => entry.kind === 'dm' && entry.botId === bot.botId,
              );
              if (!chat) return null;
              return (
                <BotRow
                  key={bot.botId}
                  t={t}
                  bot={bot}
                  index={index}
                  active={chat.conversationId === highlight}
                  messages={node.messages[chat.conversationId] ?? []}
                  activity={node.activity[chat.conversationId]}
                  busyIn={groupBusy(bot.botId)}
                  onClick={() => onOpen(chat)}
                />
              );
            })}
            {!activeBots.length && (
              <div className="empty-bots">
                <BotAvatar color={avatarColors[0]!} size={56} />
                <p>{node.online ? t.noBots : t.offline}</p>
                <button className="primary-button" disabled={!node.online} onClick={onNewBot}>
                  <Icon name="plus" />
                  {t.newBot}
                </button>
              </div>
            )}
          </div>
        </section>
        <section className="list-section" aria-label={t.groups}>
          <div className="bot-list-heading group-list-heading">
            <span>
              {t.groups} · {node.groups.length}
            </span>
            <button
              className="tiny-icon"
              onClick={onNewGroup}
              aria-label={t.newGroup}
              disabled={!canGroup}
            >
              <Icon name="plus" />
            </button>
          </div>
          <div className="bot-list group-list">
            {node.groups.map((group, index) => {
              const chat = node.conversations.find(
                (entry) => entry.kind === 'group' && entry.groupId === group.groupId,
              );
              if (!chat) return null;
              return (
                <GroupRow
                  key={group.groupId}
                  t={t}
                  group={group}
                  bots={node.bots}
                  index={index}
                  active={chat.conversationId === highlight}
                  messages={node.messages[chat.conversationId] ?? []}
                  activity={node.activity[chat.conversationId]}
                  onClick={() => onOpen(chat)}
                />
              );
            })}
            {!node.groups.length && <p className="empty-group-copy">{t.noGroups}</p>}
          </div>
        </section>
      </div>
      <footer className="sidebar-footer">
        <button className="profile-button" onClick={() => setScreen('settings')}>
          <span className="profile-initial">{me?.user.email.slice(0, 1).toUpperCase()}</span>
          <span>
            {me?.user.email}
            <small>{t.settings}</small>
          </span>
        </button>
        <button className="quiet-button language-button" onClick={onLanguage}>
          <Icon name="globe" />
          {t.language}
        </button>
      </footer>
      <NewMenu t={t} canGroup={canGroup} onNewBot={onNewBot} onNewGroup={onNewGroup} />
      {children}
    </aside>
  );
}

/** Newest message worth previewing (bots sometimes finish a turn with no visible text). */
function previewMessage(messages: Message[]) {
  for (let index = messages.length - 1; index >= 0; index--) {
    const message = messages[index]!;
    if (message.kind === 'text' || message.kind === 'commentary' || message.kind === 'system') {
      if (readableMessageText(message.content.text).trim()) return message;
    } else return message;
  }
  return undefined;
}

function previewText(message: Message) {
  if (message.kind === 'text' || message.kind === 'commentary' || message.kind === 'system')
    return readableMessageText(message.content.text).replace(/\s+/g, ' ').slice(0, 80);
  if (message.kind === 'tool') return message.content.tool;
  return message.content.command ?? message.content.prompt;
}

function useRowMotion(index: number) {
  const reduceMotion = useReducedMotion();
  return {
    initial: reduceMotion ? false : { opacity: 0, y: 6 },
    animate: { opacity: 1, y: 0 },
    transition: { duration: 0.26, ease, delay: Math.min(index, 8) * 0.03 },
  } as const;
}

function RowHighlight() {
  const reduceMotion = useReducedMotion();
  return (
    <motion.span
      className="row-highlight"
      layoutId="sidebar-active"
      transition={reduceMotion ? { duration: 0 } : { type: 'spring', stiffness: 520, damping: 42 }}
    />
  );
}

function BotRow({
  t,
  bot,
  index,
  active,
  messages,
  activity,
  busyIn,
  onClick,
}: {
  t: Texts;
  bot: Bot;
  index: number;
  active: boolean;
  messages: Message[];
  activity?: ActivityState;
  busyIn?: Group;
  onClick(): void;
}) {
  const rowMotion = useRowMotion(index);
  const state = activity?.state ?? 'idle';
  const last = previewMessage(messages);
  const working = state === 'thinking' || state === 'tool' || Boolean(busyIn);
  const status =
    busyIn && state === 'idle'
      ? fill(t.replyingInGroup, { name: busyIn.name })
      : last
        ? previewText(last)
        : state === 'thinking'
          ? t.thinking
          : t.lastMessage;
  return (
    <motion.button
      className={`bot-row${active ? ' active' : ''}`}
      aria-current={active ? 'true' : undefined}
      style={{ '--bot': bot.avatar.color } as CSSProperties}
      onClick={onClick}
      {...rowMotion}
    >
      {active && <RowHighlight />}
      <span className="avatar-wrap">
        <BotAvatar color={bot.avatar.color} size={40} working={working} />
      </span>
      <span className="bot-row-info">
        <span className="row-top">
          <strong>{bot.displayName}</strong>
          {last && <time dateTime={last.createdAt}>{listTime(last.createdAt, t)}</time>}
        </span>
        {bot.role && <span className="row-role">{bot.role}</span>}
        <span className="row-status">
          {state === 'waiting_approval' ? (
            <span className="needs-you">{t.needsYou}</span>
          ) : (
            working && <SpinnerDots />
          )}
          <small>{status}</small>
        </span>
      </span>
    </motion.button>
  );
}

function GroupRow({
  t,
  group,
  bots,
  index,
  active,
  messages,
  activity,
  onClick,
}: {
  t: Texts;
  group: Group;
  bots: Bot[];
  index: number;
  active: boolean;
  messages: Message[];
  activity?: ActivityState;
  onClick(): void;
}) {
  const rowMotion = useRowMotion(index + 4);
  const members = group.botIds
    .map((botId) => bots.find((bot) => bot.botId === botId))
    .filter((bot) => bot !== undefined);
  const last = previewMessage(messages);
  const state = activity?.state ?? 'idle';
  const speaker = bots.find((bot) => bot.botId === activity?.botId);
  const author = last?.author.type === 'bot' && bots.find((bot) => bot.botId === last.author.id);
  const status =
    state !== 'idle' && state !== 'waiting_approval' && speaker
      ? fill(t.memberReplying, { name: speaker.displayName }) +
        (activity?.chain ? ` · ${activity.chain.count}/${activity.chain.max}` : '')
      : last
        ? (author ? author.displayName + t.previewSeparator : '') + previewText(last)
        : t.groupChat;
  return (
    <motion.button
      className={`bot-row group-row${active ? ' active' : ''}`}
      aria-current={active ? 'true' : undefined}
      style={speaker ? ({ '--bot': speaker.avatar.color } as CSSProperties) : undefined}
      onClick={onClick}
      {...rowMotion}
    >
      {active && <RowHighlight />}
      <GroupDots colors={members.map((member) => member.avatar.color)} />
      <span className="bot-row-info">
        <span className="row-top">
          <strong>{group.name}</strong>
          {last && <time dateTime={last.createdAt}>{listTime(last.createdAt, t)}</time>}
        </span>
        <span className="row-status">
          {state === 'waiting_approval' ? (
            <span className="needs-you">{t.needsYou}</span>
          ) : (
            state !== 'idle' && <SpinnerDots />
          )}
          <small>{status}</small>
        </span>
      </span>
    </motion.button>
  );
}

/** Phone-only floating “new” button that fans out into bot / group actions. */
function NewMenu({
  t,
  canGroup,
  onNewBot,
  onNewGroup,
}: {
  t: Texts;
  canGroup: boolean;
  onNewBot(): void;
  onNewGroup(): void;
}) {
  const [open, setOpen] = useState(false);
  const reduceMotion = useReducedMotion();
  const items = [
    { label: t.newBot, icon: 'bot' as const, run: onNewBot, disabled: false },
    { label: t.newGroup, icon: 'users' as const, run: onNewGroup, disabled: !canGroup },
  ];
  return (
    <div
      className="fab-layer"
      onKeyDown={(event) => {
        if (event.key === 'Escape') setOpen(false);
      }}
    >
      <AnimatePresence>
        {open && (
          <motion.div
            className="fab-scrim"
            onClick={() => setOpen(false)}
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
            transition={{ duration: 0.18 }}
          />
        )}
      </AnimatePresence>
      <AnimatePresence>
        {open && (
          <motion.div className="fab-menu" role="menu" aria-label={t.newMenu}>
            {items.map((item, index) => (
              <motion.button
                key={item.label}
                role="menuitem"
                disabled={item.disabled}
                onClick={() => {
                  setOpen(false);
                  item.run();
                }}
                initial={reduceMotion ? { opacity: 0 } : { opacity: 0, y: 10, scale: 0.96 }}
                animate={{ opacity: 1, y: 0, scale: 1 }}
                exit={reduceMotion ? { opacity: 0 } : { opacity: 0, y: 6, scale: 0.98 }}
                transition={
                  reduceMotion
                    ? { duration: 0.1 }
                    : {
                        type: 'spring',
                        stiffness: 520,
                        damping: 34,
                        delay: (items.length - 1 - index) * 0.04,
                      }
                }
              >
                <span>{item.label}</span>
                <span className="fab-menu-icon">
                  <Icon name={item.icon} />
                </span>
              </motion.button>
            ))}
          </motion.div>
        )}
      </AnimatePresence>
      <motion.button
        className="fab"
        aria-label={t.newMenu}
        aria-expanded={open}
        aria-haspopup="menu"
        onClick={() => setOpen(!open)}
        animate={{ rotate: open ? 45 : 0 }}
        whileTap={reduceMotion ? undefined : { scale: 0.92 }}
        transition={
          reduceMotion ? { duration: 0 } : { type: 'spring', stiffness: 500, damping: 30 }
        }
      >
        <Icon name="plus" />
      </motion.button>
    </div>
  );
}
