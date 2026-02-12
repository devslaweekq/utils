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

# Detect distribution
if [ -f /etc/os-release ]; then
    . /etc/os-release
    DISTRO=$ID
else
    echo "Error: Unable to determine Linux distribution"
    exit 1
fi

echo "Detected distribution: $DISTRO"

# Update packages and install dependencies
echo "Updating packages..."
case $DISTRO in
    ubuntu|debian)
        sudo apt update -qq
        sudo apt install -y curl wget gnupg lsb-release apt-transport-https ca-certificates
        ;;
    centos|rhel|fedora|rocky|almalinux)
        if command -v dnf &> /dev/null; then
            sudo dnf install -y curl wget gnupg
        else
            sudo yum install -y curl wget gnupg
        fi
        ;;
    *)
        echo "Warning: Unknown distribution"
        ;;
esac

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
echo ""
echo "Tailscale installation completed!"
echo ""
echo "Next steps:"
echo "1. Interactive authentication (recommended for first setup): tailscale up"
echo "2. Or use an Auth Key (for automation): tailscale up --authkey=YOUR_KEY"
echo "3. Configure as Exit Node (to route traffic): tailscale up --advertise-exit-node"
echo ""
echo "Useful commands:"
echo "  tailscale status  - connection status"
echo "  tailscale ip      - your Tailscale IP address"
echo "  tailscale down    - disconnect"
echo ""
echo "Admin panel: https://login.tailscale.com/admin/"

echo ""
