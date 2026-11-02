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
    if (method === 'subagent.list')
      return {
        subagents: [
          { subagent_id: 'child-qa', goal: 'Inspect a harmless fixture', status: 'running' },
        ],
      };
    if (method === 'process.list')
      return { processes: [{ session_id: 'proc-qa', command: 'sleep 60', status: 'running' }] };
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
      expect.objectContaining({ name: '/new', availability: 'app' }),
      expect.objectContaining({ name: '/handoff', availability: 'not-integrated' }),
      expect.objectContaining({ name: '/redraw', availability: 'app' }),
      expect.objectContaining({ name: '/toolsets', availability: 'available' }),
      expect.objectContaining({ name: '/plan', availability: 'available' }),
    ]),
  );
  expect(catalog.commands.find((row) => row.name === '/quit')?.description).not.toContain(
    '--delete',
  );
  expect(catalog.commands.find((row) => row.name === '/queue')?.description).toContain(
    'enqueue/edit/reorder are not connected',
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

it('shows native child and process identifiers that users need for tail, steer and stop', async () => {
  const { commands } = await commandJourney();
  const result = await commands.execute('test-bot', '/agents');
  expect(result.output).toContain('Agent child-qa [running]: Inspect a harmless fixture');
  expect(result.output).toContain('Process proc-qa [running]: sleep 60');
});

it('App help explains the actual adapter syntax instead of advertising unsupported CLI arguments', async () => {
  const { commands, rpc } = await commandJourney();
  const result = await commands.execute('test-bot', '/help quit');
  expect(result.output).toContain('usage: /quit');
  expect(result.output).not.toContain('--delete');
  expect(rpc.mock.calls.every(([method]) => method === 'commands.catalog')).toBe(true);
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
  await expect(commands.execute('test-bot', '/handoff')).rejects.toThrow(
    'does not expose handoff on canonical gateway sessions',
  );
  await expect(commands.execute('test-bot', '/config agent.max_turns 10')).rejects.toThrow(
    'without arguments',
  );
  expect(saveHermesSession).not.toHaveBeenCalled();
  expect(rpc.mock.calls.every(([method]) => method === 'commands.catalog')).toBe(true);
});
