### then on my local pc init ssh key
If no ssh keys
```
sudo ufw allow ssh
cd ~
mkdir -p ~/.ssh
chmod 700 ~/.ssh
cd ~/.ssh
ssh-keygen -t ed25519 -C "plakidin.vyacheslav@mail.ru"
chmod 600 ~/.ssh/id_ed25519
chmod 600 ~/.ssh/id_ed25519.pub
cd -
eval "$(ssh-agent -s)" && ssh-add ~/.ssh/id_ed25519
ssh-copy-id -i ~/.ssh/id_ed25519.pub msi@64.227.69.234 pswd user->enter
```
### after connect to droplet
`ssh 64.227.69.234`

### check adding keys

```
sudo nano ~/.ssh/authorized_keys
// edit config
sudo nano /etc/ssh/sshd_config
```
```
# PermitRootLogin no
# PubkeyAuthentication yes
# AuthorizedKeysFile      .ssh/authorized_keys .ssh/authorized_keys2
# PasswordAuthentication no
# PermitEmptyPasswords no ???
# sudo systemctl restart sshd
```

### Install NVM & npm

```
cd ~
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/master/install.sh | bash
source ~/.bashrc
nvm ls-remote
VERSION=20.13.1
nvm install $VERSION
nvm use $VERSION
nvm alias default $VERSION
sudo chown -R "$USER":"$USER" ~/.npm
sudo chown -R "$USER":"$USER" ~/.nvm
npm i -g pm2@latest nodemon serve
sudo npm i -g pm2@latest nodemon serve
nvm ls
```


### npm service
```
# sudo npm i
# sudo pm2 start bot.js
# sudo pm2 startup systemd
# sudo pm2 save
# sudo systemctl start pm2-root
# sudo systemctl status pm2-root
# sudo reboot
# sudo systemctl stop pm2-root
# sudo pm2 stop bot
# sudo pm2 restart bot
# sudo pm2 list
# sudo pm2 info app_name
# sudo pm2 monit
```





### https://habr.com/ru/articles/594877/

```
echo "Installing DNS-proxy"
echo "

"
git clone https://github.com/AdguardTeam/dnsproxy.git \
  && cd dnsproxy \
  && go build -mod=vendor

./dnsproxy -u sdns://AgcAAAAAAAAABzEuMC4wLjGgENk8mGSlIfMGXMOlIlCcKvq7AVgcrZxtjon911-ep0cg63Ul-I8NlFj4GplQGb_TTLiczclX57DvMV8Q-JdjgRgSZG5zLmNsb3VkZmxhcmUuY29tCi9kbnMtcXVlcnk
```

### This key is taken from the dnsproxy project documentation on github.com `https://github.com/AdguardTeam/dnsproxy`. You can use other encryption types if you wish; examples are provided there.

### Then add rules for recursive DNS:

```
sudo iptables -A INPUT -s 10.20.20.0/24 -p tcp -m tcp --dport 53 -m conntrack --ctstate NEW -j ACCEPT
sudo iptables -A INPUT -s 10.20.20.0/24 -p udp -m udp --dport 53 -m conntrack --ctstate NEW -j A
```


### Replace the virtual IP addresses `10.20.20.0/24` with the subnet of your WireGuard network.

### To persist the routes, install and configure iptables-persistent

```
sudo apt install -y iptables-persistent

echo iptables-persistent iptables-persistent/autosave_v4 boolean true | sudo debconf-set-selections
echo iptables-persistent iptables-persistent/autosave_v6 boolean true | sudo debconf-set-selections
sudo apt install -y iptables-persistent -y
sudo systemctl enable netfilter-persistent
sudo netfilter-persistent save
```


### Install Pi-hole to block ads.
```
sudo curl -sSL https://install.pi-hole.net | bash
```

#### After the installer starts, choose the virtual interface of your WireGuard (`wg0`). Then press Enter and at the end save the password for the program web interface.




# 5. Proceed to installation and configuration of your own DNS server.

# Install Unbound DNS:
sudo apt install -y unbound unbound-host -y
# Download DNS root hints:
curl -o /var/lib/unbound/root.hints https://www.internic.net/domain/named.cache
# Create config `/etc/unbound/unbound.conf.d/pi-hole.conf`

nano /etc/unbound/unbound.conf.d/pi-hole.conf
# Copy this configuration there:

