import { z } from 'zod';
import { rpcErrorSchema } from './errors';

// Hermes MemoryStore's native entry separator, not a Markdown paragraph splitter.
export const USER_MEMORY_SEPARATOR = '\n§\n';
export const userMemoryStateSchema = z.strictObject({
  revision: z.number().int().nonnegative(),
  initialized: z.boolean(),
  content: z.string(),
  imports: z.array(
    z.strictObject({
      id: z.uuid(),
      nodeId: z.string(),
      botId: z.string(),
      name: z.string(),
      content: z.string(),
      reviewed: z.boolean(),
    }),
  ),
  conflicts: z.array(
    z.strictObject({
      id: z.uuid(),
      nodeId: z.string(),
      botId: z.string(),
      name: z.string(),
      base: z.string(),
      current: z.string(),
      incoming: z.string(),
      resolved: z.boolean(),
    }),
  ),
});
export const userMemorySaveSchema = z.strictObject({
  revision: z.number().int().nonnegative(),
  content: z.string(),
  reviewedImports: z.array(z.uuid()),
  reviewedConflicts: z.array(z.uuid()),
});
export const userMemoryRequestSchema = z.discriminatedUnion('action', [
  z.strictObject({
    action: z.literal('sync'),
    updates: z.array(
      z.strictObject({
        botId: z.string(),
        name: z.string(),
        base: z.string().nullable(),
        content: z.string(),
      }),
    ),
  }),
  userMemorySaveSchema.extend({ action: z.literal('save') }),
]);
export const userMemoryResponseSchema = z.discriminatedUnion('ok', [
  z.strictObject({ ok: z.literal(true), result: userMemoryStateSchema }),
  z.strictObject({ ok: z.literal(false), error: rpcErrorSchema }),
]);
export const userMemoryViewSchema = z.strictObject({
  shared: userMemoryStateSchema.nullable(),
  connected: z.boolean(),
  error: z.string(),
});
export type UserMemoryState = z.infer<typeof userMemoryStateSchema>;
export type UserMemoryRequest = z.infer<typeof userMemoryRequestSchema>;
export type UserMemoryView = z.infer<typeof userMemoryViewSchema>;
