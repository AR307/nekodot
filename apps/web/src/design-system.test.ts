import { readFileSync, readdirSync } from 'node:fs';
import { join, relative } from 'node:path';
import { expect, test } from 'vitest';
import { breakpoints, durations, ease, easeExit, easePop, shift, stagger } from './motion';

/**
 * Static guards for the motion and layout system
 * (docs/superpowers/specs/2026-11-05-ui-ergonomics-motion-design.md):
 * one source of truth for timing, curves and breakpoints.
 */
const root = new URL('.', import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1');
const files = (dir: string): string[] =>
  readdirSync(dir, { withFileTypes: true }).flatMap((entry) =>
    entry.isDirectory() ? files(join(dir, entry.name)) : [join(dir, entry.name)],
  );
const sources = files(root);
const read = (file: string) => readFileSync(file, 'utf8');
const where = (file: string, text: string, index: number) =>
  `${relative(root, file).replaceAll('\\', '/')}:${text.slice(0, index).split('\n').length}`;
const tokens = read(join(root, 'styles/tokens.css'));
const token = (name: string) => {
  const match = new RegExp(`--${name}:\\s*([^;]+);`).exec(tokens);
  if (!match) throw new Error(`missing --${name} in tokens.css`);
  return match[1]!.trim();
};
const curve = (value: string) =>
  /cubic-bezier\(([^)]+)\)/
    .exec(value)![1]!
    .split(',')
    .map((part) => Number(part.trim()));

test('motion.ts mirrors the CSS motion tokens', () => {
  for (const [name, seconds] of Object.entries(durations))
    expect(token(`dur-${name}`), name).toBe(`${Math.round(seconds * 1000)}ms`);
  expect(curve(token('ease'))).toEqual([...ease]);
  expect(curve(token('ease-pop'))).toEqual([...easePop]);
  expect(curve(token('ease-exit'))).toEqual([...easeExit]);
  for (const [step, px] of Object.entries(shift)) expect(token(`shift-${step}`)).toBe(`${px}px`);
  expect(token('stagger')).toBe(`${Math.round(stagger * 1000)}ms`);
});

test('CSS timing comes only from tokens', () => {
  const problems: string[] = [];
  for (const file of sources.filter((f) => f.endsWith('.css') && !f.endsWith('tokens.css'))) {
    const text = read(file);
    const declaration =
      /(?:^|[;{\s])((?:transition|animation)(?:-duration|-delay|-timing-function)?)\s*:\s*([^;}]+)/g;
    for (const match of text.matchAll(declaration)) {
      const value = match[2]!;
      if (/cubic-bezier\(|(?<![\w-])\d*\.?\d+m?s\b/.test(value.replace(/(?<![\w.])0m?s\b/g, '')))
        problems.push(`${where(file, text, match.index)} ${match[1]}: ${value.trim()}`);
    }
  }
  expect(problems).toEqual([]);
});

test('Motion parameters in components come only from motion.ts', () => {
  const problems: string[] = [];
  const timing = /\b(?:duration|delay|stiffness|damping|bounce|repeatDelay)\s*:\s*([^,}\n]+)/g;
  const curves = /\beas(?:e|ing)\s*:\s*(?:\[|'(?!linear')[^']*')|cubic-bezier\(/g;
  for (const file of sources.filter((f) => /\.tsx?$/.test(f))) {
    if (/motion\.ts$|\.test\.ts$|[\\/]i18n[\\/]/.test(file)) continue;
    const text = read(file);
    for (const match of text.matchAll(timing))
      // Any number other than a bare 0 is a literal timing value.
      if (/(?<![\w.])(?!0(?![.\d]))\d*\.?\d+/.test(match[1]!))
        problems.push(`${where(file, text, match.index)} ${match[0].trim()}`);
    for (const match of text.matchAll(curves))
      problems.push(`${where(file, text, match.index)} ${match[0].trim()}`);
  }
  expect(problems).toEqual([]);
});

test('Media queries use only the shared breakpoints', () => {
  const allowed = new Set(Object.values(breakpoints).flatMap((px) => [`${px}px`, `${px - 1}px`]));
  const problems: string[] = [];
  for (const file of sources.filter((f) => /\.(css|tsx|ts)$/.test(f) && !f.endsWith('.test.ts'))) {
    const text = read(file);
    for (const match of text.matchAll(/\((?:max|min)-width:\s*(\d+px)\)/g)) {
      // Container queries size a component to its own box, not the viewport scale.
      const line = text.slice(text.lastIndexOf('\n', match.index) + 1, match.index);
      if (line.trimStart().startsWith('@container')) continue;
      if (!allowed.has(match[1]!)) problems.push(`${where(file, text, match.index)} ${match[0]}`);
    }
  }
  expect(problems).toEqual([]);
});
