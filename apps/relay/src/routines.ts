import { createHash, randomUUID, timingSafeEqual } from 'node:crypto';
import { z } from 'zod';
import type { FastifyInstance } from 'fastify';
import type { RoutineRoute, RoutineDelivery, RoutineReceipt } from '@nekodot/protocol';
import type { RelayDatabase, NodeRow } from './database';
import { HttpFault } from './auth';

interface RouteRow {
  routine_id: string;
  node_id: string;
  bot_id: string;
  digest: string;
  enabled: number;
}
export class RoutineIngress {
  constructor(private database: RelayDatabase) {
    database.db.exec(`CREATE TABLE IF NOT EXISTS routine_routes(
      routine_id TEXT PRIMARY KEY,node_id TEXT NOT NULL,bot_id TEXT NOT NULL,digest TEXT NOT NULL,enabled INTEGER NOT NULL);`);
  }
  publish(node: NodeRow, routes: RoutineRoute[]) {
    if (!this.database.owns(node.user_id, node.node_id))
      throw new HttpFault('forbidden', 'Node is unpaired', 403);
    for (const route of routes) {
      const owner = this.database.db
        .prepare('SELECT node_id FROM routine_routes WHERE routine_id=?')
        .get(route.routineId);
      if (owner && owner.node_id !== node.node_id)
        throw new HttpFault('forbidden', 'Routine belongs to another node', 403);
    }
    this.database.db.exec('BEGIN');
    try {
      this.database.db
        .prepare('UPDATE routine_routes SET enabled=0 WHERE node_id=?')
        .run(node.node_id);
      const save = this.database.db.prepare(`INSERT INTO routine_routes VALUES(?,?,?,?,?)
        ON CONFLICT(routine_id) DO UPDATE SET bot_id=excluded.bot_id,digest=excluded.digest,enabled=excluded.enabled`);
      for (const route of routes)
        save.run(route.routineId, node.node_id, route.botId, route.digest, Number(route.enabled));
      this.database.db.exec('COMMIT');
    } catch (error) {
      this.database.db.exec('ROLLBACK');
      throw error;
    }
  }
  register(
    app: FastifyInstance,
    deliver: (nodeId: string, payload: RoutineDelivery) => Promise<RoutineReceipt>,
  ) {
    app.post('/hooks/:routineId', async (request, reply) => {
      const params = z.object({ routineId: z.uuid() }).safeParse(request.params);
      if (!params.success) throw new HttpFault('invalid_params', 'Invalid routine ID');
      const { routineId } = params.data;
      const token = /^Bearer (\S+)$/.exec(request.headers.authorization ?? '')?.[1];
      const row = this.database.db
        .prepare('SELECT * FROM routine_routes WHERE routine_id=?')
        .get(routineId) as unknown as RouteRow | undefined;
      const digest = createHash('sha256')
        .update(token ?? '')
        .digest();
      if (!row || !token || !timingSafeEqual(digest, Buffer.from(row.digest, 'hex')))
        throw new HttpFault('unauthorized', 'Invalid webhook credential', 401);
      const owner = this.database.db
        .prepare('SELECT user_id FROM nodes WHERE node_id=? AND revoked=0')
        .get(row.node_id);
      if (!owner || !row.enabled) throw new HttpFault('forbidden', 'Webhook is disabled', 403);
      const payload = z.record(z.string(), z.json()).safeParse(request.body);
      if (!payload.success)
        throw new HttpFault('invalid_params', 'Webhook body must be a JSON object');
      const requestId = z
        .string()
        .min(1)
        .max(240)
        .safeParse(request.headers['x-request-id'] ?? randomUUID());
      if (!requestId.success) throw new HttpFault('invalid_params', 'Invalid X-Request-ID');
      // The body is transient: neither the request nor the receipt is stored in Relay.
      const receipt = await deliver(row.node_id, {
        routineId,
        digest: row.digest,
        requestId: requestId.data,
        body: JSON.stringify(payload.data),
      });
      return reply.code(receipt.status).header('Cache-Control', 'no-store').send(receipt.body);
    });
  }
}
