import type { FlowSnapshot, FlowStep } from '@nekodot/protocol';
import type { GroupChainRecord, NodeDatabase, RunRecord } from './database';
import { NodeFault } from './fault';

const tools: Record<string, FlowStep['kind']> = {
  web_search: 'search',
  search_files: 'search',
  session_search: 'search',
  web_extract: 'browser',
  browser_exec: 'browser',
  browser_cdp: 'browser',
  browser_dialog: 'browser',
  browser_vault: 'browser',
  browser_navigate: 'browser',
  browser_click: 'browser',
  browser_type: 'browser',
  browser_snapshot: 'browser',
  browser_screenshot: 'browser',
  browser_scroll: 'browser',
  read_file: 'read',
  write_file: 'write',
  patch: 'write',
  execute_code: 'code',
  terminal: 'terminal',
};
const active = (step: FlowStep) => step.state === 'running' || step.state === 'waiting';

/** A display projection of admitted work, never an execution authority. */
export class ExecutionFlows {
  private readonly values = new Map<string, FlowSnapshot>();
  constructor(private readonly database: NodeDatabase) {}

  private load(conversationId: string) {
    let value = this.values.get(conversationId);
    if (!value) {
      value = this.database.setting<FlowSnapshot>('flow:' + conversationId);
      if (value) this.values.set(conversationId, value);
    }
    return value;
  }

  get(conversationId: string) {
    const conversation = this.database.conversation(conversationId);
    if (!conversation) throw new NodeFault('not_found', 'Conversation not found');
    const flow = this.load(conversationId);
    if (
      conversation.kind === 'dm' &&
      flow?.sessionId !== this.database.hermesSession(conversationId)?.storedSessionId
    )
      return null;
    return flow ?? null;
  }

  all() {
    return this.database.conversations().flatMap((c) => {
      const flow = this.get(c.conversationId);
      return flow ? [flow] : [];
    });
  }

  start(run: RunRecord) {
    if (!run.runId || !run.storedSessionId || run.queue === 'queued') return;
    const chain = run.groupId ? this.database.chain(run.conversationId) : undefined;
    const flowId = chain?.notificationId ?? run.runId;
    let flow = this.load(run.conversationId);
    if (flow?.steps.some((step) => step.runId === run.runId)) return;
    const reset = flow?.flowId !== flowId;
    if (reset || !flow) {
      flow = {
        flowId,
        conversationId: run.conversationId,
        ...(run.groupId ? {} : { sessionId: run.storedSessionId }),
        state: 'running',
        queuedBotIds: [],
        steps: [],
        seq: 0,
      };
      this.values.set(run.conversationId, flow);
    }
    const bot = this.step(run, 'bot', run.runId + ':bot', this.frontier(flow));
    const thinking = this.step(run, 'thinking', run.runId + ':thinking:start', [bot.stepId]);
    flow.steps.push(bot, thinking);
    flow.state = 'running';
    flow.queuedBotIds = [...(chain?.queue ?? [])];
    this.database.saveFlow(flow, [bot, thinking], reset);
  }

  sessionChanged(conversationId: string) {
    const previous = this.load(conversationId);
    const sessionId = this.database.hermesSession(conversationId)?.storedSessionId;
    if (!previous?.sessionId || previous.sessionId === sessionId || !sessionId) return;
    const flow: FlowSnapshot = {
      flowId: 'session:' + sessionId,
      conversationId,
      sessionId,
      state: 'done',
      queuedBotIds: [],
      steps: [],
      seq: 0,
    };
    this.values.set(conversationId, flow);
    this.database.saveFlow(flow, [], true);
  }

  private owned(run: RunRecord) {
    const flow = this.load(run.conversationId);
    return flow?.steps.some((s) => s.runId === run.runId) ? flow : undefined;
  }

  private step(run: RunRecord, kind: FlowStep['kind'], stepId: string, after: string[]): FlowStep {
    return {
      stepId,
      runId: run.runId!,
      sessionId: run.storedSessionId!,
      botId: run.botId,
      kind,
      state: 'running',
      after,
    };
  }

  private frontier(flow: FlowSnapshot) {
    const referenced = new Set(flow.steps.flatMap((s) => s.after));
    return flow.steps.filter((s) => !referenced.has(s.stepId)).map((s) => s.stepId);
  }

