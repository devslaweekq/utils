#!/usr/bin/env bash
set -euo pipefail

# Simple one-file installer for Telemt MTProto proxy (Docker)
# - Installs Docker if needed
# - Creates /root/mtproxy-telemt
# - Generates docker-compose.yml and telemt.toml
# - Configures two users with independent random secrets
# - Binds container port 443 to host port 443 (for HTTPS masking)

TARGET_DIR="/root/mtproxy-telemt"

if [ "$EUID" -ne 0 ]; then
  echo "Run this script as root, for example: sudo $0"
  exit 1
fi

echo "Checking Docker..."

if ! command -v docker >/dev/null 2>&1; then
  echo "Docker is not installed, installing..."
  apt update -y
  apt install -y docker.io docker-compose-plugin
fi

if ! docker --version >/dev/null 2>&1; then
  echo "Docker is not available after installation, aborting."
  exit 1
fi

if ! docker compose version >/dev/null 2>&1; then
  echo "Docker Compose plugin is not available, aborting."
  exit 1
fi

echo "Checking that host port 443 is free..."
if ss -tulpn 2>/dev/null | grep -qE 'LISTEN.+:443[[:space:]]'; then
  echo "Error: host port 443 is already in use."
  echo "Current listeners on 443:"
  ss -tulpn 2>/dev/null | grep -E 'LISTEN.+:443[[:space:]]' || true
  echo "Stop the service that uses port 443 and run this installer again."
  exit 1
fi

echo "Generating secrets for users..."
SECRET_1="$(openssl rand -hex 16)"
SECRET_2="$(openssl rand -hex 16)"
echo "Secrets:"
echo "  user1: ${SECRET_1}"
echo "  user2: ${SECRET_2}"

echo "Preparing directory..."
mkdir -p "${TARGET_DIR}"

echo "Writing docker-compose.yml..."
cat > "${TARGET_DIR}/docker-compose.yml" <<EOF
services:
  telemt:
    image: whn0thacked/telemt-docker:latest
    container_name: telemt
    restart: unless-stopped
    environment:
      RUST_LOG: "info"
    volumes:
      - ./telemt.toml:/etc/telemt.toml:ro
    ports:
      - "443:443/tcp"
    security_opt:
      - no-new-privileges:true
    cap_drop:
      - ALL
    cap_add:
      - NET_BIND_SERVICE
    read_only: true
    tmpfs:
      - /tmp:rw,nosuid,nodev,noexec,size=16m
    deploy:
      resources:
        limits:
          cpus: "0.50"
          memory: 256M

EOF

echo "Writing telemt.toml..."
cat > "${TARGET_DIR}/telemt.toml" <<EOF
# telemt.toml

# Which users will have a t.me link generated.
show_link = ["user1","user2"]

[general]
prefer_ipv6 = false
fast_mode = true
use_middle_proxy = false

[general.modes]
classic = false
secure = false
tls = true

[server]
port = 443
listen_addr_ipv4 = "0.0.0.0"
listen_addr_ipv6 = "::"

[censorship]
# Domain used in SNI. Replace with a real popular HTTPS site if needed.
tls_domain = "1c.ru"
# Enable masking by proxying the real site above.
mask = true
mask_port = 443
fake_cert_len = 2048

[access.users]
user1 = "${SECRET_1}"
user2 = "${SECRET_2}"

[[upstreams]]
type = "direct"
enabled = true
weight = 10
EOF

echo "Starting Telemt via docker compose..."

cd "${TARGET_DIR}"
docker compose pull
docker compose up -d

echo "Container logs with proxy links (if available):"
docker compose logs 2>/dev/null | grep "tg://proxy" || echo "No links found in logs yet."

echo "Done."
echo "Config directory: ${TARGET_DIR}"
echo "Users: user1, user2"
echo "Secrets:"
echo "  user1: ${SECRET_1}"
echo "  user2: ${SECRET_2}"
echo "Host port: 443 -> container port 443"

SERVER_IP="$(curl -s https://api.ipify.org || hostname -I | awk '{print $1}')"
echo
echo "To verify masking manually, you can run from anywhere on the Internet:"
echo "  curl -v -I --resolve 1c.ru:443:${SERVER_IP} https://1c.ru/"
echo "If the response shows a valid *.1c.ru certificate and HTTP/1.1 200 OK, masking works."
