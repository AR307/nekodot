import { randomUUID } from 'node:crypto';
import { readFile } from 'node:fs/promises';
import { dirname, join } from 'node:path';
import { HermesApi } from '../../../apps/node/src/hermes/api';
import { HermesManagement } from '../../../apps/node/src/hermes/management';
import type { HermesGateway, GatewayFrame } from '../../../apps/node/src/hermes/gateway';
import type { HermesRuntime } from '../../../apps/node/src/hermes/runtime';
import type { HermesInput } from '@nekodot/protocol';

interface RecordedSession {
  profile: string;
  sessionId: string;
  storedSessionId: string;
  replayEpoch: string;
  sequence: number;
  events: GatewayFrame[];
  admissionIds: string[];
}

function frameFromRecordedEvent(
  session: RecordedSession,
  event: Record<string, unknown>,
): GatewayFrame {
  const type = String(event.event);
  const payload: Record<string, unknown> = {};
  for (const [key, value] of Object.entries(event))
    if (!['event', 'run_id', 'timestamp', 'seq'].includes(key)) payload[key] = value;
  if (typeof payload.delta === 'string') {
    payload.text = payload.delta;
    delete payload.delta;
  }
  const frameType =
    type === 'tool.started'
      ? 'tool.start'
      : type === 'tool.completed'
        ? 'tool.complete'
        : type === 'run.completed' ||
            type === 'run.failed' ||
            type === 'run.interrupted' ||
            type === 'run.cancelled'
          ? 'message.complete'
          : type;
  if (frameType === 'tool.start' || frameType === 'tool.complete') {
    payload.name = payload.tool;
    payload.tool_id = payload.tool_call_id;
    delete payload.tool;
    delete payload.tool_call_id;
    if (typeof payload.preview === 'string') payload.summary = payload.preview;
  }
  if (frameType === 'message.complete') {
    payload.text = payload.output;
    payload.status =
      type === 'run.failed'
        ? 'error'
        : type === 'run.interrupted' || type === 'run.cancelled'
          ? 'interrupted'
          : 'complete';
    delete payload.output;
  }
  const seq = ++session.sequence;
  return {
    type: frameType,
    session_id: session.sessionId,
    seq,
    replay_epoch: session.replayEpoch,
    payload,
  };
}

/** Test injection only; product code exercises the canonical gateway methods. */
export function recordedManagementRuntime(
  url: string,
  key: string,
  home: string,
  catalog: unknown,
): Pick<
  HermesRuntime,
  'management' | 'profileHome' | 'cli' | 'restart' | 'configureScreen' | 'environment' | 'gateway'
