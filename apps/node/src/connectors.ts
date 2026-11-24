import { readFile } from 'node:fs/promises';
import { join } from 'node:path';
import { z } from 'zod';
import {
  connectorRequestSchema,
  connectorApprovalSchema,
  type ConnectorAuthorization,
  type ConnectorRequest,
} from '@nekodot/protocol';
import type { NodeDatabase } from './database';
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
  /** The native session that asked; the work continues there after the user decides. */
  sessionId: string;
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
  onContinue!: (
    request: { botId: string; conversationId: string; sessionId: string },
    submissionId: string,
    text: string,
  ) => Promise<void>;
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
  private persist(row: PendingConnection) {
    this.db.db
      .prepare(
        'INSERT INTO connector_requests VALUES(?,?) ON CONFLICT(id) DO UPDATE SET data=excluded.data',
      )
      .run(row.requestId, JSON.stringify(row));
    this.db.putMessage({
      messageId: 'connector:' + row.requestId,
      conversationId: row.conversationId,
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
  /** Stopping a conversation's work also drops the account connections it was waiting for. */
  cancel(conversationId: string) {
    for (const row of this.all().filter(
      (r) => r.conversationId === conversationId && !r.continued && !r.stopped,
    )) {
      row.stopped = true;
      this.persist(row);
    }
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
    if (this.db.bot(row.botId)?.archived) {
      row.stopped = true;
      this.persist(row);
      return;
    }
    // The turn that asked finishes first; the Dot then continues in the same session.
    const running = this.db
      .runs()
      .some(
        (r) =>
          r.botId === row.botId &&
          (r.sessionId === row.sessionId || r.storedSessionId === row.sessionId) &&
          r.state !== 'idle',
      );
    if (running) return;
    const text =
      row.authorization.status === 'active'
        ? `The account connection you requested is now authorized. Service: ${row.authorization.service.name}. Connection reference: ${row.authorization.connectionId}. Continue only the remaining work of the user's request in this conversation; do not repeat completed operations. Authorization to connect is not approval to write or send: use the existing native approval for each tool as required. This is not a new request from the user.`
        : `The account authorization for ${row.authorization.service.name} ended with status ${row.authorization.status}. Do not execute any connector operation, retry authorization, or switch to browser access. Tell the user plainly what is blocked. This is not a new request from the user.`;
    this.continuing.add(row.requestId);
    try {
      await this.onContinue(row, 'connector:' + row.requestId, text);
      row.continued = true;
      this.persist(row);
    } finally {
      this.continuing.delete(row.requestId);
    }
  }
  /** A turn ended: an authorization it was waiting for may now continue. */
  settled() {
    if (!this.all().some((r) => !r.stopped && !r.continued)) return;
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
      if (!run) throw new NodeFault('conflict', 'Connection must be requested from a running turn');
      const authorization = (await this.request(input)) as ConnectorAuthorization;
      const row: PendingConnection = {
        requestId,
        botId: p.botId,
        sessionId: run.storedSessionId ?? p.sessionId,
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
          'An authorization card is already in this chat. Tell the user briefly which service you need and why, then end this turn; do not expose internal IDs or paste an OAuth URL. The work resumes in this conversation after the user decides. Do not poll, repeat completed work, or use another access method.',
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
