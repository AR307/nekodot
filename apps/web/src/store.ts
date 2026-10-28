import { create } from 'zustand';
import type {
  Bot,
  Conversation,
  Group,
  LiveEvent,
  Me,
  Message,
  PersistedEvent,
} from '@nekodot/protocol';

export interface NodeState {
  bots: Bot[];
  groups: Group[];
  conversations: Conversation[];
  messages: Record<string, Message[]>;
  activity: Record<string, ActivityState>;
  online: boolean;
  seq: number;
  platform: string;
  computerUse: boolean;
}
export type ActivityState = {
  botId?: string;
  state: 'thinking' | 'tool' | 'waiting_approval' | 'idle';
  chain?: { count: number; max: number };
};
export interface TeamState extends Omit<NodeState, 'activity'> {
  activity: Record<string, ActivityState>;
}
const emptyNode = (): TeamState => ({
  bots: [],
  groups: [],
  conversations: [],
  messages: {},
  activity: {},
  online: false,
  seq: 0,
  platform: '',
  computerUse: false,
});
const initialToken = localStorage.getItem('nekodot-token');
const initialLanguage = localStorage.getItem('nekodot-language') === 'en' ? 'en' : 'zh';
const initialNodeId = localStorage.getItem('nekodot-node');

interface AppState {
  token: string | null;
  language: 'zh' | 'en';
  me: Me | null;
  selectedNodeId: string | null;
  selectedConversationId: string | null;
  screen: 'home' | 'pair' | 'settings' | 'auth';
  nodes: Record<string, TeamState>;
  pairing: { code: string; expiresAt: string; installCommand: string } | null;
  authError: string;
  setToken(token: string | null): void;
  setMe(me: Me | null): void;
  setScreen(screen: AppState['screen']): void;
  setSelectedNode(nodeId: string | null): void;
  setSelectedConversation(conversationId: string | null): void;
  setLanguage(language: 'zh' | 'en'): void;
  setPairing(pairing: AppState['pairing']): void;
  setAuthError(message: string): void;
  setNodeOnline(nodeId: string, online: boolean): void;
  setSnapshot(
    nodeId: string,
    snapshot: {
      bots: Bot[];
      groups: Group[];
      conversations: Conversation[];
      headSeq: number;
      node: { platform: string; computerUse: boolean };
    },
  ): void;
  setMessages(nodeId: string, conversationId: string, messages: Message[]): void;
  applyEvent(nodeId: string, event: PersistedEvent): void;
  applyLive(nodeId: string, event: LiveEvent): void;
}

