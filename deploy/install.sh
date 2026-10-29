#!/usr/bin/env bash
set -euo pipefail
umask 077

relay='__NEKODOT_RELAY_URL__'
home="${NEKODOT_HOME:-$HOME/.nekodot}"
pair_code=''
relay_ssh=''
relay_ssh_key=''
relay_ssh_known_hosts=''
uninstall=false
with_computer=false
while [ "$#" -gt 0 ]; do
  case "$1" in
    --pair|--relay|--relay-ssh|--relay-ssh-key|--relay-ssh-known-hosts)
      [ "$#" -ge 2 ] || { printf '%s requires a value\n' "$1" >&2; exit 2; }
      case "$1" in
        --pair) pair_code="$2" ;;
        --relay) relay="$2" ;;
        --relay-ssh) relay_ssh="$2" ;;
        --relay-ssh-key) relay_ssh_key="$2" ;;
        --relay-ssh-known-hosts) relay_ssh_known_hosts="$2" ;;
      esac
      shift 2 ;;
    --uninstall) uninstall=true; shift ;;
    --with-computer) with_computer=true; shift ;;
    --help)
      printf '%s\n' 'Usage: install.sh --pair ABCD-2345 [--relay http://127.0.0.1:4329]' \
        '       install.sh --with-computer  (Linux VPS: install native Hermes screen dependencies)' \
        '       install.sh --uninstall  (stop and disable; retain all files and history)'
      exit 0 ;;
    *) printf 'Unknown option: %s\n' "$1" >&2; exit 2 ;;
  esac
done

[ "$(uname -s)" = Linux ] && [ "$(uname -m)" = x86_64 ] || {
  printf '%s\n' 'Supported: Linux x64. On Windows, run this command inside WSL2 Ubuntu 24.04.' >&2
  exit 1
}
command -v systemctl >/dev/null && [ -d /run/systemd/system ] || {
  printf '%s\n' 'systemd is required. For WSL2, enable systemd and restart your WSL instance first.' >&2
  exit 1
}
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
export DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=$XDG_RUNTIME_DIR/bus}"
if [ "$uninstall" = true ]; then
  systemctl --user disable --now nekodot-node.service
  if [ -f "$HOME/.config/systemd/user/nekodot-relay-tunnel.service" ]; then
    systemctl --user disable --now nekodot-relay-tunnel.service
  fi
  printf 'Node service stopped and disabled. All program files, profiles, history and logs remain in %s\n' "$home"
  exit 0
fi
for tool in curl tar git; do
  command -v "$tool" >/dev/null || { printf 'Install %s with your system package manager, then rerun.\n' "$tool" >&2; exit 1; }
done
if ! ldconfig -p 2>/dev/null | grep -qF 'libatomic.so.1'; then
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
    if (exec 3<>"/dev/tcp/127.0.0.1/$api_port") 2>/dev/null; then
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
export HERMES_RUNTIME_DIR="$home/hermes-runtime"
export NEKODOT_HERMES_API_PORT="$api_port"
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
source_dir="$home/hermes-source"
if [ ! -f "$source_dir/scripts/run-in-hermes-env" ]; then
  printf '%s\n' 'Installing isolated Hermes with the official installer...'
  bootstrap="$home/downloads/hermes-install.sh"
  curl -fSL --retry 3 --retry-delay 1 \
    'https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.sh' -o "$bootstrap"
  for stage in prerequisites repository venv python-deps config; do
    bash "$bootstrap" --non-interactive --channel stable \
      --dir "$source_dir" --hermes-home "$HERMES_HOME" --stage "$stage"
  done
fi
printf '%s\n' 'Preparing the official Hermes runtime...'
(cd "$source_dir" && bash scripts/run-in-hermes-env python hermes --version)
if [ "$with_computer" = true ]; then
  if grep -qi microsoft /proc/sys/kernel/osrelease; then
    printf '%s\n' 'Screen support currently requires a Linux VPS; WSL nodes can still use chat.' >&2
    exit 1
  fi
  printf '%s\n' 'Installing the official Hermes computer-use runtime and screen packages...'
  if ! (cd "$source_dir" && bash scripts/run-in-hermes-env python hermes computer-use screen install --yes); then
    printf '%s\n' 'Screen dependencies were not installed. Run the administrator command printed by Hermes, then rerun with --with-computer. Existing data is retained.' >&2
    exit 1
  fi
  (cd "$source_dir" && bash scripts/run-in-hermes-env python hermes computer-use install)
  (cd "$source_dir" && bash scripts/run-in-hermes-env python hermes tools post-setup chromium)
  # The native screen package set does not include Chromium's audio shared library.
  if command -v apt-get >/dev/null && ! ldconfig -p 2>/dev/null | grep -qF 'libasound.so.2'; then
    . /etc/os-release
    audio_package=libasound2
    if [ "$ID" = ubuntu ] && [ "$VERSION_ID" = 24.04 ]; then audio_package=libasound2t64; fi
    printf 'Chromium requires an OS library. Administrator command: apt-get install -y --no-install-recommends %s\n' "$audio_package"
    if [ "$(id -u)" -eq 0 ]; then apt-get install -y --no-install-recommends "$audio_package"
    elif command -v sudo >/dev/null && sudo -n true 2>/dev/null; then sudo -n apt-get install -y --no-install-recommends "$audio_package"
    else printf '%s\n' 'Ask an administrator to run that command, then rerun --with-computer. Existing data is retained.' >&2; exit 1
    fi
  fi
fi
curl -fSL --retry 3 --retry-delay 1 "$relay/downloads/nekodot-node.cjs" -o "$home/bin/nekodot-node.cjs"
cat > "$home/bin/nekodot-node" <<EOF
#!/usr/bin/env bash
export NEKODOT_HOME='$home'
export NEKODOT_HERMES_SOURCE='$source_dir'
export NEKODOT_HERMES_RUNTIME='$HERMES_RUNTIME_DIR'
export NEKODOT_HERMES_API_PORT='$api_port'
export PATH='$node_root/bin':\$PATH
exec '$node_root/bin/node' '$home/bin/nekodot-node.cjs' "\$@"
EOF
chmod 700 "$home/bin/nekodot-node"
if [ ! -f "$home/node.json" ]; then
  if ! "$home/bin/nekodot-node" pair --relay "$relay" --code "$pair_code"; then
    printf '%s\n' 'Pairing did not complete. Generate a new code and rerun; installed dependencies are retained.' >&2
    exit 1
  fi
else
  printf '%s\n' 'Keeping the existing node identity and history; pairing code was not consumed.'
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
systemctl --user restart nekodot-node.service
printf '%s\n' 'Node service started. Return to the web app; it will show this computer when connected.'
