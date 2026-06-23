#!/bin/bash

# bash -c "$(curl -fsSL https://raw.githubusercontent.com/mkasberg/ghostty-ubuntu/HEAD/install.sh)"

curl -fsSL https://opencode.ai/install | bash

wget https://opencode.ai/ru/download/stable/linux-x64-deb -O opencode.deb
sudo apt install -y ./opencode.deb
rm opencode.deb
