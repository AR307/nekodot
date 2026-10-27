import { z } from 'zod';
export const idSchema = z.string().min(1);
export const seqSchema = z.number().int().nonnegative();
export const timestampSchema = z.iso.datetime();
export const avatarSchema = z.strictObject({
  shape: z.literal('dot'),
  color: z.string().regex(/^#[0-9a-fA-F]{6}$/),
});
export const botFields = {
  displayName: z.string().trim().min(1),
  handle: z.string().regex(/^[a-z0-9-]{1,24}$/),
  avatar: avatarSchema,
  role: z.string(),
  model: z.string().min(1),
};
export const botSchema = z.strictObject({
  botId: z.string().regex(/^nk-[a-z2-7]{6}$/),
  ...botFields,
  archived: z.boolean(),
  createdAt: timestampSchema,
});
export const groupFields = {
  name: z.string().trim().min(1),
  botIds: z
    .array(botSchema.shape.botId)
    .min(2)
    .max(6)
    .refine((ids) => new Set(ids).size === ids.length, 'Members must be unique'),
  leadBotId: botSchema.shape.botId,
};
export const groupSchema = z
  .strictObject({
    groupId: idSchema,
    ...groupFields,
    archived: z.boolean(),
    createdAt: timestampSchema,
  })
  .refine((g) => g.botIds.includes(g.leadBotId), 'Lead must be a member');
const conversationBase = { conversationId: idSchema, createdAt: timestampSchema };
export const conversationSchema = z.discriminatedUnion('kind', [
  z.strictObject({ ...conversationBase, kind: z.literal('dm'), botId: botSchema.shape.botId }),
  z.strictObject({ ...conversationBase, kind: z.literal('group'), groupId: idSchema }),
]);
const messageBase = {
  messageId: idSchema,
  conversationId: idSchema,
  seq: seqSchema,
  author: z.strictObject({ type: z.enum(['user', 'bot', 'system']), id: idSchema.optional() }),
  status: z.enum(['streaming', 'done', 'failed', 'cancelled']),
  createdAt: timestampSchema,
};
const textContent = z.strictObject({ text: z.string() });
export const messageSchema = z.discriminatedUnion('kind', [
  z.strictObject({ ...messageBase, kind: z.literal('text'), content: textContent }),
  z.strictObject({ ...messageBase, kind: z.literal('commentary'), content: textContent }),
  z.strictObject({
    ...messageBase,
    kind: z.literal('system'),
    content: z.strictObject({ text: z.string(), retryText: z.string().optional() }),
  }),
  z.strictObject({
    ...messageBase,
    kind: z.literal('tool'),
    content: z.strictObject({
      tool: idSchema,
      preview: z.string(),
      resultPreview: z.string().optional(),
      durationMs: z.number().nonnegative().optional(),
      error: z.boolean().optional(),
    }),
  }),
  z.strictObject({
    ...messageBase,
    kind: z.literal('approval'),
    content: z.strictObject({
      runId: idSchema,
      botId: botSchema.shape.botId,
      requestId: idSchema,
      executionGeneration: z.number().int().nonnegative(),
      prompt: z.string(),
      command: z.string().optional(),
      choice: z.enum(['once', 'deny']).optional(),
    }),
  }),
]);
export type Bot = z.infer<typeof botSchema>;
export type Group = z.infer<typeof groupSchema>;
export type Conversation = z.infer<typeof conversationSchema>;
export type Message = z.infer<typeof messageSchema>;
