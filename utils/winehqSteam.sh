#!/bin/bash

# Check OS and set release variable
if [[ -f /etc/os-release ]]; then
    source /etc/os-release
    release=$ID
    codename=$VERSION_CODENAME
elif [[ -f /usr/lib/os-release ]]; then
    source /usr/lib/os-release
    release=$ID
    codename=$VERSION_CODENAME
else
    echo "Failed to check the system OS, please contact the author!" >&2
    exit 1
fi
echo "The OS release is: $release"
echo "The OS version is: $codename"

sudo mkdir -pm755 /etc/apt/keyrings
wget -O - https://dl.winehq.org/wine-builds/winehq.key | sudo gpg --dearmor -o /etc/apt/keyrings/winehq-archive.key -
sudo dpkg --add-architecture i386
sudo wget -NP /etc/apt/sources.list.d/ https://dl.winehq.org/wine-builds/$release/dists/$codename/winehq-$codename.sources

sudo apt update
sudo apt upgrade -y

sudo apt install -y libpoppler-glib8:{i386,amd64}
# wine winecfg
sudo apt install --install-recommends winehq-stable -y

sudo apt install -y \
  librust-proton-call-dev proton-caller
  # libgl1-mesa-glx:{i386,amd64}
sudo apt install --fix-broken -y
sudo apt install -y meson gcc-mingw-w64-i686 g++-mingw-w64-i686 \
  g++-mingw-w64-x86-64-posix g++-mingw-w64-x86-64-win32 glslang-tools

cd ~
git clone --recursive https://github.com/HansKristian-Work/vkd3d-proton
cd vkd3d-proton
chmod +x ./package-release.sh
mkdir -p $HOME/vkd3d
sudo ./package-release.sh master $HOME/vkd3d --no-package
cd ~
sudo rm -rf vkd3d-proton

# change to build.86 for 32-bit
sudo chmod +x $HOME/vkd3d/vkd3d-proton-master/setup_vkd3d_proton.sh
$HOME/vkd3d/vkd3d-proton-master/setup_vkd3d_proton.sh install

# wget -O $HOME/steam.deb http://media.steampowered.com/client/installer/steam.deb
wget https://repo.steampowered.com/steam/archive/precise/steam_latest.deb
sudo apt install -y $HOME/steam_latest.deb
sudo rm -rf $HOME/steam_latest.deb

tee -a $HOME/.steam/steam/steam_dev.cfg <<< \
'
@nClientDownloadEnableHTTP2PlatformLinux 0
@fDownloadRateImprovementToAddAnotherConnection 1.0
'
flatpak override com.usebottles.bottles --user --filesystem=xdg-data/applications
sudo flatpak override com.usebottles.bottles --filesystem=$HOME/.local/share/Steam


# primerun %command% -input_button_code_is_scan_code -vulkan_disable_steam_shader_cache
# gamemoderun mangohud __NV_PRIME_RENDER_OFFLOAD=1 __VK_LAYER_NV_optimus=NVIDIA_only __GLX_VENDOR_LIBRARY_NAME=nvidia %command%
# Exec=env
# __GL_THREADED_OPTIMIZATION=1 for OpenGL games
# __GL_SHADER_DISK_CACHE=1 to create a shader cache for a game
# __GL_SHADER_DISK_CACHE_PATH=/path/to/location to set the location for the shader cache.

# for .msi files wine msiexec /i
# for .exe files wine *.exe

# mkdir -v $HOME/.wine-MyApp
# export WINEPREFIX=$HOME/.wine-MyApp
# wine winecfg

# export WINEPREFIX=$HOME/.wine-MyApp
# uninstall wine
# rm -r $HOME/.wine-MyApp

# flatpak steam
# tee -a $HOME/.var/app/com.valvesoftware.Steam/.steam/steam/steam_dev.cfg <<< \
# '
# @nClientDownloadEnableHTTP2PlatformLinux 0
# @fDownloadRateImprovementToAddAnotherConnection 1.0
# '
# sudo flatpak override com.usebottles.bottles --filesystem=$HOME/.var/app/com.valvesoftware.Steam/data/Steam
