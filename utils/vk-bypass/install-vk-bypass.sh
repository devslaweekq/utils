#!/usr/bin/env bash
# Installs a systemd job that applies vk-bypass.sh at boot
# and refreshes the rules every 6 hours (VK IP addresses change).
#
# Usage:
#   install-vk-bypass.sh install     install the script and the timer
#   install-vk-bypass.sh uninstall   remove the timer, the rules and the files
#   install-vk-bypass.sh status      timer state and the last run
#
# DRY_RUN=1 install-vk-bypass.sh install  only print the actions, change nothing.
#
# What it touches: /usr/local/sbin/vk-bypass.sh and two files in /etc/systemd/system/
# (vk-bypass.service, vk-bypass.timer). vk-bypass.sh itself only changes ip rule.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$HERE/vk-bypass.sh"
BIN=/usr/local/sbin/vk-bypass.sh
UNIT_DIR=/etc/systemd/system
DRY_RUN="${DRY_RUN:-0}"

run() {
  if [[ "$DRY_RUN" == "1" ]]; then
    echo "[dry-run] $*"
  elif [[ $EUID -ne 0 ]]; then
    sudo "$@"
  else
    "$@"
  fi
}

write_unit() { # $1 = path, content on stdin
  if [[ "$DRY_RUN" == "1" ]]; then
    echo "[dry-run] writing $1:"
    sed 's/^/    /'
  else
    run tee "$1" >/dev/null
  fi
}

cmd_install() {
  [[ -f "$SRC" ]] || { echo "Not found: $SRC" >&2; exit 1; }
  run install -m 0755 "$SRC" "$BIN"

  write_unit "$UNIT_DIR/vk-bypass.service" <<EOF
[Unit]
Description=Direct route to VK, bypassing Tailscale exit node
After=network-online.target tailscaled.service
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=$BIN on
EOF

  write_unit "$UNIT_DIR/vk-bypass.timer" <<EOF
[Unit]
Description=Apply VK bypass at boot and refresh every 6 hours

[Timer]
OnBootSec=30s
OnUnitActiveSec=6h

[Install]
WantedBy=timers.target
EOF

  run systemctl daemon-reload
  run systemctl enable --now vk-bypass.timer
  echo "Done. The first run is ~30 seconds after boot, or right after enable."
}

cmd_uninstall() {
  run systemctl disable --now vk-bypass.timer || true
  [[ -x "$BIN" ]] && run "$BIN" off || true
  run rm -f "$UNIT_DIR/vk-bypass.service" "$UNIT_DIR/vk-bypass.timer" "$BIN"
  run systemctl daemon-reload
  echo "Removed: the timer, the routing rules and the files."
}

cmd_status() {
  systemctl list-timers vk-bypass.timer --no-pager || true
  systemctl status vk-bypass.service --no-pager -n 10 || true
}

case "${1:-}" in
  install) cmd_install ;;
  uninstall) cmd_uninstall ;;
  status) cmd_status ;;
  *) echo "Usage: $0 {install|uninstall|status}   (DRY_RUN=1 for a dry run)" >&2; exit 1 ;;
esac
