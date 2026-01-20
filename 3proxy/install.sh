#!/bin/bash

echo Updating system
echo '#################################################################'
sudo apt install -y wget nano curl build-essential gcc make

echo "Download and unpack the sources"

tar xzf ./3proxy-0.9.4.tar.gz
cd ./3proxy-0.9.4

echo "Compiling"
sudo make -f Makefile.Linux

echo "Installing"
sudo mkdir /etc/3proxy
cd ./3proxy-0.9.4/bin
sudo cp 3proxy /usr/bin/
cd /etc/3proxy/

sudo adduser --system --no-create-home --disabled-login --group msi
id msi

echo "Setting access rights to proxy server files"
# sudo chmod 600 /etc/3proxy/
sudo chown msi:msi -R /etc/3proxy
sudo chown msi:msi /usr/bin/3proxy
sudo chmod 444 /etc/3proxy/3proxy.cfg
sudo chmod 400 /etc/3proxy/.proxyauth

echo "Setting 3proxy.service"
sudo cp ./3proxy.service /etc/systemd/system

echo "Enable & starting 3proxy.service"
sudo systemctl daemon-reload
sudo systemctl enable 3proxy
sudo systemctl start 3proxy
sudo ps -ela | grep "3proxy"
  # && sudo systemctl status 3proxy.service \

echo "Oppening port 3128 & 2525"
sudo iptables -I INPUT -p tcp -m tcp --dport 3128 -j ACCEPT
sudo iptables -I INPUT -p tcp -m tcp --dport 2525 -j ACCEPT

sudo systemctl daemon-reload

echo '#################################################################'
echo "3proxy installed & running now"
echo '#################################################################'

# . *.ru;*.github.com;*.google.com;*.youtube.com;*.digitalocean.com;*.telegram.org;*.tg.me;*.binance.com;*.huobi;*.okx;*.bybit;*.htx;*.sbrf;*.gpb;*.metamask
