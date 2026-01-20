#!/bin/bash

# Add Ethereum repository and install Solidity compiler
sudo add-apt-repository -y ppa:ethereum/ethereum
sudo apt update
sudo apt install -y python3-graphviz python3-pygraphviz solc graphviz
solc --version

python3 -m pip config set global.break-system-packages true
python3 -m pipx ensurepath
pipx ensurepath

python3 -m pip install solc solc-select slither slither-analyzer eralchemy graphviz pygraphviz
solc-select install 0.8.0 0.8.22 0.8.24 0.8.25 0.8.26 0.8.28
# solc-select use 0.8.24

echo "Setup completed successfully!"

# git clone https://github.com/crytic/slither
# cd slither
# git checkout dev
# make dev
# . ./env/bin/activate
