import { z } from 'zod';
import { avatarSchema } from './entities';

export const tokenUsageSchema = z.strictObject({
  input: z.number().int().nonnegative(),
  output: z.number().int().nonnegative(),
  cacheRead: z.number().int().nonnegative(),
  cacheWrite: z.number().int().nonnegative(),
});
export type TokenUsage = z.infer<typeof tokenUsageSchema>;
export const emptyUsage = (): TokenUsage => ({ input: 0, output: 0, cacheRead: 0, cacheWrite: 0 });
export const totalUsage = (value: TokenUsage) =>
  value.input + value.output + value.cacheRead + value.cacheWrite;

export const usageEntitySchema = z.strictObject({
  id: z.string().min(1),
  kind: z.enum(['bot', 'group', 'routine']),
  name: z.string(),
  ownerName: z.string(),
  avatars: z.array(avatarSchema),
  group: z.boolean(),
});
export type UsageEntity = z.infer<typeof usageEntitySchema>;
export const usageRecordSchema = z.strictObject({
  taskId: z.string().optional(),
  id: z.string().min(1),
  profile: z.string().min(1),
  sessionId: z.string(),
  executionId: z.string(),
  at: z.iso.datetime(),
  tokens: tokenUsageSchema.nullable(),
  entity: usageEntitySchema,
});
export type UsageRecord = z.infer<typeof usageRecordSchema>;
export const usageBatchSchema = z.strictObject({
  records: z.array(usageRecordSchema).max(500),
});
export interface UsageAmounts {
  tokens: TokenUsage;
  total: number;
  unavailable: number;
}
export interface UsageBreakdown extends UsageAmounts {
  nodeId: string;
  nodeName: string;
  entity: UsageEntity;
  percent: number;
}
export interface UsageDayRow extends UsageAmounts {
  date: string;
  nodeId: string;
  nodeName: string;
  entity: UsageEntity;
}
export interface UsageSummary {
  from: string;
  to: string;
  totals: UsageAmounts;
  days: ({ date: string } & UsageAmounts)[];
  conversations: UsageBreakdown[];
  routines: UsageBreakdown[];
  rows: UsageDayRow[];
  nodes: { nodeId: string; name: string; online: boolean; syncedAt: string | null }[];
}
