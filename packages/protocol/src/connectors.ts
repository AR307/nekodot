import { z } from 'zod';

export interface ConnectorService {
  serviceId: string;
  name: string;
  icon?: string;
  authMethods: string[];
}
export type ConnectorStatus = 'pending' | 'active' | 'failed' | 'expired' | 'disconnected';
export interface ConnectorConnection {
  connectionId: string;
  service: ConnectorService;
  account: string;
  label: string;
  status: ConnectorStatus;
  updatedAt: string;
}
export type ConnectorAuthorizationStatus = ConnectorStatus | 'cancelled';
export interface ConnectorAuthorization {
  authorizationId: string;
  connectionId: string;
  service: ConnectorService;
  status: ConnectorAuthorizationStatus;
  url: string;
  expiresAt: string;
}
export interface ConnectorTool {
  toolId: string;
  serviceId: string;
  name: string;
  description: string;
  parameters: Record<string, unknown>;
  operation: 'read' | 'write' | 'delete' | 'unknown';
}
export interface ConnectorResult {
  status: 'completed' | 'failed' | 'blocked';
  data: Record<string, unknown>;
  error?: string;
}
export interface ConnectorPage {
  services: ConnectorService[];
  cursor?: string;
}
export const connectorApprovalSchema = z.object({
  title: z.string(),
  service: z.object({ serviceId: z.string(), name: z.string(), icon: z.string().optional() }),
  account: z.string(),
  arguments: z.record(z.string(), z.unknown()),
});
const ref = z.string().min(1);
export const connectorRequestSchema = z.discriminatedUnion('operation', [
  z.strictObject({ operation: z.literal('list'), serviceId: ref.optional() }),
  z.strictObject({
    operation: z.literal('catalog'),
    query: z.string().optional(),
    cursor: ref.optional(),
  }),
  z.strictObject({ operation: z.literal('authorize'), serviceId: ref, requestId: ref }),
  z.strictObject({ operation: z.literal('authorization'), authorizationId: ref }),
  z.strictObject({ operation: z.literal('cancel'), authorizationId: ref }),
  z.strictObject({ operation: z.literal('search'), query: ref, serviceId: ref.optional() }),
  z.strictObject({ operation: z.literal('describe'), toolId: ref, connectionId: ref.optional() }),
  z.strictObject({
    operation: z.literal('execute'),
    toolId: ref,
    connectionId: ref,
    arguments: z.record(z.string(), z.unknown()),
  }),
]);
export type ConnectorRequest = z.infer<typeof connectorRequestSchema>;
