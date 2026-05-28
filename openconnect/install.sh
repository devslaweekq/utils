#!/usr/bin/env bash
set -euo pipefail

# Automated ocserv (OpenConnect VPN server) install for Ubuntu.
#
# Supports:
# - DOMAIN + Let's Encrypt (recommended)
# - IP-only + self-signed cert (works, but clients will warn unless you trust the CA/cert)
#
# Usage examples:
#   sudo bash openconnect/install.sh --domain vpn.example.com --email admin@example.com --user alice
#   sudo bash openconnect/install.sh --ip-only --user alice
#
# Options via env:
#   VPN_DOMAIN, CERTBOT_EMAIL, VPN_USER, VPN_PORT (default 443), VPN_SUBNET (default 10.10.10.0/24)

VPN_DOMAIN="${VPN_DOMAIN:-}"
CERTBOT_EMAIL="${CERTBOT_EMAIL:-}"
VPN_USER="${VPN_USER:-}"
VPN_PORT="${VPN_PORT:-443}"
VPN_SUBNET="${VPN_SUBNET:-10.10.10.0/24}"
IP_ONLY="${IP_ONLY:-0}"
EXISTING_CERT="${EXISTING_CERT:-}"
EXISTING_KEY="${EXISTING_KEY:-}"
SKIP_CERT="${SKIP_CERT:-0}"
SKIP_PORT_CHECK="${SKIP_PORT_CHECK:-0}"
AUTO_PORT="${AUTO_PORT:-1}"

usage() {
  cat <<'EOF'
ocserv automated installer (Ubuntu)

Required (choose one):
  --domain <vpn.example.com>   Use Let's Encrypt (recommended)
  --ip-only                    Use self-signed certificate (no domain)

Optional:
  --email <admin@example.com>  Email for certbot (Let's Encrypt)
  --user <name>                Create first VPN user (ocpasswd)
  --port <443>                 TCP/UDP port for ocserv (default 443; disables auto port selection)
  --subnet <10.10.10.0/24>     VPN client subnet for NAT (default 10.10.10.0/24)
  --cert <path>                Use existing TLS certificate (PEM)
  --key <path>                 Use existing TLS private key (PEM)
  --skip-cert                  Do not run certbot/openssl (requires --cert/--key or preexisting LE files)
  --skip-port-check            Do not fail if 80/443 are already in use (advanced)

Environment:
  VPN_DOMAIN, CERTBOT_EMAIL, VPN_USER, VPN_PORT, VPN_SUBNET, IP_ONLY=1
  EXISTING_CERT, EXISTING_KEY, SKIP_CERT=1, SKIP_PORT_CHECK=1, AUTO_PORT=1

Examples:
  sudo bash openconnect/install.sh --domain vpn.example.com --email admin@example.com --user alice
  sudo bash openconnect/install.sh --ip-only --user alice
  sudo bash openconnect/install.sh --domain vpn.example.com --cert /etc/letsencrypt/live/vpn.example.com/fullchain.pem --key /etc/letsencrypt/live/vpn.example.com/privkey.pem --skip-cert
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --domain) VPN_DOMAIN="${2:-}"; shift 2;;
    --email) CERTBOT_EMAIL="${2:-}"; shift 2;;
    --user) VPN_USER="${2:-}"; shift 2;;
    --port) VPN_PORT="${2:-}"; AUTO_PORT=0; shift 2;;
    --subnet) VPN_SUBNET="${2:-}"; shift 2;;
    --cert) EXISTING_CERT="${2:-}"; shift 2;;
    --key) EXISTING_KEY="${2:-}"; shift 2;;
    --skip-cert) SKIP_CERT=1; shift;;
    --skip-port-check) SKIP_PORT_CHECK=1; shift;;
    --ip-only) IP_ONLY=1; shift;;
    -h|--help) usage; exit 0;;
    *) echo "Unknown option: $1" >&2; usage; exit 2;;
  esac
