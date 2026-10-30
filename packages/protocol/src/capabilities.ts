import { z } from 'zod';
import { botSchema, idSchema, timestampSchema } from './entities';

export const memoryDocumentSchema = z.enum(['SOUL.md', 'MEMORY.md', 'USER.md']);
export const nativeRecordSchema = z.record(z.string(), z.unknown());
export const operationSchema = z.strictObject({
  operationId: z.uuid(),
  kind: z.string(),
  botIds: z.array(botSchema.shape.botId),
  status: z.enum(['running', 'done', 'failed', 'interrupted']),
  detail: z.string(),
  createdAt: timestampSchema,
  updatedAt: timestampSchema,
  results: z.array(
    z.strictObject({
      botId: botSchema.shape.botId,
      ok: z.boolean(),
      detail: z.string(),
      native: nativeRecordSchema.optional(),
    }),
  ),
});
export const extensionSchema = z.strictObject({
  id: idSchema,
  name: z.string(),
  description: z.string(),
  category: z.string(),
  source: z.string(),
  icon: z.string().optional(),
  repository: z.url().optional(),
  identifier: z.string().optional(),
  platforms: z.array(z.string()),
  dependencies: z.array(z.string()),
  desktop: z.boolean(),
  states: z.array(
    z.strictObject({
      botId: botSchema.shape.botId,
      installed: z.boolean(),
      enabled: z.boolean(),
      status: z.string(),
    }),
  ),
  native: nativeRecordSchema,
});
export const attachmentSchema = z.strictObject({
  fileId: z.uuid(),
  botId: botSchema.shape.botId,
  conversationId: idSchema,
  messageId: idSchema,
  name: z.string(),
  mime: z.string(),
  size: z.number().nonnegative(),
  sentAt: timestampSchema,
  available: z.boolean(),
});
export type MemoryDocument = z.infer<typeof memoryDocumentSchema>;
export type Operation = z.infer<typeof operationSchema>;
export type Extension = z.infer<typeof extensionSchema>;
export type Attachment = z.infer<typeof attachmentSchema>;
