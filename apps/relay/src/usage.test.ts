import { mkdtemp } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { expect, it } from 'vitest';
import type { UsageRecord } from '@nekodot/protocol';
import { RelayDatabase } from './database';
import { AccountUsage } from './usage';

it('keeps offline account usage, separates group/background shares, and buckets actual calls across DST', async () => {
  const db = new RelayDatabase(await mkdtemp(join(tmpdir(), 'nekodot-usage-')));
  try {
    for (const [id, user] of [
      ['a', 'user'],
      ['b', 'user'],
      ['c', 'other'],
    ])
      db.db
        .prepare('INSERT INTO nodes VALUES(?,?,?,?,?,?)')
        .run(id!, user!, 'Computer ' + id, 'win32', id!, 0);
    const usage = new AccountUsage(db);
    const node = db.nodes('user')[0]!;
    const row = (
      id: string,
      kind: 'bot' | 'group' | 'routine',
      at: string,
      value: number,
    ): UsageRecord => ({
      id,
      profile: 'nk-aaaaaa',
      sessionId: 'same-native-session',
      executionId: id,
      at,
      tokens: { input: value, output: 10, cacheRead: 20, cacheWrite: 30 },
      entity: {
        id: kind,
        kind,
        name: kind,
        ownerName: 'Dot',
        group: kind === 'group',
        avatars: [{ shape: 'dot', color: '#347BDD' }],
      },
    });
    const rows = [
      row('dm', 'bot', '2026-11-01T05:30:00.000Z', 40),
      row('group', 'group', '2026-11-01T06:30:00.000Z', 140),
      row('cron', 'routine', '2026-11-02T04:30:00.000Z', 240),
    ];
    usage.ingest(node, rows);
    usage.ingest(node, rows); // An ACK lost during reconnect must not double consumption.
    usage.ingest(db.nodes('user')[1]!, [row('second', 'bot', '2026-11-02T06:00:00.000Z', 40)]);
    const query = { from: '2026-11-01', to: '2026-11-01', timezone: 'America/New_York' };
    const result = usage.query('user', query, () => false);
    expect(result.totals.total).toBe(600);
    expect(result.days).toHaveLength(1);
    expect(result.conversations.map((r) => r.total)).toEqual([200, 100]);
    expect(result.conversations.reduce((sum, r) => sum + r.percent, 0)).toBeCloseTo(100);
    expect(result.routines.map((r) => r.percent)).toEqual([100]);
    expect(result.rows.reduce((sum, r) => sum + r.total, 0)).toBe(600);
    expect(result.nodes.every((n) => !n.online)).toBe(true);
    expect(usage.query('other', query, () => false).totals.total).toBe(0);
    expect(() => usage.query('other', { ...query, nodeId: 'a' }, () => true)).toThrow(
      'Node not found',
    );
    expect(
      usage.query('user', { ...query, to: '2026-11-02', nodeId: 'b' }, () => true).totals.total,
    ).toBe(100);
    usage.ingest(node, [{ ...rows[0]!, id: 'unreported', tokens: null }]);
    expect(usage.query('user', query, () => true).totals).toMatchObject({
      total: 600,
      unavailable: 1,
    });
  } finally {
    db.db.close();
  }
});
