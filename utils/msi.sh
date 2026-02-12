#!/bin/bash

set -e

echo "🔹 Installing MSI EC (Battery Charge Control)..."
if ! dkms status | grep -q "msi_ec"; then
  sudo apt update
  sudo apt install -y git build-essential dkms

  # Clone repository with proper error handling
  if [ -d "/tmp/msi-ec" ]; then
    sudo rm -rf /tmp/msi-ec
  fi

  sudo git clone https://github.com/BeardOverflow/msi-ec.git /tmp/msi-ec
  cd /tmp/msi-ec
  sudo make dkms-install
  sudo make
  sudo make install
  sudo modprobe msi_ec

  cd "$HOME"
else
  echo "...MSI EC module already installed, skipping..."
fi

# TODO tlp

# echo "🔹 Installing Qt 6.9.0 build dependencies..."
# sudo add-apt-repository -y ppa:kubuntu-ppa/backports
# sudo apt update
# sudo apt install -y qt6-base-dev qt6-declarative-dev qt6-tools-dev

# sudo cp /mnt/D/CRYPTO/utils/utils/qt-online.run /tmp/qt-online.run
# cd /tmp
# chmod +x ./qt-online.run
# ./qt-online.run
# cd ~

# # Add Qt 6.9.0 paths to .bashrc
# echo 'export PATH=$HOME/Qt/6.9.0/gcc_64/bin:$PATH' >> ~/.bashrc
# echo 'export LD_LIBRARY_PATH=$HOME/Qt/6.9.0/gcc_64/lib:$LD_LIBRARY_PATH' >> ~/.bashrc
# echo 'export QT_PLUGIN_PATH=$HOME/Qt/6.9.0/gcc_64/plugins:$QT_PLUGIN_PATH' >> ~/.bashrc
# echo 'export QML2_IMPORT_PATH=$HOME/Qt/6.9.0/gcc_64/qml:$QML2_IMPORT_PATH' >> ~/.bashrc

# # Apply changes to the current shell session
# source ~/.bashrc

# # Create symbolic links for main Qt libraries
# sudo ln -sf $HOME/Qt/6.9.0/gcc_64/lib/libQt6Core.so.6 /usr/lib/libQt6Core.so.6
# sudo ln -sf $HOME/Qt/6.9.0/gcc_64/lib/libQt6Gui.so.6 /usr/lib/libQt6Gui.so.6
# sudo ln -sf $HOME/Qt/6.9.0/gcc_64/lib/libQt6Widgets.so.6 /usr/lib/libQt6Widgets.so.6
# sudo ln -sf $HOME/Qt/6.9.0/gcc_64/lib/libQt6Network.so.6 /usr/lib/libQt6Network.so.6
# sudo ln -sf $HOME/Qt/6.9.0/gcc_64/lib/libQt6Qml.so.6 /usr/lib/libQt6Qml.so.6
# sudo ln -sf $HOME/Qt/6.9.0/gcc_64/lib/libQt6Quick.so.6 /usr/lib/libQt6Quick.so.6

# # Update library cache
# sudo ldconfig

# # Create configuration file for ldconfig
# sudo bash -c "echo '$HOME/Qt/6.9.0/gcc_64/lib' > /etc/ld.so.conf.d/qt6.conf"
# sudo ldconfig

# # Create an alternative for qmake6
# sudo update-alternatives --install /usr/bin/qmake6 qmake6 $HOME/Qt/6.9.0/gcc_64/bin/qmake6 100
# source ~/.bashrc
# qmake6 --version

if command -v mcontrolcenter &> /dev/null; then
    echo "MControlCenter already installed, skipping..."
else
    echo "🔹 Installing MControlCenter..."
    if [ ! -f "/tmp/MControlCenter.tar.gz" ]; then
        sudo wget -c "https://github.com/dmitry-s93/MControlCenter/releases/download/0.5.0/MControlCenter-0.5.0-bin.tar.gz" -O /tmp/MControlCenter.tar.gz
    fi
    if [ -d "/tmp/MControlCenter-0.5.0-bin" ]; then
       sudo rm -rf /tmp/MControlCenter-0.5.0-bin
    fi

    sudo tar -xzf /tmp/MControlCenter.tar.gz -C /tmp
    cd /tmp/MControlCenter-0.5.0-bin
    sudo ./install.sh

    cd "$HOME"
fi

echo "🔹 Installation completed successfully!"
echo "🔹 You can now run MControlCenter by typing 'mcontrolcenter' in terminal or finding it in your applications menu."
