import { StrictMode, useState } from 'react';
import { createRoot } from 'react-dom/client';
import zh from './i18n/zh';
import en from './i18n/en';
import './style.css';
function App() {
  const [language, setLanguage] = useState<'zh' | 'en'>(
    navigator.language.startsWith('zh') ? 'zh' : 'en',
  );
  const t = language === 'zh' ? zh : en;
  return (
    <main lang={language}>
      <header>
        <a href="/" className="brand" aria-label="nekodot">
          <span className="cat" aria-hidden="true">
            •
          </span>
          nekodot<span className="brand-dot">.</span>
        </a>
        <button onClick={() => setLanguage(language === 'zh' ? 'en' : 'zh')}>{t.lang}</button>
      </header>
      <section className="hero">
        <p className="eyebrow">
          <span />
          {t.stage}
        </p>
        <h1>{t.title}</h1>
        <p className="intro">{t.intro}</p>
        <div className="architecture">{t.architecture}</div>
      </section>
      <section className="cards" aria-label={language === 'zh' ? '基础模块' : 'Foundation modules'}>
        {[
          [t.protocol, t.protocolText, '01'],
          [t.node, t.nodeText, '02'],
          [t.connection, t.connectionText, '03'],
        ].map(([title, body, n]) => (
          <article key={n}>
            <span className="number">{n}</span>
            <h2>{title}</h2>
            <p>{body}</p>
          </article>
        ))}
      </section>
      <footer>
        <span className="status-dot" />
        {t.note}
        <span className="edition">nekodot / 2026</span>
      </footer>
    </main>
  );
}
createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <App />
  </StrictMode>,
);
