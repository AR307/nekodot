#!/usr/bin/env bash
set -euo pipefail
umask 077

relay='__NEKODOT_RELAY_URL__'
home="${NEKODOT_HOME:-$HOME/.nekodot}"
pair_code=''
relay_ssh=''
relay_ssh_key=''
relay_ssh_known_hosts=''
node_name=''
uninstall=false
sandbox=false
while [ "$#" -gt 0 ]; do
  case "$1" in
    --pair|--relay|--relay-ssh|--relay-ssh-key|--relay-ssh-known-hosts|--name)
      [ "$#" -ge 2 ] || { printf '%s requires a value\n' "$1" >&2; exit 2; }
      case "$1" in
        --pair) pair_code="$2" ;;
        --name) node_name="$2" ;;
        --relay) relay="$2" ;;
        --relay-ssh) relay_ssh="$2" ;;
        --relay-ssh-key) relay_ssh_key="$2" ;;
        --relay-ssh-known-hosts) relay_ssh_known_hosts="$2" ;;
      esac
      shift 2 ;;
    --uninstall) uninstall=true; shift ;;
    --sandbox) sandbox=true; shift ;;
    --help)
      printf '%s\n' 'Usage: install.sh --pair ABCD-2345 [--name NAME] [--relay http://127.0.0.1:4329] [--sandbox]' \
        '       install.sh --uninstall [--sandbox]  (stop; retain all files and history)' \
        '       --sandbox: for a cloud sandbox without systemd; the node is kept running by' \
        '       $NEKODOT_HOME/bin/nekodot-supervise, started by $NEKODOT_HOME/bin/nekodot-start'
      exit 0 ;;
    *) printf 'Unknown option: %s\n' "$1" >&2; exit 2 ;;
  esac
done

[ "$(uname -s)" = Linux ] && [ "$(uname -m)" = x86_64 ] || {
  printf '%s\n' 'Supported: Linux x64. On Windows, run this command inside WSL2 Ubuntu 24.04.' >&2
  exit 1
}
# A sandbox runs the node under its own supervisor, which ends the node's
# process group when it is told to stop.
stop_supervisor() {
  local pid
  pid="$(cat "$home/nekodot-supervise.pid" 2>/dev/null || true)"
  if [ -n "$pid" ] && grep -q nekodot-supervise "/proc/$pid/cmdline" 2>/dev/null; then
    kill -TERM "$pid" 2>/dev/null || true
    for _ in $(seq 1 30); do kill -0 "$pid" 2>/dev/null || break; sleep 1; done
  fi
}
if [ "$sandbox" = true ]; then
  if [ "$uninstall" = true ]; then
    stop_supervisor
    printf 'Node stopped. All program files, profiles, history and logs remain in %s\n' "$home"
    exit 0
  fi
  # A sandbox image may lack a tool the installer needs; as root they are
  # added with apt, otherwise the check below names what is missing.
  missing=''
  for tool in curl tar git; do command -v "$tool" >/dev/null || missing="$missing $tool"; done
  if ! ldconfig -p 2>/dev/null | grep -F 'libatomic.so.1' >/dev/null; then missing="$missing libatomic1"; fi
  if [ -n "$missing" ] && command -v apt-get >/dev/null; then
    as_root=''
    if [ "$(id -u)" -ne 0 ] && command -v sudo >/dev/null && sudo -n true 2>/dev/null; then as_root='sudo -n'; fi
    if [ "$(id -u)" -eq 0 ] || [ -n "$as_root" ]; then
      printf 'Installing%s...\n' "$missing"
      $as_root apt-get update
      # shellcheck disable=SC2086
      DEBIAN_FRONTEND=noninteractive $as_root apt-get install -y --no-install-recommends ca-certificates $missing
    fi
  fi
