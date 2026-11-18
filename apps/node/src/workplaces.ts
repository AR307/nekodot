import { chmod, readFile, stat } from 'node:fs/promises';
import { setTimeout as delay } from 'node:timers/promises';
import { isAbsolute, relative, resolve } from 'node:path';
import { parseDocument } from 'yaml';
import { z } from 'zod';
import { workplaceSchema, type PairingCode, type Workplace } from '@nekodot/protocol';
import type { NodeDatabase } from './database';
import type { HermesRuntime } from './hermes/runtime';
import { NodeFault } from './fault';

/**
 * The command an approval card shows. Hermes names a plugin's approval rule only by the
 * tool; for the sandbox plugin the user approves its own sentence, the card's prompt.
 */
export function approvalCommand(command?: string) {
  return command?.startsWith('<nekodot_sandbox>') ? undefined : command;
}

/** A Hermes `terminal.<key>`; credentials never go here, they go to .env through a card. */
const settingKey = z
  .string()
  .regex(/^[a-z0-9_]{1,40}$/)
  .refine((key) => !/token|secret|password|passphrase|api_key|credential/.test(key), {
    message: 'Credentials go to .env through a confidential card, not into settings',
  });
const settingValue = z.union([
  z
    .string()
    .max(500)
    .regex(/^[^\r\n]*$/),
  z.number(),
  z.boolean(),
]);
const requestSchema = z
  .strictObject({
    action: z.literal('sandbox'),
    operation: z.enum(['status', 'use', 'home', 'computer']),
    botId: z.string(),
    token: z.string(),
    sessionId: z.string().optional(),
    label: workplaceSchema.shape.label.optional(),
    backend: workplaceSchema.shape.backend
      .refine((backend) => backend !== 'local', { message: 'Use home to come back' })
      .optional(),
    settings: z.record(settingKey, settingValue).optional(),
    name: z
      .string()
      .trim()
      .min(1)
      .max(40)
      .regex(/^\P{Cc}+$/u)
      .optional(),
  })
  .superRefine((value, ctx) => {
    if (value.operation === 'use' && (!value.label || !value.backend))
      ctx.addIssue({ code: 'custom', message: 'use needs label and backend' });
    if (value.operation === 'computer' && !value.name)
      ctx.addIssue({ code: 'custom', message: 'computer needs name' });
  });
type Request = z.infer<typeof requestSchema>;

/** What a move changed, so coming back restores exactly that. */
interface Saved extends Workplace {
  previous: Record<string, string | number | boolean | null>;
}

/**
 * Where each Bot's hands work: its own computer, or a sandbox it set up itself with the
 * user's key. Hermes owns the rest: `terminal.backend` moves commands and files, and its
 * screen, browser and computer_use follow a backend that can carry them (ssh, docker).
 */
export class Workplaces {
  /** Set by the Relay connection: a pairing code for this node's owner. */
  pairing?: () => Promise<PairingCode>;
  onError: (message: string) => void = () => {};
  private restarting?: Promise<void>;
  constructor(
    private readonly database: NodeDatabase,
    private readonly hermes: HermesRuntime,
    /** How long to wait between looks for a moment when no Dot is working. */
    private readonly poll = 2000,
  ) {}

  get(botId: string): Workplace | null {
    const saved = this.database.setting<Saved>('workplace:' + botId);
    return saved ? { label: saved.label, backend: saved.backend } : null;
  }

  /** The bridge from the Bot's nekodot-sandbox plugin. */
  async local(value: unknown) {
    const p = requestSchema.parse(value);
    if (!this.database.bot(p.botId)) throw new NodeFault('not_found', 'Bot not found');
    const token = await readFile(
      resolve(this.hermes.profileHome(p.botId), 'plugins', 'nekodot-secrets', 'bridge.token'),
      'utf8',
    );
    if (p.token !== token.trim())
      throw new NodeFault('forbidden', 'Profile does not own this request');
    switch (p.operation) {
      case 'status':
        return { workplace: this.get(p.botId) };
      case 'use':
        return {
          workplace: await this.use(p),
          note: 'Approved and saved. Hermes on this computer restarts as soon as no Dot is working, and from then on your commands, files, browser and screen run there. Tell the user it is done and finish this turn. Use home to come back.',
        };
      case 'home':
        await this.home(p.botId);
        return {
          workplace: null,
          note: 'Back on this computer once Hermes restarts, as soon as no Dot is working.',
        };
      case 'computer':
        return this.computer(p.name!);
    }
  }

