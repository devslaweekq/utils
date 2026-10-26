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

# Generate passwords (16 hex characters)
PASSWORD1=$(openssl rand -hex 8)
PASSWORD2=$(openssl rand -hex 8)

sudo mkdir -p /etc/hysteria

# Generate self-signed certificate
echo "Generating self-signed certificate..."
sudo rm -f /etc/hysteria/cert.pem /etc/hysteria/key.pem
sudo openssl ecparam -genkey -name prime256v1 -out /tmp/hysteria-key.pem 2>/dev/null
if [[ -f /tmp/hysteria-key.pem ]]; then
    sudo openssl req -new -x509 -days 36500 -key /tmp/hysteria-key.pem -out /etc/hysteria/cert.pem -subj "/CN=localhost"
    sudo mv /tmp/hysteria-key.pem /etc/hysteria/key.pem
else
    sudo openssl req -x509 -nodes -newkey rsa:2048 -keyout /etc/hysteria/key.pem -out /etc/hysteria/cert.pem -subj "/CN=localhost" -days 36500
fi
sudo chmod 644 /etc/hysteria/key.pem
sudo chmod 644 /etc/hysteria/cert.pem
sudo chown root:root /etc/hysteria/key.pem /etc/hysteria/cert.pem

echo "Creating configuration file..."
sudo tee /etc/hysteria/config.yaml > /dev/null <<EOF
listen: :443

tls:
  cert: /etc/hysteria/cert.pem
  key: /etc/hysteria/key.pem

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

masquerade:
  type: proxy
  proxy:
    url: https://1c.ru
    rewriteHost: true
  forceHTTPS: true
EOF

echo "Configuring iptables..."
# IPv4
sudo iptables -t nat -A PREROUTING -i eth0 -p udp --dport 80:10000 -j DNAT --to-destination :443 2>/dev/null || true
# IPv6
sudo ip6tables -t nat -A PREROUTING -i eth0 -p udp --dport 80:10000 -j DNAT --to-destination :443 2>/dev/null || true
# Allow UDP port 443 (insert at the beginning to ensure it's processed first)
sudo iptables -I INPUT 1 -p udp --dport 443 -j ACCEPT 2>/dev/null || true
sudo ip6tables -I INPUT 1 -p udp --dport 443 -j ACCEPT 2>/dev/null || true
# Also allow on any interface
sudo iptables -I INPUT 1 -p udp -m udp --dport 443 -j ACCEPT 2>/dev/null || true
sudo ip6tables -I INPUT 1 -p udp -m udp --dport 443 -j ACCEPT 2>/dev/null || true

echo "Getting server IP address..."
SERVER_IP=""
for service in "ifconfig.me" "ipinfo.io/ip" "icanhazip.com" "api.ipify.org"; do
    IP=$(curl -s --max-time 3 "$service" 2>/dev/null | grep -oE '^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$' | head -1 || true)
    if [[ -n "$IP" ]]; then
        SERVER_IP="$IP"
        break
    fi
done

if [[ -z "$SERVER_IP" ]]; then
    echo "Warning: failed to automatically determine IP address"
    SERVER_IP="YOUR_SERVER_IP"
fi

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
    echo "Server status:"
    sudo ss -ulnp | grep :443 || echo "Warning: Port 443 UDP not listening"
    echo ""
    echo "Connection links for Streisand:"
    echo ""
    echo "User 1:"
    echo "hysteria2://user1:${PASSWORD1}@${SERVER_IP}:${PORT}/?insecure=true"
    echo ""
    echo "User 2:"
    echo "hysteria2://user2:${PASSWORD2}@${SERVER_IP}:${PORT}/?insecure=true"
    echo ""
    echo "=========================================="
    echo ""
    echo "To check connections, run:"
    echo "sudo journalctl -u hysteria-server.service -f"
else
    echo "Error: service did not start. Check logs:"
    echo "sudo journalctl -u hysteria-server.service -n 50 --no-pager"
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
