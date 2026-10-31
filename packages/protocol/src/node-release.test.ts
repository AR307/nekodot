import { expect, it } from 'vitest';
import { randomUUID } from 'node:crypto';
import { helloSchema, envelopeSchema, payloadSchemas, nodeReleaseSchema } from './index';

it('offers a timestamped release while keeping legacy and development hello valid', () => {
  for (const version of ['1.0.0', 'development', '20261031000100'])
    expect(helloSchema.safeParse({ nodeToken: 'test', version }).success).toBe(true);
  expect(
    envelopeSchema.parse({
      v: 1,
      id: randomUUID(),
      type: 'node.update',
      payload: { version: '20261031000100' },
    }).type,
  ).toBe('node.update');
  expect(payloadSchemas['node.update'].safeParse({ version: '1.0.0' }).success).toBe(false);
  expect(
    nodeReleaseSchema.safeParse({
      version: '20261031000100',
      sha256: 'ab'.repeat(32),
      signature: 'test',
    }).success,
  ).toBe(true);
  expect(
    nodeReleaseSchema.safeParse({ version: '20261031000100', sha256: 'bad', signature: 'test' })
      .success,
  ).toBe(false);
});
