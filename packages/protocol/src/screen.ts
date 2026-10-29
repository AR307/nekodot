import { z } from 'zod';
import { botSchema, idSchema } from './entities';

export const screenStatusSchema = z.strictObject({
  botId: botSchema.shape.botId,
  available: z.boolean(),
  installed: z.boolean(),
  running: z.boolean(),
  geometry: z.string(),
  missing: z.array(z.string()),
  holder: z.enum(['agent', 'human']),
  controllerSessionId: z.uuid().optional(),
  installCommand: z.string().optional(),
  blocker: z.string().optional(),
});
export const tunnelRequestSchema = z.strictObject({
  nodeId: idSchema,
  botId: botSchema.shape.botId,
  kind: z.literal('vnc'),
  sessionId: z.uuid().optional(),
});
export const tunnelTicketSchema = z.strictObject({
  sessionId: z.uuid(),
  ticket: z.string().min(1),
  expiresAt: z.iso.datetime(),
});
export const tunnelOpenSchema = z.strictObject({
  tunnelId: z.uuid(),
  sessionId: z.uuid(),
  botId: botSchema.shape.botId,
});
export const tunnelNodeHelloSchema = z.strictObject({
  tunnelId: z.uuid(),
  nodeToken: z.string().min(1),
});
export type ScreenStatus = z.infer<typeof screenStatusSchema>;
export type TunnelRequest = z.infer<typeof tunnelRequestSchema>;
export type TunnelTicket = z.infer<typeof tunnelTicketSchema>;
export type TunnelOpen = z.infer<typeof tunnelOpenSchema>;
