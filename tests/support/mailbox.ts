import { once } from 'node:events';
import { SMTPServer } from 'smtp-server';

/** A real loopback SMTP inbox used only by automated account/browser journeys. */
export async function startMailbox() {
  const messages: string[] = [];
  const server = new SMTPServer({
    disabledCommands: ['AUTH', 'STARTTLS'],
    onData(stream, _session, callback) {
      let body = '';
      stream.on('data', (chunk) => {
        body += String(chunk);
      });
      stream.on('end', () => {
        messages.push(body);
        callback();
      });
    },
  });
  server.listen(0, '127.0.0.1');
  await once(server.server, 'listening');
  const address = server.server.address();
  if (!address || typeof address === 'string') throw new Error('SMTP inbox did not listen');
  return {
    smtp: {
      host: '127.0.0.1',
      port: address.port,
      secure: false,
      user: '',
      password: '',
      from: 'nekodot@example.test',
    },
    code: () => {
      const code = messages.at(-1)?.match(/\b\d{6}\b/)?.[0];
      if (!code) throw new Error('No verification email received');
      return code;
    },
    close: () => new Promise<void>((resolve) => server.close(() => resolve())),
  };
}