done

if [[ "${IP_ONLY}" != "1" && -z "${VPN_DOMAIN}" ]]; then
  echo "ERROR: Provide --domain <name> or use --ip-only" >&2
  exit 2
fi

if [[ "${IP_ONLY}" == "1" && -n "${VPN_DOMAIN}" ]]; then
  echo "ERROR: Use either --ip-only OR --domain, not both" >&2
  exit 2
fi

if [[ -n "${VPN_DOMAIN}" && -z "${CERTBOT_EMAIL}" ]]; then
  if [[ "${SKIP_CERT}" != "1" && -z "${EXISTING_CERT}" && -z "${EXISTING_KEY}" ]]; then
    echo "ERROR: --email is required when using --domain (Let's Encrypt)" >&2
    exit 2
  fi
fi

if [[ $EUID -ne 0 ]]; then
  echo "ERROR: run as root (use sudo)" >&2
  exit 1
fi

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_OCSERV_CONF="${SCRIPT_DIR}/ocserv.conf"

egress_if() {
  ip route get 1.1.1.1 | awk '{print $5; exit}'
}

port_in_use() {
  local port="$1"
  ss -lntH "( sport = :${port} )" 2>/dev/null | grep -q .
}

tcp_port_in_use_any() {
  local port="$1"
  ss -lntH "( sport = :${port} )" 2>/dev/null | grep -q .
}

udp_port_in_use_any() {
  local port="$1"
  ss -lnuH "( sport = :${port} )" 2>/dev/null | grep -q .
}

tcp_port_in_use_by_other_than() {
  # Returns 0 if TCP port is listened by a process NOT matching the given regex.
  # Example: tcp_port_in_use_by_other_than 443 'ocserv'
  local port="$1"
  local allow_regex="$2"
  ss -lntp "( sport = :${port} )" 2>/dev/null | awk 'NR>1{print}' | grep -q . || return 1
  ss -lntp "( sport = :${port} )" 2>/dev/null | awk 'NR>1{print}' | grep -vqE "${allow_regex}"
}

stop_ocserv_and_free_ports() {
  # Ensure we can re-bind the selected port even if a previous ocserv instance is stuck.
  systemctl stop ocserv >/dev/null 2>&1 || true
  pkill -f ocserv >/dev/null 2>&1 || true
}

port_pids() {
  # Print unique PIDs listening on the given port (tcp+udp).
  local port="$1"
  {
    ss -lntup "( sport = :${port} )" 2>/dev/null || true
    ss -lnup "( sport = :${port} )" 2>/dev/null || true
  } \
    | awk '
      {
        while (match($0, /pid=[0-9]+/)) {
          pid = substr($0, RSTART+4, RLENGTH-4)
          print pid
          $0 = substr($0, RSTART+RLENGTH)
        }
      }
    ' \
    | sort -u
}

force_free_port() {
  # Aggressively free target VPN port before installation/restart.
  # This prevents stale listeners from breaking re-installs.
  local port="$1"
  local pids
  pids="$(port_pids "${port}" || true)"
  if [[ -z "${pids}" ]]; then
    return 0
  fi

  echo "INFO: freeing port ${port} (terminating listeners: ${pids//$'\n'/, })"
  while IFS= read -r pid; do
    [[ -n "${pid}" ]] || continue
    kill -TERM "${pid}" >/dev/null 2>&1 || true
  done <<< "${pids}"

  sleep 1

  pids="$(port_pids "${port}" || true)"
  if [[ -n "${pids}" ]]; then
    echo "WARN: forcing kill on remaining listeners at port ${port}: ${pids//$'\n'/, }"
    while IFS= read -r pid; do
      [[ -n "${pid}" ]] || continue
      kill -KILL "${pid}" >/dev/null 2>&1 || true
    done <<< "${pids}"
  fi
}

