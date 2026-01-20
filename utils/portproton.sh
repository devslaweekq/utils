#!/bin/bash

cd ~
wget https://github.com/Castro-Fidel/PortProton_dpkg/releases/download/portproton_1.7-2_amd64/portproton_1.7-2_amd64.deb
sudo apt install -y ./portproton_1.7-2_amd64.deb
rm portproton_1.7-2_amd64.deb

sudo dpkg --add-architecture amd64
sudo dpkg --add-architecture i386
sudo apt update
sudo apt upgrade -y
sudo apt install -y \
  dkms linux-headers-$(uname -r) meson libsystemd-dev pkg-config ninja-build git \
  libdbus-1-dev libinih-dev build-essential curl file libc6 libnss3 \
  xz-utils bubblewrap mesa-utils icoutils tar libvulkan1:{i386,amd64} zstd \
  cabextract xdg-utils openssl libgl1:{i386,amd64} libpoppler-glib8:{i386,amd64} \
  libgtk-3-dev glslang-tools \
  mingw-w64 mingw-w64-common mingw-w64-i686-dev mingw-w64-tools mingw-w64-x86-64-dev

sudo apt install --fix-broken -y
sudo apt install -y lutris

git clone --recurse-submodules https://github.com/flightlessmango/MangoHud.git && \
  cd MangoHud && \
  ./build.sh build && \
  ./build.sh package && \
  ./build.sh install && \
cd ~ && rm -rf MangoHud

tee -a ~/.config/MangoHud/MangoHud.conf <<< \
'
background_alpha=0.3
font_size=20
background_color=020202
text_color=ffffff
position=top-right
no_display
toggle_hud=F11
cpu_stats
cpu_temp
cpu_color=007AFA
gpu_stats
gpu_temp
gpu_color=00BD00
ram
ram_color=B3000A
vram
vram_color=00801B
io_read
io_write
io_color=B84700
arch
engine_color=B200B0
frame_timing=1
frametime_color=00ff00
#output_file=~/.config/MangoHud/mangohud_log_
#fps_limit 120
#media_player
#toggle_logging=F10
'
