const limit = 160;

/**
 * The Dot's current line of thought, read from the reasoning Hermes streams: the latest
 * heading of a reasoning summary, else the latest complete sentence. Nothing until a sentence
 * completes, so the status changes a sentence at a time rather than a token at a time.
 */
export function currentThought(reasoning: string) {
  const headings = [...reasoning.matchAll(/^\s*\*\*([^*\n]{2,200})\*\*\s*$/gm)];
  const pieces = reasoning
    .split(/(?<=[.!?。！？])\s*|\n+/)
    .map((piece) => piece.trim())
    .filter(Boolean);
  const complete = /[.!?。！？]\s*$|\n\s*$/.test(reasoning) ? pieces : pieces.slice(0, -1);
  const line = (headings.at(-1)?.[1] ?? complete.at(-1) ?? '')
    .replace(/[*`#>]+/g, '')
    .replace(/^[-•\s]+/, '')
    .replace(/\s+/g, ' ')
    .trim();
  if (!line) return undefined;
  return line.length > limit ? line.slice(0, limit - 1).trimEnd() + '…' : line;
}
