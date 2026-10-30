import { z } from 'zod';

export const modelSettingsSchema = z.strictObject({
  contextLength: z.number().int().positive().nullable().optional(),
});
export const providerOutputSchema = z.strictObject({
  sourceId: z.string().min(1),
  kind: z.enum(['custom', 'oauth']),
  name: z.string(),
  provider: z.string(),
  baseUrl: z.url().optional(),
  apiKeyLast4: z.string().max(4).optional(),
  ready: z.boolean(),
});
export const providerInputSchema = z.strictObject({
  sourceId: z.string().min(1).optional(),
  kind: z.literal('custom'),
  name: z.string().trim().min(1),
  baseUrl: z.url(),
  apiKey: z.string().min(1).optional(),
});
export const modelInfoSchema = z.strictObject({
  model: z.string(),
  provider: z.string(),
  detectedContext: z.number().positive().nullable(),
  configuredContext: z.number().positive().nullable(),
  effectiveContext: z.number().positive().nullable(),
  detectedMaxOutput: z.number().positive().nullable(),
  configuredMaxOutput: z.number().positive().nullable(),
  contextSource: z.string(),
  outputSource: z.string(),
  compression: z.strictObject({
    enabled: z.boolean(),
    threshold: z.number().nullable(),
    thresholdTokens: z.number().nullable(),
    effectiveThresholdTokens: z.number().nullable(),
    count: z.number().int().nonnegative().nullable(),
    records: z.array(z.record(z.string(), z.json())),
    note: z.string(),
  }),
});
export type ProviderSource = z.infer<typeof providerOutputSchema>;
