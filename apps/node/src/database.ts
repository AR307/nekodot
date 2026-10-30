import { DatabaseSync } from 'node:sqlite';
import { mkdirSync } from 'node:fs';
import { join } from 'node:path';
import type {
  Bot,
  Conversation,
  Group,
  Message,
  PersistedEvent,
  RpcResult,
} from '@nekodot/protocol';

export interface RunRecord {
  runId?: string;
  conversationId: string;
  botId: string;
  groupId?: string;
  requestId?: string;
  stopRequested?: boolean;
  lastSeq: number;
  state: 'thinking' | 'tool' | 'waiting_approval' | 'waiting_question' | 'idle';
  textMessageId?: string;
  inputMessageId: string;
  welcome?: true;
}

export interface GroupChainRecord {
  notificationId: string;
  failed?: boolean;
  conversationId: string;
  group: Group;
  roster: Bot[];
  queue: string[];
  count: number;
  cursorByBot: Record<string, number>;
  currentBotId?: string;
  currentInput?: string;
  currentInstructions?: string;
  requestId?: string;
  active: boolean;
}

export class NodeDatabase {
  readonly db: DatabaseSync;
  onEvent: (event: PersistedEvent) => void = () => {};
  constructor(readonly directory: string) {
    mkdirSync(directory, { recursive: true, mode: 0o700 });
    this.db = new DatabaseSync(join(directory, 'node.db'));
    this.db.exec('PRAGMA journal_mode=WAL');
    let version = Number(this.db.prepare('PRAGMA user_version').get()!.user_version);
    if (version < 1) {
      this.db
        .exec(`CREATE TABLE bots(bot_id TEXT PRIMARY KEY,handle TEXT UNIQUE NOT NULL,data TEXT NOT NULL);
        CREATE TABLE conversations(conversation_id TEXT PRIMARY KEY,bot_id TEXT UNIQUE NOT NULL,data TEXT NOT NULL);
        CREATE TABLE messages(message_id TEXT PRIMARY KEY,conversation_id TEXT NOT NULL,client_msg_id TEXT UNIQUE,run_id TEXT,tool_call_id TEXT,created_seq INTEGER NOT NULL,data TEXT NOT NULL);
        CREATE INDEX message_conversation ON messages(conversation_id,created_seq);
        CREATE TABLE events(seq INTEGER PRIMARY KEY AUTOINCREMENT,kind TEXT NOT NULL,data TEXT NOT NULL);
        CREATE TABLE settings(key TEXT PRIMARY KEY,value TEXT NOT NULL);
        CREATE TABLE runs(conversation_id TEXT PRIMARY KEY,data TEXT NOT NULL);
        PRAGMA user_version=1;`);
      version = 1;
    }
    if (version < 2) {
      this.db.exec(`BEGIN;
        ALTER TABLE conversations RENAME TO conversations_v1;
        CREATE TABLE conversations(
          conversation_id TEXT PRIMARY KEY,
          kind TEXT NOT NULL,
          bot_id TEXT,
          group_id TEXT,
          data TEXT NOT NULL
        );
        INSERT INTO conversations(conversation_id,kind,bot_id,data)
          SELECT conversation_id,'dm',bot_id,data FROM conversations_v1;
        CREATE UNIQUE INDEX conversation_dm_bot ON conversations(bot_id) WHERE kind='dm';
        CREATE UNIQUE INDEX conversation_group_id ON conversations(group_id) WHERE kind='group';
        DROP TABLE conversations_v1;
        CREATE TABLE groups(group_id TEXT PRIMARY KEY,data TEXT NOT NULL);
        CREATE TABLE group_chains(conversation_id TEXT PRIMARY KEY,data TEXT NOT NULL);
        PRAGMA user_version=2;
        COMMIT;`);
    }
    this.db.exec(`CREATE TABLE IF NOT EXISTS attachments(
      file_id TEXT PRIMARY KEY,bot_id TEXT NOT NULL,message_id TEXT NOT NULL,
      reference TEXT NOT NULL,storage_path TEXT,data TEXT NOT NULL,
      UNIQUE(message_id,reference)
    ); CREATE INDEX IF NOT EXISTS attachments_bot ON attachments(bot_id);`);
  }
  private all<T>(sql: string, ...params: string[]): T[] {
    return this.db
      .prepare(sql)
      .all(...params)
      .map((r) => JSON.parse(r.data as string) as T);
  }
  bots() {
    return this.all<Bot>('SELECT data FROM bots').filter((b) => !b.archived);
  }
  bot(id: string) {
    return this.all<Bot>('SELECT data FROM bots WHERE bot_id=?', id)[0];
  }
  allBots() {
    return this.all<Bot>('SELECT data FROM bots');
  }
  handleUsed(handle: string, id?: string) {
    return !!this.db
      .prepare('SELECT 1 FROM bots WHERE handle=? AND bot_id<>?')
      .get(handle, id ?? '');
  }
  conversations() {
    return this.all<Conversation>('SELECT data FROM conversations');
  }
  groups() {
    return this.all<Group>('SELECT data FROM groups').filter((group) => !group.archived);
  }
  group(id: string) {
    return this.all<Group>('SELECT data FROM groups WHERE group_id=?', id)[0];
  }
  conversation(id: string) {
    return this.all<Conversation>('SELECT data FROM conversations WHERE conversation_id=?', id)[0];
  }
  message(id: string) {
    return this.all<Message>('SELECT data FROM messages WHERE message_id=?', id)[0];
  }
  messageRun(id: string) {
    const row = this.db.prepare('SELECT run_id FROM messages WHERE message_id=?').get(id);
    return row?.run_id ? String(row.run_id) : undefined;
  }
  messagesForRun(runId: string) {
    return this.all<Message>(
      'SELECT data FROM messages WHERE run_id=? ORDER BY created_seq',
      runId,
    );
  }
  byClient(id: string) {
    return this.all<Message>('SELECT data FROM messages WHERE client_msg_id=?', id)[0];
  }
  tool(runId: string, callId: string) {
    return this.all<Message>(
      'SELECT data FROM messages WHERE run_id=? AND tool_call_id=?',
      runId,
      callId,
    )[0];
  }
  approval(runId: string, requestId: string) {
    return this.messagesForRun(runId).find(
      (message) => message.kind === 'approval' && message.content.requestId === requestId,
    );
  }
  runMessages(runId: string) {
    return this.all<Message>(
      'SELECT data FROM messages WHERE run_id=? ORDER BY created_seq',
      runId,
    );
  }
  messages(conversationId: string, beforeSeq?: number, limit = 50) {
    return this.db
      .prepare(
        'SELECT data FROM messages WHERE conversation_id=? AND created_seq<? ORDER BY created_seq DESC LIMIT ?',
      )
      .all(conversationId, beforeSeq ?? Number.MAX_SAFE_INTEGER, limit)
      .map((r) => JSON.parse(r.data as string) as Message)
      .reverse();
  }
  messagesAfter(conversationId: string, afterSeq: number) {
    return this.db
      .prepare(
        'SELECT data FROM messages WHERE conversation_id=? AND created_seq>? ORDER BY created_seq',
      )
      .all(conversationId, afterSeq)
      .map((row) => JSON.parse(row.data as string) as Message);
  }
  head() {
    return Number(this.db.prepare('SELECT COALESCE(MAX(seq),0) AS seq FROM events').get()!.seq);
  }
  since(seq: number): RpcResult<'sync.since'> {
    const headSeq = this.head();
    if (headSeq - seq > 1000 || seq > headSeq) return { events: [], headSeq, resyncRequired: true };
    const events = this.db
      .prepare('SELECT seq,kind,data FROM events WHERE seq>? ORDER BY seq')
      .all(seq)
      .map(
        (r) =>
          ({
            seq: Number(r.seq),
            kind: r.kind,
            data: JSON.parse(r.data as string),
          }) as PersistedEvent,
      );
    return { events, headSeq, resyncRequired: false };
  }
  private write(
    kind: PersistedEvent['kind'],
    data: unknown,
    save: (seq: number) => void,
    run?: RunRecord,
    chain?: GroupChainRecord,
  ) {
    this.db.exec('BEGIN');
    let event: PersistedEvent;
    try {
      const seq = Number(
        this.db.prepare('INSERT INTO events(kind,data) VALUES(?,?)').run(kind, '{}')
          .lastInsertRowid,
      );
      save(seq);
      const payload = data;
      if (run) this.saveRun(run);
      if (chain) this.saveChain(chain);
      this.db.prepare('UPDATE events SET data=? WHERE seq=?').run(JSON.stringify(payload), seq);
      event = { seq, kind, data: payload } as PersistedEvent;
      this.db.exec('COMMIT');
    } catch (error) {
      this.db.exec('ROLLBACK');
      throw error;
    }
    this.onEvent(event);
    return event;
  }
  private writeBatch(
    items: { kind: PersistedEvent['kind']; data: unknown; save: (seq: number) => void }[],
  ) {
    const events: PersistedEvent[] = [];
    this.db.exec('BEGIN');
    try {
      for (const item of items) {
        const seq = Number(
          this.db.prepare('INSERT INTO events(kind,data) VALUES(?,?)').run(item.kind, '{}')
            .lastInsertRowid,
        );
        item.save(seq);
        this.db.prepare('UPDATE events SET data=? WHERE seq=?').run(JSON.stringify(item.data), seq);
        events.push({ seq, kind: item.kind, data: item.data } as PersistedEvent);
      }
      this.db.exec('COMMIT');
    } catch (error) {
      this.db.exec('ROLLBACK');
      throw error;
    }
    for (const event of events) this.onEvent(event);
    return events;
  }
  putBot(bot: Bot) {
    this.write(
      bot.archived ? 'bot.archived' : 'bot.upserted',
      bot.archived ? { botId: bot.botId } : bot,
      () =>
        this.db
          .prepare(
            'INSERT INTO bots VALUES(?,?,?) ON CONFLICT(bot_id) DO UPDATE SET handle=excluded.handle,data=excluded.data',
          )
          .run(bot.botId, bot.handle, JSON.stringify(bot)),
    );
  }
  putConversation(conversation: Conversation) {
    this.write('conversation.upserted', conversation, () =>
      this.db
        .prepare(
          'INSERT INTO conversations(conversation_id,kind,bot_id,group_id,data) VALUES(?,?,?,?,?)',
        )
        .run(
          conversation.conversationId,
          conversation.kind,
          conversation.kind === 'dm' ? conversation.botId : null,
          conversation.kind === 'group' ? conversation.groupId : null,
          JSON.stringify(conversation),
        ),
    );
  }
  putGroup(group: Group, conversation?: Conversation) {
    const items: { kind: PersistedEvent['kind']; data: unknown; save: (seq: number) => void }[] = [
      {
        kind: group.archived ? 'group.archived' : 'group.upserted',
        data: group.archived ? { groupId: group.groupId } : group,
        save: () =>
          this.db
            .prepare(
              'INSERT INTO groups VALUES(?,?) ON CONFLICT(group_id) DO UPDATE SET data=excluded.data',
            )
            .run(group.groupId, JSON.stringify(group)),
      },
    ];
    if (conversation)
      items.push({
        kind: 'conversation.upserted',
        data: conversation,
        save: () =>
          this.db
            .prepare(
              'INSERT INTO conversations(conversation_id,kind,bot_id,group_id,data) VALUES(?,?,?,?,?)',
            )
            .run(
              conversation.conversationId,
              conversation.kind,
              conversation.kind === 'dm' ? conversation.botId : null,
              conversation.kind === 'group' ? conversation.groupId : null,
              JSON.stringify(conversation),
            ),
      });
    this.writeBatch(items);
  }
  putMessage(
    message: Message,
    metadata: { clientMsgId?: string; runId?: string; toolCallId?: string } = {},
    run?: RunRecord,
    chain?: GroupChainRecord,
  ) {
    const event = this.write(
      'message.upserted',
      message,
      (seq) => {
        const existing = this.db
          .prepare('SELECT created_seq FROM messages WHERE message_id=?')
          .get(message.messageId);
        message.seq = existing ? Number(existing.created_seq) : seq;
        this.db
          .prepare(
            'INSERT INTO messages VALUES(?,?,?,?,?,?,?) ON CONFLICT(message_id) DO UPDATE SET data=excluded.data',
          )
          .run(
            message.messageId,
            message.conversationId,
            metadata.clientMsgId ?? null,
            metadata.runId ?? null,
            metadata.toolCallId ?? null,
            seq,
            JSON.stringify(message),
          );
      },
      run,
      chain,
    );
    return event.data as Message;
  }
  setting<T>(key: string) {
    const row = this.db.prepare('SELECT value FROM settings WHERE key=?').get(key);
    return row ? (JSON.parse(row.value as string) as T) : undefined;
  }
  setSetting(key: string, value: unknown) {
    this.db
      .prepare(
        'INSERT INTO settings VALUES(?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value',
      )
      .run(key, JSON.stringify(value));
  }
  updateMessage(message: Message, run?: RunRecord, metadata: { toolCallId?: string } = {}) {
    return this.putMessage(message, { runId: run?.runId, ...metadata }, run);
  }
  setMessageRun(messageId: string, runId: string) {
    this.db.prepare('UPDATE messages SET run_id=? WHERE message_id=?').run(runId, messageId);
  }
  saveRun(run: RunRecord) {
    this.db
      .prepare(
        'INSERT INTO runs VALUES(?,?) ON CONFLICT(conversation_id) DO UPDATE SET data=excluded.data',
      )
      .run(run.conversationId, JSON.stringify(run));
  }
  runs() {
    return this.all<RunRecord>('SELECT data FROM runs').filter((r) => r.state !== 'idle');
  }
  groupHistory(conversationId: string) {
    return this.all<GroupChainRecord>(
      'SELECT data FROM group_chains WHERE conversation_id=?',
      conversationId,
    )[0];
  }
  chain(conversationId: string) {
    const chain = this.groupHistory(conversationId);
    return chain?.active ? chain : undefined;
  }
  chains() {
    return this.all<GroupChainRecord>('SELECT data FROM group_chains').filter(
      (chain) => chain.active,
    );
  }
  saveChain(chain: GroupChainRecord) {
    this.db
      .prepare(
        'INSERT INTO group_chains VALUES(?,?) ON CONFLICT(conversation_id) DO UPDATE SET data=excluded.data',
      )
      .run(chain.conversationId, JSON.stringify(chain));
  }
  clearChain(conversationId: string) {
    const chain = this.groupHistory(conversationId);
    if (chain) this.saveChain({ ...chain, active: false, queue: [], currentBotId: undefined });
  }
}
