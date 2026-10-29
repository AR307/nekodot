import type { TaskNotification } from '@nekodot/protocol';
import type { NodeDatabase } from './database';

export class Notifications {
  onSend: (value: TaskNotification) => void = () => {};
  constructor(private database: NodeDatabase) {
    database.db.exec(
      'CREATE TABLE IF NOT EXISTS notification_outbox(id TEXT PRIMARY KEY,data TEXT NOT NULL)',
    );
  }
  send(value: TaskNotification) {
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