> {
  const management = new HermesManagement(url, key);
  const sessions = new Map<string, RecordedSession>();
  const sessionsById = new Map<string, RecordedSession>();
  const gateways = new Map<string, HermesGateway>();
  const apis = new Map<string, HermesApi>();
  const api = (profile: string) => {
    let value = apis.get(profile);
    if (!value) {
      value = new HermesApi(url + '/p/' + profile, key);
      apis.set(profile, value);
    }
    return value;
  };
  const sessionFor = (id: string) => sessions.get(id) ?? sessionsById.get(id);
  const makeSnapshot = async (session: RecordedSession) => {
    const runId = session.admissionIds.at(-1);
    const state = runId ? await apiForSession(session).state(runId) : undefined;
    const prompts = (state?.pending_controls ?? []).map((prompt) => ({
      kind: prompt.kind,
      prompt_id: prompt.prompt_id,
      execution_generation: prompt.execution_generation,
      choices: prompt.choices,
      command: prompt.command,
      description: prompt.description,
      question: prompt.question,
      multi_select: prompt.multi_select,
    }));
    return {
      session_id: session.sessionId,
      stored_session_id: session.storedSessionId,
      replay_epoch: session.replayEpoch,
      last_sequence: session.sequence,
      running: ['running', 'queued', 'pending', 'waiting_for_approval'].includes(
        state?.status ?? '',
      ),
      execution_generation: state?.execution_generation ?? 0,
      prompts,
      messages: [],
    };
  };
  const apiForSession = (session: RecordedSession) => api(session.profile);
  const gateway = (profile: string) => {
    const existingGateway = gateways.get(profile);
    if (existingGateway) return existingGateway;
    const rpc = async <T>(method: string, params: Record<string, unknown>): Promise<T> => {
      if (method === 'commands.catalog')
        return (await management.rpc('commands.catalog', { profile })) as T;
      if (method === 'session.create') {
        const requestId = String(params.request_id ?? randomUUID());
        const sessionProfile = String(params.profile ?? profile);
        let session = sessions.get(requestId);
        if (!session) {
          session = {
            profile: sessionProfile,
            sessionId: 'runtime-' + randomUUID(),
            storedSessionId: 'stored-' + randomUUID(),
            replayEpoch: randomUUID(),
            sequence: 0,
            events: [],
            admissionIds: [],
          };
          sessions.set(requestId, session);
          sessionsById.set(session.sessionId, session);
          sessionsById.set(session.storedSessionId, session);
        }
        return (await makeSnapshot(session)) as T;
      }
      if (method === 'session.resume') {
        const session = sessionFor(String(params.session_id));
        if (!session) throw new Error('not_found');
        return (await makeSnapshot(session)) as T;
      }
      const session = sessionFor(String(params.session_id));
      if (!session) throw new Error('not_found');
      if (method === 'slash.exec' || method === 'command.dispatch') {
        const command =
          method === 'slash.exec'
            ? String(params.command ?? '')
            : '/' + String(params.name ?? '') + (params.arg ? ' ' + String(params.arg) : '');
        return (await management.rpc('slash.exec', {
          profile: session.profile || profile,
          session_id: session.sessionId,
          command,
        })) as T;
      }
      const runId = String(params.admission_id ?? session.admissionIds.at(-1) ?? '');
      const hermes = api(session.profile || profile);
      if (method === 'prompt.submit') {
        const submissionId = String(params.submission_id ?? randomUUID());
        const attachments = Array.isArray(params.attachments)
          ? (params.attachments as { path: string; mime: string }[])
          : [];
        const sessionProfile = session.profile || profile;
        const imageCache = join(
          sessionProfile === 'default' ? home : join(home, 'profiles', sessionProfile),
          'cache',
          'images',
        );
        if (attachments.some(({ path }) => dirname(path) !== imageCache))
          throw new Error('Hermes gateway images must use the profile image cache');
        const input: HermesInput = attachments.length
          ? [
              {
                role: 'user',
                content: [
                  { type: 'text', text: String(params.text ?? '') },
                  ...(await Promise.all(
                    attachments.map(async ({ path, mime }) => ({
                      type: 'image_url' as const,
                      image_url: {
                        url: `data:${mime};base64,${(await readFile(path)).toString('base64')}`,
                      },
                    })),
                  )),
                ],
              },
            ]
          : String(params.text ?? '');
        const created = await hermes.createRun(input, session.sessionId, submissionId);
        session.admissionIds.push(created.run_id);
        void (async () => {
          for await (const item of hermes.events(created.run_id)) {
            const native = frameFromRecordedEvent(
              session,
              item.data as unknown as Record<string, unknown>,
            );
            session.events.push(native);
          }
        })();
        return {
          admission_id: created.run_id,
          status: 'started',
          outcome: null,
          execution_generation: 1,
        } as T;
      }
      if (method === 'session.events.since') {
        const after = Number(params.last_sequence ?? 0);
        return {
          events: session.events.filter((event) => (event.seq ?? 0) > after),
          replay_epoch: session.replayEpoch,
          latest_seq: session.sequence,
          snapshot_required: false,
          truncated: false,
        } as T;
      }
      if (method === 'prompt.receipt') {
        const state = await hermes.state(runId);
        const status =
          state.status === 'unknown'
            ? 'unknown'
            : ['queued', 'pending'].includes(state.status)
              ? 'queued'
              : ['running', 'waiting_for_approval', 'stopping'].includes(state.status)
                ? 'started'
                : 'terminal';
        return {
          admission_id: runId,
          status,
          outcome:
            state.status === 'completed'
              ? 'completed'
              : state.status === 'failed'
                ? 'failed'
                : state.status === 'cancelled'
                  ? 'cancelled'
                  : null,
          execution_generation: state.execution_generation,
          ...(params.include_result === true
            ? { result: { final_response: state.output, failed: state.status === 'failed' } }
            : {}),
        } as T;
      }
      if (method === 'session.steer')
        return {
          ...(await hermes.steer(runId, String(params.text ?? ''))),
          execution_generation: Number(params.execution_generation ?? 1),
          status: 'queued',
        } as T;
      if (method === 'session.interrupt' || method === 'prompt.cancel')
        return (await hermes.stop(runId)) as T;
      if (method === 'prompt.resolve_unknown')
        return (await hermes.resolveUnknown(
          runId,
          runId,
          Number(params.execution_generation ?? 1),
        )) as T;
      if (method === 'approval.respond')
        return (await hermes.approve(
          runId,
          String(params.prompt_id),
          Number(params.execution_generation),
          String(params.choice) as never,
        )) as T;
      if (method === 'clarify.respond')
        return (await hermes.clarify(
          runId,
          String(params.prompt_id),
          Number(params.execution_generation),
          String(params.answer),
        )) as T;
      throw new Error('Unsupported fake Hermes gateway method: ' + method);
    };
    const value = {
      get generation() {
        return 1;
      },
      listeners: new Set(),
      rpc,
      close: () => {},
    } as unknown as HermesGateway;
    gateways.set(profile, value);
    return value;
  };
  return {
    management,
    environment: (profile) => management.request('/api/test/environment', profile),
    profileHome: (profile) => join(home, 'profiles', profile),
    cli: async () => JSON.stringify(catalog),
    restart: async () => {},
    configureScreen: async () => {},
    gateway,
  };
}
