import { platform } from 'node:os';
import type { RpcResult } from '@nekodot/protocol';
import type { HermesRuntime } from './hermes/runtime';
import type { BotService } from './bots';

type Capabilities = RpcResult<'desktop.status'>;
type DesktopStatus = NonNullable<Capabilities['desktopControl']>;

/**
 * What this node can do with screens: Hermes-owned Bot displays on Linux servers, or Hermes
 * `computer_use` on the real desktop of the computer the desktop client hosts it on. Readiness
 * and per-Bot enablement come from Hermes' own REST surface; nothing is installed or granted here.
 */
export class DesktopControl {
  private status: DesktopStatus = {
    platformSupported: false,
    installed: false,
    ready: null,
    canGrant: false,
    detail: 'not checked',
  };
  constructor(
    private readonly hermes: HermesRuntime,
    private readonly bots: BotService,
    readonly desktop: boolean,
    private readonly screens: boolean,
  ) {}

  capabilities(): Capabilities {
    return {
      platform: platform(),
      computerUse: this.screens,
      host: this.desktop ? 'desktop' : 'server',
      desktopControl: this.desktop ? this.status : null,
    };
  }

  async refresh(): Promise<Capabilities> {
    if (!this.desktop) return this.capabilities();
    const raw = await this.hermes.management.request<{
      platform_supported?: boolean;
      installed?: boolean;
      ready?: boolean | null;
      can_grant?: boolean;
      error?: string | null;
      checks?: { label?: string; status?: string; message?: string }[];
    }>('/api/tools/computer-use/status', 'default');
    const problem = raw.checks?.find(
      (check) => check.status === 'fail' || check.status === 'error',
    );
    this.status = {
      platformSupported: raw.platform_supported === true,
      installed: raw.installed === true,
      ready: raw.ready ?? null,
      canGrant: raw.can_grant === true,
      detail: raw.error ?? problem?.message ?? '',
    };
    return this.capabilities();
  }

  /** Reads or switches the Bot's native `computer_use` toolset through Hermes' toolset writer. */
  async bot(botId: string, enabled?: boolean) {
    this.bots.get(botId);
    if (enabled !== undefined)
      await this.hermes.management.request('/api/tools/toolsets/computer_use', botId, {
        method: 'PUT',
        body: JSON.stringify({ enabled }),
      });
    const toolsets = await this.hermes.management.request<{ name: string; enabled: boolean }[]>(
      '/api/tools/toolsets',
      botId,
    );
    return { enabled: toolsets.some((row) => row.name === 'computer_use' && row.enabled) };
  }
}