wait_for_ocserv_listeners() {
  # Wait for ocserv to bind TCP+UDP on selected VPN port.
  local port="$1"
  local timeout_s="${2:-20}"
  local i
  for ((i=1; i<=timeout_s; i++)); do
    if ss -lntH "( sport = :${port} )" 2>/dev/null | grep -q . \
      && ss -lnuH "( sport = :${port} )" 2>/dev/null | grep -q .; then
      return 0
    fi
    sleep 1
  done
  return 1
}

EGRESS_IF="$(egress_if)"
if [[ -z "${EGRESS_IF}" ]]; then
  echo "ERROR: could not detect egress interface" >&2
  exit 1
fi

# Auto-select port when not explicitly provided.
# If 443/tcp is already occupied (common when nginx is on 443), fall back to 8443.
if [[ "${AUTO_PORT}" == "1" ]]; then
  if [[ "${VPN_PORT}" == "443" ]]; then
    # If 443 is in use by anything other than ocserv, avoid it.
    if tcp_port_in_use_by_other_than 443 'ocserv' ; then
      # Allow 8443 if it's only used by ocserv (re-run idempotency).
      if tcp_port_in_use_by_other_than 8443 'ocserv' || (udp_port_in_use_any 8443 && ! ss -lnup "( sport = :8443 )" 2>/dev/null | grep -qE 'ocserv'); then
        echo "ERROR: port 443 is in use, and 8443 is also in use. Provide --port <free_port>." >&2
        exit 2
      fi
      VPN_PORT="8443"
      echo "INFO: port 443 is in use; switching ocserv to ${VPN_PORT} (tcp+udp)"
    fi
  fi
fi

stop_ocserv_and_free_ports
# Always free the selected VPN port before install/start.
# This is especially important for repeated installs on 8443.
force_free_port "${VPN_PORT}"

echo "[1/7] Installing packages"
export DEBIAN_FRONTEND=noninteractive
apt update
apt install -y ocserv ufw

if [[ -n "${VPN_DOMAIN}" ]]; then
  if [[ "${SKIP_CERT}" != "1" && -z "${EXISTING_CERT}" && -z "${EXISTING_KEY}" ]]; then
    apt install -y certbot
  fi
else
  if [[ "${SKIP_CERT}" != "1" && -z "${EXISTING_CERT}" && -z "${EXISTING_KEY}" ]]; then
    apt install -y openssl
  fi
fi

echo "[2/7] Configuring firewall (UFW)"
ufw allow 22/tcp
ufw allow "${VPN_PORT}/tcp"
ufw allow "${VPN_PORT}/udp"
if [[ -n "${VPN_DOMAIN}" ]]; then
  ufw allow 80/tcp
fi
ufw --force enable

echo "[3/7] Preparing TLS certificate"
SERVER_CERT=""
SERVER_KEY=""