else
command -v systemctl >/dev/null && [ -d /run/systemd/system ] || {
  printf '%s\n' 'systemd is required. For WSL2, enable systemd and restart your WSL instance first.' >&2
  exit 1
}
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
export DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=$XDG_RUNTIME_DIR/bus}"
fi
if [ "$uninstall" = true ]; then
  systemctl --user disable --now nekodot-node.service
  if [ -f "$HOME/.config/systemd/user/nekodot-relay-tunnel.service" ]; then
    systemctl --user disable --now nekodot-relay-tunnel.service
  fi
  printf 'Node service stopped and disabled. All program files, profiles, history and logs remain in %s\n' "$home"
  exit 0
fi
required_tools='curl tar git'
if [ "$sandbox" = false ]; then required_tools="$required_tools systemd-notify"; fi
for tool in $required_tools; do
  command -v "$tool" >/dev/null || { printf 'Install %s with your system package manager, then rerun.\n' "$tool" >&2; exit 1; }
done
if ! ldconfig -p 2>/dev/null | grep -F 'libatomic.so.1' >/dev/null; then
  printf '%s\n' 'The Hermes runtime requires libatomic.so.1. Install the OS package that provides it (Ubuntu/Debian: libatomic1), then rerun.' >&2
  exit 1
fi
if [ -n "$relay_ssh" ]; then
  [[ "$relay_ssh" =~ ^([a-zA-Z0-9_.-]+@)?[a-zA-Z0-9_.-]+$ ]] || {
    printf '%s\n' 'The Relay SSH target must be a configured host alias or user@host.' >&2; exit 2;
  }
  command -v ssh >/dev/null || { printf '%s\n' 'Install OpenSSH client to connect to the Relay.' >&2; exit 1; }
  relay='http://127.0.0.1:4329'
  if [ -n "$relay_ssh_key" ] || [ -n "$relay_ssh_known_hosts" ]; then
    [ -r "$relay_ssh_key" ] && [ -r "$relay_ssh_known_hosts" ] || {
      printf '%s\n' 'Both readable --relay-ssh-key and --relay-ssh-known-hosts files are required.' >&2; exit 2;
    }
  fi
fi
[ -f "$home/node.json" ] || [ -n "$pair_code" ] || {
  printf '%s\n' 'Generate a pairing code in the web app and pass --pair ABCD-2345.' >&2; exit 2;
}
case "$relay" in http://*|https://*) ;; *) printf '%s\n' 'Provide a Relay HTTP URL with --relay.' >&2; exit 2 ;; esac
relay="${relay%/}"
mkdir -p "$home/runtime" "$home/bin" "$home/downloads" "$home/logs"
if [ -n "$relay_ssh_key" ]; then
  mkdir -p "$home/ssh"
  if [ ! -f "$home/ssh/id_ed25519" ]; then install -m 600 "$relay_ssh_key" "$home/ssh/id_ed25519"; fi
  if [ ! -f "$home/ssh/known_hosts" ]; then install -m 600 "$relay_ssh_known_hosts" "$home/ssh/known_hosts"; fi
fi

api_port_file="$home/hermes-api-port"
if [ -s "$api_port_file" ]; then
  read -r api_port < "$api_port_file"
else
  api_port=18642
  while [ "$api_port" -le 18742 ]; do
    if (exec 3<>"/dev/tcp/127.0.0.1/$api_port") 2>/dev/null ||
       (exec 3<>"/dev/tcp/127.0.0.1/$((api_port + 1))") 2>/dev/null; then
      api_port=$((api_port + 1))
    else
      break
    fi
  done
  [ "$api_port" -le 18742 ] || { printf '%s\n' 'No local Hermes API port is available.' >&2; exit 1; }
  printf '%s\n' "$api_port" > "$api_port_file"
fi

node_version=24.22.1
node_root="$home/runtime/node-v$node_version-linux-x64"
if [ ! -x "$node_root/bin/node" ]; then
  printf '%s\n' 'Installing private Node 24 runtime...'
  curl -fSL --retry 3 --retry-delay 1 "https://nodejs.org/dist/v$node_version/node-v$node_version-linux-x64.tar.gz" \
    -o "$home/downloads/node-v$node_version-linux-x64.tar.gz"
  tar -xzf "$home/downloads/node-v$node_version-linux-x64.tar.gz" -C "$home/runtime"
