#!/usr/bin/env bash
# Unattended install + configure of AdGuard Home as a split-DNS resolver.
#
# What it does:
#   1. Frees port 53 from systemd-resolved's stub listener.
#   2. Installs AdGuard Home (official script) if not already installed.
#   3. Finishes the first-run setup wizard via the REST API (no browser needed).
#   4. Configures split upstream forwarding:
#        - RU domains/CDNs  -> Yandex DNS (correct ECS/edge routing inside RU)
#        - everything else  -> Quad9 / Mullvad / Cloudflare DoH/DoT, resolved
#                               straight from this EU server (not from RU, so
#                               RU ISP-level DNS injection never applies to it)
#   5. Opens port 53 (tcp/udp) in ufw.
#
# Re-running is safe: if AdGuard Home is already set up, it reuses the saved
# admin credentials and just re-applies the DNS settings below.
#
# Usage:
#   sudo bash install.sh
#   ADGUARD_ADMIN_PASSWORD='...' sudo -E bash install.sh   # pin the admin password

set -euo pipefail

ADGUARD_DIR=/opt/AdGuardHome
ADGUARD_BIN="$ADGUARD_DIR/AdGuardHome"
ADGUARD_YAML="$ADGUARD_DIR/AdGuardHome.yaml"
CREDS_FILE=/root/.adguardhome_admin_credentials
WEB_ADDR=127.0.0.1
WEB_PORT=9007
DNS_PORT=53
ADMIN_USER="${ADGUARD_ADMIN_USER:-slaweekq}"
ADMIN_PASS="${ADGUARD_ADMIN_PASSWORD:-}"

# Domains routed to Yandex DNS for correct in-RU CDN edge selection.
RU_DOMAINS="ru/su/xn--p1ai/yandex.net/yandex.ru/yastatic.net/mail.ru/vk.com/vk.ru/vk-cdn.net/userapi.com/ok.ru/sberbank.ru/sber.ru/ozon.ru/wildberries.ru/avito.ru/rutube.ru/kinopoisk.ru/2gis.ru/mts.ru/beeline.ru/megafon.ru/tinkoff.ru/gosuslugi.ru/dzen.ru"

log() { echo "[adguard-home] $*"; }
die() {
    echo "[adguard-home] ERROR: $*" >&2
    exit 1
}

[[ $EUID -eq 0 ]] || die "run as root: sudo bash install.sh"
command -v systemctl >/dev/null 2>&1 || die "systemd is required"
command -v curl >/dev/null 2>&1 || sudo apt update && sudo apt install -y curl

log "Freeing port 53 from systemd-resolved's stub listener..."
mkdir -p /etc/systemd/resolved.conf.d
cat >/etc/systemd/resolved.conf.d/adguardhome.conf <<'EOF'
[Resolve]
DNS=127.0.0.1
DNSStubListener=no
EOF
systemctl reload-or-restart systemd-resolved 2>/dev/null || true

if [[ -f /etc/resolv.conf && ! -L /etc/resolv.conf ]]; then
    cp /etc/resolv.conf /etc/resolv.conf.backup-adguardhome
fi
ln -sf /run/systemd/resolve/resolv.conf /etc/resolv.conf

for _ in $(seq 1 10); do
    ss -H -ltnu 2>/dev/null | awk '{print $5}' | grep -q ':53$' || break
    sleep 1
done
if ss -H -ltnu 2>/dev/null | awk '{print $5}' | grep -q ':53$'; then
    die "port 53 is still in use, check: ss -ltnup | grep :53"
fi

if [[ ! -x "$ADGUARD_BIN" ]]; then
    log "Installing AdGuard Home..."
    curl -s -S -L https://raw.githubusercontent.com/AdguardTeam/AdGuardHome/master/scripts/install.sh | sh -s -- -v
else
    log "AdGuard Home binary already present, skipping download."
fi
systemctl enable --now AdGuardHome >/dev/null 2>&1 || true

log "Waiting for AdGuard Home web interface on :$WEB_PORT..."
for _ in $(seq 1 30); do
    curl -s -o /dev/null "http://127.0.0.1:${WEB_PORT}/" && break
    sleep 1
done

if [[ -z "$ADMIN_PASS" ]]; then
    ADMIN_PASS=$(openssl rand -base64 18)
fi

