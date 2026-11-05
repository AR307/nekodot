import { AnimatedList } from '../components/ui/animated-list';
import {
  useEffect,
  useLayoutEffect,
  useRef,
  useState,
  type CSSProperties,
  type FormEvent,
  type ReactNode,
} from 'react';
import { AnimatePresence, motion, useReducedMotion } from 'motion/react';
import type { ApprovalChoice, Bot, Conversation, Group, Message } from '@nekodot/protocol';
import { callNode, loadConversation } from '../relay-connection';
import { useAppStore } from '../store';
import { BotAvatar, GroupDots, Icon, LoadingText, type IconName } from '../ui';
import { fill, type Texts } from '../shared';
import { DraftAttachment, MessageFiles, readableMessageText, uploadChatFile } from './files';
import { Markdown, MentionText } from './markdown';
import { useDrafts } from '../drafts';
import { writeClipboard } from '../native';
import AIApproval from '../components/ui/ai-approval';
import { PromptInput } from '../components/ui/ai-chat-input';
import { useModelOptions } from './models';
import { VoiceInput } from './voice-input';
import { durations, shift, springy, tween } from '../motion';

type Activity = 'thinking' | 'tool' | 'waiting_approval' | 'waiting_question' | 'unknown' | 'idle';

export function ChatView({
  t,
  bot,
  bots = [bot],
  group,
  chain,
  conversation,
  messages,
  activity,
  connection,
  online,
  onBack,
  onEdit,
  onScreen,
}: {
  t: Texts;
  bot: Bot;
  bots?: Bot[];
  group?: Group;
  chain?: { count: number; max: number };
  conversation: Conversation;
  messages: Message[];
  activity: Activity;
  connection?: 'connected' | 'reconnecting';
  online: boolean;
  onBack(): void;
  onEdit(): void;
  onScreen(): void;
}) {
  const nodeId = useAppStore((state) => state.selectedNodeId);
  const draftKey = `${nodeId}:${conversation.conversationId}`;
  const draft = useDrafts((state) => state.values[draftKey] ?? '');
  const files = useDrafts((state) => state.attachments[draftKey]);
  const setDraft = (text: string) => useDrafts.getState().set(draftKey, text);
  const [caret, setCaret] = useState(0);
  const [mentionIndex, setMentionIndex] = useState(0);
  const composerRef = useRef<HTMLTextAreaElement>(null);
  const fileRef = useRef<HTMLInputElement>(null);
  const [uploading, setUploading] = useState(false);
  const [voiceBusy, setVoiceBusy] = useState(false);
  const [modelMenu, setModelMenu] = useState(false);
  const [savingModel, setSavingModel] = useState(false);
  const catalog = useModelOptions(online && modelMenu, bot.sourceId ?? '');
  const zh = useAppStore((state) => state.language === 'zh');
  const [error, setError] = useState('');
  const [sending, setSending] = useState(false);
  const [instructionAdded, setInstructionAdded] = useState(false);
  const pendingDraft = useRef<{ text: string; clientMsgId: string } | null>(null);
  const [loadingEarlier, setLoadingEarlier] = useState(false);
  const [historyComplete, setHistoryComplete] = useState(false);
  const reduceMotion = useReducedMotion();
  const running = activity !== 'idle';
  const waiting =
    activity === 'waiting_approval' || activity === 'waiting_question' || activity === 'unknown';
  const members = group ? bots.filter((member) => group.botIds.includes(member.botId)) : [];
  const handles = group ? ['everyone', ...members.map((member) => member.handle)] : undefined;
  const lead = group ? bots.find((member) => member.botId === group.leadBotId) : undefined;
  const mentionMatch = group ? /(?:^|\s)@([a-z0-9-]*)$/.exec(draft.slice(0, caret)) : null;
  const mentionOptions = mentionMatch
    ? [
        {
          botId: 'everyone',
          handle: 'everyone',
          displayName: t.everyone,
          role: '',
          avatar: { color: '#8C8376', shape: 'dot' as const },
        },
        ...members,
      ].filter((member) => member.handle.startsWith(mentionMatch[1]!))
    : [];
  const activeMention = mentionOptions[Math.min(mentionIndex, mentionOptions.length - 1)];

  const {
    ref: scrollRef,
    away,
    unseen,
    onScroll,
    keepPosition,
    stickToBottom,
    toBottom,
  } = useChatScroll(messages, activity);

  useLayoutEffect(() => {
    const element = composerRef.current;
    if (!element) return;
    element.style.height = 'auto';
    element.style.height = Math.min(element.scrollHeight, 168) + 'px';
  }, [draft]);

  function insertMention(member: { handle: string }) {
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

  async function loadEarlier() {
    const first = messages[0];
    const nodeId = useAppStore.getState().selectedNodeId;
    if (!first || !nodeId || loadingEarlier) return;
    setLoadingEarlier(true);
    try {
      const result = await callNode('messages.list', {
        conversationId: conversation.conversationId,
        beforeSeq: first.seq,
        limit: 50,
      });
      keepPosition();
      useAppStore.getState().setMessages(nodeId, conversation.conversationId, result.messages);
      setHistoryComplete(result.messages.length < 50);
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : t.sendError);
    } finally {
      setLoadingEarlier(false);
    }
  }

  async function send(event: FormEvent) {
    event.preventDefault();
    const text = draft.trim();
    if ((!text && !files?.length) || sending || uploading || voiceBusy || !online || waiting)
      return;
    const fileIds = files?.map((file) => file.fileId) ?? [];
    const fingerprint = JSON.stringify([text, fileIds]);
    setSending(true);
    setError('');
    setInstructionAdded(false);
    const addingToCurrentRun = running;
    if (pendingDraft.current?.text !== fingerprint)
      pendingDraft.current = { text: fingerprint, clientMsgId: crypto.randomUUID() };
    try {
      await callNode('messages.send', {
        conversationId: conversation.conversationId,
        text,
        ...(fileIds.length ? { files: fileIds } : {}),
        clientMsgId: pendingDraft.current.clientMsgId,
      });
      if (useDrafts.getState().values[draftKey]?.trim() === text) setDraft('');
      useDrafts.getState().removeAttachments(draftKey, fileIds);
      pendingDraft.current = null;
      setInstructionAdded(addingToCurrentRun);
      stickToBottom();
      await loadConversation(conversation.conversationId);
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : t.sendError);
    } finally {
      setSending(false);
    }
  }

  async function attach(selected: FileList | null) {
    if (!selected || !nodeId || uploading) return;
    setUploading(true);
    setError('');
    try {
      for (const file of Array.from(selected)) {
        const uploaded = await uploadChatFile(file, conversation.conversationId, nodeId);
        useDrafts.getState().addAttachment(draftKey, uploaded);
      }
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : t.sendError);
    } finally {
      setUploading(false);
    }
  }

  async function selectModel(model: string) {
    setSavingModel(true);
    setError('');
    try {
      const result = await callNode('bots.update', { botId: bot.botId, model });
      useAppStore.setState((state) => {
        const node = nodeId && state.nodes[nodeId];
        return node
          ? {
              nodes: {
                ...state.nodes,
                [nodeId]: {
                  ...node,
                  bots: node.bots.map((entry) => (entry.botId === bot.botId ? result.bot : entry)),
                },
              },
            }
          : {};
      });
      setModelMenu(false);
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : t.saveError);
    } finally {
      setSavingModel(false);
    }
  }

  async function stop() {
    try {
      await callNode('runs.stop', { conversationId: conversation.conversationId });
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : t.sendError);
    }
  }

  const statusText = !online
    ? t.offline
    : activity === 'unknown'
      ? t.executionUnknown
      : connection === 'reconnecting'
        ? t.streamReconnecting
        : activity === 'thinking'
          ? t.thinking
          : activity === 'tool'
            ? t.usingTool
            : activity === 'waiting_approval'
              ? t.waitingApproval
              : activity === 'waiting_question'
                ? t.waitingQuestion
                : group
                  ? `${members.length} ${t.members}`
                  : '@' + bot.handle;
  const bannerText = fill(
    activity === 'unknown'
      ? t.executionUnknownHint
      : activity === 'waiting_question'
        ? t.botQuestionLine
        : waiting
          ? t.botWaitingLine
          : activity === 'tool'
            ? t.botToolLine
            : t.botThinkingLine,
    { name: bot.displayName },
  );
  const blocks = buildBlocks(messages, t);
  const lastBlock = blocks.at(-1);
  const lastMessage = messages.at(-1);
  const streamingTail =
    lastMessage?.author.type === 'bot' &&
    lastMessage.author.id === bot.botId &&
    lastMessage.status === 'streaming' &&
    lastMessage.kind === 'text';
  const thinkingInline =
    activity === 'thinking' &&
    !streamingTail &&
    lastBlock?.kind === 'bot' &&
    lastBlock.botId === bot.botId;
  const thinkingAlone = activity === 'thinking' && !streamingTail && !thinkingInline;
  const showIntro = messages.length < 50 || historyComplete;

  return (
    <div className="chat-column">
      <header className="chat-header">
        <button className="icon-button back-button" onClick={onBack} aria-label={t.home}>
          <Icon name="back" />
        </button>
        <button className="chat-title" onClick={onEdit}>
          <span className="chat-title-avatar">
            {group ? (
              <GroupDots colors={members.map((member) => member.avatar.color)} size={26} />
            ) : (
              <BotAvatar
                color={bot.avatar.color}
                shape={bot.avatar.shape}
                size={36}
                working={running && activity !== 'unknown'}
              />
            )}
          </span>
          <span className="chat-title-copy">
            <strong>{group?.name ?? bot.displayName}</strong>
            <small>
              {group && lead && (
                <span className="chat-lead">
                  {t.leadBot}: {lead.displayName}
                </span>
              )}
              <span
                className={`chat-status${online ? ' online' : ''}${running && online ? ' is-busy' : ''}${waiting ? ' is-waiting' : ''}`}
              >
                {online && running && !waiting ? <LoadingText text={statusText} /> : statusText}
              </span>
            </small>
          </span>
        </button>
        <button
          className="icon-button bordered"
          onClick={onScreen}
          aria-label={t.screenTitle}
          title={t.screenTitle}
        >
          <Icon name="monitor" />
        </button>
        <button
          className="icon-button bordered"
          onClick={onEdit}
          aria-label={group ? t.editGroup : t.editBot}
          title={group ? t.editGroup : t.details}
        >
          <Icon name="panel" />
        </button>
      </header>
      <div className="message-scroll" ref={scrollRef} onScroll={onScroll}>
        <div className="messages-inner">
          {messages.length >= 50 && !historyComplete && (
            <button
              className="secondary-button load-earlier"
              disabled={loadingEarlier}
              onClick={() => void loadEarlier()}
            >
              {loadingEarlier ? (
                <LoadingText text={t.loadEarlier} />
              ) : (
                <>
                  <Icon name="arrowUp" />
                  {t.loadEarlier}
                </>
              )}
            </button>
          )}
          {showIntro && (
            <div className="chat-intro">
              {group ? (
                <GroupDots colors={members.map((member) => member.avatar.color)} size={44} />
              ) : (
                <BotAvatar color={bot.avatar.color} shape={bot.avatar.shape} size={60} />
              )}
              <h2>{group?.name ?? bot.displayName}</h2>
              {!group && bot.role && <p className="chat-intro-role">{bot.role}</p>}
              <p className="muted">
                {group
                  ? fill(t.groupIntro, {
                      names: members.map((member) => member.displayName).join(t.listSeparator),
                      lead: lead?.displayName ?? '',
                    })
                  : fill(t.dmIntro, { name: bot.displayName })}
              </p>
              {!group && (
                <span className="chat-intro-meta">
                  @{bot.handle} · {bot.model}
                </span>
              )}
            </div>
          )}
          {blocks.map((block) => {
            if (block.kind === 'divider')
              return (
                <div className="day-divider" key={block.key}>
                  <span>{block.label}</span>
                </div>
              );
            if (block.kind === 'system')
              return (
                <Appear key={block.key} id={'message-' + block.message.messageId}>
                  <SystemLine t={t} message={block.message} onRetry={setDraft} />
                </Appear>
              );
            if (block.kind === 'user')
              return (
                <div className="user-block" key={block.key}>
                  {block.messages.map((message) => (
                    <Appear key={message.messageId} id={'message-' + message.messageId}>
                      <div className="message from-user">
                        <div className="user-bubble">
                          {message.kind === 'text' && (
                            <>
                              <MentionText text={message.content.text} mentions={handles} />
                              {!!message.content.files?.length && (
                                <MessageFiles ids={message.content.files} t={t} />
                              )}
                            </>
                          )}
                        </div>
                      </div>
                    </Appear>
                  ))}
                </div>
              );
            const author = bots.find((member) => member.botId === block.botId) ?? bot;
            const working =
              running && author.botId === bot.botId && block === lastBlock && !waiting;
            return (
              <div
                className="bot-block"
                key={block.key}
                style={{ '--bot': author.avatar.color } as CSSProperties}
              >
                <span className="block-avatar">
                  <BotAvatar
                    color={author.avatar.color}
                    shape={author.avatar.shape}
                    size={32}
                    working={working}
                  />
                </span>
                <div className="block-body">
                  {group && (
                    <span className="message-author">
                      <strong>{author.displayName}</strong> <span>@{author.handle}</span>
                    </span>
                  )}
                  {block.messages.map((message) => (
                    <Appear key={message.messageId} id={'message-' + message.messageId}>
                      <BotMessage
                        t={t}
                        bot={author}
                        members={group ? members : undefined}
                        message={message}
                      />
                    </Appear>
                  ))}
                  {thinkingInline && block === lastBlock && <ThinkingRow />}
                </div>
              </div>
            );
          })}
          {thinkingAlone && (
            <div className="bot-block" style={{ '--bot': bot.avatar.color } as CSSProperties}>
              <span className="block-avatar">
                <BotAvatar color={bot.avatar.color} shape={bot.avatar.shape} size={32} working />
              </span>
              <div className="block-body">
                {group && (
                  <span className="message-author">
                    <strong>{bot.displayName}</strong> <span>@{bot.handle}</span>
                  </span>
                )}
                <ThinkingRow />
              </div>
            </div>
          )}
          {group && running && chain && (
            <div className="chain-progress" role="status">
              <span className="chain-steps" aria-hidden="true">
                {Array.from({ length: chain.max }, (_, index) => (
                  <i key={index} className={index < chain.count ? 'done' : ''} />
                ))}
              </span>
              {t.relayProgress} {chain.count} / {chain.max} {t.relayRounds}
            </div>
          )}
          <div className="scroll-tail" />
        </div>
      </div>
      <div className="composer-wrap">
        <AnimatePresence>
          {away && (
            <motion.button
              className="jump-latest"
              onClick={toBottom}
              initial={{ opacity: 0, y: 8, x: '-50%' }}
              animate={{ opacity: 1, y: 0, x: '-50%' }}
              exit={{ opacity: 0, y: 8, x: '-50%' }}
              transition={tween('base', reduceMotion)}
            >
              <Icon name="arrowDown" />
              {unseen ? fill(t.newMessagesCount, { count: unseen }) : t.jumpLatest}
            </motion.button>
          )}
        </AnimatePresence>
        <AnimatePresence initial={false}>
          {running && (
            <motion.div
              className={`run-banner${waiting ? ' approval-waiting' : ''}${activity === 'unknown' ? ' execution-unknown' : ''}`}
              initial={{ opacity: 0, height: 0 }}
              animate={{ opacity: 1, height: 'auto' }}
              exit={{ opacity: 0, height: 0 }}
              transition={tween('base', reduceMotion)}
            >
              <span className="run-banner-copy">
                {waiting ? (
                  <Icon name="warning" />
                ) : (
                  <BotAvatar color={bot.avatar.color} shape={bot.avatar.shape} size={20} working />
                )}
                <span>{connection === 'reconnecting' ? t.streamReconnecting : bannerText}</span>
                {!waiting && <small className="run-banner-hint">· {t.steerHint}</small>}
              </span>
              <button className="stop-button" onClick={() => void stop()}>
                <i />
                {group ? t.stopAll : t.stop}
              </button>
            </motion.div>
          )}
        </AnimatePresence>
        {instructionAdded && (
          <p className="inline-success" role="status">
            <Icon name="check" />
            {t.currentInstruction}
          </p>
        )}
        {error && (
          <div className="inline-error" role="alert">
            <Icon name="warning" />
            <span>{error}</span>
            <button onClick={() => setError('')}>{t.close}</button>
          </div>
        )}
        <PromptInput
          hasContent={Boolean(draft || files?.length || uploading || voiceBusy)}
          running={running}
          onSubmit={(event) => void send(event)}
          attachments={
            files?.length ? (
              <div className="prompt-attachments">
                {files.map((file) => (
                  <DraftAttachment
                    key={file.fileId}
                    file={file}
                    nodeId={nodeId!}
                    t={t}
                    disabled={sending}
                    onRemove={() => useDrafts.getState().removeAttachments(draftKey, [file.fileId])}
                  />
                ))}
              </div>
            ) : undefined
          }
          tools={
            <>
              <details
                className="prompt-model"
                onBlur={(event) => {
                  if (!event.currentTarget.contains(event.relatedTarget)) setModelMenu(false);
                }}
                onKeyDown={(event) => {
                  if (event.key === 'Escape') {
                    setModelMenu(false);
                    event.currentTarget.querySelector('summary')?.focus();
                  }
                }}
                open={modelMenu}
                onToggle={(event) => setModelMenu(event.currentTarget.open)}
              >
                <summary>
                  <span className="sr-only">{t.model}: </span>
                  <Icon name="bot" />
                  <span>
                    {group ? (zh ? '群聊模型' : 'Group models') : bot.model || t.chooseModel}
                  </span>
                  <Icon name="chevronDown" />
                </summary>
                <div className="prompt-model-menu">
                  <strong>{t.model}</strong>
                  {!group && catalog.loading && <LoadingText />}
                  {!group &&
                    [...new Set([bot.model, ...catalog.models])].filter(Boolean).map((model) => (
                      <button
                        type="button"
                        key={model}
                        disabled={!online || savingModel || model === bot.model}
                        onClick={async () => {
                          await selectModel(model);
                          composerRef.current?.focus();
                        }}
                      >
                        <span>{model}</span>
                        {model === bot.model && <Icon name="check" />}
                      </button>
                    ))}
                  {!group && catalog.error && <small role="alert">{catalog.error}</small>}
                  <button
                    type="button"
                    onClick={() => {
                      setModelMenu(false);
                      onEdit();
                    }}
                  >
                    {group ? t.editGroup : t.editBot}
                    <Icon name="settings" />
                  </button>
                </div>
              </details>
              <button
                className="prompt-attach"
                type="button"
                disabled={!online || uploading || sending}
                aria-label={zh ? '添加文件或图片' : 'Attach file or image'}
                onClick={() => fileRef.current?.click()}
              >
                {uploading ? <LoadingText /> : <Icon name="plus" />}
              </button>
            </>
          }
          action={
            <>
              {!running && (voiceBusy || (!draft.trim() && !files?.length)) && (
                <VoiceInput
                  key={draftKey}
                  botId={group?.leadBotId ?? bot.botId}
                  disabled={!online || sending || uploading || waiting}
                  onBusy={setVoiceBusy}
                  onError={setError}
                  onTranscript={(text) => {
                    const previous = useDrafts.getState().values[draftKey] ?? '';
                    useDrafts.getState().set(draftKey, previous + (previous ? ' ' : '') + text);
                    composerRef.current?.focus();
                  }}
                />
              )}
              {(running || Boolean(draft.trim() || files?.length)) && (
                <button
                  type={running && !draft.trim() && !files?.length ? 'button' : 'submit'}
                  className={`send-button${sending ? ' is-sending' : ''}`}
                  disabled={
                    running && !draft.trim() && !files?.length
                      ? !online
                      : (!draft.trim() && !files?.length) ||
                        sending ||
                        uploading ||
                        voiceBusy ||
                        !online ||
                        waiting
                  }
                  aria-label={running && !draft.trim() && !files?.length ? t.stop : t.send}
                  onClick={
                    running && !draft.trim() && !files?.length ? () => void stop() : undefined
                  }
                >
                  {sending ? (
                    <LoadingText text={zh ? '发送中' : 'Sending'} />
                  ) : running && !draft.trim() && !files?.length ? (
                    <span className="prompt-stop" />
                  ) : (
                    <Icon name="arrowUp" />
                  )}
                </button>
              )}
            </>
          }
        >
          <input
            ref={fileRef}
            type="file"
            multiple
            hidden
            onChange={(event) => {
              void attach(event.target.files);
              event.target.value = '';
            }}
          />
          <AnimatePresence>
            {mentionOptions.length > 0 && (
              <motion.div
                className="mention-menu"
                role="listbox"
                aria-label={t.mentionMember}
                initial={{ opacity: 0, y: 6, scale: 0.98 }}
                animate={{ opacity: 1, y: 0, scale: 1 }}
                exit={{ opacity: 0, y: 4, scale: 0.98 }}
                transition={tween('fast', reduceMotion)}
              >
                <span className="mention-heading">{t.mentionMember}</span>
                <AnimatedList>
                  {mentionOptions.map((member) => (
                    <button
                      key={member.botId}
                      type="button"
                      role="option"
                      aria-selected={member === activeMention}
                      onMouseDown={(event) => event.preventDefault()}
                      onMouseMove={() => setMentionIndex(mentionOptions.indexOf(member))}
                      onClick={() => insertMention(member)}
                    >
                      <BotAvatar
                        color={member.avatar.color}
                        shape={member.avatar.shape}
                        size={26}
                      />
                      <strong>{member.displayName}</strong>
                      <small>
                        @{member.handle}
                        {member.role ? ' · ' + member.role : ''}
                      </small>
                    </button>
                  ))}
                </AnimatedList>
              </motion.div>
            )}
          </AnimatePresence>
          <textarea
            ref={composerRef}
            aria-label={running ? t.supplement : t.typeMessage}
            placeholder={
              running
                ? t.supplement
                : group
                  ? t.typeGroupMessage
                  : fill(t.typeMessageTo, { name: bot.displayName })
            }
            rows={1}
            value={draft}
            onChange={(event) => {
              setDraft(event.target.value);
              setCaret(event.target.selectionStart);
              setMentionIndex(0);
            }}
            onSelect={(event) => setCaret(event.currentTarget.selectionStart)}
            onKeyDown={(event) => {
              if (mentionOptions.length && (event.key === 'ArrowDown' || event.key === 'ArrowUp')) {
                event.preventDefault();
                const step = event.key === 'ArrowDown' ? 1 : -1;
                setMentionIndex(
                  (mentionOptions.indexOf(activeMention!) + step + mentionOptions.length) %
                    mentionOptions.length,
                );
                return;
              }
              if (
                !event.nativeEvent.isComposing &&
                mentionOptions.length &&
                (event.key === 'Tab' || event.key === 'Enter')
              ) {
                event.preventDefault();
                insertMention(activeMention!);
                return;
              }
              if (event.key === 'Enter' && !event.shiftKey && !event.nativeEvent.isComposing) {
                event.preventDefault();
                event.currentTarget.form?.requestSubmit();
              }
            }}
          />
        </PromptInput>
        {waiting && <div className="composer-hint">{t.approvalDraftHint}</div>}
      </div>
    </div>
  );
}

