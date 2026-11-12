import { Composio } from '@composio/core';
import type { ConnectorPage, ConnectorService } from '@nekodot/protocol';
import type { ConnectorProvider, ProviderConnection, ProviderTool } from './provider';
import { HttpFault } from '../auth';

const options = {
  sandbox: { enable: false, enableProxyExecution: false },
  proxyExecute: { enable: false },
  manageConnections: { enable: false },
  multiAccount: { enable: true, requireExplicitSelection: true },
};

export class ComposioConnectorProvider implements ConnectorProvider {
  readonly id = 'composio';
  private readonly sdk: Composio;
  private readonly services = new Map<string, { expires: number; value: ConnectorService }>();
  private readonly catalogs = new Map<string, { expires: number; value: ConnectorPage }>();
  private readonly sessions = new Map<
    string,
    { expires: number; session: ReturnType<Composio['create']> }
  >();
  constructor(apiKey: string) {
    this.sdk = new Composio({ apiKey, disableVersionCheck: true });
  }
  private session(userId: string) {
    const cached = this.sessions.get(userId);
    if (cached && cached.expires > Date.now()) return cached.session;
    const session = this.sdk.create(userId, options);
    this.sessions.set(userId, { expires: Date.now() + 15 * 60_000, session });
    void session.catch(() => this.sessions.delete(userId));
    return session;
  }
  async service(serviceId: string): Promise<ConnectorService> {
    const cached = this.services.get(serviceId);
    if (cached && cached.expires > Date.now()) return cached.value;
    const [toolkit, configs] = await Promise.all([
      this.sdk.toolkits.get(serviceId),
      this.sdk.authConfigs.list({ toolkit: serviceId, showDisabled: false }),
    ]);
    const authMethods = [
      ...new Set([
        ...(toolkit.composioManagedAuthSchemes ?? []),
        ...configs.items
          .filter((c) => c.status === 'ENABLED' && c.isEnabledForToolRouter !== false)
          .flatMap((c) => (c.authScheme ? [c.authScheme] : [])),
      ]),
    ].filter((mode) => mode !== 'NO_AUTH');
    const value: ConnectorService = {
      serviceId,
      name: toolkit.name,
      icon: toolkit.meta.logo,
      authMethods,
    };
    this.services.set(serviceId, { expires: Date.now() + 10 * 60_000, value });
    return value;
  }
  async catalog(userId: string, query = '', cursor?: string): Promise<ConnectorPage> {
    const key = JSON.stringify([userId, query, cursor]);
    const cached = this.catalogs.get(key);
    if (cached && cached.expires > Date.now()) return cached.value;
    const page = await (
      await this.session(userId)
    ).toolkits({ search: query || undefined, cursor, limit: 20 });
    const services = await Promise.all(
      page.items.filter((item) => !item.isNoAuth).map((item) => this.service(item.slug)),
    );
    const value = {
      services: services.filter((service) => service.authMethods.length > 0),
      cursor: page.cursor,
    };
    this.catalogs.set(key, { expires: Date.now() + 60_000, value });
    return value;
  }
  async connections(userId: string) {
    const connections: ProviderConnection[] = [];
    let cursor: string | undefined;
    do {
      // The provider query binds ownership; retrieve(id) alone does not return an owner.
      const page = await this.sdk.connectedAccounts.list({
        userIds: [userId],
        accountType: 'PRIVATE',
        cursor,
        limit: 100,
      });
      for (const account of page.items) {
        const display = account.state?.val as { displayName?: string } | undefined;
        connections.push({
          reference: account.id,
          serviceId: account.toolkit.slug,
          account: display?.displayName ?? '',
          status: account.isDisabled
            ? 'disconnected'
            : account.status === 'ACTIVE'
              ? 'active'
              : account.status === 'FAILED'
                ? 'failed'
                : account.status === 'EXPIRED'
                  ? 'expired'
                  : ['INACTIVE', 'REVOKED'].includes(account.status)
                    ? 'disconnected'
                    : 'pending',
        });
      }
      cursor = page.nextCursor ?? undefined;
    } while (cursor);
    return connections;
  }
  async authorize(userId: string, serviceId: string, callbackUrl: string, alias: string) {
    if (!(await this.service(serviceId)).authMethods.length)
      throw new HttpFault('unavailable', 'Connector authorization is not configured', 503);
    const request = await (await this.session(userId)).authorize(serviceId, { callbackUrl, alias });
    if (!request.redirectUrl)
      throw new HttpFault('unavailable', 'Authorization URL unavailable', 502);
    return { reference: request.id, url: request.redirectUrl };
  }
  async disconnect(reference: string) {
    await this.sdk.connectedAccounts.delete(reference);
  }
  async search(userId: string, query: string, serviceId?: string) {
    const result = await (
      await this.session(userId)
    ).search({ query, toolkits: serviceId ? [serviceId] : undefined });
    if (!result.success) throw new HttpFault('unavailable', 'Connector tool discovery failed', 502);
    const slugs = [...new Set(result.results.flatMap((item) => item.primaryToolSlugs))].filter(
      (slug) => !slug.startsWith('COMPOSIO_'),
    );
    return Promise.all(
      slugs.map(async (slug): Promise<ProviderTool> => {
        const tool = await this.sdk.tools.getRawComposioToolBySlug(slug);
        if (!tool.toolkit?.slug)
          throw new HttpFault('unavailable', 'Tool service metadata unavailable', 502);
        const tags = new Set(tool.tags);
        return {
          reference: slug,
          serviceId: tool.toolkit.slug,
          name: tool.name,
          description: tool.description ?? '',
          parameters: tool.inputParameters ?? {},
          operation: tags.has('destructiveHint')
            ? 'delete'
            : tags.has('createHint') || tags.has('updateHint')
              ? 'write'
              : tags.has('readOnlyHint')
                ? 'read'
                : 'unknown',
        };
      }),
    );
  }
  async execute(
    userId: string,
    connection: ProviderConnection,
    tool: ProviderTool,
    args: Record<string, unknown>,
  ) {
    // Each execution pins exactly one account. No shared mutable account selection.
    const session = await this.sdk.create(userId, {
      ...options,
      toolkits: [connection.serviceId],
      connectedAccounts: { [connection.serviceId]: [connection.reference] },
    });
    // SDK session.execute explicitly disables retries for side-effecting calls.
    const result = await session.execute(tool.reference, args, { account: connection.reference });
    return {
      status: result.resultType,
      data: result.data,
      ...(result.error ? { error: result.error } : {}),
    };
  }
}
