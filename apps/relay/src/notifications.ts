import { cert, initializeApp, deleteApp } from 'firebase-admin/app';
import { getMessaging } from 'firebase-admin/messaging';
import { randomUUID } from 'node:crypto';
import type { FastifyInstance, FastifyRequest } from 'fastify';
import { deviceSchema, type TaskNotification } from '@nekodot/protocol';
import type { RelayDatabase } from './database';
import { HttpFault } from './auth';

export function registerNotifications(
  app: FastifyInstance,
  database: RelayDatabase,
  authenticate: (request: FastifyRequest) => Promise<{ user_id: string; session_id?: string }>,
  credentialsFile?: string,
) {
  database.db.exec(`
    CREATE TABLE IF NOT EXISTS devices(device_id TEXT PRIMARY KEY,user_id TEXT NOT NULL,token TEXT NOT NULL UNIQUE);
    CREATE TABLE IF NOT EXISTS notification_delivery(node_id TEXT NOT NULL,event_id TEXT NOT NULL,PRIMARY KEY(node_id,event_id));
  `);
  const firebase = credentialsFile
    ? initializeApp({ credential: cert(credentialsFile) }, `nekodot-${randomUUID()}`)
    : undefined;
  app.get('/api/notifications/status', async (request) => {
    await authenticate(request);
    return {
      available: !!firebase,
      reason: firebase ? undefined : 'Firebase is not configured on this Relay',
    };
  });
  app.post('/api/devices', async (request) => {
    const user = await authenticate(request);
    const parsed = deviceSchema.safeParse(request.body);
    if (!parsed.success) throw new HttpFault('invalid_params', 'Invalid notification device');
    const { deviceId, token } = parsed.data;
    database.db.prepare('DELETE FROM devices WHERE token=?').run(token);
    database.db
      .prepare(
        'INSERT INTO devices VALUES(?,?,?) ON CONFLICT(device_id) DO UPDATE SET user_id=excluded.user_id,token=excluded.token',
      )
      .run(deviceId, user.user_id, token);
    if (user.session_id)
      database.db
        .prepare(
          'INSERT INTO device_sessions VALUES(?,?) ON CONFLICT(device_id) DO UPDATE SET session_id=excluded.session_id',
        )
        .run(deviceId, user.session_id);
    return { registered: true, available: !!firebase };
  });
  app.delete<{ Params: { id: string } }>('/api/devices/:id', async (request) => {
    const user = await authenticate(request);
    database.db
      .prepare('DELETE FROM devices WHERE device_id=? AND user_id=?')
      .run(request.params.id, user.user_id);
    return {};
  });
  app.addHook('onClose', async () => {
    if (firebase) await deleteApp(firebase);
  });
  return async (userId: string, nodeId: string, signal: TaskNotification) => {
    const inserted = database.db
      .prepare('INSERT OR IGNORE INTO notification_delivery VALUES(?,?)')
      .run(nodeId, signal.notificationId);
    if (!inserted.changes) return false;
    if (!firebase) return true;
    const devices = database.db
      .prepare('SELECT device_id,token FROM devices WHERE user_id=?')
      .all(userId) as { device_id: string; token: string }[];
    if (!devices.length) return true;
    const body = {
      approval: 'A task needs your approval.',
      completed: 'Your task has finished.',
      failed: 'A task needs your attention.',
    }[signal.kind];
    try {
      const result = await getMessaging(firebase).sendEach(
        devices.map((device) => ({
          token: device.token,
          notification: { title: 'nekodot', body },
          data: { ...signal, nodeId },
          android: {
            priority: 'high' as const,
            notification: { channelId: 'nekodot_tasks', tag: signal.notificationId },
          },
        })),
      );
      result.responses.forEach((response, index) => {
        if (response.error?.code === 'messaging/registration-token-not-registered')
          database.db
            .prepare('DELETE FROM devices WHERE device_id=?')
            .run(devices[index]!.device_id);
      });
      if (result.failureCount)
        app.log.warn(
          { service: 'push', failures: result.failureCount },
          'Some notifications were not delivered',
        );
    } catch {
      app.log.warn({ service: 'push' }, 'Firebase delivery failed; no chat content was logged');
    }
    return true;
  };
}
