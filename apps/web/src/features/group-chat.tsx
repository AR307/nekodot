import type { Bot, Conversation, Group, Message } from '@nekodot/protocol';
import type { ActivityState } from '../store';
import type { Texts } from '../shared';
import { ChatView } from './chat';

export function GroupChatView({
  t,
  group,
  conversation,
  bots,
  messages,
  activity,
  online,
  onBack,
  onEdit,
}: {
  t: Texts;
  group: Group;
  conversation: Conversation;
  bots: Bot[];
  messages: Message[];
  activity: ActivityState;
  online: boolean;
  onBack(): void;
  onEdit(): void;
}) {
  const lead = bots.find((bot) => bot.botId === group.leadBotId)!;
  const current = bots.find((bot) => bot.botId === activity.botId) ?? lead;
  return (
    <ChatView
      t={t}
      bot={current}
      bots={bots}
      group={group}
      chain={activity.chain}
      conversation={conversation}
      messages={messages}
      activity={activity.state}
      online={online}
      onBack={onBack}
      onEdit={onEdit}
    />
  );
}
