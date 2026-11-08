import { createServer } from 'node:http';
import type { AddressInfo } from 'node:net';
import type { ProviderSource } from '@nekodot/protocol';
import { expect, it } from 'vitest';
import { customModels } from './provider-models';

it('pulls each selected source protocol with its own authentication and catalog pagination', async () => {
  const requests: { path: string; authorization?: string; key?: string; version?: string }[] = [];
  const server = createServer((request, response) => {
    const url = new URL(request.url!, 'http://localhost');
    requests.push({
      path: url.pathname + url.search,
      authorization: request.headers.authorization,
      key: (request.headers['x-api-key'] ?? request.headers['x-goog-api-key']) as string,
      version: request.headers['anthropic-version'] as string,
    });
    response.setHeader('content-type', 'application/json');
    if (url.pathname.includes('gemini')) {
      response.end(
        JSON.stringify(
          url.searchParams.has('pageToken')
            ? {
                models: [
                  { name: 'models/gemini-second', supportedGenerationMethods: ['generateContent'] },
                ],
              }
            : {
                models: [
                  {
                    name: 'models/gemini-first',
                    supportedGenerationMethods: ['generateContent', 'countTokens'],
                  },
                  { name: 'models/embedding', supportedGenerationMethods: ['embedContent'] },
                ],
                nextPageToken: 'page2',
              },
        ),
      );
    } else if (url.pathname.includes('messages')) {
      response.end(
        JSON.stringify(
          url.searchParams.has('after_id')
            ? { data: [{ id: 'claude-second' }], has_more: false }
            : { data: [{ id: 'claude-first' }], has_more: true, last_id: 'claude-first' },
        ),
      );
    } else response.end(JSON.stringify({ data: [{ id: 'gpt-model' }, { id: 'grok-model' }] }));
  });
  await new Promise<void>((resolve) => server.listen(0, '127.0.0.1', resolve));
  const base = 'http://127.0.0.1:' + (server.address() as AddressInfo).port;
  try {
    for (const mode of [
      'chat_completions',
      'codex_responses',
      'anthropic_messages',
      'gemini_generate_content',
    ] as const) {
      const path =
        mode === 'gemini_generate_content'
          ? '/gemini'
          : mode === 'anthropic_messages'
            ? '/messages/v1'
            : '/v1';
      const models = await customModels(
        {
          sourceId: 'custom:test',
          kind: 'custom',
          name: 'Test',
          provider: 'test',
          ready: true,
          baseUrl: base + path,
          apiMode: mode,
        },
        'test-only',
      );
      expect(models).toEqual(
        mode === 'gemini_generate_content'
          ? ['gemini-first', 'gemini-second']
          : mode === 'anthropic_messages'
            ? ['claude-first', 'claude-second']
            : ['gpt-model', 'grok-model'],
      );
    }
    expect(requests).toEqual([
      { path: '/v1/models', authorization: 'Bearer test-only' },
      { path: '/v1/models', authorization: 'Bearer test-only' },
      { path: '/messages/v1/models', key: 'test-only', version: '2023-06-01' },
      {
        path: '/messages/v1/models?after_id=claude-first',
        key: 'test-only',
        version: '2023-06-01',
      },
      { path: '/gemini/v1beta/models', key: 'test-only' },
      { path: '/gemini/v1beta/models?pageToken=page2', key: 'test-only' },
    ]);
  } finally {
    await new Promise<void>((resolve) => server.close(() => resolve()));
  }
});

it('does not silently switch protocol on a mismatched catalog or expose an error response', async () => {
  let body = JSON.stringify({ models: [] });
  let status = 200;
  const server = createServer((_request, response) => {
    response.writeHead(status);
    response.end(body);
  });
  await new Promise<void>((resolve) => server.listen(0, '127.0.0.1', resolve));
  const source: ProviderSource = {
    sourceId: 'custom:test',
    kind: 'custom',
    name: 'Test',
    provider: 'test',
    ready: true,
    baseUrl: 'http://127.0.0.1:' + (server.address() as AddressInfo).port,
    apiMode: 'chat_completions',
  };
  try {
    await expect(customModels(source, 'test-only')).rejects.toThrow('Catalog unavailable');
    body = '<html>upstream private error</html>';
    await expect(customModels(source, 'test-only')).rejects.toThrow('Catalog unavailable');
    status = 401;
    await expect(customModels(source, 'test-only')).rejects.toThrow('Catalog unavailable');
  } finally {
    await new Promise<void>((resolve) => server.close(() => resolve()));
  }
});
