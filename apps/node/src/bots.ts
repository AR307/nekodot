import { randomBytes, randomUUID } from 'node:crypto';
import type { Bot, Conversation, RpcParams, RpcResult } from '@nekodot/protocol';
import type { NodeDatabase } from './database';
import type { HermesRuntime, ProviderOutput } from './hermes/runtime';

import { NodeFault } from './fault';
export class BotService {
  constructor(
    readonly database: NodeDatabase,
    readonly hermes: HermesRuntime,
  ) {}
  get(botId: string) {
    const bot = this.database.bot(botId);
    if (!bot || bot.archived) throw new NodeFault('not_found', 'Bot not found');
    return bot;
  }
  provider(): RpcResult<'providers.get'> {
    return this.database.setting<ProviderOutput>('provider') ?? null;
  }
  async setProvider(input: RpcParams<'providers.set'>) {
    const previous = this.provider();
    if (!input.apiKey && previous?.kind !== input.kind)
      throw new NodeFault('invalid_params', 'Enter an API key for this provider');
    await this.hermes.configureProvider(input, this.database.bots());
    const { apiKey, ...settings } = input;
    const output = { ...settings, apiKeyLast4: apiKey?.slice(-4) ?? previous!.apiKeyLast4 };
    this.database.setSetting('provider', output);
    return output;
  }
  async create(input: RpcParams<'bots.create'>) {
    const { approvalMode, ...fields } = input;
    if (!this.provider()) throw new NodeFault('invalid_params', 'Configure a provider first');
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
