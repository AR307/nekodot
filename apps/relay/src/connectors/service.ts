import { randomUUID } from 'node:crypto';
import type { FastifyInstance, FastifyRequest } from 'fastify';
import { z } from 'zod';
import {
  type ConnectorRequest,
  type ConnectorAuthorization,
  type ConnectorConnection,
  type ConnectorTool,
} from '@nekodot/protocol';
import type { RelayDatabase } from '../database';
import { HttpFault } from '../auth';
import type { ConnectorProvider, ProviderConnection, ProviderTool } from './provider';

interface StoredConnection extends ConnectorConnection {
  providerId: string;
  reference: string;
}
interface StoredAuthorization extends ConnectorAuthorization {
  providerId: string;
  reference: string;
  userId: string;
  callbackId: string;
}
interface StoredTool extends ConnectorTool {
  providerId: string;
  reference: string;
}

export function connectorFault(error: unknown): HttpFault {
  if (error instanceof HttpFault) return error;
  if (error instanceof z.ZodError)
    return new HttpFault('invalid_params', 'Invalid connector request');
  // Do not expose SDK request headers, credentials or exception dumps.
  const status =
    (error as { status?: number; cause?: { status?: number } })?.status ??
    (error as { cause?: { status?: number } })?.cause?.status;
  return new HttpFault(
    status === 429
      ? 'connector_rate_limited'
      : status === 402
        ? 'connector_quota'
        : status === 401 || status === 403
          ? 'connector_authorization'
          : 'connector_unavailable',
    'Connector request failed',
    status === 429 ? 429 : 502,
  );
}

