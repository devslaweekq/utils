#!/usr/bin/env bash
# Sends VK traffic around the Tailscale exit node (directly through the regular connection).
#
# How it works: Tailscale routes traffic into table 52 with a rule at priority 5270.
# We add rules at priority 5200 (earlier) that send VK addresses to the main table,
# i.e. through the regular gateway.
#
# Usage:
#   vk-bypass.sh on       add the rules
#   vk-bypass.sh off      delete all rules with our priority
#   vk-bypass.sh status   show the current rules
#
# DRY_RUN=1 vk-bypass.sh on  only print what would be done, change nothing.

set -euo pipefail

PRIO=5200
DOMAINS=(vk.com vk.ru userapi.com vkuser.net vk-cdn.net mycdn.me)
ASNS=(AS47541 AS47542 AS47764)   # VK and Mail.ru Group
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

collect_targets() {
  local d asn
  for d in "${DOMAINS[@]}"; do
    dig +short +time=3 +tries=1 "$d" A 2>/dev/null | grep -E '^[0-9]+(\.[0-9]+){3}$' | sed 's|$|/32|' || true
  done
  if command -v whois >/dev/null; then
    for asn in "${ASNS[@]}"; do
      whois -h whois.radb.net -- "-i origin $asn" 2>/dev/null \
        | awk '/^route:/{print $2}' | grep -E '^[0-9]+(\.[0-9]+){3}/[0-9]+$' || true
    done
  else
    echo "whois is not installed: ASN ranges skipped (sudo apt install whois)" >&2
  fi
}

cmd_on() {
  local existing added=0 skipped=0 net key
  existing="$(ip rule show)"
  while read -r net; do
    key="${net%/32}"
    if grep -qF " to $key lookup main" <<<"$existing"; then
      skipped=$((skipped + 1))
      continue
    fi
    run ip rule add to "$net" lookup main priority "$PRIO"
    added=$((added + 1))
  done < <(collect_targets | sort -u)
  echo "Rules added: $added, already present: $skipped"
}

cmd_off() {
  local n=0
  while ip rule show | grep -q "^${PRIO}:"; do
    run ip rule del priority "$PRIO" || break
    n=$((n + 1))
    [[ "$DRY_RUN" == "1" ]] && break
  done
  echo "Rules removed: $n"
}

cmd_status() {
  local count
  count="$(ip rule show | grep -c "^${PRIO}:" || true)"
  echo "Rules with priority $PRIO: $count"
  ip rule show | grep "^${PRIO}:" | head -20 || true
  [[ "$count" -gt 20 ]] && echo "... (first 20 shown)"
  return 0
}

case "${1:-}" in
  on) cmd_on ;;
  off) cmd_off ;;
  status) cmd_status ;;
  *) echo "Usage: $0 {on|off|status}   (DRY_RUN=1 for a dry run)" >&2; exit 1 ;;
esac
