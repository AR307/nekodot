import { useCallback, useEffect, useId, useState } from 'react';
import { callNode } from '../relay-connection';
import type { Texts } from '../shared';
import { SpinnerDots } from '../ui';

export function useModelOptions(online: boolean) {
  const [models, setModels] = useState<string[]>([]);
  const [loading, setLoading] = useState(online);
  const [error, setError] = useState('');
  const load = useCallback(
    (refresh = false) =>
      callNode('models.options', { refresh })
        .then((result) => {
          setModels(result.models);
          setError(result.warning ?? '');
        })
        .catch((reason: unknown) => {
          setError(reason instanceof Error ? reason.message : String(reason));
        })
        .finally(() => setLoading(false)),
    [],
  );
  const reload = useCallback(
    async (refresh = false) => {
      if (!online) return;
      setLoading(true);
      setError('');
      await load(refresh);
    },
    [online, load],
  );
  useEffect(() => {
    if (online) void load();
  }, [online, load]);
  return { models, loading, error, reload };
}

export function ModelPicker({
  t,
  label = t.model,
  value,
  onChange,
  catalog,
  disabled = false,
  required = false,
}: {
  t: Texts;
  label?: string;
  value: string;
  onChange(value: string): void;
  catalog: ReturnType<typeof useModelOptions>;
  disabled?: boolean;
  required?: boolean;
}) {
  const id = useId();
  return (
    <div className="model-picker">
      <div className="model-picker-heading">
        <label htmlFor={id}>{label}</label>
        <button
          type="button"
          className="text-button"
          disabled={disabled || catalog.loading}
          onClick={() => void catalog.reload(true)}
        >
          {catalog.loading ? (
            <>
              <SpinnerDots />
              {t.loadingModels}
            </>
          ) : (
            t.fetchModels
          )}
        </button>
      </div>
      {catalog.models.length > 0 && (
        <select
          aria-label={t.availableModels}
          value={catalog.models.includes(value) ? value : ''}
          onChange={(event) => onChange(event.target.value)}
        >
          <option value="" disabled>
            {t.chooseModel}
          </option>
          {catalog.models.map((model) => (
            <option key={model} value={model}>
              {model}
            </option>
          ))}
        </select>
      )}
      <input
        id={id}
        required={required}
        value={value}
        onChange={(event) => onChange(event.target.value)}
        placeholder={t.modelPlaceholder}
        autoComplete="off"
      />
      <small className="muted" role="status">
        {catalog.models.length
          ? t.modelsLoaded.replace('{count}', String(catalog.models.length))
          : catalog.loading
            ? t.loadingModels
            : t.noModel}
      </small>
      {catalog.error && (
        <small className="form-error" role="alert">
          {catalog.error}
        </small>
      )}
    </div>
  );
}
