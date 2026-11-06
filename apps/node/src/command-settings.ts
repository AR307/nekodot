import type { HermesRuntime } from './hermes/runtime';
import type { CommandResult } from './session-commands';
import { NodeFault } from './fault';

type SettingsCommand = '/pet' | '/tools' | '/skills';
export function isSettingsCommand(name: string, arg: string): name is SettingsCommand {
  return (
    name === '/pet' ||
    (name === '/tools' && !!arg && arg !== 'list') ||
    (name === '/skills' && /^(install|search|browse|inspect)(?:\s|$)/.test(arg))
  );
}
export async function settingsCommand(
  hermes: HermesRuntime,
  botId: string,
  name: SettingsCommand,
  arg: string,
): Promise<CommandResult> {
  if (name === '/tools') {
    const [action, ...names] = arg.split(/\s+/);
    if (!['enable', 'disable'].includes(action!) || !names.length)
      throw new NodeFault(
        'invalid_params',
        'Usage: /tools [list | enable|disable <toolset or server:tool> ...]',
      );
    const enabled = action === 'enable';
    const changed: string[] = [],
      unknown: string[] = [],
      missing: string[] = [];
    const catalog = await hermes.management.request<{ name: string }[]>(
      '/api/tools/toolsets',
      botId,
    );
    for (const target of names.filter((value) => !value.includes(':'))) {
      if (!catalog.some((row) => row.name === target)) {
        unknown.push(target);
        continue;
      }
      // tools.configure ignores profile in v0.22.5. The official REST writer
      // scopes the write correctly and keeps native install-on-enable behavior.
      await hermes.management.request(`/api/tools/toolsets/${encodeURIComponent(target)}`, botId, {
        method: 'PUT',
        body: JSON.stringify({ enabled }),
      });
      changed.push(target);
    }
    const targets = names.filter((value) => value.includes(':'));
    if (targets.length) {
      const { servers } = await hermes.management.rpc<{
        servers: { name: string; source: string; tools?: { exclude?: string[] } }[];
      }>('mcp.servers.list', { profile: botId });
      const patch: Record<string, { tools: { exclude: string[] } }> = {};
      for (const target of targets) {
        const separator = target.indexOf(':'),
          serverName = target.slice(0, separator),
          tool = target.slice(separator + 1);
        const server = servers.find((row) => row.name === serverName);
        if (!server || !tool) {
          missing.push(target);
          continue;
        }
        if (server.source === 'plugin')
          throw new NodeFault(
            'invalid_params',
            `Hermes manages ${serverName} through its plugin settings.`,
          );
        const exclude = patch[serverName]?.tools.exclude ?? server.tools?.exclude ?? [];
        patch[serverName] = {
          tools: {
            exclude: enabled
              ? exclude.filter((value) => value !== tool)
              : [...new Set([...exclude, tool])],
          },
        };
        changed.push(target);
      }
      // Native config PUT deep-merges only these filter lists. Credentials and
      // all other server settings remain untouched; no masked values are copied.
      if (Object.keys(patch).length)
        await hermes.management.request('/api/config', botId, {
          method: 'PUT',
          body: JSON.stringify({ config: { mcp_servers: patch } }),
        });
    }
    return {
      output: `Hermes profile tools: ${changed.join(', ') || 'no changes'}\nUnknown: ${unknown.join(', ') || 'none'}\nMissing servers/tools: ${missing.join(', ') || 'none'}\nNative profile configuration saved. Existing context is not rebuilt; use /new for its new tool policy.`,
    };
  }
  if (name === '/pet') {
    if (!arg || arg === 'list') return { type: 'navigate', target: 'pets' };
    const gateway = hermes.gateway(botId);
    if (arg === 'toggle') {
      const info = await gateway.rpc<{ enabled: boolean; active: string }>('pet.gallery', {
        profile: botId,
      });
      if (!info.enabled && !info.active) return { type: 'navigate', target: 'pets' };
      await gateway.rpc(info.enabled ? 'pet.disable' : 'pet.select', {
        profile: botId,
        ...(info.enabled ? {} : { slug: info.active }),
      });
    } else if (arg.startsWith('scale ')) {
      const scale = Number(arg.slice(6));
      if (!Number.isFinite(scale) || scale <= 0)
        throw new NodeFault('invalid_params', 'Usage: /pet scale <positive number>');
      await gateway.rpc('pet.scale', { profile: botId, scale });
    } else {
      await gateway.rpc('pet.select', { profile: botId, slug: arg }, 120_000);
    }
    return { output: 'Hermes profile pet setting saved.', type: 'navigate', target: 'pets' };
  }
  const [action, ...query] = arg.split(/\s+/);
  const result = await hermes.management.rpc<Record<string, unknown>>(
    'skills.manage',
    { profile: botId, action, query: query.join(' ') },
    15 * 60_000,
  );
  return { output: JSON.stringify(result, null, 2) };
}
