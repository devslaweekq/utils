#!/bin/bash

# pymobiledevice3 installer for Ubuntu — pure-Python CLI/library for talking to
# iPhone/iPad over USB without iTunes: live syslog, sysdiagnose/crash logs,
# backups, file/app access, screenshots, developer services (iOS 17+ tunnels).
# https://github.com/doronz88/pymobiledevice3

set -e

VENV_DIR="$HOME/.local/share/pymobiledevice3-venv"

sudo apt update -qq
sudo apt install -y python3 python3-pip python3-venv usbmuxd libimobiledevice-utils

mkdir -p "$HOME/.local/bin"
export PATH="$HOME/.local/bin:$PATH"

echo "Installing pymobiledevice3..."
if python3 -m pip install --user -U pymobiledevice3; then
    :
else
    # Ubuntu 23.04+ marks system Python as externally managed (PEP 668),
    # so fall back to a dedicated venv instead of forcing the install.
    echo "pip refused a user install, using venv ${VENV_DIR}..."
    python3 -m venv "$VENV_DIR"
    "$VENV_DIR/bin/python" -m pip install -U pip pymobiledevice3
    ln -sf "$VENV_DIR/bin/pymobiledevice3" "$HOME/.local/bin/pymobiledevice3"
fi

echo ""
pymobiledevice3 version
echo ""
echo "pymobiledevice3 installed successfully."
echo "Reopen the terminal (or 'source ~/.bashrc') if the command is not found."
echo "Connect the iPhone by USB, unlock it and tap 'Trust This Computer'."
echo "Usage:"
echo "  pymobiledevice3 usbmux list"
echo "  pymobiledevice3 syslog live --label -o syslog_live.txt"
echo "  pymobiledevice3 backup2 backup --full ./backup"
echo "  pymobiledevice3 crash pull ./crashes"
