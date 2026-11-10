import { z } from 'zod';
import type { HermesRuntime } from './hermes/runtime';
import { sessionCommandNames } from './session-commands';
import { controlCommandNames } from './command-controls';
import { hostCommandNames } from './host-commands';
import { clientCommands, pageCommands } from './command-client';
const catalogSchema = z.object({
  pairs: z.array(z.tuple([z.string(), z.string()])),
  commands: z.record(z.string(), z.object({ desktop: z.string().nullable().optional() })),
  skills: z.record(z.string(), z.unknown()),
  canon: z.record(z.string(), z.string()),
  categories: z.array(
    z.object({ name: z.string(), pairs: z.array(z.tuple([z.string(), z.string()])) }),
  ),
  warning: z.string().optional(),
});
const gatewayCommands = new Set(
  `help commands status context version whoami usage insights
  profile diff memory kanban topup suggestions bundles skills title goal subgoal loop heartbeat
  review refine debug curator login autoprune plan learn init moa blueprint egress reasoning voice
  approvals codex-runtime footer busy verbose yolo fast personality approve deny toolsets platforms cron`
    .split(/\s+/)
    .map((name) => '/' + name),
);
const adaptedCommands = new Set([
  ...clientCommands,
  ...sessionCommandNames,
  ...controlCommandNames,
  ...hostCommandNames,
  ...Object.keys(pageCommands),
  '/history',
  '/agents',
  '/tools',
  '/reload-skills',
  '/reload',
  '/prompt',
  '/palette',
  '/pet',
  '/login',
  '/skills',
  '/cron',
  '/help',
  '/heartbeat',
  '/moa',
  '/stop',
]);
const unavailableReasons: Record<string, string> = {
  '/handoff': 'Hermes v0.22.5 does not expose handoff on canonical gateway sessions.',
  '/mouse': 'Terminal mouse-capture setting. App mouse and touch use native controls.',
  '/indicator': 'Terminal prompt indicator. App uses its own running-state display.',
};
const appDescriptions: Record<string, string> = {
  '/redraw': 'Refresh this App and synchronize messages without replaying tasks.',
  '/prompt': 'Prefill the App composer without sending (usage: /prompt [text]).',
  '/rollback':
    'Read filesystem checkpoints (usage: /rollback [list | diff <checkpoint>]). Restore is not offered.',
  '/snapshot':
    'Create a private native backup (usage: /snapshot [create]). Restore/prune are not offered.',
  '/export': 'Export this Bot’s shareable profile to a file card (usage: /export).',
  '/import': 'Open the App form to import a profile archive as a new Bot (usage: /import).',
  '/stop': 'Stop a selected task; /stop all stops all work in this chat.',
  '/agents':
    'List native child/process IDs; tail, steer or stop a child, kill a process, pause/resume spawning.',
  '/journey': 'Browse or edit native learning entries (usage: /journey [list | edit <entry-id>]).',
  '/queue':
    'Queue a native input, inspect, cancel, edit or steer it (usage: /queue <prompt> | list | rm N | edit N <prompt> | steer N). Edits move to the FIFO tail.',
  '/model':
    'Open Bot model settings, or pick a session model: /model <id> [--provider name] [--reasoning level].',
  '/skin':
    'Set this App’s appearance (usage: /skin [light|dark|system]). Terminal skins do not apply.',
  '/wake':
    'Open this device’s microphone and native Hermes wake-word controls (usage: /wake [status]). The page shows missing native dependencies.',
  '/image': 'Attach a device image: /image [Windows path]; without a path opens the system picker.',
  '/update':
    'Check native Hermes updates (usage: /update [check]). Installation uses the managed Node release process.',
  '/quit':
    'Quit the Windows App or background Android; keep server tasks and history (usage: /quit).',
  '/heartbeat':
    'Read, pause or stop the native heartbeat (usage: /heartbeat [status|pause|stop]). Hermes v0.22.5 does not trigger it for local gateway sessions.',
  '/login': 'Open model authorization and custom API sources (usage: /login).',
  '/moa':
    'Run one prompt with the profile’s native MoA preset; the next turn keeps its normal model (usage: /moa <prompt>). Configure the preset in Bot settings.',
};
export async function discoverCommands(hermes: HermesRuntime, botId: string) {
  const catalog = catalogSchema.parse(
    await hermes.gateway(botId).rpc('commands.catalog', { profile: botId }),
  );
  const dynamic = new Set(
    catalog.categories
      .filter((category) => ['User commands', 'Plugin commands'].includes(category.name))
      .flatMap((category) => category.pairs.map(([name]) => name)),
  );
  return {
    commands: catalog.pairs
      .filter(
        ([name]) =>
          !['/new', '/resume', '/clear', '/reset', '/branch', '/fork', '/sessions'].includes(name),
      )
      .filter(([name]) => adaptedCommands.has(name) || catalog.commands[name]?.desktop !== 'hidden')
      .map(([name, description]) => ({
        name,
        description: appDescriptions[name] ?? description,
        availability: adaptedCommands.has(name)
          ? 'app'
          : gatewayCommands.has(name) || dynamic.has(name) || Object.hasOwn(catalog.skills, name)
            ? 'available'
            : catalog.commands[name]?.desktop === 'terminal' || name === '/mouse'
              ? 'terminal'
              : 'not-integrated',
        ...(unavailableReasons[name] ? { unavailableReason: unavailableReasons[name] } : {}),
        skill: Object.hasOwn(catalog.skills, name) || Object.hasOwn(catalog.skills, name.slice(1)),
      })),
    warning: catalog.warning ?? '',
    aliases: catalog.canon,
  };
}

export function parseCommand(command: string, aliases: Record<string, string> = {}) {
  const typedName = command.split(/\s/, 1)[0]!.toLowerCase();
  return { name: aliases[typedName] ?? typedName, arg: command.slice(typedName.length).trim() };
}
