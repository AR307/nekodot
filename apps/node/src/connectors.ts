import { readFile } from 'node:fs/promises';
import { join } from 'node:path';
import { z } from 'zod';
import {
  connectorRequestSchema,
  connectorApprovalSchema,
  type ConnectorAuthorization,
  type ConnectorRequest,
} from '@nekodot/protocol';
import type { NodeDatabase, RunRecord } from './database';
import type { HermesRuntime } from './hermes/runtime';
import { NodeFault } from './fault';

/** Decode only our native plugin's approval payload, never a model's prose. */
export function connectorApprovalContent(command?: string, description?: string) {
  return command?.startsWith('<nekodot_connector>')
    ? { connector: connectorApprovalSchema.parse(JSON.parse(description!)) }
    : {};
}

interface PendingConnection {
  requestId: string;
  botId: string;
  conversationId: string;
  sessionId: string;
  taskId: string;
  executionId: string;
  authorization: ConnectorAuthorization;
  createdAt: string;
  stopped?: boolean;
  continued?: boolean;
}

/** Profile-bound tools and their originating chat, not a second task engine. */
export class NodeConnectors {
  request: (request: ConnectorRequest) => Promise<unknown> = async () => {
    throw new NodeFault('unavailable', 'Relay is disconnected');
  };
  onContinue!: (taskId: string, submissionId: string, text: string) => Promise<void>;
  onRequest?: (request: PendingConnection) => void;
  private refreshing?: Promise<void>;
  private continuing = new Set<string>();
  constructor(
    private db: NodeDatabase,
    private hermes: HermesRuntime,
  ) {
    db.db.exec(
      'CREATE TABLE IF NOT EXISTS connector_requests(id TEXT PRIMARY KEY,data TEXT NOT NULL)',
    );
  }
  private all(): PendingConnection[] {
    return this.db.db
      .prepare('SELECT data FROM connector_requests')
      .all()
      .map((r) => JSON.parse(String(r.data)));
  }
  pending(taskId: string) {
    return this.all().some((r) => r.taskId === taskId && !r.stopped && !r.continued);
  }
  private persist(row: PendingConnection) {
    this.db.db
      .prepare(
        'INSERT INTO connector_requests VALUES(?,?) ON CONFLICT(id) DO UPDATE SET data=excluded.data',
      )
      .run(row.requestId, JSON.stringify(row));
    this.db.putMessage({
      messageId: 'connector:' + row.requestId,
      conversationId: row.conversationId,
      taskId: row.taskId,
      taskRole: 'execution',
      seq: this.db.head(),
      author: { type: 'bot', id: row.botId },
      kind: 'connector',
      status:
        row.stopped || row.authorization.status === 'cancelled'
          ? 'cancelled'
          : row.authorization.status === 'pending'
            ? 'streaming'
            : row.authorization.status === 'active'
              ? 'done'
              : 'failed',
      createdAt: row.createdAt,
      content: { authorization: row.authorization, stopped: row.stopped ?? false },
    });
  }
  cancelTask(taskId: string) {
    let cancelled = false;
    for (const row of this.all().filter((r) => r.taskId === taskId && !r.continued && !r.stopped)) {
      row.stopped = true;
      this.persist(row);
      cancelled = true;
    }
    return cancelled;
  }
  async changed(authorization?: ConnectorAuthorization) {
    if (!authorization) return;
    for (const row of this.all().filter(
      (r) => r.authorization.authorizationId === authorization.authorizationId,
    )) {
      row.authorization = authorization;
      this.persist(row);
      await this.continue(row);
    }
  }
  private async continue(row: PendingConnection) {
    if (
      row.stopped ||
      row.continued ||
      row.authorization.status === 'pending' ||
      this.continuing.has(row.requestId)
    )
      return;
    const task = this.db.task(row.taskId);
    if (task?.executionId === 'connector:' + row.requestId) {
      row.continued = true;
      this.persist(row);
      return;
    }
    if (
      !task ||
      task.state === 'cancelled' ||
      task.state === 'failed' ||
      task.executionId !== row.executionId ||
      this.db.bot(row.botId)?.archived
    ) {
      row.stopped = true;
      this.persist(row);
      return;
    }
    // Let the requesting execution finish and its main-Dot report settle first.
    const running = this.db
      .runs()
      .some(
        (r) =>
          r.taskId === row.taskId &&
          (r.role === 'execution' || r.role === 'report') &&
          r.state !== 'idle',
      );
    if (running) return;
    const text =
      row.authorization.status === 'active'
        ? `The account connection requested for this same task is now authorized. Service: ${row.authorization.service.name}. Connection reference: ${row.authorization.connectionId}. Continue only the remaining work in this session; do not repeat completed operations. Authorization to connect is not approval to write or send: use the existing native approval for each tool as required. Report findings to the main Dot, which will summarize them naturally.`
        : `The account authorization for ${row.authorization.service.name} ended with status ${row.authorization.status}. Do not execute any connector operation, retry authorization, or switch to browser access. Report this blocker to the main Dot for a natural explanation. This is not a new task.`;
    this.continuing.add(row.requestId);
    try {
      await this.onContinue(row.taskId, 'connector:' + row.requestId, text);
      row.continued = true;
      this.persist(row);
    } finally {
      this.continuing.delete(row.requestId);
    }
  }
  settled(run: RunRecord) {
    if (run.role !== 'execution' && run.role !== 'report') return;
    return this.recover();
  }
  recover() {
    if (this.refreshing) return this.refreshing;
    this.refreshing = this.refresh().finally(() => {
      this.refreshing = undefined;
    });
    return this.refreshing;
  }
  private async refresh() {
    for (const row of this.all().filter((r) => !r.stopped && !r.continued)) {
      row.authorization = (await this.request({
        operation: 'authorization',
        authorizationId: row.authorization.authorizationId,
      })) as ConnectorAuthorization;
      this.persist(row);
      await this.continue(row);
    }
  }
  async local(value: unknown) {
    const p = z
      .object({
        action: z.literal('connector'),
        botId: z.string(),
        sessionId: z.string().min(1),
        admissionId: z.string().min(1),
        callId: z.string().min(1),
        token: z.string(),
        request: z.record(z.string(), z.unknown()),
      })
      .parse(value);
    const bot = this.db.bot(p.botId);
    if (!bot || bot.archived) throw new NodeFault('not_found', 'Bot is unavailable');
    const token = await readFile(
      join(this.hermes.profileHome(p.botId), 'plugins', 'nekodot-secrets', 'bridge.token'),
      'utf8',
    );
    if (p.token !== token.trim())
      throw new NodeFault('forbidden', 'Profile does not own this request');
    const requestId = `${p.botId}:${p.sessionId}:${p.admissionId}:${p.callId}`;
    const input = connectorRequestSchema.parse({
      ...p.request,
      ...(p.request.operation === 'authorize' ? { requestId } : {}),
    });
    if (input.operation === 'authorize') {
      const old = this.all().find((r) => r.requestId === requestId);
      if (old) return { authorization: old.authorization, awaitingUser: true };
      const run = this.db
        .runs()
        .find(
          (r) =>
            r.botId === p.botId &&
            (r.sessionId === p.sessionId || r.storedSessionId === p.sessionId) &&
            r.runId === p.admissionId,
        );
      if (!run?.taskId || !run.executionId)
        throw new NodeFault(
          'conflict',
          'Connection must be requested from the existing execution task',
        );
      const authorization = (await this.request(input)) as ConnectorAuthorization;
      const row: PendingConnection = {
        requestId,
        botId: p.botId,
        sessionId: p.sessionId,
        taskId: run.taskId,
        executionId: run.executionId,
        conversationId: run.conversationId,
        authorization,
        createdAt: new Date().toISOString(),
      };
      this.persist(row);
      this.onRequest?.(row);
      return {
        authorization,
        awaitingUser: true,
        instruction:
          'An authorization card is already in the original chat. Finish this turn and report the service needed to the main Dot. The main Dot explains the need naturally; do not expose internal IDs or paste an OAuth URL. The original task resumes after authorization. Do not poll, repeat completed work, or use another access method.',
      };
    }
    if (input.operation === 'execute') {
      const receipt = 'connector-call:' + requestId;
      const previous = this.db.setting<{ result: unknown }>(receipt);
      if (previous) return previous.result;
      this.db.setSetting(receipt, {
        result: {
          status: 'unknown',
          error:
            'This invocation was already attempted. Its outcome is not confirmed. Do not automatically repeat a write or send.',
        },
      });
      const result = await this.request(input);
      this.db.setSetting(receipt, { result });
      return result;
    }
    return this.request(input);
  }
}
