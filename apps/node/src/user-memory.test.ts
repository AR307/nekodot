import { expect, it } from 'vitest';
import { USER_MEMORY_SEPARATOR } from '@nekodot/protocol';
import { userMemoryEnvironment } from '../../../tests/support/user-memory-environment';

it('two computers confirm originals, merge native user entries, show conflicts and recover without sharing another account or task memory', async () => {
  const environment = await userMemoryEnvironment();
  const [a, b, other] = environment.nodes;
  try {
    await a!.app.userMemory.sync();
    await b!.app.userMemory.sync();
    await a!.app.userMemory.sync();
    const initial = a!.app.userMemory.view().shared!;
    expect(initial.initialized).toBe(false);
    expect(initial.imports.map((item) => item.content)).toEqual([
      'Prefers concise answers.',
      'Uses metric units.',
    ]);
    expect(await a!.read()).toBe('Prefers concise answers.');
    expect(await b!.read()).toBe('Uses metric units.');
    const taskMemory = await b!.read('MEMORY.md');
    const soul = await b!.runtime.management.request(
      '/api/profiles/' + b!.bot.botId + '/soul',
      b!.bot.botId,
    );
    const original = initial.imports.map((item) => item.content).join(USER_MEMORY_SEPARATOR);
    await a!.app.userMemory.save({
      revision: initial.revision,
      content: original,
      reviewedImports: initial.imports.map((item) => item.id),
      reviewedConflicts: [],
    });
    await b!.app.userMemory.sync();
    expect(await a!.read()).toBe(original);
    expect(await b!.read()).toBe(original);
    expect(await other!.read()).toBe('OTHER_ACCOUNT_ONLY');

    await b!.disconnect();
    await a!.write(original + USER_MEMORY_SEPARATOR + 'Likes mint tea.');
    await a!.app.userMemory.sync();
    await b!.write('Prefers concise answers.' + USER_MEMORY_SEPARATOR + 'Uses kilometres.');
    b!.reconnect();
    await expect
      .poll(async () => {
        await b!.app.userMemory.sync();
        return b!.read();
      })
      .toBe(
        'Prefers concise answers.' +
          USER_MEMORY_SEPARATOR +
          'Uses kilometres.' +
          USER_MEMORY_SEPARATOR +
          'Likes mint tea.',
      );
    await a!.app.userMemory.sync();
    const merged = await a!.read();
    expect(merged).toContain('Uses kilometres.');
    expect(a!.app.userMemory.view().shared!.conflicts).toHaveLength(0);

    await b!.disconnect();
    await a!.write(merged.replace('Likes mint tea.', 'Likes jasmine tea.'));
    await a!.app.userMemory.sync();
    await b!.write(merged.replace('Likes mint tea.', 'Likes black tea.'));
    b!.reconnect();
    await expect
      .poll(async () => {
        await b!.app.userMemory.sync();
        return b!.app.userMemory.view().shared!.conflicts.length;
      })
      .toBe(1);
    const conflict = b!.app.userMemory.view().shared!.conflicts[0]!;
    expect(conflict).toMatchObject({
      base: 'Likes mint tea.',
      current: 'Likes jasmine tea.',
      incoming: 'Likes black tea.',
      resolved: false,
    });
    expect(await b!.read()).toContain('Likes jasmine tea.');
    const state = b!.app.userMemory.view().shared!;
    await b!.app.userMemory.save({
      revision: state.revision,
      content: state.content.replace('Likes jasmine tea.', 'Likes jasmine tea and black tea.'),
      reviewedImports: [],
      reviewedConflicts: [conflict.id],
    });
    await expect(
      b!.app.userMemory.save({
        revision: state.revision,
        content: 'STALE_EDIT',
        reviewedImports: [],
        reviewedConflicts: [],
      }),
    ).rejects.toThrow('changed on another computer');
    await a!.restart();
    await expect
      .poll(async () => {
        await a!.app.userMemory.sync();
        return a!.read();
      })
      .toContain('Likes jasmine tea and black tea.');
    expect(a!.app.userMemory.view().shared!.imports).toHaveLength(2);
    expect(a!.app.userMemory.view().shared!.imports.every((item) => item.reviewed)).toBe(true);
    expect(a!.app.userMemory.view().shared!.conflicts[0]!.resolved).toBe(true);
    expect(await b!.read('MEMORY.md')).toBe(taskMemory);
    expect(
      await b!.runtime.management.request('/api/profiles/' + b!.bot.botId + '/soul', b!.bot.botId),
    ).toEqual(soul);
    await other!.app.userMemory.sync();
    expect(JSON.stringify(other!.app.userMemory.view().shared)).not.toContain('tea');
    expect(JSON.stringify(a!.app.userMemory.view().shared)).not.toContain('OTHER_ACCOUNT_ONLY');
  } finally {
    await environment.close();
  }
});
