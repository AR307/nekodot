import { RunControls } from './controls';
import { RunEvents } from './events';
import { GroupExecution } from './groups';
import type { NativeAdmission, NativeReplay } from './types';
import { randomUUID } from 'node:crypto';
import { projectGatewayEvent } from '../hermes/events';
import { RunMessages } from './messages';
import { BotSecrets } from '../secrets';
import type { LiveEvent, Message, RpcParams } from '@nekodot/protocol';
import { NodeDatabase, type RunRecord } from '../database';
import type { HermesRuntime } from '../hermes/runtime';
import { HermesGatewayError } from '../hermes/gateway';
import { NodeFault } from '../fault';
import { BotService } from '../bots';
import { MAX_CHAIN } from '../group-routing';
import { Operations } from '../operations';
import { FileLibrary } from '../files';
import { Notifications } from '../notifications';
import { SharedUserMemory } from '../user-memory';
import { Routines } from '../routines';
import { NativeActivity } from '../native-activity';
import { openNativeSession, type NativeSessionSnapshot } from '../hermes/session';
import { ExecutionFlows } from '../flow';

type TextMessage = Extract<Message, { kind: 'text' }>;
const now = () => new Date().toISOString();
/** A visibility hint only; never cancels or restarts the native execution. */
const STALL_MS = 5 * 60_000;
export class ConversationExecution {
  readonly messages: RunMessages;
  readonly controls: RunControls;
  private readonly events: RunEvents;
  private readonly groupExecution: GroupExecution;
  private readonly nativeActivity: NativeActivity;
  private readonly consumers = new Map<string, AbortController>();
  private readonly activeRuns = new Map<string, RunRecord>();
  private readonly appliedSeq = new Map<string, number>();
  private readonly lastFrameAt = new Map<string, number>();
  private readonly stalled = new Set<string>();
  /** Introductions Hermes has not admitted yet; a send queues behind one only once it is admitted. */
  private readonly welcomes = new Map<RunRecord, Promise<void>>();
  private readonly welcomeSends = new Map<string, Promise<{ messageId: string }>>();
  private readonly submissions = new Map<string, Promise<{ messageId: string }>>();
  readonly onLive: (event: LiveEvent) => void;
  get idle() {
    return (
      this.activeRuns.size === 0 &&
      this.consumers.size === 0 &&
      this.database.runs().length === 0 &&
      this.database.chains().length === 0 &&
      !this.operations.list().some((operation) => operation.status === 'running')
    );
  }
  constructor(
    private readonly database: NodeDatabase,
    private readonly hermes: HermesRuntime,
    private readonly bots: BotService,
    private readonly operations: Operations,
    private readonly files: FileLibrary,
    private readonly routines: Routines,
    private readonly secrets: BotSecrets,
    private readonly userMemory: SharedUserMemory,
    private readonly flow: ExecutionFlows,
    private readonly notifications: Notifications,
    onLive: (event: LiveEvent) => void,
  ) {
    this.onLive = onLive;
    this.messages = new RunMessages(this.database, (event) => this.onLive(event));
    this.secrets.onContinue = async (request, submissionId, text) => {
      const gateway = hermes.gateway(request.botId);
      const snapshot = await gateway.rpc<NativeSessionSnapshot>('session.resume', {
        session_id: request.sessionId,
        omit_messages: true,
        defer_history: true,
      });
      const admission = await gateway.rpc<NativeAdmission>('prompt.submit', {
        session_id: snapshot.session_id,
        submission_id: submissionId,
        input_id: submissionId,
        text,
        queued: true,
      });
      const run: RunRecord = {
        botId: request.botId,
        conversationId: request.conversationId,
        inputMessageId: submissionId,
        submissionId,
        runId: admission.admission_id,
        native: true,
        queue: 'queued',
        state: 'thinking',
        sessionId: snapshot.session_id,
        storedSessionId: snapshot.stored_session_id,
        lastSeq: snapshot.last_sequence,
        replayEpoch: snapshot.replay_epoch,
        executionGeneration: admission.execution_generation ?? snapshot.execution_generation,
      };
      this.database.saveRun(run);
      if (admission.status === 'terminal') {
        const receipt = await gateway.rpc<NativeAdmission>('prompt.receipt', {
          session_id: run.sessionId,
          admission_id: run.runId,
          include_result: true,
        });
        await this.finishFromState(
          run,
          receipt.outcome ?? 'failed',
          receipt.result?.final_response,
        );
      } else this.consume(run, gateway);
    };
    this.nativeActivity = new NativeActivity(
      this.database,
      hermes,
      (session, frame, replayEpoch) => {
        if (frame.type === 'review.summary') {
          const text = frame.payload?.text;
          const messageId = `native-review:${session.storedSessionId}:${replayEpoch}:${frame.seq}`;
          if (typeof text === 'string' && text.trim() && !this.database.message(messageId))
            this.database.putMessage({
              messageId,
              conversationId: session.conversationId,
              seq: this.database.head(),
              author: { type: 'bot', id: session.botId },
              kind: 'system',
              status: 'done',
              createdAt: now(),
              content: { text },
            });
          return;
        }
        const admissionId = frame.admission_id ?? frame.payload?.admission_id;
        if (
          typeof admissionId !== 'string' ||
          this.database.runs().some((run) => run.runId === admissionId) ||
          this.database.messagesForRun(admissionId).length
        )
          return;
        const run: RunRecord = {
          botId: session.botId,
          conversationId: session.conversationId,
          inputMessageId: admissionId,
          runId: admissionId,
          native: true,
          storedSessionId: session.storedSessionId,
          sessionId: session.storedSessionId,
          executionGeneration: frame.execution_generation,
          replayEpoch,
          lastSeq: (frame.seq ?? 0) - 1,
          state: 'thinking',
        };
        this.database.saveRun(run);
        this.activeRuns.set(run.conversationId, run);
        this.consume(run, hermes.gateway(run.botId));
      },
    );
    this.controls = new RunControls(
      this.database,
      hermes,
      this.flow,
      this.notifications,
      (id) => this.activeRuns.get(id),
      (run) => this.publishActivity(run),
    );
    this.groupExecution = new GroupExecution(
      this.database,
      this.bots,
      hermes,
      this.messages,
      this.files,
      this.flow,
      this.notifications,
      this.secrets,
      this.userMemory,
      {
        current: (id) => this.activeRuns.get(id),
        activate: (run) => {
          this.activeRuns.set(run.conversationId, run);
        },
        release: (run) => {
          this.activeRuns.delete(run.conversationId);
          if (run.runId) {
            this.appliedSeq.delete(run.runId);
            this.lastFrameAt.delete(run.runId);
            this.stalled.delete(run.runId);
            this.notifications.acknowledge('stalled:' + run.runId);
            this.consumers.get(run.runId)?.abort();
            this.consumers.delete(run.runId);
          }
        },
        publish: (run) => this.publishActivity(run),
        start: (run, input, instructions) => this.startRun(run, input, instructions),
      },
      (event) => this.onLive(event),
    );
    this.events = new RunEvents(
      this.database,
      this.secrets,
      this.flow,
      this.messages,
      this.controls,
      this.notifications,
      this.files,
      (run) => this.publishActivity(run),
      (run, status, output) => this.groupExecution.finishGroupRun(run, status, output),
      (run) => this.end(run),
    );
  }
  activities() {
    const runs = this.database.runs();
    for (const conversation of this.database.conversations()) {
      if (conversation.kind === 'group') {
        const run =
          this.activeRuns.get(conversation.conversationId) ??
          runs.find((item) => item.conversationId === conversation.conversationId);
        const chain = this.database.chain(conversation.conversationId);
        this.onLive({
          kind: 'activity',
          conversationId: conversation.conversationId,
          botId:
            run?.botId ??
            chain?.currentBotId ??
            this.database.group(conversation.groupId)?.leadBotId ??
            '',
          state: run?.state ?? 'idle',
          runId: run?.runId,
          chain: chain ? { count: chain.count, max: MAX_CHAIN } : undefined,
          ...this.stall(run),
        });
        continue;
      }
      const run =
        this.activeRuns.get(conversation.conversationId) ??
        runs.find((item) => item.conversationId === conversation.conversationId);
      this.onLive({
        kind: 'activity',
        conversationId: conversation.conversationId,
        botId: conversation.botId,
        state: run?.state ?? 'idle',
        runId: run?.runId,
        ...this.stall(run),
      });
    }
  }

