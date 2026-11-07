import { mkdtemp } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { expect, it } from 'vitest';
import { NodeDatabase } from './database';
import { Operations } from './operations';

it('finds a delivered command after it leaves the recent operations list', async () => {
  const db = new NodeDatabase(await mkdtemp(join(tmpdir(), 'nekodot-offline-operations-')));
  try {
    const operations = new Operations(db);
    for (let i = 0; i < 45; i++)
      operations.save({
        operationId: `operation-${i}`,
        kind: `command:submission-${i}`,
        botIds: ['bot'],
        status: 'done',
        detail: 'done',
        createdAt: '2026-11-07T00:00:00Z',
        updatedAt: '2026-11-07T00:00:00Z',
        results: [],
      });
    expect(operations.list()).toHaveLength(40);
    expect(operations.byKind('command:submission-0')?.operationId).toBe('operation-0');
    expect(new Operations(db).byKind('command:submission-0')?.status).toBe('done');
  } finally {
    db.db.close();
  }
});