type Block =
  | { kind: 'divider'; key: string; label: string }
  | { kind: 'system'; key: string; message: Message }
  | { kind: 'user'; key: string; messages: Message[] }
  | { kind: 'bot'; key: string; botId?: string; messages: Message[] };

function visible(message: Message) {
  if (
    (message.kind === 'text' || message.kind === 'commentary') &&
    message.author.type === 'bot' &&
    message.status === 'done' &&
    !readableMessageText(message.content.text) &&
    !(message.kind === 'text' && message.content.files?.length)
  )
    return false;
  return true;
}

/** Groups consecutive messages by author and inserts time dividers on gaps of 30+ minutes. */
function buildBlocks(messages: Message[], t: Texts): Block[] {
  const blocks: Block[] = [];
  let previous: Message | undefined;
  for (const message of messages.filter(visible)) {
    const time = new Date(message.createdAt);
    if (!previous || time.getTime() - new Date(previous.createdAt).getTime() >= 30 * 60_000)
      blocks.push({
        kind: 'divider',
        key: 'divider-' + message.messageId,
        label: dividerLabel(time, t),
      });
    const last = blocks.at(-1);
    if (message.author.type === 'system')
      blocks.push({ kind: 'system', key: message.messageId, message });
    else if (message.author.type === 'user') {
      if (last?.kind === 'user') last.messages.push(message);
      else blocks.push({ kind: 'user', key: message.messageId, messages: [message] });
    } else if (last?.kind === 'bot' && last.botId === message.author.id)
      last.messages.push(message);
    else
      blocks.push({
        kind: 'bot',
        key: message.messageId,
        botId: message.author.id,
        messages: [message],
      });
    previous = message;
  }
  return blocks;
}

