import { BlockList, isIP } from 'node:net';
import type { HermesRuntime } from './hermes/runtime';

// Product policy: small means a known effective context of at most 32K tokens.
const localRanges = new BlockList();
for (const [address, prefix] of [
  ['127.0.0.0', 8],
  ['10.0.0.0', 8],
  ['172.16.0.0', 12],
  ['192.168.0.0', 16],
  ['169.254.0.0', 16],
  ['100.64.0.0', 10],
] as const)
  localRanges.addSubnet(address, prefix, 'ipv4');
localRanges.addAddress('::1', 'ipv6');
localRanges.addSubnet('fc00::', 7, 'ipv6');
localRanges.addSubnet('fe80::', 10, 'ipv6');

export function toolSearchMode(baseUrl: string | undefined, context: number): 'on' | 'off' {
  if (!baseUrl || !Number.isFinite(context) || context <= 0 || context > 32768) return 'off';
  const host = new URL(baseUrl).hostname.replace(/^\[|\]$/g, '');
  const ip = isIP(host);
  const local = ip
    ? localRanges.check(host, ip === 4 ? 'ipv4' : 'ipv6')
    : !host.includes('.') || host.endsWith('.localhost') || host.endsWith('.local');
  return local ? 'on' : 'off';
}

/** Called only on a Bot model/source/context selection, not during a conversation. */
export async function configureToolSearch(hermes: HermesRuntime, botId: string) {
  const [info, config] = await Promise.all([
    hermes.management.request<{ effective_context_length: number; provider: string }>(
      '/api/model/info',
      botId,
    ),
    hermes.management.request<{
      model?: { base_url?: string };
      providers?: Record<string, { base_url?: string }>;
    }>('/api/config?include_defaults=true', botId),
  ]);
  const baseUrl = config.model?.base_url || config.providers?.[info.provider]?.base_url;
  await hermes.management.request('/api/config', botId, {
    method: 'PUT',
    body: JSON.stringify({
      config: {
        tools: { tool_search: { enabled: toolSearchMode(baseUrl, info.effective_context_length) } },
      },
    }),
  });
}
