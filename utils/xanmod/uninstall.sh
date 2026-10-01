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
  ${NVIDIA_PKG} from Ubuntu repos (XanMod's NVIDIA packages are downgraded to Ubuntu's)
  GRUB settings as before install (no ibt=off, GRUB_DEFAULT=0)

Removes:
  ${KERNEL_PKG} and related packages (image, headers)
  every other installed package that came from the XanMod repo (the NVIDIA stack)
  XanMod APT repo, leftover initrd / modules, DKMS entries

Must be run from the Ubuntu generic kernel, not from XanMod itself.
The NVIDIA downgrade and the final autoremove are interactive: read the list apt shows.

Options:
  -h, --help    Show this help
  --reboot      Reboot after uninstall

After reboot, verify:
  uname -r
  cat /proc/cmdline
  nvidia-smi
EOF
}

require_generic_kernel() {
  if [[ "$(uname -r)" == *xanmod* ]]; then
    log "Running on the XanMod kernel ($(uname -r)): it cannot be removed safely while in use."
    log "Reboot into the Ubuntu generic kernel (GRUB > Advanced options), then run this script again."
    exit 1
  fi
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

# every installed package that came from the XanMod repo (kernel, headers and the NVIDIA stack)
xanmod_pkgs() {
  dpkg-query -W -f='${Package}:${Architecture}\t${Version}\n' 2>/dev/null \
    | awk -F'\t' '$2 ~ /xanmod/ { print $1 }'
}

remove_xanmod_kernel() {
  local pkgs=()
  mapfile -t pkgs < <(xanmod_pkgs | grep '^linux-' || true)
  if ((${#pkgs[@]})); then
    sudo apt purge -y "${pkgs[@]}"
  fi
}

remove_repo() {
  [[ -f "${XANMOD_LIST}" ]] && sudo rm -f "${XANMOD_LIST}"
  [[ -f "${XANMOD_KEY}" ]] && sudo rm -f "${XANMOD_KEY}"
  sudo apt update
}

# Of the remaining XanMod-versioned packages, print those that also exist in the Ubuntu archive
# (e.g. nvidia-firmware-595-<version> does not, so it is left for autoremove).
ubuntu_equivalents() {
  local p c
  while read -r p; do
    c=$(apt-cache policy "$p" 2>/dev/null | awk '/Candidate:/ { print $2 }')
    if [[ -n "${c}" && "${c}" != "(none)" && "${c}" != *xanmod* ]]; then
      echo "${p}"
    fi
  done
  return 0
}

# XanMod's NVIDIA build (595.104.02-0xanmod1) is newer than Ubuntu's, so going back is a downgrade.
# Done in ONE interactive apt transaction (no -y) so the exact list is visible and confirmed.
install_ubuntu_nvidia() {
  local pkgs=()
  mapfile -t pkgs < <(xanmod_pkgs | ubuntu_equivalents)
  log "Reinstalling NVIDIA from Ubuntu (downgrading ${#pkgs[@]} XanMod-versioned packages)"
  sudo apt install --allow-downgrades "${pkgs[@]}" "${NVIDIA_PKG}"
}

cleanup_leftovers() {
  local f
  for f in /boot/*xanmod* /var/lib/kdump/*xanmod* /lib/modules/*xanmod*; do
    if [[ -e "${f}" ]]; then
      log "Removing leftover ${f}"
      sudo rm -rf -- "${f}"
    fi
  done
  sudo update-grub
}

verify() {
  local ok=1 left
  left="$(xanmod_pkgs | tr '\n' ' ')"
  if [[ -n "${left// /}" ]]; then
    log "Still installed from XanMod: ${left}"
    ok=0
  fi
  if sudo grep -qi xanmod /boot/grub/grub.cfg; then
    log "grub.cfg still mentions xanmod"
    ok=0
  fi
  if [[ -e "${XANMOD_LIST}" || -e "${GRUB_IBT}" ]]; then
    log "XanMod repo file or ibt=off drop-in is still present"
    ok=0
  fi
  if dkms status 2>/dev/null | grep -qi xanmod; then
    log "dkms still has XanMod entries (dkms status)"
    ok=0
  fi
  if ((ok == 0)); then
    log "Not fully clean, see above."
    return 1
  fi
  log "Checks passed: no XanMod packages, GRUB entries, repo or DKMS entries left."
}

main() {
  case "${1:-}" in
    -h|--help) show_help; exit 0 ;;
    ""|--reboot) ;;
    *) log "Unknown option: $1 (try --help)"; exit 1 ;;
  esac

  command -v apt >/dev/null || { log "apt not found"; exit 1; }
  [[ "$(lsb_release -sc)" == "${CODENAME}" ]] || log "Warning: expected Ubuntu ${CODENAME}, got $(lsb_release -sc)"
  require_generic_kernel

  restore_grub
  remove_xanmod_kernel
  remove_repo
  install_ubuntu_nvidia

  sudo dpkg --configure -a
  sudo apt install -y -f
  sudo apt autoremove --purge
  sudo update-initramfs -u -k all
  cleanup_leftovers
  verify || true

  echo
  log "Done. Reboot to use Ubuntu generic kernel."
  log "Verify: uname -r && nvidia-smi"
  echo

  if [[ "${1:-}" == "--reboot" ]]; then
    sudo reboot
  fi
}

main "$@"
