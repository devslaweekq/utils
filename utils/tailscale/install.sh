#!/bin/bash

# Tailscale Installation and Configuration Script

set -e

# Check for root privileges
if [[ $EUID -ne 0 ]]; then
    echo "Error: Run this script with root privileges"
    echo "Use: sudo $0"
    exit 1
fi

echo "Starting Tailscale installation..."


# Update packages and install dependencies
echo "Updating packages..."
sudo apt update -qq
sudo apt install -y curl wget gnupg lsb-release apt-transport-https ca-certificates

# Install Tailscale
echo "Installing Tailscale..."
curl -fsSL https://tailscale.com/install.sh | sh

# Start service
echo "Starting tailscaled service..."
# Configure systemd service
sudo systemctl enable tailscaled
sudo systemctl start tailscaled

# Check status
if systemctl is-active --quiet tailscaled; then
    echo "tailscaled service started successfully"
else
    echo "Error: Failed to start tailscaled service"
    exit 1
fi

# Configure firewall
echo "Configuring firewall..."
if command -v ufw &> /dev/null; then
    sudo ufw allow 41641/udp >/dev/null 2>&1 || true
fi

# firewalld (RHEL/CentOS/Fedora)
if command -v firewall-cmd &> /dev/null && systemctl is-active --quiet firewalld; then
    sudo firewall-cmd --permanent --add-port=41641/udp >/dev/null 2>&1 || true
    sudo firewall-cmd --reload >/dev/null 2>&1 || true
fi

# iptables (fallback option)
if command -v iptables &> /dev/null; then
    sudo iptables -I INPUT -p udp --dport 41641 -j ACCEPT
    # Save rules (implementation may depend on distribution)
    if command -v iptables-save &> /dev/null; then
        sudo iptables-save > /etc/iptables/rules.v4 2>/dev/null || true
    fi
    echo "iptables rule added for port 41641/udp"
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

tailscale configure systray --enable-startup=systemd
tailscale set --operator=$USER
systemctl --user daemon-reload
sudo systemctl restart systemd-resolved
sudo systemctl restart NetworkManager
sudo systemctl restart tailscaled

echo ""
echo "Tailscale installation completed!"
echo ""
echo "Next steps:"
echo "1. Interactive authentication (recommended for first setup): tailscale up"
echo "2. Or use an Auth Key (for automation): tailscale up --authkey=YOUR_KEY"
echo ""
echo "Useful commands:"
echo "  tailscale status  - connection status"
echo "  tailscale ip      - your Tailscale IP address"
echo "  tailscale down    - disconnect"
echo ""
echo "Admin panel: https://login.tailscale.com/admin/"
echo "Client run: sudo tailscale up --exit-node=IP_EXIT_NODE --exit-node-allow-lan-access=true --accept-routes"

echo ""