export class AccountConnectors {
  onChanged: (userId: string, authorization?: ConnectorAuthorization) => void = () => {};
  constructor(
    private database: RelayDatabase,
    private provider: ConnectorProvider | undefined,
    private publicUrl: string,
  ) {
    database.db.exec(`
      CREATE TABLE IF NOT EXISTS connector_connections(id TEXT PRIMARY KEY,user_id TEXT NOT NULL,data TEXT NOT NULL);
      CREATE TABLE IF NOT EXISTS connector_authorizations(id TEXT PRIMARY KEY,user_id TEXT NOT NULL,request_key TEXT UNIQUE,callback_id TEXT UNIQUE NOT NULL,data TEXT NOT NULL);
      CREATE TABLE IF NOT EXISTS connector_tools(id TEXT PRIMARY KEY,provider_id TEXT NOT NULL,reference TEXT NOT NULL,data TEXT NOT NULL,UNIQUE(provider_id,reference));
    `);
  }
  private active(providerId?: string) {
    if (!this.provider || (providerId && this.provider.id !== providerId))
      throw new HttpFault('connector_unavailable', 'Connectors are not configured', 503);
    return this.provider;
  }
  private rows(userId: string) {
    return this.database.db
      .prepare('SELECT data FROM connector_connections WHERE user_id=?')
      .all(userId)
      .map((r) => JSON.parse(String(r.data)) as StoredConnection);
  }
  private connection(userId: string, id: string) {
    const connection = this.rows(userId).find((row) => row.connectionId === id);
    if (!connection) throw new HttpFault('not_found', 'Connection not found', 404);
    return connection;
  }
  private view({ providerId, reference, ...connection }: StoredConnection): ConnectorConnection {
    void providerId;
    void reference;
    return connection;
  }
  private saveConnection(userId: string, connection: StoredConnection) {
    this.database.db
      .prepare(
        'INSERT INTO connector_connections VALUES(?,?,?) ON CONFLICT(id) DO UPDATE SET data=excluded.data',
      )
      .run(connection.connectionId, userId, JSON.stringify(connection));
  }
  private auth(userId: string, id: string): StoredAuthorization {
    const row = this.database.db
      .prepare('SELECT data FROM connector_authorizations WHERE id=? AND user_id=?')
      .get(id, userId);
    if (!row) throw new HttpFault('not_found', 'Authorization not found', 404);
    return JSON.parse(String(row.data));
  }
  private authView({
    providerId,
    reference,
    userId,
    callbackId,
    ...authorization
  }: StoredAuthorization): ConnectorAuthorization {
    void providerId;
    void reference;
    void userId;
    void callbackId;
    return authorization;
  }
  private saveAuth(authorization: StoredAuthorization) {
    this.database.db
      .prepare('UPDATE connector_authorizations SET data=? WHERE id=?')
      .run(JSON.stringify(authorization), authorization.authorizationId);
    this.onChanged(authorization.userId, this.authView(authorization));
  }
  async list(userId: string, refresh = false) {
    if (refresh) {
      const provider = this.active();
      const remote = await provider.connections(userId);
      for (const row of this.rows(userId).filter(
        (r) => r.providerId === provider.id && r.status !== 'disconnected',
      )) {
        const match = remote.find(
          (r) => r.reference === row.reference && r.serviceId === row.service.serviceId,
        );
        row.status = match?.status ?? 'disconnected';
        if (match?.account) row.account = match.account;
        row.updatedAt = new Date().toISOString();
        this.saveConnection(userId, row);
      }
      this.onChanged(userId);
    }
    const authorizations = this.database.db
      .prepare(
        "SELECT data FROM connector_authorizations WHERE user_id=? AND json_extract(data,'$.status')='pending'",
      )
      .all(userId)
      .map((r) => this.authView(JSON.parse(String(r.data)) as StoredAuthorization));
    return {
      connections: this.rows(userId)
        .filter((r) => r.status !== 'disconnected')
        .map((r) => this.view(r)),
      authorizations,
      configured: Boolean(this.provider),
    };
  }
  async authorize(userId: string, serviceId: string, requestKey?: string, reconnectId?: string) {
    if (requestKey) {
      const row = this.database.db
        .prepare('SELECT data FROM connector_authorizations WHERE user_id=? AND request_key=?')
        .get(userId, requestKey);
      if (row) return this.authView(JSON.parse(String(row.data)) as StoredAuthorization);
    }
    const provider = this.active();
    const service = await provider.service(serviceId);
    const previous = reconnectId ? this.connection(userId, reconnectId) : undefined;
    if (previous) await this.disconnect(userId, previous.connectionId);
    const authorizationId = randomUUID(),
      connectionId = reconnectId ?? randomUUID(),
      callbackId = randomUUID();
    const callback = new URL('/api/connectors/callback', this.publicUrl);
    callback.searchParams.set('state', callbackId);
    const result = await provider.authorize(userId, serviceId, callback.toString(), connectionId);
    const authorization: StoredAuthorization = {
      authorizationId,
      connectionId,
      service,
      providerId: provider.id,
      reference: result.reference,
      userId,
      callbackId,
      status: 'pending',
      url: result.url,
      expiresAt: new Date(Date.now() + 30 * 60_000).toISOString(),
    };
    const connection: StoredConnection = {
      connectionId,
      service,
      providerId: provider.id,
      reference: result.reference,
      account: '',
      label: previous?.label ?? '',
      status: 'pending',
      updatedAt: new Date().toISOString(),
    };
    this.saveConnection(userId, connection);
    this.database.db
      .prepare('INSERT INTO connector_authorizations VALUES(?,?,?,?,?)')
      .run(authorizationId, userId, requestKey ?? null, callbackId, JSON.stringify(authorization));
    this.onChanged(userId, this.authView(authorization));
    return this.authView(authorization);
  }
  async authorization(userId: string, id: string) {
    const auth = this.auth(userId, id);
    if (auth.status !== 'pending') return this.authView(auth);
    const matches = await this.active(auth.providerId).connections(userId);
    const remote = matches.find(
      (r) => r.reference === auth.reference && r.serviceId === auth.service.serviceId,
    );
    const state = remote?.status ?? 'pending';
    auth.status =
      state === 'pending' && Date.parse(auth.expiresAt) <= Date.now() ? 'expired' : state;
    if (auth.status !== 'pending') {
      const row = this.connection(userId, auth.connectionId);
      row.status = auth.status;
      row.account = remote?.account ?? row.account;
      row.updatedAt = new Date().toISOString();
      this.saveConnection(userId, row);
      this.saveAuth(auth);
    }
    return this.authView(auth);
  }
  async cancel(userId: string, id: string) {
    const auth = this.auth(userId, id);
    if (auth.status === 'pending') {
      auth.status = 'cancelled';
      this.saveAuth(auth);
      await this.disconnect(userId, auth.connectionId);
    }
    return this.authView(auth);
  }
  async disconnect(userId: string, id: string) {
    const connection = this.connection(userId, id);
    // Deny subsequent calls immediately, even if revocation cannot reach the provider.
    connection.status = 'disconnected';
    this.saveConnection(userId, connection);
    this.onChanged(userId);
    await this.active(connection.providerId).disconnect(connection.reference);
    return {};
  }
  label(userId: string, id: string, label: string) {
    const connection = this.connection(userId, id);
    connection.label = label;
    this.saveConnection(userId, connection);
    this.onChanged(userId);
    return this.view(connection);
  }
  private tool(id: string): StoredTool {
    const row = this.database.db.prepare('SELECT data FROM connector_tools WHERE id=?').get(id);
    if (!row) throw new HttpFault('not_found', 'Discover the tool before execution', 404);
    return JSON.parse(String(row.data));
  }
  async request(userId: string, request: ConnectorRequest, nodeId: string): Promise<unknown> {
    const provider = this.active();
    switch (request.operation) {
      case 'list':
        return {
          connections: (await this.list(userId, true)).connections.filter(
            (r) => !request.serviceId || r.service.serviceId === request.serviceId,
          ),
        };
      case 'catalog':
        return provider.catalog(userId, request.query, request.cursor);
      case 'authorize':
        return this.authorize(userId, request.serviceId, nodeId + ':' + request.requestId);
      case 'authorization':
        return this.authorization(userId, request.authorizationId);
      case 'cancel':
        return this.cancel(userId, request.authorizationId);
      case 'describe': {
        const { providerId, reference, ...tool } = this.tool(request.toolId);
        this.active(providerId);
        void reference;
        return tool;
      }
      case 'search': {
        const found = await provider.search(userId, request.query, request.serviceId);
        return {
          tools: found.map(({ reference, ...metadata }) => {
            const old = this.database.db
              .prepare('SELECT id FROM connector_tools WHERE provider_id=? AND reference=?')
              .get(provider.id, reference);
            const toolId = old ? String(old.id) : randomUUID();
            const tool = { toolId, ...metadata };
            this.database.db
              .prepare(
                'INSERT INTO connector_tools VALUES(?,?,?,?) ON CONFLICT(id) DO UPDATE SET data=excluded.data',
              )
              .run(
                toolId,
                provider.id,
                reference,
                JSON.stringify({ ...tool, reference, providerId: provider.id }),
              );
            return tool;
          }),
        };
      }
      case 'execute': {
        const connection = this.connection(userId, request.connectionId);
        const tool = this.tool(request.toolId);
        if (connection.status !== 'active')
          throw new HttpFault('connector_authorization', 'Connection is not active', 409);
        if (
          tool.providerId !== connection.providerId ||
          tool.serviceId !== connection.service.serviceId
        )
          throw new HttpFault('invalid_params', 'Tool does not belong to the selected service');
        const current = (await this.active(connection.providerId).connections(userId)).find(
          (r) => r.reference === connection.reference && r.serviceId === tool.serviceId,
        );
        if (!current || current.status !== 'active') {
          connection.status = current?.status ?? 'expired';
          this.saveConnection(userId, connection);
          this.onChanged(userId);
          throw new HttpFault('connector_authorization', 'Connection requires authorization', 409);
        }
        return provider.execute(
          userId,
          current satisfies ProviderConnection,
          tool satisfies ProviderTool,
          request.arguments,
        );
      }
    }
  }
  register(
    app: FastifyInstance,
    authenticate: (request: FastifyRequest) => Promise<{ user_id: string }>,
  ) {
    // One boundary for validation and redacted provider errors; no vendor JSON leaves it.
    const route = (
      method: 'GET' | 'POST' | 'PUT' | 'DELETE',
      url: string,
      handler: (userId: string, request: FastifyRequest) => unknown,
    ) =>
      app.route({
        method,
        url: '/api/connectors' + url,
        handler: async (request) => {
          const user = await authenticate(request);
          try {
            return await handler(user.user_id, request);
          } catch (error) {
            throw connectorFault(error);
          }
        },
      });
    const id = (request: FastifyRequest) =>
      z.object({ id: z.string().uuid() }).parse(request.params).id;
    route('POST', '/catalog', (user, request) => {
      const p = z
        .strictObject({ query: z.string().optional(), cursor: z.string().optional() })
        .parse(request.body ?? {});
      return this.active().catalog(user, p.query, p.cursor);
    });
    route('GET', '/connections', (user) => this.list(user));
    route('POST', '/refresh', async (user) => {
      for (const r of this.database.db
        .prepare(
          "SELECT id FROM connector_authorizations WHERE user_id=? AND json_extract(data,'$.status')='pending'",
        )
        .all(user))
        await this.authorization(user, String(r.id));
      return this.list(user, true);
    });
    route('POST', '/authorizations', (user, request) =>
      this.authorize(
        user,
        z.strictObject({ serviceId: z.string().min(1) }).parse(request.body).serviceId,
      ),
    );
    route('GET', '/authorizations/:id', (user, request) => this.authorization(user, id(request)));
    route('POST', '/connections/:id/authorize', (user, request) => {
      const connection = this.connection(user, id(request));
      return this.authorize(user, connection.service.serviceId, undefined, connection.connectionId);
    });
    route('POST', '/authorizations/:id/cancel', (user, request) => this.cancel(user, id(request)));
    route('PUT', '/connections/:id', (user, request) =>
      this.label(
        user,
        id(request),
        z.strictObject({ label: z.string().trim().max(120) }).parse(request.body).label,
      ),
    );
    route('DELETE', '/connections/:id', (user, request) => this.disconnect(user, id(request)));
    app.get('/api/connectors/callback', async (request, reply) => {
      const query = z.object({ state: z.string().uuid() }).safeParse(request.query);
      if (!query.success) throw new HttpFault('invalid_params', 'Unknown authorization', 400);
      const row = this.database.db
        .prepare('SELECT id,user_id FROM connector_authorizations WHERE callback_id=?')
        .get(query.data.state);
      if (!row) throw new HttpFault('not_found', 'Authorization not found', 404);
      try {
        await this.authorization(String(row.user_id), String(row.id));
      } catch (error) {
        throw connectorFault(error);
      }
      // No callback query value is treated as proof of connection or identity.
      return reply
        .header('Cache-Control', 'no-store')
        .header('Content-Security-Policy', "default-src 'none'; style-src 'unsafe-inline'")
        .type('text/html')
        .send(
          '<!doctype html><meta name="viewport" content="width=device-width"><title>nekodot</title><body style="font:16px system-ui;padding:32px">返回 nekodot · Return to nekodot</body>',
        );
    });
  }
}
