import { z } from 'zod';
import type { ProviderSource } from '@nekodot/protocol';
import { NodeFault } from './fault';

const catalog = z.object({
  data: z.array(z.object({ id: z.string() })).optional(),
  models: z
    .array(
      z.object({
        name: z.string(),
        supportedGenerationMethods: z.array(z.string()).optional(),
      }),
    )
    .optional(),
  has_more: z.boolean().optional(),
  last_id: z.string().optional(),
  nextPageToken: z.string().optional(),
});

const unavailable = () => new NodeFault('unavailable', 'Catalog unavailable');

/** Discovery only. Inference always goes through the selected native Hermes transport. */
export async function customModels(source: ProviderSource, key: string) {
  const gemini = source.apiMode === 'gemini_generate_content';
  const messages = source.apiMode === 'anthropic_messages';
  const url = new URL(source.baseUrl!);
  // Same base rules as the Hermes transports: Gemini drops an OpenAI-compatible suffix and
  // defaults to v1beta; the others default to /v1 when the user gave only a host.
  let path = url.pathname.replace(/\/+$/, '');
  if (gemini) {
    path = path.replace(/\/openai$/i, '');
    if (!/\/v\d+(?:alpha|beta)?\d*$/i.test(path)) path += '/v1beta';
  } else if (!path) path = '/v1';
  url.pathname = path + '/models';
  const headers: Record<string, string> = gemini
    ? { 'x-goog-api-key': key }
    : messages
      ? { 'x-api-key': key, 'anthropic-version': '2023-06-01' }
      : { Authorization: 'Bearer ' + key };
  const ids = new Set<string>();
  let next: string | undefined;
  do {
    // An unreachable host, a refused connection and a timeout reject instead of responding.
    const response = await fetch(url, { headers, signal: AbortSignal.timeout(15_000) }).catch(
      () => {
        throw unavailable();
      },
    );
    if (!response.ok) throw unavailable();
    const parsed = catalog.safeParse(await response.json().catch(() => null));
    if (!parsed.success) throw unavailable();
    const page = parsed.data;
    const rows = gemini ? page.models : page.data;
    if (!rows) throw unavailable();
    if (gemini) {
      for (const item of page.models!)
        if (item.supportedGenerationMethods?.includes('generateContent'))
          ids.add(item.name.replace(/^models\//, ''));
    } else {
      for (const item of page.data!) ids.add(item.id);
    }
    next = gemini ? page.nextPageToken : page.has_more ? page.last_id : undefined;
    if (!next) break;
    url.searchParams.set(gemini ? 'pageToken' : 'after_id', next);
  } while (next);
  return [...ids];
}
