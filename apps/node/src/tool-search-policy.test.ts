import { expect, it } from 'vitest';
import { toolSearchMode } from './tool-search-policy';

it('uses deferred tools only for a known small-context local model', () => {
  expect(toolSearchMode('http://localhost:11434/v1', 8192)).toBe('on');
  expect(toolSearchMode('http://192.168.1.5:1234/v1', 32768)).toBe('on');
  expect(toolSearchMode('http://[::1]:11434/v1', 16384)).toBe('on');
  expect(toolSearchMode('http://ollama:11434/v1', 8192)).toBe('on');
  expect(toolSearchMode('http://localhost:11434/v1', 131072)).toBe('off');
  expect(toolSearchMode('https://models.example.com/v1', 8192)).toBe('off');
  expect(toolSearchMode('http://localhost:11434/v1', 0)).toBe('off');
  expect(toolSearchMode('http://localhost:11434/v1', Number.NaN)).toBe('off');
  expect(toolSearchMode(undefined, 8192)).toBe('off');
});
