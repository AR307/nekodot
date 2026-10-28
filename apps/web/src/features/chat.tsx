import { useEffect, useRef, useState, type FormEvent } from 'react';
import { AnimatePresence, motion, useReducedMotion } from 'motion/react';
import type { Bot, Conversation, Group, Message } from '@nekodot/protocol';
import { callNode, loadConversation } from '../relay-connection';
import { useAppStore } from '../store';
import { BotAvatar, Icon, SpinnerDots } from '../ui';
import type { Texts } from '../shared';

export function ChatView({
  t,
  bot,
  bots = [bot],
  group,
  chain,
  conversation,
  messages,
  activity,
  online,
  onBack,
  onEdit,
}: {
  t: Texts;
  bot: Bot;
  bots?: Bot[];
  group?: Group;
  chain?: { count: number; max: number };
  conversation: Conversation;
  messages: Message[];
  activity: 'thinking' | 'tool' | 'waiting_approval' | 'idle';
  online: boolean;
  onBack(): void;
  onEdit(): void;
}) {
  const [draft, setDraft] = useState('');
  const [caret, setCaret] = useState(0);
  const composerRef = useRef<HTMLTextAreaElement>(null);
  const [error, setError] = useState('');
  const [sending, setSending] = useState(false);
  const [instructionAdded, setInstructionAdded] = useState(false);
  const pendingDraft = useRef<{ text: string; clientMsgId: string } | null>(null);
  const [loadingEarlier, setLoadingEarlier] = useState(false);
  const [historyComplete, setHistoryComplete] = useState(false);
  const loadingEarlierRef = useRef(false);
  const tailRef = useRef<HTMLDivElement>(null);
  const lastMessage = messages.at(-1);
  const lastText = lastMessage?.kind === 'text' ? lastMessage.content.text : '';
  const reduceMotion = useReducedMotion();
  const running = activity !== 'idle';
  const members = group ? bots.filter((member) => group.botIds.includes(member.botId)) : [];
  const mentionMatch = group ? /(?:^|\s)@([a-z0-9-]*)$/.exec(draft.slice(0, caret)) : null;
  const mentionOptions = mentionMatch
    ? members.filter((member) => member.handle.startsWith(mentionMatch[1]!))
    : [];

  function insertMention(member: Bot) {
    const start = draft.lastIndexOf('@', caret - 1);
    const text = draft.slice(0, start) + '@' + member.handle + ' ' + draft.slice(caret);
    const nextCaret = start + member.handle.length + 2;
    setDraft(text);
    setCaret(nextCaret);
    requestAnimationFrame(() => {
      composerRef.current?.focus();
      composerRef.current?.setSelectionRange(nextCaret, nextCaret);
    });
  }

  useEffect(() => {
    if (loadingEarlierRef.current) return;
    tailRef.current?.scrollIntoView({ behavior: reduceMotion ? 'auto' : 'smooth', block: 'end' });
  }, [messages.length, lastText, activity, reduceMotion]);

  async function loadEarlier() {
    const first = messages[0];
    const nodeId = useAppStore.getState().selectedNodeId;
    if (!first || !nodeId || loadingEarlier) return;
    setLoadingEarlier(true);
    loadingEarlierRef.current = true;
    try {
      const result = await callNode('messages.list', {
        conversationId: conversation.conversationId,
        beforeSeq: first.seq,
        limit: 50,
      });
      useAppStore.getState().setMessages(nodeId, conversation.conversationId, result.messages);
      setHistoryComplete(result.messages.length < 50);
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : t.sendError);
    } finally {
      setLoadingEarlier(false);
      window.requestAnimationFrame(() => {
        loadingEarlierRef.current = false;
      });
    }
  }

  async function send(event: FormEvent) {
    event.preventDefault();
    const text = draft.trim();
    if (!text || sending || !online || activity === 'waiting_approval') return;
    setSending(true);
    setError('');
    setInstructionAdded(false);
    const addingToCurrentRun = running;
    if (pendingDraft.current?.text !== text)
      pendingDraft.current = { text, clientMsgId: crypto.randomUUID() };
    try {
      await callNode('messages.send', {
        conversationId: conversation.conversationId,
        text,
        clientMsgId: pendingDraft.current.clientMsgId,
      });
      setDraft('');
      pendingDraft.current = null;
      setInstructionAdded(addingToCurrentRun);
      await loadConversation(conversation.conversationId);
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : t.sendError);
    } finally {
      setSending(false);
    }
  }

  async function stop() {
    try {
      await callNode('runs.stop', { conversationId: conversation.conversationId });
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : t.sendError);
    }
  }

  return (
    <div className="chat-column">
      <header className="chat-header">
        <button className="icon-button back-button" onClick={onBack} aria-label={t.home}>
          <Icon name="chevron" />
        </button>
        <BotAvatar color={bot.avatar.color} size={42} working={running} />
        <button className="chat-title" onClick={onEdit}>
          <strong>{group?.name ?? bot.displayName}</strong>
          <small>
            {group
              ? `${t.leadBot}: ${bots.find((member) => member.botId === group.leadBotId)?.displayName}`
              : '@' + bot.handle}
          </small>
        </button>
        <div className={`chat-status ${online ? 'online' : 'offline'}`}>
          <i />
          {!online
            ? t.offline
            : activity === 'thinking'
              ? t.thinking
              : activity === 'tool'
                ? t.usingTool
                : activity === 'waiting_approval'
                  ? t.waitingApproval
                  : online
                    ? t.connected
                    : t.offline}
        </div>
      </header>
      <div className="message-scroll">
        <div className="messages-inner">
          {messages.length >= 50 && !historyComplete && (
            <button
              className="text-button load-earlier"
              disabled={loadingEarlier}
              onClick={() => void loadEarlier()}
            >
              {t.loadEarlier}
            </button>
          )}
          <div className="chat-date">
            <span>
              {group ? `${t.groupChat} · ${members.length} ${t.members}` : `${t.dm} · ${bot.model}`}
            </span>
          </div>
          <AnimatePresence initial={false}>
            {messages.map((message) => (
              <MessageView
                key={message.messageId}
                t={t}
                bot={bots.find((member) => member.botId === message.author.id) ?? bot}
                members={group ? members : undefined}
                message={message}
                onRetry={setDraft}
              />
            ))}
          </AnimatePresence>
          {activity === 'thinking' && (
            <div className="bot-thinking">
              <BotAvatar color={bot.avatar.color} size={36} working />
              <div>
                <small>
                  {bot.displayName} · {t.thinking}
                </small>
                <SpinnerDots />
              </div>
            </div>
          )}
          {group && running && chain && (
            <div className="chain-progress" role="status">
              {t.relayProgress} {chain.count} / {chain.max}
            </div>
          )}
          <div ref={tailRef} />
        </div>
      </div>
      <div className="composer-wrap">
        {running && (
          <div
            className={`run-banner ${activity === 'waiting_approval' ? 'approval-waiting' : ''}`}
          >
            <span>
              {activity === 'waiting_approval'
                ? t.waitingApproval
                : activity === 'tool'
                  ? t.usingTool
                  : t.inputHint}
            </span>
            <button className="stop-button" onClick={() => void stop()}>
              <Icon name="stop" />
              {group ? t.stopAll : t.stop}
            </button>
          </div>
        )}
        {instructionAdded && (
          <p className="inline-success" role="status">
            {t.currentInstruction}
          </p>
        )}
        {error && (
          <div className="inline-error" role="alert">
            {error}
            <button onClick={() => setError('')}>{t.close}</button>
          </div>
        )}
        <form className="composer" onSubmit={(event) => void send(event)}>
          {mentionOptions.length > 0 && (
            <div className="mention-menu" role="listbox" aria-label={t.mentionMember}>
              {mentionOptions.map((member) => (
                <button
                  key={member.botId}
                  type="button"
                  role="option"
                  aria-selected={false}
                  onMouseDown={(event) => event.preventDefault()}
                  onClick={() => insertMention(member)}
                >
                  <BotAvatar color={member.avatar.color} size={28} />
                  <span>
                    {member.displayName}
                    <small>@{member.handle}</small>
                  </span>
                </button>
              ))}
            </div>
          )}
          <textarea
            ref={composerRef}
            aria-label={running ? t.supplement : t.typeMessage}
            placeholder={running ? t.supplement : t.typeMessage}
            rows={1}
            value={draft}
            onChange={(event) => {
              setDraft(event.target.value);
              setCaret(event.target.selectionStart);
            }}
            onSelect={(event) => setCaret(event.currentTarget.selectionStart)}
            onKeyDown={(event) => {
              if (event.key === 'Enter' && !event.shiftKey) {
                event.preventDefault();
                if (mentionOptions[0]) {
                  insertMention(mentionOptions[0]);
                  return;
                }
                event.currentTarget.form?.requestSubmit();
              }
            }}
          />
          <button
            className="send-button"
            disabled={!draft.trim() || sending || !online || activity === 'waiting_approval'}
            aria-label={t.send}
          >
            <Icon name="send" />
          </button>
        </form>
        <div className="composer-hint">
          {activity === 'waiting_approval' ? t.approvalDraftHint : t.inputHint}
        </div>
      </div>
    </div>
  );
}

