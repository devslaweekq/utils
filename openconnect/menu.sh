#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_SH="${SCRIPT_DIR}/install.sh"

PASSWD_FILE="/etc/ocserv/ocpasswd"
CONF_FILE="/etc/ocserv/ocserv.conf"
SYSCTL_FILE="/etc/sysctl.d/60-ocserv.conf"
UFW_BEFORE="/etc/ufw/before.rules"

need_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    echo "ERROR: run as root (use sudo)" >&2
    exit 1
  fi
}

prompt() {
  local label="$1"
  local out_var="$2"
  local value=""
  read -r -p "${label}: " value
  printf -v "${out_var}" "%s" "${value}"
}

pause() {
  read -r -p "Press Enter to continue... " _
}

clear_screen() {
  if command -v clear >/dev/null 2>&1; then
    clear
  else
    printf "\033c"
  fi
}

page() {
  # Run an action as a "page": clear -> run -> wait -> return.
  clear_screen
  "$@"
  echo
  pause
}

infer_port_from_conf() {
  if [[ -f "${CONF_FILE}" ]]; then
    awk -F= '
      $1 ~ /^[[:space:]]*tcp-port[[:space:]]*$/ {
        gsub(/[[:space:]]/, "", $2);
        print $2; exit
      }' "${CONF_FILE}" 2>/dev/null || true
  fi
}

listener_summary() {
  local port="$1"
  local tcp udp
  tcp="$(ss -lntup "( sport = :${port} )" 2>/dev/null | awk 'NR==2{print}')"
  udp="$(ss -lnup "( sport = :${port} )" 2>/dev/null | awk 'NR==2{print}')"

  if [[ -n "${tcp}" ]]; then
    echo "TCP: listening"
    echo "TCP owner: ${tcp}"
  else
    echo "TCP: not listening"
  fi

  if [[ -n "${udp}" ]]; then
    echo "UDP: listening"
    echo "UDP owner: ${udp}"
  else
    echo "UDP: not listening"
  fi
}

infer_subnet_from_conf() {
  # returns CIDR if possible, else empty
  if [[ -f "${CONF_FILE}" ]]; then
    net="$(awk -F= '$1 ~ /^[[:space:]]*ipv4-network[[:space:]]*$/ {gsub(/[[:space:]\"]/, "", $2); print $2; exit}' "${CONF_FILE}" 2>/dev/null || true)"
    mask="$(awk -F= '$1 ~ /^[[:space:]]*ipv4-netmask[[:space:]]*$/ {gsub(/[[:space:]\"]/, "", $2); print $2; exit}' "${CONF_FILE}" 2>/dev/null || true)"
    if [[ -n "${net}" && "${mask}" == "255.255.255.0" ]]; then
      echo "${net}/24"
      return 0
    fi
  fi
  return 1
}

install_domain() {
  need_root
  if [[ ! -x "${INSTALL_SH}" ]]; then
    echo "ERROR: ${INSTALL_SH} is not executable or missing" >&2
    return 1
  fi

  local domain cert key
  prompt "Domain (e.g. oc.example.com)" domain
  prompt "Path to certificate (fullchain.pem)" cert
  prompt "Path to private key (privkey.pem)" key

  bash "${INSTALL_SH}" \
    --domain "${domain}" \
    --cert "${cert}" \
    --key "${key}" \
    --skip-cert

  echo
  echo "Next step: create a VPN user:"
  echo "  sudo ocpasswd -c ${PASSWD_FILE} <username>"
}

install_self_signed() {
  need_root
  if [[ ! -x "${INSTALL_SH}" ]]; then
    echo "ERROR: ${INSTALL_SH} is not executable or missing" >&2
    return 1
  fi

  bash "${INSTALL_SH}" --ip-only

  echo
  echo "Next step: create a VPN user:"
  echo "  sudo ocpasswd -c ${PASSWD_FILE} <username>"
}

show_status() {
  need_root
  local port domain
  port="$(infer_port_from_conf || true)"
  port="${port:-8443}"
  domain=""
  if [[ -f "${CONF_FILE}" ]]; then
    domain="$(awk -F= '$1 ~ /^[[:space:]]*default-domain[[:space:]]*$/ {gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2); gsub(/"/, "", $2); print $2; exit}' "${CONF_FILE}" 2>/dev/null || true)"
  fi

  echo "=== ocserv ==="
  if systemctl is-active ocserv >/dev/null 2>&1; then
    echo "Service: running"
  else
    echo "Service: NOT running (systemd)"
  fi
  echo "Port: ${port}"
  if [[ -n "${domain}" ]]; then
    echo "Connect: https://${domain}:${port}"
  else
    echo "Connect: https://<SERVER_IP>:${port}"
  fi
  echo

  echo "=== listeners (port ${port}) ==="
  listener_summary "${port}"
  echo

  echo "=== systemd status (brief) ==="
  systemctl --no-pager --full -l status ocserv 2>/dev/null | sed -n '1,20p' || true
}

