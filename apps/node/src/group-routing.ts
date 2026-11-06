import type { Bot, Message } from '@nekodot/protocol';
import type { GroupChainRecord } from './database';

export const MAX_CHAIN = 6;

export function mentionedBots(text: string, roster: Pick<Bot, 'botId' | 'handle'>[]) {
  const byHandle = new Map(roster.map((bot) => [bot.handle, bot.botId]));
  const result: string[] = [];
  for (const match of text.matchAll(
    /(?:^|[^\p{L}\p{M}\p{N}_@-])@([\p{L}\p{M}\p{N}_-]+)(?![\p{L}\p{M}\p{N}_-])/gu,
  )) {
    const targets =
      match[1] === 'everyone' ? roster.map((bot) => bot.botId) : [byHandle.get(match[1]!)];
    for (const botId of targets) {
      if (botId && !result.includes(botId)) result.push(botId);
    }
  }
  return result;
}

export function groupPrompt(chain: GroupChainRecord, botId: string, messages: Message[]) {
  const members = new Map(chain.roster.map((bot) => [bot.botId, bot]));
  const lines = messages.flatMap((message) => {
    if (message.kind !== 'text' || message.author.type === 'system') return [];
    const author = message.author.id ? members.get(message.author.id) : undefined;
    const name = author ? `${author.displayName} (@${author.handle})` : 'User';
    return [`${name}: ${message.content.text}`];
  });
  return {
    input: `[nekodot group "${chain.group.name}"] New messages since your last turn:\n${lines.join('\n')}\nReply to the group as @${members.get(botId)!.handle}.`,
    instructions: `Group members: ${chain.roster
      .map((bot) => `${bot.displayName} (@${bot.handle}) — ${bot.role}`)
      .join(', ')}. Mention a teammate with @handle only when you need them to act.`,
  };
}
