import { z } from 'zod';
import type { HermesRuntime } from './hermes/runtime';

const nativeLimits = z.object({
  memory: z.object({
    memory_char_limit: z.number().int().positive(),
    user_char_limit: z.number().int().positive(),
  }),
});

/** A profile's native MemoryStore caps for MEMORY.md and USER.md, defaults included. */
export async function memoryLimits(hermes: HermesRuntime, profile: string) {
  const { memory } = nativeLimits.parse(
    await hermes.management.request('/api/config?include_defaults=true', profile),
  );
  return { memory: memory.memory_char_limit, user: memory.user_char_limit };
}
