#!/bin/bash

set -e

echo "🔹 Installing MSI EC (Battery Charge Control)..."
if ! dkms status | grep -q "msi_ec"; then
  sudo apt update
  sudo apt install -y git build-essential dkms

  # Clone repository with proper error handling
  if [ -d "/tmp/msi-ec" ]; then
    sudo rm -rf /tmp/msi-ec
  fi

  sudo git clone https://github.com/BeardOverflow/msi-ec.git /tmp/msi-ec
  cd /tmp/msi-ec
  sudo make dkms-install
  sudo make
  sudo make install
  sudo modprobe msi_ec

  cd "$HOME"
else
  echo "...MSI EC module already installed, skipping..."
fi

# TODO tlp

if command -v mcontrolcenter &> /dev/null; then
    echo "MControlCenter already installed, skipping..."
else
    echo "🔹 Installing MControlCenter..."
    if [ ! -f "/tmp/MControlCenter.tar.gz" ]; then
        sudo wget -c "https://github.com/dmitry-s93/MControlCenter/releases/download/0.5.1/MControlCenter-0.5.1-bin.tar.gz" -O /tmp/MControlCenter.tar.gz
    fi
    if [ -d "/tmp/MControlCenter-0.5.1-bin" ]; then
       sudo rm -rf /tmp/MControlCenter-0.5.1-bin
    fi

    sudo tar -xzf /tmp/MControlCenter.tar.gz -C /tmp
    cd /tmp/MControlCenter-0.5.1-bin
    sudo ./install.sh

    cd "$HOME"
fi

echo "🔹 Installation completed successfully!"
echo "🔹 You can now run MControlCenter by typing 'mcontrolcenter' in terminal or finding it in your applications menu."

for f in /etc/apt/sources.list.d/*.sources; do
  [ -f "$f" ] || continue
  printf '%s: ' "$(basename "$f")"
  grep -E '^[[:space:]]*Suites:' "$f" \
    | sed 's/^[[:space:]]*Suites:[[:space:]]*//' \
    | tr -d '\r' \
    | paste -sd ' ' - || echo "(нет Suites)"
done
