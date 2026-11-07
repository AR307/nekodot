import { z } from 'zod';
export const providerApiModeSchema = z.enum([
  '',
  'chat_completions',
  'codex_responses',
  'anthropic_messages',
]);
export const reasoningLevelSchema = z.enum([
  'none',
  'minimal',
  'low',
  'medium',
  'high',
  'xhigh',
  'max',
  'ultra',
]);
export const modelCatalogEntrySchema = z.strictObject({
  model: z.string(),
  name: z.string(),
  catalogProvider: z.string().nullable(),
  catalogUpdatedAt: z.string(),
  sdk: z.string().nullable(),
  api: z.string().nullable(),
  apiMode: providerApiModeSchema.optional(),
  parameters: z.array(z.string()),
  reasoningLevels: z.array(reasoningLevelSchema),
  reasoningOptions: z.array(z.json()),
  context: z.number().nullable(),
  output: z.number().nullable(),
  inputModalities: z.array(z.string()),
  outputModalities: z.array(z.string()),
});
export const modelReasoningSchema = z.strictObject({
  sessionId: z.string(),
  model: z.string(),
  provider: z.string(),
  apiMode: z.string(),
  effort: z.string().nullable(),
  wireEffort: z.string().nullable(),
  levels: z.array(reasoningLevelSchema),
});
export type ModelCatalogEntry = z.infer<typeof modelCatalogEntrySchema>;

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
  apiMode: providerApiModeSchema.optional(),
});
export const providerInputSchema = z.strictObject({
  sourceId: z.string().min(1).optional(),
  kind: z.literal('custom'),
  name: z.string().trim().min(1),
  baseUrl: z.url(),
  apiKey: z.string().min(1).optional(),
  apiMode: providerApiModeSchema.optional(),
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
export const hermesSettingFieldSchema = z.strictObject({
  key: z.string(),
  type: z.string(),
  description: z.string(),
  category: z.string(),
  /** Where the product shows the setting: a kind on the Bot page, or an app-wide group. */
  group: z.string(),
  options: z.array(z.json()).optional(),
  clearable: z.boolean().optional(),
  value: z.json(),
  sensitive: z.boolean(),
  editable: z.boolean(),
  configured: z.boolean(),
});
export const hermesSettingsSchema = z.strictObject({
  botId: z.string(),
  scope: z.literal('Hermes profile'),
  categories: z.array(z.string()),
  fields: z.array(hermesSettingFieldSchema),
});
/** Installation-wide Hermes settings, kept identical on the root and every Bot profile. */
export const hermesSharedSettingsSchema = z.strictObject({
  scope: z.literal('All Bot profiles'),
  categories: z.array(z.string()),
  fields: z.array(hermesSettingFieldSchema),
});
export type ProviderSource = z.infer<typeof providerOutputSchema>;
