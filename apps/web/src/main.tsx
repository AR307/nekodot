import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import { App } from './team-app';
import './styles/tokens.css';
import './styles/fonts.css';
import './style.css';
import './styles/capabilities.css';

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <App />
  </StrictMode>,
);
