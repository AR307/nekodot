import { create } from 'zustand';

// Drafts live for this process only; server history remains the source of chat content.
export const useDrafts = create<{
  values: Record<string, string>;
  set(key: string, text: string): void;
  clear(): void;
}>((set) => ({
  values: {},
  set: (key, text) => set((state) => ({ values: { ...state.values, [key]: text } })),
  clear: () => set({ values: {} }),
}));
