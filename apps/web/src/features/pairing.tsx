import { useEffect, useRef, useState } from 'react';
import { AnimatePresence, motion, useReducedMotion } from 'motion/react';
import { fetchMe, relayRequest } from '../api';
import { useAppStore } from '../store';
import { BotAvatar, Icon, SpinnerDots, StatusDot, ease } from '../ui';
import { avatarColors, fill, type Texts } from '../shared';

const pairingTtlSeconds = 600;

export function PairScreen({
  t,
  onBack,
  onLanguage,
}: {
  t: Texts;
  onBack(): void;
  onLanguage(): void;
}) {
  const pairing = useAppStore((state) => state.pairing);
  const setPairing = useAppStore((state) => state.setPairing);
  const me = useAppStore((state) => state.me);
  const setMe = useAppStore((state) => state.setMe);
  const setSelectedNode = useAppStore((state) => state.setSelectedNode);
  const setScreen = useAppStore((state) => state.setScreen);
  const [busy, setBusy] = useState(false);
  const [copied, setCopied] = useState(false);
  const [error, setError] = useState('');
  const requestedPairing = useRef(false);
  const existingNodes = useRef(new Set(me?.nodes.map((node) => node.nodeId) ?? []));
  const [connectedNode, setConnectedNode] = useState<string | null>(null);
  const reduceMotion = useReducedMotion();
  const [secondsLeft, setSecondsLeft] = useState(0);
  const [pairTarget, setPairTarget] = useState<'local' | 'cloud'>('cloud');
  const shellQuote = (value: string) => `'${value.replaceAll("'", "'\"'\"'")}'`;
  const localInstallCommand = pairing
    ? import.meta.env.VITE_NEKODOT_RELAY_SSH &&
      import.meta.env.VITE_NEKODOT_RELAY_SSH_IDENTITY &&
      import.meta.env.VITE_NEKODOT_RELAY_SSH_KNOWN_HOSTS
      ? `/mnt/c/Windows/System32/OpenSSH/ssh.exe -o BatchMode=yes -o StrictHostKeyChecking=yes ${import.meta.env.VITE_NEKODOT_RELAY_SSH} 'curl -fsSL http://127.0.0.1:4329/install.sh' | bash -s -- --pair ${pairing.code} --relay http://127.0.0.1:4329 --relay-ssh ${import.meta.env.VITE_NEKODOT_RELAY_SSH} --relay-ssh-key ${shellQuote(import.meta.env.VITE_NEKODOT_RELAY_SSH_IDENTITY)} --relay-ssh-known-hosts ${shellQuote(import.meta.env.VITE_NEKODOT_RELAY_SSH_KNOWN_HOSTS)}`
      : t.localInstallUnavailable
    : null;
  const installCommand = pairTarget === 'local' ? localInstallCommand : pairing?.installCommand;
  const commandReady = Boolean(installCommand) && installCommand !== t.localInstallUnavailable;
  const connected = me?.nodes.find((node) => node.nodeId === connectedNode);
  const expired = Boolean(pairing) && secondsLeft === 0;

  async function generate() {
    setBusy(true);
    setError('');
    try {
      const result = await relayRequest<{
        code: string;
        expiresAt: string;
        installCommand: string;
      }>('/pairing-codes', { method: 'POST', body: '{}' });
      setPairing(result);
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : t.saveError);
    } finally {
      setBusy(false);
    }
  }

  useEffect(() => {
    if (!pairing && !requestedPairing.current) {
      requestedPairing.current = true;
      void relayRequest<{ code: string; expiresAt: string; installCommand: string }>(
        '/pairing-codes',
        { method: 'POST', body: '{}' },
      )
        .then(setPairing)
        .catch((reason: unknown) =>
          setError(reason instanceof Error ? reason.message : t.saveError),
        );
    }
  }, [pairing, setPairing, t.saveError]);
  useEffect(() => {
    if (!pairing) return;
    const tick = () =>
      setSecondsLeft(Math.max(0, Math.floor((Date.parse(pairing.expiresAt) - Date.now()) / 1000)));
    const firstTick = window.setTimeout(tick, 0);
    const interval = window.setInterval(tick, 1000);
    return () => {
      window.clearTimeout(firstTick);
      window.clearInterval(interval);
    };
  }, [pairing]);
  useEffect(() => {
    if (!pairing) return;
    const poll = window.setInterval(() => {
      void fetchMe()
        .then((value) => {
          setMe(value);
          value.nodes.forEach((node) =>
            useAppStore.getState().setNodeOnline(node.nodeId, node.online),
          );
          const fresh = value.nodes.find(
            (node) => node.online && !existingNodes.current.has(node.nodeId),
          );
          if (fresh) {
            setSelectedNode(fresh.nodeId);
            setConnectedNode(fresh.nodeId);
          }
        })
        .catch(() => {});
    }, 2000);
    return () => window.clearInterval(poll);
  }, [pairing, setMe, setScreen, setSelectedNode]);
  useEffect(() => {
    if (!connectedNode) return;
    const timer = window.setTimeout(
      () => {
        setPairing(null);
        setScreen('home');
      },
      reduceMotion ? 120 : 1400,
    );
    return () => window.clearTimeout(timer);
  }, [connectedNode, reduceMotion, setPairing, setScreen]);

  const clock = `${Math.floor(secondsLeft / 60)}:${String(secondsLeft % 60).padStart(2, '0')}`;
  const highlighted =
    installCommand && pairing && commandReady
      ? installCommand
          .split(pairing.code)
          .flatMap((part, index) =>
            index ? [<mark key={index}>{pairing.code}</mark>, part] : [part],
          )
      : (installCommand ?? t.preparingCommand);
  const steps = [pairTarget === 'cloud' ? t.pairStepCloud : t.localTargetHelp, t.pairStepPaste];

  return (
    <main className="pair-page" aria-busy={busy}>
      <header className="page-top">
        <button className="icon-button" onClick={onBack} aria-label={t.home}>
          <Icon name="back" />
        </button>
        <span className="step-label">
          <span className="step-bars" aria-hidden="true">
            <i className="done" />
            <i className="done" />
            <i />
          </span>
          {t.stepOf}
        </span>
        <button className="quiet-button language-button" onClick={onLanguage}>
          <Icon name="globe" />
          {t.language}
        </button>
      </header>
      <motion.section
        className="pair-content"
        initial={reduceMotion ? false : { opacity: 0, y: 10 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ duration: 0.32, ease }}
      >
        <div className="pair-heading">
          <h1>{t.addComputer}</h1>
          <p className="muted">{t.pairLead}</p>
        </div>
        <div className="pair-choices" role="group" aria-label={t.addComputer}>
          {(
            [
              ['local', 'laptop', t.localComputer, t.localShort],
              ['cloud', 'server', t.cloudComputer, t.cloudShort],
            ] as const
          ).map(([target, icon, title, help]) => (
            <button
              key={target}
              type="button"
              className={`choice-card${pairTarget === target ? ' active' : ''}`}
              aria-pressed={pairTarget === target}
              onClick={() => {
                setCopied(false);
                setPairTarget(target);
              }}
            >
              {pairTarget === target && (
                <motion.span
                  className="choice-ring"
                  layoutId="pair-choice"
                  transition={
                    reduceMotion ? { duration: 0 } : { type: 'spring', stiffness: 520, damping: 40 }
                  }
                />
              )}
              <Icon name={icon} />
              <strong>{title}</strong>
              <small>{help}</small>
            </button>
          ))}
        </div>
        <ol className="pair-steps">
          {steps.map((step, index) => (
            <li key={index}>
              <span>{index + 1}</span>
              {step}
            </li>
          ))}
        </ol>
        <div className="command-box">
          <code>{highlighted}</code>
          <button
            className="copy-button"
            disabled={!commandReady}
            onClick={() => {
              if (installCommand && commandReady)
                void navigator.clipboard.writeText(installCommand).then(() => setCopied(true));
            }}
          >
            <Icon name={copied ? 'check' : 'copy'} />
            {copied ? t.copied : t.copyCommand}
          </button>
        </div>
        <AnimatePresence mode="wait" initial={false}>
          {connectedNode ? (
            <motion.div
              key="success"
              className="pair-success"
              role="status"
              initial={{ opacity: 0, scale: 0.96 }}
              animate={{ opacity: 1, scale: 1 }}
              transition={{ duration: 0.2, ease }}
            >
              <span className="pair-burst">
                <motion.span
                  initial={{ scale: reduceMotion ? 1 : 0.6 }}
                  animate={{ scale: reduceMotion ? 1 : [0.6, 1.08, 1] }}
                  transition={{ duration: 0.6, ease: [0.34, 1.4, 0.64, 1] }}
                >
                  <BotAvatar color={avatarColors[1]!} size={56} />
                </motion.span>
                {!reduceMotion &&
                  avatarColors.map((color, index) => {
                    const angle = (index * Math.PI) / 4;
                    return (
                      <motion.i
                        key={color}
                        style={{ background: color }}
                        initial={{ x: 0, y: 0, opacity: 1 }}
                        animate={{ x: Math.cos(angle) * 46, y: Math.sin(angle) * 46, opacity: 0 }}
                        transition={{ duration: 0.6, ease }}
                      />
                    );
                  })}
              </span>
              <div>
                <strong>{t.pairSuccess}</strong>
                <small>{fill(t.pairWelcome, { name: connected?.name ?? '' })}</small>
              </div>
            </motion.div>
          ) : (
            <motion.div
              key="wait"
              className={`pair-wait${expired ? ' is-expired' : ''}`}
              exit={{ opacity: 0, scale: 0.98 }}
              transition={{ duration: 0.16 }}
            >
              {expired ? <Icon name="warning" /> : <SpinnerDots />}
              <div>
                <strong>{expired ? t.codeExpired : t.waiting}</strong>
                <small>
                  {pairing
                    ? fill(t.expiresIn, { code: pairing.code, time: clock })
                    : t.preparingCommand}
                </small>
              </div>
              {pairing && (
                <span className="pair-countdown" aria-hidden="true">
                  <svg viewBox="0 0 36 36">
                    <circle cx="18" cy="18" r="15" />
                    <circle
                      cx="18"
                      cy="18"
                      r="15"
                      style={{
                        strokeDashoffset: 94.25 * (1 - secondsLeft / pairingTtlSeconds),
                      }}
                    />
                  </svg>
                </span>
              )}
              {expired && (
                <button
                  className="secondary-button"
                  disabled={busy}
                  onClick={() => {
                    setPairing(null);
                    void generate();
                  }}
                >
                  {t.refreshCode}
                </button>
              )}
            </motion.div>
          )}
        </AnimatePresence>
        {me?.nodes.length ? (
          <section className="paired-nodes" aria-label={t.nodesTitle}>
            <h2>{t.nodesTitle}</h2>
            {me.nodes.map((node) => (
              <div className="paired-node" key={node.nodeId}>
                <StatusDot state={node.online ? 'ok' : 'offline'} />
                <span>{node.name}</span>
                <small>{node.online ? t.connected : t.offline}</small>
              </div>
            ))}
          </section>
        ) : null}
        {error && (
          <p className="form-error" role="alert">
            {error}
          </p>
        )}
      </motion.section>
    </main>
  );
}