```
server:
     # if no logfile is specified, syslog is used
     # logfile: "/var/log/unbound/unbound.log"
     verbosity: 1
     port: 5353

     do-ip4: yes
     do-udp: yes
     do-tcp: yes

     # may be set to yes if you have IPv6 connectivity
     do-ip6: no

     # use this only when you downloaded the list of primary root servers
     root-hints: "/var/lib/unbound/root.hints"

     # respond to DNS requests on all interfaces
     interface: 0.0.0.0
     max-udp-size: 3072

     # IPs authorised to access the DNS Server
     access-control: 0.0.0.0/0                 refuse
     access-control: 127.0.0.1                 allow
     access-control: 10.20.20.0/24             allow

     # hide DNS Server info
     hide-identity: yes
     hide-version: yes

     # limit DNS fraud and use DNSSEC
     harden-glue: yes
     harden-dnssec-stripped: yes
     harden-referral-path: yes

     # add an unwanted reply threshold to clean the cache and avoid, when possible, DNS poisoning
     unwanted-reply-threshold: 10000000

     # have the validator print validation failures to the log val-log-level: 1
     # don't use Capitalisation randomisation as it known to cause DNSSEC issues sometimes
     # see https://discourse.pi-hole.net/t/unbound-stubby-or-dnscrypt-proxy/9378 for further details
     use-caps-for-id: no

     # reduce EDNS reassembly buffer size
     # suggested by the unbound man page to reduce fragmentation reassembly problems
     edns-buffer-size: 1472

     # TTL bounds for cache
     cache-min-ttl: 3600
     cache-max-ttl: 86400

     # perform prefetching of close to expired message cache entries
     # this only applies to domains that have been frequently queried
     prefetch: yes
     prefetch-key: yes
     # one thread should be sufficient, can be increased on beefy machines
     num-threads: 1
     # ensure kernel buffer is large enough to not lose messages in traffic spikes
     so-rcvbuf: 1m

     # ensure privacy of local IP ranges
     private-address: 192.168.0.0/16
     private-address: 169.254.0.0/16
     private-address: 172.16.0.0/12
     private-address: 10.0.0.0/8
     private-address: fd00::/8
     private-address: fe80::/10
```

- Replace the virtual address `access-control: 10.20.20.0/24` with the address of your own subnet.

- Reboot the server with `reboot` and verify the DNS server with the commands:

dig pi-hole.net @127.0.0.1 -p 5353

dig sigfail.verteiltesysteme.net @127.0.0.1 -p 5353

dig sigok.verteiltesysteme.net @127.0.0.1 -p 5353

- In the first and third case the status should be `NOERROR`, and in the second case `SERVFAIL`. If the output matches this, everything is working correctly.

- Next open the Pi-hole web interface in a browser. The address will be the same as the VPS server address plus `/admin` (for example `http://185.18.55.137/admin`). Go to the settings tab and configure it as on your reference screenshot.

- At the bottom you can also enable the `Use DNSSEC` checkbox and save.

- It is a good idea to restrict access to the Pi-hole web interface so it cannot be brute-forced. We will allow access only from the internal subnet:

iptables -A INPUT -s 10.55.55.0/24 -p tcp --dport 80 -j ACCEPT

iptables -A INPUT -p tcp --dport 80 -j DROP
- Also remember to replace `10.55.55.0/24` with your own virtual network here.

- 6. To test all configured services, open these links:

- DNS leak test `https://dnsleak.com/`
- and `https://www.dnsleaktest.com/` — the DNS server address there should match the public IP address of your VPS server.

# P.S.

- For greater effectiveness of Pi-hole you can add additional sources with blocklists for filtering unwanted traffic. For example:

- http://sysctl.org/cameleon/hosts

- https://s3.amazonaws.com/lists.disconnect.me/simple_tracking.txt

- https://s3.amazonaws.com/lists.disconnect.me/simple_ad.txt

- https://easylist-downloads.adblockplus.org/easyprivacy.txt

- https://easylist-downloads.adblockplus.org/easylist.txt

- http://www.fanboy.co.nz/adblock/opera/urlfilter.ini

- http://www.fanboy.co.nz/adblock/fanboy-tracking.txt

- http://phishing.mailscanner.info/phishing.bad.sites.conf

- https://zeltser.com/malicious-ip-blocklists/

- Additional lists can be downloaded from `https://firebog.net/`.

- They are added via the Pi-hole web interface.

- As a result we have our own VPN server abroad (and thus the ability to visit the desired resources), our own DNS server with encrypted traffic, and an ad blocker as a pleasant bonus. Blocking efficiency is not 100%, but almost twice as good as the default. Ads are blocked not only in the browser but also in mobile apps.

```
# echo "Installing wireguard"
# echo '#################################################################'
# cd ~
# wget https://git.io/wireguard -O wireguard-install.sh && sudo bash wireguard-install.sh
# curl -O https://raw.githubusercontent.com/angristan/wireguard-install/master/wireguard-install.sh
# chmod +x wireguard-install.sh
# sudo ./wireguard-install.sh

# ssh-keygen -f "/home/msi/.ssh/known_hosts" -R "178.128.17.181"

# curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/jammy.noarmor.gpg | \
#   sudo tee /usr/share/keyrings/tailscale-archive-keyring.gpg >/dev/null
# curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/jammy.tailscale-keyring.list | \
#   sudo tee /etc/apt/sources.list.d/tailscale.list
# sudo apt update
# sudo apt install -y tailscale
# sudo tailscale up
# tailscale ip -4
# 2C-4D-54-E9-02-BD
```
