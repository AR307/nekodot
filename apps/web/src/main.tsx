import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import { App } from './team-app';
import { ClientNotifications } from './features/notifications';
import './styles/tokens.css';
import './styles/fonts.css';
import './style.css';
import './styles/shell.css';
import './styles/chat.css';
import './styles/sheet.css';
import './styles/pages.css';
import './styles/auth.css';
import './styles/capabilities.css';
import './styles/screen.css';
import './styles/shining-text.css';

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <ClientNotifications />
    <App />
  </StrictMode>,
);

import './styles/client.css';
