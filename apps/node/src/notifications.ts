import type { TaskNotification } from '@nekodot/protocol';
import type { NodeDatabase } from './database';

export class Notifications {
  onSend: (value: TaskNotification) => void = () => {};
  constructor(private database: NodeDatabase) {
    database.db.exec(
      'CREATE TABLE IF NOT EXISTS notification_outbox(id TEXT PRIMARY KEY,data TEXT NOT NULL)',
    );
  }
  send(signal: Omit<TaskNotification, 'displayName' | 'preview'>) {
    const conversation = this.database.conversation(signal.conversationId);
    const name =
      conversation?.kind === 'group'
        ? this.database.group(conversation.groupId)?.name
        : conversation?.kind === 'dm'
          ? this.database.bot(conversation.botId)?.displayName
          : undefined;
    const final = this.database
      .messages(signal.conversationId)
      .findLast(
        (message) =>
          message.author.type === 'bot' && message.kind === 'text' && message.status === 'done',
      );
    const plain =
      signal.kind === 'completed' && final?.kind === 'text'
        ? final.content.text
            .replace(/```[^\n]*\n?|```/g, '')
            .replace(/!?\[([^\]]*)\]\([^)]*\)/g, '$1')
            .replace(/<[^>]*>/g, '')
            .replace(/(^|\n)\s{0,3}#{1,6}\s+|[*_`]/g, '$1')
            .trim()
        : {
            approval: '需要你审批 / Approval needed',
            question: '需要你的回答 / Your answer is needed',
            failed: '任务失败，请打开查看 / Task failed. Open to review.',
            completed: '任务已完成 / Task completed',
          }[signal.kind];
    const value: TaskNotification = {
      ...signal,
      displayName: name ?? 'nekodot',
      preview: plain.length > 800 ? plain.slice(0, 800) + '…' : plain,
    };
    this.database.db
      .prepare('INSERT OR IGNORE INTO notification_outbox VALUES(?,?)')
      .run(value.notificationId, JSON.stringify(value));
    this.onSend(value);
  }
  flush() {
    for (const row of this.database.db.prepare('SELECT data FROM notification_outbox').all())
      this.onSend(JSON.parse(String(row.data)) as TaskNotification);
  }
  acknowledge(id: string) {
    this.database.db.prepare('DELETE FROM notification_outbox WHERE id=?').run(id);
  }
}
