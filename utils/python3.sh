#!/bin/bash

echo '#### Installing Python3'
echo '#################################################################'
sudo apt update
sudo apt upgrade -y
sudo apt install --fix-broken -y
sudo apt autoremove --purge -y
sudo apt autoclean -y
sudo apt clean -y

sudo apt install -y \
  cpu-checker python3-pip python3-dev python3-virtualenv pipx \
  python3-venv python-is-python3 python3 python3-full build-essential \
  software-properties-common wget zlib1g-dev libffi-dev libgdbm-dev \
  libnss3-dev libssl-dev libreadline-dev

. ~/.bashrc
python3 --version
pip3 --version
python3 -m pip config set global.break-system-packages true
pip install pipenv
pip3 install --upgrade pip
echo '#### Python3 installed'
echo '#################################################################'
