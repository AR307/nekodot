import { randomUUID } from 'node:crypto';
import type { Message, RpcParams, ApprovalChoice } from '@nekodot/protocol';
import { connectorApprovalContent } from '../connectors';
import { NodeDatabase, type RunRecord } from '../database';
import type { HermesRuntime } from '../hermes/runtime';
import { NodeFault } from '../fault';
import { Notifications } from '../notifications';
import { ExecutionFlows } from '../flow';
import type { NativePrompt } from './types';

const now = () => new Date().toISOString();
export class RunControls {
  constructor(
    private readonly database: NodeDatabase,
    private readonly hermes: HermesRuntime,
    private readonly flow: ExecutionFlows,
    private readonly notifications: Notifications,
    private readonly onActivity: (run: RunRecord) => void,
    private readonly onTaskQuestion: (
      run: RunRecord,
      question: Extract<Message, { kind: 'question' }>,
    ) => Promise<void>,
  ) {}
  async respondToApproval(params: RpcParams<'approvals.respond'>) {
    const runId = this.database.messageRun(params.messageId);
    const message = this.database.message(params.messageId);
    if (
      message?.kind === 'approval' &&
      message.status === 'done' &&
      message.content.choice === params.choice
    )
      return {};
    if (!runId || message?.kind !== 'approval' || message.status !== 'streaming')
      throw new NodeFault('not_found', 'Approval is no longer pending');
    const run = this.database.runs().find((item) => item.runId === runId);
    if (!run) throw new NodeFault('not_found', 'Run is no longer active');
    if (!run.sessionId) throw new NodeFault('not_found', 'Hermes session is no longer active');
    await this.hermes
      .gateway(run.botId)
      .rpc(run.background === 'cron' ? 'cron.approve' : 'approval.respond', {
        ...(run.background === 'cron' ? { admission_id: run.runId } : {}),
        session_id: run.sessionId,
        execution_generation: message.content.executionGeneration,
        prompt_id: message.content.requestId,
        choice: params.choice,
      });
    message.content = { ...message.content, choice: params.choice };
    message.status = 'done';
    run.state = 'thinking';
    this.database.putMessage(message, { runId }, run);
    this.flow.settle(
      run,
      'approval',
      message.content.requestId,
      params.choice === 'deny' ? 'cancelled' : 'done',
    );
    this.onActivity(run);
    return {};
  }

  async restoreNativePrompts(run: RunRecord, prompts: NativePrompt[]) {
    for (const pending of prompts) {
      if (pending.kind === 'clarify') {
        await this.restoreQuestion(run, pending);
        continue;
      }
      if (!run.runId) continue;
      const connector = connectorApprovalContent(pending.command, pending.description);
      const existing = this.database.approval(run.runId, pending.prompt_id);
      if (existing) {
        if (existing.status === 'streaming') {
          if (connector.connector) {
            existing.content = { ...existing.content, ...connector };
            this.database.putMessage(existing, { runId: run.runId }, run);
          }
          this.flow.prompt(run, 'approval', pending.prompt_id, existing.messageId);
        }
        continue;
      }
      run.state = 'waiting_approval';
      this.database.putMessage(
        {
          messageId: randomUUID(),
          conversationId: run.conversationId,
          seq: this.database.head(),
          author: { type: 'bot', id: run.botId },
          kind: 'approval',
          status: 'streaming',
          createdAt: now(),
          content: {
            runId: run.runId,
            botId: run.botId,
            requestId: pending.prompt_id,
            executionGeneration: pending.execution_generation,
            prompt: pending.description ?? pending.command ?? 'Approval required',
            ...(pending.command ? { command: pending.command } : {}),
            ...connector,
            ...(pending.choices ? { choices: pending.choices as ApprovalChoice[] } : {}),
          },
        },
        { runId: run.runId },
        run,
      );
      const message = this.database.approval(run.runId, pending.prompt_id);
      if (message) this.flow.prompt(run, 'approval', pending.prompt_id, message.messageId);
    }
  }

