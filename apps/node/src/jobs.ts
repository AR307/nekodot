import { randomUUID } from 'node:crypto';
import type { JobContent, LiveEvent, Message } from '@nekodot/protocol';
import type { NodeDatabase, RunRecord } from './database';
import { HermesGatewayError } from './hermes/gateway';
import type { HermesRuntime } from './hermes/runtime';
import type { BotSecrets } from './secrets';
import { NodeFault } from './fault';

/** What a job's progress line says. Counts and speed stay as the job prints them. */
export interface JobProgress {
  label?: string;
  done?: string;
  total?: string;
  percent?: number;
  rate?: string;
  elapsedSeconds?: number;
  etaSeconds?: number;
}

const ESC = String.fromCharCode(27);

/** Output without terminal escape sequences (colours, cursor moves). */
function plain(text: string) {
  const [first = '', ...rest] = text.split(ESC);
  return (
    first + rest.map((part) => part.replace(/^(?:\[[0-?]*[ -/]*[@-~]|[@-Z\\-_])/, '')).join('')
  );
}

const units: [RegExp, number][] = [
  [/^(?:d|days?|天)$/i, 86400],
  [/^(?:h|hrs?|hours?|小时|时)$/i, 3600],
  [/^(?:m|mins?|minutes?|分钟|分)$/i, 60],
  [/^(?:s|secs?|seconds?|秒)$/i, 1],
];

/** Seconds in a printed duration: 1:02:03, 00:37, 2m10s, 1h 5m, 3 min, 2分10秒. */
export function durationSeconds(text: string): number | undefined {
  const value = text.trim();
  const clock = /^(?:(\d+):)?(\d{1,2}):(\d{2})$/.exec(value);
  if (clock) return Number(clock[1] ?? 0) * 3600 + Number(clock[2]) * 60 + Number(clock[3]);
  const parts = [...value.matchAll(/(\d+(?:\.\d+)?)\s*([a-z]+|天|小时|时|分钟|分|秒)/gi)];
  if (
    !parts.length ||
    parts
      .map((p) => p[0])
      .join('')
      .replace(/\s/g, '') !== value.replace(/\s/g, '')
  )
    return undefined;
  let seconds = 0;
  for (const [, amount, unit] of parts) {
    const scale = units.find(([pattern]) => pattern.test(unit!))?.[1];
    if (scale === undefined) return undefined;
    seconds += Number(amount) * scale;
  }
  return seconds;
}

const count = (text: string) => Number(text.replace(/,/g, ''));
const clean = (text: string | undefined, max: number) => {
  const value = text?.trim().replace(/\s+/g, ' ');
  return value ? value.slice(0, max) : undefined;
};
const duration = String.raw`\d+:\d{2}(?::\d{2})?|(?:\d+(?:\.\d+)?\s*(?:days?|d|hours?|hrs?|h|minutes?|mins?|m|seconds?|secs?|s|天|小时|时|分钟|分|秒)\s*)+`;

// tqdm: "Collecting pages:  45%|████▌     | 450/1000 [00:30<00:37, 14.95it/s]"
const tqdm = new RegExp(
  String.raw`^(?:(.*?):\s*)?(\d{1,3})%\|[^|]*\|\s*([\d.]+[kMGTPEZY]?)\/([\d.]+[kMGTPEZY]?)\s*\[([\d:]+)<([\d:]+|\?)(?:,\s*([^,\]]*))?[^\]]*\]`,
);
// tqdm without a total: "Scraping: 450it [00:30, 14.95it/s]"
const tqdmOpen = new RegExp(
  String.raw`^(?:(.*?):\s*)?([\d.]+[kMGTPEZY]?)[A-Za-z]*\s*\[([\d:]+),\s*((?:[\d.]+|\?)[A-Za-z]*\/[A-Za-z]+)[^\]]*\]`,
);
const etaWord = new RegExp(
  String.raw`(?:\bETA\b|剩余时间|剩余|剩下)\s*[:：=]?\s*(${duration})`,
  'i',
);
const elapsedWord = new RegExp(
  String.raw`(?:\belapsed\b|已用时?|用时)\s*[:：=]?\s*(${duration})`,
  'i',
);
const percentPart = /(\d{1,3}(?:\.\d+)?)\s*%/;
const countPart = /(\d[\d,]*(?:\.\d+)?)\s*\/\s*(\d[\d,]*(?:\.\d+)?)/;
const ratePart = /(\d+(?:\.\d+)?\s*[A-Za-z]+\/s)\b/;

/** One line as a progress line, in tqdm's layout or any line with an ETA and how far it is. */
function progressLine(line: string): JobProgress | undefined {
  const bar = tqdm.exec(line);
  if (bar) {
    return {
      label: clean(bar[1], 120),
      percent: Math.min(100, Number(bar[2])),
      done: clean(bar[3], 24),
      total: clean(bar[4], 24),
      elapsedSeconds: durationSeconds(bar[5]!),
      ...(bar[6] !== '?' ? { etaSeconds: durationSeconds(bar[6]!) } : {}),
      ...(bar[7] && !bar[7].startsWith('?') ? { rate: clean(bar[7], 32) } : {}),
    };
  }
  const open = tqdmOpen.exec(line);
  if (open) {
    return {
      label: clean(open[1], 120),
      done: clean(open[2], 24),
      elapsedSeconds: durationSeconds(open[3]!),
      ...(!open[4]!.startsWith('?') ? { rate: clean(open[4], 32) } : {}),
    };
  }
  const eta = etaWord.exec(line);
  const percent = percentPart.exec(line);
  const counted = countPart.exec(line);
  if (!eta || (!percent && !counted)) return undefined;
  const first = Math.min(
    ...[percent, counted]
      .filter((match): match is RegExpExecArray => match !== null)
      .map((match) => match.index),
  );
  const done = counted ? count(counted[1]!) : undefined;
  const total = counted ? count(counted[2]!) : undefined;
  const share = percent
    ? Number(percent[1])
    : done !== undefined && total
      ? (done / total) * 100
      : undefined;
  const elapsed = elapsedWord.exec(line);
  const rate = ratePart.exec(line);
  return {
    label: clean(line.slice(0, first).replace(/[\s:：|([{-]+$/, ''), 120),
    ...(counted ? { done: clean(counted[1], 24), total: clean(counted[2], 24) } : {}),
    ...(share !== undefined ? { percent: Math.min(100, Math.round(share * 10) / 10) } : {}),
    etaSeconds: durationSeconds(eta[1]!),
    ...(elapsed ? { elapsedSeconds: durationSeconds(elapsed[1]!) } : {}),
    ...(rate ? { rate: clean(rate[1], 32) } : {}),
  };
}

/** The newest progress line in a job's output, which redraws it with carriage returns. */
export function jobProgress(output: string): JobProgress | undefined {
  const lines = plain(output).split(/[\r\n]+/);
  for (let i = lines.length - 1; i >= Math.max(0, lines.length - 200); i--) {
    const line = lines[i]!.trim();
    const progress = line ? progressLine(line) : undefined;
    if (progress) return progress;
  }
  return undefined;
}

/** A job named by its script when its progress line gives no description. */
export function commandLabel(command: string) {
  const script = /[\w.-]+\.(?:py|js|mjs|cjs|ts|sh|rb|pl|go|php|r)\b/i.exec(command)?.[0];
  return script ?? clean(command.split('\n')[0], 80) ?? 'job';
}

/** A Hermes background process as `process.list` reports it. */
interface NativeProcess {
  session_id: string;
  command?: string;
  status: string;
  exit_code?: number | null;
  started_epoch?: number | null;
  exited_at?: number | null;
  completion_reason?: string | null;
  output_tail?: string | null;
}

/** A process a Dot's terminal call left running, followed until it ends. */
interface Job {
  processId: string;
  botId: string;
  conversationId: string;
  /** The Hermes session that owns the process. */
  sessionId: string;
  command?: string;
  startedAt?: number;
  /** The card, once the job printed progress. */
  messageId?: string;
  last?: JobProgress;
  misses: number;
}

const saved = 'background-jobs';

/**
 * Long jobs a Dot runs in the background, shown in the chat that started them as a card with
 * their progress: what their progress line says, read from Hermes's own view of the process,
 * so it works wherever the Dot's commands run. A job that never prints progress gets no card.
 */
export class BackgroundJobs {
  private jobs: Job[];
  private timer?: ReturnType<typeof setTimeout>;
  private polling?: Promise<void>;
  private closed = false;
  private failure?: string;
  /** When each card was last saved and what it last showed; live updates fill the time between. */
  private readonly savedAt = new Map<string, number>();
  private readonly shown = new Map<string, string>();

  constructor(
    private readonly database: NodeDatabase,
    private readonly hermes: HermesRuntime,
    private readonly secrets: BotSecrets,
    private readonly onLive: (event: LiveEvent) => void,
    private readonly interval = 2000,
    private readonly saveEvery = 10_000,
  ) {
    this.jobs = database.setting<Job[]>(saved) ?? [];
  }

  /** A terminal call in [run] left [processId] running in the background. */
  track(run: RunRecord, processId: string) {
    const sessionId = run.storedSessionId ?? run.sessionId;
    if (!sessionId || this.jobs.some((job) => job.processId === processId)) return;
    this.jobs.push({
      processId,
      botId: run.botId,
      conversationId: run.conversationId,
      sessionId,
      misses: 0,
    });
    this.save();
    this.schedule();
  }

  /** Follows the jobs that were running when the node last stopped. */
  resume() {
    this.schedule();
  }

  /** Stops the job a card shows; its card says so once Hermes reports it ended. */
  async stop(messageId: string) {
    const job = this.jobs.find((item) => item.messageId === messageId);
    if (!job) throw new NodeFault('not_found', 'This job is no longer running');
    await this.hermes
      .gateway(job.botId)
      .rpc('process.kill', { session_id: job.sessionId, process_id: job.processId });
  }

  async close() {
    this.closed = true;
    clearTimeout(this.timer);
    this.timer = undefined;
    await this.polling;
  }

  private schedule() {
    if (this.closed || this.timer || this.polling || !this.jobs.length) return;
    this.timer = setTimeout(() => {
      this.timer = undefined;
      this.polling = this.poll()
        .catch((error: unknown) => {
          const message = error instanceof Error ? error.message : String(error);
          if (message !== this.failure) console.warn('Background job progress failed:', message);
          this.failure = message;
        })
        .finally(() => {
          this.polling = undefined;
          this.schedule();
        });
    }, this.interval);
  }

  /** One look at every followed job, a `process.list` per Hermes session. */
  async poll() {
    const sessions = new Map<string, Job[]>();
    for (const job of this.jobs) {
      const key = job.botId + '\n' + job.sessionId;
      sessions.set(key, [...(sessions.get(key) ?? []), job]);
    }
    for (const jobs of sessions.values()) {
      const processes = await this.list(jobs[0]!.botId, jobs[0]!.sessionId).catch(() => undefined);
      for (const job of jobs) {
        const process = processes?.find((item) => item.session_id === job.processId);
        if (process) {
          job.misses = 0;
          this.update(job, process);
        } else if (++job.misses >= (processes ? 3 : 30)) {
          // Hermes no longer knows the process (it restarted), or cannot be asked for a minute.
          this.end(job);
        }
      }
    }
    this.save();
  }

  private async list(botId: string, sessionId: string) {
    const gateway = this.hermes.gateway(botId);
    const read = () =>
      gateway.rpc<{ processes: NativeProcess[] }>('process.list', { session_id: sessionId });
    try {
      return (await read()).processes;
    } catch (error) {
      // A session Hermes let go of is live again once resumed, and still owns its processes.
      if (!(error instanceof HermesGatewayError) || error.reason !== 'not_found') throw error;
      await gateway.rpc('session.resume', {
        session_id: sessionId,
        defer_history: true,
        omit_messages: true,
      });
      return (await read()).processes;
    }
  }

  private update(job: Job, process: NativeProcess) {
    job.command ??= process.command;
    if (job.startedAt === undefined && process.started_epoch)
      job.startedAt = process.started_epoch * 1000;
    const progress = jobProgress(process.output_tail ?? '') ?? job.last;
    job.last = progress;
    const running = process.status === 'running';
    if (progress) {
      const state: JobContent['state'] = running
        ? 'running'
        : process.exit_code === 0 && process.completion_reason !== 'killed'
          ? 'done'
          : ['killed', 'lost'].includes(process.completion_reason ?? '')
            ? 'stopped'
            : 'failed';
      const ended =
        !running && process.exited_at ? process.exited_at * 1000 : running ? Date.now() : undefined;
      this.show(job, this.content(job, progress, state, ended, process.exit_code));
    }
    if (!running) this.forget(job);
  }

  private content(
    job: Job,
    progress: JobProgress,
    state: JobContent['state'],
    endedAt: number | undefined,
    exitCode: number | null | undefined,
  ): JobContent {
    const elapsed =
      progress.elapsedSeconds ??
      (job.startedAt !== undefined && endedAt !== undefined
        ? Math.max(0, (endedAt - job.startedAt) / 1000)
        : undefined);
    const percent = progress.percent;
    // Printed or, from how far it is in how long, estimated.
    const eta =
      state !== 'running'
        ? undefined
        : (progress.etaSeconds ??
          (percent && percent < 100 && elapsed !== undefined
            ? (elapsed * (100 - percent)) / percent
            : undefined));
    return {
      botId: job.botId,
      label: this.secrets
        .scrub(job.botId, progress.label ?? commandLabel(job.command ?? ''))
        .slice(0, 200),
      state,
      ...(progress.done !== undefined ? { done: progress.done } : {}),
      ...(progress.total !== undefined ? { total: progress.total } : {}),
      ...(percent !== undefined ? { percent: Math.max(0, Math.min(100, percent)) } : {}),
      ...(progress.rate !== undefined ? { rate: progress.rate } : {}),
      ...(elapsed !== undefined ? { elapsedSeconds: Math.round(elapsed) } : {}),
      ...(eta !== undefined ? { etaSeconds: Math.round(eta) } : {}),
      ...(state !== 'running' && typeof exitCode === 'number' ? { exitCode } : {}),
    };
  }

  /** The card: made once, saved now and then, live in between, and saved once it ends. */
  private show(job: Job, content: JobContent) {
    const json = JSON.stringify(content);
    if (job.messageId && this.shown.get(job.messageId) === json) return;
    const ended = content.state !== 'running';
    const status: Message['status'] = !ended
      ? 'streaming'
      : content.state === 'done'
        ? 'done'
        : content.state === 'stopped'
          ? 'cancelled'
          : 'failed';
    const now = Date.now();
    const existing = job.messageId ? this.database.message(job.messageId) : undefined;
    if (existing?.kind !== 'job') {
      const message: Message = {
        messageId: randomUUID(),
        conversationId: job.conversationId,
        seq: this.database.head(),
        author: { type: 'bot', id: job.botId },
        kind: 'job',
        status,
        createdAt: new Date().toISOString(),
        content,
      };
      this.database.putMessage(message);
      job.messageId = message.messageId;
      this.savedAt.set(message.messageId, now);
    } else if (ended || now - (this.savedAt.get(existing.messageId) ?? 0) >= this.saveEvery) {
      this.database.putMessage({ ...existing, status, content });
      this.savedAt.set(existing.messageId, now);
    } else {
      this.onLive({
        kind: 'job',
        conversationId: job.conversationId,
        messageId: existing.messageId,
        content,
      });
    }
    this.shown.set(job.messageId!, json);
  }

  /** The process is gone without a word from Hermes: its card says it stopped. */
  private end(job: Job) {
    const message = job.messageId ? this.database.message(job.messageId) : undefined;
    if (message?.kind === 'job' && message.content.state === 'running') {
      const content: JobContent = { ...message.content, state: 'stopped' };
      delete content.etaSeconds;
      this.database.putMessage({ ...message, status: 'cancelled', content });
    }
    this.forget(job);
  }

  private forget(job: Job) {
    this.jobs = this.jobs.filter((item) => item !== job);
    if (job.messageId) {
      this.savedAt.delete(job.messageId);
      this.shown.delete(job.messageId);
    }
  }

  private save() {
    this.database.setSetting(saved, this.jobs);
  }
}
