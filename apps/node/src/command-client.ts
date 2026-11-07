import type { CommandResult } from './session-commands';
import { NodeFault } from './fault';
export const clientCommands = new Set([
  '/copy',
  '/image',
  '/paste',
  '/focus',
  '/density',
  '/timestamps',
  '/skin',
  '/statusbar',
  '/battery',
  '/redraw',
  '/quit',
]);
export const pageCommands: Record<string, string> = {
  '/config': 'settings',
  '/model': 'model',
  '/plugins': 'plugins',
  '/subscription': 'subscription',
  '/journey': 'journey',
  '/hatch': 'hatch',
  '/import': 'profile-import',
  '/wake': 'voice',
};
export function clientAction(name: string, arg: string): CommandResult | undefined {
  if (clientCommands.has(name)) return { type: 'client', target: name, message: arg };
  if (name === '/login' && !arg) return { type: 'navigate', target: 'sources' };
  if (name === '/wake' && !arg) return { type: 'navigate', target: 'voice' };
  if (name === '/hatch') return { type: 'navigate', target: 'hatch', message: arg };
  if (name === '/journey') {
    if (!arg || arg === 'list') return { type: 'navigate', target: 'journey' };
    if (arg.startsWith('edit '))
      return { type: 'navigate', target: 'journey', message: arg.slice(5).trim() };
    throw new NodeFault(
      'invalid_params',
      'Usage: /journey [list|edit <entry-id>]. Deletion is not offered.',
    );
  }
  if (name === '/prompt' || name === '/palette')
    return { type: 'prefill' as const, message: name === '/palette' ? '/' : arg };
}