  private async use(p: Request) {
    const settings = { ...p.settings };
    if (typeof settings.ssh_key === 'string')
      settings.ssh_key = await this.sshKey(p.botId, settings.ssh_key);
    await this.stopScreen(p.botId);
    // Moving from one sandbox to another starts from this computer, so home restores the original.
    await this.home(p.botId);
    const config = await this.terminalConfig(p.botId);
    const keys = ['backend', ...Object.keys(settings).filter((key) => key !== 'backend')];
    const saved: Saved = {
      label: p.label!,
      backend: p.backend!,
      previous: Object.fromEntries(keys.map((key) => [key, config[key] ?? null])),
    };
    // Saved first: a move that fails halfway can still be undone with home.
    this.database.setSetting('workplace:' + p.botId, saved);
    this.restartWhenIdle();
    await this.set(p.botId, 'backend', p.backend!);
    for (const [key, value] of Object.entries(settings))
      if (key !== 'backend') await this.set(p.botId, key, value);
    return { label: saved.label, backend: saved.backend };
  }

  /** Brings the Bot's hands back to this computer: every setting as it was before the move. */
  async home(botId: string) {
    if (!this.database.bot(botId)) throw new NodeFault('not_found', 'Bot not found');
    const saved = this.database.setting<Saved>('workplace:' + botId);
    if (!saved) return;
    await this.stopScreen(botId);
    const config = await this.terminalConfig(botId);
    for (const [key, value] of Object.entries(saved.previous)) {
      if (value !== null) await this.set(botId, key, value);
      else if (key in config) await this.hermes.cli(botId, ['config', 'unset', 'terminal.' + key]);
    }
    this.database.deleteSetting('workplace:' + botId);
    this.restartWhenIdle();
  }

  /**
   * Hermes applies a changed terminal backend only in a fresh process: a running one keeps every
   * terminal environment it built, the screen's among them, on the old backend. So it restarts at
   * the first moment no Dot is working, never cutting a turn short.
   */
  restartWhenIdle() {
    this.restarting ??= (async () => {
      while (this.database.runs().length) await delay(this.poll);
      await this.hermes.restart();
    })()
      .catch((error: unknown) =>
        this.onError(
          `Hermes did not restart after a Dot moved: ${error instanceof Error ? error.message : error}`,
        ),
      )
      .finally(() => (this.restarting = undefined));
    return this.restarting;
  }

  private async computer(name: string) {
    if (!this.pairing) throw new NodeFault('unavailable', 'Relay is disconnected');
    const code = await this.pairing();
    return {
      command: `${code.sandboxCommand} --name '${name.replaceAll("'", "'\\''")}'`,
      expiresAt: code.expiresAt,
      note: 'Run this as root inside the sandbox: bash, curl and outbound HTTPS to the Relay are needed. The pairing code is single-use and lasts 30 minutes. Nothing wakes this computer if its provider stops the sandbox; tell the user.',
    };
  }

  /**
   * The screen moves with the hands. One left running where the Dot no longer works keeps that
   * machine's memory, or holds a sandbox's display another Dot may need.
   */
  private async stopScreen(botId: string) {
    const status = await this.hermes.management.rpc<{ running: boolean }>('display.status', {
      profile: botId,
    });
    if (status.running)
      await this.hermes.management.rpc('display.stop', { profile: botId, force: true }, 120_000);
  }

  /** Hermes reads TERMINAL_* from .env as well, so only its own CLI writes both. */
  private set(botId: string, key: string, value: string | number | boolean) {
    return this.hermes.cli(botId, ['config', 'set', 'terminal.' + key, String(value)]);
  }

  private async terminalConfig(botId: string): Promise<Record<string, string | number | boolean>> {
    const raw = await readFile(resolve(this.hermes.profileHome(botId), 'config.yaml'), 'utf8');
    const terminal = (parseDocument(raw, { compat: 'yaml-1.1' }).toJS() as Record<string, unknown>)
      ?.terminal;
    return terminal && typeof terminal === 'object'
      ? (terminal as Record<string, string | number | boolean>)
      : {};
  }

  /** A private key the Bot made in its own profile; ssh refuses one others can read. */
  private async sshKey(botId: string, path: string) {
    const home = this.hermes.profileHome(botId);
    const key = resolve(home, path);
    const inside = relative(home, key);
    if (!inside || inside.startsWith('..') || isAbsolute(inside))
      throw new NodeFault('invalid_params', 'ssh_key must be a file in this Dot’s profile');
    if (
      !(await stat(key).then(
        (s) => s.isFile(),
        () => false,
      ))
    )
      throw new NodeFault('invalid_params', 'ssh_key does not exist');
    await chmod(key, 0o600);
    return key;
  }
}
