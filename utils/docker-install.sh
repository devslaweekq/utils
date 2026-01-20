#!/bin/bash
set -e

echo "🔹 Installing Docker and Docker Compose..."
echo '#################################################################'

if command -v docker &> /dev/null && docker --version &> /dev/null && docker compose version &> /dev/null; then
    echo 'Docker and Docker Compose are already installed. Continuing...'
    docker --version
    docker-compose --version

    # Ensure current user is in docker group
    if groups "$USER" | grep -q "docker"; then
        echo "User $USER is already in the docker group."
    else
        echo "Adding user $USER to the docker group..."
        sudo usermod -aG docker "$USER"
        echo "User added to docker group. You may need to log out and back in for this to take effect."
    fi

    exit 0
else
    echo 'Docker not found. Installing Docker...'
    sudo apt autoremove $(dpkg -l *docker* |grep ii |awk '{print $2}') -y
    sudo apt remove --purge -y '^docker*' '^containerd*'
    sudo apt autoremove -y

    echo "Installing dependencies..."
    sudo apt update && sudo apt install -y apt-transport-https \
        ca-certificates curl gnupg lsb-release uidmap pass gnupg2

    curl -sSL https://get.docker.com | sh &&\
      sudo usermod -aG docker $(whoami) &&\
      sudo gpasswd -a $USER docker
    # dockerd-rootless-setuptool.sh install --force

    echo "Enabling and starting Docker service..."
    sudo systemctl restart docker
    sudo systemctl enable --now \
      docker docker.service docker.socket containerd containerd.service
    sudo systemctl daemon-reload
    source ~/.bashrc

    # mkdir -p $HOME/.docker
    # touch $HOME/.docker/config.json
    # echo '{"credsStore":"pass"}' > "$HOME/.docker/config.json"
    # echo "Installing docker-volume-local-persist plugin..."
    # curl -fsSL https://raw.githubusercontent.com/MatchbookLab/local-persist/master/scripts/install.sh | sudo bash

    echo '#################################################################'
    echo "🔹 Docker installation completed successfully!"
    echo "🔹 You may need to log out and back in for docker group membership to take effect."
    echo "🔹 Alternatively, you can run: newgrp docker"
    echo '#################################################################'
fi
