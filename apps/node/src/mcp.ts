import type { RpcParams } from '@nekodot/protocol';
import type { BotService } from './bots';
import type { HermesRuntime } from './hermes/runtime';

/** Profile-scoped management only. Reading the center never probes or starts a server. */
export class McpServers {
  constructor(
    readonly bots: BotService,
    readonly hermes: HermesRuntime,
  ) {}

  async list(botId: string) {
    this.bots.get(botId);
    return this.hermes.management.rpc('mcp.servers.list', { profile: botId });
  }

  async add({ botId, name, config, bearerToken }: RpcParams<'mcp.add'>) {
    this.bots.get(botId);
    return this.hermes.management.rpc('mcp.servers.add', {
      profile: botId,
      name,
      config,
      ...(bearerToken ? { bearer_token: bearerToken } : {}),
    });
  }

  async toggle({ botId, name, enabled }: RpcParams<'mcp.toggle'>) {
    this.bots.get(botId);
    return this.hermes.management.request(
      `/api/mcp/servers/${encodeURIComponent(name)}/enabled`,
      botId,
      { method: 'PUT', body: JSON.stringify({ enabled }) },
    );
  }

  async test({ botId, name }: RpcParams<'mcp.test'>) {
    this.bots.get(botId);
    return this.hermes.management.rpc('mcp.servers.test', { profile: botId, name }, 120_000);
  }
}