fi
export PATH="$node_root/bin:$PATH"
export NEKODOT_HOME="$home"
export HERMES_HOME="$home/hermes"
hermes_version='__NEKODOT_HERMES_RUNTIME__'
payload="$home/hermes-runtimes/$hermes_version"
export HERMES_RUNTIME_DIR="$payload/tools"
export UV_CACHE_DIR="$home/cache/uv"
mkdir -p "$home/cache" "$HERMES_HOME"
if [ ! -e "$HERMES_HOME/cache" ]; then ln -s "$home/cache" "$HERMES_HOME/cache"; fi
export NEKODOT_HERMES_API_PORT="$api_port"
# Hermes's dependency resolver needs upload times, which some system pip mirrors omit.
export UV_INDEX_URL='https://pypi.org/simple'
if [ "$sandbox" = true ]; then
  # The app that made the sandbox keeps the pairing code alive itself.
  printf '%s\n' 'First installation can take several minutes.'
else
  printf '%s\n' 'First installation can take several minutes. Use Add 30 minutes in the app to keep the same pairing code.'
fi
relay_tunnel_pid=''
stop_relay_tunnel() {
  if [ -n "$relay_tunnel_pid" ] && kill -0 "$relay_tunnel_pid" 2>/dev/null; then
    kill "$relay_tunnel_pid" 2>/dev/null || true
    wait "$relay_tunnel_pid" 2>/dev/null || true
  fi
}
trap stop_relay_tunnel EXIT
if [ -n "$relay_ssh" ]; then
  ssh_auth_args=()
  if [ -n "$relay_ssh_key" ]; then
    ssh_auth_args=(-i "$home/ssh/id_ed25519" -o IdentitiesOnly=yes -o "UserKnownHostsFile=$home/ssh/known_hosts")
  fi
  ready=false
  if curl -fsS --max-time 2 "$relay/health" >/dev/null; then ready=true; fi
  if [ "$ready" != true ]; then
    ssh -N -o BatchMode=yes -o StrictHostKeyChecking=yes -o ExitOnForwardFailure=yes \
      -o ServerAliveInterval=15 -o ServerAliveCountMax=3 \
      "${ssh_auth_args[@]}" \
      -L 127.0.0.1:4329:127.0.0.1:4329 "$relay_ssh" \
      >"$home/logs/relay-tunnel.log" 2>&1 &
    relay_tunnel_pid=$!
    for _ in $(seq 1 30); do
      if curl -fsS --max-time 2 "$relay/health" >/dev/null; then ready=true; break; fi
      kill -0 "$relay_tunnel_pid" 2>/dev/null || break
      sleep 1
    done
    [ "$ready" = true ] || { printf '%s\n' 'Could not connect the SSH tunnel to the Relay. Check WSL SSH key and known-host configuration.' >&2; exit 1; }
  fi
fi
if [ ! -x "$payload/bin/hermes" ]; then
  printf 'Hermes %s\n' "$hermes_version"
  archive="$home/downloads/hermes-$hermes_version-linux-x64.tar.gz"
  curl -fsSL --retry 3 "$relay/downloads/hermes/$hermes_version/linux-x64.json" \
    -o "$archive.json"
  bytes=$(node -p "JSON.parse(require('fs').readFileSync(process.argv[1], 'utf8')).bytes" "$archive.json")
  if [ "$(stat -c %s "$archive" 2>/dev/null || printf 0)" != "$bytes" ]; then
    curl -fSL --retry 3 --retry-delay 1 \
      -C - "$relay/downloads/hermes/$hermes_version/linux-x64.tar.gz" -o "$archive"
  fi
  staging="$payload.extract-$(date +%s%N)"
  mkdir -p "$staging"
  tar -xzf "$archive" -C "$staging"
  HERMES_HOME="$home/bootstrap-home" HERMES_RUNTIME_DIR="$staging/tools" "$staging/bin/hermes" --version
  mv "$staging" "$payload"
