import type { IncomingMessage, Server, ServerResponse } from 'node:http';
import { readFile } from 'node:fs/promises';
import { join } from 'node:path';
import { WebSocketServer } from 'ws';
import { createHash, randomBytes } from 'node:crypto';

/** Native response recording, used only by offline product journey tests. */
export async function managementReplay(fixturesDirectory: string, apiKey: string) {
  const fixture = JSON.parse(
    await readFile(join(fixturesDirectory, 'management-native.json'), 'utf8'),
  ) as {
    documents: { name: string; content: string; exists: boolean }[];
    skills: Record<string, unknown>[];
    official: unknown;
    plugins: { plugins: Record<string, unknown>[] };
    catalog: unknown;
    jobs: unknown[];
    pending: string;
  };
  const documents = new Map<string, typeof fixture.documents>();
  const displayFixture = JSON.parse(
    await readFile(join(fixturesDirectory, 'display-native.json'), 'utf8'),
  ) as {
    records: { result: Record<string, unknown> & { lease: Record<string, unknown> } }[];
  };
  const displays = new Map<string, Record<string, unknown> & { lease: Record<string, unknown> }>();
  function display(profile: string) {
    let state = displays.get(profile);
    if (!state) {
      state = structuredClone(displayFixture.records[1]!.result);
      state.profile_key = '/isolated/hermes/profiles/' + profile;
      state.profile = profile;
      displays.set(profile, state);
    }
    return state;
  }
  const profiles = new Map<
    string,
    { skills: Record<string, unknown>[]; plugins: Record<string, unknown>[] }
  >();
  function data(profile: string) {
    let state = profiles.get(profile);
    if (!state) {
      state = {
        skills: structuredClone(fixture.skills),
        plugins: structuredClone(fixture.plugins.plugins),
      };
      profiles.set(profile, state);
    }
    return state;
  }
  const json = (response: ServerResponse, value: unknown) => {
    response.writeHead(200, { 'Content-Type': 'application/json' });
    response.end(JSON.stringify(value));
  };
  async function route(request: IncomingMessage, response: ServerResponse): Promise<boolean> {
    const url = new URL(request.url ?? '/', 'http://127.0.0.1');
    if (!url.pathname.startsWith('/api/')) return false;
    if (request.headers['x-hermes-session-token'] !== apiKey) return false;
    const profile = url.searchParams.get('profile') ?? 'default';
    if (!documents.has(profile)) documents.set(profile, structuredClone(fixture.documents));
    const docs = documents.get(profile)!;
    let body: Record<string, unknown> = {};
    if (request.method === 'PUT' || request.method === 'POST') {
      const chunks = [];
      for await (const chunk of request) chunks.push(Buffer.from(chunk));
      body = JSON.parse(Buffer.concat(chunks).toString());
    }
    if (url.pathname.endsWith('/soul')) {
      const doc = docs.find((row) => row.name === 'SOUL.md')!;
      if (request.method === 'PUT') doc.content = String(body.content);
      json(response, { content: doc.content, exists: true });
    } else if (url.pathname === '/api/cron/jobs') json(response, fixture.jobs);
    else if (url.pathname === '/api/skills') json(response, data(profile).skills);
    else if (url.pathname === '/api/skills/hub/official') json(response, fixture.official);
    else if (url.pathname === '/api/skills/toggle') {
      const row = data(profile).skills.find((row) => row.name === body.name);
      if (row) row.enabled = body.enabled;
      json(response, { ok: true });
    } else if (url.pathname === '/api/skills/content')
      json(response, {
        name: url.searchParams.get('name'),
        path: '/isolated/profile/skills/' + url.searchParams.get('name') + '/SKILL.md',
        content:
          '---\nname: ' +
          url.searchParams.get('name') +
          '\n---\n' +
          String(
            data(profile).skills.find((row) => row.name === url.searchParams.get('name'))
              ?.description ?? '',
          ),
      });
    else if (url.pathname === '/api/fs/read-text') {
      const name = url.searchParams.get('path')?.split(/[\\/]/).at(-1);
      const doc = docs.find((row) => row.name === name);
      json(response, { text: doc?.content ?? '' });
    } else if (url.pathname === '/api/fs/write-text') {
      const name = String(body.path).split(/[\\/]/).at(-1);
      const doc = docs.find((row) => row.name === name);
      if (doc) doc.content = String(body.content);
      json(response, { ok: true });
    } else if (url.pathname === '/api/profiles') json(response, []);
    else json(response, {});
    return true;
  }
  function attach(server: Server) {
    const wss = new WebSocketServer({ noServer: true });
    server.on('upgrade', (request, socket, head) => {
      const url = new URL(request.url ?? '/', 'http://127.0.0.1');
      if (url.pathname !== '/api/ws' || url.searchParams.get('token') !== apiKey) {
        socket.destroy();
        return;
      }
      wss.handleUpgrade(request, socket, head, (ws) => wss.emit('connection', ws));
    });
    wss.on('connection', (socket) =>
      socket.on('message', (raw) => {
        const req = JSON.parse(raw.toString()) as {
          id: string;
          method: string;
          params: Record<string, unknown>;
        };
        let result: unknown = {};
        if (req.method.startsWith('display.')) {
          const state = display(String(req.params.profile));
          if (req.method === 'display.start') state.running = true;
          if (req.method === 'display.stop') state.running = false;
          result = structuredClone(state);
          if (req.method === 'display.observe')
            result = {
              ...structuredClone(state),
              ticket: randomBytes(16).toString('hex'),
              viewer_id: req.params.viewer_id ?? randomBytes(16).toString('hex'),
              path: '/api/display/ws',
            };
          if (req.method === 'display.lease.acquire' || req.method === 'display.lease.release') {
            const human = req.method.endsWith('acquire');
            state.lease = {
              ...state.lease,
              holder: human ? 'human' : 'agent',
              viewer_hash: human
                ? createHash('sha256')
                    .update(String(req.params.viewer_id))
                    .digest('hex')
                    .slice(0, 12)
                : null,
              epoch: Number(state.lease.epoch) + 1,
            };
            result = { lease: structuredClone(state.lease) };
            for (const client of wss.clients)
              client.send(
                JSON.stringify({
                  method: 'event',
                  params: {
                    type: 'display.lease',
                    payload: { profile_key: state.profile_key, lease: state.lease },
                  },
                }),
              );
          }
        }
        if (req.method === 'session.resume') result = { session_id: 'recorded-session' };
        if (req.method === 'slash.exec') result = { output: fixture.pending };
        if (req.method === 'plugins.manage') {
          const state = data(String(req.params.profile));
          if (req.params.action === 'list') result = { plugins: state.plugins };
          else {
            const plugin = state.plugins.find(
              (row) => row.key === req.params.key || row.name === req.params.key,
            );
            if (plugin && req.params.action === 'toggle')
              plugin.status = req.params.enable ? 'enabled' : 'disabled';
            result = { ok: true, restart_required: false };
          }
        }
        socket.send(JSON.stringify({ jsonrpc: '2.0', id: req.id, result }));
      }),
    );
    return () => {
      for (const socket of wss.clients) socket.terminate();
      wss.close();
    };
  }
  return { route, attach, catalog: fixture.catalog };
}
