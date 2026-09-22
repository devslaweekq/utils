#!/bin/bash

cd ~
wget https://github.com/Castro-Fidel/PortProton_dpkg/releases/download/portproton_1.7-3_amd64/portproton_1.7-3_amd64.deb
sudo apt install -y ./portproton_1.7-3_amd64.deb
rm portproton_1.7-3_amd64.deb

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
sudo apt install -y lutris mangohud

mkdir -p ~/.config/MangoHud
tee -a ~/.config/MangoHud/MangoHud.conf <<< \
'
### Limit the application FPS. Comma-separated list of one or more FPS values (e.g. 0,30,60). 0 means unlimited (unless VSynced)
fps_limit=165

### VSync [0-3] 0 = adaptive; 1 = off; 2 = mailbox; 3 = on
# vsync=-1

### OpenGL VSync [0-N] 0 = off; >=1 = wait for N v-blanks, N > 1 acts as a FPS limiter (FPS = display refresh rate / N)
# gl_vsync=-2

### Display the current GPU information
## Note: gpu_mem_clock and gpu_mem_temp also need "vram" to be enabled
gpu_stats
gpu_temp
# gpu_junction_temp
# gpu_core_clock
# gpu_mem_temp
# gpu_mem_clock
# gpu_power
# gpu_power_limit
# gpu_load_change
# gpu_efficiency

### Display the current CPU information
cpu_stats
cpu_temp
# cpu_power
# cpu_mhz
# cpu_load_change
# cpu_efficiency

### Display IO read and write for the app (not system)
io_read
io_write

### Display system vram / ram / swap space usage
vram
ram
swap

### Display FPS and frametime
fps
frametime

### Display loaded MangoHud architecture
arch

### Display the frametime line graph
frame_timing

### Display GameMode / vkBasalt running status
gamemode
# vkbasalt

font_size=20
font_size_text=20

### Outline text
text_outline
# text_outline_color = 000000
# text_outline_thickness = 1.5

### Change the hud position
# position=top-right
position=top-left

### Hud transparency / alpha
background_alpha=0.5
# alpha=1.0

### Color customization
text_color=FFFFFF
gpu_color=00BD00
# gpu_color=2E9762
cpu_color=007AFA
# cpu_color=2E97CB
vram_color=00801B
# vram_color=AD64C1
ram_color=B3000A
# ram_color=C26693
engine_color=B200B0
# engine_color=EB5B5B
io_color=B84700
# io_color=A491D3
frametime_color=00ff00
background_color=020202
toggle_hud=F11
toggle_logging=F10
# output_file="~/.config/MangoHud/mangohud_log_"
'

# git clone --recurse-submodules https://github.com/flightlessmango/MangoHud.git && \
#   cd MangoHud && \
#   ./build.sh build && \
#   ./build.sh package && \
#   ./build.sh install && \
# cd ~ && rm -rf MangoHud
