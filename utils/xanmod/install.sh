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
  GRUB default pinned to the Ubuntu generic kernel (done BEFORE the kernel
  install, so a failed install never leaves XanMod as the default)

Checks:
  refuses to run with Secure Boot enabled (XanMod is unsigned)
  removes tp-smapi-dkms (ThinkPad-only, its DKMS build fails on XanMod and
  leaves the kernel package half-configured)
  verifies package state, GRUB default and ibt=off at the end

Options:
  -h, --help    Show this help
  --reboot      Reboot after install

After reboot (pick XanMod in GRUB > Advanced options), verify:
  uname -r
  cat /proc/cmdline | grep ibt=off
  nvidia-smi
EOF
}

require_root_tools() {
  command -v apt >/dev/null || { log "apt not found"; exit 1; }
  [[ "$(lsb_release -sc)" == "${CODENAME}" ]] || log "Warning: expected Ubuntu ${CODENAME}, got $(lsb_release -sc)"
}

# tp_smapi is ThinkPad-only and fails to build against XanMod (LLVM) kernels. A failed DKMS
# build makes the kernel postinst exit 1 and dpkg leaves linux-image-* unconfigured.
remove_incompatible_dkms() {
  if [[ "$(dpkg-query -W -f='${db:Status-Abbrev}' tp-smapi-dkms 2>/dev/null)" == ii* ]]; then
    log "Removing tp-smapi-dkms (ThinkPad-only, breaks the XanMod kernel postinst)"
    sudo apt purge -y tp-smapi-dkms
  fi
}

setup_repo() {
  if [[ ! -f "${XANMOD_KEY}" ]]; then
    wget -qO - https://dl.xanmod.org/archive.key | sudo gpg --dearmor -vo "${XANMOD_KEY}"
  fi
  echo "deb [signed-by=${XANMOD_KEY}] http://deb.xanmod.org ${CODENAME} main non-free" | sudo tee "${XANMOD_LIST}" >/dev/null
  sudo apt update
}

# Must run before the kernel is installed: the newest kernel in GRUB is the default entry,
# so without the pin a half-failed install boots XanMod without ibt=off.
setup_grub() {
  local fallback entry
  fallback="$(ls -1 /boot/vmlinuz-*-generic 2>/dev/null | sed 's|.*/vmlinuz-||' | sort -V | tail -1)"

  if [[ -z "${fallback}" ]]; then
    log "No generic kernel in /boot to fall back to, refusing to install XanMod"
    exit 1
  fi

  echo 'GRUB_CMDLINE_LINUX_DEFAULT="$GRUB_CMDLINE_LINUX_DEFAULT ibt=off"' | sudo tee "${GRUB_IBT}" >/dev/null

  entry="Advanced options for Ubuntu>Ubuntu, with Linux ${fallback}"
  if grep -q '^GRUB_DEFAULT=' /etc/default/grub; then
    sudo sed -i "s|^GRUB_DEFAULT=.*|GRUB_DEFAULT=\"${entry}\"|" /etc/default/grub
  else
    echo "GRUB_DEFAULT=\"${entry}\"" | sudo tee -a /etc/default/grub >/dev/null
  fi
  sudo sed -i 's|^GRUB_SAVEDEFAULT=.*|GRUB_SAVEDEFAULT="true"|' /etc/default/grub
  log "GRUB default pinned to: ${fallback}"

  sudo update-grub
}

install_kernel() {
  if ! sudo apt install -y "${KERNEL_PKG}"; then
    log "Kernel install failed (usually a DKMS module that does not build). Modules not installed:"
    dkms status 2>/dev/null | grep -v ': installed' >&2 || true
    log "GRUB default is already pinned to the generic kernel, so rebooting is safe."
    log "Fix or remove the failing DKMS package, then run: sudo dpkg --configure -a && $0"
    exit 1
  fi
}

verify() {
  local ok=1
  if [[ "$(dpkg-query -W -f='${db:Status-Abbrev}' "${KERNEL_PKG}" 2>/dev/null)" != ii* ]]; then
    log "FAIL: ${KERNEL_PKG} is not fully configured (check: dpkg -l ${KERNEL_PKG})"
    ok=0
  fi
  if ! grep -q '^GRUB_DEFAULT=.*Linux .*-generic' /etc/default/grub; then
    log "FAIL: GRUB_DEFAULT is not pinned to a generic kernel"
    ok=0
  fi
  if ! sudo grep -q 'ibt=off' /boot/grub/grub.cfg; then
    log "FAIL: ibt=off is missing in /boot/grub/grub.cfg"
    ok=0
  fi
  if ((ok == 0)); then
    log "Do NOT reboot before fixing the above."
    exit 1
  fi
  log "Checks passed: ${KERNEL_PKG} configured, GRUB default is generic, ibt=off set."
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
  remove_incompatible_dkms

  setup_grub
  setup_repo

  sudo apt install -y --no-install-recommends dkms libelf-dev libdw-dev clang lld llvm build-essential
  sudo apt install -y "${NVIDIA_PKG}"
  install_kernel

  sudo dpkg --configure -a
  sudo apt install -y -f

  sudo update-grub
  sudo update-initramfs -u -k all
  verify

  echo
  log "Done. Reboot and pick XanMod in GRUB (Advanced options)."
  log "Verify: uname -r && cat /proc/cmdline | grep ibt=off && nvidia-smi"
  echo

  if [[ "${1:-}" == "--reboot" ]]; then
    sudo reboot
  fi
}

main "$@"