if [[ -n "${VPN_DOMAIN}" ]]; then
  if [[ -n "${EXISTING_CERT}" || -n "${EXISTING_KEY}" ]]; then
    if [[ -z "${EXISTING_CERT}" || -z "${EXISTING_KEY}" ]]; then
      echo "ERROR: provide both --cert and --key" >&2
      exit 2
    fi
    if [[ ! -f "${EXISTING_CERT}" || ! -f "${EXISTING_KEY}" ]]; then
      echo "ERROR: --cert/--key path does not exist" >&2
      exit 2
    fi
    SERVER_CERT="${EXISTING_CERT}"
    SERVER_KEY="${EXISTING_KEY}"
  elif [[ -f "/etc/letsencrypt/live/${VPN_DOMAIN}/fullchain.pem" && -f "/etc/letsencrypt/live/${VPN_DOMAIN}/privkey.pem" ]]; then
    # Reuse existing Let's Encrypt cert if present (common when nginx already manages it).
    SERVER_CERT="/etc/letsencrypt/live/${VPN_DOMAIN}/fullchain.pem"
    SERVER_KEY="/etc/letsencrypt/live/${VPN_DOMAIN}/privkey.pem"
  else
    if [[ "${SKIP_CERT}" == "1" ]]; then
      echo "ERROR: --skip-cert set, but no existing cert found for domain and no --cert/--key provided" >&2
      exit 2
    fi

    # If nginx (or anything) is already bound to port 80, certbot --standalone will fail.
    if port_in_use 80 && [[ "${SKIP_PORT_CHECK}" != "1" ]]; then
      echo "ERROR: port 80 is already in use (likely nginx). Cannot run: certbot --standalone" >&2
      echo "Fix options:" >&2
      echo "  - provide --cert/--key (use your existing certificate files), plus --skip-cert" >&2
      echo "  - or obtain/renew cert via your existing nginx/certbot setup, then re-run" >&2
      echo "  - or re-run with --skip-port-check (advanced; may still fail)" >&2
      exit 2
    fi

    # Stop ocserv if running; certbot standalone needs port 80.
    systemctl stop ocserv >/dev/null 2>&1 || true

    certbot certonly --standalone --non-interactive --agree-tos \
      -m "${CERTBOT_EMAIL}" \
      -d "${VPN_DOMAIN}"

    SERVER_CERT="/etc/letsencrypt/live/${VPN_DOMAIN}/fullchain.pem"
    SERVER_KEY="/etc/letsencrypt/live/${VPN_DOMAIN}/privkey.pem"
  fi
else
  if [[ -n "${EXISTING_CERT}" || -n "${EXISTING_KEY}" ]]; then
    if [[ -z "${EXISTING_CERT}" || -z "${EXISTING_KEY}" ]]; then
      echo "ERROR: provide both --cert and --key" >&2
      exit 2
    fi
    if [[ ! -f "${EXISTING_CERT}" || ! -f "${EXISTING_KEY}" ]]; then
      echo "ERROR: --cert/--key path does not exist" >&2
      exit 2
    fi
    SERVER_CERT="${EXISTING_CERT}"
    SERVER_KEY="${EXISTING_KEY}"
  else
    if [[ "${SKIP_CERT}" == "1" ]]; then
      echo "ERROR: --skip-cert set, but no --cert/--key provided (ip-only mode)" >&2
      exit 2
    fi
    install -d -m 0755 /etc/ocserv/ssl
    CN="$(hostname -f 2>/dev/null || hostname)"
    # Best-effort public IP discovery (for IP-only self-signed SAN)
    PUB_IP="$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if ($i=="src") {print $(i+1); exit}}')"
    openssl req -x509 -newkey rsa:4096 -sha256 -days 825 -nodes \
      -keyout /etc/ocserv/ssl/server.key \
      -out /etc/ocserv/ssl/server.crt \
      -subj "/CN=${CN}" \
      -addext "subjectAltName=DNS:${CN},IP:${PUB_IP}" \
      -addext "basicConstraints=critical,CA:FALSE" \
      -addext "keyUsage=critical,digitalSignature,keyEncipherment" \
      -addext "extendedKeyUsage=serverAuth"
    chmod 0600 /etc/ocserv/ssl/server.key
    SERVER_CERT="/etc/ocserv/ssl/server.crt"
    SERVER_KEY="/etc/ocserv/ssl/server.key"
  fi
fi

echo "[4/7] Updating /etc/ocserv/ocserv.conf"
CONF="/etc/ocserv/ocserv.conf"

cp -a "${CONF}" "${CONF}.bak.$(date +%Y%m%d%H%M%S)"

if [[ -f "${REPO_OCSERV_CONF}" ]]; then
  cp -a "${REPO_OCSERV_CONF}" "${CONF}"
fi

set_kv() {
  local key="$1"
  local value="$2"
  if grep -qE "^[[:space:]]*${key}[[:space:]]*=" "${CONF}"; then
    sed -i -E "s|^[[:space:]]*${key}[[:space:]]*=.*|${key} = ${value}|" "${CONF}"
  else
    printf "\n%s = %s\n" "${key}" "${value}" >> "${CONF}"
  fi
}

