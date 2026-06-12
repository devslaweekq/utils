#!/usr/bin/env bash
# Remove XanMod + restore Ubuntu generic kernel and NVIDIA open driver
set -euo pipefail

readonly CODENAME="resolute"
readonly KERNEL_PKG="linux-xanmod-x64v3"
readonly NVIDIA_PKG="nvidia-driver-595-open"
readonly XANMOD_KEY="/etc/apt/keyrings/xanmod-archive-keyring.gpg"
readonly XANMOD_LIST="/etc/apt/sources.list.d/xanmod-release.list"
readonly GRUB_IBT="/etc/default/grub.d/99-xanmod-nvidia-ibt-off.cfg"

log() { echo "[xanmod-uninstall] $*" >&2; }

show_help() {
  cat <<EOF
Usage: $(basename "$0") [OPTION]

Remove XanMod and restore stock Ubuntu setup:
  generic kernel (default GRUB entry)
  ${NVIDIA_PKG} from Ubuntu repos
  GRUB settings as before install (no ibt=off, GRUB_DEFAULT=0)

Removes:
  ${KERNEL_PKG} and related packages
  XanMod NVIDIA driver
  XanMod APT repo

Options:
  -h, --help    Show this help
  --reboot      Reboot after uninstall

After reboot, verify:
  uname -r
  cat /proc/cmdline
  nvidia-smi
EOF
}

restore_grub() {
  [[ -f "${GRUB_IBT}" ]] && sudo rm -f "${GRUB_IBT}"

  if grep -q '^GRUB_DEFAULT=' /etc/default/grub; then
    sudo sed -i 's|^GRUB_DEFAULT=.*|GRUB_DEFAULT=0|' /etc/default/grub
  else
    echo 'GRUB_DEFAULT=0' | sudo tee -a /etc/default/grub >/dev/null
  fi

  sudo sed -i '/^GRUB_SAVEDEFAULT=/d' /etc/default/grub
  sudo update-grub
  log "GRUB restored (default entry, ibt=off removed)"
}

remove_xanmod_packages() {
  local pkgs=()
  mapfile -t pkgs < <(dpkg-query -W -f='${Package}\n' 'linux-*xanmod*' 2>/dev/null || true)
  if ((${#pkgs[@]})); then
    sudo apt purge -y "${pkgs[@]}"
  fi
  sudo apt purge -y "${KERNEL_PKG}" 2>/dev/null || true
}

remove_nvidia() {
  sudo apt purge -y "${NVIDIA_PKG}" 2>/dev/null || true
}

remove_repo() {
  [[ -f "${XANMOD_LIST}" ]] && sudo rm -f "${XANMOD_LIST}"
  [[ -f "${XANMOD_KEY}" ]] && sudo rm -f "${XANMOD_KEY}"
  sudo apt update
}

install_ubuntu_nvidia() {
  sudo apt install -y "${NVIDIA_PKG}"
}

main() {
  case "${1:-}" in
    -h|--help) show_help; exit 0 ;;
    ""|--reboot) ;;
    *) log "Unknown option: $1 (try --help)"; exit 1 ;;
  esac

  command -v apt >/dev/null || { log "apt not found"; exit 1; }
  [[ "$(lsb_release -sc)" == "${CODENAME}" ]] || log "Warning: expected Ubuntu ${CODENAME}, got $(lsb_release -sc)"
  [[ "$(uname -r)" == *xanmod* ]] && log "Running on XanMod kernel — reboot into generic after script finishes"

  restore_grub
  remove_xanmod_packages
  remove_nvidia
  remove_repo
  install_ubuntu_nvidia

  sudo dpkg --configure -a
  sudo apt install -y -f
  sudo update-initramfs -u -k all
  sudo apt autoremove -y

  echo
  log "Done. Reboot to use Ubuntu generic kernel."
  log "Verify: uname -r && nvidia-smi"
  echo

  if [[ "${1:-}" == "--reboot" ]]; then
    sudo reboot
  fi
}

main "$@"
