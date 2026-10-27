import { useState, type FormEvent } from 'react';
import { relayRequest } from '../api';
import { useAppStore } from '../store';
import { BotAvatar, Icon, SpinnerDots, Wordmark } from '../ui';
import { avatarColors, type Texts } from '../shared';

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
      <button className="quiet-button auth-language" type="button" onClick={onToggleLanguage}>
        {t.language}
      </button>
      <section className="auth-brand-panel">
        <Wordmark />
        <div className="auth-intro">
          <span className="eyebrow">
            <i /> {t.yourAiTeam}
          </span>
          <h1>{t.welcome}</h1>
          <p>{t.tagline}</p>
          <div className="path-pill">
            Web <span>→</span> Relay <span>→</span> {t.yourComputer} <span>→</span> Hermes
          </div>
        </div>
        <div className="auth-dots" aria-hidden="true">
          <BotAvatar color={avatarColors[0]!} size={62} />
          <BotAvatar color={avatarColors[1]!} size={46} />
          <BotAvatar color={avatarColors[2]!} size={52} />
        </div>
      </section>
      <section className="auth-form-panel">
        <form className="auth-card" onSubmit={(event) => void submit(event)}>
          <p className="eyebrow">
            <i /> {t.privateByDesign}
          </p>
          <h2>{mode === 'signup' ? t.signUp : t.signIn}</h2>
          <p className="muted">{t.welcome}</p>
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
            <Icon name="arrow" />
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
        </form>
      </section>
    </main>
  );
}