  async resume() {
    for (const run of this.database.runs()) {
      const conversationId = run.groupId
        ? (this.database
            .conversations()
            .find((item) => item.kind === 'dm' && item.botId === run.botId)?.conversationId ??
          run.conversationId)
        : run.conversationId;
      const session = this.database.hermesSession(conversationId);
      if (!session && !run.storedSessionId) {
        await this.finishInterrupted(
          run,
          'This execution predates the Hermes gateway session and was not restarted.',
        );
        continue;
      }
      const gateway = this.hermes.gateway(run.botId);
      try {
        const priorEpoch = run.replayEpoch ?? session?.replayEpoch;
        let snapshot = await gateway.rpc<NativeSessionSnapshot>('session.resume', {
          session_id: session?.storedSessionId ?? run.storedSessionId,
          defer_history: true,
          omit_messages: true,
        });
        const replayChanged = priorEpoch !== undefined && priorEpoch !== snapshot.replay_epoch;
        if (replayChanged)
          snapshot = await gateway.rpc<NativeSessionSnapshot>('session.resume', {
            session_id: snapshot.stored_session_id,
          });
        run.replayEpoch = snapshot.replay_epoch;
        run.executionGeneration = snapshot.execution_generation;
        run.sessionId = snapshot.session_id;
        run.storedSessionId = snapshot.stored_session_id;
        if (replayChanged) {
          this.messages.reconcileNativeText(run, snapshot);
          run.lastSeq = snapshot.last_sequence;
        }
        this.database.saveRun(run);
        this.database.saveHermesSession({
          conversationId,
          botId: run.botId,
          storedSessionId: snapshot.stored_session_id,
          replayEpoch: snapshot.replay_epoch,
          lastSequence: replayChanged
            ? snapshot.last_sequence
            : (session?.lastSequence ?? snapshot.last_sequence),
        });
        if (!run.runId) {
          const input = this.database.message(run.inputMessageId);
          const chain = run.groupId ? this.database.chain(run.conversationId) : undefined;
          if (run.queue !== 'queued') this.activeRuns.set(run.conversationId, run);
          void this.startRun(
            run,
            chain?.currentInput ?? (input?.kind === 'text' ? input.content.text : ''),
            chain?.currentInstructions,
          );
          continue;
        }
        const receipt = await gateway.rpc<NativeAdmission>('prompt.receipt', {
          session_id: run.sessionId,
          admission_id: run.runId,
          include_result: true,
        });
        if (receipt.status === 'unknown') {
          this.pauseUnknown(run);
        } else if (receipt.status === 'queued' || receipt.status === 'started') {
          if (
            run.queue === 'queued' &&
            receipt.status === 'started' &&
            !snapshot.pending?.some((row) => row.admission_id === run.runId && row.steering)
          ) {
            run.queue = 'started';
            this.queueMessage(run, 'running');
          }
          if (run.queue !== 'queued') this.activeRuns.set(run.conversationId, run);
          if (run.queue !== 'queued')
            this.controls.restoreNativePrompts(run, snapshot.prompts ?? []);
          if (receipt.status === 'started') this.flow.start(run);
          this.publishActivity(run);
          this.consume(run, gateway);
        } else {
          await this.finishFromState(
            run,
            receipt.outcome === 'cancelled'
              ? 'cancelled'
              : receipt.outcome === 'completed'
                ? 'completed'
                : receipt.outcome === 'failed'
                  ? 'failed'
                  : 'interrupted',
            receipt.result?.final_response,
            undefined,
            typeof receipt.outcome === 'string' ? receipt.outcome : undefined,
          );
        }
      } catch (error) {
        if (run.state === 'unknown') this.pauseUnknown(run);
        else if (error instanceof HermesGatewayError && error.message === 'not_found')
          await this.finishInterrupted(
            run,
            'Hermes no longer has this execution. It was not restarted.',
          );
        else {
          if (run.queue !== 'queued') this.activeRuns.set(run.conversationId, run);
          this.publishActivity(run);
          this.consume(run, gateway);
        }
      }
    }
    const activeConversations = new Set(this.database.runs().map((run) => run.conversationId));
    for (const chain of this.database.chains()) {
      if (chain.queue.length && !activeConversations.has(chain.conversationId))
        await this.groupExecution.startNextGroupRun(chain);
    }
    this.nativeActivity.start();
  }

