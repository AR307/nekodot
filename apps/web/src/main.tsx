import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import { App } from './team-app';
import './styles/tokens.css';
import './styles/fonts.css';
import './style.css';

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <App />
  </StrictMode>,
);
