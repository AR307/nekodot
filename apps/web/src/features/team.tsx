import { useState } from 'react';
import { AnimatePresence } from 'motion/react';
import type { Bot, Conversation, Message } from '@nekodot/protocol';
import { loadConversation } from '../relay-connection';
import { selectNodeData, useAppStore } from '../store';
import { BotDialog } from './bots';
import { ChatView } from './chat';
import { BotAvatar, Icon, Wordmark, SpinnerDots } from '../ui';
import { avatarColors, type Texts } from '../shared';

export function TeamPage({ t, nodeName }: { t: Texts; nodeName: string }) {
  const me = useAppStore((state) => state.me);
  const selectedNodeId = useAppStore((state) => state.selectedNodeId);
  const node = useAppStore(selectNodeData);
  const selectedConversationId = useAppStore((state) => state.selectedConversationId);
  const setConversation = useAppStore((state) => state.setSelectedConversation);
  const setScreen = useAppStore((state) => state.setScreen);
  const [botModal, setBotModal] = useState<Bot | 'new' | null>(null);
  const [mobileChat, setMobileChat] = useState(Boolean(selectedConversationId));
  const conversations = node.conversations.filter(
    (item) => item.kind === 'dm' && node.bots.some((bot) => bot.botId === item.botId),
  );
  const conversation =
    conversations.find((item) => item.conversationId === selectedConversationId) ??
    conversations[0];
  const bot =
    conversation?.kind === 'dm'
      ? node.bots.find((item) => item.botId === conversation.botId)
      : undefined;
  const online = node.online;

  function openConversation(item: Conversation) {
    setConversation(item.conversationId);
    setMobileChat(true);
    void loadConversation(item.conversationId);
  }
  function newBot() {
    setBotModal('new');
  }

  return (
    <main className={`team-layout${mobileChat ? ' mobile-chat' : ''}`}>
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
        <div className="team-heading">
          <div>
            <span className="eyebrow">
              <i /> {t.team.toUpperCase()}
            </span>
            <h1>{t.team}</h1>
          </div>
          <div
            className={`node-state ${online ? 'is-online' : 'is-offline'}`}
            title={online ? t.connected : t.offline}
          >
            <i />
            <select
              aria-label={t.chooseNode}
              value={selectedNodeId ?? ''}
              onChange={(event) => useAppStore.getState().setSelectedNode(event.target.value)}
            >
              {me?.nodes.map((item) => (
                <option value={item.nodeId} key={item.nodeId}>
                  {item.name}
                </option>
              ))}
            </select>
          </div>
        </div>
        <div className="bot-list-heading">
          <span>{t.dm}</span>
          <button className="tiny-icon" onClick={newBot} aria-label={t.newBot}>
            <Icon name="plus" />
          </button>
        </div>
        <div className="bot-list">
          {node.bots.map((item) => {
            const chat = node.conversations.find(
              (entry) => entry.kind === 'dm' && entry.botId === item.botId,
            );
            const last = chat ? node.messages[chat.conversationId]?.at(-1) : undefined;
            const state = chat ? node.activity[chat.conversationId] : 'idle';
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
          {!node.bots.length && (
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
        <button className="new-bot-wide" onClick={newBot}>
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
        </footer>
      </aside>
      <section className="conversation-area">
        {conversation && bot ? (
          <ChatView
            key={conversation.conversationId}
            t={t}
            bot={bot}
            conversation={conversation}
            messages={node.messages[conversation.conversationId] ?? []}
            activity={node.activity[conversation.conversationId] ?? 'idle'}
            online={online}
            onBack={() => setMobileChat(false)}
            onEdit={() => setBotModal(bot)}
          />
        ) : (
          <div className="welcome-panel">
            <BotAvatar color={avatarColors[0]!} size={78} />
            <span className="eyebrow">
              <i /> {online ? t.connected.toUpperCase() : t.offline.toUpperCase()}
            </span>
            <h2>{node.bots.length ? t.chooseComputer : t.teamEmpty}</h2>
            <p className="muted">{node.bots.length ? t.lastMessage : t.tagline}</p>
            {!node.bots.length && (
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
                const existing = node.conversations.find(
                  (entry) => entry.kind === 'dm' && entry.botId === item.botId,
                );
                if (existing) openConversation(existing);
              }
            }}
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
