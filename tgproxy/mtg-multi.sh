#!/usr/bin/env bash
# cd ~
# curl -o mtg-multi.sh https://raw.githubusercontent.com/devslaweekq/utils/main/tgproxy/mtg-multi.sh
# chmod +x mtg-multi.sh
# sudo ./mtg-multi.sh [port]        # install / upgrade
# sudo ./mtg-multi.sh -d|--delete   # fully remove
#
# Automatic install of mtg-multi (https://github.com/MHSanaei/mtg-multi) -
# a multi-user Telegram MTProto proxy - as a systemd service on Ubuntu.
# Generates a secret, opens the port (if ufw is active) and prints a
# ready-to-use tg://proxy link at the end.
#
# Re-running the script upgrades the binary and restarts the service
# without touching the existing secret/port (config is left as-is).
# Pass -d/--delete to stop the service and remove everything it installed.

set -euo pipefail

REPO="MHSanaei/mtg-multi"
BIN_PATH="/usr/local/bin/mtg-multi"
CONFIG_DIR="/etc/mtg-multi"
CONFIG_PATH="${CONFIG_DIR}/config.toml"
SERVICE_PATH="/etc/systemd/system/mtg-multi.service"
API_BIND="127.0.0.1:9090"
FRONT_DOMAIN="${FRONT_DOMAIN:-storage.googleapis.com}"

info()  { printf "\033[1;34m[INFO]\033[0m %s\n" "$*"; }
warn()  { printf "\033[1;33m[WARN]\033[0m %s\n" "$*"; }
error() { printf "\033[1;31m[ERR ]\033[0m %s\n" "$*"; }

if [[ $EUID -ne 0 ]]; then
  error "Run this script as root, for example: sudo $0"
  exit 1
fi

if [[ -f /etc/os-release ]]; then
  . /etc/os-release
  if [[ "${ID:-}" != "ubuntu" && "${ID_LIKE:-}" != *"ubuntu"* ]]; then
    warn "This script was tested on Ubuntu. Continuing at your own risk."
  fi
fi

port_in_use() {
  local out
  out="$(ss -H -tln "( sport = :$1 )" 2>/dev/null || true)"
  [[ -n "$out" ]]
}

# Try 443, then 7443, then ask the user for a port until a free one is given.
pick_port() {
  local p
  for p in 443 7443; do
    if ! port_in_use "$p"; then
      echo "$p"
      return 0
    fi
    warn "Port $p is already in use, trying the next candidate..." >&2
  done
  while true; do
    read -r -p "Ports 443 and 7443 are both busy. Enter a port to use (1-65535): " custom
    if [[ "$custom" =~ ^[0-9]+$ ]] && (( custom >= 1 && custom <= 65535 )); then
      if port_in_use "$custom"; then
        warn "Port $custom is also busy, try another one." >&2
      else
        echo "$custom"
        return 0
      fi
    else
      warn "Enter a valid port number." >&2
    fi
  done
}

detect_asset_arch() {
  case "$(uname -m)" in
    x86_64) echo "amd64" ;;
    aarch64|arm64) echo "arm64" ;;
    armv7l) echo "armv7" ;;
    armv6l) echo "armv6" ;;
    armv5*) echo "armv5" ;;
    i386|i686) echo "386" ;;
    s390x) echo "s390x" ;;
    *) error "Unsupported architecture: $(uname -m)"; exit 1 ;;
  esac
}

config_port() {
  [[ -f "$CONFIG_PATH" ]] || return 0
  grep -m1 '^bind-to' "$CONFIG_PATH" | grep -oE ':[0-9]+"' | tr -d ':"' || true
}

uninstall() {
  local port
  port="$(config_port)"

  local have_service=false have_bin=false have_config=false
  [[ -f "$SERVICE_PATH" ]] && have_service=true
  [[ -f "$BIN_PATH" ]] && have_bin=true
  [[ -d "$CONFIG_DIR" ]] && have_config=true

  if ! $have_service && ! $have_bin && ! $have_config; then
    info "Nothing to remove - mtg-multi is not installed."
    exit 0
  fi

  echo "This will remove:"
  $have_service && echo "  - the mtg-multi systemd service"
  $have_bin && echo "  - the binary at ${BIN_PATH}"
  $have_config && echo "  - the config directory ${CONFIG_DIR} (including the secret!)"
  if [[ -n "$port" ]] && command -v ufw >/dev/null 2>&1 && ufw status | grep -q "Status: active"; then
    echo "  - the ufw rule for ${port}/tcp"
  fi

  read -r -p "Are you sure? [y/N] " confirm
  if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    info "Aborted, nothing was removed."
    exit 0
  fi

  if $have_service; then
    info "Stopping and disabling the service..."
    systemctl stop mtg-multi 2>/dev/null || true
    systemctl disable mtg-multi 2>/dev/null || true
    rm -f "$SERVICE_PATH"
    systemctl daemon-reload
    systemctl reset-failed mtg-multi 2>/dev/null || true
  fi

  if [[ -n "$port" ]] && command -v ufw >/dev/null 2>&1 && ufw status | grep -q "Status: active"; then
    info "Removing the ufw rule for ${port}/tcp..."
    ufw --force delete allow "${port}/tcp" >/dev/null 2>&1 || true
  fi

  if $have_bin || $have_config; then
    info "Removing the binary and config..."
    rm -f "$BIN_PATH"
    rm -rf "$CONFIG_DIR"
  fi

  info "mtg-multi has been fully removed."
}

