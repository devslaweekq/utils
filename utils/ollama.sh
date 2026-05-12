#!/bin/bash

set -e

sudo apt update
sudo apt install -y git build-essential curl
curl -fsSL https://ollama.com/install.sh | sh

ollama -v

# Create a user and group for Ollama:
sudo useradd -r -s /bin/false -U -m -d /usr/share/ollama ollama
sudo usermod -a -G ollama $(whoami)

sudo tee -a << EOF > /etc/systemd/system/ollama.service
[Unit]
Description=Ollama Service
After=network-online.target

[Service]
ExecStart=/usr/bin/ollama serve
User=ollama
Group=ollama
Restart=always
RestartSec=3
Environment="PATH=$PATH"

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable ollama
sudo systemctl start ollama
sudo systemctl status ollama

sudo rmmod nvidia_uvm && sudo modprobe nvidia_uvm

ollama pull qwen3.6:35b
# ollama pull hf.co/HauhauCS/Qwen3.6-35B-A3B-Uncensored-HauhauCS-Aggressive:IQ4_XS
ollama list

# https://lmstudio.ai/download
# curl -fsSL https://lmstudio.ai/install.sh | bash

# To uninstall:
# sudo systemctl stop ollama
# sudo systemctl disable ollama
# sudo rm /etc/systemd/system/ollama.service
# sudo rm -r $(which ollama | tr 'bin' 'lib')
# sudo rm $(which ollama)
# sudo userdel ollama
# sudo groupdel ollama
# sudo rm -r /usr/share/ollama
