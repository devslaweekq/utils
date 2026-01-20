curl -O https://raw.githubusercontent.com/angristan/openvpn-install/master/openvpn-install.sh
chmod +x openvpn-install.sh
sudo ./openvpn-install.sh


# Step 1: Update and Upgrade Ubuntu
sudo apt update
sudo apt upgrade -y
# Step 2: Install OpenVPN
sudo apt install -y openvpn easy-rsa
# Step 3: Generate Certificates and Keys
make-cadir ~/openvpn-ca && cd ~/openvpn-ca
sudo tee -a ./vars <<< \
'
set_var EASYRSA_REQ_COUNTRY    "US"
set_var EASYRSA_REQ_PROVINCE   "California"
set_var EASYRSA_REQ_CITY       "San Francisco"
set_var EASYRSA_REQ_ORG        "Copyleft Certificate Co"
set_var EASYRSA_REQ_EMAIL      "me@example.net"
set_var EASYRSA_REQ_OU         "My Organizational Unit"'

./easyrsa init-pki
./easyrsa build-ca
./easyrsa gen-req server nopass
./easyrsa sign-req server server
./easyrsa gen-dh
openvpn --genkey --secret pki/ta.key
# Step 4: Configure OpenVPN
zcat \
  /usr/share/doc/openvpn/examples/sample-config-files/server.conf.gz | \
  sudo tee /etc/openvpn/server.conf > /dev/null

cp /root/openvpn-ca/pki/{ca.crt,dh.pem,ta.key} /etc/openvpn
cp /root/openvpn-ca/pki/issued/server.crt /etc/openvpn
cp /root/openvpn-ca/pki/private/server.key /etc/openvpn
# Edit the following content in the configuration file /etc/openvpn/server.conf:
ca ca.crt
cert server.crt
key server.key  # This file should be kept secret
dh dh.pem
;tls-auth ta.key 0
tls-crypt ta.key
# Enable IP Forwarding
sudo tee -a /etc/sysctl.conf <<< \
'net.ipv4.ip_forward=1
net.ipv6.conf.all.forwarding=1'
sudo sysctl -p
# Step 5: Start and Enable OpenVPN
sudo systemctl start openvpn@server
sudo systemctl enable openvpn@server
# sudo systemctl status openvpn@server
# Step 6: Configure Firewall
sudo ufw allow OpenVPN
sudo ufw disable
sudo ufw enable
sudo ufw status
# Step 7: Connect to OpenVPN Server

./easyrsa gen-req client1 nopass
./easyrsa sign-req client client1
cp pki/private/client1.key /etc/openvpn/client/
cp pki/issued/client1.crt /etc/openvpn/client/
cp pki/{ca.crt,ta.key} /etc/openvpn/client/

# Create a client configuration file into the /root/openvpn-ca directory to use as your base configuration:
cp /usr/share/doc/openvpn/examples/sample-config-files/client.conf /root/openvpn-ca/

remote my-server-1 1194 # my-server-1 is the server public IP
user nobody
group nogroup
;ca ca.crt
;cert client.crt
;key client.key
;tls-auth ta.key 1
key-direction 1

# Now create a script to compile the base configuration with the necessary certificate, key, and encryption files.
bash -c \
"cat << EOF > /root/openvpn-ca/config_gen.sh
#!/bin/bash
# First argument: Client identifier
KEY_DIR=/etc/openvpn/client
OUTPUT_DIR=/root
BASE_CONFIG=/root/openvpn-ca/client.conf
cat ${BASE_CONFIG} \
    <(echo -e '<ca>') \
    ${KEY_DIR}/ca.crt \
    <(echo -e '</ca>\n<cert>') \
    ${KEY_DIR}/${1}.crt \
    <(echo -e '</cert>\n<key>') \
    ${KEY_DIR}/${1}.key \
    <(echo -e '</key>\n<tls-crypt>') \
    ${KEY_DIR}/ta.key \
    <(echo -e '</tls-crypt>') \
    > ${OUTPUT_DIR}/${1}.ovpn
EOF"

# After writing the script, save and close the config_gen.sh file.
# Don’t forget to make the file executable by running:
chmod 700 /root/openvpn-ca/config_gen.sh
./config_gen.sh client1
