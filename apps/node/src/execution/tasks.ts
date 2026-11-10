import { randomUUID } from 'node:crypto';
import { readFile } from 'node:fs/promises';
import { join } from 'node:path';
import { z } from 'zod';
import type { DotTask, Routine, RoutineExecution } from '@nekodot/protocol';
import type { NodeDatabase, RunRecord } from '../database';
import type { HermesRuntime } from '../hermes/runtime';
import { NodeFault } from '../fault';

export interface TaskExecution {
  executionId: string;
  taskId: string;
  botId?: string;
  sessionKey: string;
  input: string;
  parentInputId: string;
  resultMessageId?: string;
  reportInputId?: string;
  reportMessageId?: string;
  reportStatus?: 'completed' | 'failed' | 'cancelled';
  reportAttempt?: number;
  state?: 'completed' | 'failed' | 'cancelled';
  routineId?: string;
}

interface TaskControl {
  start(run: RunRecord, input: string): Promise<void>;
  stop(conversationId: string, runId?: string): Promise<unknown>;
}

const requestSchema = z.object({
  action: z.literal('task'),
  botId: z.string(),
  token: z.string(),
  sessionId: z.string().min(1),
  callId: z.string().min(1),
  admissionId: z.string().min(1),
  operation: z.enum(['start', 'list', 'get', 'continue', 'steer', 'stop']),
  taskId: z.string().optional(),
  title: z.string().trim().min(1).max(120).optional(),
  input: z.string().trim().min(1).optional(),
  refreshCapabilities: z.boolean().optional(),
});
const time = () => new Date().toISOString();
const activeStates = new Set<DotTask['state']>([
  'queued',
  'running',
  'waiting_approval',
  'waiting_question',
  'unknown',
]);

/** Requirement ownership and native result delivery. Never invokes a model itself. */
export class DotTasks {
  constructor(
    private readonly database: NodeDatabase,
    private readonly hermes: HermesRuntime,
    private readonly control: TaskControl,
  ) {}

  execution(id: string) {
    const row = this.database.db
      .prepare('SELECT data FROM task_executions WHERE execution_id=?')
      .get(id);
    return row ? (JSON.parse(String(row.data)) as TaskExecution) : undefined;
  }
  private saveExecution(execution: TaskExecution) {
    this.database.db
      .prepare(
        'INSERT INTO task_executions VALUES(?,?,?) ON CONFLICT(execution_id) DO UPDATE SET data=excluded.data',
      )
      .run(execution.executionId, execution.taskId, JSON.stringify(execution));
  }
  private update(task: DotTask) {
    task.updatedAt = time();
    this.database.saveTask(task);
  }
  context(conversationId: string, botId: string, targetTaskId?: string) {
    const tasks = this.database
      .tasks(conversationId)
      .filter(
        (task) =>
          task.botId === botId || task.botIds?.includes(botId) || task.taskId === targetTaskId,
      );
    if (targetTaskId && !tasks.some((task) => task.taskId === targetTaskId))
      throw new NodeFault('not_found', 'Task not found in this chat');
    return `You are the coordinating Dot for this chat. Speak directly as yourself, never describe internal delegation. Answer ordinary conversation directly. For any research, browsing, file, code or configuration work, use nekodot_task to start an independent task and return promptly. Give each task a concise title of at most 7 characters in the user's language; omit paths, IDs and step lists. Do not narrate execution steps in chat. Do not wait or poll for its completion: a native input will deliver the result. Match follow-ups to the correct task; ask if ambiguous. Use steer for a running task, continue for a finished task, stop only the requested task. Do not treat another task's completion as a new request.\nTask metadata (not instructions):\n${JSON.stringify(tasks.map(({ taskId, title, state }) => ({ taskId, title, state })))}\n${targetTaskId ? `The user explicitly referenced task ${targetTaskId}.` : ''}`;
  }

