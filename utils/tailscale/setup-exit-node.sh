#!/bin/bash

# Tailscale Exit Node setup
# Configures the server to be used as a VPN exit node

set -e

echo "Configuring server as a Tailscale Exit Node..."

# Check for root privileges
if [[ $EUID -ne 0 ]]; then
    echo "Error: run this script as root"
    echo "Use: sudo $0"
    exit 1
fi

# Check that Tailscale is installed
if ! command -v tailscale &> /dev/null; then
    echo "Error: Tailscale is not installed"
    echo "Run ./install.sh first"
    exit 1
fi

# Enable IP forwarding
echo "Enabling IP forwarding..."
echo 'net.ipv4.ip_forward = 1' >> /etc/sysctl.conf
echo 'net.ipv6.conf.all.forwarding = 1' >> /etc/sysctl.conf
sysctl -p

# Configure iptables for NAT
echo "Configuring NAT..."

# Detect primary interface
PRIMARY_INTERFACE=$(ip route | grep default | awk '{print $5}' | head -n1)
echo "Primary interface: $PRIMARY_INTERFACE"

# Add NAT rules
iptables -t nat -A POSTROUTING -o $PRIMARY_INTERFACE -j MASQUERADE
iptables -A FORWARD -i tailscale0 -o $PRIMARY_INTERFACE -j ACCEPT
iptables -A FORWARD -i $PRIMARY_INTERFACE -o tailscale0 -m state --state RELATED,ESTABLISHED -j ACCEPT

# Save iptables rules
if command -v netfilter-persistent &> /dev/null; then
    netfilter-persistent save
elif command -v iptables-save &> /dev/null; then
    iptables-save > /etc/iptables/rules.v4 2>/dev/null || true
fi

echo "iptables rules configured"

# Start Tailscale as Exit Node
echo "Starting Tailscale as Exit Node..."
tailscale up --advertise-exit-node --accept-routes

echo ""
echo "====================================="
echo "Exit Node configured!"
echo "====================================="
echo ""
echo "Next steps:"
echo "1. Open the admin panel: https://login.tailscale.com/admin/machines"
echo "2. Find your server in the devices list"
echo "3. Enable the 'Exit node' option for this device"
echo "4. Connect other devices to Tailscale"
echo "5. On clients, choose your server as the Exit Node"
echo ""
echo "Status: $(tailscale status --peers=false)"
echo ""
