import { expect, it } from 'vitest';
import { ModelCatalog } from './model-catalog';
import type { NodeDatabase } from './database';

const data = {
  templated: { id: 'templated', api: 'https://{account}.example.com/v1', models: {} },
  openai: {
    id: 'openai',
    npm: '@ai-sdk/openai',
    models: {
      'gpt-6.1-sol': {
        id: 'gpt-6.1-sol',
        name: 'GPT-6.1 Sol',
        canonical_model_id: 'openai/gpt-6.1-sol',
        reasoning_options: [{ type: 'effort', values: ['low', 'medium', 'high', 'xhigh', 'max'] }],
        temperature: false,
        tool_call: true,
        limit: { context: 1050000 },
      },
    },
  },
  relay: {
    id: 'relay',
    models: {
      'gpt-6.1-sol': {
        id: 'gpt-6.1-sol',
        name: 'GPT-6.1 Sol',
        canonical_model_id: 'openai/gpt-6.1-sol',
      },
    },
  },
};
const catalog = () =>
  new ModelCatalog({
    setting: () => ({ fetchedAt: new Date().toISOString(), data }),
  } as unknown as NodeDatabase);
it('custom source resolves exact canonical metadata despite mirrored IDs and endpoint templates', async () => {
  const entry = await catalog().describe(
    'custom-test',
    'gpt-6.1-sol',
    'https://private.example.test/v1',
  );
  expect(entry.catalogProvider).toBe('openai');
  expect(entry.reasoningLevels).toEqual(['low', 'medium', 'high', 'xhigh', 'max']);
  expect(entry.parameters).toEqual(['tools', 'reasoning_effort']);
  expect(entry.context).toBe(1050000);
});
it('unknown model names do not inherit capabilities from a similar family', async () => {
  const entry = await catalog().describe('custom-test', 'gpt-6.1-sol-latest');
  expect(entry.catalogProvider).toBeNull();
  expect(entry.reasoningLevels).toEqual([]);
});
