#!/bin/bash

# bash -c "$(curl -fsSL https://raw.githubusercontent.com/mkasberg/ghostty-ubuntu/HEAD/install.sh)"

curl -fsSL https://opencode.ai/install | bash

wget https://opencode.ai/ru/download/stable/linux-x64-deb -O linux-x64-deb.deb
sudo apt install -y ./linux-x64-deb.deb
rm linux-x64-deb.deb
