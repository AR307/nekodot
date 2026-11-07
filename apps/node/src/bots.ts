import { randomBytes, randomUUID } from 'node:crypto';
import type { Bot, Conversation, RpcParams } from '@nekodot/protocol';
import type { NodeDatabase } from './database';
import type { HermesRuntime } from './hermes/runtime';
import type { Providers } from './providers';
import type { HermesSettings } from './hermes-settings';

import { NodeFault } from './fault';
import { configureToolSearch } from './tool-search-policy';
export class BotService {
  constructor(
    readonly database: NodeDatabase,
    readonly hermes: HermesRuntime,
    readonly providers: Providers,
    readonly settings: HermesSettings,
  ) {}
  get(botId: string) {
    const bot = this.database.bot(botId);
    if (!bot || bot.archived) throw new NodeFault('not_found', 'Bot not found');
    return bot;
  }
  async create(input: Omit<RpcParams<'bots.create'>, 'archiveFileId'>, archive?: string) {
    const { approvalMode, handle: providedHandle, ...fields } = input;
    await this.providers.source(input.sourceId);
    let handle = providedHandle;
    if (!handle) {
      const base = [
        ...input.displayName
          .trim()
          .normalize('NFKC')
          .toLowerCase()
          .replace(/^@/, '')
          .replace(/[^\p{L}\p{M}\p{N}_-]+/gu, '-')
          .replace(/^-+|-+$/g, ''),
      ].slice(0, 24);
      if (!base.length) base.push(...'bot');
      handle = base.join('');
      for (let suffix = 2; this.database.handleUsed(handle); suffix++) {
        const ending = '-' + suffix;
        handle = base.slice(0, 24 - ending.length).join('') + ending;
      }
    } else if (this.database.handleUsed(handle))
      throw new NodeFault('conflict', 'Handle already used');
    const alphabet = 'abcdefghijklmnopqrstuvwxyz234567';
    const bot: Bot = {
      botId: 'nk-' + [...randomBytes(6)].map((n) => alphabet[n % 32]).join(''),
      ...fields,
      handle,
      archived: false,
      createdAt: new Date().toISOString(),
    };
    if (archive)
      await this.hermes.management.request('/api/profiles/import', undefined, {
        method: 'POST',
        body: JSON.stringify({ archive, name: bot.botId }),
      });
    await this.hermes.configureBot(bot, !archive, approvalMode);
    await this.providers.configureBot(bot);
    await this.settings.applyShared(bot.botId);
    if (bot.sourceId) await configureToolSearch(this.hermes, bot.botId);
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
    if (
      bot.sourceId &&
      (fields.sourceId !== undefined ||
        fields.model !== undefined ||
        fields.modelSettings?.contextLength !== undefined)
    )
      await configureToolSearch(this.hermes, bot.botId);
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