fi
printf '%s\n' 'Preparing the official Hermes runtime...'
if [ ! -f "$HERMES_HOME/config.yaml" ]; then
  cp "$payload/hermes-agent/cli-config.yaml.example" "$HERMES_HOME/config.yaml"
fi
"$payload/bin/hermes" pm install --extra all
"$payload/bin/hermes" --version
if ! grep -qi microsoft /proc/sys/kernel/osrelease; then
  printf '%s\n' 'Installing the official Hermes computer-use runtime and screen packages...'
  if ! "$payload/bin/hermes" computer-use screen install --yes; then
    printf '%s\n' 'Screen dependencies were not installed. Run the administrator command printed by Hermes, then rerun. Existing data is retained.' >&2
    exit 1
  fi
  "$payload/bin/hermes" computer-use install
  # The native screen package set does not include Chromium's audio shared library.
  if command -v apt-get >/dev/null && ! ldconfig -p 2>/dev/null | grep -F 'libasound.so.2' >/dev/null; then
    . /etc/os-release
    audio_package=libasound2
    if [ "$ID" = ubuntu ] && [ "$VERSION_ID" = 24.04 ]; then audio_package=libasound2t64; fi
    printf 'Chromium requires an OS library. Administrator command: apt-get install -y --no-install-recommends %s\n' "$audio_package"
    if [ "$(id -u)" -eq 0 ]; then apt-get install -y --no-install-recommends "$audio_package"
    elif command -v sudo >/dev/null && sudo -n true 2>/dev/null; then sudo -n apt-get install -y --no-install-recommends "$audio_package"
    else printf '%s\n' 'Ask an administrator to run that command, then rerun. Existing data is retained.' >&2; exit 1
    fi
  fi
fi
curl -fSL --retry 3 --retry-delay 1 "$relay/downloads/nekodot-node.cjs" -o "$home/bin/nekodot-node.cjs.install-$$"
mv -f "$home/bin/nekodot-node.cjs.install-$$" "$home/bin/nekodot-node.cjs"
mkdir -p "$home/bin/recycle"
for marker in update-pending update-tried update-rejected; do
  if [ -f "$home/bin/$marker" ]; then
    mv "$home/bin/$marker" "$home/bin/recycle/$marker-$(date +%s%N)"
  fi
done
cat > "$home/bin/nekodot-node" <<EOF
#!/usr/bin/env bash
set -e
export NEKODOT_HOME='$home'
export NEKODOT_HERMES_LAUNCHER='$payload/bin/hermes'
export NEKODOT_HERMES_RUNTIME='$HERMES_RUNTIME_DIR'
export UV_CACHE_DIR='$UV_CACHE_DIR'
export NEKODOT_HERMES_API_PORT='$api_port'
export UV_INDEX_URL='https://pypi.org/simple'
export PATH='$node_root/bin':\$PATH
bin='$home/bin'
if [ "\${1:-}" = run ] && [ -f "\$bin/update-pending" ]; then
  if [ -f "\$bin/update-tried" ]; then
    mv -f "\$bin/nekodot-node.cjs.previous" "\$bin/nekodot-node.cjs"
    mkdir -p "\$bin/recycle"
    if [ -f "\$bin/update-rejected" ]; then
      mv "\$bin/update-rejected" "\$bin/recycle/update-rejected-\$(date +%s%N)"
    fi
    mv "\$bin/update-pending" "\$bin/update-rejected"
    mv "\$bin/update-tried" "\$bin/recycle/update-tried-\$(date +%s%N)"
    printf '%s\n' 'Node update did not become ready; restored the previous release.' >&2
  else
    : > "\$bin/update-tried"
  fi
