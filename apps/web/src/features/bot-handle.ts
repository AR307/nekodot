/** Preview of the handle Node derives from a new Bot's name (Node owns the final, unique value). */
export function handleFromName(name: string) {
  const base = [
    ...name
      .trim()
      .normalize('NFKC')
      .toLowerCase()
      .replace(/^@/, '')
      .replace(/[^\p{L}\p{M}\p{N}_-]+/gu, '-')
      .replace(/^-+|-+$/g, ''),
  ].slice(0, 24);
  return base.length ? base.join('') : 'bot';
}
