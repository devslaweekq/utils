#!/usr/bin/env bash
set -euo pipefail

sudo apt update

# OpenConnect GUI client via NetworkManager (GNOME/KDE):
# - network-manager-openconnect: NetworkManager backend
# - network-manager-openconnect-gnome: GNOME UI plugin (incl. nm-connection-editor)
sudo apt install -y \
  openconnect \
  network-manager-openconnect \
  network-manager-openconnect-gnome
sudo systemctl restart NetworkManager

echo
echo "Done."
echo "Next: Network Settings -> VPN -> Add -> OpenConnect (AnyConnect compatible)."
echo "If you don't see the option, re-login or restart NetworkManager:"
echo "  sudo systemctl restart NetworkManager"
