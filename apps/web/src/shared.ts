import zh from './i18n/zh';
export const avatarColors = [
  '#E8603C',
  '#FF3B47',
  '#FF4FA3',
  '#B05FD0',
  '#8B75AF',
  '#5B7CE6',
  '#2E8BFF',
  '#19B5C9',
  '#2F9E8F',
  '#22C55E',
  '#77A979',
  '#F2C230',
  '#D9932B',
  '#A9683A',
  '#8C8376',
  '#5A5A60',
];
export type Texts = typeof zh;

export function fill(template: string, values: Record<string, string | number>) {
  return template.replace(/\{(\w+)\}/g, (match, key: string) => String(values[key] ?? match));
}

/** Compact list timestamp: just now, clock time today, yesterday, weekday this week, else date. */
export function listTime(iso: string, t: Texts) {
  const date = new Date(iso);
  const now = new Date();
  const locale = t === zh ? 'zh-CN' : 'en-US';
  if (now.getTime() - date.getTime() < 60_000) return t.justNow;
  const startOfDay = (value: Date) =>
    new Date(value.getFullYear(), value.getMonth(), value.getDate()).getTime();
  const days = Math.round((startOfDay(now) - startOfDay(date)) / 86_400_000);
  if (days === 0)
    return date.toLocaleTimeString(locale, { hour: '2-digit', minute: '2-digit', hour12: false });
  if (days === 1) return t.yesterday;
  if (days < 7) return date.toLocaleDateString(locale, { weekday: 'short' });
  return date.toLocaleDateString(locale, { month: 'numeric', day: 'numeric' });
}