  startWelcome(botId: string, conversationId: string, retry = false) {
    if (this.database.runs().some((run) => run.conversationId === conversationId))
      throw new NodeFault('conflict', 'A conversation run is already active');
    const run: RunRecord = {
      conversationId,
      botId,
      lastSeq: -1,
      state: 'thinking',
      welcome: true,
      inputMessageId: randomUUID(),
      requestId: retry ? randomUUID() : 'welcome:' + botId,
    };
    const message = this.messages.newText(run, '', 'streaming');
    run.inputMessageId = message.messageId;
    run.textMessageId = message.messageId;
    this.activeRuns.set(conversationId, run);
    this.database.putMessage(message, {}, run);
    this.publishActivity(run);
    const admission = this.startRun(
      run,
      'You have just been created as a nekodot Bot. Introduce yourself briefly using your own identity and role, then ask what task the user would like you to work on. Speak directly to the user. Do not claim the user has sent you a message. Do not use tools for this introduction.',
    ).finally(() => this.welcomes.delete(run));
    this.welcomes.set(run, admission);
    return message.messageId;
  }

  async queueInput(
    params: Pick<RpcParams<'commands.execute'>, 'conversationId' | 'botId' | 'clientMsgId'>,
    text: string,
    replacesAdmissionId?: string,
  ) {
    const duplicate = this.database.byClient(params.clientMsgId);
    if (duplicate) return { messageId: duplicate.messageId };
    if (this.database.runs().some((run) => run.botId === params.botId && run.groupId))
      throw new NodeFault(
        'conflict',
        'Finish this Bot’s group turn before queueing a private input.',
      );
    const message: TextMessage = {
      messageId: randomUUID(),
      conversationId: params.conversationId,
      seq: this.database.head(),
      author: { type: 'user' },
      kind: 'text',
      status: 'done',
      createdAt: now(),
      content: { text, queue: 'queued' },
    };
    const run: RunRecord = {
      conversationId: params.conversationId,
      botId: params.botId,
      inputMessageId: message.messageId,
      submissionId: params.clientMsgId,
      lastSeq: -1,
      state: 'thinking',
      queue: 'queued',
      ...(replacesAdmissionId ? { replacesAdmissionId } : {}),
    };
    this.database.putMessage(message, { clientMsgId: params.clientMsgId }, run);
    await this.startRun(run, text);
    return { messageId: message.messageId };
  }

  async sendMessage(
    params: RpcParams<'messages.send'>,
    command?: { botId: string; input: string; modelOverride?: RunRecord['modelOverride'] },
  ): Promise<{ messageId: string }> {
    const pending = this.submissions.get(params.clientMsgId);
    if (pending) return pending;
    const request = this.deliverMessage(params, command).finally(() =>
      this.submissions.delete(params.clientMsgId),
    );
    this.submissions.set(params.clientMsgId, request);
    return request;
  }

