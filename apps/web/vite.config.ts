import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import tailwindcss from '@tailwindcss/vite';
export default defineConfig({
  plugins: [react(), tailwindcss()],
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