function dividerLabel(date: Date, t: Texts) {
  const locale = t.team === '团队' ? 'zh-CN' : 'en-US';
  const clock = date.toLocaleTimeString(locale, {
    hour: '2-digit',
    minute: '2-digit',
    hour12: false,
  });
  const day = new Date(date.getFullYear(), date.getMonth(), date.getDate()).getTime();
  const now = new Date();
  const today = new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime();
  const days = Math.round((today - day) / 86_400_000);
  if (days === 0) return `${t.today} ${clock}`;
  if (days === 1) return `${t.yesterday} ${clock}`;
  return (
    date.toLocaleDateString(locale, { month: 'short', day: 'numeric', weekday: 'short' }) +
    ' ' +
    clock
  );
}

/** Follows new content only while the reader is at the bottom; otherwise counts what arrived. */
function useChatScroll(messages: Message[], activity: Activity) {
  const ref = useRef<HTMLDivElement>(null);
  const atBottom = useRef(true);
  const restore = useRef<{ height: number; top: number } | null>(null);
  const count = useRef(messages.length);
  const [away, setAway] = useState(false);
  const [unseen, setUnseen] = useState(0);
  const reduceMotion = useReducedMotion();
  const last = messages.at(-1);
  const lastSize =
    last && (last.kind === 'text' || last.kind === 'commentary') ? last.content.text.length : 0;

  useLayoutEffect(() => {
    const element = ref.current;
    if (!element) return;
    const added = messages.length - count.current;
    count.current = messages.length;
    if (restore.current) {
      element.scrollTop = restore.current.top + (element.scrollHeight - restore.current.height);
      restore.current = null;
      return;
    }
    if (atBottom.current) element.scrollTop = element.scrollHeight;
    else if (added > 0) setUnseen((value) => value + added);
  }, [messages.length, lastSize, activity, last?.status, messages]);

  useEffect(() => {
    const element = ref.current;
    if (!element) return;
    element.scrollTo({ top: element.scrollHeight });
    // Late layout (file cards, images, expanded tool results, a resized composer) must not
    // push the newest content out of view while the reader is following the conversation.
    const observer = new ResizeObserver(() => {
      if (atBottom.current && !restore.current) element.scrollTop = element.scrollHeight;
    });
    observer.observe(element);
    if (element.firstElementChild) observer.observe(element.firstElementChild);
    return () => observer.disconnect();
  }, []);

  return {
    ref,
    away,
    unseen,
    onScroll() {
      const element = ref.current!;
      const near = element.scrollHeight - element.scrollTop - element.clientHeight < 96;
      atBottom.current = near;
      setAway(!near);
      if (near) setUnseen(0);
    },
    keepPosition() {
      const element = ref.current;
      if (element) restore.current = { height: element.scrollHeight, top: element.scrollTop };
    },
    stickToBottom() {
      atBottom.current = true;
    },
    toBottom() {
      atBottom.current = true;
      setUnseen(0);
      ref.current?.scrollTo({
        top: ref.current.scrollHeight,
        behavior: reduceMotion ? 'auto' : 'smooth',
      });
    },
  };
}