  async restoreQuestion(run: RunRecord, pending: NativePrompt) {
    if (pending.kind !== 'clarify' || !run.runId) return;
    const existing = this.database
      .messagesForRun(run.runId)
      .find(
        (message) => message.kind === 'question' && message.content.requestId === pending.prompt_id,
      );
    run.state = 'waiting_question';
    if (!existing)
      this.database.putMessage(
        {
          messageId: randomUUID(),
          conversationId: run.conversationId,
          seq: this.database.head(),
          author: { type: 'bot', id: run.botId },
          kind: 'question',
          status: 'streaming',
          createdAt: now(),
          content: {
            runId: run.runId,
            botId: run.botId,
            requestId: pending.prompt_id,
            executionGeneration: pending.execution_generation ?? run.executionGeneration ?? 0,
            question: pending.question ?? 'Hermes needs your answer',
            choices: pending.choices ?? [],
            multiSelect: pending.multi_select ?? false,
          },
        },
        { runId: run.runId },
        run,
      );
    else this.database.saveRun(run);
    const message =
      existing ??
      this.database
        .messagesForRun(run.runId)
        .find((m) => m.kind === 'question' && m.content.requestId === pending.prompt_id);
    if (message?.kind !== 'question') return;
    const privateQuestion = run.role === 'execution' && !!run.taskId;
    this.flow.prompt(
      run,
      'question',
      pending.prompt_id,
      privateQuestion ? undefined : message.messageId,
    );
    if (run.questionMessageId) {
      const original = this.database.message(run.questionMessageId);
      const worker =
        original?.kind === 'question'
          ? this.database.runs().find((r) => r.runId === original.content.runId)
          : undefined;
      if (worker && original?.kind === 'question')
        this.flow.prompt(worker, 'question', original.content.requestId, message.messageId);
    }
    if (!existing && !privateQuestion)
      this.notifications.send({
        notificationId: `question:${run.runId}:${pending.prompt_id}`,
        conversationId: run.conversationId,
        ...(run.taskId ? { taskId: run.taskId } : {}),
        kind: 'question',
      });
    this.onActivity(run);
    if (privateQuestion) await this.onTaskQuestion(run, message);
  }

  async respondToQuestion(params: RpcParams<'questions.respond'>) {
    const message = this.database.message(params.messageId);
    if (
      message?.kind === 'question' &&
      message.status === 'done' &&
      message.content.answer === params.answer
    )
      return {};
    if (message?.kind !== 'question' || message.status !== 'streaming')
      throw new NodeFault('conflict', 'This question is no longer pending');
    const run = this.database.runs().find((item) => item.runId === message.content.runId);
    if (!run?.runId) throw new NodeFault('conflict', 'Run is no longer active');
    if (!run.sessionId) throw new NodeFault('not_found', 'Hermes session is no longer active');
    const response = await this.hermes
      .gateway(run.botId)
      .rpc<{ status: string }>(run.background === 'cron' ? 'cron.clarify' : 'clarify.respond', {
        ...(run.background === 'cron' ? { admission_id: run.runId } : {}),
        session_id: run.sessionId,
        execution_generation: message.content.executionGeneration,
        prompt_id: message.content.requestId,
        answer: params.answer,
      });
    if (response.status === 'already_resolved') {
      message.status = 'done';
      this.database.putMessage(message, { runId: run.runId });
      throw new NodeFault(
        'conflict',
        'Hermes already closed this question. Your answer was not sent.',
      );
    }
    message.content.answer = params.answer;
    message.status = 'done';
    run.state = 'thinking';
    this.database.putMessage(message, { runId: run.runId }, run);
    this.flow.settle(run, 'question', message.content.requestId, 'done');
    this.onActivity(run);
    return {};
  }

  pendingInstruction(run: RunRecord, text?: string) {
    if (!text) return;
    this.database.putMessage(
      {
        messageId: randomUUID(),
        conversationId: run.conversationId,
        seq: this.database.head(),
        author: { type: 'system' },
        kind: 'system',
        status: 'done',
        createdAt: now(),
        content: {
          text: 'The run ended before consuming your added instruction. You can resend it.',
          retryText: text,
        },
      },
      { runId: run.runId },
    );
  }

  settleControls(run: RunRecord, status: Message['status']) {
    if (!run.runId) return;
    for (const message of this.database.messagesForRun(run.runId)) {
      if (
        message.status === 'streaming' &&
        (message.kind === 'tool' || message.kind === 'approval' || message.kind === 'question')
      ) {
        message.status = status;
        this.database.putMessage(message, { runId: run.runId });
      }
    }
  }
}