  private async deliverMessage(
    params: RpcParams<'messages.send'>,
    command?: { botId: string; input: string; modelOverride?: RunRecord['modelOverride'] },
  ): Promise<{ messageId: string }> {
    const duplicate = this.database.byClient(params.clientMsgId);
    if (duplicate) return { messageId: duplicate.messageId };
    if (this.database.setting(`steer:${params.clientMsgId}`))
      throw new NodeFault(
        'conflict',
        'The original instruction has an unconfirmed receipt; it was not repeated.',
      );
    if (
      params.sessionId &&
      params.sessionId !== this.database.hermesSession(params.conversationId)?.storedSessionId
    )
      throw new NodeFault('conflict', 'The original conversation session has changed.');
    const conversation = this.database.conversation(params.conversationId);
    if (!conversation) throw new NodeFault('not_found', 'Conversation not found');
    const targets =
      conversation.kind === 'dm'
        ? [conversation.botId]
        : (this.database.group(conversation.groupId)?.botIds ?? []);
    if (
      !command &&
      this.operations
        .list()
        .some(
          (op) =>
            op.kind.startsWith('command:') &&
            op.status === 'running' &&
            op.botIds.some((id) => targets.includes(id)),
        )
    )
      throw new NodeFault(
        'conflict',
        'Wait for the Hermes command to finish before sending. Your draft is kept.',
      );
    if (!params.text.trim() && !params.files?.length)
      throw new NodeFault('invalid_params', 'Write a message or attach a file.');
    if (
      command?.modelOverride &&
      this.database
        .runs()
        .some((run) => run.botId === command.botId || run.conversationId === params.conversationId)
    )
      throw new NodeFault(
        'conflict',
        'Wait for the current task before starting a one-turn model command. No input was sent.',
      );
    if (
      params.files?.length &&
      this.database.runs().some((run) => run.conversationId === params.conversationId)
    )
      throw new NodeFault(
        'conflict',
        'Hermes steer accepts text only. Wait for this run to finish or stop it before sending attachments.',
      );
    if (conversation.kind === 'group') {
      if (params.routineExecutionId)
        throw new NodeFault(
          'invalid_params',
          'Continue a routine in its Bot private conversation.',
        );
      return this.groupExecution.sendGroupMessage(params, conversation, command);
    }
    const bot = this.bots.get(conversation.botId);
    const active =
      this.activeRuns.get(conversation.conversationId) ??
      this.database.runs().find((run) => run.conversationId === conversation.conversationId);
    const routine = params.routineExecutionId
      ? this.routines.execution(bot.botId, params.routineExecutionId)
      : undefined;
    if (routine && active)
      throw new NodeFault(
        'conflict',
        'Wait for the current task before discussing a routine result. Your draft is kept.',
      );
    const userMessage: Message = {
      messageId: randomUUID(),
      conversationId: conversation.conversationId,
      seq: this.database.head(),
      author: { type: 'user' },
      kind: 'text',
      status: 'done',
      createdAt: now(),
      content: {
        text: params.text,
        ...(routine
          ? {
              routine: {
                routineId: routine.routineId,
                executionId: routine.executionId,
                sessionId: routine.sessionId,
              },
            }
          : {}),
      },
    };

    if (active) {
      // A new Bot's gateway may still be starting; a resend of the same draft shares the wait.
      const welcome = this.welcomes.get(active);
      if (welcome) {
        const waiting =
          this.welcomeSends.get(params.clientMsgId) ??
          welcome
            .finally(() => this.welcomeSends.delete(params.clientMsgId))
            .then(() => this.deliverMessage(params, command));
        this.welcomeSends.set(params.clientMsgId, waiting);
        return waiting;
      }
      this.activeRuns.set(active.conversationId, active);
      if (active.state === 'unknown')
        throw new NodeFault(
          'conflict',
          'The previous execution was interrupted. Click Stop to acknowledge it before sending a new task. Completed effects will be kept.',
        );
      if (active.state === 'waiting_approval' || active.state === 'waiting_question')
        throw new NodeFault(
          'conflict',
          'Resolve the pending approval or stop this run before sending.',
        );
      if (!active.runId || !active.sessionId || active.executionGeneration === undefined)
        throw new NodeFault('conflict', 'The current run is starting. Try again shortly.');
      // An introduction is not a task to correct: the user's message is its own turn after it.
      if (active.welcome) return this.queueInput({ ...params, botId: bot.botId }, params.text);
      const steerKey = `steer:${params.clientMsgId}`;
      if (this.database.setting(steerKey))
        throw new NodeFault(
          'conflict',
          'The original instruction has an unconfirmed receipt; it was not repeated.',
        );
      this.database.setSetting(steerKey, { runId: active.runId });
      const accepted = await this.hermes.gateway(bot.botId).rpc<{
        status: 'queued' | 'redirected' | 'rejected';
        execution_generation: number;
      }>('session.steer', {
        session_id: active.sessionId,
        execution_generation: active.executionGeneration,
        text: params.text,
      });
      if (accepted.status === 'rejected')
        throw new NodeFault(
          'conflict',
          'Hermes did not accept this instruction. You can send it again.',
        );
      active.executionGeneration = accepted.execution_generation;
      const previousReply = this.messages.currentText(active);
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
      ...(command?.modelOverride ? { modelOverride: command.modelOverride } : {}),
    };
    if (params.files?.length) this.files.attach(userMessage, params.files);
    if (run.queue !== 'queued') this.activeRuns.set(run.conversationId, run);
    userMessage.seq = this.database.head();
    this.database.putMessage(userMessage, { clientMsgId: params.clientMsgId }, run);
    this.publishActivity(run);
    void this.startRun(run, command?.input ?? params.text);
    return { messageId: userMessage.messageId };
  }

