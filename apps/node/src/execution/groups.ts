import { randomUUID } from 'node:crypto';
import { RunMessages } from '../execution/messages';
import { BotSecrets } from '../secrets';
import type { LiveEvent, Message, RpcParams } from '@nekodot/protocol';
import { NodeDatabase, type GroupChainRecord, type RunRecord } from '../database';
import { NodeFault } from '../fault';
import { BotService } from '../bots';
import { groupPrompt, MAX_CHAIN, mentionedBots } from '../group-routing';
import { FileLibrary } from '../files';
import { Notifications } from '../notifications';
import { SharedUserMemory } from '../user-memory';
import { ExecutionFlows } from '../flow';

const now = () => new Date().toISOString();
interface GroupRunControl {
  current(conversationId: string): RunRecord | undefined;
  activate(run: RunRecord): void;
  release(run: RunRecord): void;
  publish(run: RunRecord): void;
  start(run: RunRecord, input: string, instructions?: string): Promise<void>;
}
export class GroupExecution {
  constructor(
    private readonly database: NodeDatabase,
    private readonly bots: BotService,
    private readonly messages: RunMessages,
    private readonly files: FileLibrary,
    private readonly flow: ExecutionFlows,
    private readonly notifications: Notifications,
    private readonly secrets: BotSecrets,
    private readonly userMemory: SharedUserMemory,
    private readonly runs: GroupRunControl,
    private readonly onLive: (event: LiveEvent) => void,
  ) {}
  async sendGroupMessage(
    params: RpcParams<'messages.send'>,
    conversation: Extract<NonNullable<ReturnType<NodeDatabase['conversation']>>, { kind: 'group' }>,
    command?: { botId: string; input: string; modelOverride?: RunRecord['modelOverride'] },
  ) {
    const group = this.database.group(conversation.groupId);
    if (!group || group.archived) throw new NodeFault('not_found', 'Group not found');
    const roster = group.botIds.map((botId) => this.bots.get(botId));
    const target = params.taskId ? this.database.task(params.taskId) : undefined;
    const userMessage: Message = {
      messageId: randomUUID(),
      conversationId: conversation.conversationId,
      seq: this.database.head(),
      author: { type: 'user' },
      kind: 'text',
      status: 'done',
      createdAt: now(),
      content: { text: params.text, ...(params.spaceId ? { spaces: [params.spaceId] } : {}) },
    };
    if (target) {
      userMessage.taskId = target.taskId;
      userMessage.groupChainId = target.groupChainId;
      if (params.files?.length) this.files.attach(userMessage, params.files);
      const run: RunRecord = {
        role: 'coordinator',
        conversationId: conversation.conversationId,
        botId: target.botId,
        groupId: group.groupId,
        groupChainId: target.groupChainId,
        groupFollowup: true,
        targetTaskId: target.taskId,
        inputMessageId: userMessage.messageId,
        submissionId: params.clientMsgId,
        queue: 'queued',
        lastSeq: -1,
        state: 'thinking',
      };
      this.database.putMessage(userMessage, { clientMsgId: params.clientMsgId }, run);
      void this.runs.start(run, params.text);
      return { messageId: userMessage.messageId };
    }
    const mentioned = mentionedBots(params.text, roster);
    const chain: GroupChainRecord = {
      notificationId: userMessage.messageId,
      inputMessageId: userMessage.messageId,
      conversationId: conversation.conversationId,
      group,
      roster,
      queue: command ? [command.botId] : mentioned.length ? mentioned : [group.leadBotId],
      commandInput: command?.input,
      commandModelOverride: command?.modelOverride,
      count: 0,
      cursorByBot: {},
      requestId: userMessage.messageId,
      active: true,
    };
    userMessage.groupChainId = chain.notificationId;
    userMessage.seq = this.database.head();
    if (params.files?.length) this.files.attach(userMessage, params.files);
    this.database.putMessage(userMessage, { clientMsgId: params.clientMsgId }, undefined, chain);
    await this.startNextGroupRun(chain);
    return { messageId: userMessage.messageId };
  }

  async startNextGroupRun(chain: GroupChainRecord) {
    if (chain.count >= MAX_CHAIN || !chain.queue.length)
      this.notifications.send({
        ...(chain.taskId ? { taskId: chain.taskId } : {}),
        notificationId: `chain:${chain.notificationId}`,
        conversationId: chain.conversationId,
        kind: chain.failed ? 'failed' : 'completed',
      });
    if (chain.count >= MAX_CHAIN) {
      this.flow.group(chain, 'paused');
      this.groupNotice(chain, 'Relay paused after 6 turns. Mention a group member to continue.');
      this.database.clearChain(chain.notificationId);
      this.publishGroupIdle(chain.conversationId);
      return;
    }
    if (!chain.queue.length) {
      this.flow.group(chain, chain.failed ? 'failed' : 'done');
      this.database.clearChain(chain.notificationId);
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
    const modelOverride = chain.commandModelOverride;
    chain.commandModelOverride = undefined;
    this.database.saveChain(chain);
    const run: RunRecord = {
      role: 'coordinator',
      groupChainId: chain.notificationId,
      targetTaskId: chain.taskId,
      queue: 'queued',
      conversationId: chain.conversationId,
      botId,
      groupId: chain.group.groupId,
      requestId: chain.requestId,
      lastSeq: -1,
      state: 'thinking',
      inputMessageId: chain.requestId ?? randomUUID(),
      ...(modelOverride ? { modelOverride } : {}),
    };
    this.database.saveRun(run);
    this.runs.activate(run);
    this.runs.publish(run);
    void this.runs.start(run, chain.currentInput, chain.currentInstructions);
  }

  groupNotice(chain: GroupChainRecord, text: string) {
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

  publishGroupIdle(conversationId: string) {
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

  async finishGroupRun(
    run: RunRecord,
    status: 'completed' | 'failed' | 'cancelled',
    output: string,
  ) {
    await this.secrets.finish(run);
    run.state = 'idle';
    const chain = run.groupChainId ? this.database.chain(run.groupChainId) : undefined;
    this.runs.release(run);
    if (run.groupFollowup) {
      this.database.saveRun(run);
      this.runs.publish(run);
      return;
    }
    if (
      chain &&
      run.role === 'coordinator' &&
      this.database
        .tasks(run.conversationId)
        .some(
          (task) =>
            task.groupChainId === chain.notificationId &&
            (!['completed', 'failed', 'cancelled'].includes(task.state) || !task.reportMessageId),
        )
    ) {
      this.database.saveRun(run);
      this.runs.publish(run);
      return;
    }
    if (!chain || status === 'cancelled') {
      if (chain) this.flow.group(chain, 'cancelled');
      if (chain && status === 'cancelled') this.database.clearChain(chain.notificationId);
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
        if (botId !== run.botId && !chain.queue.includes(botId)) chain.queue.push(botId);
    chain.currentBotId = undefined;
    chain.currentInstructions = undefined;
    chain.requestId = randomUUID();
    this.database.saveRun({ ...run, state: 'idle' });
    this.database.saveChain(chain);
    this.flow.group(chain);
    await this.userMemory.sync();
    await this.startNextGroupRun(chain);
  }
}
