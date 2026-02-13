#!/usr/bin/env bash
set -euo pipefail

# cd ~
# curl -o hys2_install.sh https://raw.githubusercontent.com/devslaweekq/utils/main/hys2/install.sh
# chmod +x hys2_install.sh
# sudo ./hys2_install.sh

# https://habr.com/ru/articles/776402/
# https://v2.hysteria.network/docs/getting-started/Server-Installation-Script/
# https://v2.hysteria.network/docs/advanced/Full-Server-Config/

# Clients:
# https://github.com/apernet/hysteria/releases/tag/app/v2.7.0
# https://v2.hysteria.network/docs/getting-started/3rd-party-apps/
# bash <(curl -fsSL https://get.hy2.sh/) --remove

echo "Installing Hysteria2..."
bash <(curl -fsSL https://get.hy2.sh/)

# Generating passwords (16 hex characters)
PASSWORD1=$(openssl rand -hex 8)
PASSWORD2=$(openssl rand -hex 8)

sudo mkdir -p /etc/hysteria

echo "Creating configuration file..."
sudo tee /etc/hysteria/config.yaml > /dev/null <<EOF
listen: :443

acme:
  domains:
    - $(hostname)
  email: admin@$(hostname)
  ca: letsencrypt

auth:
  type: userpass
  userpass:
    user1: ${PASSWORD1}
    user2: ${PASSWORD2}

sniff:
  enable: true
  timeout: 2s
  rewriteDomain: false
  udpPorts: all

outbounds:
  - name: direct
    type: direct
  - name: socks5_proxy
    type: socks5
    socks5:
      addr: 127.0.0.1:8088
      username: user1
      password: ${PASSWORD1}

masquerade:
  type: proxy
  proxy:
    url: 1c.ru
    rewriteHost: true
  listenHTTP: :80
  listenHTTPS: :443
  forceHTTPS: true
EOF

echo "Configuring iptables..."
# IPv4
sudo iptables -t nat -A PREROUTING -i eth0 -p udp --dport 80:10000 -j DNAT --to-destination :443 2>/dev/null || true
# IPv6
sudo ip6tables -t nat -A PREROUTING -i eth0 -p udp --dport 80:10000 -j DNAT --to-destination :443 2>/dev/null || true

# Getting server IP address
SERVER_IP=$(curl -s ifconfig.me || curl -s ipinfo.io/ip || echo "YOUR_SERVER_IP")
PORT=443

echo "Starting service..."
sudo systemctl daemon-reload
sudo systemctl restart hysteria-server.service
sudo systemctl enable hysteria-server.service

sleep 2
if sudo systemctl is-active --quiet hysteria-server.service; then
    echo ""
    echo "=========================================="
    echo "Hysteria2 server successfully installed!"
    echo "=========================================="
    echo ""
    echo "Connection links for Streisand:"
    echo ""
    echo "User 1:"
    echo "hysteria2://user1:${PASSWORD1}@${SERVER_IP}:${PORT}/"
    echo ""
    echo "User 2:"
    echo "hysteria2://user2:${PASSWORD2}@${SERVER_IP}:${PORT}/"
    echo ""
    echo "=========================================="
else
    echo "Error: service did not start. Check logs:"
    echo "sudo journalctl -u hysteria-server.service"
    exit 1
fi

# outbounds:
#   - name: warp_proxy
# 	type: socks5
# 	socks5:
#   	addr: 127.0.0.1:40000
# acl:
#   inline:
# # WARP proxy
#   - warp_proxy(suffix:google.com)
#   - warp_proxy(suffix:openai.com)
# # Block RU
#   - reject(geoip:ru)
# # Block Google Ads
#   - reject(geosite:google@ads)
# # Block UDP port 443
#   - reject(all, udp/443)
# # Direct all other connections
#   - direct(all)

# For warp
# cd && bash <(curl -fsSL git.io/warp.sh) proxy
