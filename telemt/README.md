# Telemt MTProto Proxy (Docker)

This directory contains a **one‑file installer** for running the [Telemt](https://github.com/whn0thacked/telemt) MTProto proxy inside Docker.

The goal: run a masked MTProto proxy that looks like normal HTTPS traffic to `1c.ru`, with **two independent users**, without manually editing config files on the server.

---

## Quick install from GitHub

From your server:

```bash
cd ~
curl -o telemt-install.sh https://raw.githubusercontent.com/devslaweekq/utils/main/telemt/install.sh
chmod +x telemt-install.sh
sudo ./telemt-install.sh
```

This will download the latest `install.sh` from the repository and run it.

---

## What the installer does

File: `install.sh`

- Installs Docker and Docker Compose plugin if they are not present.
- Creates the directory `/root/mtproxy-telemt`.
- Generates:
  - `docker-compose.yml` – container definition for Telemt.
  - `telemt.toml` – Telemt configuration.
- Creates **two users**:
  - `user1` with a random 16‑byte hex secret.
  - `user2` with a random 16‑byte hex secret.
- Binds container port `443` to **host port `7443`**:
  - From Internet clients you connect to `SERVER_IP:7443`.
- Starts the container with `docker compose up -d`.
- Prints:
  - The secrets for both users.
  - A `curl` command to verify TLS masking.

---

## How to run on the server

1. Copy `install.sh` to the server (for example to `/root`).
2. Make it executable:

   ```bash
   chmod +x install.sh
   ```

3. Run as root:

   ```bash
   sudo ./install.sh
   ```

The script will:

- Install Docker if needed.
- Create `/root/mtproxy-telemt`.
- Start the `telemt` container.

You should see something like:

```text
Secrets:
  user1: 0123abcd...
  user2: 89ef0123...
Host port: 7443 -> container port 443
Config directory: /root/mtproxy-telemt
```

Use these secrets in your Telegram clients when adding an MTProto proxy.

---

## Files created on the server

In `/root/mtproxy-telemt`:

- `docker-compose.yml`

  ```yaml
  services:
    telemt:
      image: whn0thacked/telemt-docker:latest
      container_name: telemt
      restart: unless-stopped
      environment:
        RUST_LOG: "info"
      volumes:
        - ./telemt.toml:/etc/telemt.toml:ro
      ports:
        - "7443:443/tcp"
      security_opt:
        - no-new-privileges:true
      cap_drop:
        - ALL
      cap_add:
        - NET_BIND_SERVICE
      read_only: true
      tmpfs:
        - /tmp:rw,nosuid,nodev,noexec,size=16m
      deploy:
        resources:
          limits:
            cpus: "0.50"
            memory: 256M
  ```

- `telemt.toml` (generated, core structure):

  ```toml
  show_link = ["user1","user2"]

  [general]
  prefer_ipv6 = false
  fast_mode = true
  use_middle_proxy = false

  [general.modes]
  classic = false
  secure = false
  tls = true

  [server]
  port = 443
  listen_addr_ipv4 = "0.0.0.0"
  listen_addr_ipv6 = "::"

  [censorship]
  tls_domain = "1c.ru"
  mask = true
  mask_port = 443
  fake_cert_len = 2048

  [access.users]
  user1 = "RANDOM_SECRET_FOR_USER1"
  user2 = "RANDOM_SECRET_FOR_USER2"

  [[upstreams]]
  type = "direct"
  enabled = true
  weight = 10
  ```

> Do not edit the secrets in `telemt.toml` manually while the container is running; instead, stop the container, edit the file and then run `docker compose up -d` again.

---

## How to verify TLS masking

At the end of `install.sh` output you will see a command like:

```bash
curl -v -I --resolve 1c.ru:443:SERVER_IP https://1c.ru/
```

Run it **from any machine on the Internet**. If you see:

- a valid `*.1c.ru` TLS certificate and
- `HTTP/1.1 200 OK`,

then your Telemt proxy is successfully masked as normal HTTPS traffic to `1c.ru`.