function Appear({ id, children }: { id: string; children: ReactNode }) {
  const reduceMotion = useReducedMotion();
  return (
    <motion.div
      id={id}
      className="appear"
      initial={{ opacity: 0, y: reduceMotion ? 0 : shift[2] }}
      animate={{ opacity: 1, y: 0 }}
      transition={tween('base', reduceMotion)}
    >
      {children}
    </motion.div>
  );
}

function ThinkingRow() {
  return (
    <div className="thinking-row">
      <LoadingText
        text={useAppStore((state) => state.language) === 'zh' ? '正在思考…' : 'Thinking…'}
      />
    </div>
  );
}

function SystemLine({
  t,
  message,
  onRetry,
}: {
  t: Texts;
  message: Message;
  onRetry(text: string): void;
}) {
  if (message.kind !== 'system') return null;
  const text = message.content.text;
  return (
    <p className="system-message">
      <span>
        {message.content.retryText ? (
          <>
            {t.unconsumedInstruction}{' '}
            <button className="text-button" onClick={() => onRetry(message.content.retryText!)}>
              {t.prepareResend}
            </button>
          </>
        ) : text === 'Relay paused after 6 turns. Mention a group member to continue.' ? (
          t.relayPaused
        ) : text.endsWith(' could not complete this turn.') ? (
          t.botTurnFailed.replace('{name}', text.slice(0, -' could not complete this turn.'.length))
        ) : (
          text
        )}
      </span>
    </p>
  );
}