# Required basics
set_kv "auth" "\"plain[passwd=/etc/ocserv/ocpasswd]\""
set_kv "tcp-port" "${VPN_PORT}"
set_kv "udp-port" "${VPN_PORT}"
set_kv "server-cert" "${SERVER_CERT}"
set_kv "server-key" "${SERVER_KEY}"

# If present in config, keep them consistent; otherwise append.
set_kv "ipv4-network" "\"${VPN_SUBNET%/*}\""
set_kv "ipv4-netmask" "\"255.255.255.0\""

echo "[4/7] Validating ocserv configuration"
if ! ocserv -t -c "${CONF}" >/dev/null 2>&1; then
  echo "ERROR: ocserv config test failed: ${CONF}" >&2
  echo "Tip: run manually for details: sudo ocserv -t -c ${CONF}" >&2
  exit 1
fi

echo "[5/7] Enabling IP forwarding"
echo "net.ipv4.ip_forward=1" > /etc/sysctl.d/60-ocserv.conf
echo "net.ipv6.conf.all.forwarding=1" > /etc/sysctl.d/61-ocserv-ipv6.conf
sysctl --system >/dev/null

echo "[6/7] Enabling NAT for VPN subnet in UFW before.rules"
BEFORE="/etc/ufw/before.rules"
NAT_MARKER_BEGIN="# ocserv-nat-begin"
NAT_MARKER_END="# ocserv-nat-end"
BEFORE6="/etc/ufw/before6.rules"
NAT6_MARKER_BEGIN="# ocserv-nat6-begin"
NAT6_MARKER_END="# ocserv-nat6-end"

validate_ufw_before_rules() {
  # Validate iptables-restore format if possible (iptables-restore --test exists on iptables-nft/legacy).
  if command -v iptables-restore >/dev/null 2>&1; then
    if iptables-restore --test < "${BEFORE}" >/dev/null 2>&1; then
      return 0
    fi
    return 1
  fi
  return 0
}

validate_ufw_before6_rules() {
  if [[ ! -f "${BEFORE6}" ]]; then
    return 0
  fi
  if command -v ip6tables-restore >/dev/null 2>&1; then
    if ip6tables-restore --test < "${BEFORE6}" >/dev/null 2>&1; then
      return 0
    fi
    return 1
  fi
  return 0
}

ensure_ufw_nat_block() {
  # UFW uses iptables-restore format. The *nat table section MUST appear before *filter.
  # We insert a marked *nat block right before the first "*filter" line.
  if grep -qF "${NAT_MARKER_BEGIN}" "${BEFORE}"; then
    return 0
  fi
  if ! grep -q '\*filter' "${BEFORE}"; then
    echo "ERROR: could not find '*filter' table header in ${BEFORE}. File may be corrupted." >&2
    echo "Fix options:" >&2
    echo "  - restore from your backup: /etc/ufw/before.rules.bak.*" >&2
    echo "  - or reinstall ufw configs: sudo apt-get install --reinstall ufw" >&2
    return 1
  fi

  # NOTE: Do NOT use \b in awk regex (mawk treats it as backspace, not word-boundary).
  if ! awk -v subnet="${VPN_SUBNET}" -v eif="${EGRESS_IF}" -v mb="${NAT_MARKER_BEGIN}" -v me="${NAT_MARKER_END}" '
    BEGIN {inserted=0}
    $0 ~ /\\*filter/ && inserted==0 {
      print ""
      print mb
      print "*nat"
      print ":POSTROUTING ACCEPT [0:0]"
      print "-A POSTROUTING -s " subnet " -o " eif " -j MASQUERADE"
      print "COMMIT"
      print me
      inserted=1
    }
    {print}
    END {
      if (inserted==0) exit 2
    }
  ' "${BEFORE}" > "${BEFORE}.tmp"; then
    echo "ERROR: failed to update ${BEFORE} with NAT table" >&2
    return 1
  fi
  mv "${BEFORE}.tmp" "${BEFORE}"
}

