import { useState, type CSSProperties } from 'react';
import { AnimatePresence } from 'motion/react';
import type { Bot, Conversation, Group, Message } from '@nekodot/protocol';
import { loadConversation } from '../relay-connection';
import { selectNodeData, useAppStore } from '../store';
import { BotDialog } from './bots';
import { ChatView } from './chat';
import { BotAvatar, Icon, Wordmark, SpinnerDots } from '../ui';
import { avatarColors, type Texts } from '../shared';
import { GroupDialog } from './groups';
import { GroupChatView } from './group-chat';
import { NodePicker } from './node-picker';

export function TeamPage({
  t,
  nodeName,
  onLanguage,
}: {
  t: Texts;
  nodeName: string;
  onLanguage(): void;
}) {
  const me = useAppStore((state) => state.me);
  const node = useAppStore(selectNodeData);
  const activeBots = node.bots.filter((bot) => !bot.archived);
  const selectedConversationId = useAppStore((state) => state.selectedConversationId);
  const setConversation = useAppStore((state) => state.setSelectedConversation);
  const setScreen = useAppStore((state) => state.setScreen);
  const [botModal, setBotModal] = useState<Bot | 'new' | null>(null);
  const [groupModal, setGroupModal] = useState<Group | 'new' | null>(null);
  const [mobileChat, setMobileChat] = useState(Boolean(selectedConversationId));
  const [sidebarWidth, setSidebarWidth] = useState(
    Number(localStorage.getItem('nekodot-sidebar-width')) || 280,
  );
  function resizeSidebar(width: number) {
    const next = Math.max(260, Math.min(440, window.innerWidth - 480, width));
    setSidebarWidth(next);
    localStorage.setItem('nekodot-sidebar-width', String(next));
  }
  const conversations = node.conversations.filter(
    (item) => item.kind === 'dm' && activeBots.some((bot) => bot.botId === item.botId),
  );
  const groupConversations = node.conversations.filter(
    (item) => item.kind === 'group' && node.groups.some((group) => group.groupId === item.groupId),
  );
  const allConversations = [...conversations, ...groupConversations];
  const conversation =
    allConversations.find((item) => item.conversationId === selectedConversationId) ??
    allConversations[0];
  const bot =
    conversation?.kind === 'dm'
      ? node.bots.find((item) => item.botId === conversation.botId)
      : undefined;
  const group =
    conversation?.kind === 'group'
      ? node.groups.find((item) => item.groupId === conversation.groupId)
      : undefined;
  const online = node.online;

  function openConversation(item: Conversation) {
    setConversation(item.conversationId);
    setMobileChat(true);
    void loadConversation(item.conversationId).catch(() => {
      // RelayConnection reloads the selected conversation after reconnecting.
    });
  }
  function newBot() {
    setBotModal('new');
  }

  return (
    <main
      className={`team-layout${mobileChat ? ' mobile-chat' : ''}`}
      style={{ '--sidebar-width': `${sidebarWidth}px` } as CSSProperties}
    >
      <aside className="team-sidebar">
        <header className="sidebar-header">
          <Wordmark />
          <button
            className="icon-button"
            onClick={() => setScreen('settings')}
            aria-label={t.settings}
          >
            <Icon name="settings" />
          </button>
        </header>
        <NodePicker t={t} />
        <div className="sidebar-conversations">
          <div className="bot-list-heading">
            <span>{t.dm}</span>
            <button className="tiny-icon" onClick={newBot} aria-label={t.newBot}>
              <Icon name="plus" />
            </button>
          </div>
          <div className="bot-list">
            {activeBots.map((item) => {
              const chat = node.conversations.find(
                (entry) => entry.kind === 'dm' && entry.botId === item.botId,
              );
              const last = chat ? node.messages[chat.conversationId]?.at(-1) : undefined;
              const state = chat ? (node.activity[chat.conversationId]?.state ?? 'idle') : 'idle';
              const active = chat?.conversationId === conversation?.conversationId;
              return (
                <button
                  className={`bot-row${active ? ' active' : ''}`}
                  key={item.botId}
                  onClick={() => chat && openConversation(chat)}
                >
                  <span className="avatar-wrap">
                    <BotAvatar color={item.avatar.color} size={42} working={state !== 'idle'} />
                    {state === 'thinking' && (
                      <span className="mini-thinking">
                        <SpinnerDots />
                      </span>
                    )}
                  </span>
                  <span className="bot-row-info">
                    <strong>{item.displayName}</strong>
                    <small>{last ? messagePreview(last, t) : t.lastMessage}</small>
                  </span>
                  {state === 'waiting_approval' && (
                    <span className="needs-you">{t.waitingApproval}</span>
                  )}
                  {state === 'tool' && <span className="work-indicator" />}
                </button>
              );
            })}
            {!activeBots.length && (
              <div className="empty-bots">
                <BotAvatar color={avatarColors[0]!} size={60} />
                <p>{node.online ? t.noBots : t.offline}</p>
                <button className="primary-button" disabled={!node.online} onClick={newBot}>
                  {t.newBot}
                  <Icon name="plus" />
                </button>
              </div>
            )}
          </div>
          <div className="bot-list-heading group-list-heading">
            <span>{t.groups}</span>
            <button
              className="tiny-icon"
              onClick={() => setGroupModal('new')}
              aria-label={t.newGroup}
              disabled={activeBots.length < 2 || !online}
            >
              <Icon name="plus" />
            </button>
          </div>
          <div className="bot-list group-list">
            {node.groups.map((item) => {
              const chat = node.conversations.find(
                (entry) => entry.kind === 'group' && entry.groupId === item.groupId,
              );
              if (!chat) return null;
              const active = chat.conversationId === conversation?.conversationId;
              const state = node.activity[chat.conversationId];
              return (
                <button
                  className={`bot-row group-row${active ? ' active' : ''}`}
                  key={item.groupId}
                  onClick={() => openConversation(chat)}
                >
                  <span className="group-avatar-stack">
                    {item.botIds.slice(0, 3).map((botId) => {
                      const member = node.bots.find((entry) => entry.botId === botId);
                      return member ? (
                        <BotAvatar key={botId} color={member.avatar.color} size={27} />
                      ) : null;
                    })}
                  </span>
                  <span className="bot-row-info">
                    <strong>{item.name}</strong>
                    <small>
                      {state?.chain && state.state !== 'idle'
                        ? `${t.relayProgress} ${state.chain.count}/${state.chain.max}`
                        : t.groupChat}
                    </small>
                  </span>
                  {state?.state === 'waiting_approval' && (
                    <span className="needs-you">{t.waitingApproval}</span>
                  )}
                </button>
              );
            })}
            {!node.groups.length && <p className="empty-group-copy">{t.noGroups}</p>}
          </div>
        </div>
        <button className="new-bot-wide" onClick={newBot} disabled={!online}>
          <Icon name="plus" />
          {t.newBot}
        </button>
        <footer className="sidebar-footer">
          <button className="profile-button" onClick={() => setScreen('settings')}>
            <span className="profile-initial">{me?.user.email.slice(0, 1).toUpperCase()}</span>
            <span>
              {me?.user.email}
              <small>{nodeName}</small>
            </span>
            <Icon name="chevron" />
          </button>
          <button
            className="quiet-button language-button"
            onClick={onLanguage}
            aria-label={t.language}
          >
            {t.language}
          </button>
        </footer>
        <div
          className="sidebar-resizer"
          role="separator"
          aria-label={t.resizeSidebar}
          aria-orientation="vertical"
          aria-valuemin={260}
          aria-valuemax={440}
          aria-valuenow={sidebarWidth}
          tabIndex={0}
          onPointerDown={(event) => event.currentTarget.setPointerCapture(event.pointerId)}
          onPointerMove={(event) => {
            if (event.currentTarget.hasPointerCapture(event.pointerId))
              resizeSidebar(event.clientX);
          }}
          onPointerUp={(event) => event.currentTarget.releasePointerCapture(event.pointerId)}
          onDoubleClick={() => resizeSidebar(280)}
          onKeyDown={(event) => {
            if (event.key === 'ArrowLeft' || event.key === 'ArrowRight') {
              event.preventDefault();
              resizeSidebar(sidebarWidth + (event.key === 'ArrowLeft' ? -20 : 20));
            }
          }}
        />
      </aside>
      <section className="conversation-area">
        {conversation && bot ? (
          <ChatView
            key={conversation.conversationId}
            t={t}
            bot={bot}
            conversation={conversation}
            messages={node.messages[conversation.conversationId] ?? []}
            activity={node.activity[conversation.conversationId]?.state ?? 'idle'}
            online={online}
            onBack={() => setMobileChat(false)}
            onEdit={() => setBotModal(bot)}
          />
        ) : conversation && group ? (
          <GroupChatView
            key={conversation.conversationId}
            t={t}
            group={group}
            conversation={conversation}
            bots={node.bots}
            messages={node.messages[conversation.conversationId] ?? []}
            activity={node.activity[conversation.conversationId] ?? { state: 'idle' }}
            online={online}
            onBack={() => setMobileChat(false)}
            onEdit={() => setGroupModal(group)}
          />
        ) : (
          <div className="welcome-panel">
            <BotAvatar color={avatarColors[0]!} size={78} />
            <span className="eyebrow">
              <i /> {online ? t.connected.toUpperCase() : t.offline.toUpperCase()}
            </span>
            <h2>{activeBots.length ? t.chooseComputer : t.teamEmpty}</h2>
            <p className="muted">{activeBots.length ? t.lastMessage : t.tagline}</p>
            {!activeBots.length && (
              <button className="primary-button" disabled={!online} onClick={newBot}>
                {t.createBot}
                <Icon name="arrow" />
              </button>
            )}
          </div>
        )}
      </section>
      <AnimatePresence>
        {botModal && (
          <BotDialog
            key={botModal === 'new' ? 'new' : botModal.botId}
            t={t}
            value={botModal === 'new' ? undefined : botModal}
            onClose={() => setBotModal(null)}
            onSaved={(item, chat) => {
              setBotModal(null);
              if (chat) openConversation(chat);
              else if (item) {
                const existing = selectNodeData(useAppStore.getState()).conversations.find(
                  (entry) => entry.kind === 'dm' && entry.botId === item.botId,
                );
                if (existing) openConversation(existing);
              }
            }}
          />
        )}
        {groupModal && (
          <GroupDialog
            key={groupModal === 'new' ? 'new-group' : groupModal.groupId}
            t={t}
            value={groupModal === 'new' ? undefined : groupModal}
            onClose={() => setGroupModal(null)}
            onSaved={() => setGroupModal(null)}
          />
        )}
      </AnimatePresence>
    </main>
  );
}

function messagePreview(message: Message, t: Texts) {
  if (message.kind === 'text' || message.kind === 'commentary' || message.kind === 'system')
    return message.content.text.slice(0, 52);
  if (message.kind === 'tool') return message.content.tool;
  return t.approvalTitle;
}
