import {
  hermesControlResponseSchema,
  hermesRunCreatedSchema,
  hermesRunStateSchema,
  type HermesRunState,
} from '@nekodot/protocol';
import { readSse } from './sse';
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
      signal: init?.signal ?? AbortSignal.timeout(180_000),
    });
    if (!response.ok)
      throw new Error('Hermes HTTP ' + response.status + ': ' + (await response.text()));
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
  async approve(runId: string, requestId: string, generation: number, choice: 'once' | 'deny') {
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
  async *events(runId: string) {
    yield* readSse(await this.request('/v1/runs/' + encodeURIComponent(runId) + '/events'));
  }
}
