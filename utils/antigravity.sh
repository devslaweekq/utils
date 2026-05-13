#!/bin/bash

sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://us-central1-apt.pkg.dev/doc/repo-signing-key.gpg | \
  sudo gpg --dearmor --yes -o /etc/apt/keyrings/antigravity-repo-key.gpg
echo "Types: deb
URIs: https://us-central1-apt.pkg.dev/projects/antigravity-auto-updater-dev/
Suites: antigravity-debian
Components: main
Signed-By: /etc/apt/keyrings/antigravity-repo-key.gpg
Architectures: amd64" | \
  sudo tee /etc/apt/sources.list.d/antigravity.sources > /dev/null

sudo apt update
sudo apt install -y antigravity
