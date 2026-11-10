import { randomUUID } from 'node:crypto';
import type { RpcParams } from '@nekodot/protocol';
import { NodeDatabase } from './database';
import { NodeFault } from './fault';
import { BotService } from './bots';
import { Operations } from './operations';
import { BotManagement } from './bot-management';
import { FileLibrary } from './files';
import { BotCommands } from './commands';
import type { CommandResult } from './session-commands';
import { ExecutionFlows } from './flow';

import type { ConversationExecution } from './execution/sessions';
const now = () => new Date().toISOString();
export class CommandOperations {
  constructor(
    private readonly bots: BotService,
    private readonly database: NodeDatabase,
    private readonly operations: Operations,
    private readonly management: BotManagement,
    private readonly commands: BotCommands,
    private readonly flow: ExecutionFlows,
    private readonly files: FileLibrary,
    private readonly execution: Pick<
      ConversationExecution,
      'queueInput' | 'sendMessage' | 'stopTasks'
    >,
  ) {}
  execute(params: RpcParams<'commands.execute'>) {
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
    const existing = this.operations.byKind(operationKind);
    if (existing) return existing;
    if (
      params.sessionId &&
      params.sessionId !== this.database.hermesSession(params.conversationId)?.storedSessionId
    )
      throw new NodeFault('conflict', 'The original conversation session has changed.');
    return this.operations.start(operationKind, [params.botId], async (operation) => {
      const refine = /^\/refine(?:\s+(.*))?$/.exec(params.command.trim());
      let result: CommandResult;
      if (/^\/stop(?:\s|$)/.test(params.command.trim())) {
        result = {
          output: await this.execution.stopTasks(
            params.conversationId,
            params.command.trim().slice(5).trim(),
            params.taskId,
          ),
        };
      } else if (refine && !/^(pending|approve|reject|diff)(?:\s|$)/.test(refine[1] ?? '')) {
        await this.management.refineInOperation(params.botId, refine[1] ?? '', operation);
        result = { output: operation.detail };
      } else result = await this.commands.execute(params.botId, params.command, params.clientMsgId);
      if (result.type === 'alias' && result.target)
        result = await this.commands.execute(params.botId, result.target);
      if (result.type === 'queue' && result.message) {
        if (conversation.kind !== 'dm')
          throw new NodeFault(
            'invalid_params',
            'Queue inputs in this Bot’s private chat. Group handoffs keep their existing routing.',
          );
        await this.execution.queueInput(params, result.message, result.target);
      }
      if ((result.type === 'send' || result.type === 'skill') && result.message) {
        await this.execution.sendMessage(
          {
            conversationId: params.conversationId,
            text: result.display || params.command,
            clientMsgId: params.clientMsgId,
          },
          { botId: params.botId, input: result.message, modelOverride: result.modelOverride },
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
            text: output,
            command: params.command.split(/\s/)[0]!,
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
}
