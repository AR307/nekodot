import { randomUUID } from 'node:crypto';
import { platform } from 'node:os';
import type {
  LiveEvent,
  Message,
  PersistedEvent,
  RpcParams,
  RpcRequest,
  RpcResult,
  ApprovalChoice,
  HermesRunState,
  HermesEvent,
} from '@nekodot/protocol';
import { NodeDatabase, type GroupChainRecord, type RunRecord } from './database';
import type { HermesRuntime } from './hermes/runtime';
import type { HermesApi } from './hermes/api';
import { NodeFault } from './fault';
import { BotService } from './bots';
import { Providers } from './providers';
import { GroupService } from './groups';
import { groupPrompt, MAX_CHAIN, mentionedBots } from './group-routing';
import { Operations } from './operations';
import { BotManagement } from './bot-management';
import { FileLibrary } from './files';
import { Extensions } from './extensions';
import { BotScreens } from './screens';
import { Notifications } from './notifications';
import { SharedUserMemory } from './user-memory';

type TextMessage = Extract<Message, { kind: 'text' }>;

const now = () => new Date().toISOString();
const isActiveStatus = (status: string) =>
  ['queued', 'running', 'waiting_for_approval', 'stopping', 'pending'].includes(status);

export class NodeApplication {
  readonly database: NodeDatabase;
  readonly bots: BotService;
  readonly providers: Providers;
  readonly groups: GroupService;
  readonly operations: Operations;
  readonly management: BotManagement;
  readonly files: FileLibrary;
  readonly extensions: Extensions;
  readonly screens: BotScreens;
  readonly notifications: Notifications;
  readonly userMemory: SharedUserMemory;
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
    this.notifications = new Notifications(this.database);
    this.providers = new Providers(hermes, this.database);
    this.bots = new BotService(this.database, hermes, this.providers);
    this.groups = new GroupService(this.database);
    this.operations = new Operations(this.database);
    this.userMemory = new SharedUserMemory(this.database, hermes);
    this.management = new BotManagement(
      this.database,
      this.bots,
      hermes,
      this.operations,
      this.userMemory,
    );
    this.files = new FileLibrary(this.database, hermes, this.operations);
    this.extensions = new Extensions(this.database, this.bots, hermes, this.operations);
    this.screens = new BotScreens(hermes, this.bots, this.operations);
    this.screens.onStatus = (status) => this.onLive({ kind: 'screen', status });
    this.database.onEvent = (event) => this.onEvent(event);
  }

  async handle(request: RpcRequest): Promise<unknown> {
    switch (request.method) {
      case 'screen.status':
        return this.screens.status(request.params.botId);
      case 'screen.start':
        return this.screens.start(request.params.botId);
      case 'screen.stop':
        return this.screens.stop(request.params.botId, request.params.force);
      case 'screen.control':
        return this.screens.control(request.params);
      case 'bots.jobs':
        return this.management.jobs(request.params.botId);
      case 'bots.jobs.runs':
        return this.management.jobRuns(request.params.botId, request.params.jobId);
      case 'memory.get':
        await this.userMemory.sync();
        return this.management.memory(request.params.botId);
      case 'memory.user.get':
        return this.userMemory.sync();
      case 'memory.user.save':
        return this.userMemory.save(request.params);
      case 'memory.save':
        return this.management.save(request.params);
      case 'memory.refine':
        return this.management.refine(request.params.botId, request.params.focus);
      case 'memory.review':
        return this.management.review(request.params);
      case 'operations.get':
        return this.operations.get(request.params.operationId);
      case 'operations.list':
        return { operations: this.operations.list() };
      case 'hermes.restart':
        return this.management.restart();
      case 'files.list':
        return { files: this.files.list(request.params) };
      case 'files.backfill':
        this.bots.get(request.params.botId);
        return this.files.backfill(request.params.botId);
      case 'imports.create':
        return this.files.createImport();
      case 'extensions.list':
        return this.extensions.list(request.params.kind);
      case 'extensions.content':
        return this.extensions.content(request.params);
      case 'extensions.install':
        return this.extensions.install(request.params);
      case 'extensions.toggle':
        return this.extensions.toggle(request.params);
      case 'extensions.configure':
        return this.extensions.configure(request.params);
      case 'sync.snapshot':
        this.activities();
        return {
          bots: this.database.allBots(),
          groups: this.database.groups(),
          conversations: this.database.conversations(),
          headSeq: this.database.head(),
          node: { platform: platform(), computerUse: this.screens.available },
        } satisfies RpcResult<'sync.snapshot'>;
      case 'sync.since':
        this.activities();
        return this.database.since(request.params.seq);
      case 'messages.list':
        return {
          messages: this.database
            .messages(
              request.params.conversationId,
              request.params.aroundMessageId
                ? (this.database.message(request.params.aroundMessageId)?.seq ?? 0) + 1
                : request.params.beforeSeq,
              request.params.limit,
            )
            .map((message) =>
              message.kind === 'text' && this.streamingTexts.has(message.messageId)
                ? {
                    ...message,
                    content: {
                      ...message.content,
                      text: this.streamingTexts.get(message.messageId)!,
                    },
                  }
                : message,
            ),
        };
      case 'messages.send':
        return this.sendMessage(request.params);
      case 'runs.stop':
        return this.stop(request.params.conversationId);
      case 'approvals.respond':
        return this.respondToApproval(request.params);
      case 'questions.respond':
        return this.respondToQuestion(request.params);
      case 'providers.list':
        return this.providers.list();
      case 'providers.authorize':
        return this.providers.authorize(request.params);
      case 'providers.set':
        return this.providers.set(request.params);
      case 'models.options':
        return this.providers.models(request.params);
      case 'models.info':
        return this.providers.info(request.params.botId);
      case 'bots.create': {
        const created = await this.bots.create(request.params);
        this.startWelcome(created.bot.botId, created.conversation.conversationId);
        return created;
      }
      case 'bots.welcome.retry': {
        const previous = this.database.message(request.params.messageId);
        if (
          previous?.kind !== 'text' ||
          !previous.content.welcome ||
          !['failed', 'cancelled'].includes(previous.status) ||
          !previous.author.id
        )
          throw new NodeFault('conflict', 'This introduction is not waiting for a retry');
        this.bots.get(previous.author.id);
        const messageId = this.startWelcome(previous.author.id, previous.conversationId, true);
        this.database.putMessage({
          ...previous,
          content: { ...previous.content, welcome: undefined },
        });
        return { messageId };
      }
      case 'bots.update':
        return this.bots.update(request.params);
      case 'bots.archive':
        return this.bots.archive(request.params.botId);
      case 'bots.permissions.get':
        return { mode: await this.hermes.approvalMode(this.bots.get(request.params.botId).botId) };
      case 'groups.create':
        return this.groups.create(request.params);
      case 'groups.update':
        return this.groups.update(request.params);
      case 'groups.archive':
        return this.groups.archive(request.params.groupId);
      default:
        throw new NodeFault('not_found', 'Method is not available in this phase');
    }
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
          chain: chain ? { count: chain.count, max: MAX_CHAIN } : undefined,
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
      });
    }
  }

  async resume() {
    for (const run of this.database.runs()) {
      if (!run.runId) {
        await this.finishInterrupted(run, 'Run was interrupted before Hermes returned its run ID.');
        continue;
      }
      try {
        const api = await this.hermes.api(run.botId);
        const state = await api.state(run.runId);
        if (isActiveStatus(state.status)) {
          this.activeRuns.set(run.conversationId, run);
          this.restoreQuestion(run, state);
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
                  ...(prompt.choices ? { choices: prompt.choices as ApprovalChoice[] } : {}),
                },
              };
              run.state = 'waiting_approval';
              this.database.putMessage(message, { runId: run.runId }, run);
            }
          }
          this.publishActivity(run);
          this.consume(run, api);
        } else {
          await this.finishFromState(
            run,
            state.status,
            state.output,
            state.pending_steer,
            state.error ?? state.turn_exit_reason,
          );
        }
      } catch {
        await this.finishInterrupted(
          run,
          'Hermes could not resume this run. It was not restarted.',
        );
      }
    }
    const activeConversations = new Set(this.database.runs().map((run) => run.conversationId));
    for (const chain of this.database.chains()) {
      if (chain.queue.length && !activeConversations.has(chain.conversationId))
        await this.startNextGroupRun(chain);
    }
  }

  async close() {
    await this.userMemory.close();
    this.screens.close();
    for (const run of this.activeRuns.values())
      this.persistText(run, this.currentText(run), run.lastSeq);
    for (const consumer of this.consumers.values()) consumer.abort();
    this.consumers.clear();
    this.database.db.close();
  }

  private startWelcome(botId: string, conversationId: string, retry = false) {
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
    const message = this.newText(run, '', 'streaming');
    run.inputMessageId = message.messageId;
    run.textMessageId = message.messageId;
    this.activeRuns.set(conversationId, run);
    this.database.putMessage(message, {}, run);
    this.publishActivity(run);
    void this.startRun(
      run,
      'You have just been created as a nekodot Bot. Introduce yourself briefly using your own identity and role, then ask what task the user would like you to work on. Speak directly to the user. Do not claim the user has sent you a message. Do not use tools for this introduction.',
    );
    return message.messageId;
  }

  private async sendMessage(params: RpcParams<'messages.send'>) {
    const duplicate = this.database.byClient(params.clientMsgId);
    if (duplicate) return { messageId: duplicate.messageId };
    const conversation = this.database.conversation(params.conversationId);
    if (!conversation) throw new NodeFault('not_found', 'Conversation not found');
    if (conversation.kind === 'group') return this.sendGroupMessage(params, conversation);
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
      if (active.state === 'waiting_approval' || active.state === 'waiting_question')
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
      active.welcome = undefined;
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

  private async sendGroupMessage(
    params: RpcParams<'messages.send'>,
    conversation: Extract<NonNullable<ReturnType<NodeDatabase['conversation']>>, { kind: 'group' }>,
  ) {
    const group = this.database.group(conversation.groupId);
    if (!group || group.archived) throw new NodeFault('not_found', 'Group not found');
    const roster = group.botIds.map((botId) => this.bots.get(botId));
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
      if (active.state === 'waiting_approval' || active.state === 'waiting_question')
        throw new NodeFault(
          'conflict',
          'Resolve the pending approval or stop this run before sending.',
        );
      if (!active.runId)
        throw new NodeFault('conflict', 'The current run is starting. Try again shortly.');
      const accepted = await (await this.hermes.api(active.botId)).steer(active.runId, params.text);
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
      const chain = this.database.chain(conversation.conversationId);
      if (chain) {
        chain.queue = [];
        this.database.saveChain(chain);
      }
      this.database.saveRun(active);
      this.publishActivity(active);
      return { messageId: userMessage.messageId };
    }
    const mentioned = mentionedBots(params.text, roster);
    const chain: GroupChainRecord = {
      notificationId: userMessage.messageId,
      conversationId: conversation.conversationId,
      group,
      roster,
      queue: mentioned.length ? mentioned : [group.leadBotId],
      count: 0,
      cursorByBot: this.database.groupHistory(conversation.conversationId)?.cursorByBot ?? {},
      requestId: userMessage.messageId,
      active: true,
    };
    userMessage.seq = this.database.head();
    this.database.putMessage(userMessage, { clientMsgId: params.clientMsgId }, undefined, chain);
    await this.startNextGroupRun(chain);
    return { messageId: userMessage.messageId };
  }

  private async startNextGroupRun(chain: GroupChainRecord) {
    if (chain.count >= MAX_CHAIN || !chain.queue.length)
      this.notifications.send({
        notificationId: `chain:${chain.notificationId}`,
        conversationId: chain.conversationId,
        kind: chain.failed ? 'failed' : 'completed',
      });
    if (chain.count >= MAX_CHAIN) {
      this.groupNotice(chain, 'Relay paused after 6 turns. Mention a group member to continue.');
      this.database.clearChain(chain.conversationId);
      this.publishGroupIdle(chain.conversationId);
      return;
    }
    if (!chain.queue.length) {
      this.database.clearChain(chain.conversationId);
      this.publishGroupIdle(chain.conversationId);
      return;
    }
    const botId = chain.queue.shift()!;
    chain.count += 1;
    chain.currentBotId = botId;
    const prompt = groupPrompt(
      chain,
      botId,
      this.database.messagesAfter(chain.conversationId, chain.cursorByBot[botId] ?? 0),
    );
    chain.currentInput = prompt.input;
    chain.currentInstructions = prompt.instructions;
    this.database.saveChain(chain);
    const run: RunRecord = {
      conversationId: chain.conversationId,
      botId,
      groupId: chain.group.groupId,
      requestId: chain.requestId,
      lastSeq: -1,
      state: 'thinking',
      inputMessageId: chain.requestId ?? randomUUID(),
    };
    this.database.saveRun(run);
    this.activeRuns.set(run.conversationId, run);
    this.publishActivity(run);
    void this.startRun(run, chain.currentInput, chain.currentInstructions);
  }

  private groupNotice(chain: GroupChainRecord, text: string) {
    this.database.putMessage(
      {
        messageId: randomUUID(),
        conversationId: chain.conversationId,
        seq: this.database.head(),
        author: { type: 'system' },
        kind: 'system',
        status: 'done',
        createdAt: now(),
        content: { text },
      },
      {},
    );
  }

  private publishGroupIdle(conversationId: string) {
    const group = this.database
      .conversations()
      .find((item) => item.kind === 'group' && item.conversationId === conversationId);
    if (!group || group.kind !== 'group') return;
    const model = this.database.group(group.groupId);
    if (!model) return;
    this.onLive({
      kind: 'activity',
      conversationId,
      botId: model.leadBotId,
      state: 'idle',
      chain: { count: 0, max: MAX_CHAIN },
    });
  }

  private async startRun(run: RunRecord, input: string, instructions?: string) {
    try {
      await this.userMemory.sync();
      await this.providers.configureBot(this.bots.get(run.botId));
      const api = await this.hermes.api(run.botId);
      const conversationId = run.groupId
        ? this.database
            .conversations()
            .find((conversation) => conversation.kind === 'dm' && conversation.botId === run.botId)
            ?.conversationId
        : run.conversationId;
      if (!conversationId) throw new Error('Bot private conversation is missing');
      const created = await api.createRun(
        input,
        'nk_dm_' + conversationId,
        run.requestId ?? run.inputMessageId,
        instructions,
      );
      run.runId = created.run_id;
      if (this.database.message(run.inputMessageId))
        this.database.setMessageRun(run.inputMessageId, created.run_id);
      this.database.saveRun(run);
      this.consume(run, api);
    } catch (error) {
      const failed = this.currentText(run) ?? this.newText(run, '', 'failed');
      failed.status = 'failed';
      failed.content.failureReason =
        error instanceof NodeFault
          ? error.message
          : 'Could not start this run. Check the provider and try again.';
      const idle = this.idle(run);
      if (run.groupId) await this.finishGroupRun(run, 'failed', failed.content.text);
      else {
        this.database.putMessage(failed, { runId: run.runId }, idle);
        this.notifications.send({
          notificationId: `request:${run.inputMessageId}`,
          conversationId: run.conversationId,
          kind: 'failed',
        });
        this.end(idle);
      }
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
    let disconnected = false;
    while (!signal.aborted && run.runId) {
      try {
        for await (const frame of api.events(run.runId, run.lastSeq, signal)) {
          if (disconnected) {
            disconnected = false;
            this.publishActivity(run);
          }
          const event = frame.data;
          if (event.seq <= Math.max(run.lastSeq, this.appliedSeq.get(run.runId) ?? -1)) continue;
          await this.acceptEvent(run, api, event);
          if (run.state === 'idle') return;
          this.appliedSeq.set(run.runId, event.seq);
        }
        if (signal.aborted) return;
        const state = await api.state(run.runId);
        if (!isActiveStatus(state.status)) {
          await this.finishFromState(
            run,
            state.status,
            state.output,
            state.pending_steer,
            state.error ?? state.turn_exit_reason,
          );
          return;
        }
        this.restoreQuestion(run, state);
        reconnectDelay = 1000;
      } catch (error) {
        if (signal.aborted) return;
        if (error instanceof Error && error.name === 'ZodError') {
          await this.finishInterrupted(
            run,
            'Hermes returned an unsupported event. The task was not restarted.',
          );
          return;
        }
        if (!disconnected) {
          disconnected = true;
          this.persistText(run, this.currentText(run), run.lastSeq);
          this.onLive({
            kind: 'activity',
            conversationId: run.conversationId,
            botId: run.botId,
            state: run.state,
            connection: 'reconnecting',
            detail: error instanceof Error ? error.message : 'Hermes stream disconnected',
          });
        }
        try {
          const state = await api.state(run.runId);
          if (!isActiveStatus(state.status)) {
            await this.finishFromState(
              run,
              state.status,
              state.output,
              state.pending_steer,
              state.error ?? state.turn_exit_reason,
            );
            return;
          }
          this.restoreQuestion(run, state);
        } catch (stateError) {
          if (stateError instanceof NodeFault && stateError.code === 'not_found') {
            await this.finishInterrupted(
              run,
              'Hermes no longer has this run. It was not restarted.',
            );
            return;
          }
        }
      }
      if (signal.aborted) return;
      await new Promise((resolve) => setTimeout(resolve, reconnectDelay));
      reconnectDelay = Math.min(reconnectDelay * 2, 30000);
    }
  }

  private async acceptEvent(run: RunRecord, api: HermesApi, event: HermesEvent) {
    const runId = run.runId!;
    if (event.event === 'clarify.request') {
      this.persistText(run, this.currentText(run), event.seq);
      this.restoreQuestion(run, await api.state(runId));
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
      run.state = 'thinking';
      run.lastSeq = event.seq;
      this.database.saveRun(run);
      this.publishActivity(run);
      return;
    }
    if (event.event === 'message.delta') {
      const textMessage = this.ensureText(run);
      const delta = event.delta ?? '';
      const previous = this.streamingTexts.get(textMessage.messageId) ?? textMessage.content.text;
      textMessage.content = { ...textMessage.content, text: previous + delta };
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
        tool.status = run.stopRequested ? 'cancelled' : 'done';
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
          ...((pending.choices ?? event.choices)
            ? { choices: (pending.choices ?? event.choices) as ApprovalChoice[] }
            : {}),
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
      this.notifications.send({
        notificationId: `approval:${runId}:${pending.prompt_id}`,
        conversationId: run.conversationId,
        kind: 'approval',
      });
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
      const state = await api.state(runId);
      const reply = this.ensureText(run);
      reply.content = { ...reply.content, text: event.output ?? reply.content.text };
      reply.status = 'done';
      await this.files.capture(reply);
      this.persistText(run, reply, event.seq);
      this.pendingInstruction(run, state.pending_steer);
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
      this.settleControls(run, event.event === 'run.cancelled' ? 'cancelled' : 'failed');
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
        reply.content = { ...reply.content, text: event.output ?? 'Run failed.' };
      if (event.event !== 'run.cancelled')
        reply.content.failureReason =
          typeof event.error === 'string'
            ? event.error
            : (event.turn_exit_reason ??
              'Hermes interrupted this turn. Send a message to continue; the task was not restarted.');
      reply.status = event.event === 'run.cancelled' ? 'cancelled' : 'failed';
      this.persistText(run, reply, event.seq);
      const state = await api.state(runId);
      this.pendingInstruction(run, state.pending_steer);
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

  private async finishGroupRun(
    run: RunRecord,
    status: 'completed' | 'failed' | 'cancelled',
    output: string,
  ) {
    run.state = 'idle';
    const chain = this.database.chain(run.conversationId);
    this.activeRuns.delete(run.conversationId);
    if (run.runId) {
      this.appliedSeq.delete(run.runId);
      const consumer = this.consumers.get(run.runId);
      consumer?.abort();
      this.consumers.delete(run.runId);
    }
    if (!chain || status === 'cancelled') {
      if (chain && status === 'cancelled') this.database.clearChain(run.conversationId);
      this.database.saveRun({ ...run, state: 'idle' });
      this.publishGroupIdle(run.conversationId);
      await this.userMemory.sync();
      return;
    }
    if (status === 'failed') chain.failed = true;
    if (status === 'failed')
      this.groupNotice(
        chain,
        `${chain.roster.find((bot) => bot.botId === run.botId)?.displayName ?? 'Bot'} could not complete this turn.`,
      );
    chain.cursorByBot[run.botId] = this.database.head();
    if (status === 'completed')
      for (const botId of mentionedBots(output, chain.roster))
        if (botId !== run.botId) chain.queue.push(botId);
    chain.currentBotId = undefined;
    chain.currentInstructions = undefined;
    chain.requestId = randomUUID();
    this.database.saveRun({ ...run, state: 'idle' });
    this.database.saveChain(chain);
    await this.userMemory.sync();
    await this.startNextGroupRun(chain);
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
    if (buffered !== undefined) current.content = { ...current.content, text: buffered };
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
      content: { text, ...(run.welcome ? { welcome: true as const } : {}) },
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
    void this.userMemory.sync();
  }

  private publishActivity(run: RunRecord) {
    const chain = run.groupId ? this.database.chain(run.conversationId) : undefined;
    this.onLive({
      kind: 'activity',
      conversationId: run.conversationId,
      botId: run.botId,
      state: run.state,
      chain: chain ? { count: chain.count, max: MAX_CHAIN } : undefined,
    });
  }

  private async stop(conversationId: string) {
    const run =
      this.activeRuns.get(conversationId) ??
      this.database.runs().find((item) => item.conversationId === conversationId);
    if (!run?.runId) throw new NodeFault('not_found', 'No active run');
    run.stopRequested = true;
    this.database.saveRun(run);
    try {
      await (await this.hermes.api(run.botId)).stop(run.runId);
    } catch (error) {
      run.stopRequested = false;
      this.database.saveRun(run);
      throw error;
    }
    if (run.groupId) this.database.clearChain(conversationId);
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

  private restoreQuestion(run: RunRecord, state: HermesRunState) {
    const pending = state.pending_controls?.find((control) => control.kind === 'clarify');
    if (!pending || !run.runId) return;
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
            executionGeneration: pending.execution_generation ?? state.execution_generation ?? 0,
            question: pending.question ?? 'Hermes needs your answer',
            choices: pending.choices ?? [],
            multiSelect: pending.multi_select ?? false,
          },
        },
        { runId: run.runId },
        run,
      );
    else this.database.saveRun(run);
    if (!existing)
      this.notifications.send({
        notificationId: `question:${run.runId}:${pending.prompt_id}`,
        conversationId: run.conversationId,
        kind: 'question',
      });
    this.publishActivity(run);
  }

  private async respondToQuestion(params: RpcParams<'questions.respond'>) {
    const message = this.database.message(params.messageId);
    if (message?.kind !== 'question' || message.status !== 'streaming')
      throw new NodeFault('conflict', 'This question is no longer pending');
    const run =
      this.activeRuns.get(message.conversationId) ??
      this.database.runs().find((item) => item.runId === message.content.runId);
    if (!run?.runId) throw new NodeFault('conflict', 'Run is no longer active');
    const response = await (
      await this.hermes.api(run.botId)
    ).clarify(
      run.runId,
      message.content.requestId,
      message.content.executionGeneration,
      params.answer,
    );
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

  private async finishFromState(
    run: RunRecord,
    status: string,
    output?: string,
    pendingSteer?: string,
    failureReason?: string,
  ) {
    this.settleControls(
      run,
      status === 'cancelled' ? 'cancelled' : status === 'completed' ? 'done' : 'failed',
    );
    const activeMessage = this.currentText(run);
    if (activeMessage && status !== 'completed' && status !== 'cancelled')
      activeMessage.content.failureReason =
        failureReason ?? 'Hermes interrupted this turn. The task was not restarted.';
    if (run.groupId) {
      const reply = activeMessage ?? this.newText(run, output ?? '', 'done');
      reply.content = { ...reply.content, text: output ?? reply.content.text };
      reply.status =
        status === 'cancelled' ? 'cancelled' : status === 'completed' ? 'done' : 'failed';
      if (status === 'completed') await this.files.capture(reply);
      this.persistText(run, reply, run.lastSeq);
      this.pendingInstruction(run, pendingSteer);
      await this.finishGroupRun(
        run,
        status === 'cancelled' ? 'cancelled' : status === 'completed' ? 'completed' : 'failed',
        output ?? activeMessage?.content.text ?? '',
      );
      return;
    }
    if (status === 'completed') {
      const reply = activeMessage ?? this.newText(run, output ?? '', 'done');
      reply.content = { ...reply.content, text: output ?? reply.content.text };
      reply.status = 'done';
      await this.files.capture(reply);
      this.persistText(run, reply, run.lastSeq);
    } else if (status === 'cancelled') {
      const reply = activeMessage ?? this.newText(run, 'Run stopped.', 'cancelled');
      reply.status = 'cancelled';
      this.persistText(run, reply, run.lastSeq);
    } else {
      const reply = activeMessage ?? this.newText(run, output ?? 'Run was interrupted.', 'failed');
      if (!reply.content.text)
        reply.content = { ...reply.content, text: output ?? 'Run was interrupted.' };
      reply.content.failureReason =
        failureReason ?? 'Hermes interrupted this turn. The task was not restarted.';
      reply.status = 'failed';
      this.persistText(run, reply, run.lastSeq);
    }
    this.pendingInstruction(run, pendingSteer);
    if (status !== 'cancelled')
      this.notifications.send({
        notificationId: `run:${run.runId}`,
        conversationId: run.conversationId,
        kind: status === 'completed' ? 'completed' : 'failed',
      });
    this.end(run);
  }

  private async finishInterrupted(run: RunRecord, text: string) {
    this.settleControls(run, 'failed');
    const message = this.currentText(run) ?? this.newText(run, text, 'failed');
    if (!message.content.text) message.content = { ...message.content, text };
    message.content.failureReason = text;
    message.status = 'failed';
    this.database.putMessage(message, { runId: run.runId }, this.idle(run));
    run.state = 'idle';
    if (run.groupId) {
      await this.finishGroupRun(run, 'failed', text);
      return;
    }
    this.activeRuns.delete(run.conversationId);
    this.publishActivity(this.idle(run));
    await this.userMemory.sync();
    this.notifications.send({
      notificationId: `run:${run.runId}`,
      conversationId: run.conversationId,
      kind: 'failed',
    });
  }

  private settleControls(run: RunRecord, status: Message['status']) {
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
