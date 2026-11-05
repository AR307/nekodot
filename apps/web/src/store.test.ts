import { beforeEach, expect, it, vi } from 'vitest';
import type { Me } from '@nekodot/protocol';

const memory = new Map<string, string>();
vi.stubGlobal('localStorage', {
  getItem: (key: string) => memory.get(key) ?? null,
  setItem: (key: string, value: string) => void memory.set(key, value),
  removeItem: (key: string) => void memory.delete(key),
});
const { useAppStore, selectNodeData, selectUpdateCommand } = await import('./store');

const command = "curl -fsSL 'https://relay.example.test/install.sh' | bash";
const me = (online: boolean, updateCommand: string | null): Me => ({
  user: { userId: 'user-1', email: 'user@example.test' },
  nodes: [{ nodeId: 'node-1', name: 'Legacy', platform: 'linux', online, updateCommand }],
});
const state = () => useAppStore.getState();

beforeEach(() => {
  state().setToken('token');
  state().setSelectedNode('node-1');
  state().setSocketReady(true);
  state().setMe(me(true, command));
});

it('keeps a connected legacy Node update command after its snapshot is rejected', () => {
  expect(selectUpdateCommand(state())).toBe(command);
  // A 1.0.0 Node answers sync.snapshot in the old shape; the client cannot use it.
  state().setNodeUnsynced('node-1');
  expect(selectNodeData(state()).online).toBe(false);
  expect(state().me?.nodes[0]?.online).toBe(true);
  expect(selectUpdateCommand(state())).toBe(command);
});

it('drops the command on disconnect and waits for /me after the computer reconnects', () => {
  state().setNodeOnline('node-1', false);
  expect(state().me?.nodes[0]).toMatchObject({ online: false, updateCommand: null });
  expect(selectUpdateCommand(state())).toBeNull();
  state().setNodeOnline('node-1', true);
  expect(selectUpdateCommand(state())).toBeNull();
  state().setMe(me(true, null));
  expect(selectUpdateCommand(state())).toBeNull();
});

it('hides the command until the browser socket is ready', () => {
  state().setSocketReady(false);
  expect(selectUpdateCommand(state())).toBeNull();
});
