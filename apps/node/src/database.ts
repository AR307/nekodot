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
  FlowSnapshot,
  FlowChange,
  DotTask,
  Space,
  SpaceRecord,
} from '@nekodot/protocol';

export interface NativeModelOverride {
  model: string;
  provider: string;
}

export interface RunRecord {
  role?: 'coordinator' | 'execution' | 'report' | 'consultation';
  /** The worker's private native question being considered by the main Dot. */
  questionMessageId?: string;
  taskId?: string;
  executionId?: string;
  /** Logical native session scope; never use the private chat for a group run. */
  sessionKey?: string;
  groupChainId?: string;
  groupFollowup?: boolean;
  pendingInput?: string;
  targetTaskId?: string;
  background?: 'cron' | 'webhook';
  routineId?: string;
  runId?: string;
  conversationId: string;
  botId: string;
  groupId?: string;
  requestId?: string;
  sessionId?: string;
  storedSessionId?: string;
  submissionId?: string;
  executionGeneration?: number;
  replayEpoch?: string;
  stopRequested?: boolean;
  lastSeq: number;
  state: 'thinking' | 'tool' | 'waiting_approval' | 'waiting_question' | 'unknown' | 'idle';
  textMessageId?: string;
  /** Stable originating input; queued/native records are persisted under this ID. */
  inputMessageId: string;
  welcome?: true;
  queue?: 'queued' | 'started';
  replacesAdmissionId?: string;
  native?: boolean;
  modelOverride?: NativeModelOverride;
}

export interface HermesSessionRecord {
  ownerConversationId?: string;
  conversationId: string;
  botId: string;
  storedSessionId: string;
  replayEpoch: string;
  lastSequence: number;
}