function QuestionCard({
  message,
  t,
}: {
  message: Extract<Message, { kind: 'question' }>;
  t: Texts;
}) {
  const [selected, setSelected] = useState<string[]>([]);
  const [answer, setAnswer] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const pending = message.status === 'streaming';
  async function respond(event: FormEvent) {
    event.preventDefault();
    setBusy(true);
    setError('');
    try {
      await callNode('questions.respond', {
        messageId: message.messageId,
        answer: [...selected, answer.trim()].filter(Boolean).join('\n'),
      });
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : String(reason));
    } finally {
      setBusy(false);
    }
  }
  return (
    <form className="question-card" onSubmit={(event) => void respond(event)}>
      <strong>{message.content.question}</strong>
      {pending ? (
        <>
          <AnimatedList className="approval-actions">
            {message.content.choices.map((choice) => (
              <button
                type="button"
                className="secondary-button"
                key={choice}
                aria-pressed={selected.includes(choice)}
                onClick={() =>
                  setSelected(
                    message.content.multiSelect
                      ? selected.includes(choice)
                        ? selected.filter((item) => item !== choice)
                        : [...selected, choice]
                      : [choice],
                  )
                }
              >
                {choice}
              </button>
            ))}
          </AnimatedList>
          <textarea
            aria-label={t.questionAnswer}
            value={answer}
            onChange={(event) => setAnswer(event.target.value)}
          />
          <button
            className="primary-button"
            disabled={busy || (!selected.length && !answer.trim())}
          >
            {t.submitAnswer}
          </button>
        </>
      ) : (
        <p>
          {message.content.answer ??
            (message.status === 'cancelled' ? t.stopped : t.questionClosed)}
        </p>
      )}
      {error && (
        <p role="alert" className="form-error">
          {error}
        </p>
      )}
    </form>
  );
}

