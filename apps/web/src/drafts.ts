import { create } from 'zustand';
import type { Attachment } from '@nekodot/protocol';

// Drafts live for this process only; server history remains the source of chat content.
export const useDrafts = create<{
  values: Record<string, string>;
  attachments: Record<string, Attachment[]>;
  addAttachment(key: string, file: Attachment): void;
  removeAttachments(key: string, ids: string[]): void;
  set(key: string, text: string): void;
  clear(): void;
}>((set) => ({
  values: {},
  attachments: {},
  addAttachment: (key, file) =>
    set((state) => ({
      attachments: {
        ...state.attachments,
        [key]: [...(state.attachments[key] ?? []), file],
      },
    })),
  removeAttachments: (key, ids) =>
    set((state) => ({
      attachments: {
        ...state.attachments,
        [key]: (state.attachments[key] ?? []).filter((file) => !ids.includes(file.fileId)),
      },
    })),
  set: (key, text) => set((state) => ({ values: { ...state.values, [key]: text } })),
  clear: () => set({ values: {}, attachments: {} }),
}));
