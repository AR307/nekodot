import { useEffect, useState } from 'react';
import type { Operation } from '@nekodot/protocol';
import { callNode } from '../relay-connection';
import { SpinnerDots } from '../ui';
import type { Texts } from '../shared';

export function OperationProgress({
  initial,
  t,
  onFinished,
}: {
  initial: Operation;
  t: Texts;
  onFinished?(operation: Operation): void;
}) {
  const [operation, setOperation] = useState(initial);
  const [error, setError] = useState('');
  useEffect(() => {
    if (initial.status !== 'running') return;
    let stopped = false;
    const timer = window.setInterval(() => {
      void callNode('operations.get', { operationId: initial.operationId })
        .then((value) => {
          if (stopped) return;
          setOperation(value);
          setError('');
          if (value.status !== 'running') {
            window.clearInterval(timer);
            onFinished?.(value);
          }
        })
        .catch((reason: unknown) => {
          if (!stopped) setError(reason instanceof Error ? reason.message : t.offline);
        });
    }, 1500);
    return () => {
      stopped = true;
      window.clearInterval(timer);
    };
  }, [initial.operationId, initial.status, onFinished, t.offline]);
  return (
    <section className={`operation-card operation-${operation.status}`} role="status">
      <strong>
        {operation.status === 'running' ? (
          <>
            <SpinnerDots /> {t.operationRunning}
          </>
        ) : operation.status === 'done' ? (
          t.completed
        ) : operation.status === 'interrupted' ? (
          t.interrupted
        ) : (
          t.failed
        )}
      </strong>
      <p>{operation.detail}</p>
      {operation.results.map((result) => (
        <p key={result.botId}>
          {result.ok ? '✓' : '!'} {result.botId} · {result.detail}
        </p>
      ))}
      {operation.results
        .filter((result) => result.native)
        .map((result) => (
          <details key={result.botId + '-native'}>
            <summary>{result.botId} · Hermes</summary>
            <pre className="native-output">{JSON.stringify(result.native, null, 2)}</pre>
          </details>
        ))}
      {error && <p className="form-error">{error}</p>}
    </section>
  );
}
