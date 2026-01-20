#!/bin/bash

echo "Deleting 3proxy"
sudo systemctl stop 3proxy.service
sudo rm -rf /etc/systemd/system/3proxy.service /etc/3proxy /usr/bin/3proxy
sudo systemctl daemon-reload
echo "3proxy deleted"
  # && sudo rm -rf /var/log/3proxy \