export const useAppStore = create<AppState>((set) => ({
  token: initialToken,
  language: initialLanguage,
  me: null,
  selectedNodeId: initialNodeId,
  selectedConversationId: initialNodeId
    ? localStorage.getItem('nekodot-conversation-' + initialNodeId)
    : null,
  screen: initialToken ? 'home' : 'auth',
  nodes: {},
  pairing: null,
  authError: '',
  setToken: (token) => {
    if (token) localStorage.setItem('nekodot-token', token);
    else localStorage.removeItem('nekodot-token');
    set({
      token,
      me: null,
      nodes: {},
      pairing: null,
      selectedConversationId: null,
      screen: token ? 'home' : 'auth',
    });
  },
  setMe: (me) => set({ me }),
  setScreen: (screen) => set({ screen }),
  setSelectedNode: (nodeId) => {
    if (nodeId) localStorage.setItem('nekodot-node', nodeId);
    else localStorage.removeItem('nekodot-node');
    set({
      selectedNodeId: nodeId,
      selectedConversationId: nodeId
        ? localStorage.getItem('nekodot-conversation-' + nodeId)
        : null,
    });
  },
  setSelectedConversation: (selectedConversationId) =>
    set((state) => {
      if (state.selectedNodeId) {
        const key = 'nekodot-conversation-' + state.selectedNodeId;
        if (selectedConversationId) localStorage.setItem(key, selectedConversationId);
        else localStorage.removeItem(key);
      }
      return { selectedConversationId };
    }),
  setLanguage: (language) => {
    localStorage.setItem('nekodot-language', language);
    set({ language });
  },
  setPairing: (pairing) => set({ pairing }),
  setAuthError: (authError) => set({ authError }),
  setNodeOnline: (nodeId, online) =>
    set((state) => {
      const current = state.nodes[nodeId] ?? emptyNode();
      return {
        nodes: { ...state.nodes, [nodeId]: { ...current, online } },
        me: state.me
          ? {
              ...state.me,
              nodes: state.me.nodes.map((node) =>
                node.nodeId === nodeId ? { ...node, online } : node,
              ),
            }
          : null,
      };
    }),
  setSnapshot: (nodeId, snapshot) =>
    set((state) => {
      const current = state.nodes[nodeId] ?? emptyNode();
      return {
        nodes: {
          ...state.nodes,
          [nodeId]: {
            ...current,
            bots: snapshot.bots,
            groups: snapshot.groups,
            conversations: snapshot.conversations,
            seq: snapshot.headSeq,
            platform: snapshot.node.platform,
            computerUse: snapshot.node.computerUse,
            online: true,
            activity: {},
          },
        },
      };
    }),
  setMessages: (nodeId, conversationId, messages) =>
    set((state) => {
      const node = state.nodes[nodeId] ?? emptyNode();
      const merged = new Map(
        (node.messages[conversationId] ?? []).map((message) => [message.messageId, message]),
      );
      for (const message of messages) merged.set(message.messageId, message);
      return {
        nodes: {
          ...state.nodes,
          [nodeId]: {
            ...node,
            messages: {
              ...node.messages,
              [conversationId]: [...merged.values()].sort((a, b) => a.seq - b.seq),
            },
          },
        },
      };
    }),
  applyEvent: (nodeId, event) =>
    set((state) => {
      const node = state.nodes[nodeId] ?? emptyNode();
      if (event.seq <= node.seq) return state;
      const next: TeamState = { ...node, seq: event.seq };
      switch (event.kind) {
        case 'bot.upserted':
          next.bots = [...node.bots.filter((bot) => bot.botId !== event.data.botId), event.data];
          break;
        case 'bot.archived':
          next.bots = node.bots.map((bot) =>
            bot.botId === event.data.botId ? { ...bot, archived: true } : bot,
          );
          break;
        case 'conversation.upserted':
          next.conversations = [
            ...node.conversations.filter(
              (conversation) => conversation.conversationId !== event.data.conversationId,
            ),
            event.data,
          ];
          break;
        case 'message.upserted': {
          const conversationId = event.data.conversationId;
          const existing = node.messages[conversationId] ?? [];
          next.messages = {
            ...node.messages,
            [conversationId]: [
              ...existing.filter((message) => message.messageId !== event.data.messageId),
              event.data,
            ].sort((a, b) => a.seq - b.seq),
          };
          break;
        }
        case 'group.upserted':
          next.groups = [
            ...node.groups.filter((group) => group.groupId !== event.data.groupId),
            event.data,
          ];
          break;
        case 'group.archived':
          next.groups = node.groups.filter((group) => group.groupId !== event.data.groupId);
          break;
      }
      return { nodes: { ...state.nodes, [nodeId]: next } };
    }),
  applyLive: (nodeId, event) =>
    set((state) => {
      const node = state.nodes[nodeId] ?? emptyNode();
      if (event.kind === 'activity')
        return {
          nodes: {
            ...state.nodes,
            [nodeId]: {
              ...node,
              activity: {
                ...node.activity,
                [event.conversationId]: {
                  state: event.state,
                  botId: event.botId,
                  chain: event.chain,
                },
              },
            },
          },
        };
      const messages = node.messages[event.conversationId] ?? [];
      const found = messages.find((message) => message.messageId === event.messageId);
      if (!found || found.kind !== 'text' || event.offset > found.content.text.length) return state;
      const remaining = event.text.slice(found.content.text.length - event.offset);
      if (!remaining || found.status !== 'streaming') return state;
      return {
        nodes: {
          ...state.nodes,
          [nodeId]: {
            ...node,
            messages: {
              ...node.messages,
              [event.conversationId]: messages.map((message) =>
                message.messageId === event.messageId
                  ? { ...found, content: { text: found.content.text + remaining } }
                  : message,
              ),
            },
          },
        },
      };
    }),
}));

export const selectNodeData = (state: AppState) =>
  state.selectedNodeId ? (state.nodes[state.selectedNodeId] ?? emptyNode()) : emptyNode();
