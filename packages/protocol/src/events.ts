import { z } from 'zod';
import {
  botSchema,
  conversationSchema,
  groupSchema,
  idSchema,
  messageSchema,
  seqSchema,
} from './entities';
const eventBase = { seq: seqSchema };
export const eventSchema = z.discriminatedUnion('kind', [
  z.strictObject({ ...eventBase, kind: z.literal('bot.upserted'), data: botSchema }),
  z.strictObject({
    ...eventBase,
    kind: z.literal('bot.archived'),
    data: z.strictObject({ botId: botSchema.shape.botId }),
  }),
  z.strictObject({ ...eventBase, kind: z.literal('group.upserted'), data: groupSchema }),
  z.strictObject({
    ...eventBase,
    kind: z.literal('group.archived'),
    data: z.strictObject({ groupId: idSchema }),
  }),
  z.strictObject({
    ...eventBase,
    kind: z.literal('conversation.upserted'),
    data: conversationSchema,
  }),
  z.strictObject({ ...eventBase, kind: z.literal('message.upserted'), data: messageSchema }),
]);
export const liveSchema = z.discriminatedUnion('kind', [
  z.strictObject({
    kind: z.literal('delta'),
    conversationId: idSchema,
    messageId: idSchema,
    text: z.string(),
  }),
  z.strictObject({
    kind: z.literal('activity'),
    conversationId: idSchema,
    botId: botSchema.shape.botId,
    state: z.enum(['thinking', 'tool', 'waiting_approval', 'idle']),
    chain: z
      .strictObject({ count: z.number().int().nonnegative(), max: z.number().int().positive() })
      .optional(),
  }),
]);
export type PersistedEvent = z.infer<typeof eventSchema>;
export type LiveEvent = z.infer<typeof liveSchema>;
