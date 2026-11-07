import { randomUUID } from 'node:crypto';
import { RunMessages } from '../execution/messages';
import { BotSecrets } from '../secrets';
import type { LiveEvent, Message, RpcParams } from '@nekodot/protocol';
import { NodeDatabase, type GroupChainRecord, type RunRecord } from '../database';
import type { HermesRuntime } from '../hermes/runtime';
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
    private readonly hermes: HermesRuntime,
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
    const active =
      this.runs.current(conversation.conversationId) ??
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
      const previousReply = this.messages.currentText(active);
      if (previousReply) {
        previousReply.status = 'done';
        this.database.putMessage(previousReply, { runId: active.runId }, active);
        this.messages.release(previousReply.messageId);
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
      this.runs.publish(active);
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
      commandModelOverride: command?.modelOverride,
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

  async startNextGroupRun(chain: GroupChainRecord) {
    if (chain.count >= MAX_CHAIN || !chain.queue.length)
      this.notifications.send({
        notificationId: `chain:${chain.notificationId}`,
        conversationId: chain.conversationId,
        kind: chain.failed ? 'failed' : 'completed',
      });
    if (chain.count >= MAX_CHAIN) {
      this.flow.group(chain, 'paused');
      this.groupNotice(chain, 'Relay paused after 6 turns. Mention a group member to continue.');
      this.database.clearChain(chain.conversationId);
      this.publishGroupIdle(chain.conversationId);
      return;
    }
    if (!chain.queue.length) {
      this.flow.group(chain, chain.failed ? 'failed' : 'done');
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
    const modelOverride = chain.commandModelOverride;
    chain.commandModelOverride = undefined;
    this.database.saveChain(chain);
    const run: RunRecord = {
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
    const chain = this.database.chain(run.conversationId);
    this.runs.release(run);
    if (!chain || status === 'cancelled') {
      if (chain) this.flow.group(chain, 'cancelled');
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
