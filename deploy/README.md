# Relay and node deployment

The product page runs locally. The remote machine hosts only Relay and the node installer/downloads, on loopback. No domain, public web hosting or PWA is required.

## Build and upload

Use Node 24 and the repository's pnpm version:

```sh
pnpm install --frozen-lockfile
pnpm build:distribution
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

The installer uses private Node 24 and the official Hermes installation stages, then starts `nekodot-node.service`. It retains the current node identity on repeated installation. For a different Relay address, pass `--relay <url>`.

Some minimal Ubuntu images do not include Hermes PM's `libatomic.so.1` runtime dependency. The installer checks for it before downloading Node or Hermes; on Ubuntu/Debian, install it with `sudo apt-get install -y libatomic1`, then rerun the same command. This does not install or change the system Node runtime.

On Windows, choose **This computer** in the web page and run its command inside WSL2 Ubuntu 24.04 with systemd enabled. Windows OpenSSH fetches the installer, then the installer privately copies the configured identity and known-hosts file into `~/.nekodot/ssh/` so WSL can maintain its own loopback tunnel and user service. No global WSL or SSH configuration is modified. The copied identity remains local to `~/.nekodot` and is kept by the non-destructive uninstall.

```sh
systemctl --user status nekodot-node
journalctl --user -u nekodot-node
~/.nekodot/bin/nekodot-node run
curl -fsSL http://127.0.0.1:4329/install.sh | bash -s -- --uninstall
```

Do not run the foreground command while the service is active. Uninstall stops/disables the service and retains all files, profiles and history. Reinstall starts the existing node again.

This phase supports Linux/WSL2 x64 only. macOS, ARM, full-machine reboot acceptance and real phone acceptance must not be reported as passed without their corresponding environment and evidence.

## Native Linux screen

Add `--with-computer` to the downloaded installer command on a Linux VPS:

```sh
curl -fsSL http://127.0.0.1:4329/install.sh | bash -s -- --pair ABCD-2345 --with-computer
```

For an already paired node, rerun with `--with-computer` and omit `--pair`. The installer retains the node identity, database, Hermes profiles and browser data. It uses the official Hermes CLI/PM to install the screen packages, computer-use driver and Chromium; it does not change the system Node or configure sudo. Missing administrator privileges produce an installation command to run separately.

Open a Bot's screen in the web page and choose **Start screen**. Hermes owns its 1440×900 desktop, browser and control lease. The node connects out through the authenticated Relay screen channel; VNC and CDP do not need public ports. The existing development proxy and SSH tunnel also carry `/ws/tunnel`.

WSL, Windows and macOS screens are not supported in this phase. Use the local loopback web page for screen access; ordinary LAN HTTP is not a secure context. See [native observations](../docs/hermes-screen-notes.md) and [acceptance results](../docs/phase4-acceptance.md).
