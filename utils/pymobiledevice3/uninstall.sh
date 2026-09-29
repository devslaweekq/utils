#!/bin/bash

# pymobiledevice3 uninstaller for Ubuntu — removes the pip package (or the
# fallback venv created by install.sh) and its local data directory
# (downloaded developer images, cache and pair records).
# System packages (python3, usbmuxd, libimobiledevice-utils) are kept because
# other tools, e.g. iPhone.sh, depend on them.
# https://github.com/doronz88/pymobiledevice3

set -e

VENV_DIR="$HOME/.local/share/pymobiledevice3-venv"

if python3 -m pip show pymobiledevice3 &> /dev/null; then
    echo "Removing pymobiledevice3 (pip)..."
    python3 -m pip uninstall -y pymobiledevice3
else
    echo "pymobiledevice3 not installed via user pip, skipping."
fi

if [[ -d "$VENV_DIR" ]]; then
    echo "Removing venv ${VENV_DIR}..."
    rm -rf "$VENV_DIR"
    [[ -L "$HOME/.local/bin/pymobiledevice3" ]] && rm -f "$HOME/.local/bin/pymobiledevice3"
fi

# pymobiledevice3 keeps its data in ~/.pymobiledevice3 or, on newer Linux
# installs, in $XDG_DATA_HOME/pymobiledevice3.
DATA_DIRS=("${HOME}/.pymobiledevice3" "${XDG_DATA_HOME:-${HOME}/.local/share}/pymobiledevice3")

for dir in "${DATA_DIRS[@]}"; do
    if [[ -d "$dir" ]]; then
        echo "Removing data directory ${dir} (developer images, cache, pair records)..."
        rm -rf "$dir"
    fi
done

echo ""
echo "pymobiledevice3 has been fully removed."
