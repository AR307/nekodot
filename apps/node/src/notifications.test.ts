import { mkdtemp } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { randomUUID } from 'node:crypto';
import { expect, it } from 'vitest';
import { NodeDatabase } from './database';
import { Notifications } from './notifications';
import type { TaskNotification } from '@nekodot/protocol';

it('names private/group notifications and previews only final bot text while persisting delivery on the Node', async () => {
  const database = new NodeDatabase(await mkdtemp(join(tmpdir(), 'nekodot-preview-')));
  try {
    const botId = 'nk-abcdef';
    const conversationId = randomUUID();
    database.putBot({
      botId,
      displayName: 'Native Bot',
      handle: 'native-bot',
      avatar: { shape: 'dot', color: 'coral' },
      role: 'Test',
      model: 'test',
      archived: false,
      createdAt: new Date().toISOString(),
    });
    database.putConversation({
      conversationId,
      kind: 'dm',
      botId,
      createdAt: new Date().toISOString(),
    });
    database.putMessage({
      messageId: randomUUID(),
      conversationId,
      author: { type: 'bot', id: botId },
      kind: 'text',
      status: 'done',
      createdAt: new Date().toISOString(),
      seq: 0,
      content: { text: '**已完成**：中文文件已保存。[查看](https://example.test)' },
    });
    database.putMessage({
      messageId: randomUUID(),
      conversationId,
      author: { type: 'bot', id: botId },
      kind: 'commentary',
      status: 'done',
      createdAt: new Date().toISOString(),
      seq: 0,
      content: { text: 'This commentary must not become the completion preview' },
    });
    const notices = new Notifications(database);
    const sent: TaskNotification[] = [];
    notices.onSend = (value) => sent.push(value);
    notices.send({ notificationId: 'run:one', conversationId, kind: 'completed' });
    expect(sent[0]).toMatchObject({
      displayName: 'Native Bot',
      preview: '已完成：中文文件已保存。查看',
    });
    const groupId = randomUUID();
    database.putGroup(
      {
        groupId,
        name: 'Acceptance Group',
        botIds: [botId, 'nk-ghijkl'],
        leadBotId: botId,
        archived: false,
        createdAt: new Date().toISOString(),
      },
      { conversationId: randomUUID(), kind: 'group', groupId, createdAt: new Date().toISOString() },
    );
    const groupConversation = database
      .conversations()
      .find((c) => c.kind === 'group' && c.groupId === groupId)!;
    notices.send({
      notificationId: 'approval:one',
      conversationId: groupConversation.conversationId,
      kind: 'approval',
    });
    expect(sent[1]).toMatchObject({ displayName: 'Acceptance Group', kind: 'approval' });
    notices.send({ notificationId: 'question:one', conversationId, kind: 'question' });
    expect(sent[2]?.preview).toContain('回答');
    notices.flush();
    expect(sent).toHaveLength(6);
  } finally {
    database.db.close();
  }
});
