import { z } from 'zod';
import type { FastifyInstance, FastifyRequest } from 'fastify';
import {
  emptyUsage,
  totalUsage,
  type UsageRecord,
  type UsageSummary,
  type UsageAmounts,
  type UsageDayRow,
  type UsageBreakdown,
} from '@nekodot/protocol';
import type { NodeRow, RelayDatabase } from './database';
import { HttpFault } from './auth';

const day = z.string().regex(/^\d{4}-\d{2}-\d{2}$/);
const querySchema = z.strictObject({
  from: day.nullable(),
  to: day,
  timezone: z.string(),
  nodeId: z.string().optional(),
});
const amounts = (): UsageAmounts => ({ tokens: emptyUsage(), total: 0, unavailable: 0 });
function add(target: UsageAmounts, row: UsageRecord) {
  if (!row.tokens) {
    target.unavailable++;
    return;
  }
  for (const key of ['input', 'output', 'cacheRead', 'cacheWrite'] as const)
    target.tokens[key] += row.tokens[key];
  target.total += totalUsage(row.tokens);
}

export class AccountUsage {
  constructor(private database: RelayDatabase) {
    database.db.exec(`CREATE TABLE IF NOT EXISTS usage_calls(
      user_id TEXT NOT NULL,node_id TEXT NOT NULL,profile TEXT NOT NULL,id TEXT NOT NULL,at TEXT NOT NULL,data TEXT NOT NULL,
      PRIMARY KEY(user_id,node_id,profile,id));
      CREATE INDEX IF NOT EXISTS usage_account_time ON usage_calls(user_id,at);
      CREATE TABLE IF NOT EXISTS usage_sync(node_id TEXT PRIMARY KEY,synced_at TEXT NOT NULL);`);
  }
  ingest(node: NodeRow, records: UsageRecord[]) {
    if (!this.database.owns(node.user_id, node.node_id))
      throw new HttpFault('forbidden', 'Node unpaired', 403);
    const insert = this.database.db.prepare(
      'INSERT OR IGNORE INTO usage_calls VALUES(?,?,?,?,?,?)',
    );
    this.database.db.exec('BEGIN');
    try {
      for (const row of records)
        insert.run(node.user_id, node.node_id, row.profile, row.id, row.at, JSON.stringify(row));
      this.database.db
        .prepare(
          'INSERT INTO usage_sync VALUES(?,?) ON CONFLICT(node_id) DO UPDATE SET synced_at=excluded.synced_at',
        )
        .run(node.node_id, new Date().toISOString());
      this.database.db.exec('COMMIT');
    } catch (error) {
      this.database.db.exec('ROLLBACK');
      throw error;
    }
  }

  query(
    userId: string,
    input: z.infer<typeof querySchema>,
    online: (id: string) => boolean,
  ): UsageSummary {
    if (input.nodeId && !this.database.owns(userId, input.nodeId))
      throw new HttpFault('not_found', 'Node not found', 404);
    let dates: Intl.DateTimeFormat;
    try {
      dates = new Intl.DateTimeFormat('en-CA', {
        timeZone: input.timezone,
        year: 'numeric',
        month: '2-digit',
        day: '2-digit',
      });
    } catch {
      throw new HttpFault('invalid_params', 'Invalid timezone');
    }
    if (input.from && input.from > input.to)
      throw new HttpFault('invalid_params', 'Invalid date range');
    const nodes = this.database
      .nodes(userId)
      .filter((n) => !input.nodeId || input.nodeId === n.node_id);
    const byNode = new Map(nodes.map((n) => [n.node_id, n]));
    const rows = this.database.db
      .prepare('SELECT node_id,data FROM usage_calls WHERE user_id=? ORDER BY at')
      .all(userId);
    const result: UsageSummary = {
      from: input.from ?? input.to,
      to: input.to,
      totals: amounts(),
      days: [],
      conversations: [],
      routines: [],
      rows: [],
      nodes: nodes.map((n) => ({
        nodeId: n.node_id,
        name: n.name,
        online: online(n.node_id),
        syncedAt:
          (this.database.db
            .prepare('SELECT synced_at FROM usage_sync WHERE node_id=?')
            .get(n.node_id)?.synced_at as string | undefined) ?? null,
      })),
    };
    const daily = new Map<string, UsageAmounts>();
    const entities = new Map<string, UsageBreakdown>();
    const exportRows = new Map<string, UsageDayRow>();
    for (const stored of rows) {
      const node = byNode.get(String(stored.node_id));
      if (!node) continue;
      const row = JSON.parse(String(stored.data)) as UsageRecord;
      const date = dates.format(new Date(row.at));
      if (date > input.to || (input.from && date < input.from)) continue;
      if (date < result.from) result.from = date;
      add(result.totals, row);
      const d = daily.get(date) ?? amounts();
      add(d, row);
      daily.set(date, d);
      const key = JSON.stringify([node.node_id, row.entity.kind, row.entity.id]);
      const entity = entities.get(key) ?? {
        ...amounts(),
        nodeId: node.node_id,
        nodeName: node.name,
        entity: row.entity,
        percent: 0,
      };
      entity.entity = row.entity;
      add(entity, row);
      entities.set(key, entity);
      const exportKey = date + key;
      const e = exportRows.get(exportKey) ?? {
        ...amounts(),
        date,
        nodeId: node.node_id,
        nodeName: node.name,
        entity: row.entity,
      };
      add(e, row);
      exportRows.set(exportKey, e);
    }
    result.days = [...daily]
      .map(([date, value]) => ({ date, ...value }))
      .sort((a, b) => a.date.localeCompare(b.date));
    result.rows = [...exportRows.values()].sort((a, b) => a.date.localeCompare(b.date));
    result.conversations = [...entities.values()].filter((r) => r.entity.kind !== 'routine');
    result.routines = [...entities.values()].filter((r) => r.entity.kind === 'routine');
    for (const group of [result.conversations, result.routines]) {
      const total = group.reduce((sum, r) => sum + r.total, 0);
      group.sort((a, b) => b.total - a.total);
      for (const row of group) row.percent = total ? (row.total / total) * 100 : 0;
    }
    return result;
  }

  register(
    app: FastifyInstance,
    authenticate: (request: FastifyRequest) => Promise<{ user_id: string }>,
    routing: { online(id: string): boolean; refreshUsage(id: string): Promise<boolean> },
  ) {
    app.post('/api/usage/query', async (request) => {
      const user = await authenticate(request);
      const parsed = querySchema.safeParse(request.body);
      if (!parsed.success) throw new HttpFault('invalid_params', 'Invalid usage query');
      return this.query(user.user_id, parsed.data, routing.online);
    });
    app.post('/api/usage/refresh', async (request) => {
      const user = await authenticate(request);
      const parsed = z.strictObject({ nodeId: z.string().optional() }).safeParse(request.body);
      if (!parsed.success) throw new HttpFault('invalid_params', 'Invalid usage refresh');
      if (parsed.data.nodeId && !this.database.owns(user.user_id, parsed.data.nodeId))
        throw new HttpFault('not_found', 'Node not found', 404);
      const nodes = this.database
        .nodes(user.user_id)
        .filter((n) => !parsed.data.nodeId || n.node_id === parsed.data.nodeId);
      return {
        nodes: await Promise.all(
          nodes.map(async (n) => ({
            nodeId: n.node_id,
            synced: routing.online(n.node_id) && (await routing.refreshUsage(n.node_id)),
          })),
        ),
      };
    });
  }
}
