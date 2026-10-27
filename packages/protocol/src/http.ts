import { z } from 'zod';

export const authInputSchema = z.strictObject({
  email: z.email().trim().toLowerCase(),
  password: z.string().min(8),
});
export const pairInputSchema = z.strictObject({
  code: z.string().regex(/^[A-HJ-NP-Z2-9]{4}-[A-HJ-NP-Z2-9]{4}$/),
  nodeName: z.string().trim().min(1),
  platform: z.string().min(1),
});
export const nodeSummarySchema = z.strictObject({
  nodeId: z.string(),
  name: z.string(),
  platform: z.string(),
  online: z.boolean(),
});
export const meSchema = z.strictObject({
  user: z.strictObject({ userId: z.string(), email: z.email() }),
  nodes: z.array(nodeSummarySchema),
});
export type NodeSummary = z.infer<typeof nodeSummarySchema>;
export type Me = z.infer<typeof meSchema>;
