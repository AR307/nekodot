import { randomUUID } from 'node:crypto';
import type { Operation } from '@nekodot/protocol';
import type { NodeDatabase } from './database';
import { NodeFault } from './fault';

export class Operations {
  constructor(private readonly database: NodeDatabase) {
    for (const operation of this.list())
      if (operation.status === 'running')
        this.save({
          ...operation,
          status: 'interrupted',
          detail: 'Node restarted. Refresh to check the actual Hermes state.',
        });
  }
  list(): Operation[] {
    return this.database.db
      .prepare(
        "SELECT value FROM settings WHERE key LIKE 'operation:%' ORDER BY rowid DESC LIMIT 40",
      )
      .all()
      .map((row) => JSON.parse(String(row.value)) as Operation);
  }
  get(id: string) {
    const operation = this.database.setting<Operation>('operation:' + id);
    if (!operation) throw new NodeFault('not_found', 'Operation not found');
    return operation;
  }
  save(operation: Operation) {
    operation.updatedAt = new Date().toISOString();
    this.database.setSetting('operation:' + operation.operationId, operation);
    return operation;
  }
  start(kind: string, botIds: string[], run: (operation: Operation) => Promise<void>) {
    const now = new Date().toISOString();
    const operation: Operation = {
      operationId: randomUUID(),
      kind,
      botIds,
      status: 'running',
      detail: 'Starting Hermes…',
      createdAt: now,
      updatedAt: now,
      results: [],
    };
    this.save(operation);
    void run(operation)
      .then(() => {
        operation.status = operation.results.some((result) => !result.ok) ? 'failed' : 'done';
        this.save(operation);
      })
      .catch((error: unknown) => {
        operation.status = 'failed';
        operation.detail = error instanceof Error ? error.message : 'Hermes operation failed';
        this.save(operation);
      });
    return structuredClone(operation);
  }
}
