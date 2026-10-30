import { z } from 'zod';
import { idSchema } from './entities';

export const notificationSchema = z.strictObject({
  notificationId: z.string().min(1).max(240),
  conversationId: idSchema,
  kind: z.enum(['approval', 'question', 'completed', 'failed']),
  displayName: z.string().max(160),
  preview: z.string().max(801),
});
export type TaskNotification = z.infer<typeof notificationSchema>;
export const deviceSchema = z.strictObject({
  deviceId: z.uuidv4(),
  token: z.string().min(1).max(4096),
  platform: z.literal('android'),
});