case "${1-}" in
  -d|--delete)
    uninstall
    exit 0
    ;;
  -h|--help)
    cat <<EOF
Usage: sudo $0 [port]        install or upgrade mtg-multi
       sudo $0 -d|--delete   stop and remove mtg-multi entirely

[port] is only used on the first install (auto-picks 443, then 7443, then
asks interactively if both are busy). Later runs upgrade the binary and
leave the existing secret/port untouched.
EOF
    exit 0
    ;;
esac

info "Installing dependencies (curl, tar, iproute2)..."
apt-get update -y -qq
apt-get install -y -qq curl tar iproute2 >/dev/null

ARCH="$(detect_asset_arch)"

info "Looking up the latest mtg-multi release..."
API_RESPONSE="$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest")"
LATEST_TAG="$(printf '%s' "$API_RESPONSE" | grep -m1 '"tag_name"' | sed -E 's/.*"tag_name": *"([^"]+)".*/\1/')"
if [[ -z "$LATEST_TAG" ]]; then
  error "Could not determine the latest mtg-multi release."
  exit 1
fi
VERSION="${LATEST_TAG#v}"
ASSET="mtg-multi-${VERSION}-linux-${ARCH}.tar.gz"
URL="https://github.com/${REPO}/releases/download/${LATEST_TAG}/${ASSET}"

info "Downloading ${ASSET}..."
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
curl -fsSL "$URL" -o "${TMP_DIR}/mtg-multi.tar.gz"
tar -xzf "${TMP_DIR}/mtg-multi.tar.gz" -C "$TMP_DIR"

BIN_SRC="$(find "$TMP_DIR" -type f -name mtg-multi | head -n1)"
if [[ -z "$BIN_SRC" ]]; then
  error "mtg-multi binary not found inside the downloaded archive."
  exit 1
fi

install -m 755 "$BIN_SRC" "$BIN_PATH"
info "mtg-multi ${LATEST_TAG} installed to ${BIN_PATH}"

mkdir -p "$CONFIG_DIR"

if [[ -f "$CONFIG_PATH" ]]; then
  info "Existing config found at ${CONFIG_PATH} - keeping the current secret and port (this is an upgrade run)."
else
  if [[ -n "${1-}" ]]; then
    PORT="$1"
    if ! [[ "$PORT" =~ ^[0-9]+$ ]] || (( PORT < 1 || PORT > 65535 )); then
      error "Invalid port: $PORT"
      exit 1
    fi
    if port_in_use "$PORT"; then
      error "Port $PORT is already in use. Free it, or re-run without an argument to auto-pick a port."
      exit 1
    fi
  else
    PORT="$(pick_port)"
  fi
  info "Using port $PORT"

  info "Generating a secret (fronting domain: ${FRONT_DOMAIN})..."
  SECRET="$("$BIN_PATH" generate-secret --hex "$FRONT_DOMAIN")"

  cat > "$CONFIG_PATH" <<EOF
bind-to = "0.0.0.0:${PORT}"
api-bind-to = "${API_BIND}"

[secrets]
default = "${SECRET}"
EOF
fi

# The service runs as the unprivileged "nobody" user, so it must own the
# config file to be able to read it (root:root 600 would lock it out).
chown nobody:nogroup "$CONFIG_PATH"
chmod 600 "$CONFIG_PATH"

PORT="$(config_port)"

info "Creating the systemd service..."
cat > "$SERVICE_PATH" <<EOF
[Unit]
Description=mtg-multi (Telegram MTProto proxy)
After=network.target

[Service]
Type=simple
ExecStart=${BIN_PATH} run ${CONFIG_PATH}
Restart=on-failure
RestartSec=2
User=nobody
AmbientCapabilities=CAP_NET_BIND_SERVICE
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now mtg-multi
systemctl restart mtg-multi

sleep 1
if ! systemctl is-active --quiet mtg-multi; then
  error "mtg-multi service failed to start. Check: systemctl status mtg-multi, journalctl -u mtg-multi -e"
  exit 1
fi

if command -v ufw >/dev/null 2>&1 && ufw status | grep -q "Status: active"; then
  info "ufw is active, opening port ${PORT}/tcp..."
  ufw allow "${PORT}/tcp" >/dev/null
else
  warn "ufw is not active (or not installed) - if you use a firewall/cloud security group, open port ${PORT}/tcp there manually."
fi

SERVER_IP="$(curl -fsS https://api.ipify.org || hostname -I | awk '{print $1}')"

echo
info "Done! mtg-multi is running and enabled at boot."
echo
echo "=== Telegram proxy link ==="
"$BIN_PATH" access --ipv4 "$SERVER_IP" "$CONFIG_PATH"
echo
info "Config: ${CONFIG_PATH} | Binary: ${BIN_PATH} | Logs: journalctl -u mtg-multi -f"
info "This is a minimal config (one secret, no quotas/ad-tag/limits) - let's tune the rest together if you want."
