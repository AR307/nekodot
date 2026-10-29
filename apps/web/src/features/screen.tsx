import { useCallback, useEffect, useRef, useState } from 'react';
import type RFB from '@novnc/novnc';
import type { Bot, Operation, ScreenStatus, TunnelTicket } from '@nekodot/protocol';
import { relayRequest } from '../api';
import { callNode } from '../relay-connection';
import { selectNodeData, useAppStore } from '../store';
import { BotAvatar, Icon, SpinnerDots, useMediaQuery } from '../ui';
import type { Texts } from '../shared';
import { OperationProgress } from './operations';

export function ScreenPanel({
  bot,
  members,
  t,
  onSelect,
  onClose,
}: {
  bot: Bot;
  members: Bot[];
  t: Texts;
  onSelect(botId: string): void;
  onClose(): void;
}) {
  const nodeId = useAppStore((state) => state.selectedNodeId)!;
  const fullScreen = useMediaQuery('(max-width: 1279px)');
  const node = useAppStore(selectNodeData);
  const status = node.screens[bot.botId];
  const [error, setError] = useState('');
  const [operation, setOperation] = useState<Operation>();
  const refresh = useCallback(async () => {
    try {
      const status = await callNode('screen.status', { botId: bot.botId });
      useAppStore.getState().applyLive(nodeId, { kind: 'screen', status });
      setError('');
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : t.failed);
    }
  }, [bot.botId, nodeId, t.failed]);
  useEffect(() => {
    if (!node.online) return;
    void Promise.resolve().then(refresh);
    void callNode('operations.list', {})
      .then(({ operations }) => {
        setOperation(
          operations.find(
            (op) =>
              op.kind.startsWith('screen.') &&
              op.botIds.includes(bot.botId) &&
              op.status === 'running',
          ),
        );
      })
      .catch((reason: Error) => setError(reason.message));
    const timer = window.setInterval(() => {
      void refresh();
    }, 10_000);
    const onVisible = () => {
      if (document.visibilityState === 'visible') void refresh();
    };
    document.addEventListener('visibilitychange', onVisible);
    return () => {
      window.clearInterval(timer);
      document.removeEventListener('visibilitychange', onVisible);
    };
  }, [node.online, bot.botId, refresh]);
  async function action(kind: 'screen.start' | 'screen.stop') {
    setError('');
    try {
      setOperation(await callNode(kind, { botId: bot.botId }));
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : t.failed);
    }
  }
  return (
    <aside
      className="screen-panel"
      aria-label={t.screenTitle}
      role={fullScreen ? 'dialog' : undefined}
      aria-modal={fullScreen ? true : undefined}
      onKeyDown={(event) => {
        if ((event.target as HTMLElement).tagName === 'CANVAS') return;
        if (event.key === 'Escape') onClose();
        if (fullScreen && event.key === 'Tab') {
          const elements = [
            ...event.currentTarget.querySelectorAll<HTMLElement>(
              'button:not(:disabled),select:not(:disabled),textarea:not(:disabled),summary',
            ),
          ].filter((element) => element.offsetParent !== null);
          const target = event.shiftKey ? elements.at(-1) : elements[0];
          if (document.activeElement === (event.shiftKey ? elements[0] : elements.at(-1))) {
            event.preventDefault();
            target?.focus();
          }
        }
      }}
    >
      <header className="screen-header">
        <BotAvatar color={bot.avatar.color} size={32} />
        <div>
          <strong>{bot.displayName}</strong>
          <small>{t.screenTitle}</small>
        </div>
        <button
          className="icon-button"
          autoFocus
          onClick={onClose}
          aria-label={t.close}
          title={t.screenCloseHint}
        >
          <Icon name="close" />
        </button>
      </header>
      {members.length > 1 && (
        <label className="screen-member-select">
          <span>{t.screenSelectBot}</span>
          <select value={bot.botId} onChange={(event) => onSelect(event.target.value)}>
            {members.map((member) => (
              <option key={member.botId} value={member.botId}>
                {member.displayName}
              </option>
            ))}
          </select>
        </label>
      )}
      <div className="screen-body">
        {!node.online && <p className="offline-strip">{t.offline}</p>}
        {!window.isSecureContext ? (
          <p className="screen-empty">{t.screenSecure}</p>
        ) : !status ? (
          <div className="screen-empty">
            <SpinnerDots />
          </div>
        ) : !status.available ? (
          <p className="screen-empty">{t.screenUnsupported}</p>
        ) : !status.installed ? (
          <section className="screen-empty">
            <Icon name="monitor" />
            <h3>{t.screenNotInstalled}</h3>
            <p>{t.screenInstallHint}</p>
            {status.missing.length > 0 && <p>{status.missing.join(', ')}</p>}
            {status.installCommand && <pre>{status.installCommand}</pre>}
          </section>
        ) : !status.running ? (
          <section className="screen-empty">
            <Icon name="monitor" />
            <h3>{t.screenStopped}</h3>
            <p>{status.geometry}</p>
            <button
              className="primary-button"
              disabled={!node.online || operation?.status === 'running'}
              onClick={() => void action('screen.start')}
            >
              {t.screenStart}
            </button>
          </section>
        ) : (
          <ScreenViewer
            key={bot.botId}
            bot={bot}
            nodeId={nodeId}
            online={node.online}
            status={status}
            t={t}
          />
        )}
        {status?.blocker && status.available && <p className="form-error">{status.blocker}</p>}
        {error && (
          <p className="form-error" role="alert">
            {error}
          </p>
        )}
        {operation && (
          <OperationProgress
            key={operation.operationId}
            initial={operation}
            t={t}
            onFinished={(operation) => {
              setOperation(operation);
              void refresh();
            }}
          />
        )}
      </div>
      <footer className="screen-footer">
        <small>{t.screenCloseHint}</small>
        {status?.running && (
          <button
            className="quiet-button"
            disabled={!node.online || operation?.status === 'running'}
            onClick={() => void action('screen.stop')}
          >
            {t.screenStop}
          </button>
        )}
      </footer>
    </aside>
  );
}

