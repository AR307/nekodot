# Relay and node deployment

The Flutter client renders locally and connects to the HTTPS Relay. The remote machine hosts Relay and installer/downloads behind Caddy; Hermes management and VNC remain on loopback.

## Build and upload

Use Node 24 and the repository's pnpm version:

```sh
pnpm install --frozen-lockfile
pnpm build:distribution
# Build the backend package on each supported host.
node scripts/stage-hermes-runtime.mjs /build/windows/win32-x64.json /build/linux/linux-x64.json
# Required for an auto-updating Node release; the key stays outside the repository/server.
NEKODOT_RELEASE_KEY_FILE=/private/nekodot-release.pem pnpm release:node
docker build -f deploy/docker/Dockerfile -t nekodot-relay:phase3 .
docker save -o .runtime/nekodot-relay-phase3.tar nekodot-relay:phase3
```

Upload the image archive and Compose file to a dedicated remote project directory. On that machine:

```sh
docker load -i nekodot-relay-phase3.tar
mkdir -p data
chown 1000:1000 data
# Create .env locally with JWT_SECRET=<a private random value>; do not commit it.
docker compose up -d
curl -fsS http://127.0.0.1:4329/health
```

Keep the same JWT_SECRET and data directory across restarts. Do not modify other Compose projects or expose port 4329 publicly. Installer downloads are included in the image.

## Google and GitHub sign-in

The apps offer **Continue with Google** and **Continue with GitHub** only for providers the Relay has a client for. Create the clients yourself and put both values of each in `.env`:

| Provider | Create it at                                                 | Callback URL to register                      | `.env`                                                 |
| -------- | ------------------------------------------------------------ | --------------------------------------------- | ------------------------------------------------------ |
| Google   | Google Cloud console, OAuth client of type _Web application_ | `<PUBLIC_URL>/api/auth/oauth/google/callback` | `GOOGLE_OAUTH_CLIENT_ID`, `GOOGLE_OAUTH_CLIENT_SECRET` |
| GitHub   | GitHub, Settings, Developer settings, OAuth Apps             | `<PUBLIC_URL>/api/auth/oauth/github/callback` | `GITHUB_OAUTH_CLIENT_ID`, `GITHUB_OAUTH_CLIENT_SECRET` |

The Relay starts only with both values of a pair or neither. Google asks for `openid email`, GitHub for `read:user user:email`; a sign-in needs a verified email. The first sign-in creates an account for that email, or signs in to the account that already has it. Such an account has no password until its owner sets one with **Forgot password**.

The app opens the provider in the system browser. The Relay sends a one-time code back to the app that started the sign-in (a `127.0.0.1` address on a computer, the `nekodot://oauth` link on Android), and the app redeems it with a secret it never sent, so a code that reaches anyone else is useless.

## Node releases

Publish Relay and its Node downloads **before** distributing a new client. After every distribution build, run `pnpm release:node` with the publisher's Ed25519 PEM private key. It stamps the bundle with a 14-digit UTC version and public key and writes `nekodot-node.json`. Deploy the bundle and manifest together. Relay reads the manifest again on Node/client connections; replacing downloads does not require a Relay restart.

The publisher creates and backs up the production key outside Git and the server; it is never included in a download or container. Losing or rotating it requires every installed Node to rerun its install command once. Local acceptance uses a separate test key only. Ordinary builds need no key and are development builds: they do not self-update, and any stale manifest is moved to `.runtime/recycle`.

Online `1.0.0` Nodes must rerun the command shown in the client once. They cannot understand an update notification. Reinstall preserves identity, credentials, database and Hermes profiles; it atomically replaces the bundle and moves pending/tried/rejected markers into `bin/recycle`. Thereafter signed releases download in the background and switch only when native runs, group chains and management operations are idle. Hermes and the private Node **24.22.1** runtime are not updated.