function MessageView({
  t,
  bot,
  message,
  members,
  onRetry,
}: {
  t: Texts;
  bot: Bot;
  message: Message;
  members?: Bot[];
  onRetry(text: string): void;
}) {
  const reduceMotion = useReducedMotion();
  const [expanded, setExpanded] = useState(false);
  const handoffs =
    members && message.kind === 'text' && message.status === 'done' && message.author.type === 'bot'
      ? members.filter(
          (member) =>
            member.botId !== message.author.id &&
            new RegExp(`(?:^|[^\\w@-])@${member.handle}(?![a-z0-9-])`).test(message.content.text),
        )
      : [];
  if (
    (message.kind === 'text' || message.kind === 'commentary') &&
    message.author.type === 'bot' &&
    message.status === 'done' &&
    !message.content.text.trim()
  )
    return null;
  return (
    <motion.article
      className={`message message-${message.kind}${message.author.type === 'user' ? ' from-user' : ''}`}
      initial={{ opacity: 0, y: reduceMotion ? 0 : 8 }}
      animate={{ opacity: 1, y: 0 }}
      exit={{ opacity: 0, y: 0 }}
      transition={{ duration: reduceMotion ? 0.1 : 0.22, ease: [0.2, 0.8, 0.2, 1] }}
    >
      {message.author.type === 'user' ? (
        <div className="user-bubble">{message.kind === 'text' && message.content.text}</div>
      ) : message.author.type === 'system' ? (
        <p className="system-message">
          {message.kind === 'system' &&
            (message.content.retryText ? (
              <>
                {t.unconsumedInstruction}{' '}
                <button className="text-button" onClick={() => onRetry(message.content.retryText!)}>
                  {t.prepareResend}
                </button>
              </>
            ) : message.content.text ===
              'Relay paused after 6 turns. Mention a group member to continue.' ? (
              t.relayPaused
            ) : (
              message.content.text
            ))}
        </p>
      ) : (
        <>
          {(message.kind === 'text' || message.kind === 'commentary') && (
            <>
              <BotAvatar
                color={bot.avatar.color}
                size={32}
                working={message.status === 'streaming'}
              />
              <div className="bot-message-body">
                <span className="message-author">
                  {bot.displayName}
                  {members ? ` @${bot.handle}` : ''}
                </span>
                <div className={message.kind === 'commentary' ? 'commentary-copy' : 'bot-copy'}>
                  {message.content.text}
                  {message.status === 'streaming' && <span className="stream-cursor">▍</span>}
                  {message.status === 'failed' && (
                    <small className="message-state failed-state"> · {t.failed}</small>
                  )}
                  {message.status === 'cancelled' && (
                    <small className="message-state"> · {t.stopped}</small>
                  )}
                </div>
                {handoffs?.map((member) => (
                  <motion.span
                    className="handoff-tag"
                    key={member.botId}
                    initial={{ opacity: 0, x: reduceMotion ? 0 : -12 }}
                    animate={{ opacity: 1, x: 0 }}
                    transition={{ duration: reduceMotion ? 0.1 : 0.2 }}
                  >
                    <motion.span
                      animate={{ y: reduceMotion ? 0 : [0, -4, 0] }}
                      transition={{ duration: reduceMotion ? 0.1 : 0.3 }}
                    >
                      <BotAvatar color={member.avatar.color} size={18} />
                    </motion.span>
                    → {t.handoffTo} @{member.handle}
                  </motion.span>
                ))}
              </div>
            </>
          )}
          {message.kind === 'tool' && (
            <div className={`tool-card${message.content.error ? ' tool-error' : ''}`}>
              {members && (
                <small className="card-author">
                  {bot.displayName} @{bot.handle}
                </small>
              )}
              <button className="tool-summary" onClick={() => setExpanded(!expanded)}>
                <span className={`tool-check ${message.status === 'streaming' ? 'spinning' : ''}`}>
                  {message.status === 'streaming'
                    ? '◌'
                    : message.content.error || message.status === 'failed'
                      ? '!'
                      : message.status === 'cancelled'
                        ? '×'
                        : '✓'}
                </span>
                <span className="tool-title">
                  <strong>{message.content.tool}</strong>
                  <small>{message.content.preview}</small>
                </span>
                <span className="tool-status">
                  {message.status === 'streaming' ? (
                    <SpinnerDots />
                  ) : message.status === 'cancelled' ? (
                    t.stopped
                  ) : message.status === 'failed' || message.content.error ? (
                    t.failed
                  ) : (
                    t.completed
                  )}
                  <Icon name="chevron" />
                </span>
              </button>
              <AnimatePresence>
                {expanded && (
                  <motion.div
                    className="tool-result"
                    initial={{ height: 0, opacity: 0 }}
                    animate={{ height: 'auto', opacity: 1 }}
                    exit={{ height: 0, opacity: 0 }}
                    transition={
                      reduceMotion
                        ? { duration: 0.1 }
                        : { type: 'spring', stiffness: 400, damping: 32 }
                    }
                  >
                    <span>
                      {t.toolDetails}
                      {message.content.durationMs
                        ? ` · ${(message.content.durationMs / 1000).toFixed(1)}s`
                        : ''}
                    </span>
                    <pre>{message.content.resultPreview || message.content.preview}</pre>
                  </motion.div>
                )}
              </AnimatePresence>
            </div>
          )}
          {message.kind === 'approval' && (
            <ApprovalCard
              t={t}
              message={message}
              author={members ? `${bot.displayName} @${bot.handle}` : undefined}
            />
          )}
        </>
      )}
    </motion.article>
  );
}

