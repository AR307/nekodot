import { randomBytes, randomUUID } from 'node:crypto';
import type { Bot, RpcParams, RpcResult } from '@nekodot/protocol';
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
    await this.hermes.configureProvider(input, this.database.bots());
    const { apiKey, ...settings } = input;
    const output = { ...settings, apiKeyLast4: apiKey.slice(-4) };
    this.database.setSetting('provider', output);
    return output;
  }
  async create(input: RpcParams<'bots.create'>) {
    if (!this.provider()) throw new NodeFault('invalid_params', 'Configure a provider first');
    if (this.database.handleUsed(input.handle))
      throw new NodeFault('conflict', 'Handle already used');
    const alphabet = 'abcdefghijklmnopqrstuvwxyz234567';
    const bot: Bot = {
      botId: 'nk-' + [...randomBytes(6)].map((n) => alphabet[n % 32]).join(''),
      ...input,
      archived: false,
      createdAt: new Date().toISOString(),
    };
    await this.hermes.configureBot(bot, true);
    this.database.putBot(bot);
    this.database.putConversation({
      conversationId: randomUUID(),
      kind: 'dm',
      botId: bot.botId,
      createdAt: new Date().toISOString(),
    });
    return { bot };
  }
  async update(input: RpcParams<'bots.update'>) {
    const bot = { ...this.get(input.botId), ...input };
    if (this.database.handleUsed(bot.handle, bot.botId))
      throw new NodeFault('conflict', 'Handle already used');
    await this.hermes.configureBot(bot, false);
    this.database.putBot(bot);
    return { bot };
  }
  archive(botId: string) {
    const bot = this.get(botId);
    this.database.putBot({ ...bot, archived: true });
    return {};
  }
}
