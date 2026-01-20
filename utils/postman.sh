#!/bin/bash

cd ~
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
curl -sSL https://get.livekit.io/cli | bash
curl -sf https://binaries.nats.dev/nats-io/natscli/nats@latest | sh


echo 'Installing Insomnia'
echo '#################################################################'
curl -1sLf \
  'https://packages.konghq.com/public/insomnia/setup.deb.sh' |\
  sudo -E distro=ubuntu codename=focal bash
sudo apt update
sudo apt install -y insomnia
sudo apt install -y libfontconfig-dev


echo 'Installing Dbeaver'
echo '#################################################################'
wget https://dbeaver.io/files/dbeaver-ce_latest_amd64.deb
sudo apt install -y ./dbeaver-ce_latest_amd64.deb
rm dbeaver-ce_latest_amd64.deb


# echo 'Installing PostgresQL'
# echo '#################################################################'
# sudo apt install -y postgresql
# sudo apt install -y postgresql-common
# sudo /usr/share/postgresql-common/pgdg/apt.postgresql.org.sh
# # for dump
# pg_dump -U postgres -h localhost -p 5432 test | gzip > db_dump.sql.gz


# echo 'Installing Postman'
# echo '#################################################################'
# npm i -g nestjs nx postman
# curl -o- "https://dl-cli.pstmn.io/install/linux64.sh" | sh
# sudo snap install postman
# sudo snap remove postman

# wget https://dl.pstmn.io/download/latest/linux
# tar -xzf linux
# cd Postman
# ./Postman

# sudo nano ~/.bashrc
# export PATH="/home/user/Postman:$PATH"
# source ~/.bashrc
