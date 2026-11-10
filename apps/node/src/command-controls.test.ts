import { expect, it, vi } from 'vitest';
import type { HermesRuntime } from './hermes/runtime';
import type { NodeDatabase } from './database';
import { commandControl } from './command-controls';
import { settingsCommand } from './command-settings';

it('writes toolsets through the native profile-scoped REST writer, without rebuilding a session', async () => {
  const request = vi.fn(async () => [{ name: 'terminal' }]),
    rpc = vi.fn(),
    gateway = vi.fn();
  const runtime = { management: { request, rpc }, gateway } as unknown as HermesRuntime;
  const result = await settingsCommand(runtime, 'chosen-bot', '/tools', 'disable terminal');
  expect(result.output).toContain('Hermes profile tools: terminal');
  expect(request).toHaveBeenLastCalledWith('/api/tools/toolsets/terminal', 'chosen-bot', {
    method: 'PUT',
    body: JSON.stringify({ enabled: false }),
  });
  expect(rpc).not.toHaveBeenCalled();
  expect(gateway).not.toHaveBeenCalled();
});

it('sends only a chosen MCP tool filter, not a copied masked configuration or credentials', async () => {
  const request = vi.fn(async () => []),
    rpc = vi.fn(async () => ({
      servers: [{ name: 'files', source: 'config', tools: { exclude: ['write'] } }],
    }));
  const runtime = { management: { request, rpc } } as unknown as HermesRuntime;
  await settingsCommand(runtime, 'chosen-bot', '/tools', 'disable files:delete');
  expect(rpc).toHaveBeenCalledWith('mcp.servers.list', { profile: 'chosen-bot' });
  expect(request).toHaveBeenLastCalledWith('/api/config', 'chosen-bot', {
    method: 'PUT',
    body: JSON.stringify({
      config: { mcp_servers: { files: { tools: { exclude: ['write', 'delete'] } } } },
    }),
  });
});

it('reads native wake requirements with the profile-scoped contract, not a session field', async () => {
  const rpc = vi.fn(async () => ({ session_id: 'live-qa' }));
  const runtime = { gateway: () => ({ rpc }) } as unknown as HermesRuntime;
  const database = {
    conversations: () => [{ kind: 'dm', botId: 'chosen-bot', conversationId: 'dm-qa' }],
    hermesSession: () => undefined,
    setting: () => undefined,
    setSetting: vi.fn(),
    messages: () => [],
    saveHermesSession: vi.fn(),
  } as unknown as NodeDatabase;
  const result = await commandControl(database, runtime, 'chosen-bot', '/wake', 'status');
  expect(rpc).toHaveBeenLastCalledWith('wake.status', {
    profile: 'chosen-bot',
    surface: 'gui',
    client_capture: true,
  });
  expect(result.output).toContain('no listener was started');
});
