#!/bin/bash

set -e

sudo apt update

echo "🔹 Installing xanmod kernel..."
if ! dpkg -l | grep -q "linux-xanmod"; then
    wget -qO - https://dl.xanmod.org/archive.key | sudo gpg --dearmor -vo /etc/apt/keyrings/xanmod-archive-keyring.gpg
    echo "deb [signed-by=/etc/apt/keyrings/xanmod-archive-keyring.gpg] http://deb.xanmod.org $(lsb_release -sc) main" | sudo tee /etc/apt/sources.list.d/xanmod-release.list
    sudo apt update
    # sudo apt install --reinstall -y linux-xanmod-x64v3
    sudo apt install --reinstall -y linux-xanmod-lts-x64v3
    sudo apt install --no-install-recommends dkms libelf-dev clang lld llvm
    sudo update-initramfs -u
    sudo update-grub2
    sudo update-grub
else
    echo "Xanmod kernel is already installed."
fi

sudo dpkg --configure -a
sudo apt install -y -f
sudo apt install --fix-broken -y
echo "Current kernel version:"
cat /proc/version

sudo apt update
sudo apt install -y nvidia-driver-580-open
sudo apt install -y libnvidia-gl-580 nvidia-dkms-580-open

# echo "🔹 Configuring swap (32GB)..."
# lsblk -f
# sudo nano /etc/fstab
# sudo swapon --show
# free -h
# df -h
# sudo swapoff -a

# # Check if swapfile already exists with correct size
# SWAP_SIZE=$(sudo du -h /swapfile 2>/dev/null | awk '{print $1}' | tr -d 'G')
# if [ "$SWAP_SIZE" != "32" ]; then
#     echo "Creating 32GB swap file..."
#     sudo dd if=/dev/zero of=/swapfile count=32768 bs=1MiB oflag=append conv=notrunc
#     sudo chmod 600 /swapfile
#     sudo mkswap /swapfile
# fi
# sudo swapon /swapfile

# if ! grep -q "/swapfile" /etc/fstab; then
#     sudo cp /etc/fstab /etc/fstab.bak
#     echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
# fi

# # https://ubuntuhandbook.org/index.php/2021/08/enable-hibernate-ubuntu-21-10/
# df -h # root_dir -> resume
# sudo filefrag -v /swapfile #copy first physical_offset value -> resume_offset
# sudo gnome-text-editor /etc/default/grub
# # GRUB_CMDLINE_LINUX_DEFAULT="quiet splash resume=/dev/nvme0n1p2 resume_offset=119285760"
# sudo update-grub

# sudo tee -a /etc/initramfs-tools/conf.d/resume <<< \
# "resume=/dev/nvme0n1p2 resume_offset=119285760"
# sudo update-initramfs -c -k all
# sudo systemctl hibernate

cat /proc/sys/vm/swappiness
sudo sysctl vm.swappiness=10
cat /proc/sys/vm/vfs_cache_pressure
sudo sysctl vm.vfs_cache_pressure=50
cat /proc/sys/fs/inotify/max_user_watches
sudo sysctl fs.inotify.max_user_watches=524288
sudo tee -a /etc/sysctl.conf <<< \
"vm.swappiness=10
vm.vfs_cache_pressure=50
fs.inotify.max_user_watches=524288"

echo "🔹 System optimization completed successfully!"
echo "🔹 It is recommended to reboot your system to apply all changes."
read -r -p "Would you like to reboot now? (y/n): " RESTART
if [[ $RESTART == "y" || $RESTART == "Y" ]]; then
    sudo reboot
else
    echo "Please reboot your system manually later to apply all changes."
    echo " after reboot, run:"
    echo " echo performance | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor"
fi
# sudo grep "menuentry 'Ubuntu," /boot/grub/grub.cfg | sed 's/^[ \t]*//;s/[ \t]*$//' | awk -F"'" '{print $2}' | awk '{printf "%1d %s\n", (NR-2)+1, $0}'



# mainline kernel
# sudo add-apt-repository ppa:teejee2008/ppa
# sudo apt update
# sudo apt install ukuu
# ukuu --install-latest

# echo "🔹 Installing mainline kernel..."
# if ! command_exists mainline; then
#     sudo add-apt-repository -y ppa:cappelikan/ppa
#     sudo apt update
#     sudo apt install -y mainline
# else
#     echo "Mainline is already installed."
# fi

# 1. Settings for gaming kernel:
# # Create file settings
# sudo nano /etc/sysctl.d/99-xanmod-gaming.conf

# # Add the following lines:
# vm.swappiness=10
# vm.vfs_cache_pressure=50
# kernel.sched_autogroup_enabled=0
# kernel.sched_child_runs_first=0
# kernel.sched_latency_ns=4000000
# kernel.sched_migration_cost_ns=500000
# kernel.sched_min_granularity_ns=500000
# kernel.sched_wakeup_granularity_ns=1000000
# kernel.sched_rt_runtime_us=950000

# # Apply settings
# sudo sysctl -p /etc/sysctl.d/99-xanmod-gaming.conf
