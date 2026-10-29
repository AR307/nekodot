import { z } from 'zod';
export const transferRequestSchema = z.discriminatedUnion('action', [
  z.strictObject({
    action: z.literal('read'),
    fileId: z.uuid(),
    offset: z.number().int().nonnegative(),
  }),
  z.strictObject({
    action: z.literal('write'),
    importId: z.uuid(),
    path: z.string().min(1),
    offset: z.number().int().nonnegative(),
    data: z.string(),
  }),
]);
export const transferResponseSchema = z.discriminatedUnion('ok', [
  z.strictObject({
    ok: z.literal(true),
    data: z.string().optional(),
    done: z.boolean().optional(),
    name: z.string().optional(),
    mime: z.string().optional(),
    size: z.number().optional(),
  }),
  z.strictObject({ ok: z.literal(false), error: z.string() }),
]);
export type TransferRequest = z.infer<typeof transferRequestSchema>;
export type TransferResponse = z.infer<typeof transferResponseSchema>;
export const transferChunkBytes = 256 * 1024;
