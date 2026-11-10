import { BotSecrets } from './secrets';
import type { RpcRequest, RpcResult } from '@nekodot/protocol';
import { NodeDatabase } from './database';
import type { HermesRuntime } from './hermes/runtime';
import { NodeFault } from './fault';
import { BotService } from './bots';
import { Providers } from './providers';
import { HermesSettings } from './hermes-settings';
import { GroupService } from './groups';
import { Operations } from './operations';
import { BotManagement } from './bot-management';
import { FileLibrary } from './files';
import { Extensions } from './extensions';
import { BotScreens } from './screens';
import { DesktopControl } from './desktop-control';
import { SharedUserMemory } from './user-memory';
import { BotCommands } from './commands';
import { NativeExtras } from './native-extras';
import { Routines } from './routines';
import { BotVoice } from './voice';
import { ExecutionFlows } from './flow';

import type { ConversationExecution } from './execution/sessions';
import type { CommandOperations } from './command-operations';
interface RpcFeatures {
  secrets: BotSecrets;
  bots: BotService;
  voice: BotVoice;
  operations: Operations;
  commands: BotCommands;
  nativeExtras: NativeExtras;
  userMemory: SharedUserMemory;
  screens: BotScreens;
  desktopControl: DesktopControl;
  routines: Routines;
  management: BotManagement;
  files: FileLibrary;
  extensions: Extensions;
  flow: ExecutionFlows;
  database: NodeDatabase;
  providers: Providers;
  settings: HermesSettings;
  desktop: boolean;
  hermes: HermesRuntime;
  groups: GroupService;
}
export class NodeRpc {
  constructor(
    private readonly features: RpcFeatures,
    private readonly execution: ConversationExecution,
    private readonly commandOperations: CommandOperations,
  ) {}
  async handle(request: RpcRequest): Promise<unknown> {
    switch (request.method) {
      case 'secrets.get':
        return this.features.secrets.get(request.params.botId, request.params.requestId);
      case 'secrets.submit':
        return this.features.secrets.submit(
          request.params.botId,
          request.params.requestId,
          request.params,
        );
      case 'secrets.cancel':
        return this.features.secrets.cancel(request.params.botId, request.params.requestId);
      case 'secrets.list':
        return this.features.secrets.list(request.params.botId);
      case 'secrets.replace':
        return this.features.secrets.replace(request.params.botId, request.params.credentialId);
      case 'secrets.disable':
        return this.features.secrets.disable(request.params.botId, request.params.credentialId);
      case 'voice.status':
        this.features.bots.get(request.params.botId);
        return this.features.voice.status(request.params.botId);
      case 'voice.start':
        this.features.bots.get(request.params.botId);
        return this.features.voice.start(request.params.botId);
      case 'voice.feed':
        this.features.bots.get(request.params.botId);
        return this.features.voice.feed(
          request.params.botId,
          request.params.listenerId,
          request.params.pcm,
        );
      case 'voice.stop':
        this.features.bots.get(request.params.botId);
        return this.features.voice.stop(request.params.listenerId, request.params.botId);
      case 'voice.transcribe':
        this.features.bots.get(request.params.botId);
        return this.features.operations.start(
          'voice-transcription',
          [request.params.botId],
          async (operation) => {
            const result = await this.features.voice.transcribe(
              request.params.botId,
              request.params.audio,
            );
            operation.results.push({
              botId: request.params.botId,
              ok: true,
              detail: 'Hermes transcription completed',
              native: result,
            });
          },
        );
      case 'commands.list':
        this.features.bots.get(request.params.botId);
        return this.features.commands.catalog(request.params.botId);
      case 'commands.execute':
        return this.commandOperations.execute(request.params);
      case 'sessions.list':
        this.features.bots.get(request.params.botId);
        return this.features.commands.sessions.list(request.params.botId);
      case 'sessions.history':
        this.features.bots.get(request.params.botId);
        return this.features.commands.sessions.history(
          request.params.botId,
          request.params.sessionId,
        );
      case 'learning.list':
        this.features.bots.get(request.params.botId);
        return this.features.nativeExtras.learning(request.params.botId);
      case 'learning.get':
        this.features.bots.get(request.params.botId);
        return this.features.nativeExtras.learningEntry(request.params.botId, request.params.id);
      case 'learning.save': {
        this.features.bots.get(request.params.botId);
        const result = await this.features.nativeExtras.learningEntry(
          request.params.botId,
          request.params.id,
          request.params.content,
        );
        await this.features.userMemory.sync();
        return result;
      }
      case 'pets.list':
        this.features.bots.get(request.params.botId);
        return this.features.nativeExtras.pets(request.params.botId);
      case 'pets.thumbnail':
        this.features.bots.get(request.params.botId);
        return this.features.nativeExtras.petThumbnail(
          request.params.botId,
          request.params.slug,
          request.params.url,
        );
      case 'pets.manage': {
        const { botId, action, ...params } = request.params;
        this.features.bots.get(botId);
        return this.features.operations.start('pet:' + action, [botId], async (operation) => {
          const result = await this.features.nativeExtras.petAction(botId, action, params);
          operation.results.push({
            botId,
            ok: true,
            detail: 'Hermes pet ' + action,
            native: result,
          });
        });
      }
      case 'subscription.get':
        this.features.bots.get(request.params.botId);
        return this.features.nativeExtras.subscription(request.params.botId);
      case 'screen.status':
        return this.features.screens.status(request.params.botId);
      case 'desktop.status':
        return this.features.desktopControl.refresh();
      case 'bots.desktopControl':
        return this.features.desktopControl.bot(request.params.botId, request.params.enabled);
      case 'screen.start':
        return this.features.screens.start(request.params.botId);
      case 'screen.stop':
        return this.features.screens.stop(request.params.botId, request.params.force);
      case 'screen.control':
        return this.features.screens.control(request.params);
      case 'routines.list':
        return this.features.routines.list(request.params.botId);
      case 'routines.get':
        return this.features.routines.get(request.params.botId, request.params.routineId);
      case 'routines.approvalRespond':
        return this.features.routines.approvalRespond(
          request.params.botId,
          request.params.executionId,
          request.params.promptId,
          request.params.choice,
        );
      case 'routines.create':
        return this.features.routines.create(request.params);
      case 'routines.update':
        return this.features.routines.update(request.params);
      case 'routines.credentials':
        return this.features.routines.credentials(request.params.botId, request.params.routineId);
      case 'routines.enable':
        return this.features.routines.enable(
          request.params.botId,
          request.params.routineId,
          request.params.enabled,
        );
      case 'routines.grant':
        return this.features.routines.enable(
          request.params.botId,
          request.params.routineId,
          true,
          true,
        );
      case 'routines.rotate':
        return this.features.routines.rotate(request.params.botId, request.params.routineId);
      case 'routines.test':
        return this.features.routines.send(
          request.params.botId,
          request.params.routineId,
          request.params.payload,
          request.params.requestId,
        );
      case 'memory.get':
        await this.features.userMemory.sync();
        return this.features.management.memory(request.params.botId);
      case 'memory.user.get':
        return {
          ...(await this.features.userMemory.sync()),
          limit: await this.features.userMemory.limit(),
        } satisfies RpcResult<'memory.user.get'>;
      case 'memory.user.save':
        return {
          ...(await this.features.userMemory.save(request.params)),
          limit: await this.features.userMemory.limit(),
        } satisfies RpcResult<'memory.user.save'>;
      case 'memory.save':
        return this.features.management.save(request.params);
      case 'memory.refine':
        return this.features.management.refine(request.params.botId, request.params.focus);
      case 'memory.review':
        return this.features.management.review(request.params);
      case 'operations.get':
        return this.features.operations.get(request.params.operationId);
      case 'operations.list':
        return { operations: this.features.operations.list() };
      case 'hermes.restart':
        return this.features.management.restart();
      case 'files.list':
        return { files: this.features.files.list(request.params) };
      case 'files.get':
        return this.features.files.get(request.params.fileId);
      case 'files.receive':
        return this.features.files.receive(request.params);
      case 'files.backfill':
        this.features.bots.get(request.params.botId);
        return this.features.files.backfill(request.params.botId);
      case 'imports.create':
        return this.features.files.createImport();
      case 'extensions.list':
        return this.features.extensions.list(request.params.kind);
      case 'extensions.content':
        return this.features.extensions.content(request.params);
      case 'extensions.install':
        return this.features.extensions.install(request.params);
      case 'extensions.toggle':
        return this.features.extensions.toggle(request.params);
      case 'extensions.configure':
        return this.features.extensions.configure(request.params);
      case 'flow.get':
        return { flow: this.features.flow.get(request.params.conversationId) };
      case 'sync.snapshot':
        this.execution.activities();
        return {
          bots: this.features.database.allBots(),
          groups: this.features.database.groups(),
          conversations: this.features.database.conversations(),
          latest: this.features.database.latestTexts(),
          flows: this.features.flow.all(),
          tasks: this.features.database.tasks(),
          headSeq: this.features.database.head(),
          node: this.features.desktopControl.capabilities(),
        } satisfies RpcResult<'sync.snapshot'>;
      case 'sync.since':
        this.execution.activities();
        return this.features.database.since(request.params.seq);
      case 'messages.list':
        return {
          messages: this.features.database
            .messages(
              request.params.conversationId,
              request.params.aroundMessageId
                ? (this.features.database.message(request.params.aroundMessageId)?.seq ?? 0) + 1
                : request.params.beforeSeq,
              request.params.limit,
            )
            .map((message) =>
              message.kind === 'text' &&
              this.execution.messages.buffered(message.messageId) !== undefined
                ? {
                    ...message,
                    content: {
                      ...message.content,
                      text: this.execution.messages.buffered(message.messageId)!,
                    },
                  }
                : message,
            ),
        };
      case 'messages.send':
        return this.execution.sendMessage(request.params);
      case 'tasks.list':
        return { tasks: this.features.database.tasks(request.params.conversationId) };
      case 'tasks.get': {
        const task = this.features.database.task(request.params.taskId);
        if (!task || task.conversationId !== request.params.conversationId)
          throw new NodeFault('not_found', 'Task not found');
        return { task, messages: this.features.database.taskMessages(task.taskId) };
      }
      case 'runs.stop':
        return this.execution.stop(request.params.conversationId, request.params.runId);
      case 'approvals.respond':
        return this.execution.controls.respondToApproval(request.params);
      case 'questions.respond':
        return this.execution.controls.respondToQuestion(request.params);
      case 'providers.list':
        return this.features.providers.list();
      case 'providers.authorize':
        return this.features.providers.authorize(request.params);
      case 'providers.set':
        return this.features.providers.set(request.params);
      case 'providers.test':
        return this.features.providers.test(request.params, this.features.operations);
      case 'models.describe':
        return this.features.providers.describe(request.params);
      case 'models.reasoning.get':
        return this.features.providers.reasoning(request.params.botId);
      case 'models.reasoning.set':
        return this.features.providers.setReasoning(request.params);
      case 'models.options':
        return this.features.providers.models(request.params);
      case 'models.info':
        return this.features.providers.info(request.params.botId);
      case 'models.assign':
        return this.features.providers.assign(request.params);
      case 'hermes.settings.get':
        return this.features.settings.get(request.params.botId);
      case 'hermes.settings.set':
        return this.features.settings.set(request.params);
      case 'hermes.shared.get':
        return this.features.settings.shared();
      case 'hermes.shared.set':
        return this.features.settings.setShared(request.params);
      case 'bots.create': {
        const { archiveFileId, ...fields } = request.params;
        const created = await this.features.bots.create(
          fields,
          archiveFileId ? this.features.files.profileArchive(archiveFileId) : undefined,
        );
        // Driving the user's own desktop is opt-in per Bot (Bot details), not Hermes' default.
        if (this.features.desktop) await this.features.desktopControl.bot(created.bot.botId, false);
        this.execution.startWelcome(created.bot.botId, created.conversation.conversationId);
        return created;
      }
      case 'bots.welcome.retry': {
        const previous = this.features.database.message(request.params.messageId);
        if (
          previous?.kind !== 'text' ||
          !previous.content.welcome ||
          !['failed', 'cancelled'].includes(previous.status) ||
          !previous.author.id
        )
          throw new NodeFault('conflict', 'This introduction is not waiting for a retry');
        this.features.bots.get(previous.author.id);
        const messageId = this.execution.startWelcome(
          previous.author.id,
          previous.conversationId,
          true,
        );
        this.features.database.putMessage({
          ...previous,
          content: { ...previous.content, welcome: undefined },
        });
        return { messageId };
      }
      case 'bots.update':
        return this.features.bots.update(request.params);
      case 'bots.archive':
        this.features.bots.archive(request.params.botId);
        if (this.features.routines.routes().some((route) => route.botId === request.params.botId))
          await this.features.routines.syncRoutes();
        return {};
      case 'bots.permissions.get':
        return {
          mode: await this.features.hermes.approvalMode(
            this.features.bots.get(request.params.botId).botId,
          ),
        };
      case 'groups.create':
        return this.features.groups.create(request.params);
      case 'groups.update':
        return this.features.groups.update(request.params);
      case 'groups.archive':
        return this.features.groups.archive(request.params.groupId);
      default:
        throw new NodeFault('not_found', 'Method is not available in this phase');
    }
  }
}
