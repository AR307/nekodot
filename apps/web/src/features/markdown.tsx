import { useState, type ReactNode } from 'react';
import { Icon } from '../ui';
import { writeClipboard } from '../native';

/**
 * Small, safe Markdown subset for bot replies: fenced code, headings, lists, quotes,
 * rules, paragraphs, inline code, bold, italics, links and @mentions. Builds React
 * nodes directly (no HTML injection) and tolerates half-streamed input.
 */
export function Markdown({
  text,
  mentions,
  copyLabel,
  copiedLabel,
  trailing,
}: {
  text: string;
  mentions?: string[];
  copyLabel: string;
  copiedLabel: string;
  /** Inline node kept on the last line of text, e.g. the streaming caret. */
  trailing?: ReactNode;
}) {
  const blocks = parseBlocks(text);
  const lastIndex = blocks.length - 1;
  const tail = (index: number) => (index === lastIndex ? trailing : null);
  const inline = (value: string, key: string) => renderInline(value, key, mentions);
  return (
    <>
      {blocks.map((block, index) => {
        const key = String(index);
        switch (block.type) {
          case 'code':
            return (
              <CodeBlock
                key={key}
                lang={block.lang}
                code={block.text}
                copyLabel={copyLabel}
                copiedLabel={copiedLabel}
              />
            );
          case 'heading':
            return (
              <p key={key} className={`md-heading md-h${block.level}`}>
                {inline(block.text, key)}
                {tail(index)}
              </p>
            );
          case 'quote':
            return (
              <blockquote key={key}>
                {inline(block.text, key)}
                {tail(index)}
              </blockquote>
            );
          case 'rule':
            return <hr key={key} />;
          case 'list': {
            const List = block.ordered ? 'ol' : 'ul';
            return (
              <List key={key} start={block.ordered ? block.start : undefined}>
                {block.items.map((item, itemIndex) => (
                  <li key={itemIndex}>
                    {inline(item, key + '-' + itemIndex)}
                    {itemIndex === block.items.length - 1 && tail(index)}
                  </li>
                ))}
              </List>
            );
          }
          default:
            return (
              <p key={key}>
                {inline(block.text, key)}
                {tail(index)}
              </p>
            );
        }
      })}
      {(blocks.length === 0 ||
        blocks[lastIndex]!.type === 'code' ||
        blocks[lastIndex]!.type === 'rule') &&
        trailing}
    </>
  );
}

type Block =
  | { type: 'paragraph'; text: string }
  | { type: 'heading'; level: number; text: string }
  | { type: 'quote'; text: string }
  | { type: 'rule' }
  | { type: 'code'; lang: string; text: string }
  | { type: 'list'; ordered: boolean; start: number; items: string[] };

const bullet = /^\s{0,3}[-*+]\s+(.*)$/;
const numbered = /^\s{0,3}(\d{1,9})[.)]\s+(.*)$/;

function parseBlocks(text: string): Block[] {
  const lines = text.replace(/\r\n?/g, '\n').split('\n');
  const blocks: Block[] = [];
  let index = 0;
  while (index < lines.length) {
    const line = lines[index]!;
    const fence = /^\s{0,3}(```|~~~)\s*([\w+-]*)/.exec(line);
    if (fence) {
      const body: string[] = [];
      index++;
      while (index < lines.length && !lines[index]!.trim().startsWith(fence[1]!))
        body.push(lines[index++]!);
      index++;
      blocks.push({ type: 'code', lang: fence[2] ?? '', text: body.join('\n') });
      continue;
    }
    if (!line.trim()) {
      index++;
      continue;
    }
    const heading = /^\s{0,3}(#{1,6})\s+(.*?)\s*#*\s*$/.exec(line);
    if (heading) {
      blocks.push({ type: 'heading', level: Math.min(heading[1]!.length, 3), text: heading[2]! });
      index++;
      continue;
    }
    if (/^\s{0,3}([-*_])(\s*\1){2,}\s*$/.test(line)) {
      blocks.push({ type: 'rule' });
      index++;
      continue;
    }
    if (/^\s{0,3}>/.test(line)) {
      const body: string[] = [];
      while (index < lines.length && /^\s{0,3}>/.test(lines[index]!))
        body.push(lines[index++]!.replace(/^\s{0,3}>\s?/, ''));
      blocks.push({ type: 'quote', text: body.join('\n') });
      continue;
    }
    const listMatch = bullet.exec(line) ?? numbered.exec(line);
    if (listMatch) {
      const ordered = !bullet.test(line);
      const items: string[] = [];
      const start = ordered ? Number(numbered.exec(line)![1]) : 1;
      while (index < lines.length) {
        const current = lines[index]!;
        const item = ordered ? numbered.exec(current) : bullet.exec(current);
        if (item) items.push(ordered ? item[2]! : item[1]!);
        else if (current.trim() && /^\s{2,}/.test(current) && items.length)
          items[items.length - 1] += '\n' + current.trim();
        else break;
        index++;
      }
      blocks.push({ type: 'list', ordered, start, items });
      continue;
    }
    const body: string[] = [];
    while (
      index < lines.length &&
      lines[index]!.trim() &&
      !/^\s{0,3}(```|~~~|#{1,6}\s|>)/.test(lines[index]!) &&
      !(body.length && (bullet.test(lines[index]!) || numbered.test(lines[index]!)))
    )
      body.push(lines[index++]!);
    blocks.push({ type: 'paragraph', text: body.join('\n') });
  }
  return blocks;
}

