import { useEffect, useState } from 'react';
import type { RpcResult } from '@nekodot/protocol';
import { callNode } from '../relay-connection';
import type { Texts } from '../shared';

export function ModelInformation({ botId, t }: { botId: string; t: Texts }) {
  const [info, setInfo] = useState<RpcResult<'models.info'>>();
  const [error, setError] = useState('');
  const [revision, setRevision] = useState(0);
  useEffect(() => {
    let active = true;
    void callNode('models.info', { botId })
      .then((value) => {
        if (active) {
          setInfo(value);
          setError('');
        }
      })
      .catch((e: Error) => {
        if (active) setError(e.message);
      });
    return () => {
      active = false;
    };
  }, [botId, revision]);
  return (
    <section className="detail-section">
      <div className="section-heading">
        <h3>{t.modelInformation}</h3>
        <button className="quiet-button" onClick={() => setRevision((v) => v + 1)}>
          {t.refresh}
        </button>
      </div>
      {error && <p className="form-error">{error}</p>}
      {info && (
        <>
          <p>
            {info.provider} · {info.model}
          </p>
          <dl className="model-limits">
            <dt>{t.detectedContext}</dt>
            <dd>{info.detectedContext ?? t.unknownValue}</dd>
            <dt>{t.contextOverride}</dt>
            <dd>{info.configuredContext ?? t.nativeAuto}</dd>
            <dt>{t.effectiveContext}</dt>
            <dd>{info.effectiveContext ?? t.unknownValue}</dd>
            <dt>{t.maxOutput}</dt>
            <dd>{info.detectedMaxOutput ?? t.unknownValue}</dd>
            <dt>{t.nativeCompression}</dt>
            <dd>{info.compression.enabled ? t.enabled : t.disabled}</dd>
            <dt>{t.compressionThreshold}</dt>
            <dd>
              {info.compression.threshold != null
                ? info.compression.threshold * 100 + '%'
                : t.unknownValue}
              {info.compression.thresholdTokens
                ? ' / ' + info.compression.thresholdTokens + ' tokens'
                : ''}
            </dd>
            <dt>{t.effectiveCompressionThreshold}</dt>
            <dd>{info.compression.effectiveThresholdTokens ?? t.unknownValue} tokens</dd>
            <dt>{t.compressionCount}</dt>
            <dd>{info.compression.count ?? t.unknownValue}</dd>
          </dl>
          <p className="muted">{t.modelInfoHint}</p>
          <p className="muted">{t.compressionHistoryHint}</p>
          {info.compression.records.length > 0 && (
            <details>
              <summary>{t.compressionRecords}</summary>
              <pre>{JSON.stringify(info.compression.records, null, 2)}</pre>
            </details>
          )}
        </>
      )}
    </section>
  );
}
