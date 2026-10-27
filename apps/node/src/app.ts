import { randomUUID } from 'node:crypto';
import { platform } from 'node:os';
import type {
  LiveEvent,
  Message,
  PersistedEvent,
  RpcParams,
  RpcRequest,
  RpcResult,
} from '@nekodot/protocol';
import { NodeDatabase, type RunRecord } from './database';
import type { HermesRuntime } from './hermes/runtime';
import type { HermesApi } from './hermes/api';
import { NodeFault } from './fault';
import type { SseFrame } from './hermes/sse';
import { BotService } from './bots';

type HermesEvent = SseFrame['data'] & {
  event: string;
  seq: number;
  delta?: string;
  text?: string;
  already_streamed?: boolean;
  tool?: string;
  preview?: string;
  tool_call_id?: string;
  duration?: number;
  error?: boolean | string;
  output?: string;
  prompt_id?: string;
  execution_generation?: number;
  command?: string;
  description?: string;
  accepted?: boolean;
};
type TextMessage = Extract<Message, { kind: 'text' }>;

const now = () => new Date().toISOString();
const isActiveStatus = (status: string) =>
  ['queued', 'running', 'waiting_for_approval', 'stopping', 'pending'].includes(status);

export class NodeApplication {
  readonly database: NodeDatabase;
  readonly bots: BotService;
  onEvent: (event: PersistedEvent) => void = () => {};
  onLive: (event: LiveEvent) => void = () => {};
  private readonly consumers = new Map<string, AbortController>();
  private readonly activeRuns = new Map<string, RunRecord>();
  private readonly textProgress = new Map<string, { persistedAt: number; length: number }>();
  private readonly streamingTexts = new Map<string, string>();
  private readonly appliedSeq = new Map<string, number>();

  constructor(
    home: string,
    readonly hermes: HermesRuntime,
  ) {
    this.database = new NodeDatabase(home);
    this.bots = new BotService(this.database, hermes);
    this.database.onEvent = (event) => this.onEvent(event);
  }

  async handle(request: RpcRequest): Promise<unknown> {
    switch (request.method) {
      case 'sync.snapshot':
        this.activities();
        return {
          bots: this.database.bots(),
          groups: [],
          conversations: this.database.conversations(),
          headSeq: this.database.head(),
          node: { platform: platform(), computerUse: false },
        } satisfies RpcResult<'sync.snapshot'>;
      case 'sync.since':
        this.activities();
        return this.database.since(request.params.seq);
      case 'messages.list':
        return {
          messages: this.database
            .messages(request.params.conversationId, request.params.beforeSeq, request.params.limit)
            .map((message) =>
              message.kind === 'text' && this.streamingTexts.has(message.messageId)
                ? { ...message, content: { text: this.streamingTexts.get(message.messageId)! } }
                : message,
            ),
        };
      case 'messages.send':
        return this.sendMessage(request.params);
      case 'runs.stop':
        return this.stop(request.params.conversationId);
      case 'approvals.respond':
        return this.respondToApproval(request.params);
      case 'providers.get':
        return this.bots.provider();
      case 'providers.set':
        return this.bots.setProvider(request.params);
      case 'models.options':
        return this.hermes.models();
      case 'bots.create':
        return this.bots.create(request.params);
      case 'bots.update':
        return this.bots.update(request.params);
      case 'bots.archive':
        return this.bots.archive(request.params.botId);
      default:
        throw new NodeFault('not_found', 'Method is not available in this phase');
    }
  }

  activities() {
    const runs = this.database.runs();
    for (const conversation of this.database.conversations()) {
      if (conversation.kind !== 'dm') continue;
      const run =
        this.activeRuns.get(conversation.conversationId) ??
        runs.find((item) => item.conversationId === conversation.conversationId);
      this.onLive({
        kind: 'activity',
        conversationId: conversation.conversationId,
        botId: conversation.botId,
        state: run?.state ?? 'idle',
      });
    }
  }

