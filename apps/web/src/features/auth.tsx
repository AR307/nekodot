import { useState, type FormEvent } from 'react';
import { AnimatePresence, motion, useReducedMotion } from 'motion/react';
import { relayRequest } from '../api';
import { useAppStore } from '../store';
import { BotAvatar, Icon, SpinnerDots, Wordmark, ease } from '../ui';
import { avatarColors, type Texts } from '../shared';

const crew = [
  { color: avatarColors[2]!, size: 76, x: '8%', y: '18%', delay: 0, working: true },
  { color: avatarColors[0]!, size: 92, x: '46%', y: '4%', delay: 0.6, working: false },
  { color: avatarColors[1]!, size: 64, x: '74%', y: '40%', delay: 1.2, working: false },
  { color: avatarColors[3]!, size: 56, x: '30%', y: '58%', delay: 1.8, working: false },
];

export function AuthPage({
  t,
  language,
  onToggleLanguage,
}: {
  t: Texts;
  language: 'zh' | 'en';
  onToggleLanguage(): void;
}) {
  const setToken = useAppStore((state) => state.setToken);
  const error = useAppStore((state) => state.authError);
  const setError = useAppStore((state) => state.setAuthError);
  const [mode, setMode] = useState<'login' | 'signup'>('signup');
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [busy, setBusy] = useState(false);
  const reduceMotion = useReducedMotion();

  async function submit(event: FormEvent) {
    event.preventDefault();
    setBusy(true);
    setError('');
    try {
      const result = await relayRequest<{ token: string }>('/auth/' + mode, {
        method: 'POST',
        body: JSON.stringify({ email, password }),
      });
      setToken(result.token);
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : 'Could not sign in');
    } finally {
      setBusy(false);
    }
  }
  return (
    <main className="auth-layout" lang={language}>
      <section className="auth-brand-panel">
        <Wordmark />
        <div className="auth-crew" aria-hidden="true">
          {crew.map((member, index) => (
            <motion.span
              key={index}
              className="auth-crew-member"
              style={{ left: member.x, top: member.y }}
              initial={reduceMotion ? false : { opacity: 0, scale: 0.6, y: 12 }}
              animate={{ opacity: 1, scale: 1, y: 0 }}
              transition={{
                delay: 0.1 + index * 0.08,
                type: 'spring',
                stiffness: 260,
                damping: 18,
              }}
            >
              <span style={{ animationDelay: `${member.delay}s` }}>
                <BotAvatar color={member.color} size={member.size} working={member.working} />
              </span>
            </motion.span>
          ))}
        </div>
        <div className="auth-intro">
          <h1>{t.authHeadline}</h1>
          <p>{t.authBody}</p>
          <ul>
            {[t.authPoint1, t.authPoint2, t.authPoint3].map((point) => (
              <li key={point}>
                <Icon name="check" />
                {point}
              </li>
            ))}
          </ul>
          <div className="path-pill">
            Web <span>→</span> Relay <span>→</span> {t.yourComputer} <span>→</span> Hermes
          </div>
        </div>
      </section>
      <section className="auth-form-panel">
        <button className="quiet-button auth-language" type="button" onClick={onToggleLanguage}>
          <Icon name="globe" />
          {t.language}
        </button>
        <form className="auth-card" onSubmit={(event) => void submit(event)}>
          <AnimatePresence mode="wait" initial={false}>
            <motion.div
              key={mode}
              className="auth-card-heading"
              initial={{ opacity: 0, y: reduceMotion ? 0 : 6 }}
              animate={{ opacity: 1, y: 0 }}
              exit={{ opacity: 0, y: reduceMotion ? 0 : -6 }}
              transition={{ duration: 0.16, ease }}
            >
              <h2>{mode === 'signup' ? t.signUp : t.signIn}</h2>
              <p className="muted">{t.welcome}</p>
            </motion.div>
          </AnimatePresence>
          <label>
            {t.email}
            <input
              autoComplete="email"
              type="email"
              required
              value={email}
              placeholder={t.emailPlaceholder}
              onChange={(event) => setEmail(event.target.value)}
            />
          </label>
          <label>
            {t.password}
            <input
              autoComplete={mode === 'signup' ? 'new-password' : 'current-password'}
              type="password"
              minLength={8}
              required
              value={password}
              placeholder={t.passwordPlaceholder}
              onChange={(event) => setPassword(event.target.value)}
            />
          </label>
          {error && (
            <p className="form-error" role="alert">
              {error}
            </p>
          )}
          <button className="primary-button full-button" disabled={busy}>
            {busy ? <SpinnerDots /> : t.submit}
            {!busy && <Icon name="arrow" />}
          </button>
          <button
            className="text-button account-toggle"
            type="button"
            onClick={() => {
              setMode(mode === 'signup' ? 'login' : 'signup');
              setError('');
            }}
          >
            {mode === 'signup' ? t.alreadyAccount : t.newAccount}
          </button>
          <p className="auth-privacy">
            <Icon name="check" />
            {t.privateByDesign}
          </p>
        </form>
      </section>
    </main>
  );
}
