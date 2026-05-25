#!/bin/bash

set -e

sudo apt update
sudo apt install -y jq git build-essential curl libsdl2-dev cmake whisper.cpp
curl -fsSL https://ollama.com/install.sh | sh

ollama -v

# Create a user and group for Ollama:
sudo useradd -r -s /bin/false -U -m -d /usr/share/ollama ollama
sudo usermod -a -G ollama $(whoami)

sudo systemctl daemon-reload
sudo systemctl enable ollama
sudo systemctl start ollama

# sudo systemctl status ollama
curl http://localhost:11434/api/tags | jq .

sudo rmmod nvidia_uvm && sudo modprobe nvidia_uvm

ollama pull gemma4:E2B
ollama run gemma4:E2B "Hello, what can you do?"
# ollama list
# ollama pull qwen3.6:35b
# ollama pull hf.co/HauhauCS/Qwen3.6-35B-A3B-Uncensored-HauhauCS-Aggressive:IQ4_XS
# ollama pull hf.co/HauhauCS/Gemma-4-E4B-Uncensored-HauhauCS-Aggressive:Q4_K_M

# STT (Listen)
# A: Gemini API https://aistudio.google.com/apikey
# B: Deepgram https://deepgram.com

# https://lmstudio.ai/download

sudo wget https://installers.lmstudio.ai/linux/x64/0.4.13-1/LM-Studio-0.4.13-1-x64.deb -O /tmp/LM_Studio.deb
sudo apt install -y /tmp/LM_Studio.deb
sudo rm -rf /tmp/LM_Studio.deb
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
