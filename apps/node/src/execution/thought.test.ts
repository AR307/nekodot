import { describe, expect, it } from 'vitest';
import { currentThought } from './thought';

describe('currentThought', () => {
  it('takes the latest heading of a reasoning summary', () => {
    expect(
      currentThought(
        '**Reading the archive**\n\nI unzip it first.\n\n**Checking the totals**\n\nThe sum',
      ),
    ).toBe('Checking the totals');
  });

  it('takes the latest complete sentence and waits for the first one', () => {
    expect(currentThought('I need the file list')).toBeUndefined();
    expect(currentThought('I need the file list. Then I read the')).toBe('I need the file list.');
    expect(currentThought('先看目录。再读要求文件。')).toBe('再读要求文件。');
    expect(currentThought('Plan the steps\n')).toBe('Plan the steps');
  });

  it('keeps the line short and plain', () => {
    const long = 'word '.repeat(60).trim() + '.';
    const thought = currentThought(long)!;
    expect(thought.length).toBeLessThanOrEqual(160);
    expect(thought.endsWith('…')).toBe(true);
    expect(currentThought('- `ls` the **folder** first.\n')).toBe('ls the folder first.');
  });
});
