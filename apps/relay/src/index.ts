import { homedir } from 'node:os';
import { join, resolve } from 'node:path';
import { createRelay } from './server';
import { readFile } from 'node:fs/promises';
import { smtpSchema } from './email';
import { github, google, type OAuthClient } from './oauth';
const port = Number(process.env.PORT ?? 4319);
// A sign-in provider is offered only when both its client id and secret are set.
function oauthClient(name: string): OAuthClient | undefined {
  const clientId = process.env[`${name}_OAUTH_CLIENT_ID`];
  const clientSecret = process.env[`${name}_OAUTH_CLIENT_SECRET`];
  if (!clientId !== !clientSecret)
    throw new Error(`Set both ${name}_OAUTH_CLIENT_ID and ${name}_OAUTH_CLIENT_SECRET, or neither`);
  return clientId && clientSecret ? { clientId, clientSecret } : undefined;
}
const googleClient = oauthClient('GOOGLE');
const githubClient = oauthClient('GITHUB');
if (!process.env.JWT_SECRET) throw new Error('Set JWT_SECRET before starting Relay');
const { app } = await createRelay({
  dataDir: process.env.DATA_DIR ?? join(homedir(), '.nekodot-relay'),
  jwtSecret: process.env.JWT_SECRET,
  publicUrl: process.env.PUBLIC_URL ?? `http://127.0.0.1:${port}`,
  logger: true,
  distributionDirectory: resolve(process.env.DISTRIBUTION_DIR ?? 'dist/distribution'),
  clientOrigins: (process.env.CLIENT_ORIGINS ?? '').split(',').filter(Boolean),
  firebaseCredentials: process.env.GOOGLE_APPLICATION_CREDENTIALS,
  composioApiKey: process.env.COMPOSIO_API_KEY,
  smtp: process.env.SMTP_CONFIG
    ? smtpSchema.parse(JSON.parse(await readFile(process.env.SMTP_CONFIG, 'utf8')))
    : undefined,
  trustedProxy: (process.env.TRUSTED_PROXY ?? '').split(',').filter(Boolean),
  oauth: {
    ...(googleClient ? { google: google(googleClient) } : {}),
    ...(githubClient ? { github: github(githubClient) } : {}),
  },
});
await app.listen({ host: process.env.HOST ?? '127.0.0.1', port });
for (const signal of ['SIGINT', 'SIGTERM'] as const)
  process.once(signal, () => {
    void app.close();
  });
