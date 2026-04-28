#!/bin/bash

# Tailscale Exit Node setup
# Configures the server to be used as a VPN exit node

set -e

sudo apt install -y wl-clipboard
tailscale systray
tailscale configure systray --enable-startup=systemd