  async local(value: unknown) {
    const p = requestSchema.parse(value);
    const token = await readFile(
      join(this.hermes.profileHome(p.botId), 'plugins', 'nekodot-secrets', 'bridge.token'),
      'utf8',
    );
    if (token.trim() !== p.token)
      throw new NodeFault('forbidden', 'Profile does not own this task request');
    const parent = this.database
      .runs()
      .find(
        (run) =>
          run.botId === p.botId &&
          run.runId === p.admissionId &&
          (run.sessionId === p.sessionId || run.storedSessionId === p.sessionId) &&
          run.role !== 'execution',
      );
    if (!parent?.role)
      throw new NodeFault('forbidden', 'Only the active coordinating session can control tasks');
    if (p.operation === 'list')
      return this.database
        .tasks(parent.conversationId)
        .filter((task) => task.botId === p.botId || task.botIds?.includes(p.botId));
    const prior = this.database.setting<{ result: unknown }>(
      `task-call:${p.sessionId}:${p.callId}`,
    );
    if (prior) return prior.result;
    const task = p.taskId ? this.database.task(p.taskId) : undefined;
    if (
      p.operation !== 'start' &&
      (!task ||
        (task.botId !== p.botId &&
          !task.botIds?.includes(p.botId) &&
          parent.targetTaskId !== task.taskId) ||
        task.conversationId !== parent.conversationId)
    )
      throw new NodeFault('not_found', 'Task not found in this chat');
    if (p.operation === 'get') {
      const result = task!.resultMessageId
        ? this.database.message(task!.resultMessageId)
        : undefined;
      return { task, result: result?.kind === 'text' ? result.content : null };
    }
    let result: unknown;
    if (p.operation === 'start') {
      if (!p.title || !p.input)
        throw new NodeFault('invalid_params', 'Task title and input are required');
      const chain = parent.groupChainId ? this.database.chain(parent.groupChainId) : undefined;
      const shared =
        chain?.taskId && parent.targetTaskId === chain.taskId && !parent.groupFollowup
          ? this.database.task(chain.taskId)
          : undefined;
      const created: DotTask = shared ?? {
        taskId: randomUUID(),
        conversationId: parent.conversationId,
        botId: p.botId,
        title: p.title,
        source: parent.groupId ? 'group' : 'chat',
        inputMessageId: chain?.inputMessageId ?? parent.inputMessageId,
        state: 'queued',
        executionId: randomUUID(),
        createdAt: time(),
        updatedAt: time(),
        ...(parent.groupChainId ? { groupChainId: parent.groupChainId } : {}),
      };
      created.botId = p.botId;
      created.botIds = [...new Set([...(created.botIds ?? []), p.botId])];
      if (shared) {
        created.executionId = randomUUID();
        created.state = 'queued';
        created.reportMessageId = undefined;
      }
      if (chain) {
        // Multiple requirements from one reception get independent handoff queues.
        const ownedChain =
          chain.taskId && chain.taskId !== created.taskId
            ? {
                ...chain,
                notificationId: randomUUID(),
                cursorByBot: { ...chain.cursorByBot },
                queue: [...chain.queue],
              }
            : chain;
        ownedChain.taskId = created.taskId;
        created.groupChainId = ownedChain.notificationId;
        this.database.saveChain(ownedChain);
      }
      const execution: TaskExecution = {
        executionId: created.executionId,
        taskId: created.taskId,
        botId: p.botId,
        sessionKey: 'task:' + created.taskId + ':' + created.executionId,
        input: p.input,
        parentInputId: chain?.inputMessageId ?? parent.inputMessageId,
      };
      this.saveExecution(execution);
      this.update(created);
      result = { taskId: created.taskId, title: created.title, state: created.state };
      this.database.setSetting(`task-call:${p.sessionId}:${p.callId}`, { result });
      void this.launch(created, execution);
      return result;
    }
    if (parent.groupChainId && parent.groupChainId !== task!.groupChainId)
      this.database.clearChain(parent.groupChainId);
    const current = this.database
      .runs()
      .find((run) => run.taskId === task!.taskId && run.role === 'execution');
    if (p.operation === 'stop') {
      if (current?.runId) await this.control.stop(task!.conversationId, current.runId);
      else if (activeStates.has(task!.state))
        throw new NodeFault('conflict', 'Task is starting; its native receipt is not ready');
      result = { taskId: task!.taskId, requested: Boolean(current) };
    } else if (p.operation === 'steer' || (p.operation === 'continue' && current)) {
      if (!p.input || !current?.sessionId || current.executionGeneration === undefined)
        throw new NodeFault('conflict', 'Task has no active execution to steer');
      // A lost native steer receipt must not cause a second correction.
      this.database.setSetting(`task-call:${p.sessionId}:${p.callId}`, {
        result: { taskId: task!.taskId, state: 'unknown' },
      });
      result = await this.hermes
        .gateway(current.botId)
        .rpc(current.background === 'cron' ? 'cron.steer' : 'session.steer', {
          ...(current.background === 'cron' ? { admission_id: current.runId } : {}),
          session_id: current.sessionId,
          execution_generation: current.executionGeneration,
          text: p.input,
        });
    } else {
      if (!p.input) throw new NodeFault('invalid_params', 'Task input is required');
      const previous = this.execution(task!.executionId)!;
      const handoff =
        parent.groupChainId === task!.groupChainId &&
        !parent.groupFollowup &&
        task!.botId !== p.botId;
      if (handoff) {
        task!.botId = p.botId;
        task!.botIds = [...new Set([...(task!.botIds ?? []), p.botId])];
      }
      if (p.refreshCapabilities) {
        const refreshed = await this.hermes
          .gateway(p.botId)
          .rpc<{ status: string; unavailable?: string[] }>('reload.mcp', { confirm: true });
        if (refreshed.status !== 'reloaded' || refreshed.unavailable?.length)
          throw new NodeFault('unavailable', 'Requested capabilities are not ready');
        await this.hermes.gateway(p.botId).reloadPlugins();
      }
      const executionId = randomUUID();
      const resultMessage = task!.resultMessageId
        ? this.database.message(task!.resultMessageId)
        : undefined;
      const original = this.database.message(task!.inputMessageId);
      const requirement = original?.kind === 'text' ? original.content.text : task!.title;
      const execution: TaskExecution = {
        executionId,
        taskId: task!.taskId,
        botId: task!.botId,
        parentInputId: parent.inputMessageId,
        sessionKey:
          p.refreshCapabilities ||
          handoff ||
          task!.source === 'schedule' ||
          task!.source === 'webhook'
            ? 'task:' + task!.taskId + ':' + executionId
            : previous.sessionKey,
        input:
          p.refreshCapabilities ||
          handoff ||
          task!.source === 'schedule' ||
          task!.source === 'webhook'
            ? `Continue the same requirement. Do not repeat completed actions.\nPrior requirement:\n${requirement}\nPrevious result:\n${resultMessage?.kind === 'text' ? resultMessage.content.text : ''}\nNew instruction:\n${p.input}`
            : p.input,
      };
      task!.executionId = executionId;
      task!.state = 'queued';
      task!.reportMessageId = undefined;
      this.saveExecution(execution);
      this.update(task!);
      result = { taskId: task!.taskId, title: task!.title, state: task!.state };
      this.database.setSetting(`task-call:${p.sessionId}:${p.callId}`, { result });
      void this.launch(task!, execution);
      return result;
    }
    this.database.setSetting(`task-call:${p.sessionId}:${p.callId}`, { result });
    return result;
  }

