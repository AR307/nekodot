import type {
  ConnectorPage,
  ConnectorService,
  ConnectorStatus,
  ConnectorTool,
  ConnectorResult,
} from '@nekodot/protocol';

/** Only this boundary knows third-party connection and tool references. */
export interface ProviderConnection {
  reference: string;
  serviceId: string;
  account: string;
  status: ConnectorStatus;
}
export interface ProviderTool extends Omit<ConnectorTool, 'toolId'> {
  reference: string;
}
export interface ConnectorProvider {
  readonly id: string;
  catalog(userId: string, query?: string, cursor?: string): Promise<ConnectorPage>;
  service(serviceId: string): Promise<ConnectorService>;
  connections(userId: string): Promise<ProviderConnection[]>;
  authorize(
    userId: string,
    serviceId: string,
    callbackUrl: string,
    alias: string,
  ): Promise<{ reference: string; url: string }>;
  disconnect(reference: string): Promise<void>;
  search(userId: string, query: string, serviceId?: string): Promise<ProviderTool[]>;
  execute(
    userId: string,
    connection: ProviderConnection,
    tool: ProviderTool,
    args: Record<string, unknown>,
  ): Promise<ConnectorResult>;
}
