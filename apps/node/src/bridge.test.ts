import { it, expect } from 'vitest';
import { execFile } from 'node:child_process';
import { mkdtemp } from 'node:fs/promises';
import { createServer } from 'node:net';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { promisify } from 'node:util';
import { bridgeEndpoint, isNamedPipe, pythonBridgeCall } from './bridge';
import { windowsControlPipe } from './hermes/gateway';
import { deliveryReferences } from './files';

const run = promisify(execFile);
const python = process.platform === 'win32' ? 'python' : 'python3';

it('answers the Hermes plugin Python client over this platform bridge', async () => {
  const home = await mkdtemp(join(tmpdir(), 'nekodot-bridge-'));
  const path = bridgeEndpoint(home);
  expect(isNamedPipe(path)).toBe(process.platform === 'win32');
  const server = createServer((socket) => {
    let input = '';
    socket.on('data', (chunk) => {
      input += chunk.toString();
      if (input.endsWith('\n'))
        socket.end(JSON.stringify({ ok: true, result: JSON.parse(input) }) + '\n');
    });
  });
  await new Promise<void>((resolve) => server.listen(path, resolve));
  try {
    const script = `import json\nimport socket\n${pythonBridgeCall}\nimport sys\nprint(json.dumps(_bridge_call(sys.argv[1], {"action": "list", "botId": "nk-测试"}, 10)))\n`;
    const { stdout } = await run(python, ['-I', '-c', script, path]);
    expect(JSON.parse(stdout)).toEqual({ ok: true, result: { action: 'list', botId: 'nk-测试' } });
  } finally {
    await new Promise<void>((resolve) => server.close(() => resolve()));
  }
});

it.runIf(process.platform === 'win32')(
  'names the gateway control pipe exactly as Hermes normcase does',
  async () => {
    const home = 'D:/数据目录/Nekodot/accounts/u_1/Hermes';
    const { stdout } = await run(python, [
      '-I',
      '-c',
      'import hashlib, os, sys; print(hashlib.sha256(os.path.normcase(sys.argv[1]).encode("utf-8")).hexdigest()[:16])',
      home,
    ]);
    expect(windowsControlPipe(home)).toBe('\\\\.\\pipe\\hermes-gateway-' + stdout.trim());
  },
);

it('collects Windows drive and file URL deliveries', () => {
  const references = deliveryReferences(
    '[报告](C:\\Users\\me\\报告.md)\n[data](file:///C:/Users/me/data%20set.csv)',
  );
  expect(references[0]).toBe('C:\\Users\\me\\报告.md');
  expect(references[1]).toBe(
    process.platform === 'win32' ? 'C:\\Users\\me\\data set.csv' : '/C:/Users/me/data set.csv',
  );
});
