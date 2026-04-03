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

echo ""
echo "====================================="
echo "Exit Node configured!"
echo "====================================="
echo ""
echo "Next steps:"
echo "1. Open the settings: https://login.tailscale.com/admin/settings"
echo "2. Add your auth key: https://login.tailscale.com/admin/settings/auth-keys"
echo "3. Copy the auth key and paste it into the script "
echo "4. Run the command: sudo tailscale up --auth-key=YOUR_AUTH_KEY --advertise-exit-node --accept-routes=true --accept-dns=false"
echo "5. Open the admin panel: https://login.tailscale.com/admin/machines"
echo "6. Find your server in the devices list"
echo "7. Enable the 'Exit node' option for this device"
echo "8. Connect other devices to Tailscale"
echo "9. On clients, choose your server as the Exit Node"
echo "10. After installing, open https://login.tailscale.com/admin/acls/file"
echo "11. Copy the content of the settings.json and paste it into the 'ACLs' field"
echo "12. Click 'Save'"
echo ""
echo "Status: $(tailscale status --peers=false)"
echo ""