function BotMessage({
  t,
  bot,
  message,
  members,
}: {
  t: Texts;
  bot: Bot;
  message: Message;
  members?: Bot[];
}) {
  const reduceMotion = useReducedMotion();
  const [welcomeError, setWelcomeError] = useState('');
  if (message.kind === 'tool') return <ToolCard t={t} message={message} />;
  if (message.kind === 'approval') return <ApprovalCard t={t} message={message} />;
  if (message.kind === 'question') return <QuestionCard message={message} t={t} />;
  if (message.kind !== 'text' && message.kind !== 'commentary') return null;
  const displayText = readableMessageText(message.content.text);
  const handoffs =
    members && message.kind === 'text' && message.status === 'done'
      ? members.filter(
          (member) =>
            member.botId !== bot.botId &&
            new RegExp(`(?:^|[^\\w@-])@${member.handle}(?![a-z0-9-])`).test(message.content.text),
        )
      : [];
  return (
    <div
      className={`message message-${message.kind}${message.content.welcome ? ' welcome-introduction' : ''}`}
    >
      <div className={message.kind === 'commentary' ? 'commentary-copy' : 'bot-copy'}>
        {message.kind === 'commentary' ? (
          displayText
        ) : (
          <Markdown
            text={displayText}
            mentions={members?.map((member) => member.handle)}
            copyLabel={t.copyText}
            copiedLabel={t.copied}
            trailing={message.status === 'streaming' && <span className="stream-cursor">▍</span>}
          />
        )}
        {message.kind === 'commentary' && message.status === 'streaming' && (
          <span className="stream-cursor">▍</span>
        )}
        {message.status === 'failed' && (
          <small className="message-state failed-state">
            {message.content.failureReason ?? t.failed}
          </small>
        )}
        {message.status === 'cancelled' && <small className="message-state">{t.stopped}</small>}
        {message.content.welcome && ['failed', 'cancelled'].includes(message.status) && (
          <button
            className="text-button"
            onClick={() => {
              setWelcomeError('');
              void callNode('bots.welcome.retry', { messageId: message.messageId }).catch(
                (e: Error) => setWelcomeError(e.message),
              );
            }}
          >
            {t.retryWelcome}
          </button>
        )}
        {welcomeError && (
          <p className="form-error" role="alert">
            {welcomeError}
          </p>
        )}
      </div>
      {message.kind === 'text' && !!message.content.files?.length && (
        <MessageFiles ids={message.content.files} t={t} />
      )}
      {handoffs.map((member) => (
        <motion.span
          className="handoff-tag"
          key={member.botId}
          initial={{ opacity: 0, x: reduceMotion ? 0 : -shift[3] }}
          animate={{ opacity: 1, x: 0 }}
          transition={tween('base', reduceMotion)}
        >
          <Icon name="arrow" />
          {t.handoffTo} @{member.handle}
          <motion.span
            className="handoff-avatar"
            animate={{ y: reduceMotion ? 0 : [0, -shift[1], 0] }}
            transition={tween('panel', reduceMotion, durations.fast)}
          >
            <BotAvatar color={member.avatar.color} shape={member.avatar.shape} size={16} />
          </motion.span>
        </motion.span>
      ))}
      {message.kind === 'text' && message.status === 'done' && displayText && (
        <CopyButton t={t} text={displayText} />
      )}
    </div>
  );
}

