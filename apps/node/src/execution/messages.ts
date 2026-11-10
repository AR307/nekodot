import { randomUUID } from 'node:crypto';
import type { LiveEvent, Message } from '@nekodot/protocol';
import type { NodeDatabase, RunRecord } from '../database';
import type { NativeSessionSnapshot } from '../hermes/session';

type TextMessage = Extract<Message, { kind: 'text' }>;
const now = () => new Date().toISOString();

export class RunMessages {
  private readonly textProgress = new Map<string, { persistedAt: number; length: number }>();
  private readonly streamingTexts = new Map<string, string>();

  constructor(
    private readonly database: NodeDatabase,
    private readonly onLive: (event: LiveEvent) => void,
  ) {}

  buffered(messageId: string) {
    return this.streamingTexts.get(messageId);
  }

  release(messageId: string | undefined) {
    if (!messageId) return;
    this.streamingTexts.delete(messageId);
    this.textProgress.delete(messageId);
  }

  append(run: RunRecord, message: TextMessage, delta: string, seq: number) {
    const previous = this.streamingTexts.get(message.messageId) ?? message.content.text;
    message.content = { ...message.content, text: previous + delta };
    this.streamingTexts.set(message.messageId, message.content.text);
    this.onLive({
      kind: 'delta',
      conversationId: run.conversationId,
      messageId: message.messageId,
      text: delta,
      offset: previous.length,
    });
    const progress = this.textProgress.get(message.messageId) ?? { persistedAt: 0, length: 0 };
    if (
      message.content.text.length - progress.length >= 400 ||
      Date.now() - progress.persistedAt >= 1000
    ) {
      this.persistText(run, message, seq);
    }
  }

  reconcileNativeText(run: RunRecord, snapshot: NativeSessionSnapshot) {
    const active = this.currentText(run);
    if (!active) return;
    const text = [...(snapshot.messages ?? [])]
      .reverse()
      .find((message) => message.role === 'assistant' && typeof message.text === 'string')?.text;
    if (typeof text !== 'string' || !text.startsWith(active.content.text)) return;
    active.content = { ...active.content, text };
    this.persistText(run, active, snapshot.last_sequence);
  }

  ensureText(run: RunRecord): TextMessage {
    const current = this.currentText(run);
    if (current) return current;
    const message = this.newText(run, '', 'streaming');
    run.textMessageId = message.messageId;
    const saved = this.database.putMessage(message, { runId: run.runId }, run) as TextMessage;
    this.textProgress.set(saved.messageId, { persistedAt: Date.now(), length: 0 });
    this.streamingTexts.set(saved.messageId, '');
    return saved;
  }

  currentText(run: RunRecord) {
    const message = run.textMessageId ? this.database.message(run.textMessageId) : undefined;
    if (message?.kind !== 'text') return undefined;
    const current = message as TextMessage;
    const buffered = this.streamingTexts.get(current.messageId);
    if (buffered !== undefined) current.content = { ...current.content, text: buffered };
    return current;
  }

  newText(run: RunRecord, text: string, status: Message['status']): TextMessage;

  newText(run: RunRecord, text: string, status: Message['status'], kind: 'text'): TextMessage;

  newText(
    run: RunRecord,
    text: string,
    status: Message['status'],
    kind: 'commentary',
  ): Extract<Message, { kind: 'commentary' }>;

  newText(
    run: RunRecord,
    text: string,
    status: Message['status'],
    kind: 'text' | 'commentary' = 'text',
  ): TextMessage | Extract<Message, { kind: 'commentary' }> {
    return {
      messageId: randomUUID(),
      nativeSessionId: run.storedSessionId,
      ...(run.taskId
        ? {
            taskId: run.taskId,
            taskRole: run.role === 'execution' ? ('execution' as const) : ('report' as const),
          }
        : {}),
      conversationId: run.conversationId,
      seq: this.database.head(),
      author: { type: 'bot', id: run.botId },
      kind,
      status,
      createdAt: now(),
      content: { text, ...(run.welcome ? { welcome: true as const } : {}) },
    };
  }

  persistText(run: RunRecord, message: TextMessage | undefined, seq: number) {
    if (message) {
      run.textMessageId = message.messageId;
      message.seq = this.database.head();
      run.lastSeq = seq;
      this.database.putMessage(message, { runId: run.runId }, run);
      if (message.status === 'streaming') {
        this.textProgress.set(message.messageId, {
          persistedAt: Date.now(),
          length: message.content.text.length,
        });
        this.streamingTexts.set(message.messageId, message.content.text);
      } else this.release(message.messageId);
    } else {
      run.lastSeq = seq;
      this.database.saveRun(run);
    }
  }
}