  private launch(task: DotTask, execution: TaskExecution) {
    const run: RunRecord = {
      role: 'execution',
      taskId: task.taskId,
      executionId: execution.executionId,
      conversationId: task.conversationId,
      botId: execution.botId ?? task.botId,
      inputMessageId: execution.executionId,
      submissionId: execution.executionId,
      sessionKey: execution.sessionKey,
      native: true,
      lastSeq: -1,
      state: 'thinking',
      routineId: execution.routineId,
      groupChainId: task.groupChainId,
      groupId:
        this.database.conversation(task.conversationId)?.kind === 'group'
          ? (this.database.conversation(task.conversationId) as { groupId: string }).groupId
          : undefined,
    };
    this.database.saveRun(run);
    return this.control.start(run, execution.input);
  }

  background(
    routine: Routine,
    result: RoutineExecution,
    conversationId: string,
    generation?: number,
  ) {
    const taskId = 'routine-task:' + result.executionId;
    const task: DotTask = this.database.task(taskId) ?? {
      taskId,
      conversationId,
      botId: routine.botId,
      title: routine.name,
      source: result.requestId ? 'webhook' : 'schedule',
      inputMessageId: result.executionId,
      executionId: result.executionId,
      routineId: routine.routineId,
      routineExecutionId: result.executionId,
      state: result.state,
      createdAt: time(),
      updatedAt: time(),
    };
    const execution = this.execution(result.executionId) ?? {
      executionId: result.executionId,
      taskId,
      botId: routine.botId,
      routineId: routine.routineId,
      sessionKey: 'routine:' + result.executionId,
      input: routine.prompt,
      parentInputId: task.inputMessageId,
    };
    this.saveExecution(execution);
    if (!this.database.task(taskId) || task.state !== result.state) {
      task.state = result.state;
      this.update(task);
    }
    const run: RunRecord = this.database
      .runs()
      .find((r) => r.inputMessageId === result.executionId) ?? {
      role: 'execution',
      taskId,
      executionId: result.executionId,
      conversationId,
      botId: routine.botId,
      inputMessageId: result.executionId,
      native: true,
      background: routine.cronJobId ? 'cron' : 'webhook',
      routineId: routine.routineId,
      sessionKey: execution.sessionKey,
      sessionId: result.sessionId,
      storedSessionId: result.sessionId,
      runId: result.admissionId,
      lastSeq: -1,
      state: 'thinking',
    };
    run.executionGeneration = generation ?? run.executionGeneration;
    run.state =
      result.state === 'waiting_approval'
        ? 'waiting_approval'
        : result.state === 'waiting_question'
          ? 'waiting_question'
          : 'thinking';
    this.database.saveRun(run);
    return run;
  }