export interface GroupChainRecord {
  notificationId: string;
  inputMessageId?: string;
  taskId?: string;
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
  commandInput?: string;
  commandModelOverride?: NativeModelOverride;
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
    this.db
      .exec(`CREATE TABLE IF NOT EXISTS spaces(space_id TEXT PRIMARY KEY,bot_id TEXT NOT NULL,data TEXT NOT NULL);
      CREATE TABLE IF NOT EXISTS space_records(space_id TEXT NOT NULL,key TEXT NOT NULL,value TEXT NOT NULL,PRIMARY KEY(space_id,key));
      CREATE TABLE IF NOT EXISTS space_mutations(mutation_id TEXT PRIMARY KEY,space_id TEXT NOT NULL);
      CREATE TABLE IF NOT EXISTS space_publications(submission_id TEXT NOT NULL,space_id TEXT NOT NULL,PRIMARY KEY(submission_id,space_id));`);
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
    if (version < 3) {
      this.db.exec(`BEGIN;
        CREATE TABLE hermes_sessions(conversation_id TEXT PRIMARY KEY,bot_id TEXT NOT NULL,stored_session_id TEXT UNIQUE NOT NULL,replay_epoch TEXT NOT NULL,last_sequence INTEGER NOT NULL);
        PRAGMA user_version=3;
        COMMIT;`);
    }
    if (version < 4) {
      const columns = this.db.prepare('PRAGMA table_info(hermes_sessions)').all();
      if (columns.some((column) => column.name === 'session_id'))
        this.db.exec('ALTER TABLE hermes_sessions RENAME COLUMN session_id TO stored_session_id');
      this.db.exec('PRAGMA user_version=4');
    }
    this.db.exec(`CREATE TABLE IF NOT EXISTS usage_owners(
      profile TEXT NOT NULL,kind TEXT NOT NULL,id TEXT NOT NULL,conversation_id TEXT NOT NULL,
      PRIMARY KEY(profile,kind,id));
    CREATE TABLE IF NOT EXISTS attachments(
      file_id TEXT PRIMARY KEY,bot_id TEXT NOT NULL,message_id TEXT NOT NULL,
      reference TEXT NOT NULL,storage_path TEXT,data TEXT NOT NULL,
      UNIQUE(message_id,reference)
    ); CREATE INDEX IF NOT EXISTS attachments_bot ON attachments(bot_id);`);
    this.db
      .exec(`CREATE TABLE IF NOT EXISTS dot_tasks(task_id TEXT PRIMARY KEY,conversation_id TEXT NOT NULL,data TEXT NOT NULL);
      CREATE INDEX IF NOT EXISTS dot_tasks_conversation ON dot_tasks(conversation_id);
      CREATE TABLE IF NOT EXISTS task_executions(execution_id TEXT PRIMARY KEY,task_id TEXT NOT NULL,data TEXT NOT NULL);`);
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
    return this.all<Conversation>('SELECT data FROM conversations').map((c) => ({
      ...c,
      sessionId: this.hermesSession(c.conversationId)?.storedSessionId,
    }));
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
  /** The newest text or commentary with words in each conversation. */
  latestTexts() {
    const newest = this.db.prepare(
      `SELECT data FROM messages WHERE conversation_id=?
        AND json_extract(data,'$.kind') IN ('text','commentary')
         AND coalesce(json_extract(data,'$.taskRole'),'') <> 'execution'
        AND trim(coalesce(json_extract(data,'$.content.text'),''))<>''
        ORDER BY created_seq DESC LIMIT 1`,
    );
    return this.conversations().flatMap((conversation) => {
      const row = newest.get(conversation.conversationId);
      return row ? [JSON.parse(row.data as string) as Message] : [];
    });
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
          'INSERT INTO conversations(conversation_id,kind,bot_id,group_id,data) VALUES(?,?,?,?,?) ON CONFLICT(conversation_id) DO UPDATE SET data=excluded.data',
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
    const owner =
      run ??
      (metadata.runId ? this.runs().find((item) => item.runId === metadata.runId) : undefined);
    if (owner?.storedSessionId) message.nativeSessionId = owner.storedSessionId;
    if (owner?.groupChainId) message.groupChainId = owner.groupChainId;
    if (owner?.taskId) {
      message.taskId = owner.taskId;
      message.taskRole = owner.role === 'execution' ? 'execution' : 'report';
    }
    if (metadata.clientMsgId) message.clientMsgId = metadata.clientMsgId;
    if (message.kind === 'text' && message.author.type === 'bot' && message.status === 'done') {
      const submission =
        owner?.role === 'report'
          ? owner.executionId
          : (owner?.inputMessageId ??
            (message.content.routine ? 'native:' + message.content.routine.sessionId : undefined));
      if (submission) {
        const spaces = this.db
          .prepare('SELECT space_id FROM space_publications WHERE submission_id=?')
          .all(submission)
          .map((row) => String(row.space_id));
        if (spaces.length) message.content.spaces = spaces;
      }
    }
    const event = this.write(
      'message.upserted',
      message,
      (seq) => {
        const existing = this.db
          .prepare('SELECT created_seq FROM messages WHERE message_id=?')
          .get(message.messageId);
        message.seq = existing ? Number(existing.created_seq) : seq;
        if (message.kind === 'text' && message.author.type === 'user') {
          for (const id of message.content.files ?? [])
            this.db
              .prepare(
                "UPDATE attachments SET message_id=?,data=json_set(data,'$.messageId',?) WHERE file_id=?",
              )
              .run(message.messageId, message.messageId, id);
        }
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
  spaces(): Space[] {
    return this.db
      .prepare('SELECT data FROM spaces ORDER BY rowid DESC')
      .all()
      .map((row) => JSON.parse(String(row.data)) as Space);
  }
  space(id: string): Space | undefined {
    const row = this.db.prepare('SELECT data FROM spaces WHERE space_id=?').get(id);
    return row ? (JSON.parse(String(row.data)) as Space) : undefined;
  }
  putSpace(space: Space) {
    this.write('space.upserted', space, () => {
      this.db
        .prepare(
          'INSERT INTO spaces VALUES(?,?,?) ON CONFLICT(space_id) DO UPDATE SET data=excluded.data',
        )
        .run(space.spaceId, space.botId, JSON.stringify(space));
    });
    return space;
  }
  spaceData(id: string) {
    return {
      records: this.db
        .prepare('SELECT key,value FROM space_records WHERE space_id=? ORDER BY key')
        .all(id)
        .map((row) => ({ key: String(row.key), value: JSON.parse(String(row.value)) })),
      revision: this.setting<number>('space-data:' + id) ?? 0,
    };
  }
  putSpaceRecords(id: string, mutationId: string, records: SpaceRecord[]) {
    if (
      !this.db
        .prepare('SELECT mutation_id FROM space_mutations WHERE mutation_id=? AND space_id=?')
        .get(mutationId, id)
    ) {
      this.write('space.data.changed', { spaceId: id }, (seq) => {
        for (const record of records)
          this.db
            .prepare(
              'INSERT INTO space_records VALUES(?,?,?) ON CONFLICT(space_id,key) DO UPDATE SET value=excluded.value',
            )
            .run(id, record.key, JSON.stringify(record.value));
        this.db.prepare('INSERT INTO space_mutations VALUES(?,?)').run(mutationId, id);
        this.setSetting('space-data:' + id, seq);
      });
    }
    return this.spaceData(id);
  }
  setSetting(key: string, value: unknown) {
    this.db
      .prepare(
        'INSERT INTO settings VALUES(?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value',
      )
      .run(key, JSON.stringify(value));
  }
  saveFlow(flow: FlowSnapshot, steps: FlowSnapshot['steps'], reset = false) {
    const change: FlowChange = { ...flow, steps, reset };
    this.write('flow.changed', change, (seq) => {
      flow.seq = seq;
      change.seq = seq;
      this.setSetting('flow:' + (flow.taskId ?? flow.conversationId), flow);
    });
  }
  updateMessage(message: Message, run?: RunRecord, metadata: { toolCallId?: string } = {}) {
    return this.putMessage(message, { runId: run?.runId, ...metadata }, run);
  }
  setMessageRun(messageId: string, runId: string) {
    this.db.prepare('UPDATE messages SET run_id=? WHERE message_id=?').run(runId, messageId);
  }
  saveRun(run: RunRecord) {
    if (run.runId && run.taskId)
      this.setSetting('usage-task:' + run.botId + ':admission:' + run.runId, run.taskId);
    if (run.role === 'execution' && run.storedSessionId && run.taskId)
      this.setSetting('usage-task-session:' + run.botId + ':' + run.storedSessionId, run.taskId);
    if (run.runId && run.routineId)
      this.setSetting('usage-routine:' + run.botId + ':' + 'admission:' + run.runId, run.routineId);
    if (run.runId)
      this.db
        .prepare('INSERT OR IGNORE INTO usage_owners VALUES(?,?,?,?)')
        .run(run.botId, 'execution', 'admission:' + run.runId, run.conversationId);
    if (run.queue || run.native || run.role) {
      this.setSetting(
        (run.native || run.role ? 'native-admission:' : 'native-queue:') + run.inputMessageId,
        run,
      );
      return;
    }
    this.db
      .prepare(
        'INSERT INTO runs VALUES(?,?) ON CONFLICT(conversation_id) DO UPDATE SET data=excluded.data',
      )
      .run(run.conversationId, JSON.stringify(run));
  }
  hermesSessions(): HermesSessionRecord[] {
    return this.db
      .prepare(
        "SELECT s.*, o.conversation_id owner_id FROM hermes_sessions s LEFT JOIN usage_owners o ON o.profile=s.bot_id AND o.kind='session' AND o.id=s.stored_session_id",
      )
      .all()
      .map((row) => ({
        conversationId: String(row.conversation_id),
        ownerConversationId: String(row.owner_id),
        botId: String(row.bot_id),
        storedSessionId: String(row.stored_session_id),
        replayEpoch: String(row.replay_epoch),
        lastSequence: Number(row.last_sequence),
      }));
  }
  hermesSession(conversationId: string) {
    const row = this.db
      .prepare('SELECT * FROM hermes_sessions WHERE conversation_id=?')
      .get(conversationId);
    return row
      ? ({
          conversationId: String(row.conversation_id),
          botId: String(row.bot_id),
          storedSessionId: String(row.stored_session_id),
          replayEpoch: String(row.replay_epoch),
          lastSequence: Number(row.last_sequence),
        } satisfies HermesSessionRecord)
      : undefined;
  }
  saveHermesSession(session: HermesSessionRecord) {
    this.db
      .prepare('INSERT OR IGNORE INTO usage_owners VALUES(?,?,?,?)')
      .run(
        session.botId,
        'session',
        session.storedSessionId,
        session.ownerConversationId ?? session.conversationId,
      );
    this.db
      .prepare(
        'INSERT INTO hermes_sessions VALUES(?,?,?,?,?) ON CONFLICT(conversation_id) DO UPDATE SET bot_id=excluded.bot_id,stored_session_id=excluded.stored_session_id,replay_epoch=excluded.replay_epoch,last_sequence=excluded.last_sequence',
      )
      .run(
        session.conversationId,
        session.botId,
        session.storedSessionId,
        session.replayEpoch,
        session.lastSequence,
      );
    const conversation = this.conversation(session.conversationId);
    if (conversation && conversation.sessionId !== session.storedSessionId) {
      this.putConversation({ ...conversation, sessionId: session.storedSessionId });
    }
  }
  runs() {
    return [
      ...this.all<RunRecord>('SELECT data FROM runs'),
      ...this.all<RunRecord>(
        "SELECT value AS data FROM settings WHERE key LIKE 'native-queue:%' OR key LIKE 'native-admission:%' ORDER BY rowid",
      ),
    ].filter((r) => r.state !== 'idle');
  }
  tasks(conversationId?: string) {
    return conversationId
      ? this.all<DotTask>(
          'SELECT data FROM dot_tasks WHERE conversation_id=? ORDER BY rowid',
          conversationId,
        )
      : this.all<DotTask>('SELECT data FROM dot_tasks ORDER BY rowid');
  }
  task(taskId: string) {
    return this.all<DotTask>('SELECT data FROM dot_tasks WHERE task_id=?', taskId)[0];
  }
  saveTask(task: DotTask) {
    this.write('task.upserted', task, () => {
      this.db
        .prepare(
          'INSERT INTO dot_tasks VALUES(?,?,?) ON CONFLICT(task_id) DO UPDATE SET data=excluded.data',
        )
        .run(task.taskId, task.conversationId, JSON.stringify(task));
    });
  }
  taskMessages(taskId: string) {
    return this.all<Message>(
      "SELECT data FROM messages WHERE json_extract(data,'$.taskId')=? ORDER BY created_seq",
      taskId,
    );
  }
  groupHistory(conversationId: string) {
    return this.all<GroupChainRecord>('SELECT data FROM group_chains')
      .filter((chain) => chain.conversationId === conversationId)
      .at(-1);
  }
  chain(chainId: string) {
    const chain = this.all<GroupChainRecord>(
      'SELECT data FROM group_chains WHERE conversation_id=?',
      chainId,
    )[0];
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
      .run(chain.notificationId, JSON.stringify(chain));
  }
  clearChain(chainId: string) {
    const chain = this.chain(chainId);
    if (chain) this.saveChain({ ...chain, active: false, queue: [], currentBotId: undefined });
  }
}