  private async startRun(run: RunRecord, input: string, instructions?: string) {
    try {
      this.secrets.attach(run.botId);
      await this.userMemory.sync();
      // Sources are applied when a Bot or its source changes: /api/model/set probes the provider
      // catalog, which can outlast the 30 s management deadline.
      await this.hermes.syncRules(this.bots.get(run.botId));
      const conversationId = run.groupId
        ? this.database
            .conversations()
            .find((conversation) => conversation.kind === 'dm' && conversation.botId === run.botId)
            ?.conversationId
        : run.conversationId;
      if (!conversationId) throw new Error('Bot private conversation is missing');
      const attachments = run.groupId
        ? this.database
            .messagesAfter(
              run.conversationId,
              this.database.chain(run.conversationId)?.cursorByBot[run.botId] ?? 0,
            )
            .flatMap((message) => (message.kind === 'text' ? (message.content.files ?? []) : []))
        : (this.database.message(run.inputMessageId) as TextMessage | undefined)?.content.files;
      const gateway = this.hermes.gateway(run.botId);
      const snapshot = await openNativeSession(
        this.database,
        this.hermes,
        run.botId,
        conversationId,
      );
      const inputMessage = this.database.message(run.inputMessageId);
      const routineContext =
        run.welcome || run.groupId
          ? { text: '', until: undefined, key: '' }
          : await this.routines.context(
              run.botId,
              snapshot.stored_session_id,
              inputMessage?.kind === 'text' ? inputMessage.content.routine?.executionId : undefined,
            );
      run.sessionId = snapshot.session_id;
      run.storedSessionId = snapshot.stored_session_id;
      run.replayEpoch = snapshot.replay_epoch;
      run.lastSeq = snapshot.last_sequence;
      run.submissionId ??= run.requestId ?? run.inputMessageId;
      this.database.saveRun(run);
      const nativeInput = await this.files.gatewayInput(
        run.botId,
        [instructions, input + routineContext.text].filter(Boolean).join('\n\n'),
        attachments,
      );
      const admission = await gateway.rpc<NativeAdmission>(
        run.replacesAdmissionId ? 'prompt.replace_queued' : 'prompt.submit',
        {
          session_id: run.sessionId,
          text: nativeInput.text,
          submission_id: run.submissionId,
          ...(run.modelOverride ? { model_override: run.modelOverride } : {}),
          ...(run.replacesAdmissionId
            ? { admission_id: run.replacesAdmissionId }
            : { input_id: run.inputMessageId, ...(run.queue ? { queued: true } : {}) }),
          ...(nativeInput.attachments.length ? { attachments: nativeInput.attachments } : {}),
        },
      );
      run.runId = admission.admission_id;
      run.executionGeneration = admission.execution_generation ?? snapshot.execution_generation;
      run.state = 'thinking';
      if (routineContext.until) this.database.setSetting(routineContext.key, routineContext.until);
      if (this.database.message(run.inputMessageId))
        this.database.setMessageRun(run.inputMessageId, admission.admission_id);
      this.database.saveRun(run);
      if (admission.status === 'started' && run.queue !== 'queued') this.flow.start(run);
      if (admission.status === 'unknown') {
        this.pauseUnknown(run);
      } else if (admission.status === 'terminal') {
        const receipt = await gateway.rpc<NativeAdmission>('prompt.receipt', {
          session_id: run.sessionId,
          admission_id: admission.admission_id,
          include_result: true,
        });
        await this.finishFromState(
          run,
          receipt.outcome === 'cancelled'
            ? 'cancelled'
            : receipt.outcome === 'completed'
              ? 'completed'
              : receipt.outcome === 'failed'
                ? 'failed'
                : 'interrupted',
          receipt.result?.final_response,
          undefined,
          receipt.outcome ?? undefined,
        );
      } else this.consume(run, gateway);
    } catch (error) {
      const failed = this.messages.currentText(run) ?? this.messages.newText(run, '', 'failed');
      failed.status = 'failed';
      failed.content.failureReason =
        error instanceof NodeFault
          ? error.message
          : 'Could not start this run. Check the provider and try again.';
      const failureCode = !(error instanceof NodeFault)
        ? 'run_start'
        : error.code === 'timeout'
          ? 'timeout'
          : undefined;
      if (failureCode) failed.content.failureCode = failureCode;
      const idle = this.idleRun(run);
      this.database.putMessage(failed, { runId: run.runId }, idle);
      if (run.groupId) await this.groupExecution.finishGroupRun(run, 'failed', failed.content.text);
      else {
        this.notifications.send({
          notificationId: `request:${run.inputMessageId}`,
          conversationId: run.conversationId,
          kind: 'failed',
        });
        this.end(idle);
      }
    }
  }

  private consume(run: RunRecord, gateway: ReturnType<HermesRuntime['gateway']>) {
    if (!run.runId || this.consumers.has(run.runId)) return;
    const controller = new AbortController();
    this.consumers.set(run.runId, controller);
    void this.readRun(run, gateway, controller.signal).finally(() => {
      if (run.runId) this.consumers.delete(run.runId);
    });
  }

