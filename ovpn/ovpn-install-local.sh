curl -fsSL https://packages.openvpn.net/packages-repo.gpg | \
  sudo tee /etc/apt/trusted.gpg.d/openvpn.asc

echo "deb [arch=amd64 signed-by=/etc/apt/trusted.gpg.d/openvpn.asc] https://packages.openvpn.net/openvpn3/debian lunar main" | \
sudo tee /etc/apt/sources.list.d/openvpn-packages.list

sudo apt update
sudo apt install -y openvpn3

cp /mnt/D/CRYPTO/setup/vpn/msi.ovpn ./msi.ovpn
openvpn3 config-import --config ./msi.ovpn --name OpenVpnDO --persistent
# /net/openvpn/v3/configuration/1beaec38x7a23x4ea2x8f59x933930624b17
openvpn3 config-acl --show --lock-down true --grant root --config OpenVpnDO
sudo systemctl enable --now openvpn3-session@OpenVpnDO.service
openvpn3 configs-list
openvpn3 sessions-list
