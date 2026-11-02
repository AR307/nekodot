import { readFile } from 'node:fs/promises';
import { expect, it, vi } from 'vitest';
import type { NodeDatabase } from './database';
import type { HermesRuntime } from './hermes/runtime';
import { BotCommands } from './commands';

async function commandJourney() {
  const { catalog } = JSON.parse(await readFile('docs/fixtures/commands-native.json', 'utf8'));
  const rpc = vi.fn(async (method: string) => {
    if (method === 'commands.catalog') return catalog;
    if (method === 'session.create')
      return {
        session_id: 'native-live',
        stored_session_id: 'native-stored',
        replay_epoch: 'native-epoch',
        last_sequence: 0,
      };
    if (method === 'session.history')
      return {
        messages: [
          { role: 'user', text: 'Remember the harmless test label.' },
          { role: 'assistant', text: 'I remember the harmless test label.' },
          { role: 'tool', text: 'not a conversation turn' },
          { role: 'user', text: 'hidden projection row', hidden: true },
        ],
      };
    if (method === 'slash.exec') return { output: 'Native reply' };
    throw new Error('Unexpected native method: ' + method);
  });
  const saveHermesSession = vi.fn();
  const database = {
    conversations: () => [{ kind: 'dm', botId: 'test-bot', conversationId: 'test-dm' }],
    hermesSession: () => undefined,
    saveHermesSession,
  } as unknown as NodeDatabase;
  const runtime = { gateway: () => ({ rpc }) } as unknown as HermesRuntime;
  return { commands: new BotCommands(database, runtime), rpc, saveHermesSession };
}

it('lists usable commands honestly and reads history through the native history API, without a model turn', async () => {
  const { commands, rpc } = await commandJourney();
  const catalog = await commands.catalog('test-bot');
  expect(catalog.commands).toEqual(
    expect.arrayContaining([
      expect.objectContaining({ name: '/history', availability: 'app' }),
      expect.objectContaining({ name: '/config', availability: 'app' }),
      expect.objectContaining({ name: '/model', availability: 'app' }),
      expect.objectContaining({ name: '/new', availability: 'not-integrated' }),
      expect.objectContaining({ name: '/redraw', availability: 'terminal' }),
      expect.objectContaining({ name: '/toolsets', availability: 'available' }),
      expect.objectContaining({ name: '/plan', availability: 'available' }),
    ]),
  );
  const history = await commands.execute('test-bot', '/history');
  expect(history.output).toContain('Bot: I remember the harmless test label.');
  expect(history.output).not.toContain('hidden projection row');
  expect(history.output).not.toContain('not a conversation turn');
  expect(rpc).toHaveBeenCalledWith('session.history', { session_id: 'native-live' });
  expect(rpc.mock.calls.some(([method]) => ['slash.exec', 'prompt.submit'].includes(method))).toBe(
    false,
  );
});

it('opens App settings and composes locally; unsupported session controls never alter the session', async () => {
  const { commands, rpc, saveHermesSession } = await commandJourney();
  expect(await commands.execute('test-bot', '/config')).toEqual({
    type: 'navigate',
    target: 'settings',
  });
  expect(await commands.execute('test-bot', '/plugins')).toEqual({
    type: 'navigate',
    target: 'plugins',
  });
  expect(await commands.execute('test-bot', '/compose My next instruction')).toEqual({
    type: 'prefill',
    message: 'My next instruction',
  });
  await expect(commands.execute('test-bot', '/new')).rejects.toThrow('not connected yet');
  await expect(commands.execute('test-bot', '/config agent.max_turns 10')).rejects.toThrow(
    'without arguments',
  );
  expect(saveHermesSession).not.toHaveBeenCalled();
  expect(rpc.mock.calls.every(([method]) => method === 'commands.catalog')).toBe(true);
});