  private async readRun(
    run: RunRecord,
    gateway: ReturnType<HermesRuntime['gateway']>,
    signal: AbortSignal,
  ) {
    let reconnectDelay = 500;
    let disconnected = false;
    let attachedGeneration = -1;
    this.lastFrameAt.set(run.runId!, Date.now());
    while (!signal.aborted && run.runId) {
      try {
        if (attachedGeneration !== gateway.generation) {
          const snapshot = await gateway.rpc<NativeSessionSnapshot>('session.resume', {
            session_id: run.storedSessionId!,
          });
          const replayChanged = run.replayEpoch !== snapshot.replay_epoch;
          run.replayEpoch = snapshot.replay_epoch;
          run.sessionId = snapshot.session_id;
          run.storedSessionId = snapshot.stored_session_id;
          run.executionGeneration = snapshot.execution_generation;
          if (replayChanged) {
            this.messages.reconcileNativeText(run, snapshot);
            run.lastSeq = snapshot.last_sequence;
          }
          if (run.queue !== 'queued')
            this.controls.restoreNativePrompts(run, snapshot.prompts ?? []);
          const session = this.database.hermesSession(
            run.groupId
              ? (this.database
                  .conversations()
                  .find((item) => item.kind === 'dm' && item.botId === run.botId)?.conversationId ??
                  run.conversationId)
              : run.conversationId,
          );
          if (session && session.storedSessionId === snapshot.stored_session_id)
            this.database.saveHermesSession({
              ...session,
              storedSessionId: snapshot.stored_session_id,
              replayEpoch: snapshot.replay_epoch,
              ...(replayChanged ? { lastSequence: snapshot.last_sequence } : {}),
            });
          this.database.saveRun(run);
          attachedGeneration = gateway.generation;
        }
        const replay = await gateway.rpc<NativeReplay>('session.events.since', {
          session_id: run.sessionId!,
          last_sequence: Math.max(run.lastSeq, this.appliedSeq.get(run.runId) ?? 0),
          replay_epoch: run.replayEpoch,
        });
        if (disconnected) {
          disconnected = false;
          this.watchProgress(run, true);
          this.publishActivity(run);
        }
        if (replay.snapshot_required || replay.truncated) {
          const snapshot = await gateway.rpc<NativeSessionSnapshot>('session.resume', {
            session_id: run.storedSessionId!,
          });
          run.replayEpoch = snapshot.replay_epoch;
          run.sessionId = snapshot.session_id;
          run.storedSessionId = snapshot.stored_session_id;
          run.lastSeq = snapshot.last_sequence;
          run.executionGeneration = snapshot.execution_generation;
          this.messages.reconcileNativeText(run, snapshot);
          if (run.queue !== 'queued')
            this.controls.restoreNativePrompts(run, snapshot.prompts ?? []);
          const session = this.database.hermesSession(
            run.groupId
              ? (this.database
                  .conversations()
                  .find((item) => item.kind === 'dm' && item.botId === run.botId)?.conversationId ??
                  run.conversationId)
              : run.conversationId,
          );
          if (session)
            this.database.saveHermesSession({
              ...session,
              storedSessionId: snapshot.stored_session_id,
              replayEpoch: snapshot.replay_epoch,
              lastSequence: snapshot.last_sequence,
            });
          this.database.saveRun(run);
          this.watchProgress(run, true);
        } else {
          let progressed = false;
          for (const frame of replay.events) {
            if (signal.aborted) return;
            const sequence = frame.seq ?? -1;
            if (sequence <= Math.max(run.lastSeq, this.appliedSeq.get(run.runId) ?? -1)) continue;
            // A session can also carry background completions for another admission.
            progressed ||=
              frame.admission_id === run.runId || frame.payload?.admission_id === run.runId;
            const event = projectGatewayEvent(run, frame);
            if (event && !(run.queue === 'queued' && event.event.startsWith('run.'))) {
              if (run.queue === 'queued' && event.event !== 'run.cancelled') {
                run.queue = 'started';
                this.activeRuns.set(run.conversationId, run);
                this.queueMessage(run, 'running');
                this.publishActivity(run);
              }
              if (frame.execution_generation !== undefined)
                run.executionGeneration = frame.execution_generation;
              await this.events.accept(run, event);
            }
            this.appliedSeq.set(run.runId, sequence);
            if (run.lastSeq >= sequence) {
              const session = this.database.hermesSession(
                run.groupId
                  ? (this.database
                      .conversations()
                      .find((item) => item.kind === 'dm' && item.botId === run.botId)
                      ?.conversationId ?? run.conversationId)
                  : run.conversationId,
              );
              if (session && session.storedSessionId === run.storedSessionId)
                this.database.saveHermesSession({
                  ...session,
                  replayEpoch: replay.replay_epoch,
                  lastSequence: Math.max(session.lastSequence, sequence),
                });
            }
            if (run.state === 'idle' || run.state === 'unknown') return;
          }
          run.replayEpoch = replay.replay_epoch;
          const receipt = await gateway.rpc<NativeAdmission>('prompt.receipt', {
            session_id: run.sessionId!,
            admission_id: run.runId,
          });
          if (receipt.status === 'unknown') {
            this.pauseUnknown(run);
            return;
          }
          if (receipt.status === 'started' && run.queue === 'queued') {
            const snapshot = await gateway.rpc<NativeSessionSnapshot>('session.resume', {
              session_id: run.storedSessionId!,
              omit_messages: true,
            });
            // A native steer transfer also reads as started, but owns no separate turn or prompts.
            if (!snapshot.pending?.some((row) => row.admission_id === run.runId && row.steering)) {
              run.queue = 'started';
              run.executionGeneration = receipt.execution_generation ?? run.executionGeneration;
              this.activeRuns.set(run.conversationId, run);
              this.flow.start(run);
              this.queueMessage(run, 'running');
              this.controls.restoreNativePrompts(run, snapshot.prompts ?? []);
              this.database.saveRun(run);
              this.publishActivity(run);
            }
          }
          if (receipt.status === 'terminal') {
            const completed = await gateway.rpc<NativeAdmission>('prompt.receipt', {
              session_id: run.sessionId!,
              admission_id: run.runId,
              include_result: true,
            });
            if (
              run.queue === 'queued' &&
              (completed.outcome === 'cancelled' || completed.outcome === 'steered')
            ) {
              this.queueMessage(run, completed.outcome);
              this.end(run);
              return;
            }
            await this.finishFromState(
              run,
              completed.outcome === 'cancelled'
                ? 'cancelled'
                : completed.outcome === 'completed'
                  ? 'completed'
                  : completed.outcome === 'failed'
                    ? 'failed'
                    : 'interrupted',
              completed.result?.final_response,
              undefined,
              completed.outcome ?? undefined,
            );
            return;
          }
          this.watchProgress(run, progressed);
        }
        reconnectDelay = 500;
      } catch (error) {
        if (signal.aborted) return;
        if (!disconnected) {
          disconnected = true;
          this.messages.persistText(run, this.messages.currentText(run), run.lastSeq);
          this.onLive({
            kind: 'activity',
            conversationId: run.conversationId,
            botId: run.botId,
            state: run.state,
            connection: 'reconnecting',
            detail: error instanceof Error ? error.message : 'Hermes stream disconnected',
          });
        }
      }
      if (signal.aborted) return;
      await new Promise((resolve) => setTimeout(resolve, reconnectDelay));
      reconnectDelay = Math.min(reconnectDelay * 2, 10000);
    }
  }