function ApprovalCard({
  t,
  message,
  author,
}: {
  t: Texts;
  message: Extract<Message, { kind: 'approval' }>;
  author?: string;
}) {
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  async function respond(choice: 'once' | 'deny') {
    setBusy(true);
    setError('');
    try {
      await callNode('approvals.respond', { messageId: message.messageId, choice });
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : t.saveError);
    } finally {
      setBusy(false);
    }
  }
  const status =
    message.content.choice === 'once'
      ? t.approved
      : message.content.choice === 'deny'
        ? t.denied
        : message.status === 'cancelled'
          ? t.stopped
          : message.status === 'failed'
            ? t.failed
            : '';
  return (
    <div className="approval-card">
      {author && <small className="card-author">{author}</small>}
      <div className="approval-title">
        <span className="approval-mark">!</span>
        <strong>{status || t.approvalTitle}</strong>
      </div>
      <p>{message.content.prompt}</p>
      {message.content.command && <pre className="approval-command">{message.content.command}</pre>}
      {!status && message.status === 'streaming' && (
        <div className="approval-actions">
          <button className="allow-button" disabled={busy} onClick={() => void respond('once')}>
            {t.allowOnce}
          </button>
          <button className="deny-button" disabled={busy} onClick={() => void respond('deny')}>
            {t.deny}
          </button>
        </div>
      )}
      {status && <span className="approval-result">{status}</span>}
      {error && <small className="form-error">{error}</small>}
    </div>
  );
}