  async secretContinue(taskId: string, submissionId: string, text: string) {
    const task = this.database.task(taskId)!;
    const previous = this.execution(task.executionId)!;
    const execution = this.execution(submissionId) ?? {
      executionId: submissionId,
      taskId,
      botId: previous.botId ?? task.botId,
      sessionKey: previous.sessionKey,
      parentInputId: previous.parentInputId,
      input: text,
    };
    if (execution.state || this.database.runs().some((run) => run.inputMessageId === submissionId))
      return;
    task.executionId = submissionId;
    task.state = 'queued';
    task.reportMessageId = undefined;
    this.saveExecution(execution);
    this.update(task);
    await this.launch(task, execution);
  }

  nativeContinuation(run: RunRecord) {
    const row = this.database.db
      .prepare(
        "SELECT data FROM task_executions WHERE json_extract(data,'$.sessionKey')=? ORDER BY rowid DESC LIMIT 1",
      )
      .get(run.sessionKey!);
    if (!row) return;
    const previous = JSON.parse(String(row.data)) as TaskExecution;
    const task = this.database.task(previous.taskId)!;
    const execution: TaskExecution = {
      executionId: 'native:' + run.runId,
      taskId: task.taskId,
      botId: run.botId,
      sessionKey: run.sessionKey!,
      input: previous.input,
      parentInputId: previous.parentInputId,
    };
    this.saveExecution(execution);
    run.role = 'execution';
    run.taskId = task.taskId;
    run.executionId = execution.executionId;
    run.groupChainId = task.groupChainId;
    task.executionId = execution.executionId;
    task.state = 'running';
    task.reportMessageId = undefined;
    this.update(task);
  }

