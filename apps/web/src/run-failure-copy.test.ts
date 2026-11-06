import { expect, it } from 'vitest';
import { failureCodes } from '@nekodot/protocol';
import zh from './i18n/zh';
import en from './i18n/en';

it('localizes every known run-start failure code in both languages', () => {
  for (const code of failureCodes) {
    expect(zh.runFailure[code]).toMatch(/\p{Script=Han}/u);
    expect(en.runFailure[code]).toMatch(/^[\x20-\x7E]+$/);
  }
  expect(Object.keys(zh.runFailure).sort()).toEqual([...failureCodes].sort());
  expect(Object.keys(en.runFailure).sort()).toEqual([...failureCodes].sort());
});