The launcher retains the previous bundle. A new release is confirmed only after `hello.ok`; if its next launch still finds an unconfirmed attempt, it restores the previous bundle and records the rejected version. A later, higher version can update again. A Relay outage or machine restart during this window can also cause a rollback; rerunning the installer is the explicit recovery path. Markers are retained in the local recycle directory, not permanently deleted.

Release rules: new Nodes must continue to serve client versions still in use, and database changes must remain readable by the previous Node so rollback works. Do not introduce a database change that prevents this. To revert code in published downloads, stamp the previous code with a **higher** timestamp; never lower a published version. Test the bundle on the fixed runtime before publishing. This policy is a publisher responsibility, not an extra compatibility framework.

## Node installation

For a VPS, SSH into the Relay host and run the web-provided command as the Linux account that will own the node. Use a dedicated account on a shared server. systemd user services and linger must be available; an administrator can enable linger using `loginctl enable-linger <user>`.

```sh
curl -fsSL http://127.0.0.1:4329/install.sh | bash -s -- --pair ABCD-2345
```

The installer downloads private Node 24 and the versioned Nekodot Hermes backend package, then starts `nekodot-node.service`. It does not clone the Hermes repository or build frontends. Repeated installation retains the node identity, profiles and history. For a different Relay address, pass `--relay <url>`.

Some minimal Ubuntu images do not include Hermes PM's `libatomic.so.1` runtime dependency. The installer checks for it before downloading Node or Hermes; on Ubuntu/Debian, install it with `sudo apt-get install -y libatomic1`, then rerun the same command. This does not install or change the system Node runtime.

For a cloud sandbox, choose **Cloud sandbox** in the native client and enter a Daytona API key, or a Vercel access token with its team and project. The client creates the sandbox with that account and runs the same installer with `--sandbox --name <name>` (the pairing code response carries this as `sandboxCommand`). Sandboxes have no systemd, so the installer writes `~/.nekodot/bin/nekodot-supervise`, which restarts the node after a crash or an update, and `~/.nekodot/bin/nekodot-start`, which starts it once after the sandbox resumes. The keys stay on that device; the Relay never sees them. A Daytona account below Tier 3 cannot reach the Relay from its sandboxes. Vercel stops a session after the plan's limit (45 minutes on Hobby, 24 hours on Pro); an open client wakes it again.

On Windows, choose **This computer** in the native client. It uses the same backend recipe with a Windows package, installs into the selected runtime directory, and keeps account data in the separately selected data directory. No WSL or frontend build is needed.

```sh
systemctl --user status nekodot-node
journalctl --user -u nekodot-node
~/.nekodot/bin/nekodot-node run
curl -fsSL http://127.0.0.1:4329/install.sh | bash -s -- --uninstall
```

Do not run the foreground command while the service is active. Uninstall stops/disables the service and retains all files, profiles and history. Reinstall starts the existing node again.

The VPS installer supports Linux x64. The native local-node targets are Windows x64, Ubuntu 24.04 x64 and macOS arm64. Each package must be built on its target host; macOS and phone acceptance require their actual devices.

## Native Linux screen

The Linux VPS installer prepares native screen dependencies by default:

```sh
curl -fsSL http://127.0.0.1:4329/install.sh | bash -s -- --pair ABCD-2345
```

For an already paired node, rerun and omit `--pair`. The installer retains the node identity, database, profiles and browser data. Chromium, the computer-use driver and FFmpeg are packaged; OS desktop libraries use the official Hermes installer. It does not change the system Node or configure sudo. Missing administrator privileges produce an installation command to run separately.

Open a Bot's screen in the native client and choose **Start screen**. Hermes owns its 1440×900 desktop, browser and control lease. The node connects out through the authenticated Relay screen channel; VNC and CDP do not need public ports.

WSL nodes do not provide the Linux VPS screen. Desktop local-node control uses the host's native computer-use capability and permission flow. Packaging does not lower Hermes's screen memory requirements or change its execution policies.
