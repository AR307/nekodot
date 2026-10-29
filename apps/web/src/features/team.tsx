import { useEffect, useRef, useState, type CSSProperties } from 'react';
import { AnimatePresence, motion, useReducedMotion } from 'motion/react';
import type { Bot, Conversation, Group } from '@nekodot/protocol';
import { callNode, loadConversation } from '../relay-connection';
import { selectNodeData, useAppStore } from '../store';
import { BotDialog } from './bots';
import { ChatView } from './chat';
import { BotAvatar, GroupDots, Icon, Kbd, ease } from '../ui';
import { avatarColors, fill, type Texts } from '../shared';
import { GroupDialog } from './groups';
import { GroupChatView } from './group-chat';
import { BotDetails } from './bot-details';
import { ExtensionsPage } from './extensions';
import { TeamSidebar, modKey, type AppView } from './sidebar';
import { CommandPalette, type PaletteItem } from './command-palette';
import { ScreenPanel } from './screen';

export function TeamPage({ t, onLanguage }: { t: Texts; onLanguage(): void }) {
  const node = useAppStore(selectNodeData);
  const activeBots = node.bots.filter((bot) => !bot.archived);
  const selectedConversationId = useAppStore((state) => state.selectedConversationId);
  const setConversation = useAppStore((state) => state.setSelectedConversation);
  const setScreen = useAppStore((state) => state.setScreen);
  const [botModal, setBotModal] = useState<Bot | 'new' | null>(null);
  const [groupModal, setGroupModal] = useState<Group | 'new' | null>(null);
  const [detailBotId, setDetailBotId] = useState<string | null>(null);
  const [screenBotId, setScreenBotId] = useState<string | null>(null);
  const [screenMembers, setScreenMembers] = useState<string[]>([]);
  const selectedNodeId = useAppStore((state) => state.selectedNodeId);
  const [view, setView] = useState<AppView>('chats');
  const [mobileChat, setMobileChat] = useState(Boolean(selectedConversationId));
  const [paletteOpen, setPaletteOpen] = useState(false);
  const reduceMotion = useReducedMotion();
  const layoutRef = useRef<HTMLElement>(null);
  const navigated = useRef(false);
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
  const canGroup = activeBots.length >= 2 && online;
  const screenBot = node.bots.find((item) => item.botId === screenBotId);
  function openScreen(botId: string, memberIds = [botId]) {
    setScreenMembers(memberIds);
    setScreenBotId(botId);
    setDetailBotId(null);
  }
  function openGroupScreen() {
    if (!group || !conversation) return;
    const activity = node.activity[conversation.conversationId];
    const recentBot = [...(node.messages[conversation.conversationId] ?? [])]
      .reverse()
      .find(
        (message) =>
          message.author.type === 'bot' &&
          message.author.id &&
          group.botIds.includes(message.author.id),
      );
    const botId =
      activity?.state !== 'idle' && activity?.botId && group.botIds.includes(activity.botId)
        ? activity.botId
        : (recentBot?.author.id ?? group.leadBotId);
    openScreen(botId, group.botIds);
  }

  useEffect(() => {
    const onKey = (event: KeyboardEvent) => {
      if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === 'k') {
        event.preventDefault();
        setPaletteOpen((open) => !open);
      }
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, []);

  // Phone navigation: chats push in from the right, home slides back from the left.
  // Driven by navigation only, so resizing the window never replays it.
  useEffect(() => {
    if (!navigated.current) {
      navigated.current = true;
      return;
    }
    if (!window.matchMedia('(max-width: 1023px)').matches) return;
    const target = layoutRef.current?.querySelector(
      mobileChat ? '.conversation-area' : '.team-sidebar',
    );
    target?.animate(
      reduceMotion
        ? [{ opacity: 0 }, { opacity: 1 }]
        : [
            { opacity: 0, transform: `translateX(${mobileChat ? 28 : -12}px)` },
            { opacity: 1, transform: 'none' },
          ],
      { duration: reduceMotion ? 100 : 280, easing: 'cubic-bezier(0.2, 0.8, 0.2, 1)' },
    );
  }, [mobileChat, reduceMotion]);

  function openConversation(item: Conversation) {
    setView('chats');
    setConversation(item.conversationId);
    setMobileChat(true);
    void loadConversation(item.conversationId).catch(() => {
      // RelayConnection reloads the selected conversation after reconnecting.
    });
  }
  function openView(next: AppView) {
    setView(next);
    if (next !== 'chats') setMobileChat(true);
  }
  function newBot() {
    setBotModal('new');
  }
  function newGroup() {
    if (canGroup) setGroupModal('new');
  }

  const paletteItems: PaletteItem[] = [
    ...activeBots.flatMap((item) => {
      const chat = node.conversations.find(
        (entry) => entry.kind === 'dm' && entry.botId === item.botId,
      );
      return chat
        ? [
            {
              id: 'bot-' + item.botId,
              section: t.botsSection,
              label: item.displayName,
              hint: '@' + item.handle + (item.role ? ' · ' + item.role : ''),
              icon: <BotAvatar color={item.avatar.color} size={22} />,
              run: () => openConversation(chat),
            },
          ]
        : [];
    }),
    ...node.groups.flatMap((item) => {
      const chat = node.conversations.find(
        (entry) => entry.kind === 'group' && entry.groupId === item.groupId,
      );
      const colors = item.botIds.map(
        (botId) => node.bots.find((entry) => entry.botId === botId)?.avatar.color ?? '',
      );
      return chat
        ? [
            {
              id: 'group-' + item.groupId,
              section: t.groups,
              label: item.name,
              hint: fill(t.memberCount, { count: item.botIds.length }),
              icon: <GroupDots colors={colors} size={14} />,
              run: () => openConversation(chat),
            },
          ]
        : [];
    }),
    ...[
      { id: 'new-bot', label: t.newBot, icon: 'bot' as const, run: newBot, show: true },
      { id: 'new-group', label: t.newGroup, icon: 'users' as const, run: newGroup, show: canGroup },
      {
        id: 'skills',
        label: t.skillsPage,
        icon: 'spark' as const,
        run: () => openView('skills'),
        show: true,
      },
      {
        id: 'plugins',
        label: t.pluginsPage,
        icon: 'plugin' as const,
        run: () => openView('plugins'),
        show: true,
      },
      {
        id: 'settings',
        label: t.settings,
        icon: 'settings' as const,
        run: () => setScreen('settings'),
        show: true,
      },
      {
        id: 'add-computer',
        label: t.addComputer,
        icon: 'laptop' as const,
        run: () => setScreen('pair'),
        show: true,
      },
      {
        id: 'language',
        label: t.switchLanguage,
        icon: 'globe' as const,
        run: onLanguage,
        show: true,
      },
    ]
      .filter((item) => item.show)
      .map((item) => ({
        id: item.id,
        section: t.actionsSection,
        label: item.label,
        icon: <Icon name={item.icon} />,
        run: item.run,
      })),
  ];

  const paneKey = view !== 'chats' ? view : (conversation?.conversationId ?? 'welcome');
  return (
    <main
      ref={layoutRef}
      className={`team-layout${mobileChat ? ' mobile-chat' : ''}${screenBot ? ' has-screen' : ''}`}
      style={{ '--sidebar-width': `${sidebarWidth}px` } as CSSProperties}
    >
      <TeamSidebar
        t={t}
        view={view}
        activeConversationId={conversation?.conversationId}
        onView={openView}
        onOpen={openConversation}
        onNewBot={newBot}
        onNewGroup={newGroup}
        onPalette={() => setPaletteOpen(true)}
        onLanguage={onLanguage}
      >
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
      </TeamSidebar>
      <section className="conversation-area">
        <motion.div
          key={paneKey}
          className="conversation-pane"
          initial={reduceMotion ? { opacity: 0 } : { opacity: 0, y: 6 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: reduceMotion ? 0.1 : 0.24, ease }}
        >
          {view !== 'chats' ? (
            <>
              <button
                className="icon-button back-button extension-back"
                aria-label={t.home}
                onClick={() => {
                  setView('chats');
                  setMobileChat(false);
                }}
              >
                <Icon name="back" />
              </button>
              <ExtensionsPage key={view} kind={view} t={t} />
            </>
          ) : conversation && bot ? (
            <ChatView
              key={conversation.conversationId}
              t={t}
              bot={bot}
              conversation={conversation}
              messages={node.messages[conversation.conversationId] ?? []}
              activity={node.activity[conversation.conversationId]?.state ?? 'idle'}
              online={online}
              onBack={() => setMobileChat(false)}
              onEdit={() => setDetailBotId(bot.botId)}
              onScreen={() => openScreen(bot.botId)}
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
              onScreen={openGroupScreen}
            />
          ) : (
            <div className="welcome-panel">
              <BotAvatar color={avatarColors[0]!} size={72} />
              <h2>{activeBots.length ? t.welcomeTitle : t.teamEmpty}</h2>
              <p className="muted">
                {activeBots.length
                  ? fill(t.welcomeBody, { shortcut: modKey + ' K' })
                  : online
                    ? t.tagline
                    : t.offlineCreateHint}
              </p>
              {activeBots.length ? (
                <button className="secondary-button" onClick={() => setPaletteOpen(true)}>
                  <Icon name="search" />
                  {t.searchJump}
                  <Kbd>{modKey} K</Kbd>
                </button>
              ) : (
                <button className="primary-button" disabled={!online} onClick={newBot}>
                  {t.createBot}
                  <Icon name="arrow" />
                </button>
              )}
            </div>
          )}
        </motion.div>
      </section>
      {screenBot && (
        <ScreenPanel
          key={`${selectedNodeId}:${screenBot.botId}`}
          bot={screenBot}
          members={node.bots.filter((item) => screenMembers.includes(item.botId))}
          t={t}
          onSelect={setScreenBotId}
          onClose={() => setScreenBotId(null)}
        />
      )}
      <AnimatePresence>
        {paletteOpen && (
          <CommandPalette t={t} items={paletteItems} onClose={() => setPaletteOpen(false)} />
        )}
      </AnimatePresence>
      <AnimatePresence>
        {detailBotId && node.bots.find((item) => item.botId === detailBotId) && (
          <BotDetails
            bot={node.bots.find((item) => item.botId === detailBotId)!}
            t={t}
            onClose={() => setDetailBotId(null)}
            onScreen={() => openScreen(detailBotId)}
            onEdit={() => {
              setBotModal(node.bots.find((item) => item.botId === detailBotId)!);
              setDetailBotId(null);
            }}
            onSource={(file) => {
              setDetailBotId(null);
              setView('chats');
              setConversation(file.conversationId);
              setMobileChat(true);
              const nodeId = useAppStore.getState().selectedNodeId!;
              void callNode('messages.list', {
                conversationId: file.conversationId,
                aroundMessageId: file.messageId,
                limit: 50,
              }).then((value) => {
                useAppStore.getState().setMessages(nodeId, file.conversationId, value.messages);
                window.setTimeout(
                  () =>
                    document
                      .getElementById('message-' + file.messageId)
                      ?.scrollIntoView({ block: 'center' }),
                  100,
                );
              });
            }}
          />
        )}
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
