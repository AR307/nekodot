/** Public deployment address only. Credentials are never compiled into the client. */
const configured = import.meta.env.VITE_NEKODOT_RELAY_URL as string | undefined;
if (
  import.meta.env.VITE_NEKODOT_NATIVE === '1' &&
  (!configured || new URL(configured).protocol !== 'https:')
)
  throw new Error('Native builds require a product HTTPS Relay origin');
const base = configured ? new URL(configured) : new URL(location.origin);

export function relayUrl(path: string) {
  return new URL(path, base).toString();
}

export function relaySocketUrl(path: string) {
  const url = new URL(path, base);
  url.protocol = url.protocol === 'https:' ? 'wss:' : 'ws:';
  return url.toString();
}