function ScreenViewer({
  bot,
  nodeId,
  online,
  status,
  t,
}: {
  bot: Bot;
  nodeId: string;
  online: boolean;
  status: ScreenStatus;
  t: Texts;
}) {
  const viewport = useRef<HTMLDivElement>(null);
  const rfb = useRef<RFB | null>(null);
  const socket = useRef<WebSocket | null>(null);
  const [sessionId, setSessionId] = useState<string>();
  const [connected, setConnected] = useState(false);
  const [error, setError] = useState('');
  const [text, setText] = useState('');
  const [fit, setFit] = useState(true);
  const [busy, setBusy] = useState(false);
  const own =
    connected && online && status.holder === 'human' && status.controllerSessionId === sessionId;
  useEffect(() => {
    if (rfb.current) {
      rfb.current.viewOnly = !own;
      rfb.current.scaleViewport = fit;
    }
  }, [own, fit, connected]);
  useEffect(() => {
    let disposed = false;
    let identity: string | undefined;
    let timer: number | undefined;
    let attempts = 0;
    let connecting = false;
    async function connect() {
      if (disposed || !navigator.onLine || connecting) return;
      connecting = true;
      try {
        // Load first: noVNC attaches handlers synchronously when given a fresh WebSocket.
        const { default: RFB } = await import('@novnc/novnc');
        if (disposed) return;
        const ticket = await relayRequest<TunnelTicket>('/tunnels', {
          method: 'POST',
          body: JSON.stringify({
            nodeId,
            botId: bot.botId,
            kind: 'vnc',
            ...(identity ? { sessionId: identity } : {}),
          }),
        });
        if (disposed) return;
        identity = ticket.sessionId;
        setSessionId(identity);
        const ws = new WebSocket(
          `${location.protocol === 'https:' ? 'wss:' : 'ws:'}//${location.host}/ws/tunnel?ticket=${encodeURIComponent(ticket.ticket)}`,
        );
        socket.current = ws;
        const viewer = new RFB(viewport.current!, ws);
        rfb.current = viewer;
        viewer.viewOnly = true;
        viewer.scaleViewport = true;
        viewer.resizeSession = false;
        viewer.addEventListener('connect', () => {
          if (disposed) return;
          attempts = 0;
          setConnected(true);
          setError('');
          void callNode('screen.status', { botId: bot.botId })
            .then((status) => {
              useAppStore.getState().applyLive(nodeId, { kind: 'screen', status });
            })
            .catch((reason: Error) => setError(reason.message));
        });
        ws.addEventListener('close', () => {
          viewer.viewOnly = true;
          if (disposed || socket.current !== ws) return;
          setConnected(false);
          schedule();
        });
        viewer.addEventListener('securityfailure', () => setError(t.screenAuthentication));
      } catch (reason) {
        if (disposed) return;
        // A restarted Relay has no viewer mapping. A fresh identity only watches; it never takes control.
        if (reason && typeof reason === 'object' && 'status' in reason && reason.status === 409)
          identity = undefined;
        setError(reason instanceof Error ? reason.message : String(reason));
        schedule();
      } finally {
        connecting = false;
      }
    }
    function schedule() {
      if (disposed || timer !== undefined) return;
      timer = window.setTimeout(
        () => {
          timer = undefined;
          rfb.current?.disconnect();
          void connect();
        },
        Math.min(30_000, 1000 * 2 ** attempts++),
      );
    }
    const onOffline = () => {
      if (rfb.current) rfb.current.viewOnly = true;
      setConnected(false);
      socket.current?.close(4002, 'Browser offline');
    };
    const onOnline = () => {
      window.clearTimeout(timer);
      timer = undefined;
      rfb.current?.disconnect();
      void connect();
    };
    window.addEventListener('offline', onOffline);
    window.addEventListener('online', onOnline);
    void connect();
    return () => {
      disposed = true;
      window.clearTimeout(timer);
      window.removeEventListener('offline', onOffline);
      window.removeEventListener('online', onOnline);
      // Explicit close is intentional. Broken transports remain abnormal all the way to Hermes.
      socket.current?.close(1000, 'Viewer closed');
      rfb.current?.disconnect();
      rfb.current = null;
    };
  }, [bot.botId, nodeId, t.screenAuthentication]);
  async function control(action: 'take' | 'release' | 'force-release') {
    setBusy(true);
    setError('');
    try {
      const status = await callNode('screen.control', { botId: bot.botId, sessionId, action });
      useAppStore.getState().applyLive(nodeId, { kind: 'screen', status });
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : t.failed);
    } finally {
      setBusy(false);
    }
  }
  function sendText(paste: boolean) {
    if (!own || !rfb.current || !text) return;
    if (paste) {
      rfb.current.clipboardPasteFrom(text);
      rfb.current.sendKey(0xffe3, 'ControlLeft', true);
      rfb.current.sendKey(0x76, 'KeyV');
      rfb.current.sendKey(0xffe3, 'ControlLeft', false);
    } else {
      for (const char of text) {
        const point = char.codePointAt(0)!;
        rfb.current.sendKey(point === 10 ? 0xff0d : point <= 255 ? point : 0x01000000 | point);
      }
    }
    setText('');
  }
  return (
    <>
      <div className={`screen-control-bar${own ? ' has-control' : ''}`}>
        <span role="status">
          {!connected || !online
            ? t.screenConnecting
            : own
              ? t.screenYou
              : status.holder === 'human'
                ? t.screenOther
                : t.screenAgent}
        </span>
        {!own && <small>{t.screenWatching}</small>}
        {own ? (
          <button
            className="secondary-button"
            disabled={busy}
            onClick={() => void control('release')}
          >
            {t.screenRelease}
          </button>
        ) : (
          <button
            className="primary-button"
            disabled={!connected || !online || busy}
            onClick={() => void control('take')}
          >
            {t.screenTake}
          </button>
        )}
        {status.holder === 'human' && !own && (
          <button
            className="text-button"
            disabled={!online || busy}
            onClick={() => void control('force-release')}
          >
            {t.screenForceRelease}
          </button>
        )}
      </div>
      <div
        className={`screen-viewport${own ? ' has-control' : ''}`}
        ref={viewport}
        aria-label={bot.displayName + ' · ' + t.screenTitle}
      />
      {!connected && (
        <p className="screen-notice" role="status">
          {t.screenDisconnected}
        </p>
      )}
      <div className="screen-toolbar">
        <button
          className="quiet-button"
          onClick={() => socket.current?.close(4002, 'Reconnect viewer')}
        >
          {t.screenReconnect}
        </button>
        <select
          aria-label={t.screenZoom}
          value={fit ? 'fit' : 'actual'}
          onChange={(e) => setFit(e.target.value === 'fit')}
        >
          <option value="fit">{t.screenFit}</option>
          <option value="actual">{t.screenActual}</option>
        </select>
      </div>
      <p className="screen-notice">{own ? t.screenReturnHint : t.screenTakeHint}</p>
      <details className="screen-keyboard" open={own}>
        <summary>{t.screenKeyboard}</summary>
        <textarea
          aria-label={t.screenKeyboard}
          placeholder={t.screenInputHint}
          value={text}
          disabled={!own}
          onChange={(e) => setText(e.target.value)}
          rows={2}
        />
        <div className="screen-key-actions">
          <button
            className="secondary-button"
            disabled={!own || !text}
            onClick={() => sendText(false)}
          >
            {t.screenType}
          </button>
          <button
            className="secondary-button"
            disabled={!own || !text}
            onClick={() => sendText(true)}
          >
            {t.screenPaste}
          </button>
          {(
            [
              ['Enter', 0xff0d],
              ['Tab', 0xff09],
              ['Esc', 0xff1b],
              ['⌫', 0xff08],
              ['←', 0xff51],
              ['↑', 0xff52],
              ['→', 0xff53],
              ['↓', 0xff54],
            ] as const
          ).map(([name, key]) => (
            <button
              className="quiet-button"
              key={name}
              disabled={!own}
              onClick={() => rfb.current?.sendKey(key)}
            >
              {name}
            </button>
          ))}
        </div>
      </details>
      {error && (
        <p className="form-error" role="alert">
          {error}
        </p>
      )}
    </>
  );
}
