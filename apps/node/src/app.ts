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
  HermesEvent,
} from '@nekodot/protocol';
import { NodeDatabase, type GroupChainRecord, type RunRecord } from './database';
import type { HermesRuntime } from './hermes/runtime';
import { HermesGatewayError, type GatewayFrame } from './hermes/gateway';
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
import { BotCommands } from './commands';
import { NativeExtras } from './native-extras';
import { Routines } from './routines';
import { openNativeSession, type NativeSessionSnapshot } from './hermes/session';

type TextMessage = Extract<Message, { kind: 'text' }>;

const now = () => new Date().toISOString();

interface NativePrompt {
  kind: 'approval' | 'clarify';
  prompt_id: string;
  execution_generation: number;
  choices?: string[];
  command?: string;
  description?: string;
  question?: string;
  multi_select?: boolean;
}

interface NativeAdmission {
  admission_id: string;
  status: 'queued' | 'started' | 'unknown' | 'terminal';
  outcome?: string | null;
  execution_generation?: number | null;
  result?: { final_response?: string; failed?: boolean; interrupted?: boolean };
}

interface NativeReplay {
  events: GatewayFrame[];
  replay_epoch: string;
  latest_seq: number;
  snapshot_required: boolean;
  truncated: boolean;
}

export function projectGatewayEvent(run: RunRecord, frame: GatewayFrame): HermesEvent | undefined {
  const payload = frame.payload ?? {};
  // Native background completions share the session stream, not this admission.
  if (frame.admission_id !== run.runId && payload.admission_id !== run.runId) return;
  const base = {
    run_id: run.runId ?? '',
    timestamp: Date.now() / 1000,
    seq: frame.seq ?? 0,
  };
  const text = typeof payload.text === 'string' ? payload.text : undefined;
  switch (frame.type) {
    case 'message.delta':
      return { ...base, event: 'message.delta', ...(text !== undefined ? { delta: text } : {}) };
    case 'message.interim':
      return {
        ...base,
        event: 'message.interim',
        ...(text !== undefined ? { text } : {}),
        already_streamed: payload.already_streamed !== false,
      };
    case 'tool.start':
      return {
        ...base,
        event: 'tool.started',
        tool_call_id: String(payload.tool_id ?? ''),
        tool: String(payload.name ?? 'tool'),
        preview: String(payload.preview ?? payload.args_text ?? ''),
      };
    case 'tool.complete':
      return {
        ...base,
        event: 'tool.completed',
        tool_call_id: String(payload.tool_id ?? ''),
        preview: String(payload.summary ?? payload.result_text ?? ''),
        duration: typeof payload.duration_s === 'number' ? payload.duration_s : 0,
        error: payload.error === true,
      };
    case 'tool.generating':
      return {
        ...base,
        event: 'tool.generating',
        tool: String(payload.name ?? 'tool'),
      };
    case 'approval.request':
    case 'clarify.request':
      return {
        ...base,
        event: frame.type,
        prompt_id: String(payload.prompt_id ?? ''),
        execution_generation:
          frame.execution_generation ?? Number(payload.execution_generation ?? 0),
        ...(typeof payload.command === 'string' ? { command: payload.command } : {}),
        ...(typeof payload.description === 'string' ? { description: payload.description } : {}),
        ...(Array.isArray(payload.choices)
          ? {
              choices: payload.choices.filter(
                (choice): choice is string => typeof choice === 'string',
              ),
            }
          : {}),
        ...(typeof payload.question === 'string' ? { question: payload.question } : {}),
        ...(typeof payload.multi_select === 'boolean'
          ? { multi_select: payload.multi_select }
          : {}),
      };
    case 'approval.settled':
    case 'clarify.settled':
      return { ...base, event: frame.type, prompt_id: String(payload.prompt_id ?? '') };
    case 'message.complete': {
      const status = payload.status;
      const event =
        status === 'error'
          ? 'run.failed'
          : status === 'interrupted'
            ? 'run.interrupted'
            : 'run.completed';
      const output = typeof payload.text === 'string' ? payload.text : undefined;
      return {
        ...base,
        event: run.stopRequested && status === 'interrupted' ? 'run.cancelled' : event,
        ...(output !== undefined ? { output } : {}),
        ...(typeof payload.error === 'string' ? { error: payload.error } : {}),
        ...(typeof payload.failure_reason === 'string'
          ? { turn_exit_reason: payload.failure_reason }
          : {}),
      };
    }
    default:
      return undefined;
  }
}

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
  readonly commands: BotCommands;
  readonly nativeExtras: NativeExtras;
  readonly routines: Routines;
  onEvent: (event: PersistedEvent) => void = () => {};
  onLive: (event: LiveEvent) => void = () => {};
  private readonly consumers = new Map<string, AbortController>();
  private readonly activeRuns = new Map<string, RunRecord>();
  private readonly textProgress = new Map<string, { persistedAt: number; length: number }>();
  private readonly streamingTexts = new Map<string, string>();
  private readonly appliedSeq = new Map<string, number>();

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
    home: string,
    readonly hermes: HermesRuntime,
  ) {
    this.database = new NodeDatabase(home);
    this.notifications = new Notifications(this.database);
    this.routines = new Routines(this.database, hermes, this.notifications);
    this.providers = new Providers(hermes, this.database);
    this.bots = new BotService(this.database, hermes, this.providers);
    this.groups = new GroupService(this.database);
    this.operations = new Operations(this.database);
    this.commands = new BotCommands(this.database, hermes);
    this.nativeExtras = new NativeExtras(hermes);
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
      case 'commands.list':
        this.bots.get(request.params.botId);
        return this.commands.catalog(request.params.botId);
      case 'commands.execute':
        return this.executeCommand(request.params);
      case 'sessions.list':
        this.bots.get(request.params.botId);
        return this.commands.sessions.list(request.params.botId);
      case 'sessions.history':
        this.bots.get(request.params.botId);
        return this.commands.sessions.history(request.params.botId, request.params.sessionId);
      case 'learning.list':
        this.bots.get(request.params.botId);
        return this.nativeExtras.learning(request.params.botId);
      case 'learning.get':
        this.bots.get(request.params.botId);
        return this.nativeExtras.learningEntry(request.params.botId, request.params.id);
      case 'learning.save': {
        this.bots.get(request.params.botId);
        const result = await this.nativeExtras.learningEntry(
          request.params.botId,
          request.params.id,
          request.params.content,
        );
        await this.userMemory.sync();
        return result;
      }
      case 'pets.list':
        this.bots.get(request.params.botId);
        return this.nativeExtras.pets(request.params.botId);
      case 'pets.thumbnail':
        this.bots.get(request.params.botId);
        return this.nativeExtras.petThumbnail(
          request.params.botId,
          request.params.slug,
          request.params.url,
        );
      case 'pets.manage': {
        const { botId, action, ...params } = request.params;
        this.bots.get(botId);
        return this.operations.start('pet:' + action, [botId], async (operation) => {
          const result = await this.nativeExtras.petAction(botId, action, params);
          operation.results.push({
            botId,
            ok: true,
            detail: 'Hermes pet ' + action,
            native: result,
          });
        });
      }
      case 'subscription.get':
        this.bots.get(request.params.botId);
        return this.nativeExtras.subscription(request.params.botId);
      case 'screen.status':
        return this.screens.status(request.params.botId);
      case 'screen.start':
        return this.screens.start(request.params.botId);
      case 'screen.stop':
        return this.screens.stop(request.params.botId, request.params.force);
      case 'screen.control':
        return this.screens.control(request.params);
      case 'routines.list':
        return this.routines.list(request.params.botId);
      case 'routines.get':
        return this.routines.get(request.params.botId, request.params.routineId);
      case 'routines.create':
        return this.routines.create(request.params);
      case 'routines.update':
        return this.routines.update(request.params);
      case 'routines.credentials':
        return this.routines.credentials(request.params.botId, request.params.routineId);
      case 'routines.enable':
        return this.routines.enable(
          request.params.botId,
          request.params.routineId,
          request.params.enabled,
        );
      case 'routines.grant':
        return this.routines.enable(request.params.botId, request.params.routineId, true, true);
      case 'routines.rotate':
        return this.routines.rotate(request.params.botId, request.params.routineId);
      case 'routines.test':
        return this.routines.send(
          request.params.botId,
          request.params.routineId,
          request.params.payload,
          request.params.requestId,
        );
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
      case 'files.get':
        return this.files.get(request.params.fileId);
      case 'files.receive':
        return this.files.receive(request.params);
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
      case 'hermes.settings.get':
        return this.providers.settings(request.params.botId);
      case 'hermes.settings.set':
        return this.providers.setSetting(request.params);
      case 'bots.create': {
        const { archiveFileId, ...fields } = request.params;
        const created = await this.bots.create(
          fields,
          archiveFileId ? this.files.profileArchive(archiveFileId) : undefined,
        );
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
        this.bots.archive(request.params.botId);
        if (this.routines.routes().some((route) => route.botId === request.params.botId))
          await this.routines.syncRoutes();
        return {};
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
          this.reconcileNativeText(run, snapshot);
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
          this.activeRuns.set(run.conversationId, run);
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
          this.activeRuns.set(run.conversationId, run);
          this.restoreNativePrompts(run, snapshot.prompts ?? []);
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
            undefined,
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
          this.activeRuns.set(run.conversationId, run);
          this.publishActivity(run);
          this.consume(run, gateway);
        }
      }
    }
    const activeConversations = new Set(this.database.runs().map((run) => run.conversationId));
    for (const chain of this.database.chains()) {
      if (chain.queue.length && !activeConversations.has(chain.conversationId))
        await this.startNextGroupRun(chain);
    }
  }

  async close() {
    await this.routines.close();
    await this.userMemory.close();
    this.screens.close();
    for (const run of this.activeRuns.values())
      this.persistText(
        run,
        this.currentText(run),
        run.runId ? (this.appliedSeq.get(run.runId) ?? run.lastSeq) : run.lastSeq,
      );
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

  private executeCommand(params: RpcParams<'commands.execute'>) {
    this.bots.get(params.botId);
    const conversation = this.database.conversation(params.conversationId);
    const group =
      conversation?.kind === 'group' ? this.database.group(conversation.groupId) : undefined;
    if (
      !conversation ||
      (conversation.kind === 'dm'
        ? conversation.botId !== params.botId
        : !group?.botIds.includes(params.botId))
    )
      throw new NodeFault('forbidden', 'Choose a bot in this conversation.');
    const side = /^\/(bg|btw)(?:\s|$)/.test(params.command);
    const operationKind = `command${side ? '-side' : ''}:${params.clientMsgId}`;
    const existing = this.operations.list().find((op) => op.kind === operationKind);
    if (existing) return existing;
    if (
      this.operations
        .list()
        .some(
          (op) =>
            op.kind.startsWith('command:') &&
            op.status === 'running' &&
            op.botIds.includes(params.botId),
        )
    )
      throw new NodeFault('conflict', 'A Hermes command is already running for this bot.');
    return this.operations.start(operationKind, [params.botId], async (operation) => {
      let result = await this.commands.execute(params.botId, params.command, params.clientMsgId);
      if (result.type === 'alias' && result.target)
        result = await this.commands.execute(params.botId, result.target);
      if ((result.type === 'send' || result.type === 'skill') && result.message) {
        await this.sendMessage(
          {
            conversationId: params.conversationId,
            text: result.display || params.command,
            clientMsgId: params.clientMsgId,
          },
          { botId: params.botId, input: result.message },
        );
      }
      const output = [result.output, result.warning, result.notice].filter(Boolean).join('\n');
      if (output) {
        const messageId = randomUUID();
        const fileId = result.artifact
          ? await this.files.deliverArchive(
              params.botId,
              params.conversationId,
              messageId,
              result.artifact,
            )
          : undefined;
        this.database.putMessage({
          messageId,
          conversationId: params.conversationId,
          seq: this.database.head(),
          author: { type: 'system' },
          kind: 'system',
          status: 'done',
          createdAt: now(),
          content: {
            text: params.command + '\n\n' + output,
            ...(fileId ? { files: [fileId] } : {}),
          },
        });
      }
      operation.detail = output || 'Hermes command completed.';
      operation.results.push({
        botId: params.botId,
        ok: true,
        detail: operation.detail,
        ...(result.type === 'prefill' && result.message
          ? { native: { prefill: result.message } }
          : result.type === 'navigate' && result.target
            ? { native: { page: result.target, argument: result.message ?? '' } }
            : result.type === 'export'
              ? { native: { export: { filename: result.filename, content: result.content } } }
              : result.type === 'client'
                ? { native: { action: result.target, argument: result.message ?? '' } }
                : {}),
      });
    });
  }

  private async sendMessage(
    params: RpcParams<'messages.send'>,
    command?: { botId: string; input: string },
  ) {
    const duplicate = this.database.byClient(params.clientMsgId);
    if (duplicate) return { messageId: duplicate.messageId };
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
      params.files?.length &&
      this.database.runs().some((run) => run.conversationId === params.conversationId)
    )
      throw new NodeFault(
        'conflict',
        'Hermes steer accepts text only. Wait for this run to finish or stop it before sending attachments.',
      );
    if (conversation.kind === 'group') return this.sendGroupMessage(params, conversation, command);
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
    if (params.files?.length) this.files.attach(userMessage, params.files);
    this.activeRuns.set(run.conversationId, run);
    userMessage.seq = this.database.head();
    this.database.putMessage(userMessage, { clientMsgId: params.clientMsgId }, run);
    this.publishActivity(run);
    void this.startRun(run, command?.input ?? params.text);
    return { messageId: userMessage.messageId };
  }

  private async sendGroupMessage(
    params: RpcParams<'messages.send'>,
    conversation: Extract<NonNullable<ReturnType<NodeDatabase['conversation']>>, { kind: 'group' }>,
    command?: { botId: string; input: string },
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
      const accepted = await this.hermes.gateway(active.botId).rpc<{
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
      queue: command ? [command.botId] : mentioned.length ? mentioned : [group.leadBotId],
      commandInput: command?.input,
      count: 0,
      cursorByBot: this.database.groupHistory(conversation.conversationId)?.cursorByBot ?? {},
      requestId: userMessage.messageId,
      active: true,
    };
    userMessage.seq = this.database.head();
    if (params.files?.length) this.files.attach(userMessage, params.files);
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
    if (chain.commandInput) {
      prompt.input += '\n\n' + chain.commandInput;
      chain.commandInput = undefined;
    }
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
      const routineContext = run.welcome
        ? { text: '', until: undefined }
        : this.routines.context(run.botId);
      const gateway = this.hermes.gateway(run.botId);
      const snapshot = await openNativeSession(
        this.database,
        this.hermes,
        run.botId,
        conversationId,
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
      const admission = await gateway.rpc<NativeAdmission>('prompt.submit', {
        session_id: run.sessionId,
        text: nativeInput.text,
        submission_id: run.submissionId,
        input_id: run.inputMessageId,
        ...(nativeInput.attachments.length ? { attachments: nativeInput.attachments } : {}),
      });
      run.runId = admission.admission_id;
      run.executionGeneration = admission.execution_generation ?? snapshot.execution_generation;
      run.state = 'thinking';
      if (routineContext.until)
        this.database.setSetting('routine-context:' + run.botId, routineContext.until);
      if (this.database.message(run.inputMessageId))
        this.database.setMessageRun(run.inputMessageId, admission.admission_id);
      this.database.saveRun(run);
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
      const failed = this.currentText(run) ?? this.newText(run, '', 'failed');
      failed.status = 'failed';
      failed.content.failureReason =
        error instanceof NodeFault
          ? error.message
          : 'Could not start this run. Check the provider and try again.';
      const idle = this.idleRun(run);
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
            this.reconcileNativeText(run, snapshot);
            run.lastSeq = snapshot.last_sequence;
          }
          this.restoreNativePrompts(run, snapshot.prompts ?? []);
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
          this.reconcileNativeText(run, snapshot);
          this.restoreNativePrompts(run, snapshot.prompts ?? []);
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
        } else {
          for (const frame of replay.events) {
            if (signal.aborted) return;
            const sequence = frame.seq ?? -1;
            if (sequence <= Math.max(run.lastSeq, this.appliedSeq.get(run.runId) ?? -1)) continue;
            const event = projectGatewayEvent(run, frame);
            if (event) {
              if (frame.execution_generation !== undefined)
                run.executionGeneration = frame.execution_generation;
              await this.acceptEvent(run, event);
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
              if (session)
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
          if (receipt.status === 'terminal') {
            const completed = await gateway.rpc<NativeAdmission>('prompt.receipt', {
              session_id: run.sessionId!,
              admission_id: run.runId,
              include_result: true,
            });
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
        }
        reconnectDelay = 500;
      } catch (error) {
        if (signal.aborted) return;
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
      }
      if (signal.aborted) return;
      await new Promise((resolve) => setTimeout(resolve, reconnectDelay));
      reconnectDelay = Math.min(reconnectDelay * 2, 10000);
    }
  }

  private reconcileNativeText(run: RunRecord, snapshot: NativeSessionSnapshot) {
    const active = this.currentText(run);
    if (!active) return;
    const text = [...(snapshot.messages ?? [])]
      .reverse()
      .find((message) => message.role === 'assistant' && typeof message.text === 'string')?.text;
    if (typeof text !== 'string' || !text.startsWith(active.content.text)) return;
    active.content = { ...active.content, text };
    this.persistText(run, active, snapshot.last_sequence);
  }

  private async acceptEvent(run: RunRecord, event: HermesEvent) {
    const runId = run.runId!;
    if (event.event === 'clarify.request') {
      this.persistText(run, this.currentText(run), event.seq);
      this.restoreQuestion(run, {
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
      this.notifications.send({
        notificationId: `approval:${runId}:${event.prompt_id}`,
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
      const reply = this.ensureText(run);
      reply.content = { ...reply.content, text: event.output ?? reply.content.text };
      reply.status = 'done';
      await this.files.capture(reply);
      this.persistText(run, reply, event.seq);
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

  private idleRun(run: RunRecord): RunRecord {
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
    this.settleControls(run, 'failed');
    const reply = this.currentText(run) ?? this.newText(run, '', 'failed');
    reply.status = 'failed';
    reply.content.failureReason =
      'Hermes lost the execution during a restart. Click Stop to acknowledge the interrupted task, then send a new message. Completed effects are kept; this task will not be replayed.';
    run.textMessageId = reply.messageId;
    run.state = 'unknown';
    this.activeRuns.set(run.conversationId, run);
    this.persistText(run, reply, run.lastSeq);
    this.publishActivity(run);
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
    if (!run.sessionId) throw new NodeFault('not_found', 'Hermes session is no longer active');
    await this.hermes.gateway(run.botId).rpc('approval.respond', {
      session_id: run.sessionId,
      execution_generation: message.content.executionGeneration,
      prompt_id: message.content.requestId,
      choice: params.choice,
    });
    message.content = { ...message.content, choice: params.choice };
    message.status = 'done';
    run.state = 'thinking';
    this.database.putMessage(message, { runId }, run);
    this.publishActivity(run);
    return {};
  }

  private restoreNativePrompts(run: RunRecord, prompts: NativePrompt[]) {
    for (const pending of prompts) {
      if (pending.kind === 'clarify') {
        this.restoreQuestion(run, pending);
        continue;
      }
      if (!run.runId || this.database.approval(run.runId, pending.prompt_id)) continue;
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
            ...(pending.choices ? { choices: pending.choices as ApprovalChoice[] } : {}),
          },
        },
        { runId: run.runId },
        run,
      );
    }
  }

  private restoreQuestion(run: RunRecord, pending: NativePrompt) {
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
    if (!run.sessionId) throw new NodeFault('not_found', 'Hermes session is no longer active');
    const response = await this.hermes
      .gateway(run.botId)
      .rpc<{ status: string }>('clarify.respond', {
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
      if (status === 'cancelled') delete reply.content.failureReason;
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
      if (!reply.content.text) reply.content.text = 'Run stopped.';
      delete reply.content.failureReason;
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
    this.database.putMessage(message, { runId: run.runId }, this.idleRun(run));
    run.state = 'idle';
    if (run.groupId) {
      await this.finishGroupRun(run, 'failed', text);
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
