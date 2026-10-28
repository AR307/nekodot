import { DatabaseSync } from 'node:sqlite';
import { mkdtemp } from 'node:fs/promises';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { expect, it } from 'vitest';
import type { Bot, Conversation, Message } from '@nekodot/protocol';
import { NodeDatabase } from './database';
import { GroupService } from './groups';

it('opens a Phase 1 database without changing DM history and atomically creates a group conversation', async () => {
  const directory = await mkdtemp(join(tmpdir(), 'nekodot-phase1-upgrade-'));
  const db = new DatabaseSync(join(directory, 'node.db'));
  db.exec(`CREATE TABLE bots(bot_id TEXT PRIMARY KEY,handle TEXT UNIQUE NOT NULL,data TEXT NOT NULL);
    CREATE TABLE conversations(conversation_id TEXT PRIMARY KEY,bot_id TEXT UNIQUE NOT NULL,data TEXT NOT NULL);
    CREATE TABLE messages(message_id TEXT PRIMARY KEY,conversation_id TEXT NOT NULL,client_msg_id TEXT UNIQUE,run_id TEXT,tool_call_id TEXT,created_seq INTEGER NOT NULL,data TEXT NOT NULL);
    CREATE TABLE events(seq INTEGER PRIMARY KEY AUTOINCREMENT,kind TEXT NOT NULL,data TEXT NOT NULL);
    CREATE TABLE settings(key TEXT PRIMARY KEY,value TEXT NOT NULL);
    CREATE TABLE runs(conversation_id TEXT PRIMARY KEY,data TEXT NOT NULL);
    PRAGMA user_version=1;`);
  const bot: Bot = {
    botId: 'nk-aaaaaa',
    handle: 'researcher',
    displayName: 'Researcher',
    avatar: { shape: 'dot', color: '#E8603C' },
    role: 'Research',
    model: 'test-model',
    archived: false,
    createdAt: '2026-10-27T00:00:00.000Z',
  };
  const conversation: Conversation = {
    conversationId: 'old-dm',
    kind: 'dm',
    botId: bot.botId,
    createdAt: bot.createdAt,
  };
  const message: Message = {
    messageId: 'saved-reply',
    conversationId: 'old-dm',
    seq: 12,
    kind: 'text',
    author: { type: 'bot', id: bot.botId },
    status: 'done',
    content: { text: 'Preserved private chat' },
    createdAt: bot.createdAt,
  };
  db.prepare('INSERT INTO bots VALUES(?,?,?)').run(bot.botId, bot.handle, JSON.stringify(bot));
  db.prepare('INSERT INTO conversations VALUES(?,?,?)').run(
    conversation.conversationId,
    bot.botId,
    JSON.stringify(conversation),
  );
  db.prepare('INSERT INTO messages VALUES(?,?,?,?,?,?,?)').run(
    message.messageId,
    conversation.conversationId,
    null,
    'old-run',
    null,
    12,
    JSON.stringify(message),
  );
  db.prepare('INSERT INTO events VALUES(?,?,?)').run(
    12,
    'message.upserted',
    JSON.stringify(message),
  );
  db.close();
  const upgraded = new NodeDatabase(directory);
  try {
    expect(upgraded.conversation('old-dm')).toEqual(conversation);
    expect(upgraded.messages('old-dm')).toEqual([message]);
    expect(upgraded.messageRun('saved-reply')).toBe('old-run');
    upgraded.putBot({ ...bot, botId: 'nk-bbbbbb', handle: 'writer' });
    let groupAndConversationVisibleTogether = false;
    upgraded.onEvent = (event) => {
      if (event.kind === 'group.upserted')
        groupAndConversationVisibleTogether = upgraded
          .conversations()
          .some((item) => item.kind === 'group' && item.groupId === event.data.groupId);
    };
    new GroupService(upgraded).create({
      name: 'Research room',
      botIds: [bot.botId, 'nk-bbbbbb'],
      leadBotId: bot.botId,
    });
    expect(groupAndConversationVisibleTogether).toBe(true);
    expect(upgraded.messages('old-dm')).toEqual([message]);
    expect(upgraded.db.prepare('PRAGMA user_version').get()?.user_version).toBe(2);
  } finally {
    upgraded.db.close();
  }
});
