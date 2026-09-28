#!/bin/bash

# ipatool uninstaller for Ubuntu — removes the binary, state/session
# directory (cookies + file-backed keychain) and any Secret Service
# keyring entry created by ipatool.
# https://github.com/majd/ipatool

set -e

INSTALL_DIR="/usr/local/bin"
BIN_PATH="${INSTALL_DIR}/ipatool"

if [[ -f "$BIN_PATH" ]]; then
    echo "Removing ${BIN_PATH}..."
    sudo rm -f "$BIN_PATH"
else
    echo "${BIN_PATH} not found, skipping binary removal."
fi

# ipatool resolves its state directory in this order: $XDG_STATE_HOME/ipatool,
# then $XDG_DATA_HOME/ipatool, then the legacy ~/.ipatool.
STATE_DIRS=()
[[ -n "$XDG_STATE_HOME" ]] && STATE_DIRS+=("${XDG_STATE_HOME}/ipatool")
[[ -n "$XDG_DATA_HOME" ]] && STATE_DIRS+=("${XDG_DATA_HOME}/ipatool")
STATE_DIRS+=("${HOME}/.ipatool")

for dir in "${STATE_DIRS[@]}"; do
    if [[ -d "$dir" ]]; then
        echo "Removing state directory ${dir} (cookies + stored credentials)..."
        rm -rf "$dir"
    fi
done

# When a Secret Service provider (e.g. gnome-keyring) is available, ipatool
# stores credentials there under this service name instead of the file backend.
if command -v secret-tool &> /dev/null; then
    echo "Clearing Secret Service entry (if any)..."
    secret-tool clear service ipatool-auth.service 2>/dev/null || true
fi

echo ""
echo "ipatool has been fully removed."
