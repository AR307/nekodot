import { useEffect, useRef, useState } from 'react';
import { motion, useReducedMotion } from 'motion/react';
import { fetchMe, relayRequest } from '../api';
import { useAppStore } from '../store';
import { BotAvatar, Icon, SpinnerDots, Wordmark } from '../ui';
import { avatarColors, type Texts } from '../shared';

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
          const connected = value.nodes.find(
            (node) => node.online && !existingNodes.current.has(node.nodeId),
          );
          if (connected) {
            setSelectedNode(connected.nodeId);
            setConnectedNode(connected.nodeId);
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
      reduceMotion ? 120 : 650,
    );
    return () => window.clearTimeout(timer);
  }, [connectedNode, reduceMotion, setPairing, setScreen]);

  return (
    <main className="pair-page" aria-busy={busy}>
      <header className="page-top">
        <button className="icon-button" onClick={onBack} aria-label={t.home}>
          <Icon name="chevron" />
        </button>
        <Wordmark />
        <span className="step-label">{t.stepOf}</span>
        <button
          className="quiet-button language-button"
          onClick={onLanguage}
          aria-label={t.language}
        >
          {t.language}
        </button>
      </header>
      <section className="pair-content">
        <span className="eyebrow">
          <i /> 02 / 03 · {t.addComputer.toUpperCase()}
        </span>
        <h1>{t.addComputer}</h1>
        <p className="muted pair-lead">{t.pairHint}</p>
        <div className="pair-choices">
          <button
            type="button"
            className={`choice-card${pairTarget === 'local' ? ' active' : ''}`}
            aria-pressed={pairTarget === 'local'}
            onClick={() => {
              setCopied(false);
              setPairTarget('local');
            }}
          >
            <span className="choice-icon">
              <Icon name="laptop" />
            </span>
            <strong>{t.localComputer}</strong>
            <small>{t.localTargetHelp}</small>
          </button>
          <button
            type="button"
            className={`choice-card${pairTarget === 'cloud' ? ' active' : ''}`}
            aria-pressed={pairTarget === 'cloud'}
            onClick={() => {
              setCopied(false);
              setPairTarget('cloud');
            }}
          >
            <span className="choice-icon">
              <Icon name="laptop" />
            </span>
            <strong>{t.cloudComputer}</strong>
            <small>{t.cloudTargetHelp}</small>
          </button>
        </div>
        <div className="command-box">
          <span className="command-label">{t.addComputer}</span>
          <code>{installCommand ?? t.preparingCommand}</code>
          <button
            className="copy-button"
            disabled={!installCommand || installCommand === t.localInstallUnavailable}
            onClick={() => {
              if (installCommand && installCommand !== t.localInstallUnavailable)
                void navigator.clipboard.writeText(installCommand).then(() => setCopied(true));
            }}
          >
            {copied ? t.copied : t.copyCommand}
          </button>
        </div>
        {connectedNode && (
          <div className="pair-success" role="status">
            <motion.div
              initial={{ scale: reduceMotion ? 1 : 0.6 }}
              animate={{ scale: reduceMotion ? 1 : [0.6, 1.08, 1] }}
              transition={{ type: 'spring', duration: 0.6 }}
            >
              <BotAvatar color={avatarColors[1]!} size={64} />
            </motion.div>
            {!reduceMotion &&
              Array.from({ length: 8 }, (_, index) => {
                const angle = (index * Math.PI) / 4;
                return (
                  <motion.i
                    key={index}
                    initial={{ x: 0, y: 0, opacity: 1 }}
                    animate={{ x: Math.cos(angle) * 65, y: Math.sin(angle) * 65, opacity: 0 }}
                    transition={{ duration: 0.6 }}
                  />
                );
              })}
            <strong>{t.pairSuccess}</strong>
          </div>
        )}
        <div className="pair-wait">
          <SpinnerDots />
          <div>
            <strong>{t.waiting}</strong>
            <small>
              {pairing ? `${t.pairCode}: ${pairing.code} · ${secondsLeft}s` : t.pairHint}
            </small>
          </div>
          <span className="online-pulse" />
        </div>
        {me?.nodes.length ? (
          <div className="paired-nodes">
            {me.nodes.map((node) => (
              <div className="paired-node" key={node.nodeId}>
                <BotAvatar color={avatarColors[1]!} size={36} working={node.online} />
                <span>
                  {node.name}
                  <small>{node.online ? t.connected : t.offline}</small>
                </span>
              </div>
            ))}
          </div>
        ) : null}
        {pairing && secondsLeft === 0 && (
          <button
            className="text-button"
            onClick={() => {
              setPairing(null);
              void generate();
            }}
          >
            {t.refreshCode}
          </button>
        )}
        {error && (
          <p className="form-error" role="alert">
            {error}
          </p>
        )}
      </section>
    </main>
  );
}
