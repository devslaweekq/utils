#!/usr/bin/env bash
# XanMod + NVIDIA for MSI Creator Z17 / i7-12700H / RTX 3070 Ti / Ubuntu 26.04
set -euo pipefail

readonly CODENAME="resolute"
readonly KERNEL_PKG="linux-xanmod-x64v3"
readonly NVIDIA_PKG="nvidia-driver-595-open"
readonly XANMOD_KEY="/etc/apt/keyrings/xanmod-archive-keyring.gpg"
readonly XANMOD_LIST="/etc/apt/sources.list.d/xanmod-release.list"
readonly GRUB_IBT="/etc/default/grub.d/99-xanmod-nvidia-ibt-off.cfg"

log() { echo "[xanmod] $*" >&2; }

show_help() {
  cat <<EOF
Usage: $(basename "$0") [OPTION]

Install XanMod kernel and NVIDIA driver for this laptop:
  MSI Creator Z17, i7-12700H, RTX 3070 Ti, Ubuntu 26.04 (${CODENAME})

Packages:
  ${KERNEL_PKG}
  ${NVIDIA_PKG} (XanMod non-free repo)

Also configures:
  ibt=off in GRUB (required for NVIDIA on XanMod)
  GRUB fallback to Ubuntu generic kernel

Options:
  -h, --help    Show this help
  --reboot      Reboot after install

After reboot, verify:
  uname -r
  cat /proc/cmdline | grep ibt=off
  nvidia-smi
EOF
}

require_root_tools() {
  command -v apt >/dev/null || { log "apt not found"; exit 1; }
  [[ "$(lsb_release -sc)" == "${CODENAME}" ]] || log "Warning: expected Ubuntu ${CODENAME}, got $(lsb_release -sc)"
}

setup_repo() {
  if [[ ! -f "${XANMOD_KEY}" ]]; then
    wget -qO - https://dl.xanmod.org/archive.key | sudo gpg --dearmor -vo "${XANMOD_KEY}"
  fi
  echo "deb [signed-by=${XANMOD_KEY}] http://deb.xanmod.org ${CODENAME} main non-free" | sudo tee "${XANMOD_LIST}" >/dev/null
  sudo apt update
}

setup_grub() {
  local fallback
  fallback="$(ls -1 /boot/vmlinuz-*-generic 2>/dev/null | sed 's|.*/vmlinuz-||' | sort -V | tail -1)"

  echo 'GRUB_CMDLINE_LINUX_DEFAULT="$GRUB_CMDLINE_LINUX_DEFAULT ibt=off"' | sudo tee "${GRUB_IBT}" >/dev/null

  if [[ -n "${fallback}" ]]; then
    sudo sed -i "s|^GRUB_DEFAULT=.*|GRUB_DEFAULT=\"Advanced options for Ubuntu>Ubuntu, with Linux ${fallback}\"|" /etc/default/grub
    sudo sed -i 's|^GRUB_SAVEDEFAULT=.*|GRUB_SAVEDEFAULT="true"|' /etc/default/grub
    log "GRUB fallback: ${fallback}"
  fi

  sudo update-grub
}

main() {
  case "${1:-}" in
    -h|--help) show_help; exit 0 ;;
    ""|--reboot) ;;
    *) log "Unknown option: $1 (try --help)"; exit 1 ;;
  esac

  require_root_tools

  sudo dpkg --configure -a || true
  sudo apt install -y -f || true

  setup_repo

  sudo apt install -y --no-install-recommends dkms libelf-dev libdw-dev clang lld llvm build-essential
  sudo apt install -y "${NVIDIA_PKG}"
  sudo apt install -y "${KERNEL_PKG}"

  sudo dpkg --configure -a
  sudo apt install -y -f

  setup_grub
  sudo update-initramfs -u -k all

  echo
  log "Done. Reboot and pick XanMod in GRUB (Advanced options if needed)."
  log "Verify: uname -r && cat /proc/cmdline | grep ibt=off && nvidia-smi"
  echo

  if [[ "${1:-}" == "--reboot" ]]; then
    sudo reboot
  fi
}

main "$@"
