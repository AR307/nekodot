import { z } from 'zod';

export const secretFieldSchema = z.strictObject({
  name: z.string().regex(/^[A-Za-z_][A-Za-z0-9_]*$/),
  label: z.string().min(1),
  kind: z.enum(['text', 'password', 'private-key', 'otp']),
});
export const secretTargetSchema = z.discriminatedUnion('kind', [
  z.strictObject({
    kind: z.literal('file'),
    path: z.string().min(1),
    format: z.enum(['env', 'json', 'yaml', 'raw']),
  }),
  z.strictObject({ kind: z.literal('vault'), origin: z.url() }),
  z.strictObject({ kind: z.literal('browser-code'), origin: z.url() }),
  z.strictObject({ kind: z.literal('native-env'), path: z.string().min(1) }),
]);
export const secretSpecSchema = z.strictObject({
  service: z.string().trim().min(1),
  purpose: z.string().trim().min(1),
  fields: z.array(secretFieldSchema).length(1, 'Each card asks for exactly one field'),
  target: secretTargetSchema,
});
export const secretRequestSchema = secretSpecSchema.extend({
  requestId: z.string(),
  botId: z.string(),
  conversationId: z.string(),
  taskId: z.string().optional(),
  sessionId: z.string(),
  state: z.enum([
    'pending',
    'delivered',
    'applied',
    'failed',
    'cancelled',
    'expired',
    'redelivery',
  ]),
  saved: z.boolean(),
  createdAt: z.string(),
  updatedAt: z.string(),
  result: z.string(),
  credentialId: z.string().optional(),
});
export const savedSecretSchema = secretSpecSchema.extend({
  credentialId: z.string(),
  botId: z.string(),
  enabled: z.boolean(),
  createdAt: z.string(),
  lastUsedAt: z.string(),
});
export const secretEnvelopeSchema = z.strictObject({
  version: z.literal(1),
  publicKey: z.string().min(1).max(128),
  salt: z.string().min(1).max(128),
  nonce: z.string().min(1).max(128),
  ciphertext: z.string().min(1).max(1_048_576),
  tag: z.string().min(1).max(128),
});
export type SecretSpec = z.infer<typeof secretSpecSchema>;
export type SecretRequest = z.infer<typeof secretRequestSchema>;
export type SavedSecret = z.infer<typeof savedSecretSchema>;
export type SecretEnvelope = z.infer<typeof secretEnvelopeSchema>;
