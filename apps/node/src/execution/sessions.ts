import { DotTasks } from './tasks';
import { RunControls } from './controls';
import { RunEvents } from './events';
import { GroupExecution } from './groups';
import type { NativeAdmission, NativeReplay } from './types';
import { randomUUID } from 'node:crypto';
import { projectGatewayEvent } from '../hermes/events';
import { RunMessages } from './messages';
import { BotSecrets } from '../secrets';
import type { NodeConnectors } from '../connectors';
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
  readonly tasks: DotTasks;
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
    private readonly connectors?: NodeConnectors,
  ) {
    this.onLive = onLive;
    this.tasks = new DotTasks(database, hermes, {
      start: (run, input) => this.startRun(run, input),
      stop: (conversationId, runId) => this.stop(conversationId, runId),
      answer: (messageId, answer) => this.controls.respondToQuestion({ messageId, answer }),
      connectionPending: (taskId) => this.connectors?.pending(taskId) ?? false,
      cancelConnection: (taskId) => this.connectors?.cancelTask(taskId) ?? false,
    });
    if (this.connectors)
      this.connectors.onContinue = (taskId, submissionId, text) =>
        this.tasks.continueExternalInput(taskId, submissionId, text);
    this.routines.onTask = (value) => this.tasks.local(value);
    this.routines.onExecution = async (routine, execution, conversationId, prompts, generation) => {
      const run = this.tasks.background(routine, execution, conversationId, generation);
      if (['completed', 'failed', 'cancelled'].includes(execution.state)) {
        run.textMessageId = 'routine-result:' + execution.executionId;
        this.controls.settleControls(
          run,
          execution.state === 'completed'
            ? 'done'
            : execution.state === 'cancelled'
              ? 'cancelled'
              : 'failed',
        );
        this.end(run);
        await this.tasks.finished(run, execution.state as 'completed' | 'failed' | 'cancelled');
        await this.connectors?.settled(run);
      } else {
        await this.controls.restoreNativePrompts(run, prompts);
        this.publishActivity(run);
      }
    };
    this.messages = new RunMessages(this.database, (event) => this.onLive(event));
    this.secrets.onContinue = async (request, submissionId, text) => {
      if (request.taskId)
        return this.tasks.continueExternalInput(request.taskId, submissionId, text);
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
        const conversationId = session.ownerConversationId ?? session.conversationId;
        const conversation = this.database.conversation(conversationId);
        if (!conversation) return;
        if (frame.type === 'review.summary') {
          const text = frame.payload?.text;
          const owner = this.database.db
            .prepare(
              "SELECT task_id FROM task_executions WHERE json_extract(data,'$.sessionKey')=? ORDER BY rowid DESC LIMIT 1",
            )
            .get(session.conversationId);
          const messageId = `native-review:${session.storedSessionId}:${replayEpoch}:${frame.seq}`;
          if (typeof text === 'string' && text.trim() && !this.database.message(messageId))
            this.database.putMessage({
              messageId,
              ...(owner ? { taskId: String(owner.task_id), taskRole: 'execution' as const } : {}),
              conversationId,
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
          conversationId,
          sessionKey: session.conversationId,
          role: 'coordinator',
          ...(conversation.kind === 'group' ? { groupId: conversation.groupId } : {}),
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
        this.tasks.nativeContinuation(run);
        this.database.saveRun(run);
        this.activeRuns.set(run.inputMessageId, run);
        this.consume(run, hermes.gateway(run.botId));
      },
    );
    this.controls = new RunControls(
      this.database,
      hermes,
      this.flow,
      this.notifications,
      (run) => this.publishActivity(run),
      (run, question) => this.tasks.consult(run, question),
    );
    this.groupExecution = new GroupExecution(
      this.database,
      this.bots,
      this.messages,
      this.files,
      this.flow,
      this.notifications,
      this.secrets,
      this.userMemory,
      {
        current: (id) => this.current(id),
        activate: (run) => {
          this.activeRuns.set(run.inputMessageId, run);
        },
        release: (run) => {
          this.messages.release(run.textMessageId);
          this.activeRuns.delete(run.inputMessageId);
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
      (run, status, output) => this.finishRun(run, status, output),
    );
  }
  private current(conversationId: string) {
    return [...this.activeRuns.values()].find(
      (run) =>
        run.conversationId === conversationId &&
        run.role !== 'execution' &&
        run.queue !== 'queued' &&
        run.state !== 'idle',
    );
  }

  activities() {
    const runs = this.database.runs();
    for (const run of runs) if (run.role === 'execution') this.publishActivity(run);
    for (const conversation of this.database.conversations()) {
      if (conversation.kind === 'group') {
        const run =
          this.current(conversation.conversationId) ??
          runs.find(
            (item) =>
              item.conversationId === conversation.conversationId && item.role !== 'execution',
          );
        const chain = this.database
          .chains()
          .find((c) => c.conversationId === conversation.conversationId);
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
        this.current(conversation.conversationId) ??
        runs.find(
          (item) =>
            item.conversationId === conversation.conversationId && item.role !== 'execution',
        );
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
      if (run.background) continue;
      const conversationId =
        run.sessionKey ??
        (run.groupId ? 'group:' + run.conversationId + ':' + run.botId : run.conversationId);
      if (!run.runId && run.role && run.pendingInput !== undefined) {
        await this.startRun(run, run.pendingInput);
        continue;
      }
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
          session_id: run.storedSessionId ?? session?.storedSessionId,
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
          ownerConversationId: run.conversationId,
          botId: run.botId,
          storedSessionId: snapshot.stored_session_id,
          replayEpoch: snapshot.replay_epoch,
          lastSequence: replayChanged
            ? snapshot.last_sequence
            : (session?.lastSequence ?? snapshot.last_sequence),
        });
        if (!run.runId) {
          const input = this.database.message(run.inputMessageId);
          const chain = run.groupId
            ? this.database.chain(run.groupChainId ?? run.conversationId)
            : undefined;
          if (run.queue !== 'queued') this.activeRuns.set(run.inputMessageId, run);
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
          if (run.queue !== 'queued') this.activeRuns.set(run.inputMessageId, run);
          if (run.queue !== 'queued')
            await this.controls.restoreNativePrompts(run, snapshot.prompts ?? []);
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
          if (run.queue !== 'queued') this.activeRuns.set(run.inputMessageId, run);
          this.publishActivity(run);
          this.consume(run, gateway);
        }
      }
    }
    const activeChains = new Set(this.database.runs().map((run) => run.groupChainId));
    for (const chain of this.database.chains()) {
      const waiting = chain.taskId && !this.database.task(chain.taskId)?.reportMessageId;
      if (
        chain.queue.length &&
        !chain.currentBotId &&
        !activeChains.has(chain.notificationId) &&
        !waiting
      )
        await this.groupExecution.startNextGroupRun(chain);
    }
    await this.tasks.recoverReports();
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
      role: 'coordinator',
      inputMessageId: randomUUID(),
      requestId: retry ? randomUUID() : 'welcome:' + botId,
    };
    const message = this.messages.newText(run, '', 'streaming');
    run.inputMessageId = message.messageId;
    run.textMessageId = message.messageId;
    this.activeRuns.set(run.inputMessageId, run);
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
      role: 'coordinator',
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
    if (
      params.taskId &&
      this.database.task(params.taskId)?.conversationId !== params.conversationId
    )
      throw new NodeFault('not_found', 'Task not found in this chat');
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
    if (params.routineExecutionId) {
      const task = this.database
        .tasks(params.conversationId)
        .find((t) => t.routineExecutionId === params.routineExecutionId);
      if (!task) throw new NodeFault('not_found', 'Routine task not found in this chat');
      params = { ...params, taskId: task.taskId };
    }
    if (
      params.spaceId &&
      this.database.space(params.spaceId)?.conversationId !== params.conversationId
    )
      throw new NodeFault('not_found', 'Space not found in this chat');
    if (conversation.kind === 'group')
      return this.groupExecution.sendGroupMessage(params, conversation, command);
    const bot = this.bots.get(conversation.botId);
    const active =
      this.current(conversation.conversationId) ??
      this.database
        .runs()
        .find(
          (run) => run.conversationId === conversation.conversationId && run.role !== 'execution',
        );
    const routine = params.routineExecutionId
      ? this.routines.execution(bot.botId, params.routineExecutionId)
      : undefined;
    const userMessage: Message = {
      messageId: randomUUID(),
      conversationId: conversation.conversationId,
      seq: this.database.head(),
      author: { type: 'user' },
      kind: 'text',
      status: 'done',
      createdAt: now(),
      ...(params.taskId ? { taskId: params.taskId } : {}),
      content: {
        text: params.text,
        ...(params.spaceId ? { spaces: [params.spaceId] } : {}),
        ...(params.createSpace ? { createSpace: true } : {}),
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

    const run: RunRecord = {
      conversationId: conversation.conversationId,
      botId: bot.botId,
      lastSeq: -1,
      state: 'thinking',
      inputMessageId: userMessage.messageId,
      submissionId: params.clientMsgId,
      role: 'coordinator',
      targetTaskId: params.taskId,
      ...(active ? { queue: 'queued' as const } : {}),
      ...(command?.modelOverride ? { modelOverride: command.modelOverride } : {}),
    };
    if (params.files?.length) this.files.attach(userMessage, params.files);
    if (run.queue !== 'queued') this.activeRuns.set(run.inputMessageId, run);
    userMessage.seq = this.database.head();
    this.database.putMessage(userMessage, { clientMsgId: params.clientMsgId }, run);
    this.publishActivity(run);
    void this.startRun(run, command?.input ?? params.text);
    return { messageId: userMessage.messageId };
  }

  private async startRun(run: RunRecord, input: string, instructions?: string) {
    run.role ??= 'coordinator';
    run.pendingInput = input;
    this.database.saveRun(run);
    if (run.queue !== 'queued') this.activeRuns.set(run.inputMessageId, run);
    try {
      this.secrets.attach(run.botId);
      await this.userMemory.sync();
      // Sources are applied when a Bot or its source changes: /api/model/set probes the provider
      // catalog, which can outlast the 30 s management deadline.
      await this.hermes.syncRules(this.bots.get(run.botId));
      const conversationId =
        run.sessionKey ??
        (run.groupId ? 'group:' + run.conversationId + ':' + run.botId : run.conversationId);
      run.sessionKey = conversationId;
      const attachments = run.groupId
        ? this.database
            .messagesAfter(
              run.conversationId,
              this.database.chain(run.groupChainId ?? run.conversationId)?.cursorByBot[run.botId] ??
                0,
            )
            .flatMap((message) => (message.kind === 'text' ? (message.content.files ?? []) : []))
        : (
            this.database.message(
              run.role === 'execution' && run.executionId
                ? this.tasks.execution(run.executionId)!.parentInputId
                : run.inputMessageId,
            ) as TextMessage | undefined
          )?.content.files;
      const gateway = this.hermes.gateway(run.botId);
      const snapshot = await openNativeSession(
        this.database,
        this.hermes,
        run.botId,
        conversationId,
        {
          execution: run.role === 'execution',
          ownerConversationId: run.conversationId,
        },
      );
      run.sessionId = snapshot.session_id;
      run.storedSessionId = snapshot.stored_session_id;
      run.replayEpoch = snapshot.replay_epoch;
      run.lastSeq = snapshot.last_sequence;
      run.submissionId ??= run.requestId ?? run.inputMessageId;
      this.database.saveRun(run);
      const nativeInput = await this.files.gatewayInput(
        run.botId,
        [
          run.role === 'execution'
            ? 'Carry out the full brief for the coordinating Dot using your native tools. You are not speaking directly to the user. Do not use nekodot_task. If a decision is missing, use native clarify: the main Dot will consider it, ask the user when necessary and return the answer. Preserve all supplied user constraints and attachments. Return verifiable findings, failures and actual deliverable references to the main Dot; it will compose the user-facing response. Preserve native memory and skills as usual.'
            : this.tasks.context(run.conversationId, run.botId, run.targetTaskId),
          snapshot.bootstrap,
          (this.database.message(run.inputMessageId) as TextMessage | undefined)?.content
            .createSpace
            ? 'The user submitted this request through New Space. Use the nekodot-spaces skill to create and publish an interactive HTML space, and deliver it in this chat.'
            : undefined,
          ...(
            (
              this.database.message(
                run.role === 'execution' && run.executionId
                  ? this.tasks.execution(run.executionId)!.parentInputId
                  : run.inputMessageId,
              ) as TextMessage | undefined
            )?.content.spaces ?? []
          )
            .map((id) => this.database.space(id))
            .filter((space) => space !== undefined)
            .map(
              (space) =>
                `The user selected the existing Space ${JSON.stringify(space.name)} (${space.spaceId}). Use nekodot_space get for its current content directory and records; publish this same ID to update it. Preserve user records.`,
            ),
          instructions,
          input,
        ]
          .filter(Boolean)
          .join('\n\n'),
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
      if (run.role !== 'execution')
        this.database.setSetting('coordinator-session:' + conversationId + ':context', '');
      run.runId = admission.admission_id;
      run.executionGeneration = admission.execution_generation ?? snapshot.execution_generation;
      run.state = 'thinking';
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
      run.textMessageId = failed.messageId;
      await this.finishRun(run, 'failed', failed.content.text);
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
            await this.controls.restoreNativePrompts(run, snapshot.prompts ?? []);
          const session = this.database.hermesSession(
            run.sessionKey ??
              (run.groupId ? 'group:' + run.conversationId + ':' + run.botId : run.conversationId),
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
            await this.controls.restoreNativePrompts(run, snapshot.prompts ?? []);
          const session = this.database.hermesSession(
            run.sessionKey ??
              (run.groupId ? 'group:' + run.conversationId + ':' + run.botId : run.conversationId),
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
                this.activeRuns.set(run.inputMessageId, run);
                this.queueMessage(run, 'running');
                this.publishActivity(run);
              }
              if (frame.execution_generation !== undefined)
                run.executionGeneration = frame.execution_generation;
              await this.events.accept(run, event);
            }
            this.appliedSeq.set(run.runId, sequence);
            if (run.lastSeq >= sequence) {
              const session = this.database.hermesSession(run.sessionKey ?? run.conversationId);
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
              this.activeRuns.set(run.inputMessageId, run);
              this.flow.start(run);
              this.queueMessage(run, 'running');
              await this.controls.restoreNativePrompts(run, snapshot.prompts ?? []);
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
              await this.finishRun(run, 'cancelled', '');
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
            taskId: run.role === 'execution' ? run.taskId : undefined,
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
    this.messages.release(run.textMessageId);
    void this.secrets
      .finish(run)
      .catch(() => console.warn('Temporary profile vault cleanup needs retry'));
    run.state = 'idle';
    this.database.saveRun(run);
    this.activeRuns.delete(run.inputMessageId);
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
      ...(run.taskId ? { taskId: run.taskId } : {}),
      kind: 'stalled',
    });
  }

  private publishActivity(run: RunRecord) {
    this.tasks.activity(run);
    if (run.queue === 'queued') return;
    const current = this.current(run.conversationId);
    if (run.role !== 'execution' && run.state === 'idle' && current && current.runId !== run.runId)
      return;
    const chain = run.groupId
      ? this.database.chain(run.groupChainId ?? run.conversationId)
      : undefined;
    if (chain) this.flow.group(chain);
    this.onLive({
      kind: 'activity',
      conversationId: run.conversationId,
      runId: run.runId,
      botId: run.botId,
      taskId: run.role === 'execution' ? run.taskId : undefined,
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
    const run = runId
      ? [...this.activeRuns.values(), ...this.database.runs()].find(
          (item) => item.conversationId === conversationId && item.runId === runId,
        )
      : this.current(conversationId);
    if (runId && !run) return {};
    if (run?.taskId) this.connectors?.cancelTask(run.taskId);
    if (run?.background === 'cron' && run.runId && run.sessionId) {
      await this.hermes.gateway(run.botId).rpc('cron.cancel', {
        session_id: run.sessionId,
        admission_id: run.runId,
      });
      run.stopRequested = true;
      this.database.saveRun(run);
      return {};
    }
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
        if (run.groupId) this.database.clearChain(run.groupChainId ?? conversationId);
        await this.finishFromState(run, 'cancelled');
      } else if (receipt.status === 'queued') {
        await gateway.rpc('prompt.cancel', {
          session_id: run.sessionId,
          admission_id: run.runId,
        });
        this.consumers.get(run.runId)?.abort();
        if (run.groupId) this.database.clearChain(run.groupChainId ?? conversationId);
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
    if (run.groupId) this.database.clearChain(run.groupChainId ?? conversationId);
    return {};
  }
  async stopTasks(conversationId: string, selector = '', taskId?: string) {
    const tasks = this.database
      .tasks(conversationId)
      .filter((task) => !['completed', 'failed', 'cancelled'].includes(task.state));
    const target = taskId || selector;
    const selected =
      selector === 'all'
        ? tasks
        : target
          ? tasks.filter((task) => task.taskId === target || task.title === target)
          : tasks.length === 1
            ? tasks
            : [];
    if (tasks.length > 1 && !selected.length && !target)
      return tasks.map((task) => `/stop ${task.title}`).join('\n');
    if (target && selector !== 'all' && selected.length !== 1)
      throw new NodeFault('not_found', 'Task not found in this chat');
    const runs = this.database
      .runs()
      .filter(
        (run) =>
          run.conversationId === conversationId &&
          (selector === 'all' ||
            selected.some((task) => task.taskId === run.taskId) ||
            (!tasks.length && !target)),
      );
    for (const task of selected) {
      if (this.connectors?.cancelTask(task.taskId)) {
        task.state = 'cancelled';
        this.database.saveTask(task);
      }
    }
    for (const run of runs) {
      if (!run.runId)
        throw new NodeFault('conflict', 'Task is starting; its native receipt is not ready');
      await this.stop(conversationId, run.runId);
    }
    return 'Stop requested';
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
      'Hermes interrupted this turn. Send a message to continue; the task was not restarted.';
    run.textMessageId = reply.messageId;
    run.state = 'unknown';
    this.activeRuns.set(run.inputMessageId, run);
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
      await this.finishRun(run, 'cancelled', '');
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
    await this.finishRun(
      run,
      status === 'completed' ? 'completed' : status === 'cancelled' ? 'cancelled' : 'failed',
      output ?? activeMessage?.content.text ?? '',
    );
  }

  private async finishRun(
    run: RunRecord,
    status: 'completed' | 'failed' | 'cancelled',
    output: string,
  ) {
    if (run.role === 'consultation') {
      this.end(run);
      return;
    }
    if (run.role === 'execution' || run.role === 'report') {
      this.end(run);
      await this.tasks.finished(run, status);
      await this.connectors?.settled(run);
      if (run.role === 'execution') return;
      if (
        run.taskId &&
        (this.connectors?.pending(run.taskId) ||
          this.database.task(run.taskId)?.executionId !== run.executionId)
      )
        return;
      // A failed report keeps this handoff pending; recovery only submits the report.
      if (run.groupId && status === 'failed') return;
      if (run.groupId) {
        await this.groupExecution.finishGroupRun(run, status, output);
        return;
      }
    } else if (run.groupId) {
      await this.groupExecution.finishGroupRun(run, status, output);
      return;
    } else this.end(run);
    if (status !== 'cancelled')
      this.notifications.send({
        notificationId: 'run:' + (run.runId ?? run.inputMessageId),
        conversationId: run.conversationId,
        ...(run.taskId ? { taskId: run.taskId } : {}),
        kind: status === 'completed' ? 'completed' : 'failed',
      });
  }

  private async finishInterrupted(run: RunRecord, text: string) {
    await this.finishFromState(run, 'failed', undefined, undefined, text);
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
