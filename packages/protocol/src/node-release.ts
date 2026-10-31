import { z } from 'zod';

export const nodeVersionSchema = z.string().regex(/^\d{14}$/);
export const nodeReleaseSchema = z.strictObject({
  version: nodeVersionSchema,
  sha256: z.string().regex(/^[a-f0-9]{64}$/),
  signature: z.string().min(1),
});
export type NodeRelease = z.infer<typeof nodeReleaseSchema>;
