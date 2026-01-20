#!/bin/bash

set -e

echo "🔹 Installing Node Version Manager (NVM)..."
echo '#################################################################'
if [ -d "$HOME/.nvm" ]; then
    echo "NVM is already installed."
    # Source NVM
    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
    [ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"
    echo "Current NVM version: $(nvm --version)"
    echo "Current Node version: $(node --version)"
    echo "Current NPM version: $(npm --version)"
    exit 0
fi

echo "Installing dependencies..."
sudo apt update
sudo apt install -y curl git build-essential

# Install nvm
cd ~
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/master/install.sh | bash

# Get nvm in current session
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && . "$NVM_DIR/bash_completion"
. ~/.bashrc

nvm ls-remote

# Install and use v22.18.0 Node.js
VERSION=v22.18.0
nvm install "$VERSION"
nvm alias default "$VERSION"
nvm use "$VERSION"
echo "Installing useful global npm packages..."
npm i -g npm
npm i -g typescript ts-node nodemon pm2 serve
npm i -g yarn corepack prettier eslint
npm i -g npm-check-updates dotenv nx nestjs-cli nats
# npm i -g solc solhint solidity-code-metrics tronbox
corepack enable

# Check installed versions Node.js
nvm ls

echo '#################################################################'
echo "🔹 NVM installation completed successfully!"
echo "NVM version: $(nvm --version)"
echo "Node version: $(node --version)"
echo "NPM version: $(npm --version)"
echo "🔹 To start using NVM, close and reopen your terminal, or run: source ~/.bashrc"
echo '#################################################################'
