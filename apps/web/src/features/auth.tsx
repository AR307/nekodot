import { useEffect, useState, type FormEvent } from 'react';
import { AnimatePresence, motion, useReducedMotion } from 'motion/react';
import { relayRequest } from '../api';
import { useAppStore } from '../store';
import { Icon, LoadingText, Wordmark, ease } from '../ui';
import { type Texts } from '../shared';
import { AuthFrame } from '../components/ui/auth-page';

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
  const [mode, setMode] = useState<'login' | 'signup' | 'verify' | 'reset'>('signup');
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [busy, setBusy] = useState(false);
  const [code, setCode] = useState('');
  const [sending, setSending] = useState(false);
  const [retryAt, setRetryAt] = useState(0);
  const [seconds, setSeconds] = useState(0);
  const [notice, setNotice] = useState('');
  const reduceMotion = useReducedMotion();
  useEffect(() => {
    const timer = window.setInterval(
      () => setSeconds(Math.max(0, Math.ceil((retryAt - Date.now()) / 1000))),
      500,
    );
    return () => window.clearInterval(timer);
  }, [retryAt]);

  async function sendCode() {
    setSending(true);
    setError('');
    setNotice('');
    try {
      await relayRequest('/auth/code', {
        method: 'POST',
        body: JSON.stringify({
          email,
          purpose: mode === 'verify' ? 'verify' : mode === 'reset' ? 'reset' : 'signup',
          ...(mode === 'verify' ? { password } : {}),
        }),
      });
      setRetryAt(Date.now() + 60_000);
      setSeconds(60);
      setNotice(t.codeSent);
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : t.saveError);
    } finally {
      setSending(false);
    }
  }

  async function submit(event: FormEvent) {
    event.preventDefault();
    setBusy(true);
    setError('');
    try {
      const result = await relayRequest<{ token: string }>(
        '/auth/' + (mode === 'reset' ? 'password/reset' : mode),
        {
          method: 'POST',
          body: JSON.stringify({ email, password, ...(mode !== 'login' ? { code } : {}) }),
        },
      );
      if (mode === 'reset') {
        setMode('login');
        setCode('');
        setNotice(t.passwordResetDone);
      } else setToken(result.token);
    } catch (reason) {
      if (reason instanceof Error && 'code' in reason && reason.code === 'verification_required') {
        setMode('verify');
        setError(t.verifyRequired);
      } else setError(reason instanceof Error ? reason.message : 'Could not sign in');
    } finally {
      setBusy(false);
    }
  }
  return (
    <AuthFrame
      headline={t.authHeadline}
      description={t.welcome}
      note={t.authPoint1}
      language={language}
      languageLabel={t.language}
      onToggleLanguage={onToggleLanguage}
    >
      <form className="auth-card" onSubmit={(event) => void submit(event)}>
        <div className="auth-mobile-brand">
          <Wordmark />
        </div>
        <AnimatePresence mode="wait" initial={false}>
          <motion.div
            key={mode}
            className="auth-card-heading"
            initial={{ opacity: 0, y: reduceMotion ? 0 : 6 }}
            animate={{ opacity: 1, y: 0 }}
            exit={{ opacity: 0, y: reduceMotion ? 0 : -6 }}
            transition={{ duration: 0.16, ease }}
          >
            <h2>
              {mode === 'signup'
                ? t.signUp
                : mode === 'verify'
                  ? t.verifyEmail
                  : mode === 'reset'
                    ? t.resetPassword
                    : t.signIn}
            </h2>
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
            autoComplete={
              mode === 'signup' || mode === 'reset' ? 'new-password' : 'current-password'
            }
            type="password"
            minLength={8}
            required
            value={password}
            placeholder={t.passwordPlaceholder}
            onChange={(event) => setPassword(event.target.value)}
          />
        </label>
        {mode !== 'login' && (
          <label>
            {t.emailCode}
            <input
              aria-label={t.emailCode}
              autoComplete="one-time-code"
              inputMode="numeric"
              pattern="[0-9]{6}"
              minLength={6}
              maxLength={6}
              required
              value={code}
              onChange={(event) => setCode(event.target.value)}
            />
            <button
              type="button"
              className="secondary-button"
              disabled={sending || seconds > 0 || !email || (mode === 'verify' && !password)}
              onClick={() => void sendCode()}
            >
              {sending ? (
                <LoadingText action="submitting" />
              ) : seconds > 0 ? (
                `${seconds}s`
              ) : (
                t.sendCode
              )}
            </button>
          </label>
        )}
        {notice && (
          <p role="status" className="inline-success">
            {notice}
          </p>
        )}
        {error && (
          <p className="form-error" role="alert">
            {error}
          </p>
        )}
        <button className="primary-button full-button" disabled={busy}>
          {busy ? <LoadingText action="submitting" /> : t.submit}
          {!busy && <Icon name="arrow" />}
        </button>
        <button
          className="text-button account-toggle"
          type="button"
          onClick={() => {
            setMode(mode === 'signup' ? 'login' : 'signup');
            setCode('');
            setNotice('');
            setError('');
          }}
        >
          {mode === 'signup' ? t.alreadyAccount : t.newAccount}
        </button>
        {mode === 'login' && (
          <button
            className="text-button"
            type="button"
            onClick={() => {
              setMode('reset');
              setError('');
              setNotice('');
              setCode('');
            }}
          >
            {t.forgotPassword}
          </button>
        )}
        {(mode === 'verify' || mode === 'reset') && (
          <button
            className="text-button"
            type="button"
            onClick={() => {
              setMode('login');
              setError('');
              setNotice('');
            }}
          >
            {t.signIn}
          </button>
        )}
        <p className="auth-privacy">
          <Icon name="check" />
          {t.privateByDesign}
        </p>
      </form>
    </AuthFrame>
  );
}
