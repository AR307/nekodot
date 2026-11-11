import { z } from 'zod';

export const spaceOriginSchema = z
  .string()
  .url()
  .refine((value) => {
    const u = new URL(value);
    return (
      u.protocol === 'https:' &&
      u.origin === value &&
      !u.username &&
      !u.password &&
      !u.hostname.includes(':') &&
      !/^[\d.]+$/.test(u.hostname) &&
      !/(^|\.)(localhost|local|internal|invalid)$/.test(u.hostname)
    );
  }, 'Use an HTTPS website origin, not a local address or path');

export const spaceSchema = z.strictObject({
  spaceId: z.uuid(),
  botId: z.string(),
  conversationId: z.string(),
  name: z.string().trim().min(1),
  version: z.number().int().nonnegative(),
  fileId: z.uuid().optional(),
  origins: z.array(spaceOriginSchema),
  allowedOrigins: z.array(spaceOriginSchema),
  archived: z.boolean(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export const spaceRecordSchema = z.strictObject({
  key: z.string().min(1).max(256),
  value: z.json(),
});
export const spaceDataSchema = z.strictObject({
  records: z.array(spaceRecordSchema),
  revision: z.number().int().nonnegative(),
});
export type Space = z.infer<typeof spaceSchema>;
export type SpaceRecord = z.infer<typeof spaceRecordSchema>;