  private idleRun(run: RunRecord): RunRecord {
    return { ...run, state: 'idle' };
  }

  private end(run: RunRecord) {
    void this.secrets
      .finish(run)
      .catch(() => console.warn('Temporary profile vault cleanup needs retry'));
    run.state = 'idle';
    this.database.saveRun(run);
    if (this.activeRuns.get(run.conversationId)?.runId === run.runId)
      this.activeRuns.delete(run.conversationId);
    if (run.runId) {
      this.appliedSeq.delete(run.runId);
      this.lastFrameAt.delete(run.runId);
      this.stalled.delete(run.runId);
      this.notifications.acknowledge('stalled:' + run.runId);
    }
    this.publishActivity(run);
    void this.userMemory.sync();
  }

  private stall(run?: RunRecord) {
    return run?.runId && this.stalled.has(run.runId) ? { stalled: true as const } : {};
  }

  /** Hermes frames are the only progress Node sees; silence is shown, never acted on. */
  private watchProgress(run: RunRecord, progressed: boolean) {
    const runId = run.runId!;
    if (
      progressed ||
      run.queue === 'queued' ||
      run.state === 'waiting_approval' ||
      run.state === 'waiting_question'
    ) {
      this.lastFrameAt.set(runId, Date.now());
      if (this.stalled.delete(runId)) {
        this.notifications.acknowledge('stalled:' + runId);
        this.publishActivity(run);
      }
      return;
    }
    if (this.stalled.has(runId) || Date.now() - this.lastFrameAt.get(runId)! < STALL_MS) return;
    this.stalled.add(runId);
    this.publishActivity(run);
    this.notifications.send({
      notificationId: 'stalled:' + runId,
      conversationId: run.conversationId,
      kind: 'stalled',
    });
  }

  private publishActivity(run: RunRecord) {
    if (run.queue === 'queued') return;
    const current = this.activeRuns.get(run.conversationId);
    if (run.state === 'idle' && current && current.runId !== run.runId) return;
    const chain = run.groupId ? this.database.chain(run.conversationId) : undefined;
    if (chain) this.flow.group(chain);
    this.onLive({
      kind: 'activity',
      conversationId: run.conversationId,
      runId: run.runId,
      botId: run.botId,
      state: run.state,
      chain: chain ? { count: chain.count, max: MAX_CHAIN } : undefined,
      ...this.stall(run),
    });
  }

  private queueMessage(run: RunRecord, state: 'running' | 'cancelled' | 'steered') {
    const message = this.database.message(run.inputMessageId) as TextMessage | undefined;
    if (!message) return;
    message.content.queue = state;
    if (state === 'cancelled') message.status = 'cancelled';
    this.database.putMessage(message, { runId: run.runId });
  }

  async stop(conversationId: string, runId?: string) {
    const run =
      this.activeRuns.get(conversationId) ??
      this.database.runs().find((item) => item.conversationId === conversationId);
    if (runId && run?.runId !== runId) return {};
    if (!run?.runId || !run.sessionId || run.executionGeneration === undefined)
      throw new NodeFault('not_found', 'No active run');
    run.stopRequested = true;
    this.database.saveRun(run);
    try {
      const gateway = this.hermes.gateway(run.botId);
      const receipt = await gateway.rpc<NativeAdmission>('prompt.receipt', {
        session_id: run.sessionId,
        admission_id: run.runId,
      });
      if (receipt.status === 'unknown') {
        await gateway.rpc('prompt.resolve_unknown', {
          session_id: run.sessionId,
          admission_id: run.runId,
          execution_generation: run.executionGeneration,
        });
        this.consumers.get(run.runId)?.abort();
        if (run.groupId) this.database.clearChain(conversationId);
        await this.finishFromState(run, 'cancelled');
      } else if (receipt.status === 'queued') {
        await gateway.rpc('prompt.cancel', {
          session_id: run.sessionId,
          admission_id: run.runId,
        });
        this.consumers.get(run.runId)?.abort();
        if (run.groupId) this.database.clearChain(conversationId);
        await this.finishFromState(run, 'cancelled');
      } else if (receipt.status === 'terminal') {
        await this.finishFromState(
          run,
          receipt.outcome === 'completed'
            ? 'completed'
            : receipt.outcome === 'failed'
              ? 'failed'
              : 'cancelled',
        );
      } else {
        run.executionGeneration = receipt.execution_generation ?? run.executionGeneration;
        await gateway.rpc('session.interrupt', {
          session_id: run.sessionId,
          execution_generation: run.executionGeneration,
        });
      }
    } catch (error) {
      run.stopRequested = false;
      this.database.saveRun(run);
      throw error;
    }
    if (run.groupId) this.database.clearChain(conversationId);
    return {};
  }

