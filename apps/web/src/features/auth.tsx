import { useEffect, useState, type FormEvent } from 'react';
import { AnimatePresence, motion, useReducedMotion } from 'motion/react';
import { relayRequest } from '../api';
import { useAppStore } from '../store';
import { AtSign, ArrowRight, KeyRound, LockKeyhole, ShieldCheck } from 'lucide-react';
import { SpinnerDots, ease } from '../ui';
import type { Texts } from '../shared';
import { AuthPage as AuthLayout } from '../components/ui/auth-page';
import { Button } from '../components/ui/button';
import { Input } from '../components/ui/input';

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
  const title =
    mode === 'signup'
      ? t.signUp
      : mode === 'verify'
        ? t.verifyEmail
        : mode === 'reset'
          ? t.resetPassword
          : t.signIn;
  function switchMode(next: typeof mode) {
    setMode(next);
    setCode('');
    setNotice('');
    setError('');
  }
  return (
    <AuthLayout
      headline={t.authHeadline}
      description={t.authBody}
      language={language}
      languageLabel={t.language}
      homeLabel={t.authHome}
      onToggleLanguage={onToggleLanguage}
    >
      <form className="auth-card" onSubmit={(event) => void submit(event)} aria-busy={busy}>
        <AnimatePresence mode="wait" initial={false}>
          <motion.div
            key={mode}
            className="auth-card-heading"
            initial={{ opacity: 0, y: reduceMotion ? 0 : 6 }}
            animate={{ opacity: 1, y: 0 }}
            exit={{ opacity: 0, y: reduceMotion ? 0 : -6 }}
            transition={{ duration: 0.16, ease }}
          >
            <h2>{title}</h2>
            <p>{t.welcome}</p>
          </motion.div>
        </AnimatePresence>
        <div className="auth-fields">
          <div className="auth-field">
            <label htmlFor="auth-email">{t.email}</label>
            <div className="auth-input-wrap">
              <AtSign aria-hidden="true" />
              <Input
                id="auth-email"
                autoComplete="email"
                type="email"
                required
                disabled={busy}
                value={email}
                placeholder={t.emailPlaceholder}
                onChange={(event) => setEmail(event.target.value)}
              />
            </div>
          </div>
          <div className="auth-field">
            <div className="auth-label-row">
              <label htmlFor="auth-password">{t.password}</label>
              {mode === 'login' && (
                <Button
                  variant="link"
                  size="sm"
                  type="button"
                  disabled={busy}
                  onClick={() => switchMode('reset')}
                >
                  {t.forgotPassword}
                </Button>
              )}
            </div>
            <div className="auth-input-wrap">
              <LockKeyhole aria-hidden="true" />
              <Input
                id="auth-password"
                autoComplete={
                  mode === 'signup' || mode === 'reset' ? 'new-password' : 'current-password'
                }
                type="password"
                minLength={8}
                required
                disabled={busy}
                value={password}
                placeholder={t.passwordPlaceholder}
                onChange={(event) => setPassword(event.target.value)}
              />
            </div>
          </div>
          {mode !== 'login' && (
            <div className="auth-field">
              <label htmlFor="auth-code">{t.emailCode}</label>
              <div className="auth-code-row">
                <div className="auth-input-wrap">
                  <KeyRound aria-hidden="true" />
                  <Input
                    id="auth-code"
                    autoComplete="one-time-code"
                    inputMode="numeric"
                    pattern="[0-9]{6}"
                    minLength={6}
                    maxLength={6}
                    required
                    disabled={busy}
                    value={code}
                    placeholder="000000"
                    onChange={(event) => setCode(event.target.value)}
                  />
                </div>
                <Button
                  variant="outline"
                  type="button"
                  disabled={
                    busy || sending || seconds > 0 || !email || (mode === 'verify' && !password)
                  }
                  onClick={() => void sendCode()}
                >
                  {seconds > 0 ? seconds + 's' : t.sendCode}
                </Button>
              </div>
            </div>
          )}
        </div>
        {notice && (
          <p role="status" className="auth-notice">
            {notice}
          </p>
        )}
        {error && (
          <p className="form-error" role="alert">
            {error}
          </p>
        )}
        <Button type="submit" size="lg" className="auth-submit" disabled={busy || sending}>
          {busy ? (
            <SpinnerDots />
          ) : (
            <>
              {title}
              <ArrowRight size={17} aria-hidden="true" />
            </>
          )}
        </Button>
        <div className="auth-account-switch">
          <Button
            variant="link"
            type="button"
            disabled={busy}
            onClick={() => switchMode(mode === 'login' ? 'signup' : 'login')}
          >
            {mode === 'signup' ? t.alreadyAccount : mode === 'login' ? t.newAccount : t.signIn}
          </Button>
        </div>
        <p className="auth-privacy">
          <ShieldCheck size={14} aria-hidden="true" />
          {t.privateByDesign}
        </p>
      </form>
    </AuthLayout>
  );
}