function CopyButton({ t, text }: { t: Texts; text: string }) {
  const [copied, setCopied] = useState(false);
  return (
    <div className="message-actions">
      <button
        className="tiny-icon"
        aria-label={copied ? t.copied : t.copyText}
        title={copied ? t.copied : t.copyText}
        onClick={() =>
          void writeClipboard(text).then(() => {
            setCopied(true);
            window.setTimeout(() => setCopied(false), 1600);
          })
        }
      >
        <Icon name={copied ? 'check' : 'copy'} />
      </button>
    </div>
  );
}

function toolIcon(tool: string): IconName {
  const name = tool.toLowerCase();
  if (/search|find|grep/.test(name)) return 'search';
  if (/browser|url|web|fetch|http/.test(name)) return 'globe';
  if (/terminal|shell|exec|command|code|python/.test(name)) return 'terminal';
  if (/file|read|write|patch|edit|doc/.test(name)) return 'doc';
  if (/memory|skill|refine/.test(name)) return 'spark';
  return 'plugin';
}

function ToolCard({ t, message }: { t: Texts; message: Extract<Message, { kind: 'tool' }> }) {
  const reduceMotion = useReducedMotion();
  const [expanded, setExpanded] = useState(false);
  const state =
    message.status === 'streaming'
      ? 'running'
      : message.status === 'cancelled'
        ? 'stopped'
        : message.content.error || message.status === 'failed'
          ? 'failed'
          : 'done';
  const label =
    state === 'running'
      ? t.usingTool
      : state === 'stopped'
        ? t.stopped
        : state === 'failed'
          ? t.failed
          : t.completed;
  const duration = message.content.durationMs
    ? fill(t.seconds, { value: (message.content.durationMs / 1000).toFixed(1) })
    : '';
  return (
    <div className={`tool-card is-${state}`}>
      <button
        className="tool-summary"
        aria-expanded={expanded}
        onClick={() => setExpanded(!expanded)}
      >
        <span className="tool-icon">
          <Icon name={toolIcon(message.content.tool)} />
        </span>
        <span className="tool-title">
          <strong>{message.content.tool}</strong>
          <small>{message.content.preview}</small>
        </span>
        <span className="tool-status">
          {duration && state === 'done' && <span className="tool-duration">{duration}</span>}
          <span className={state === 'done' || state === 'running' ? 'sr-only' : 'tool-state'}>
            {label}
          </span>
          <span className="tool-state-icon">
            <AnimatePresence initial={false} mode="popLayout">
              <motion.span
                key={state}
                initial={{ opacity: 0, scale: 0.6 }}
                animate={{ opacity: 1, scale: 1 }}
                exit={{ opacity: 0, scale: 0.6 }}
                transition={tween('fast', reduceMotion)}
              >
                {state === 'running' ? (
                  <LoadingText text={label} />
                ) : (
                  <Icon
                    name={state === 'done' ? 'check' : state === 'stopped' ? 'stop' : 'warning'}
                  />
                )}
              </motion.span>
            </AnimatePresence>
          </span>
          <span className="tool-chevron">
            <Icon name="chevronDown" />
          </span>
        </span>
      </button>
      <AnimatePresence initial={false}>
        {expanded && (
          <motion.div
            className="tool-result"
            initial={{ height: 0, opacity: 0 }}
            animate={{ height: 'auto', opacity: 1 }}
            exit={{ height: 0, opacity: 0 }}
            transition={springy(reduceMotion)}
          >
            <div className="tool-result-inner">
              <span>{t.toolInput}</span>
              <pre>{message.content.preview}</pre>
              {message.content.resultPreview && (
                <>
                  <span>
                    {t.toolOutput}
                    {duration ? ' · ' + duration : ''}
                  </span>
                  <pre>{message.content.resultPreview}</pre>
                </>
              )}
            </div>
          </motion.div>
        )}
      </AnimatePresence>
    </div>
  );
}

