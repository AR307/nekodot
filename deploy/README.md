# Phase 3 deployment

The product page runs locally. The remote machine hosts only Relay and the node installer/downloads, on loopback. No domain, public web hosting or PWA is required.

## Build and upload

Use Node 24 and the repository's pnpm version:

```sh
pnpm install --frozen-lockfile
pnpm build:distribution
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