fi
exec '$node_root/bin/node' '$home/bin/nekodot-node.cjs' "\$@"
EOF
chmod 700 "$home/bin/nekodot-node"
if [ ! -f "$home/node.json" ]; then
  name_args=()
  if [ -n "$node_name" ]; then name_args=(--name "$node_name"); fi
  if ! "$home/bin/nekodot-node" pair --relay "$relay" --code "$pair_code" "${name_args[@]}"; then
    printf '%s\n' 'Pairing did not complete. Extend this code in the app and rerun the same command, or generate a new code. Installed dependencies are retained.' >&2
    exit 1
  fi
else
  # One-time official endpoint cutover; self-hosted addresses and identity stay unchanged.
  node - "$home/node.json" "$relay" <<'NODE'
const fs = require('node:fs');
const [file, target] = process.argv.slice(2);
const data = JSON.parse(fs.readFileSync(file, 'utf8'));
if (target === 'https://api.nekodot.com' && data.relayUrl.replace(/\/+$/, '') === 'https://nekodot.com') {
  const backup = file + '.before-api-domain';
  if (!fs.existsSync(backup)) fs.copyFileSync(file, backup);
  fs.chmodSync(backup, 0o600);
  data.relayUrl = target;
  fs.writeFileSync(file, JSON.stringify(data, null, 2) + '\n', { mode: 0o600 });
}
NODE
  printf '%s\n' 'Keeping the existing node identity and history; pairing code was not consumed.'
fi
if [ "$sandbox" = true ]; then
  # No systemd here: a loop restarts the node after an update (exit 75) or a
  # crash, and a clean stop (exit 0) ends it.
  # Each run is its own process group, so what the node started (Hermes and
  # its gateway) ends with it before the next run, as systemd would do.
  cat > "$home/bin/nekodot-supervise" <<EOF
#!/usr/bin/env bash
node=''
end_run() {
  [ -n "\$node" ] || return 0
  kill -TERM -- "-\$node" 2>/dev/null
  # The node gets 20 seconds to stop Hermes itself; then the rest is killed.
  ( sleep 20; kill -KILL -- "-\$node" 2>/dev/null ) &
  guard=\$!
  wait "\$node" 2>/dev/null
  kill -KILL -- "-\$node" 2>/dev/null
  kill "\$guard" 2>/dev/null
  node=''
}
trap 'end_run; exit 0' TERM INT
while true; do
  setsid '$home/bin/nekodot-node' run >> '$home/logs/node.log' 2>&1 &
  node=\$!
  wait "\$node"
  code=\$?
  end_run
  [ "\$code" -eq 0 ] && break
  sleep 3
done
EOF
  # Starts the supervisor unless it is running; the app runs it again after
  # the sandbox has been stopped and started.
  cat > "$home/bin/nekodot-start" <<EOF
#!/usr/bin/env bash
pid="\$(cat '$home/nekodot-supervise.pid' 2>/dev/null || true)"
if [ -n "\$pid" ] && grep -q nekodot-supervise "/proc/\$pid/cmdline" 2>/dev/null; then exit 0; fi
setsid nohup '$home/bin/nekodot-supervise' > /dev/null 2>&1 < /dev/null &
pid=\$!
# Return only once it leads its own session, so that it outlives whatever
# ran this script, such as a sandbox command that has just ended.
for _ in \$(seq 1 50); do
  [ "\$(awk '{ print \$6 }' "/proc/\$pid/stat" 2>/dev/null)" = "\$pid" ] && break
  sleep 0.1
done
printf '%s\n' "\$pid" > '$home/nekodot-supervise.pid'
EOF
  chmod 700 "$home/bin/nekodot-supervise" "$home/bin/nekodot-start"
  # A rerun starts the freshly installed node.
  stop_supervisor
  seen=0
  if [ -f "$home/logs/node.log" ]; then seen="$(wc -l < "$home/logs/node.log")"; fi
  printf '%s\n' 'Starting Hermes and waiting for the node to connect to Relay (up to 5 minutes)...'
  "$home/bin/nekodot-start"
  for _ in $(seq 1 150); do
    # No pipe: under pipefail an early-exiting grep would read as a failure.
    if [ -f "$home/logs/node.log" ] &&
       awk -v from="$((seen + 1))" 'NR >= from && /"online":true/ { found = 1; exit } END { exit !found }' "$home/logs/node.log"; then
      printf '%s\n' 'Node connected to Relay. Return to the app; this sandbox is now online.'
      exit 0
    fi
    sleep 2
  done
  printf '%s\n' 'The node has not connected. Pairing and installed files are retained. Startup logs:' >&2
  tail -n 30 "$home/logs/node.log" >&2 || true
  if [ -f "$home/logs/hermes.log" ]; then tail -n 40 "$home/logs/hermes.log" >&2; fi
  exit 1
