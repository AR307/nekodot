import { mkdir, mkdtemp, readFile, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { parseDocument, stringify } from 'yaml';
import { expect, it } from 'vitest';
import { NodeDatabase } from './database';
import type { HermesRuntime } from './hermes/runtime';
import { approvalCommand, Workplaces } from './workplaces';

const botId = 'nk-abcdef';

/** A Dot's profile whose `hermes config set/unset` edits its config.yaml as Hermes does. */
async function setup() {
  const home = await mkdtemp(join(tmpdir(), 'nekodot-workplaces-'));
  const db = new NodeDatabase(home);
  db.putBot({
    botId,
    displayName: 'Dot',
    handle: 'dot',
    role: '',
    model: 'qa',
    avatar: { shape: 'dot', color: '#E8603C' },
    archived: false,
    createdAt: new Date().toISOString(),
  });
  const profile = join(home, 'profiles', botId);
  await mkdir(join(profile, 'plugins', 'nekodot-secrets'), { recursive: true });
  await writeFile(join(profile, 'plugins', 'nekodot-secrets', 'bridge.token'), 'bridge-token\n');
  const configPath = join(profile, 'config.yaml');
  await writeFile(
    configPath,
    stringify({ model: { default: 'qa' }, terminal: { ssh_port: 2200 } }),
  );
  const calls: string[][] = [];
  const screen = { running: true, stops: 0, restarts: 0 };
  const hermes = {
    restart: async () => {
      screen.restarts++;
    },
    management: {
      rpc: async (method: string) => {
        if (method === 'display.stop') {
          screen.stops++;
          screen.running = false;
        }
        return { running: screen.running };
      },
    },
    profileHome: (bot: string) => join(home, 'profiles', bot),
    cli: async (bot: string, args: string[]) => {
      expect(bot).toBe(botId);
      calls.push(args);
      const document = parseDocument(await readFile(configPath, 'utf8'));
      const [, verb, key, value] = args;
      const path = key!.split('.');
      // Hermes stores numbers it is given as text as numbers.
      if (verb === 'set') document.setIn(path, /^\d+$/.test(value!) ? Number(value) : value);
      else document.deleteIn(path);
      await writeFile(configPath, document.toString());
      return '';
    },
  } as unknown as HermesRuntime;
  const workplaces = new Workplaces(db, hermes, 1);
  const terminal = async () =>
    (parseDocument(await readFile(configPath, 'utf8')).toJS() as { terminal?: object }).terminal;
  return { db, profile, workplaces, calls, terminal, screen };
}
const ask = (operation: string, extra: object = {}) => ({
  action: 'sandbox',
  operation,
  botId,
  token: 'bridge-token',
  ...extra,
});

it('moves a Dot into a sandbox it set up and back to exactly what it had', async () => {
  const { profile, workplaces, calls, terminal, screen } = await setup();
  await mkdir(join(profile, 'sandbox'));
  await writeFile(join(profile, 'sandbox', 'desk'), 'private key');

  const moved = await workplaces.local(
    ask('use', {
      label: 'Daytona desktop',
      backend: 'ssh',
      settings: {
        ssh_host: 'ssh.example.com',
        ssh_user: 'pn',
        ssh_port: 22,
        ssh_key: 'sandbox/desk',
      },
    }),
  );
  expect(moved).toMatchObject({ workplace: { label: 'Daytona desktop', backend: 'ssh' } });
  expect(calls[0]).toEqual(['config', 'set', 'terminal.backend', 'ssh']);
  expect(await terminal()).toEqual({
    backend: 'ssh',
    ssh_host: 'ssh.example.com',
    ssh_user: 'pn',
    ssh_port: 22,
    ssh_key: join(profile, 'sandbox', 'desk'),
  });
  expect(await workplaces.local(ask('status'))).toEqual({
    workplace: { label: 'Daytona desktop', backend: 'ssh' },
  });
  // The screen on this computer stopped when the hands left it, and Hermes restarts so that
  // nothing keeps working on the old backend.
  expect(screen.stops).toBe(1);
  await new Promise((resolve) => setTimeout(resolve, 20));
  expect(screen.restarts).toBe(1);
  screen.running = true;

  // Another sandbox: the first move is undone before the second, so home still means home.
  await workplaces.local(ask('use', { label: 'Modal', backend: 'modal', settings: {} }));
  expect(await terminal()).toEqual({ ssh_port: 2200, backend: 'modal' });

  await workplaces.local(ask('home'));
  expect(await terminal()).toEqual({ ssh_port: 2200 });
  // Moving to Modal stopped the sandbox's screen; Modal has none to stop.
  expect(screen.stops).toBe(2);
  expect(workplaces.get(botId)).toBeNull();
});

it('takes only well-formed moves from the Dot that owns them', async () => {
  const { workplaces, calls } = await setup();
  const refused = [
    ask('use', { label: 'x', backend: 'local' }),
    ask('use', { label: 'x', backend: 'ssh', settings: { api_token: 'value' } }),
    ask('use', { label: 'x', backend: 'ssh', settings: { ssh_password: 'value' } }),
    ask('use', { label: 'x', backend: 'ssh', settings: { ssh_host: 'a\nb' } }),
    ask('use', { label: 'x', backend: 'ssh', settings: { 'ssh.host': 'a' } }),
    ask('use', { backend: 'ssh' }),
    ask('computer'),
    { ...ask('status'), token: 'another-profile' },
  ];
  for (const request of refused) await expect(workplaces.local(request)).rejects.toThrow();
  await expect(
    workplaces.local(
      ask('use', { label: 'x', backend: 'ssh', settings: { ssh_key: '../../key' } }),
    ),
  ).rejects.toThrow(/profile/);
  await expect(
    workplaces.local(ask('use', { label: 'x', backend: 'ssh', settings: { ssh_key: 'missing' } })),
  ).rejects.toThrow(/exist/);
  expect(calls).toEqual([]);
});

it('gives the Dot a one-time install command for a new computer in a sandbox', async () => {
  const { workplaces } = await setup();
  await expect(workplaces.local(ask('computer', { name: 'Cloud' }))).rejects.toThrow(/Relay/);
  workplaces.pairing = async () => ({
    code: 'ABCD-2345',
    expiresAt: '2026-11-18T00:30:00.000Z',
    installCommand: "curl -fsSL 'https://relay.example/install.sh' | bash -s -- --pair ABCD-2345",
    sandboxCommand:
      "curl -fsSL 'https://relay.example/install.sh' | bash -s -- --pair ABCD-2345 --sandbox",
  });
  const result = (await workplaces.local(ask('computer', { name: "Kai's box" }))) as {
    command: string;
  };
  expect(result.command).toBe(
    "curl -fsSL 'https://relay.example/install.sh' | bash -s -- --pair ABCD-2345 --sandbox --name 'Kai'\\''s box'",
  );
});

it('shows what the sandbox plugin asks on its approval card, not the rule name', () => {
  expect(approvalCommand('<nekodot_sandbox> (plugin approval rule)')).toBeUndefined();
  expect(approvalCommand("computer_use: key 'ctrl+l'")).toBe("computer_use: key 'ctrl+l'");
  expect(approvalCommand(undefined)).toBeUndefined();
});

it('restarts Hermes only once no Dot is working', async () => {
  const { db, workplaces, screen } = await setup();
  const run = {
    botId,
    conversationId: 'chat',
    inputMessageId: 'input',
    runId: 'run',
    sessionId: 'session',
    storedSessionId: 'stored',
    state: 'thinking' as const,
    lastSeq: 0,
  };
  db.saveRun(run);
  const restarted = workplaces.restartWhenIdle();
  await new Promise((resolve) => setTimeout(resolve, 20));
  expect(screen.restarts).toBe(0);
  db.saveRun({ ...run, state: 'idle' });
  await restarted;
  expect(screen.restarts).toBe(1);
});
