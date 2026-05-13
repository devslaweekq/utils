sudo apt install -y ideviceinstaller libimobiledevice-utils ifuse
  # python-imobiledevice libimobiledevice4 libplist2 python-plist

cd ~
wget https://github.com/iDescriptor/iDescriptor/releases/download/v0.5.0/iDescriptor-v0.5.0-Linux_x86_64.AppImage.zip
unzip iDescriptor-v0.5.0-Linux_x86_64.AppImage.zip
rm -rf iDescriptor-v0.5.0-Linux_x86_64.AppImage.zip

# sudo cat /etc/udev/rules.d/99-idevice.rules
sudo groupadd idevice
sudo usermod -aG idevice $USER
sudo udevadm control --reload-rules
sudo udevadm trigger

# idevicepair pair
# mkdir -p ~/iPhone
# ifuse ~/iPhone
# cd ~/iPhone

# cd ~
# umount ~/iPhone
