import { z } from 'zod';
import { idSchema } from './entities';

export const notificationSchema = z.strictObject({
  notificationId: z.string().min(1).max(240),
  conversationId: idSchema,
  kind: z.enum(['approval', 'completed', 'failed']),
});
export type TaskNotification = z.infer<typeof notificationSchema>;
export const deviceSchema = z.strictObject({
  deviceId: z.uuidv4(),
  token: z.string().min(1).max(4096),
  platform: z.literal('android'),
});
