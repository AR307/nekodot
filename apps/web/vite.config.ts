import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import tailwindcss from '@tailwindcss/vite';
export default defineConfig({
  plugins: [react(), tailwindcss()],
  define: {
    'import.meta.env.VITE_NEKODOT_RELAY_SSH': JSON.stringify(process.env.NEKODOT_RELAY_SSH ?? ''),
    'import.meta.env.VITE_NEKODOT_RELAY_SSH_IDENTITY': JSON.stringify(
      process.env.NEKODOT_RELAY_SSH_IDENTITY ?? '',
    ),
    'import.meta.env.VITE_NEKODOT_RELAY_SSH_KNOWN_HOSTS': JSON.stringify(
      process.env.NEKODOT_RELAY_SSH_KNOWN_HOSTS ?? '',
    ),
  },
  server: {
    host: '127.0.0.1',
    port: 4318,
    proxy: {
      '/api': { target: process.env.NEKODOT_RELAY_URL ?? 'http://127.0.0.1:4319' },
      '/ws': { target: process.env.NEKODOT_RELAY_URL ?? 'http://127.0.0.1:4319', ws: true },
      '/install.sh': { target: process.env.NEKODOT_RELAY_URL ?? 'http://127.0.0.1:4319' },
      '/downloads': { target: process.env.NEKODOT_RELAY_URL ?? 'http://127.0.0.1:4319' },
    },
  },
});
