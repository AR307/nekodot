import { ConversationExecution } from './execution/sessions';
import { NodeRpc } from './rpc';
import { CommandOperations } from './command-operations';
import { BotSecrets } from './secrets';
import type { LiveEvent, PersistedEvent, RpcRequest } from '@nekodot/protocol';
import { NodeDatabase } from './database';
import type { HermesRuntime } from './hermes/runtime';
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
import { Notifications } from './notifications';
import { SharedUserMemory } from './user-memory';
import { BotCommands } from './commands';
import { NativeExtras } from './native-extras';
import { Routines } from './routines';
import { BotVoice } from './voice';
import { ExecutionFlows } from './flow';

export class NodeApplication {
  readonly database: NodeDatabase;
  readonly execution: ConversationExecution;
  private readonly rpc: NodeRpc;
  get idle() {
    return this.execution.idle;
  }
  handle(request: RpcRequest) {
    return this.rpc.handle(request);
  }
  activities() {
    this.execution.activities();
  }
  async resume() {
    await this.secrets.recover();
    // Desktop state is retained on probe failure; desktop.status retries the probe.
    if (this.desktop) void this.desktopControl.refresh().catch(() => {});
    await this.execution.resume();
  }
  async close() {
    this.secrets.close();
    await this.execution.stopWatching();
    this.voice.close();
    await this.routines.close();
    await this.userMemory.close();
    this.screens.close();
    this.execution.close();
    this.database.db.close();
  }

  readonly bots: BotService;
  readonly providers: Providers;
  readonly settings: HermesSettings;
  readonly groups: GroupService;
  readonly operations: Operations;
  readonly management: BotManagement;
  readonly files: FileLibrary;
  readonly extensions: Extensions;
  readonly screens: BotScreens;
  readonly desktopControl: DesktopControl;
  readonly notifications: Notifications;
  readonly userMemory: SharedUserMemory;
  readonly commands: BotCommands;
  readonly nativeExtras: NativeExtras;
  readonly routines: Routines;
  readonly secrets: BotSecrets;
  readonly voice: BotVoice;
  readonly flow: ExecutionFlows;

  onEvent: (event: PersistedEvent) => void = () => {};
  onLive: (event: LiveEvent) => void = () => {};

  constructor(
    home: string,
    readonly hermes: HermesRuntime,
    /** Hosted by the desktop client on the user's own computer rather than a server. */
    readonly desktop = false,
  ) {
    this.database = new NodeDatabase(home);

    this.flow = new ExecutionFlows(this.database);
    this.notifications = new Notifications(this.database);
    this.routines = new Routines(this.database, hermes, this.notifications);
    this.secrets = new BotSecrets(this.database, hermes);
    this.routines.scrub = (botId, value) => this.secrets.scrub(botId, value);
    this.secrets.onRequestCard = (request) =>
      this.notifications.send({
        notificationId: 'secret:' + request.requestId,
        ...(request.taskId ? { taskId: request.taskId } : {}),
        conversationId: request.conversationId,
        kind: 'question',
      });
    this.secrets.onWaiting = (run, waiting) =>
      this.onLive({
        kind: 'activity',
        conversationId: run.conversationId,
        botId: run.botId,
        taskId: run.taskId,
        state: waiting ? 'waiting_question' : 'thinking',
      });
    this.routines.onSecret = (input) => this.secrets.local(input);

    this.providers = new Providers(hermes, this.database);
    this.settings = new HermesSettings(hermes, this.database);
    this.bots = new BotService(this.database, hermes, this.providers, this.settings);
    this.groups = new GroupService(this.database);
    this.operations = new Operations(this.database);
    this.commands = new BotCommands(this.database, hermes);
    this.voice = new BotVoice(this.database, hermes);

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
    this.screens = new BotScreens(hermes, this.bots, this.operations, desktop);
    this.desktopControl = new DesktopControl(hermes, this.bots, desktop, this.screens.available);
    this.screens.onStatus = (status) => this.onLive({ kind: 'screen', status });
    this.database.onEvent = (event) => this.onEvent(event);
    this.execution = new ConversationExecution(
      this.database,
      this.hermes,
      this.bots,
      this.operations,
      this.files,
      this.routines,
      this.secrets,
      this.userMemory,
      this.flow,
      this.notifications,
      (event) => this.onLive(event),
    );
    const commandOperations = new CommandOperations(
      this.bots,
      this.database,
      this.operations,
      this.management,
      this.commands,
      this.flow,
      this.files,
      this.execution,
    );
    this.rpc = new NodeRpc(
      {
        secrets: this.secrets,
        bots: this.bots,
        voice: this.voice,
        operations: this.operations,
        commands: this.commands,
        nativeExtras: this.nativeExtras,
        userMemory: this.userMemory,
        screens: this.screens,
        desktopControl: this.desktopControl,
        routines: this.routines,
        management: this.management,
        files: this.files,
        extensions: this.extensions,
        flow: this.flow,
        database: this.database,
        providers: this.providers,
        settings: this.settings,
        desktop: this.desktop,
        hermes: this.hermes,
        groups: this.groups,
      },
      this.execution,
      commandOperations,
    );
  }
}
