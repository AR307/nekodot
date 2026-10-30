import { useEffect, useId, useState } from 'react';
import { callNode } from '../relay-connection';
import { useAppStore } from '../store';
import type { Texts } from '../shared';
import { SpinnerDots } from '../ui';

export function useModelOptions(online: boolean, sourceId: string) {
  const nodeId = useAppStore((state) => state.selectedNodeId);
  const [result, setResult] = useState<{ key: string; models: string[]; error: string }>();
  const [revision, setRevision] = useState(0);
  const key = `${nodeId}:${sourceId}:${online}:${revision}`;
  useEffect(() => {
    let active = true;
    if (online && sourceId)
      void callNode('models.options', { sourceId, refresh: revision > 0 })
        .then((result) => {
          if (!active) return;
          setResult({ key, models: result.models, error: result.warning ?? '' });
        })
        .catch((reason: unknown) => {
          if (active)
            setResult({
              key,
              models: [],
              error: reason instanceof Error ? reason.message : String(reason),
            });
        });
    return () => {
      active = false;
    };
  }, [online, sourceId, nodeId, revision, key]);
  const reload = () => setRevision((value) => value + 1);
  const current = result?.key === key ? result : undefined;
  return {
    models: current?.models ?? [],
    loading: online && Boolean(sourceId) && !current,
    error: current?.error ?? '',
    reload,
  };
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
          onClick={() => catalog.reload()}
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