fi
if [ "$(loginctl show-user "$(id -un)" -p Linger --value)" != yes ]; then
  if [ "$(id -u)" -eq 0 ]; then loginctl enable-linger "$(id -un)"
  else
    command -v sudo >/dev/null || {
      printf 'An administrator must enable service linger: loginctl enable-linger %s\n' "$(id -un)" >&2
      exit 1
    }
    sudo loginctl enable-linger "$(id -un)" </dev/tty || exit 1
  fi
fi
unit_dir="$HOME/.config/systemd/user"
mkdir -p "$unit_dir"
node_dependencies='After=network-online.target'
if [ -n "$relay_ssh" ]; then
  ssh_options=''
  if [ -n "$relay_ssh_key" ]; then
    printf -v ssh_options '%q ' -i "$home/ssh/id_ed25519" -o IdentitiesOnly=yes -o "UserKnownHostsFile=$home/ssh/known_hosts"
  fi
  printf -v quoted_target '%q' "$relay_ssh"
  cat > "$home/bin/nekodot-relay-tunnel" <<EOF
#!/usr/bin/env bash
exec ssh -N -o BatchMode=yes -o StrictHostKeyChecking=yes -o ExitOnForwardFailure=yes -o ServerAliveInterval=15 -o ServerAliveCountMax=3 $ssh_options -L 127.0.0.1:4329:127.0.0.1:4329 $quoted_target
EOF
  chmod 700 "$home/bin/nekodot-relay-tunnel"
  cat > "$unit_dir/nekodot-relay-tunnel.service" <<EOF
[Unit]
Description=nekodot Relay SSH tunnel
After=network-online.target

[Service]
ExecStart="$home/bin/nekodot-relay-tunnel"
Restart=on-failure
RestartSec=3

[Install]
WantedBy=default.target
EOF
  node_dependencies='After=network-online.target nekodot-relay-tunnel.service
Requires=nekodot-relay-tunnel.service'
fi
cat > "$unit_dir/nekodot-node.service" <<EOF
[Unit]
Description=nekodot node
$node_dependencies

[Service]
Type=notify
NotifyAccess=all
TimeoutStartSec=300
ExecStart="$home/bin/nekodot-node" run
WorkingDirectory=$home
Restart=on-failure
RestartSec=3
KillMode=mixed
TimeoutStopSec=20

[Install]
WantedBy=default.target
EOF
systemctl --user daemon-reload
if [ -n "$relay_ssh" ]; then
  stop_relay_tunnel
  relay_tunnel_pid=''
  systemctl --user enable --now nekodot-relay-tunnel.service
fi
systemctl --user enable nekodot-node.service
printf '%s\n' 'Starting Hermes and waiting for the node to connect to Relay (up to 5 minutes)...'
if ! systemctl --user restart nekodot-node.service; then
  printf '%s\n' 'The node has not connected. Pairing and installed files are retained. Startup logs:' >&2
  journalctl --user -u nekodot-node.service -n 30 --no-pager >&2
  if [ -f "$home/logs/hermes.log" ]; then tail -n 40 "$home/logs/hermes.log" >&2; fi
  printf '%s\n' 'After resolving the error, rerun the same install command. Do not delete the installation directory.' >&2
  exit 1
fi
printf '%s\n' 'Node connected to Relay. Return to the app; this server is now online.'