function ApprovalCard({
  t,
  message,
}: {
  t: Texts;
  message: Extract<Message, { kind: 'approval' }>;
}) {
  const connected = useAppStore(
    (state) =>
      state.socketReady &&
      Boolean(state.selectedNodeId && state.nodes[state.selectedNodeId]?.online),
  );
  const choiceLabels = {
    once: t.allowOnce,
    session: t.allowSession,
    always: t.allowAlways,
    deny: t.deny,
  };
  const resultLabels = {
    once: t.approved,
    session: t.approvedSession,
    always: t.approvedAlways,
    deny: t.denied,
  };
  const status = message.content.choice
    ? resultLabels[message.content.choice]
    : message.status === 'cancelled'
      ? t.stopped
      : message.status === 'failed'
        ? t.failed
        : '';
  const choices = message.content.choices ?? (['once', 'deny'] as const);
  return (
    <AIApproval
      key={message.messageId}
      className="approval-card"
      disabled={!connected}
      question={t.approvalTitle}
      options={choices.map((choice) => ({
        id: choice,
        label: choiceLabels[choice],
        resultLabel: resultLabels[choice],
        destructive: choice === 'deny',
      }))}
      resolvedId={message.content.choice}
      resolvedLabel={status || (message.status !== 'streaming' ? t.completed : undefined)}
      onDecide={async (option) => {
        await callNode('approvals.respond', {
          messageId: message.messageId,
          choice: option.id as ApprovalChoice,
        });
      }}
    >
      <p>{message.content.prompt}</p>
      {message.content.command && <pre className="approval-command">{message.content.command}</pre>}
      {choices.some((choice) => choice === 'session' || choice === 'always') && (
        <small className="approval-scope-hint">{t.approvalScopeHint}</small>
      )}
    </AIApproval>
  );
}
