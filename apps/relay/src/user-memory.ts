import { randomUUID } from 'node:crypto';
import { diff3Merge, diffPatch, patch } from 'node-diff3';
import {
  USER_MEMORY_SEPARATOR,
  type UserMemoryRequest,
  type UserMemoryState,
} from '@nekodot/protocol';
import type { RelayDatabase, NodeRow } from './database';
import { HttpFault } from './auth';

const entries = (text: string) =>
  text
    .split(USER_MEMORY_SEPARATOR)
    .map((s) => s.trim())
    .filter(Boolean);
const document = (items: string[]) => [...new Set(items)].join(USER_MEMORY_SEPARATOR);

/** Account USER.md only. SOUL, task memory and chat never enter this store. */
export class AccountUserMemory {
  constructor(readonly database: RelayDatabase) {
    database.db.exec(
      'CREATE TABLE IF NOT EXISTS account_user_memory(user_id TEXT PRIMARY KEY,data TEXT NOT NULL)',
    );
  }
  get(userId: string): UserMemoryState {
    const row = this.database.db
      .prepare('SELECT data FROM account_user_memory WHERE user_id=?')
      .get(userId);
    return row
      ? (JSON.parse(row.data as string) as UserMemoryState)
      : {
          revision: 0,
          initialized: false,
          content: '',
          imports: [],
          conflicts: [],
        };
  }
  apply(node: NodeRow, request: UserMemoryRequest) {
    const state = this.get(node.user_id);
    const before = JSON.stringify(state);
    if (request.action === 'save') {
      if (request.revision !== state.revision)
        throw new HttpFault(
          'conflict',
          'User memory changed on another computer. Refresh before confirming.',
          409,
        );
      state.content = document(entries(request.content));
      state.initialized = true;
      for (const item of state.imports)
        if (request.reviewedImports.includes(item.id)) item.reviewed = true;
      for (const item of state.conflicts)
        if (request.reviewedConflicts.includes(item.id)) item.resolved = true;
    } else {
      for (const update of request.updates) {
        if (update.base === null || !state.initialized) {
          if (
            update.content.trim() &&
            !(state.initialized && update.content === state.content) &&
            !state.imports.some(
              (item) =>
                item.nodeId === node.node_id &&
                item.botId === update.botId &&
                item.content === update.content,
            )
          )
            state.imports.push({
              id: randomUUID(),
              nodeId: node.node_id,
              botId: update.botId,
              name: update.name,
              content: update.content,
              reviewed: false,
            });
          continue;
        }
        const merged: string[] = [];
        for (const part of diff3Merge(
          entries(update.content),
          entries(update.base),
          entries(state.content),
        )) {
          if (part.ok) merged.push(...part.ok);
          else if (part.conflict) {
            const conflict = part.conflict;
            // Concurrent additions do not overwrite an existing entry.
            if (!conflict.o.length) merged.push(...conflict.b, ...conflict.a);
            else {
              // diff3 groups adjacent edits into one conflict. Native entry updates and
              // an append beside that entry are independent, not competing replacements.
              const incoming = diffPatch(conflict.o, conflict.a);
              const current = diffPatch(conflict.o, conflict.b);
              const overlap = incoming.some((a) =>
                current.some((b) => {
                  const left = a.buffer1,
                    right = b.buffer1;
                  if (!left.length)
                    return left.offset > right.offset && left.offset < right.offset + right.length;
                  if (!right.length)
                    return right.offset > left.offset && right.offset < left.offset + left.length;
                  return (
                    left.offset < right.offset + right.length &&
                    right.offset < left.offset + left.length
                  );
                }),
              );
              if (!overlap) {
                merged.push(
                  ...patch(
                    conflict.o,
                    [...current, ...incoming].sort(
                      (a, b) =>
                        a.buffer1.offset - b.buffer1.offset || a.buffer1.length - b.buffer1.length,
                    ),
                  ),
                );
                continue;
              }
              merged.push(...conflict.b);
              const detail = {
                base: document(conflict.o),
                current: document(conflict.b),
                incoming: document(conflict.a),
              };
              if (
                !state.conflicts.some(
                  (item) =>
                    !item.resolved &&
                    item.nodeId === node.node_id &&
                    item.botId === update.botId &&
                    item.base === detail.base &&
                    item.current === detail.current &&
                    item.incoming === detail.incoming,
                )
              )
                state.conflicts.push({
                  id: randomUUID(),
                  nodeId: node.node_id,
                  botId: update.botId,
                  name: update.name,
                  ...detail,
                  resolved: false,
                });
            }
          }
        }
        state.content = document(merged);
      }
      if (!state.initialized && !state.imports.some((item) => !item.reviewed))
        state.initialized = true;
    }
    const changed = JSON.stringify(state) !== before;
    if (changed) {
      state.revision++;
      this.database.db
        .prepare(
          'INSERT INTO account_user_memory VALUES(?,?) ON CONFLICT(user_id) DO UPDATE SET data=excluded.data',
        )
        .run(node.user_id, JSON.stringify(state));
    }
    return { state, changed };
  }
}