  private pauseUnknown(run: RunRecord) {
    if (run.runId) {
      this.lastFrameAt.delete(run.runId);
      this.stalled.delete(run.runId);
      this.notifications.acknowledge('stalled:' + run.runId);
    }
    this.flow.finish(run, 'unknown');
    this.controls.settleControls(run, 'failed');
    const reply = this.messages.currentText(run) ?? this.messages.newText(run, '', 'failed');
    reply.status = 'failed';
    reply.content.failureReason =
      'Hermes lost the execution during a restart. Click Stop to acknowledge the interrupted task, then send a new message. Completed effects are kept; this task will not be replayed.';
    run.textMessageId = reply.messageId;
    run.state = 'unknown';
    this.activeRuns.set(run.conversationId, run);
    this.messages.persistText(run, reply, run.lastSeq);
    this.publishActivity(run);
  }

  private async finishFromState(
    run: RunRecord,
    status: string,
    output?: string,
    pendingSteer?: string,
    failureReason?: string,
  ) {
    if (output) output = this.secrets.scrub(run.botId, output);
    if (
      run.queue === 'queued' &&
      ['cancelled', 'steered', 'replaced'].includes(failureReason ?? status)
    ) {
      this.queueMessage(run, failureReason === 'steered' ? 'steered' : 'cancelled');
      this.end(run);
      return;
    }
    if (run.queue === 'queued') {
      run.queue = 'started';
      this.queueMessage(run, 'running');
    }
    this.flow.start(run);
    this.flow.finish(
      run,
      status === 'cancelled' ? 'cancelled' : status === 'completed' ? 'done' : 'failed',
    );
    this.controls.settleControls(
      run,
      status === 'cancelled' ? 'cancelled' : status === 'completed' ? 'done' : 'failed',
    );
    const activeMessage = this.messages.currentText(run);
    if (activeMessage && status !== 'completed' && status !== 'cancelled')
      activeMessage.content.failureReason =
        failureReason ?? 'Hermes interrupted this turn. The task was not restarted.';
    if (run.groupId) {
      const reply = activeMessage ?? this.messages.newText(run, output ?? '', 'done');
      reply.content = { ...reply.content, text: output ?? reply.content.text };
      reply.status =
        status === 'cancelled' ? 'cancelled' : status === 'completed' ? 'done' : 'failed';
      if (status === 'cancelled') delete reply.content.failureReason;
      if (status === 'completed') await this.files.capture(reply);
      this.messages.persistText(run, reply, run.lastSeq);
      this.controls.pendingInstruction(run, pendingSteer);
      await this.groupExecution.finishGroupRun(
        run,
        status === 'cancelled' ? 'cancelled' : status === 'completed' ? 'completed' : 'failed',
        output ?? activeMessage?.content.text ?? '',
      );
      return;
    }
    if (status === 'completed') {
      const reply = activeMessage ?? this.messages.newText(run, output ?? '', 'done');
      reply.content = { ...reply.content, text: output ?? reply.content.text };
      reply.status = 'done';
      await this.files.capture(reply);
      this.messages.persistText(run, reply, run.lastSeq);
    } else if (status === 'cancelled') {
      const reply = activeMessage ?? this.messages.newText(run, 'Run stopped.', 'cancelled');
      if (!reply.content.text) reply.content.text = 'Run stopped.';
      delete reply.content.failureReason;
      reply.status = 'cancelled';
      this.messages.persistText(run, reply, run.lastSeq);
    } else {
      const reply =
        activeMessage ?? this.messages.newText(run, output ?? 'Run was interrupted.', 'failed');
      if (!reply.content.text)
        reply.content = { ...reply.content, text: output ?? 'Run was interrupted.' };
      reply.content.failureReason =
        failureReason ?? 'Hermes interrupted this turn. The task was not restarted.';
      reply.status = 'failed';
      this.messages.persistText(run, reply, run.lastSeq);
    }
    this.controls.pendingInstruction(run, pendingSteer);
    if (status !== 'cancelled')
      this.notifications.send({
        notificationId: `run:${run.runId}`,
        conversationId: run.conversationId,
        kind: status === 'completed' ? 'completed' : 'failed',
      });
    this.end(run);
  }

  private async finishInterrupted(run: RunRecord, text: string) {
    this.flow.finish(run, 'failed');
    this.controls.settleControls(run, 'failed');
    const message = this.messages.currentText(run) ?? this.messages.newText(run, text, 'failed');
    if (!message.content.text) message.content = { ...message.content, text };
    message.content.failureReason = text;
    message.status = 'failed';
    this.database.putMessage(message, { runId: run.runId }, this.idleRun(run));
    run.state = 'idle';
    if (run.groupId) {
      await this.groupExecution.finishGroupRun(run, 'failed', text);
      return;
    }
    this.activeRuns.delete(run.conversationId);
    this.publishActivity(this.idleRun(run));
    await this.userMemory.sync();
    this.notifications.send({
      notificationId: `run:${run.runId}`,
      conversationId: run.conversationId,
      kind: 'failed',
    });
  }
  stopWatching() {
    return this.nativeActivity.close();
  }
  close() {
    for (const run of this.activeRuns.values())
      this.messages.persistText(
        run,
        this.messages.currentText(run),
        run.runId ? (this.appliedSeq.get(run.runId) ?? run.lastSeq) : run.lastSeq,
      );
    for (const consumer of this.consumers.values()) consumer.abort();
    this.consumers.clear();
  }
}
