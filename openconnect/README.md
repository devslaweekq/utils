## OpenConnect VPN (ocserv) on Ubuntu

Official ocserv docs: <https://ocserv.openconnect-vpn.net/ocserv.8.html>

This folder is now **config-first**:

- edit `openconnect/ocserv.conf` (main working config template)
- apply with `openconnect/install.sh`
- optionally manage with `openconnect/menu.sh`

Manual step-by-step server setup has been removed from this README to avoid duplicate/legacy instructions.

### Main files

- `openconnect/ocserv.conf` — primary server config template (contains comments with default values).
- `openconnect/install.sh` — installs/configures ocserv and copies template to `/etc/ocserv/ocserv.conf`.
- `openconnect/menu.sh` — interactive management menu (install/status/users/uninstall).
- `openconnect/install-client-gui-ubuntu.sh` — installs OpenConnect GUI integration on Ubuntu.

### Recommended workflow

1. Adjust `openconnect/ocserv.conf` in this repo.
2. Run installer (domain or IP mode).
3. Create VPN user(s).
4. Connect from client.

### Server install

#### Option A: Interactive menu (recommended)

```bash
sudo bash openconnect/menu.sh
```

Menu supports:

- install with domain + existing cert/key
- install self-signed (IP-only)
- service status
- list/add/delete users
- uninstall all items installed by this workflow

#### Option B: Direct installer

```bash
# Domain mode (Let's Encrypt)
sudo bash openconnect/install.sh --domain vpn.example.com --email admin@example.com

# Domain mode (reuse existing cert files, no certbot)
sudo bash openconnect/install.sh \
  --domain vpn.example.com \
  --cert /etc/letsencrypt/live/vpn.example.com/fullchain.pem \
  --key /etc/letsencrypt/live/vpn.example.com/privkey.pem \
  --skip-cert

# IP-only mode (self-signed)
sudo bash openconnect/install.sh --ip-only
```

Notes:

- If `443` is already occupied, installer auto-switches ocserv to `8443`.
- `ocserv` must not be proxied with `nginx proxy_pass http://...` (it is not a plain HTTP backend).

### Create users (required)

Installer/menu does not auto-create users in the current flow.

```bash
sudo ocpasswd -c /etc/ocserv/ocpasswd <username>
```

### Client setup

#### Ubuntu CLI

```bash
sudo apt install -y openconnect
sudo openconnect --protocol=anyconnect <YOUR-DOMAIN>:8443 -u <username>
```

If TUN permission error appears, run as root (`sudo`) and ensure `/dev/net/tun` exists.

#### Ubuntu GUI (NetworkManager)

```bash
sudo bash openconnect/install-client-gui-ubuntu.sh
```

Then add VPN:

- Protocol: `Cisco AnyConnect or OpenConnect`
- Gateway: `<YOUR-DOMAIN>:8443` (or your host/port)
- For unstable UDP paths, enable `Disable UDP (DTLS and ESP)`.

#### iOS

Use **Cisco Secure Client** (App Store):

- Server: `<YOUR-DOMAIN>:8443` (or your host/port)
- Username/password: from `ocpasswd`

### Quick verification

```bash
sudo systemctl status ocserv --no-pager
sudo ss -lntup | rg ':(443|8443)\b'
```
