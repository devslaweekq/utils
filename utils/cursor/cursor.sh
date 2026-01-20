#!/bin/bash

# Cursor IDE Installation & Integration Script for Linux
# This script sets up Cursor IDE with desktop integration, file associations, and update capability

set -e # Exit on error

echo "🔹 Installing Cursor AI IDE..."
sudo apt update
sudo apt install -y curl gpg wget

# Adding keys
# Sourced from https://downloads.cursor.com/keys/anysphere.asc
sudo wget -qO- https://downloads.cursor.com/keys/anysphere.asc | gpg --dearmor > anysphere.gpg
sudo install -o root -g root -m 644 anysphere.gpg /usr/share/keyrings/
rm anysphere.gpg

# Adding repos
# sudo sh -c 'echo "deb [arch=amd64 signed-by=/usr/share/keyrings/anysphere.gpg] https://downloads.cursor.com/aptrepo stable main" >> /etc/apt/sources.list.d/cursor.list'

# Write repository in deb822 format with Signed-By.
sudo sh -c 'echo "### THIS FILE IS AUTOMATICALLY CONFIGURED ###
# You may comment out this entry, but any other modifications may be lost.
Types: deb
URIs: https://downloads.cursor.com/aptrepo
Suites: stable
Components: main
Architectures: amd64,arm64
Signed-By: /usr/share/keyrings/anysphere.gpg" >> /etc/apt/sources.list.d/cursor.sources'

sudo apt update
sudo apt upgrade -y
sudo apt install -y cursor

xdg-mime default cursor.desktop text/plain
xdg-mime default cursor.desktop application/x-shellscript
xdg-mime default cursor.desktop text/x-script.python
xdg-mime default cursor.desktop text/javascript
xdg-mime default cursor.desktop text/x-c
xdg-mime default cursor.desktop text/x-c++
xdg-mime default cursor.desktop text/x-java

# Set Cursor as default editor for git commit messages
git config --global core.editor "cursor --wait"

echo "Cursor AI IDE installation complete. You can find it in your application menu."
