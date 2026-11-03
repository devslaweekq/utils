#!/bin/bash

# Tailscale Installation and Configuration Script

set -e

# Check for root privileges
if [[ $EUID -ne 0 ]]; then
    echo "Error: Run this script with root privileges"
    echo "Use: sudo $0"
    exit 1
fi

# User who started the script (root when run without sudo)
TARGET_USER="${SUDO_USER:-root}"

# Add an iptables rule only if it is not there yet (safe to re-run)
ipt() {
    local table_args=()
    if [[ "$1" == "-t" ]]; then
        table_args=("$1" "$2")
        shift 2
    fi
    local chain="$1"
    shift
    if ! iptables "${table_args[@]}" -C "$chain" "$@" 2>/dev/null; then
        iptables "${table_args[@]}" -A "$chain" "$@"
    fi
}

unit_exists() {
    systemctl list-unit-files "$1.service" --no-legend 2>/dev/null | grep -q "^$1.service"
}

echo "Starting Tailscale installation..."


# Update packages and install dependencies
echo "Updating packages..."
apt update -qq
apt install -y curl wget gnupg lsb-release apt-transport-https ca-certificates iptables-persistent

# Install Tailscale
echo "Installing Tailscale..."
curl -fsSL https://tailscale.com/install.sh | sh

# Start service
echo "Starting tailscaled service..."
# Configure systemd service
systemctl enable tailscaled
systemctl start tailscaled

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
    ufw allow 41641/udp >/dev/null 2>&1 || true
fi

# firewalld (RHEL/CentOS/Fedora)
if command -v firewall-cmd &> /dev/null && systemctl is-active --quiet firewalld; then
    firewall-cmd --permanent --add-port=41641/udp >/dev/null 2>&1 || true
    firewall-cmd --reload >/dev/null 2>&1 || true
fi

# iptables (fallback option)
if command -v iptables &> /dev/null; then
    if ! iptables -C INPUT -p udp --dport 41641 -j ACCEPT 2>/dev/null; then
        iptables -I INPUT -p udp --dport 41641 -j ACCEPT
    fi
    echo "iptables rule added for port 41641/udp"
fi

# Enable IP forwarding (drop-in file, no duplicates on re-run)
echo "Enabling IP forwarding..."
cat > /etc/sysctl.d/99-tailscale.conf <<EOF
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
EOF
sysctl -p /etc/sysctl.d/99-tailscale.conf

# Configure iptables for NAT
echo "Configuring NAT..."

# Detect primary interface
PRIMARY_INTERFACE=$(ip route show default | awk '{print $5}' | head -n1)
if [[ -z "$PRIMARY_INTERFACE" ]]; then
    echo "Error: could not detect primary network interface"
    exit 1
fi
echo "Primary interface: $PRIMARY_INTERFACE"

# Add NAT rules
ipt -t nat POSTROUTING -o "$PRIMARY_INTERFACE" -j MASQUERADE
ipt FORWARD -i tailscale0 -o "$PRIMARY_INTERFACE" -j ACCEPT
ipt FORWARD -i "$PRIMARY_INTERFACE" -o tailscale0 -m state --state RELATED,ESTABLISHED -j ACCEPT

# Save iptables rules (once, after all rules are added)
if command -v netfilter-persistent &> /dev/null; then
    netfilter-persistent save
else
    mkdir -p /etc/iptables
    iptables-save > /etc/iptables/rules.v4
fi

echo "iptables rules configured"

# User-level setup (systray, operator) must run as the invoking user, not root
if [[ "$TARGET_USER" != "root" ]]; then
    USER_UID=$(id -u "$TARGET_USER")
    sudo -u "$TARGET_USER" XDG_RUNTIME_DIR="/run/user/$USER_UID" \
        tailscale configure systray --enable-startup=systemd || true
    sudo -u "$TARGET_USER" XDG_RUNTIME_DIR="/run/user/$USER_UID" \
        systemctl --user daemon-reload || true
    tailscale set --operator="$TARGET_USER"
fi

# Restart only the services that exist on this machine
for svc in systemd-resolved NetworkManager; do
    if unit_exists "$svc"; then
        systemctl restart "$svc"
    fi
done
systemctl restart tailscaled

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
