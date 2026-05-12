#!/bin/bash

# Install the Intel graphics GPG public key
# wget -qO - https://repositories.intel.com/gpu/intel-graphics.key | \
#   sudo gpg --yes --dearmor --output /usr/share/keyrings/intel-graphics.gpg

sudo apt update
sudo apt install -y gpg-agent wget
sudo add-apt-repository -y ppa:kobuk-team/intel-graphics

# Configure the repositories.intel.com package repository
# echo "deb [arch=amd64,i386 signed-by=/usr/share/keyrings/intel-graphics.gpg] https://repositories.intel.com/gpu/ubuntu resolute client" | \
  # sudo tee /etc/apt/sources.list.d/intel-gpu-resolute.list

# Update the package repository meta-data
sudo apt update

sudo apt install -y \
    linux-headers-$(uname -r) flex bison intel-fw-gpu \
    linux-modules-extra-$(uname -r)

# Install the compute-related packages
sudo apt install -y \
  libmfxgen1 libvpl2 va-driver-all vainfo \
  intel-gpu-tools intel-media-va-driver-non-free mesa-utils
sudo apt install -y libze-intel-gpu1 intel-metrics-discovery intel-gsc
sudo apt install -y libvpl-tools libva-glx2 # libmfx-gen1 libmfx1 level-zero
sudo apt install -y libze-intel-gpu-raytracing
sudo apt install -y libigdgmm12
sudo apt install -y libze1 util-linux-extra intel-opencl-icd clinfo
sudo apt install -y intel-level-zero-gpu
sudo apt install -y libze-dev intel-ocloc

clinfo | grep "Device Name"
sudo gpasswd -a ${USER} render
newgrp render

sudo apt install -y qemu-utils \
  libvirt-daemon-system libvirt-clients \
  bridge-utils \
  virt-manager ovmf gir1.2-spiceclientgtk-3.0
  # qemu-kvm

sudo update-grub
