import type { FlowSnapshot, FlowStep, HermesTodoState } from '@nekodot/protocol';
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

  get(conversationId: string, taskId?: string) {
    if (!this.database.conversation(conversationId))
      throw new NodeFault('not_found', 'Conversation not found');
    const task = taskId
      ? this.database.task(taskId)
      : this.database
          .tasks(conversationId)
          .filter((task) => task.source === 'chat' || task.source === 'group')
          .at(-1);
    if (!task || task.conversationId !== conversationId) return null;
    if (task.source !== 'chat' && task.source !== 'group') return null;
    return this.load(task.taskId) ?? null;
  }

  all() {
    return this.database.tasks().flatMap((task) => {
      const flow = this.get(task.conversationId, task.taskId);
      return flow ? [flow] : [];
    });
  }

  start(run: RunRecord) {
    if (
      run.role !== 'execution' ||
      !run.taskId ||
      !run.runId ||
      !run.storedSessionId ||
      run.queue === 'queued'
    )
      return;
    const task = this.database.task(run.taskId);
    if (!task || (task.source !== 'chat' && task.source !== 'group')) return;
    const chain = run.groupId
      ? this.database.chain(run.groupChainId ?? run.conversationId)
      : undefined;
    const flowId = chain?.notificationId ?? run.executionId ?? run.runId;
    let flow = this.load(run.taskId ?? run.conversationId);
    if (flow?.steps.some((step) => step.runId === run.runId)) return;
    const reset = flow?.flowId !== flowId;
    if (reset || !flow) {
      flow = {
        flowId,
        conversationId: run.conversationId,
        taskId: run.taskId,
        ...(run.groupId ? {} : { sessionId: run.storedSessionId }),
        state: 'running',
        queuedBotIds: [],
        steps: [],
        seq: 0,
      };
      this.values.set(run.taskId, flow);
    }
    const bot = this.step(run, 'bot', run.runId + ':bot', this.frontier(flow));
    const thinking = this.step(run, 'thinking', run.runId + ':thinking:start', [bot.stepId]);
    flow.steps.push(bot, thinking);
    flow.state = 'running';
    flow.queuedBotIds = [...(chain?.queue ?? [])];
    this.database.saveFlow(flow, [bot, thinking], reset);
  }

  private owned(run: RunRecord) {
    const flow = this.load(run.taskId ?? run.conversationId);
    return flow?.steps.some((s) => s.runId === run.runId) ? flow : undefined;
  }

  private step(run: RunRecord, kind: FlowStep['kind'], stepId: string, after: string[]): FlowStep {
    const parent =
      kind === 'bot' || kind === 'plan'
        ? undefined
        : this.load(run.taskId ?? run.conversationId)?.steps.find(
            (s) => s.runId === run.runId && s.kind === 'plan' && s.state === 'running',
          );
    return {
      stepId,
      runId: run.runId!,
      sessionId: run.storedSessionId!,
      botId: run.botId,
      kind,
      state: 'running',
      after,
      ...(parent ? { parentStepId: parent.stepId } : {}),
    };
  }

  private frontier(flow: FlowSnapshot) {
    const referenced = new Set(flow.steps.flatMap((s) => s.after));
    return flow.steps
      .filter((s) => s.kind !== 'plan' && !referenced.has(s.stepId))
      .map((s) => s.stepId);
  }

  plan(run: RunRecord, native: HermesTodoState) {
    const flow = this.owned(run);
    if (!flow) return;
    const prefix = `${run.runId}:plan:`;
    const changed: FlowStep[] = [];
    const states = {
      pending: 'pending',
      in_progress: 'running',
      completed: 'done',
      cancelled: 'cancelled',
    } as const;
    const previous = flow.steps.filter((s) => s.runId === run.runId && s.kind === 'plan');
    for (const todo of native.todos) {
      const stepId = prefix + todo.id;
      let step = previous.find((s) => s.stepId === stepId);
      if (!step) {
        step = this.step(run, 'plan', stepId, []);
        flow.steps.push(step);
      }
      step.title = todo.content;
      step.state = states[todo.status];
      step.parentStepId = todo.parent ? prefix + todo.parent : undefined;
      changed.push(step);
    }
    // Keep already observed actions inspectable when the native plan is replaced.
    for (const step of previous.filter((s) => !changed.includes(s))) {
      step.state = 'unknown';
      changed.push(step);
    }
    const current = changed.find((s) => s.state === 'running');
    for (const step of flow.steps.filter(
      (s) => s.runId === run.runId && (s.kind === 'thinking' || s.kind === 'reply') && active(s),
    )) {
      step.parentStepId = current?.stepId;
      changed.push(step);
    }
    this.database.saveFlow(flow, changed);
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

  settle(
    run: RunRecord,
    kind: 'approval' | 'question',
    promptId: string,
    state: 'done' | 'cancelled' | 'unknown',
  ) {
    const flow = this.owned(run);
    const step = flow?.steps.find((s) => s.stepId === `${run.runId}:${kind}:${promptId}`);
    if (!flow || !step || (!active(step) && step.state !== 'unknown')) return;
    step.state = state;
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
        state === 'done' && (step.tool || step.kind === 'plan')
          ? 'unknown'
          : state === 'done' && step.state === 'waiting'
            ? 'cancelled'
            : state;
    flow.state = run.groupId && state === 'done' ? 'running' : state;
    if (!run.groupId || state === 'cancelled') flow.queuedBotIds = [];
    this.database.saveFlow(flow, changed);
  }

  group(chain: GroupChainRecord, state?: FlowSnapshot['state']) {
    const flow = this.load(chain.taskId ?? chain.conversationId);
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
