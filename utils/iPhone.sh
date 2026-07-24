sudo apt install -y ideviceinstaller libimobiledevice-utils ifuse \
  usbmuxd libimobiledevice-utils idevicerestore
  # python-imobiledevice libimobiledevice6 libplist2 python-plist

cd ~
wget https://github.com/iDescriptor/iDescriptor/releases/download/v0.5.0/iDescriptor-v0.5.0-Linux_x86_64.AppImage.zip
unzip iDescriptor-v0.5.0-Linux_x86_64.AppImage.zip
rm -rf iDescriptor-v0.5.0-Linux_x86_64.AppImage.zip

# sudo cat /etc/udev/rules.d/99-idevice.rules
# SUBSYSTEM=="usb", ATTR{idVendor}=="05ac", MODE="0666"
sudo groupadd idevice
sudo usermod -aG idevice $USER
sudo udevadm control --reload-rules
sudo udevadm trigger

# mkdir -p ~/iPhone && idevicepair pair && ifuse ~/iPhone && cd ~/iPhone

# cd ~
# umount ~/iPhone
sudo apt install usbmuxd  libimobiledevice-utils idevicerestore
