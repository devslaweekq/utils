#!/bin/bash

sudo apt update
sudo apt install -y pulseaudio-utils pavucontrol \
  pipewire-alsa pipewire-jack pipewire-audio-client-libraries

mkdir -p ~/.config/pipewire
curl -fsSL https://raw.githubusercontent.com/devslaweekq/utils/main/utils/pipewire.conf -o ~/.config/pipewire/pipewire.conf
systemctl --user restart pipewire wireplumber pipewire-pulse
