import { randomBytes, randomUUID } from 'node:crypto';
import type { Bot, Conversation, RpcParams } from '@nekodot/protocol';
import type { NodeDatabase } from './database';
import type { HermesRuntime } from './hermes/runtime';
import type { Providers } from './providers';

import { NodeFault } from './fault';
export class BotService {
  constructor(
    readonly database: NodeDatabase,
    readonly hermes: HermesRuntime,
    readonly providers: Providers,
  ) {}
  get(botId: string) {
    const bot = this.database.bot(botId);
    if (!bot || bot.archived) throw new NodeFault('not_found', 'Bot not found');
    return bot;
  }
  async create(input: RpcParams<'bots.create'>) {
    const { approvalMode, ...fields } = input;
    await this.providers.source(input.sourceId);
    if (this.database.handleUsed(input.handle))
      throw new NodeFault('conflict', 'Handle already used');
    const alphabet = 'abcdefghijklmnopqrstuvwxyz234567';
    const bot: Bot = {
      botId: 'nk-' + [...randomBytes(6)].map((n) => alphabet[n % 32]).join(''),
      ...fields,
      archived: false,
      createdAt: new Date().toISOString(),
    };
    await this.hermes.configureBot(bot, true, approvalMode);
    await this.providers.configureBot(bot);
    this.database.putBot(bot);
    const conversation: Conversation = {
      conversationId: randomUUID(),
      kind: 'dm',
      botId: bot.botId,
      createdAt: new Date().toISOString(),
    };
    this.database.putConversation(conversation);
    return { bot, conversation };
  }
  async update(input: RpcParams<'bots.update'>) {
    const { approvalMode, ...fields } = input;
    const previous = this.get(input.botId);
    const bot = { ...previous, ...fields };
    if (this.database.handleUsed(bot.handle, bot.botId))
      throw new NodeFault('conflict', 'Handle already used');
    await this.hermes.configureBot(
      bot,
      false,
      approvalMode,
      fields.role !== undefined && fields.role !== previous.role ? previous.role : undefined,
    );
    await this.providers.configureBot(bot);
    this.database.putBot(bot);
    return { bot };
  }
  archive(botId: string) {
    const bot = this.get(botId);
    if (this.database.groups().some((group) => group.botIds.includes(botId)))
      throw new NodeFault('conflict', 'Remove this bot from active groups before archiving it');
    this.database.putBot({ ...bot, archived: true });
    return {};
  }
}
