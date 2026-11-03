import { expect, it } from 'vitest';
import { mentionedBots } from './group-routing';

it('expands @everyone in place, once per member, without matching unrelated handles', () => {
  const roster = [
    { botId: 'a', handle: 'researcher' },
    { botId: 'b', handle: 'writer' },
    { botId: 'c', handle: 'reviewer' },
  ];
  expect(mentionedBots('@writer @everyone @writer @everyone @outsider', roster)).toEqual([
    'b',
    'a',
    'c',
  ]);
  expect(mentionedBots('mail@everyone.test @everyone-else', roster)).toEqual([]);
});

it('routes name-derived Chinese handles in the same order as English handles', () => {
  const roster = [
    { botId: 'a', handle: '小鱼' },
    { botId: 'b', handle: '小鱼-2' },
    { botId: 'c', handle: 'researcher' },
  ];
  expect(mentionedBots('@小鱼-2， @researcher 再请 @小鱼， @小鱼-2', roster)).toEqual([
    'b',
    'c',
    'a',
  ]);
});
