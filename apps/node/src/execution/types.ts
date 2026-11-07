import type { GatewayFrame } from '../hermes/gateway';

export interface NativePrompt {
  kind: 'approval' | 'clarify';
  prompt_id: string;
  execution_generation: number;
  choices?: string[];
  command?: string;
  description?: string;
  question?: string;
  multi_select?: boolean;
}

export interface NativeAdmission {
  admission_id: string;
  status: 'queued' | 'started' | 'unknown' | 'terminal';
  outcome?: string | null;
  execution_generation?: number | null;
  result?: { final_response?: string; failed?: boolean; interrupted?: boolean };
}

export interface NativeReplay {
  events: GatewayFrame[];
  replay_epoch: string;
  latest_seq: number;
  snapshot_required: boolean;
  truncated: boolean;
}
