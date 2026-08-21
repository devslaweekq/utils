# AdGuard Home — split-DNS resolver (EU VPS)

Own DNS resolver for the `slaweekq.ru` VPS, meant to replace Google/Cloudflare DNS on the home router. Solves three problems at once:

- **RU ISP DNS injection** (StackOverflow/Google-type sites getting broken answers from the provider's own resolver) — bypassed, since this
  server does its own resolution and isn't subject to the RKN registry.
- **Privacy from RU-side logging** — queries go straight to this server instead of the ISP's resolver or a well-known public one
  (Google/Cloudflare), which are increasingly targeted by RKN and are themselves large third-party loggers.
- **VPN (3x-ui) getting worse under Google/Cloudflare DNS** — using a well-known public resolver is itself a distinguishable pattern; a
  private resolver on the same IP that already carries the working VLESS traffic adds no new fingerprint.

Does **not** replace the VPN — Instagram/Telegram/games keep going through 3x-ui as before, this only handles DNS resolution for everything
else.

## How it resolves

- `.ru` / `.su` / `.рф` and major RU CDNs (Yandex, VK, Mail.ru, Sber, Ozon, Wildberries, Avito, Rutube, Kinopoisk, MTS/Beeline/Megafon,
  Gosuslugi, 2GIS, Dzen) → forwarded to **Yandex DNS** (77.88.8.8 / 77.88.8.1), so CDN edge selection stays correct and fast. Mirrors the
  same split that's already in `OutlineAdminServer/x-ui/settings.now.json`'s `dns` block.
- Everything else → resolved from **this EU server** via Quad9 / Mullvad / Cloudflare (DoH/DoT), in parallel. The query never touches an RU
  resolver or RU network path.
- `edns_cs_enabled: true` — the real client subnet is passed upstream so foreign CDNs still route to a sane edge. This only matters for the
  RU-conditional branch and general CDN correctness; it does not expose anything to RU-side observers (queries never cross into RU network
  space in the first place).

Different from `utils/pihole/` (Pi-hole + Unbound) elsewhere in this repo — that one is a full recursive resolver for a local/home box
(Novosibirsk timezone in its compose file). This one is specifically for the EU VPS, forwards rather than recurses, and does the RU/ non-RU
split forwarding. Not currently wired together.

## Install

On the VPS, next to the existing `3x-ui` setup:

```bash
sudo bash install.sh
```

Idempotent — re-running it reuses the saved admin account and just re-applies the DNS settings above (useful after editing the upstream list
in `install.sh`).

Optional: pin the admin password instead of letting the script generate one:

```bash
ADGUARD_ADMIN_PASSWORD='your-password' sudo -E bash install.sh
```

What it touches on the host:

- `/etc/systemd/resolved.conf.d/adguardhome.conf` — disables systemd-resolved's stub listener on :53 so AdGuard Home can bind it (backs up
  `/etc/resolv.conf` once, if it wasn't already a systemd-resolved symlink).
- `/opt/AdGuardHome/` — AdGuard Home install (official upstream install script).
- `/root/.adguardhome_admin_credentials` — generated admin login (chmod 600).
- `ufw allow 53/tcp`, `ufw allow 53/udp`.

Doesn't touch `nginx`, `docker-compose.yml`, or anything else in `OutlineAdminServer` — no port conflicts with it (`80/443` nginx,
`3333/2096/2053` 3x-ui, `9000/9180/9001` nginx-ui, `8443` ocserv, `3128` 3proxy, `34376`/`51500-51512`/`8444` Xray inbounds — all untouched;
AdGuard Home only uses `53` and `9007` loopback-only).

## Point the TP-Link router at it

TP-Link AX5400 stock firmware has no OpenWrt support and no DoT/DoH — plain DNS via DHCP is the only option:

**Advanced → Network → DHCP Server**

- Primary DNS = the VPS's public IP (printed by the script on install; also `curl -4 ifconfig.me` on the server)
- Secondary DNS = `9.9.9.9` (Quad9) — fallback only, used if Primary doesn't answer, so the whole LAN doesn't lose DNS entirely if the VPS
  is ever down. Quad9 has no confirmed history of targeted blocking in RU, unlike Google/Cloudflare.

That's it — every device on the LAN now resolves through this server instead of Google/ Cloudflare. The 3x-ui VPN keeps working
independently for Instagram/Telegram/games.

## Security note: open resolver

Since the router can't do encrypted DNS or an authenticated tunnel, port 53 has to be open to the whole internet, unencrypted — that makes
this technically a public DNS resolver. Mitigations already in place: `ratelimit: 100` (qps), and it's not a well-known target the way
8.8.8.8 is. If your home IP turns out to be static (or you set up dynamic DNS for it), lock it down further:

```bash
ufw delete allow 53/tcp
ufw delete allow 53/udp
ufw allow from <your-home-ip> to any port 53 proto tcp
ufw allow from <your-home-ip> to any port 53 proto udp
```

## Admin UI

Bound to `127.0.0.1:9007` only (not exposed publicly). Access it via SSH tunnel:

```bash
ssh -L 9007:127.0.0.1:9007 <user>@<vps-ip>
# then open http://127.0.0.1:9007 locally
```

Login with the credentials from `/root/.adguardhome_admin_credentials`. From there you can also turn on ad/tracker blocklists (Filters → DNS
blocklists) — not enabled by default, this script only sets up the split-resolving.

## Tuning the split list

Edit `RU_DOMAINS` near the top of `install.sh`, then re-run it — the `dns_config` API call is idempotent and just overwrites the upstream
list.
