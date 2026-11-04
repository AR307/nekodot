import { createHash, randomBytes } from 'node:crypto';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

/** Hermes plugin bridge address: a Unix socket on POSIX, a fresh named pipe on Windows. */
export function bridgeEndpoint(home: string) {
  if (process.platform === 'win32')
    return '\\\\.\\pipe\\nekodot-bridge-' + randomBytes(16).toString('hex');
  const path = join(home, 'routines.sock');
  // sun_path is 104 bytes on macOS; long user-chosen data paths use a private temp directory.
  if (Buffer.byteLength(path) <= 100) return path;
  const hash = createHash('sha256').update(home).digest('hex').slice(0, 16);
  return join(tmpdir(), 'nekodot-' + hash, 'routines.sock');
}

export const isNamedPipe = (path: string) => path.startsWith('\\\\.\\pipe\\');

/** Python client used by the Hermes plugins; the request and response are one JSON line each. */
export const pythonBridgeCall = String.raw`
def _bridge_call(path, request, timeout):
    data = (json.dumps(request) + "\n").encode()
    if path.startswith("\\\\.\\pipe\\"):
        import _winapi
        import time
        deadline = time.monotonic() + timeout
        while True:
            try:
                pipe = open(path, "r+b", buffering=0)
                break
            except OSError as error:
                if getattr(error, "winerror", None) != 231 or time.monotonic() > deadline:
                    raise
                try:
                    _winapi.WaitNamedPipe(path, 1000)
                except OSError:
                    pass
        with pipe:
            pipe.write(data)
            response = b""
            while not response.endswith(b"\n"):
                chunk = pipe.read(65536)
                if not chunk:
                    raise RuntimeError("nekoDOT bridge disconnected")
                response += chunk
        return json.loads(response)
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as client:
        client.settimeout(timeout)
        client.connect(path)
        client.sendall(data)
        response = b""
        while not response.endswith(b"\n"):
            chunk = client.recv(65536)
            if not chunk:
                raise RuntimeError("nekoDOT bridge disconnected")
            response += chunk
    return json.loads(response)
`;
