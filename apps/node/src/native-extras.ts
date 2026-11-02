import type { HermesRuntime } from './hermes/runtime';
import { NodeFault } from './fault';

/** Narrow product projections of Hermes' profile-bound learning and pet APIs. */
export class NativeExtras {
  constructor(private readonly hermes: HermesRuntime) {}

  async learning(botId: string) {
    const { buckets, summary, count } = await this.hermes.gateway(botId).rpc<{
      buckets: Record<string, unknown>[];
      summary: string[];
      count: number;
    }>('learning.frames', { frames: 2 });
    // Flutter renders the structured nodes, not Hermes' terminal animation frames.
    return { buckets, summary, count };
  }

  async learningEntry(botId: string, id: string, content?: string) {
    const result = await this.hermes.gateway(botId).rpc<{
      ok: boolean;
      message?: string;
      [key: string]: unknown;
    }>(content === undefined ? 'learning.detail' : 'learning.edit', {
      id,
      ...(content === undefined ? {} : { content }),
    });
    if (!result.ok)
      throw new NodeFault('invalid_params', result.message ?? 'Hermes learning entry unavailable');
    return result;
  }

  async pets(botId: string) {
    const gateway = this.hermes.gateway(botId);
    const [gallery, generation] = await Promise.all([
      gateway.rpc<Record<string, unknown>>('pet.gallery', { profile: botId }),
      gateway.rpc<Record<string, unknown>>('pet.generate.status', { profile: botId }),
    ]);
    return { ...gallery, generation };
  }

  petThumbnail(botId: string, slug: string, url: string) {
    // Hermes thumbnail_png itself restricts remote assets to its petdex host.
    return this.hermes.gateway(botId).rpc<Record<string, unknown>>('pet.thumb', {
      profile: botId,
      slug,
      url,
    });
  }

  petAction(
    botId: string,
    action: 'select' | 'disable' | 'scale' | 'generate' | 'hatch',
    params: Record<string, unknown>,
  ) {
    return this.hermes
      .gateway(botId)
      .rpc<Record<string, unknown>>(`pet.${action}`, { ...params, profile: botId }, 15 * 60_000);
  }

  subscription(botId: string) {
    // The canonical ticket binds even the account-read handlers to this profile.
    return this.hermes
      .gateway(botId)
      .rpc<Record<string, unknown>>('subscription.state', { profile: botId });
  }
}