const inlinePattern =
  /(`[^`\n]+`)|(\*\*[^*\n]+\*\*)|(\*[^*\s][^*\n]*\*)|(\[[^\]\n]+\]\(https?:\/\/[^)\s]+\))|(https?:\/\/[^\s<>()]+[^\s<>().,;:!?'"，。；：！？])|((?<![\w@-])@[a-z0-9-]{1,24}(?![a-z0-9-]))/g;

function renderInline(text: string, key: string, mentions?: string[]): ReactNode[] {
  const nodes: ReactNode[] = [];
  let last = 0;
  let count = 0;
  const push = (value: string) => {
    value.split('\n').forEach((part, index) => {
      if (index) nodes.push(<br key={`${key}-br-${count++}`} />);
      if (part) nodes.push(part);
    });
  };
  for (const match of text.matchAll(inlinePattern)) {
    const [token] = match;
    const at = match.index;
    const id = `${key}-${count++}`;
    if (match[6] && !mentions?.includes(token.slice(1))) continue;
    push(text.slice(last, at));
    last = at + token.length;
    if (match[1]) nodes.push(<code key={id}>{token.slice(1, -1)}</code>);
    else if (match[2]) nodes.push(<strong key={id}>{token.slice(2, -2)}</strong>);
    else if (match[3]) nodes.push(<em key={id}>{token.slice(1, -1)}</em>);
    else if (match[4]) {
      const split = token.indexOf('](');
      nodes.push(
        <a key={id} href={token.slice(split + 2, -1)} target="_blank" rel="noreferrer noopener">
          {token.slice(1, split)}
        </a>,
      );
    } else if (match[5])
      nodes.push(
        <a key={id} href={token} target="_blank" rel="noreferrer noopener">
          {token}
        </a>,
      );
    else
      nodes.push(
        <span key={id} className="mention">
          {token}
        </span>,
      );
  }
  push(text.slice(last));
  return nodes;
}

function CodeBlock({
  lang,
  code,
  copyLabel,
  copiedLabel,
}: {
  lang: string;
  code: string;
  copyLabel: string;
  copiedLabel: string;
}) {
  const [copied, setCopied] = useState(false);
  return (
    <figure className="md-code">
      <figcaption>
        <span>{lang || 'text'}</span>
        <button
          type="button"
          onClick={() => {
            void writeClipboard(code).then(() => {
              setCopied(true);
              window.setTimeout(() => setCopied(false), 1600);
            });
          }}
        >
          <Icon name={copied ? 'check' : 'copy'} />
          {copied ? copiedLabel : copyLabel}
        </button>
      </figcaption>
      <pre>
        <code>{code}</code>
      </pre>
    </figure>
  );
}

/** Plain text with group @mentions emphasised (used for user bubbles). */
export function MentionText({ text, mentions }: { text: string; mentions?: string[] }) {
  if (!mentions?.length) return <>{text}</>;
  const parts = text.split(/((?<![\w@-])@[a-z0-9-]{1,24}(?![a-z0-9-]))/g);
  return (
    <>
      {parts.map((part, index) =>
        index % 2 && mentions.includes(part.slice(1)) ? (
          <b key={index} className="mention">
            {part}
          </b>
        ) : (
          part
        ),
      )}
    </>
  );
}

/** Markdown reduced to readable plain text, for one-line previews. */
export function plainText(text: string) {
  return text
    .replace(/```[\w+-]*\n?|~~~/g, '')
    .replace(/^\s{0,3}(#{1,6}|>|[-*+]|\d{1,9}[.)])\s+/gm, '')
    .replace(/\*\*([^*\n]+)\*\*/g, '$1')
    .replace(/\*([^*\s][^*\n]*)\*/g, '$1')
    .replace(/`([^`\n]+)`/g, '$1')
    .replace(/\[([^\]\n]+)\]\((https?:[^)\s]+)\)/g, '$1');
}
