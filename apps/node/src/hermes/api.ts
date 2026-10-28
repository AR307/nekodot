import {
  hermesControlResponseSchema,
  hermesRunCreatedSchema,
  hermesRunStateSchema,
  hermesSteerResponseSchema,
  hermesModelOptionsSchema,
  type HermesRunState,
  type RpcError,
  type ApprovalChoice,
} from '@nekodot/protocol';
import { readSse } from './sse';
import { NodeFault } from '../fault';
export class HermesApi {
  constructor(
    readonly baseUrl: string,
    private readonly apiKey: string,
  ) {}
  private async request(path: string, init?: RequestInit): Promise<Response> {
    const response = await fetch(this.baseUrl + path, {
      ...init,
      headers: {
        'Content-Type': 'application/json',
        Authorization: 'Bearer ' + this.apiKey,
        ...init?.headers,
      },
      ...(!path.endsWith('/events') ? { signal: init?.signal ?? AbortSignal.timeout(30_000) } : {}),
    });
    if (!response.ok) {
      const codes: Record<number, RpcError['code']> = {
        400: 'invalid_params',
        401: 'unauthorized',
        403: 'forbidden',
        404: 'not_found',
        409: 'conflict',
      };
      throw new NodeFault(
        codes[response.status] ?? 'unavailable',
        'Hermes HTTP ' + response.status + '. Check the run or provider and try again.',
      );
    }
    return response;
  }
  async createRun(input: string, sessionId: string, messageId: string, instructions?: string) {
    const body = {
      input,
      session_id: sessionId,
      ...(instructions ? { instructions } : {}),
    };
    const response = await this.request('/v1/runs', {
      method: 'POST',
      headers: { 'Idempotency-Key': messageId },
      body: JSON.stringify(body),
    });
    return hermesRunCreatedSchema.parse(await response.json());
  }
  async state(runId: string): Promise<HermesRunState> {
    return hermesRunStateSchema.parse(
      await (await this.request('/v1/runs/' + encodeURIComponent(runId))).json(),
    );
  }
  async approve(runId: string, requestId: string, generation: number, choice: ApprovalChoice) {
    const body = {
      request_id: requestId,
      execution_generation: generation,
      choice,
    };
    const response = await this.request('/v1/runs/' + encodeURIComponent(runId) + '/approval', {
      method: 'POST',
      body: JSON.stringify(body),
    });
    return hermesControlResponseSchema.parse(await response.json());
  }
  async stop(runId: string) {
    const response = await this.request('/v1/runs/' + encodeURIComponent(runId) + '/stop', {
      method: 'POST',
      body: '{}',
    });
    return hermesControlResponseSchema.parse(await response.json());
  }
  async steer(runId: string, input: string) {
    const response = await this.request('/v1/runs/' + encodeURIComponent(runId) + '/steer', {
      method: 'POST',
      body: JSON.stringify({ input }),
    });
    return hermesSteerResponseSchema.parse(await response.json());
  }
  async health() {
    return (
      await this.request('/health', { signal: AbortSignal.timeout(3000) })
    ).json() as Promise<unknown>;
  }
  async models(refresh = false) {
    const payload = hermesModelOptionsSchema.parse(
      await (
        await this.request('/api/model/options?include_unconfigured=false&refresh=' + refresh)
      ).json(),
    );
    const current = payload.providers.find(
      (row) => row.is_current || row.slug === payload.provider,
    );
    return {
      models: [...new Set(current?.models ?? [])],
      ...(current?.warning ? { warning: current.warning } : {}),
    };
  }
  async *events(runId: string, lastSeq = -1, signal?: AbortSignal) {
    yield* readSse(
      await this.request('/v1/runs/' + encodeURIComponent(runId) + '/events', {
        signal: signal ?? new AbortController().signal,
        headers: lastSeq >= 0 ? { 'Last-Event-ID': String(lastSeq) } : {},
      }),
    );
  }
}