ensure_ufw_nat6_block() {
  # Best-effort NAT66 for the IPv6 ULA pool used in ocserv.conf.
  # Only applies when /etc/ufw/before6.rules exists.
  if [[ ! -f "${BEFORE6}" ]]; then
    return 0
  fi
  if grep -qF "${NAT6_MARKER_BEGIN}" "${BEFORE6}"; then
    return 0
  fi
  if ! grep -q '\*filter' "${BEFORE6}"; then
    echo "WARN: could not find '*filter' table header in ${BEFORE6}; skipping IPv6 NAT block" >&2
    return 0
  fi

  if ! awk -v subnet="fd10:10:10::/48" -v eif="${EGRESS_IF}" -v mb="${NAT6_MARKER_BEGIN}" -v me="${NAT6_MARKER_END}" '
    BEGIN {inserted=0}
    $0 ~ /\\*filter/ && inserted==0 {
      print ""
      print mb
      print "*nat"
      print ":POSTROUTING ACCEPT [0:0]"
      print "-A POSTROUTING -s " subnet " -o " eif " -j MASQUERADE"
      print "COMMIT"
      print me
      inserted=1
    }
    {print}
    END { if (inserted==0) exit 2 }
  ' "${BEFORE6}" > "${BEFORE6}.tmp"; then
    echo "WARN: failed to update ${BEFORE6} with IPv6 NAT table; skipping" >&2
    rm -f "${BEFORE6}.tmp" || true
    return 0
  fi
  mv "${BEFORE6}.tmp" "${BEFORE6}"
}

ensure_ufw_forward_rules() {
  # Ensure forwarding accept rules are INSIDE the *filter table, before its COMMIT.
  # Also remove any previously-added rules that might be placed after COMMIT (which breaks iptables-restore).
  #
  # If the expected chain is missing, keep the file valid and skip insertion.
  if ! awk -v subnet="${VPN_SUBNET}" '
    BEGIN {in_filter=0; saw_chain=0; inserted=0}

    # Track entering filter table
    $0 ~ /\\*filter/ {in_filter=1}

    # Detect chain definition
    in_filter && $0 ~ /^:ufw-before-forward([[:space:]]|$)/ {saw_chain=1}

    # Drop any existing rules for this subnet anywhere in the file
    $0 ~ ("^-A ufw-before-forward -s " subnet " -j ACCEPT$") {next}
    $0 ~ ("^-A ufw-before-forward -d " subnet " -j ACCEPT$") {next}

    # Insert rules right before COMMIT inside *filter
    in_filter && saw_chain && $0 ~ /^COMMIT$/ && inserted==0 {
      print "-A ufw-before-forward -s " subnet " -j ACCEPT"
      print "-A ufw-before-forward -d " subnet " -j ACCEPT"
      inserted=1
    }

    {print}
    END {
      if (saw_chain==0) exit 4
      if (inserted==0) exit 3
    }
  ' "${BEFORE}" > "${BEFORE}.tmp"; then
    rc=$?
    rm -f "${BEFORE}.tmp" || true
    if [[ "${rc}" == "4" ]]; then
      echo "WARN: ${BEFORE} does not define ':ufw-before-forward' chain; skipping forward rules insertion" >&2
      return 0
    fi
    echo "ERROR: failed to update ${BEFORE} with forward rules (exit ${rc})" >&2
    return 1
  fi
  mv "${BEFORE}.tmp" "${BEFORE}"
}

# Make before.rules edits transactional
BEFORE_BAK="${BEFORE}.bak.$(date +%Y%m%d%H%M%S)"
cp -a "${BEFORE}" "${BEFORE_BAK}"

