#!/bin/bash

# cd ~ && \
# /main/vpn-install.sh
# chmod +x vpn-install.sh
# sudo ./vpn-install.sh
# echo "First add new user"
# adduser msi
# sudo usermod -aG sudo msi
# su - msi
# sudo nano ~/.ssh/authorized_keys
# edit config
# sudo tee -a /etc/ssh/ssh_config <<< \
# "    ForwardAgent yes
#     PasswordAuthentication no
#     IdentityFile ~/.ssh/id_ed25519
#     IdentitiesOnly yes"

# ???
# sudo tee -a /etc/ssh/sshd_config <<< \
# "PermitRootLogin no
# PubkeyAuthentication yes
# AuthorizedKeysFile      .ssh/authorized_keys .ssh/authorized_keys2
# PasswordAuthentication no
# PermitEmptyPasswords no ???
# sudo systemctl restart sshd"
# ???

echo '#################################################################'
echo "Updating system"
echo '#################################################################'
cd ~
tee -a ~/.bashrc <<< \
'
alias si="sudo apt install -y"
alias srf="sudo rm -rf"
alias srn="sudo reboot now"
alias srp="sudo apt remove --purge -y"
alias sdr="sudo systemctl daemon-reload"
alias supd="sudo apt update && sudo apt upgrade -y && sudo apt install --fix-broken -y && sudo apt autoremove -y && sudo apt autoclean -y"
'
. ~/.bashrc

sudo apt update
sudo apt upgrade -y
sudo apt install --fix-broken -y
sudo apt autoclean -y
sudo apt autoremove --purge
sudo apt install -y \
  git nano curl wget build-essential gcc make
echo '#################################################################'
echo "Updating system completed"
echo '#################################################################'

bash utils/main/utils/nvm-install.sh
bash utils/main/utils/docker-install.sh

# bash utils/main/3proxy/install.sh
bash utils/main/3x-ui/install.sh
bash utils/main/outline/install.sh --api-port 37280 --keys-port 58628


sudo ufw allow 22/tcp
sudo ufw allow 443/tcp
sudo ufw allow 8080/tcp
sudo ufw allow 9001/tcp
sudo ufw allow 9007/tcp

# 3proxy
sudo ufw allow 3128/tcp
sudo ufw allow 3128/udp
sudo ufw allow 2525/tcp
sudo ufw allow 2525/udp

# 3xui
sudo ufw allow 2053/tcp
sudo ufw allow 2053/udp
sudo ufw allow 3333/tcp
sudo ufw allow 3333/udp

# outline
sudo ufw allow 37280/tcp
sudo ufw allow 58628/tcp
sudo ufw allow 58628/udp

echo '#################################################################'
echo "After all installs and configs run: sudo reboot now"
echo '#################################################################'
