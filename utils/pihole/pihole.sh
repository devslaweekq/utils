mkdir -p ./{pihole_data,unbound_data}

touch ./unbound_data/{a,srv,forward}-records.conf

docker network create \
    --opt com.docker.network.bridge.name=br_vpn \
    --driver bridge --subnet 10.10.11.0/24 admin_network

docker network ls

sudo bash -c \
"cat << EOF > /etc/systemd/system/pihole.service
[Unit]
Description=Pihole and Unbound service
Requires=docker.service
After=docker.service

[Service]
Restart=always
RestartSec=5
WorkingDirectory=/opt/cursor/pihole
ExecStart=/usr/bin/docker compose up
ExecStop=/usr/bin/docker compose down

[Install]
WantedBy=multi-user.target
EOF"

dns.r4ven.me 10.10.11.100
localhost.r4ven.me 127.0.0.1
unbound.r4ven.me 10.10.11.200

systemctl enable --now pihole
systemctl start --now pihole

systemctl status pihole

systemctl restart systemd-resolved
resolvectl flush-caches

nslookup google.ru
resolvectl dns
resolvectl query google.ru

ping -c3 dns.r4ven.me
ping -c3 localhost.r4ven.me
ping -c3 unbound.r4ven.me
