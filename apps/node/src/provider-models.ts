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

/** Discovery only. Inference always goes through the selected native Hermes transport. */
export async function customModels(source: ProviderSource, key: string) {
  const gemini = source.apiMode === 'gemini_generate_content';
  const messages = source.apiMode === 'anthropic_messages';
  const base = new URL(source.baseUrl!);
  base.pathname = base.pathname.replace(/\/$/, '');
  if (gemini) {
    base.pathname = base.pathname.replace(/\/openai$/, '');
    if (!/\/v\d+(?:beta\d*|alpha\d*)?$/.test(base.pathname)) base.pathname += '/v1beta';
  } else if (!base.pathname || base.pathname === '/') base.pathname = '/v1';
  const url = new URL(base.toString());
  url.pathname = url.pathname.replace(/\/$/, '') + '/models';
  const headers: Record<string, string> = gemini
    ? { 'x-goog-api-key': key }
    : messages
      ? { 'x-api-key': key, 'anthropic-version': '2023-06-01' }
      : { Authorization: 'Bearer ' + key };
  const ids = new Set<string>();
  let next: string | undefined;
  do {
    const response = await fetch(url, { headers, signal: AbortSignal.timeout(15_000) });
    if (!response.ok) throw new NodeFault('unavailable', 'Catalog unavailable');
    const parsed = catalog.safeParse(await response.json().catch(() => null));
    if (!parsed.success) throw new NodeFault('unavailable', 'Catalog unavailable');
    const page = parsed.data;
    const rows = gemini ? page.models : page.data;
    if (!rows) throw new NodeFault('unavailable', 'Catalog unavailable');
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