ensure_ufw_nat_block
ensure_ufw_forward_rules
ensure_ufw_nat6_block

if ! validate_ufw_before_rules; then
  IPT_ERR="$(iptables-restore --test < "${BEFORE}" 2>&1 || true)"
  echo "ERROR: ${BEFORE} failed iptables-restore validation; restoring backup: ${BEFORE_BAK}" >&2
  if [[ -n "${IPT_ERR}" ]]; then
    echo "iptables-restore output:" >&2
    echo "${IPT_ERR}" >&2
  fi
  FAILED_COPY="/tmp/ufw.before.rules.failed.$(date +%Y%m%d%H%M%S)"
  cp -a "${BEFORE}" "${FAILED_COPY}" >/dev/null 2>&1 || true
  if [[ -f "${FAILED_COPY}" ]]; then
    echo "Saved failing before.rules to: ${FAILED_COPY}" >&2
    LINE="$(
      printf '%s' "${IPT_ERR}" \
        | grep -oE 'line[[:space:]]+[0-9]+' \
        | head -n 1 \
        | awk '{print $2}'
    )"
    if [[ "${LINE}" =~ ^[0-9]+$ ]]; then
      echo "Failing line ${LINE} (from saved file):" >&2
      nl -ba "${FAILED_COPY}" | sed -n "${LINE}p" >&2 || true
      echo "Context around failing line ${LINE}:" >&2
      start=$(( LINE>20 ? LINE-20 : 1 ))
      end=$(( LINE+20 ))
      nl -ba "${FAILED_COPY}" | sed -n "${start},${end}p" >&2 || true
    fi
  fi
  cp -a "${BEFORE_BAK}" "${BEFORE}"
  exit 1
fi

if ! validate_ufw_before6_rules; then
  IPT6_ERR="$(ip6tables-restore --test < "${BEFORE6}" 2>&1 || true)"
  echo "WARN: ${BEFORE6} failed ip6tables-restore validation; keeping previous file" >&2
  if [[ -n "${IPT6_ERR}" ]]; then
    echo "ip6tables-restore output:" >&2
    echo "${IPT6_ERR}" >&2
  fi
fi

systemctl restart ufw
echo "[6/7] NAT rules applied"

echo "[7/7] Starting ocserv"
systemctl enable --now ocserv
systemctl restart ocserv

echo "[7/7] Verifying listener ports"
if ! wait_for_ocserv_listeners "${VPN_PORT}" 20; then
  echo "ERROR: ocserv does not appear to be listening on :${VPN_PORT} (tcp/udp)" >&2
  echo "Current listeners on target port:" >&2
  ss -lntup "( sport = :${VPN_PORT} )" 2>/dev/null >&2 || true
  echo "Tip: check logs: sudo journalctl -u ocserv --no-pager -n 200" >&2
  exit 1
fi

if [[ -n "${VPN_USER}" ]]; then
  echo
  echo "Creating VPN user: ${VPN_USER}"
  ocpasswd -c /etc/ocserv/ocpasswd "${VPN_USER}"
fi

echo
echo "OK. ocserv is installed and running."
echo "- Port: ${VPN_PORT}/tcp and ${VPN_PORT}/udp"
echo "- Client subnet (NAT): ${VPN_SUBNET}"
if [[ -n "${VPN_DOMAIN}" ]]; then
  if [[ "${VPN_PORT}" == "443" ]]; then
    echo "- Connect to: https://${VPN_DOMAIN}"
  else
    echo "- Connect to: https://${VPN_DOMAIN}:${VPN_PORT}"
  fi
else
  if [[ "${VPN_PORT}" == "443" ]]; then
    echo "- Connect to: https://<SERVER_IP> (certificate is self-signed)"
  else
    echo "- Connect to: https://<SERVER_IP>:${VPN_PORT} (certificate is self-signed)"
  fi
fi
