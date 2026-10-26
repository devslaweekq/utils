#!/usr/bin/env bash

sudo apt install -y git curl build-essential libssl-dev zlib1g-dev mc

git clone https://github.com/TelegramMessenger/MTProxy
cd MTProxy
make
make clean

sudo cp objs/bin/mtproto-proxy /usr/bin/
chmod 775 /usr/bin/mtproto-proxy

cd /etc
sudo mkdir mtproto-proxy
cd mtproto-proxy

sudo curl -s https://core.telegram.org/getProxySecret -o proxy-secret
chmod 600 proxy-secret

sudo curl -s https://core.telegram.org/getProxyConfig -o proxy-multi.conf
chmod 600 proxy-multi.conf

sudo echo "curl -s  https://core.telegram.org/getProxyConfig -o /etc/mtproto-proxy/proxy-multi.conf" > /etc/cron.daily/mtproto-proxy
chmod 755 /etc/cron.daily/mtproto-proxy

# <SECRET>
head -c 16 /dev/urandom | xxd -ps

cat << EOF | sudo tee /etc/systemd/system/mtproto-proxy.service
[Unit]
Description=MTProxy
After=network.target
[Service]
ExecStart=/usr/bin/mtproto-proxy -u nobody -p 8287 -H 8443 -S <SECRET> --aes-pwd /etc/mtproto-proxy/proxy-secret /etc/mtproto-proxy/proxy-multi.conf -M 1
Restart=on-failure
[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl restart mtproto-proxy
sudo systemctl status mtproto-proxy
sudo systemctl enable mtproto-proxy

sudo echo "kernel.pid_max=65535" > /etc/sysctl.conf
sudo sysctl -p

# tg://proxy?server=<IP_SERVER>&port=<PORT>&secret=<SECRET>
# Sometimes, providers may detect MTProxy by packet size and block it.
# In this case, add the letters "dd" at the start of your secret. This will make random data be added to the packets.
