#!/bin/bash
set -e

echo "Install and settings PipeWire..."
sudo apt install -y pipewire pipewire-audio-client-libraries
sudo systemctl --user enable pipewire pipewire-pulse
sudo systemctl --user restart pipewire pipewire-pulse

echo 'Installing Bluetooth Audio for AirPods'
echo '#################################################################'
# sudo apt install -y 'bluez*' blueman
modprobe btusb
sudo tee -a /etc/bluetooth/main.conf > /dev/null <<EOL
ControllerMode = bredr
ControllerMode = dual
EOL

sudo /etc/init.d/bluetooth restart
sudo systemctl restart bluetooth
echo '#################################################################'
