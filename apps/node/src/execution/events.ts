import { randomUUID } from 'node:crypto';
import { RunMessages } from '../execution/messages';
import { BotSecrets } from '../secrets';
import type { Message, ApprovalChoice, HermesEvent } from '@nekodot/protocol';
import { NodeDatabase, type RunRecord } from '../database';
import { FileLibrary } from '../files';
import { Notifications } from '../notifications';
import { ExecutionFlows } from '../flow';

import type { RunControls } from './controls';
const now = () => new Date().toISOString();
export class RunEvents {
  constructor(
    private readonly database: NodeDatabase,
    private readonly secrets: BotSecrets,
    private readonly flow: ExecutionFlows,
    private readonly messages: RunMessages,
    private readonly controls: RunControls,
    private readonly notifications: Notifications,
    private readonly files: FileLibrary,
    private readonly onActivity: (run: RunRecord) => void,
    private readonly finishGroupRun: (
      run: RunRecord,
      status: 'completed' | 'failed' | 'cancelled',
      output: string,
    ) => Promise<void>,
    private readonly end: (run: RunRecord) => void,
  ) {}
  async accept(run: RunRecord, event: HermesEvent) {
    event = JSON.parse(this.secrets.scrub(run.botId, JSON.stringify(event))) as HermesEvent;
    const runId = run.runId!;
    this.flow.start(run);
    if (event.event === 'todo.updated') {
      this.flow.plan(run, event.todo_state!);
      run.lastSeq = event.seq;
      this.database.saveRun(run);
      return;
    }
    if (event.event === 'tool.generating') this.flow.phase(run, 'thinking', event.seq);
    if (event.event === 'clarify.request') {
      this.messages.persistText(run, this.messages.currentText(run), event.seq);
      this.controls.restoreQuestion(run, {
        kind: 'clarify',
        prompt_id: event.prompt_id ?? '',
        execution_generation: event.execution_generation ?? run.executionGeneration ?? 0,
        choices: event.choices,
        question: event.question,
        multi_select: event.multi_select,
      });
      run.lastSeq = event.seq;
      this.database.saveRun(run);
      return;
    }
    if (event.event === 'clarify.settled') {
      const question = this.database
        .messagesForRun(runId)
        .find(
          (message) => message.kind === 'question' && message.content.requestId === event.prompt_id,
        );
      if (question?.kind === 'question' && question.status === 'streaming') {
        question.status = 'done';
        this.database.putMessage(question, { runId });
      }
      this.flow.settle(
        run,
        'question',
        event.prompt_id ?? '',
        question?.kind === 'question' && question.content.answer ? 'done' : 'unknown',
      );
      run.state = 'thinking';
      run.lastSeq = event.seq;
      this.database.saveRun(run);
      this.onActivity(run);
      return;
    }
    if (event.event === 'message.delta') {
      const textMessage = this.messages.ensureText(run);
      const delta = event.delta ?? '';
      // Canonical null deltas delimit segments; they are not a reply being emitted.
      if (delta.trim()) this.flow.phase(run, 'reply', event.seq, textMessage.messageId);
      this.messages.append(run, textMessage, delta, event.seq);
      return;
    }
    if (event.event === 'message.interim') {
      const streamed = this.messages.currentText(run);
      if (streamed && event.already_streamed !== false) {
        this.database.putMessage({ ...streamed, kind: 'commentary', status: 'done' }, { runId });
        run.textMessageId = undefined;
      }
      if (event.already_streamed === false && event.text) {
        const commentary = this.messages.newText(run, event.text, 'done', 'commentary');
        this.database.putMessage(commentary, { runId });
      }
      run.lastSeq = event.seq;
      this.database.saveRun(run);
      return;
    }
    if (event.event === 'tool.started') {
      const previous = this.messages.currentText(run);
      if (previous) {
        run.lastSeq = event.seq;
        this.database.putMessage(
          { ...previous, kind: 'commentary', status: 'done' },
          { runId },
          run,
        );
        run.textMessageId = undefined;
      }
      const toolCallId = event.tool_call_id!;
      const tool: Message = {
        messageId: randomUUID(),
        conversationId: run.conversationId,
        seq: this.database.head(),
        author: { type: 'bot', id: run.botId },
        kind: 'tool',
        status: 'streaming',
        createdAt: now(),
        content: {
          tool: event.tool ?? 'tool',
          preview: event.preview ?? '',
          ...(event.context ? { context: event.context } : {}),
        },
      };
      run.state = 'tool';
      run.lastSeq = event.seq;
      this.database.putMessage(tool, { runId, toolCallId }, run);
      this.flow.tool(run, toolCallId, tool.content.tool, tool.messageId);
      this.onActivity(run);
      return;
    }
    if (event.event === 'tool.completed') {
      const toolCallId = event.tool_call_id;
      const tool = this.database.tool(runId, toolCallId!);
      run.state = 'thinking';
      run.lastSeq = event.seq;
      if (tool?.kind === 'tool') {
        tool.status = run.stopRequested ? 'cancelled' : 'done';
        tool.content = {
          ...tool.content,
          resultPreview: event.preview ?? '',
          durationMs: Math.round((event.duration ?? 0) * 1000),
          error: event.error === true || event.error === 'true',
        };
        this.database.putMessage(tool, { runId, ...(toolCallId ? { toolCallId } : {}) }, run);
        this.flow.toolEnd(
          run,
          toolCallId!,
          run.stopRequested ? 'cancelled' : tool.content.error ? 'failed' : 'done',
          event.seq,
        );
      } else this.database.saveRun(run);
      this.onActivity(run);
      return;
    }
    if (event.event === 'approval.request') {
      this.messages.persistText(run, this.messages.currentText(run), event.seq);
      const approval: Message = {
        messageId: randomUUID(),
        conversationId: run.conversationId,
        seq: this.database.head(),
        author: { type: 'bot', id: run.botId },
        kind: 'approval',
        status: 'streaming',
        createdAt: now(),
        content: {
          runId,
          botId: run.botId,
          requestId: event.prompt_id ?? '',
          executionGeneration: event.execution_generation ?? run.executionGeneration ?? 0,
          ...(event.choices ? { choices: event.choices as ApprovalChoice[] } : {}),
          prompt: event.description ?? event.command ?? 'Approval required',
          ...(event.command ? { command: event.command } : {}),
        },
      };
      run.state = 'waiting_approval';
      run.lastSeq = event.seq;
      this.database.putMessage(approval, { runId }, run);
      this.flow.prompt(run, 'approval', event.prompt_id ?? '', approval.messageId);
      this.notifications.send({
        notificationId: `approval:${runId}:${event.prompt_id}`,
        conversationId: run.conversationId,
        kind: 'approval',
      });
      this.onActivity(run);
      return;
    }
    if (event.event === 'approval.settled') {
      this.messages.persistText(run, this.messages.currentText(run), event.seq);
      const approval = this.database.approval(runId, event.prompt_id ?? '');
      if (approval?.kind === 'approval') {
        approval.status = 'done';
        this.database.putMessage(approval, { runId }, { ...run, lastSeq: event.seq });
      } else {
        run.lastSeq = event.seq;
        this.database.saveRun(run);
      }
      this.flow.settle(
        run,
        'approval',
        event.prompt_id ?? '',
        approval?.kind === 'approval' && approval.content.choice
          ? approval.content.choice === 'deny'
            ? 'cancelled'
            : 'done'
          : 'unknown',
      );
      run.state = 'thinking';
      this.onActivity(run);
      return;
    }
    if (event.event === 'run.completed') {
      const reply = this.messages.ensureText(run);
      reply.content = { ...reply.content, text: event.output ?? reply.content.text };
      reply.status = 'done';
      await this.files.capture(reply);
      this.messages.persistText(run, reply, event.seq);
      if (reply.content.text) this.flow.phase(run, 'reply', event.seq, reply.messageId);
      this.flow.finish(run, 'done');
      if (run.groupId) await this.finishGroupRun(run, 'completed', reply.content.text);
      else {
        this.notifications.send({
          notificationId: `run:${runId}`,
          conversationId: run.conversationId,
          kind: 'completed',
        });
        this.end(run);
      }
      return;
    }
    if (
      event.event === 'run.cancelled' ||
      event.event === 'run.interrupted' ||
      event.event === 'run.failed'
    ) {
      this.controls.settleControls(run, event.event === 'run.cancelled' ? 'cancelled' : 'failed');
      const reply =
        this.messages.currentText(run) ??
        this.messages.newText(
          run,
          event.event === 'run.cancelled'
            ? 'Run stopped.'
            : (event.output ?? 'Run was interrupted.'),
          event.event === 'run.cancelled' ? 'cancelled' : 'failed',
        );
      if (event.event !== 'run.cancelled' && !reply.content.text)
        reply.content = { ...reply.content, text: event.output ?? 'Run failed.' };
      if (event.event !== 'run.cancelled')
        reply.content.failureReason =
          typeof event.error === 'string'
            ? event.error
            : (event.turn_exit_reason ??
              'Hermes interrupted this turn. Send a message to continue; the task was not restarted.');
      reply.status = event.event === 'run.cancelled' ? 'cancelled' : 'failed';
      this.messages.persistText(run, reply, event.seq);
      this.flow.finish(run, event.event === 'run.cancelled' ? 'cancelled' : 'failed');
      if (run.groupId)
        await this.finishGroupRun(
          run,
          event.event === 'run.cancelled' ? 'cancelled' : 'failed',
          reply.content.text,
        );
      else {
        if (event.event !== 'run.cancelled')
          this.notifications.send({
            notificationId: `run:${runId}`,
            conversationId: run.conversationId,
            kind: 'failed',
          });
        this.end(run);
      }
      return;
    }
    run.lastSeq = event.seq;
    this.database.saveRun(run);
  }
}