  async resume() {
    for (const run of this.database.runs()) {
      if (!run.runId) {
        this.finishInterrupted(run, 'Run was interrupted before Hermes returned its run ID.');
        continue;
      }
      try {
        const api = await this.hermes.api(run.botId);
        const state = await api.state(run.runId);
        if (isActiveStatus(state.status)) {
          this.activeRuns.set(run.conversationId, run);
          if (state.status === 'waiting_for_approval') {
            const pending = state.pending_controls?.find((control) => control.kind === 'approval');
            if (pending && !this.database.approval(run.runId, pending.prompt_id)) {
              const prompt = pending as typeof pending & { command?: string; description?: string };
              const message: Message = {
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
                  requestId: prompt.prompt_id,
                  executionGeneration:
                    prompt.execution_generation ?? state.execution_generation ?? 0,
                  prompt: prompt.description ?? prompt.command ?? 'Approval required',
                  ...(prompt.command ? { command: prompt.command } : {}),
                },
              };
              run.state = 'waiting_approval';
              this.database.putMessage(message, { runId: run.runId }, run);
            }
          }
          this.publishActivity(run);
          this.consume(run, api);
        } else {
          this.finishFromState(run, state.status, state.output, state.pending_steer);
        }
      } catch {
        this.finishInterrupted(run, 'Hermes could not resume this run. It was not restarted.');
      }
    }
  }

  async close() {
    for (const run of this.activeRuns.values())
      this.persistText(run, this.currentText(run), run.lastSeq);
    for (const consumer of this.consumers.values()) consumer.abort();
    this.consumers.clear();
    this.database.db.close();
  }

  private async sendMessage(params: RpcParams<'messages.send'>) {
    const duplicate = this.database.byClient(params.clientMsgId);
    if (duplicate) return { messageId: duplicate.messageId };
    const conversation = this.database.conversation(params.conversationId);
    if (!conversation || conversation.kind !== 'dm')
      throw new NodeFault('not_found', 'Conversation not found');
    const bot = this.bots.get(conversation.botId);
    const active =
      this.activeRuns.get(conversation.conversationId) ??
      this.database.runs().find((run) => run.conversationId === conversation.conversationId);
    const userMessage: Message = {
      messageId: randomUUID(),
      conversationId: conversation.conversationId,
      seq: this.database.head(),
      author: { type: 'user' },
      kind: 'text',
      status: 'done',
      createdAt: now(),
      content: { text: params.text },
    };

    if (active) {
      this.activeRuns.set(active.conversationId, active);
      if (active.state === 'waiting_approval')
        throw new NodeFault(
          'conflict',
          'Resolve the pending approval or stop this run before sending.',
        );
      if (!active.runId)
        throw new NodeFault('conflict', 'The current run is starting. Try again shortly.');
      const accepted = await (await this.hermes.api(bot.botId)).steer(active.runId, params.text);
      if (!accepted.accepted)
        throw new NodeFault(
          'conflict',
          'Hermes did not accept this instruction. You can send it again.',
        );
      const previousReply = this.currentText(active);
      if (previousReply) {
        previousReply.status = 'done';
        this.database.putMessage(previousReply, { runId: active.runId }, active);
      }
      userMessage.seq = this.database.head();
      this.database.putMessage(
        userMessage,
        { clientMsgId: params.clientMsgId, runId: active.runId },
        active,
      );
      active.textMessageId = undefined;
      active.inputMessageId = userMessage.messageId;
      active.state = 'thinking';
      this.database.saveRun(active);
      this.publishActivity(active);
      return { messageId: userMessage.messageId };
    }

    const run: RunRecord = {
      conversationId: conversation.conversationId,
      botId: bot.botId,
      lastSeq: -1,
      state: 'thinking',
      inputMessageId: userMessage.messageId,
    };
    this.activeRuns.set(run.conversationId, run);
    userMessage.seq = this.database.head();
    this.database.putMessage(userMessage, { clientMsgId: params.clientMsgId }, run);
    this.publishActivity(run);
    void this.startRun(run, params.text);
    return { messageId: userMessage.messageId };
  }

  private async startRun(run: RunRecord, input: string) {
    try {
      const api = await this.hermes.api(run.botId);
      const created = await api.createRun(input, 'nk_dm_' + run.conversationId, run.inputMessageId);
      run.runId = created.run_id;
      this.database.setMessageRun(run.inputMessageId, created.run_id);
      this.database.saveRun(run);
      this.consume(run, api);
    } catch {
      const failed = this.newText(
        run,
        'Could not start this run. Check the provider and try again.',
        'failed',
      );
      const idle = this.idle(run);
      this.database.putMessage(failed, { runId: run.runId }, idle);
      this.end(idle);
    }
  }

  private consume(run: RunRecord, api: HermesApi) {
    if (!run.runId || this.consumers.has(run.runId)) return;
    const controller = new AbortController();
    this.consumers.set(run.runId, controller);
    void this.readRun(run, api, controller.signal).finally(() => {
      if (run.runId) this.consumers.delete(run.runId);
    });
  }

  private async readRun(run: RunRecord, api: HermesApi, signal: AbortSignal) {
    let reconnectDelay = 1000;
    while (!signal.aborted && run.runId) {
      try {
        for await (const frame of api.events(run.runId, run.lastSeq, signal)) {
          const event = frame.data as HermesEvent;
          if (event.seq <= Math.max(run.lastSeq, this.appliedSeq.get(run.runId) ?? -1)) continue;
          await this.acceptEvent(run, api, event);
          this.appliedSeq.set(run.runId, event.seq);
          if (run.state === 'idle') return;
        }
        if (signal.aborted) return;
        const state = await api.state(run.runId);
        if (!isActiveStatus(state.status)) {
          this.finishFromState(run, state.status, state.output, state.pending_steer);
          return;
        }
        reconnectDelay = 1000;
      } catch {
        if (signal.aborted) return;
      }
      if (signal.aborted) return;
      await new Promise((resolve) => setTimeout(resolve, reconnectDelay));
      reconnectDelay = Math.min(reconnectDelay * 2, 30000);
    }
  }

  private async acceptEvent(run: RunRecord, api: HermesApi, event: HermesEvent) {
    const runId = run.runId!;
    if (event.event === 'message.delta') {
      const textMessage = this.ensureText(run);
      const delta = event.delta ?? '';
      const previous = this.streamingTexts.get(textMessage.messageId) ?? textMessage.content.text;
      textMessage.content = { text: previous + delta };
      this.streamingTexts.set(textMessage.messageId, textMessage.content.text);
      this.onLive({
        kind: 'delta',
        conversationId: run.conversationId,
        messageId: textMessage.messageId,
        text: delta,
        offset: previous.length,
      });
      const progress = this.textProgress.get(textMessage.messageId) ?? {
        persistedAt: 0,
        length: 0,
      };
      if (
        textMessage.content.text.length - progress.length >= 400 ||
        Date.now() - progress.persistedAt >= 1000
      ) {
        this.persistText(run, textMessage, event.seq);
      }
      return;
    }
    if (event.event === 'message.interim') {
      const streamed = this.currentText(run);
      if (streamed && event.already_streamed !== false) {
        this.database.putMessage({ ...streamed, kind: 'commentary', status: 'done' }, { runId });
        run.textMessageId = undefined;
      }
      if (event.already_streamed === false && event.text) {
        const commentary = this.newText(run, event.text, 'done', 'commentary');
        this.database.putMessage(commentary, { runId });
      }
      run.lastSeq = event.seq;
      this.database.saveRun(run);
      return;
    }
    if (event.event === 'tool.started') {
      const previous = this.currentText(run);
      if (previous) {
        previous.status = 'done';
        this.persistText(run, previous, event.seq);
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
        content: { tool: event.tool ?? 'tool', preview: event.preview ?? '' },
      };
      run.state = 'tool';
      run.lastSeq = event.seq;
      this.database.putMessage(tool, { runId, toolCallId }, run);
      this.publishActivity(run);
      return;
    }
    if (event.event === 'tool.completed') {
      const toolCallId = event.tool_call_id;
      const tool = this.database.tool(runId, toolCallId!);
      run.state = 'thinking';
      run.lastSeq = event.seq;
      if (tool?.kind === 'tool') {
        tool.status = 'done';
        tool.content = {
          ...tool.content,
          resultPreview: event.preview ?? '',
          durationMs: Math.round((event.duration ?? 0) * 1000),
          error: event.error === true || event.error === 'true',
        };
        this.database.putMessage(tool, { runId, ...(toolCallId ? { toolCallId } : {}) }, run);
      } else this.database.saveRun(run);
      this.publishActivity(run);
      return;
    }
    if (event.event === 'approval.request') {
      this.persistText(run, this.currentText(run), event.seq);
      const state = await api.state(runId);
      const pending = state.pending_controls?.find(
        (control) => control.prompt_id === event.prompt_id,
      );
      if (!pending) {
        run.lastSeq = event.seq;
        this.database.saveRun(run);
        return;
      }
      const details = pending as typeof pending & { command?: string; description?: string };
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
          requestId: pending.prompt_id,
          executionGeneration: pending.execution_generation ?? event.execution_generation ?? 0,
          prompt:
            details.description ??
            details.command ??
            event.description ??
            event.command ??
            'Approval required',
          ...((details.command ?? event.command)
            ? { command: details.command ?? event.command }
            : {}),
        },
      };
      run.state = 'waiting_approval';
      run.lastSeq = event.seq;
      this.database.putMessage(approval, { runId }, run);
      this.publishActivity(run);
      return;
    }
    if (event.event === 'approval.settled') {
      this.persistText(run, this.currentText(run), event.seq);
      const approval = this.database.approval(runId, event.prompt_id ?? '');
      if (approval?.kind === 'approval') {
        approval.status = 'done';
        this.database.putMessage(approval, { runId }, { ...run, lastSeq: event.seq });
      } else {
        run.lastSeq = event.seq;
        this.database.saveRun(run);
      }
      run.state = 'thinking';
      this.publishActivity(run);
      return;
    }
    if (event.event === 'run.completed') {
      const reply = this.ensureText(run);
      reply.content = { text: event.output ?? reply.content.text };
      reply.status = 'done';
      this.persistText(run, reply, event.seq);
      this.pendingInstruction(run, (await api.state(runId)).pending_steer);
      this.end(run);
      return;
    }
    if (
      event.event === 'run.cancelled' ||
      event.event === 'run.interrupted' ||
      event.event === 'run.failed'
    ) {
      for (const message of this.database.messagesForRun(runId)) {
        if (
          message.status === 'streaming' &&
          (message.kind === 'tool' || message.kind === 'approval')
        ) {
          message.status = event.event === 'run.cancelled' ? 'cancelled' : 'failed';
          this.database.putMessage(message, { runId });
        }
      }
      const reply =
        this.currentText(run) ??
        this.newText(
          run,
          event.event === 'run.cancelled'
            ? 'Run stopped.'
            : (event.output ?? 'Run was interrupted.'),
          event.event === 'run.cancelled' ? 'cancelled' : 'failed',
        );
      if (event.event !== 'run.cancelled' && !reply.content.text)
        reply.content = { text: event.output ?? 'Run failed.' };
      reply.status = event.event === 'run.cancelled' ? 'cancelled' : 'failed';
      this.persistText(run, reply, event.seq);
      this.pendingInstruction(run, (await api.state(runId)).pending_steer);
      this.end(run);
      return;
    }
    run.lastSeq = event.seq;
    this.database.saveRun(run);
  }

  private ensureText(run: RunRecord): TextMessage {
    const current = this.currentText(run);
    if (current) return current;
    const message = this.newText(run, '', 'streaming');
    run.textMessageId = message.messageId;
    const saved = this.database.putMessage(message, { runId: run.runId }, run) as TextMessage;
    this.textProgress.set(saved.messageId, { persistedAt: Date.now(), length: 0 });
    this.streamingTexts.set(saved.messageId, '');
    return saved;
  }

  private currentText(run: RunRecord) {
    const message = run.textMessageId ? this.database.message(run.textMessageId) : undefined;
    if (message?.kind !== 'text') return undefined;
    const current = message as TextMessage;
    const buffered = this.streamingTexts.get(current.messageId);
    if (buffered !== undefined) current.content = { text: buffered };
    return current;
  }

  private newText(run: RunRecord, text: string, status: Message['status']): TextMessage;
  private newText(
    run: RunRecord,
    text: string,
    status: Message['status'],
    kind: 'text',
  ): TextMessage;
  private newText(
    run: RunRecord,
    text: string,
    status: Message['status'],
    kind: 'commentary',
  ): Extract<Message, { kind: 'commentary' }>;
  private newText(
    run: RunRecord,
    text: string,
    status: Message['status'],
    kind: 'text' | 'commentary' = 'text',
  ): TextMessage | Extract<Message, { kind: 'commentary' }> {
    return {
      messageId: randomUUID(),
      conversationId: run.conversationId,
      seq: this.database.head(),
      author: { type: 'bot', id: run.botId },
      kind,
      status,
      createdAt: now(),
      content: { text },
    };
  }

  private persistText(run: RunRecord, message: TextMessage | undefined, seq: number) {
    if (message) {
      message.seq = this.database.head();
      this.textProgress.set(message.messageId, {
        persistedAt: Date.now(),
        length: message.content.text.length,
      });
      this.streamingTexts.set(message.messageId, message.content.text);
      run.lastSeq = seq;
      this.database.putMessage(message, { runId: run.runId }, run);
    } else {
      run.lastSeq = seq;
      this.database.saveRun(run);
    }
  }

  private idle(run: RunRecord): RunRecord {
    return { ...run, state: 'idle' };
  }

  private end(run: RunRecord) {
    run.state = 'idle';
    this.database.saveRun(run);
    this.activeRuns.delete(run.conversationId);
    if (run.runId) this.appliedSeq.delete(run.runId);
    this.publishActivity(run);
  }

  private publishActivity(run: RunRecord) {
    this.onLive({
      kind: 'activity',
      conversationId: run.conversationId,
      botId: run.botId,
      state: run.state,
    });
  }

  private async stop(conversationId: string) {
    const run =
      this.activeRuns.get(conversationId) ??
      this.database.runs().find((item) => item.conversationId === conversationId);
    if (!run?.runId) throw new NodeFault('not_found', 'No active run');
    await (await this.hermes.api(run.botId)).stop(run.runId);
    return {};
  }

  private async respondToApproval(params: RpcParams<'approvals.respond'>) {
    const runId = this.database.messageRun(params.messageId);
    const message = this.database.message(params.messageId);
    if (!runId || message?.kind !== 'approval' || message.status !== 'streaming')
      throw new NodeFault('not_found', 'Approval is no longer pending');
    const run =
      this.activeRuns.get(message.conversationId) ??
      this.database.runs().find((item) => item.runId === runId);
    if (!run) throw new NodeFault('not_found', 'Run is no longer active');
    await (
      await this.hermes.api(run.botId)
    ).approve(runId, message.content.requestId, message.content.executionGeneration, params.choice);
    message.content = { ...message.content, choice: params.choice };
    message.status = 'done';
    run.state = 'thinking';
    this.database.putMessage(message, { runId }, run);
    this.publishActivity(run);
    return {};
  }

  private pendingInstruction(run: RunRecord, text?: string) {
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

  private finishFromState(run: RunRecord, status: string, output?: string, pendingSteer?: string) {
    const activeMessage = this.currentText(run);
    if (status === 'completed') {
      const reply = activeMessage ?? this.newText(run, output ?? '', 'done');
      reply.content = { text: output ?? reply.content.text };
      reply.status = 'done';
      this.persistText(run, reply, run.lastSeq);
    } else if (status === 'cancelled') {
      const reply = activeMessage ?? this.newText(run, 'Run stopped.', 'cancelled');
      reply.status = 'cancelled';
      this.persistText(run, reply, run.lastSeq);
    } else {
      const reply = activeMessage ?? this.newText(run, output ?? 'Run was interrupted.', 'failed');
      if (!reply.content.text) reply.content = { text: output ?? 'Run was interrupted.' };
      reply.status = 'failed';
      this.persistText(run, reply, run.lastSeq);
    }
    this.pendingInstruction(run, pendingSteer);
    this.end(run);
  }

  private finishInterrupted(run: RunRecord, text: string) {
    const message = this.currentText(run) ?? this.newText(run, text, 'failed');
    if (!message.content.text) message.content = { text };
    message.status = 'failed';
    this.database.putMessage(message, { runId: run.runId }, this.idle(run));
    this.activeRuns.delete(run.conversationId);
    this.publishActivity(this.idle(run));
  }
}