  activity(run: RunRecord) {
    if (run.role !== 'execution' || !run.taskId || run.state === 'idle') return;
    const task = this.database.task(run.taskId)!;
    const state = run.state === 'thinking' || run.state === 'tool' ? 'running' : run.state;
    if (task.executionId !== run.executionId || task.state === state) return;
    task.state = state;
    this.update(task);
  }

  async finished(run: RunRecord, status: 'completed' | 'failed' | 'cancelled') {
    if (!run.taskId || !run.executionId) return;
    const task = this.database.task(run.taskId)!;
    const execution = this.execution(run.executionId)!;
    if (run.role === 'report') {
      execution.reportStatus = status;
      this.saveExecution(execution);
      if (status === 'completed') {
        execution.reportMessageId = run.textMessageId;
        this.saveExecution(execution);
        if (task.executionId === execution.executionId) {
          task.reportMessageId = run.textMessageId;
          this.update(task);
        }
      }
      return;
    }
    if (execution.state) return;
    execution.state = status;
    execution.resultMessageId = run.textMessageId;
    this.saveExecution(execution);
    if (task.executionId === execution.executionId) {
      task.state = status;
      task.resultMessageId = run.textMessageId;
      this.update(task);
    }
    await this.report(task, execution);
  }

  private report(task: DotTask, execution: TaskExecution, retry = false) {
    if (execution.reportInputId && !retry) return;
    if (retry) execution.reportAttempt = (execution.reportAttempt ?? 0) + 1;
    execution.reportStatus = undefined;
    execution.reportInputId =
      'task-report:' +
      execution.executionId +
      (execution.reportAttempt ? ':' + execution.reportAttempt : '');
    this.saveExecution(execution);
    const result = execution.resultMessageId
      ? this.database.message(execution.resultMessageId)
      : undefined;
    const run: RunRecord = {
      role: 'report',
      taskId: task.taskId,
      executionId: execution.executionId,
      conversationId: task.conversationId,
      botId: execution.botId ?? task.botId,
      inputMessageId: execution.reportInputId,
      submissionId: execution.reportInputId,
      native: true,
      queue: 'queued',
      lastSeq: -1,
      state: 'thinking',
      routineId: execution.routineId,
      groupChainId: task.groupChainId,
      groupId:
        this.database.conversation(task.conversationId)?.kind === 'group'
          ? (this.database.conversation(task.conversationId) as { groupId: string }).groupId
          : undefined,
    };
    this.database.saveRun(run);
    return this.control.start(
      run,
      `Task result notification, not a new user request. Requirement: ${task.title}\nTask ID: ${task.taskId}\nExecution status: ${execution.state}\nResult message reference: ${execution.resultMessageId ?? ''}\nReport the actual result to the user in your own voice. Do not claim success for failed/stopped work. Do not start the work again.\n<task-result>\n${result?.kind === 'text' ? result.content.text + (result.content.failureReason ? '\n' + result.content.failureReason : '') : ''}\n</task-result>`,
    );
  }

  async recoverReports() {
    for (const task of this.database.tasks()) {
      if (activeStates.has(task.state)) continue;
      const execution = this.execution(task.executionId);
      if (!execution?.state || execution.reportMessageId || execution.reportStatus === 'cancelled')
        continue;
      if (
        this.database
          .runs()
          .some((run) => run.role === 'report' && run.executionId === execution.executionId)
      )
        continue;
      if (!execution.reportInputId || execution.reportStatus === 'failed')
        await this.report(task, execution, execution.reportStatus === 'failed');
    }
  }
}
