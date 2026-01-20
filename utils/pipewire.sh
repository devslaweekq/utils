sudo apt update
sudo apt install -y pulseaudio-utils pavucontrol \
  pipewire-alsa pipewire-jack pipewire-audio-client-libraries

mkdir -p ~/.config/pipewire
cp /mnt/d/CRYPTO/setup/Linux/pipewire.conf ~/.config/pipewire
systemctl --user restart pipewire wireplumber pipewire-pulse
