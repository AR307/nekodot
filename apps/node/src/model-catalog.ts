import { z } from 'zod';
import { reasoningLevelSchema, type ModelCatalogEntry } from '@nekodot/protocol';
import type { NodeDatabase } from './database';

const modelSchema = z.looseObject({
  id: z.string(),
  name: z.string(),
  canonical_model_id: z.string().optional(),
  provider: z.looseObject({ npm: z.string().optional(), api: z.string().optional() }).optional(),
  reasoning_options: z
    .array(
      z.looseObject({
        type: z.string(),
        values: z.array(z.string()).optional(),
        min: z.number().optional(),
        max: z.number().optional(),
      }),
    )
    .optional(),
  temperature: z.boolean().optional(),
  tool_call: z.boolean().optional(),
  structured_output: z.boolean().optional(),
  limit: z
    .looseObject({ context: z.number().optional(), output: z.number().optional() })
    .optional(),
  modalities: z.looseObject({ input: z.array(z.string()), output: z.array(z.string()) }).optional(),
});
const catalogSchema = z.record(
  z.string(),
  z.looseObject({
    id: z.string(),
    npm: z.string().optional(),
    api: z.string().optional(),
    models: z.record(z.string(), modelSchema),
  }),
);
type Catalog = z.infer<typeof catalogSchema>;
interface SavedCatalog {
  fetchedAt: string;
  data: Catalog;
}

/** Public metadata only; the user's authenticated provider remains the model inventory. */
export class ModelCatalog {
  private pending?: Promise<SavedCatalog>;
  constructor(private readonly database: NodeDatabase) {}
  async load(refresh = false): Promise<SavedCatalog> {
    const saved = this.database.setting<SavedCatalog>('models-dev');
    if (!refresh && saved && Date.now() - Date.parse(saved.fetchedAt) < 4 * 3600_000) return saved;
    this.pending ??= (async () => {
      const response = await fetch('https://models.dev/api.json', {
        signal: AbortSignal.timeout(20_000),
      });
      if (!response.ok) throw new Error('models.dev HTTP ' + response.status);
      const entry = {
        fetchedAt: new Date().toISOString(),
        data: catalogSchema.parse(await response.json()),
      };
      this.database.setSetting('models-dev', entry);
      return entry;
    })().finally(() => {
      this.pending = undefined;
    });
    return this.pending;
  }
  async describe(
    provider: string,
    model: string,
    baseUrl?: string,
    refresh = false,
  ): Promise<ModelCatalogEntry> {
    const { data, fetchedAt } = await this.load(refresh);
    const catalogProvider =
      ({ 'openai-codex': 'openai', 'claude-code': 'anthropic' } as Record<string, string>)[
        provider
      ] ?? provider;
    // Prefer the actual provider or endpoint, then an explicit canonical ID. Never substring-match model families.
    const endpoint = baseUrl
      ? Object.values(data).find(
          (p) =>
            p.api && URL.canParse(p.api) && new URL(p.api).hostname === new URL(baseUrl).hostname,
        )
      : undefined;
    let owner = data[catalogProvider] ?? endpoint;
    let entry = owner?.models[model];
    if (!entry && model.includes('/')) {
      const slash = model.indexOf('/');
      const named = data[model.slice(0, slash)];
      if (named?.models[model.slice(slash + 1)]) {
        owner = named;
        entry = named.models[model.slice(slash + 1)];
      }
    }
    if (!entry) {
      const matches = Object.values(data).flatMap((p) =>
        Object.values(p.models)
          .filter((m) => m.id === model || m.canonical_model_id === model)
          .map((m) => ({ p, m })),
      );
      const canonical = matches.filter(({ p, m }) => m.canonical_model_id === p.id + '/' + m.id);
      const picked =
        canonical.length === 1 ? canonical[0] : matches.length === 1 ? matches[0] : undefined;
      if (picked) {
        owner = picked.p;
        entry = picked.m;
      }
    }
    const options = entry?.reasoning_options ?? [];
    const levels = [
      ...new Set(options.filter((o) => o.type === 'effort').flatMap((o) => o.values ?? [])),
    ].filter(
      (value): value is z.infer<typeof reasoningLevelSchema> =>
        reasoningLevelSchema.safeParse(value).success,
    );
    const parameters = [
      ...(entry?.temperature ? ['temperature'] : []),
      ...(entry?.tool_call ? ['tools'] : []),
      ...(entry?.structured_output ? ['structured_output'] : []),
      ...options.map((o) => (o.type === 'effort' ? 'reasoning_effort' : o.type)),
    ];
    return {
      model,
      name: entry?.name ?? model,
      catalogProvider: entry ? owner!.id : null,
      catalogUpdatedAt: fetchedAt,
      sdk: entry?.provider?.npm ?? (entry ? (owner?.npm ?? null) : null),
      api: entry?.provider?.api ?? (entry ? (owner?.api ?? null) : null),
      parameters,
      reasoningLevels: levels,
      reasoningOptions: options as ModelCatalogEntry['reasoningOptions'],
      context: entry?.limit?.context ?? null,
      output: entry?.limit?.output ?? null,
      inputModalities: entry?.modalities?.input ?? [],
      outputModalities: entry?.modalities?.output ?? [],
    };
  }
}