CONFIGURE_HTTP_CODE=$(curl -s -o /tmp/agh_configure_resp.json -w "%{http_code}" \
    -X POST "http://127.0.0.1:${WEB_PORT}/control/install/configure" \
    -H "Content-Type: application/json" \
    -d "{\"dns\":{\"ip\":\"0.0.0.0\",\"port\":${DNS_PORT}},\"web\":{\"ip\":\"${WEB_ADDR}\",\"port\":${WEB_PORT}},\"username\":\"${ADMIN_USER}\",\"password\":\"${ADMIN_PASS}\"}")

if [[ "$CONFIGURE_HTTP_CODE" == "200" ]]; then
    log "First-run setup complete, admin user '${ADMIN_USER}' created."
    umask 077
    cat >"$CREDS_FILE" <<EOF
ADGUARD_ADMIN_USER=${ADMIN_USER}
ADGUARD_ADMIN_PASSWORD=${ADMIN_PASS}
EOF
    chmod 600 "$CREDS_FILE"
elif [[ -f "$CREDS_FILE" ]]; then
    log "Already configured, reusing saved credentials from ${CREDS_FILE}."
    # shellcheck disable=SC1090
    source "$CREDS_FILE"
    ADMIN_USER="$ADGUARD_ADMIN_USER"
    ADMIN_PASS="$ADGUARD_ADMIN_PASSWORD"
else
    log "AdGuard Home is already configured but ${CREDS_FILE} is missing."
    log "Skipping automatic DNS setup — configure upstreams manually in the web UI,"
    log "or remove ${ADGUARD_YAML} and re-run this script to redo the wizard."
    exit 0
fi

log "Applying split-DNS upstream configuration..."
AUTH_HEADER="Authorization: Basic $(printf '%s:%s' "$ADMIN_USER" "$ADMIN_PASS" | base64 -w0)"

DNS_CONFIG_JSON=$(
    cat <<JSON
{
  "upstream_dns": [
    "[/${RU_DOMAINS}/]77.88.8.8",
    "[/${RU_DOMAINS}/]77.88.8.1",
    "https://dns.quad9.net/dns-query",
    "https://dns.mullvad.net/dns-query",
    "tls://one.one.one.one"
  ],
  "bootstrap_dns": ["9.9.9.9", "1.1.1.1"],
  "fallback_dns": ["9.9.9.9"],
  "upstream_mode": "parallel",
  "ratelimit": 100,
  "edns_cs_enabled": true,
  "edns_cs_use_custom": false
}
JSON
)

DNS_CONFIG_HTTP_CODE=$(curl -s -o /tmp/agh_dns_config_resp.json -w "%{http_code}" \
    -X POST "http://127.0.0.1:${WEB_PORT}/control/dns_config" \
    -H "$AUTH_HEADER" -H "Content-Type: application/json" \
    -d "$DNS_CONFIG_JSON")

[[ "$DNS_CONFIG_HTTP_CODE" == "200" ]] || die "dns_config API call failed (HTTP ${DNS_CONFIG_HTTP_CODE}), see /tmp/agh_dns_config_resp.json"
log "Split-DNS upstreams applied."

if command -v ufw >/dev/null 2>&1; then
    ufw allow 53/tcp comment 'AdGuard Home DNS' >/dev/null || true
    ufw allow 53/udp comment 'AdGuard Home DNS' >/dev/null || true
    log "Opened 53/tcp and 53/udp in ufw."
fi

PUBLIC_IP=$(curl -s -4 https://ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')

cat <<SUMMARY

============================================================
AdGuard Home is up.

  DNS server (point your router here):  ${PUBLIC_IP}:53
  Admin web UI (loopback only):         http://127.0.0.1:${WEB_PORT}
    -> access remotely via SSH tunnel:
       ssh -L 9007:127.0.0.1:9007 <user>@${PUBLIC_IP}
  Admin credentials saved at:           ${CREDS_FILE}

WARNING: port 53 is open to the whole internet on this host
(TP-Link's stock firmware only supports plain DNS, no DoT/DoH,
so this is the only way to point a whole-router DNS at it).
That makes it a public resolver — ratelimit=100qps is on, but
consider restricting it later (ufw allow from <your-ISP-IP> to
any port 53) once you know your home IP is stable.
============================================================
SUMMARY