  phase(run: RunRecord, kind: 'thinking' | 'reply', seq: number, messageId?: string) {
    const flow = this.owned(run);
    if (
      !flow ||
      flow.steps.some(
        (s) =>
          s.runId === run.runId &&
          active(s) &&
          (s.tool || s.kind === 'approval' || s.kind === 'question'),
      )
    )
      return;
    if (flow.steps.some((s) => s.runId === run.runId && s.kind === kind && active(s))) return;
    const changed = this.endPhases(flow, run);
    const step = this.step(run, kind, `${run.runId}:${kind}:${seq}`, this.frontier(flow));
    if (messageId) step.messageId = messageId;
    flow.steps.push(step);
    flow.state = 'running';
    this.database.saveFlow(flow, [...changed, step]);
  }

  private endPhases(flow: FlowSnapshot, run: RunRecord) {
    const changed = flow.steps.filter(
      (s) => s.runId === run.runId && (s.kind === 'thinking' || s.kind === 'reply') && active(s),
    );
    for (const s of changed) s.state = 'done';
    return changed;
  }

  tool(run: RunRecord, toolId: string, name: string, messageId: string) {
    const flow = this.owned(run);
    if (!flow) return;
    const id = `${run.runId}:tool:${toolId}`;
    if (flow.steps.some((s) => s.stepId === id)) return;
    const changed = this.endPhases(flow, run);
    const concurrent = flow.steps.find((s) => s.runId === run.runId && s.tool && active(s));
    const step = this.step(
      run,
      tools[name] ?? 'tool',
      id,
      concurrent ? concurrent.after : this.frontier(flow),
    );
    step.tool = name;
    step.messageId = messageId;
    flow.steps.push(step);
    this.database.saveFlow(flow, [...changed, step]);
  }

  toolEnd(run: RunRecord, toolId: string, state: FlowStep['state'], seq: number) {
    const flow = this.owned(run);
    const step = flow?.steps.find((s) => s.stepId === `${run.runId}:tool:${toolId}`);
    if (!flow || !step || !active(step)) return;
    step.state = state;
    this.database.saveFlow(flow, [step]);
    this.phase(run, 'thinking', seq);
  }

  prompt(run: RunRecord, kind: 'approval' | 'question', promptId: string, messageId: string) {
    this.start(run);
    const flow = this.owned(run);
    const id = `${run.runId}:${kind}:${promptId}`;
    if (!flow || flow.steps.some((s) => s.stepId === id)) return;
    const changed = this.endPhases(flow, run);
    const step = this.step(run, kind, id, this.frontier(flow));
    const calls = flow.steps.filter((s) => s.runId === run.runId && s.tool && active(s));
    // Native controls do not always identify a call. Only the single active call is unambiguous.
    if (calls.length === 1) {
      calls[0]!.state = 'waiting';
      changed.push(calls[0]!);
    }
    step.state = 'waiting';
    step.messageId = messageId;
    flow.steps.push(step);
    flow.state = 'waiting';
    this.database.saveFlow(flow, [...changed, step]);
  }

  settle(run: RunRecord, kind: 'approval' | 'question', promptId: string, denied: boolean) {
    const flow = this.owned(run);
    const step = flow?.steps.find((s) => s.stepId === `${run.runId}:${kind}:${promptId}`);
    if (!flow || !step || !active(step)) return;
    step.state = denied ? 'cancelled' : 'done';
    const changed = [step];
    const pending = flow.steps.some(
      (s) => (s.kind === 'approval' || s.kind === 'question') && s.state === 'waiting',
    );
    if (!pending) {
      for (const call of flow.steps.filter((s) => s.tool && s.state === 'waiting')) {
        call.state = 'running';
        changed.push(call);
      }
    }
    flow.state = pending ? 'waiting' : 'running';
    this.database.saveFlow(flow, changed);
    this.phase(run, 'thinking', run.lastSeq);
  }

  finish(run: RunRecord, state: FlowStep['state']) {
    const flow = this.owned(run);
    if (!flow) return;
    const changed = flow.steps.filter((s) => s.runId === run.runId && active(s));
    for (const step of changed)
      step.state =
        state === 'done' && step.tool
          ? 'unknown'
          : state === 'done' && step.state === 'waiting'
            ? 'cancelled'
            : state;
    flow.state = run.groupId && state === 'done' ? 'running' : state;
    if (!run.groupId || state === 'cancelled') flow.queuedBotIds = [];
    this.database.saveFlow(flow, changed);
  }

  group(chain: GroupChainRecord, state?: FlowSnapshot['state']) {
    const flow = this.load(chain.conversationId);
    if (!flow || flow.flowId !== chain.notificationId) return;
    if (
      (!state || flow.state === state) &&
      JSON.stringify(flow.queuedBotIds) === JSON.stringify(state ? [] : chain.queue)
    )
      return;
    flow.queuedBotIds = state ? [] : [...chain.queue];
    if (state) flow.state = state;
    this.database.saveFlow(flow, []);
  }
}