list_users() {
  need_root
  if [[ ! -f "${PASSWD_FILE}" ]]; then
    echo "No users file at ${PASSWD_FILE}"
    return 0
  fi
  echo "Users in ${PASSWD_FILE}:"
  awk -F: 'NF>=1 && $1!="" {print $1}' "${PASSWD_FILE}" | sort -u
}

add_user() {
  need_root
  local user
  prompt "Username" user
  if [[ -z "${user}" ]]; then
    echo "ERROR: empty username" >&2
    return 1
  fi
  ocpasswd -c "${PASSWD_FILE}" "${user}"
}

delete_user() {
  need_root
  if [[ ! -f "${PASSWD_FILE}" ]]; then
    echo "No users file at ${PASSWD_FILE}"
    return 0
  fi

  mapfile -t users < <(awk -F: 'NF>=1 && $1!="" {print $1}' "${PASSWD_FILE}" | sort -u)
  if [[ ${#users[@]} -eq 0 ]]; then
    echo "No users found."
    return 0
  fi

  echo "Select user to delete:"
  local i
  for i in "${!users[@]}"; do
    printf "  %d) %s\n" "$((i+1))" "${users[$i]}"
  done

  local sel
  read -r -p "Select number (or 0 to cancel): " sel
  if [[ "${sel}" == "0" ]]; then
    echo "Cancelled."
    return 0
  fi
  if ! [[ "${sel}" =~ ^[0-9]+$ ]]; then
    echo "ERROR: invalid selection" >&2
    return 1
  fi
  if (( sel < 1 || sel > ${#users[@]} )); then
    echo "ERROR: selection out of range" >&2
    return 1
  fi

  ocpasswd -c "${PASSWD_FILE}" -d "${users[$((sel-1))]}"
}

uninstall_all() {
  need_root
  echo "This will stop ocserv, remove configs created/used by this script, remove UFW ocserv NAT block, and purge ocserv package."
  read -r -p "Type 'YES' to continue: " confirm
  if [[ "${confirm}" != "YES" ]]; then
    echo "Cancelled."
    return 0
  fi

  systemctl stop ocserv >/dev/null 2>&1 || true
  systemctl disable ocserv >/dev/null 2>&1 || true
  pkill -f ocserv >/dev/null 2>&1 || true

  # Remove ocserv NAT block + forward rules for its subnet from UFW before.rules
  if [[ -f "${UFW_BEFORE}" ]]; then
    subnet="$(infer_subnet_from_conf || true)"
    subnet="${subnet:-10.10.10.0/24}"
    cp -a "${UFW_BEFORE}" "${UFW_BEFORE}.bak.$(date +%Y%m%d%H%M%S)"
    sed -i '/# ocserv-nat-begin/,/# ocserv-nat-end/d' "${UFW_BEFORE}" || true
    sed -i \
      -e "/^-A ufw-before-forward -s ${subnet//\//\\/} -j ACCEPT$/d" \
      -e "/^-A ufw-before-forward -d ${subnet//\//\\/} -j ACCEPT$/d" \
      "${UFW_BEFORE}" || true
    systemctl restart ufw >/dev/null 2>&1 || true
  fi

  rm -f "${SYSCTL_FILE}" || true
  sysctl --system >/dev/null 2>&1 || true

  rm -f "${PASSWD_FILE}" || true
  rm -f "${CONF_FILE}" || true
  rm -rf /etc/ocserv/ssl || true

  apt-get remove --purge -y ocserv || true
  apt-get autoremove -y || true

  echo "Done."
}

main() {
  while true; do
    clear_screen
    echo
    echo "OpenConnect (ocserv) menu"
    echo "1) Install for domain (provide domain + cert/key paths; do NOT create user)"
    echo "2) Install self-signed (IP-only; do NOT create user)"
    echo "3) Status"
    echo "4) List users"
    echo "5) Add user"
    echo "6) Delete user"
    echo "7) Uninstall everything related to ocserv"
    echo "0) Exit"
    echo
    read -r -p "Select: " choice

    case "${choice}" in
      1) page install_domain;;
      2) page install_self_signed;;
      3) page show_status;;
      4) page list_users;;
      5) page add_user;;
      6) page delete_user;;
      7) page uninstall_all;;
      0) exit 0;;
      *) echo "Unknown option";;
    esac
  done
}

main "$@"

