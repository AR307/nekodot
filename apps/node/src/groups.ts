import { randomUUID } from 'node:crypto';
import type { Conversation, Group, RpcParams } from '@nekodot/protocol';
import { NodeFault } from './fault';
import type { NodeDatabase } from './database';

const now = () => new Date().toISOString();

export class GroupService {
  constructor(readonly database: NodeDatabase) {}

  create(input: RpcParams<'groups.create'>) {
    this.requireActiveBots(input.botIds);
    const group: Group = {
      groupId: randomUUID(),
      ...input,
      archived: false,
      createdAt: now(),
    };
    const conversation: Conversation = {
      conversationId: randomUUID(),
      kind: 'group',
      groupId: group.groupId,
      createdAt: now(),
    };
    this.database.putGroup(group, conversation);
    return { group };
  }

  update(input: RpcParams<'groups.update'>) {
    const current = this.database.group(input.groupId);
    if (!current || current.archived) throw new NodeFault('not_found', 'Group not found');
    const group = { ...current, ...input };
    this.requireActiveBots(group.botIds);
    if (!group.botIds.includes(group.leadBotId))
      throw new NodeFault('invalid_params', 'The lead bot must be a group member');
    this.database.putGroup(group);
    return { group };
  }

  archive(groupId: string) {
    const group = this.database.group(groupId);
    if (!group || group.archived) throw new NodeFault('not_found', 'Group not found');
    this.database.putGroup({ ...group, archived: true });
    return {};
  }

  private requireActiveBots(botIds: string[]) {
    const bots = new Map(this.database.bots().map((bot) => [bot.botId, bot]));
    for (const botId of botIds)
      if (!bots.has(botId)) throw new NodeFault('not_found', 'A group member bot is not active');
  }
}
