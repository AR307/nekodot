import { expect, it } from 'vitest';
import { botFields } from '@nekodot/protocol';
import { handleFromName } from './bot-handle';

it('previews a distinct, valid handle for Chinese and mixed names instead of a shared default', () => {
  expect(handleFromName('小核')).toBe('小核');
  expect(handleFromName('小核')).not.toBe(handleFromName('小研'));
  expect(handleFromName('  Research Bot! ')).toBe('research-bot');
  expect(handleFromName('数据 Lab 2')).toBe('数据-lab-2');
  expect(handleFromName('!!!')).toBe('bot');
  expect([...handleFromName('很长的名字'.repeat(10))]).toHaveLength(24);
  for (const name of ['小核', 'Research Bot', '数据 Lab 2', '!!!'])
    expect(botFields.handle.safeParse(handleFromName(name)).success).toBe(true);
});
