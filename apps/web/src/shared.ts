import zh from './i18n/zh';
export const avatarColors = [
  '#E8603C',
  '#2F9E8F',
  '#5B7CE6',
  '#D9932B',
  '#B05FD0',
  '#3FA45B',
  '#E05A8A',
  '#6B645B',
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
