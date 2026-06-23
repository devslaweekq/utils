#!/usr/bin/env bash
# macOS on KVM/QEMU — automated setup
# Repo: https://github.com/Coopydood/ultimate-macOS-KVM
#
# Note: NVIDIA GPU passthrough is not supported in macOS (Apple dropped
# NVIDIA drivers since Mojave 2018). CPU/RAM/disk run near-native speed.
#
# Usage:
#   bash macos-kvm.sh                        — full setup
#   bash macos-kvm.sh --update-space <size>  — resize VM disk: +32G adds 32GB to current size or 128G sets exact size (must be larger)
#   bash macos-kvm.sh -us <size>

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

info()  { echo -e "${CYAN}==>${NC} $*"; }
ok()    { echo -e "${GREEN} ✓${NC}  $*"; }
warn()  { echo -e "${YELLOW}[!]${NC} $*"; }
pause() { echo -e "${YELLOW}[>]${NC} $* — press Enter to continue..."; read -r; }

INSTALL_DIR="$HOME/macos-kvm"
DISK="$INSTALL_DIR/mac_hdd_ng.img"

# -----------------------------------------------------------------------------
# --update-space / -us <size> : resize VM disk
# -----------------------------------------------------------------------------
if [[ "${1:-}" == "--update-space" || "${1:-}" == "-us" ]]; then
    SIZE="${2:-}"
    if [ -z "$SIZE" ]; then
        echo -e "${RED}[✗]${NC} Usage: bash macos-kvm.sh --update-space <size>  (e.g. +32G or 128G)"
        exit 1
    fi
    if [ ! -f "$DISK" ]; then
        echo -e "${RED}[✗]${NC} Disk not found: $DISK"
        exit 1
    fi
    CURRENT=$(qemu-img info "$DISK" | grep 'virtual size' | awk '{print $3, $4}')
    info "Current disk size: $CURRENT"
    info "Resizing to: $SIZE ..."
    qemu-img resize "$DISK" "$SIZE"
    ok "Disk resized. New size:"
    qemu-img info "$DISK" | grep 'virtual size'
    echo ""
    warn "Apply inside macOS: Disk Utility → select Macintosh HD → resize partition"
    exit 0
fi

# Detect system resources
TOTAL_MEM_MB=$(( $(grep MemTotal /proc/meminfo | awk '{print $2}') / 1024 ))
TOTAL_CPUS=$(nproc)
VM_MEM_MB=$(( TOTAL_MEM_MB / 2 ))
VM_MEM_MB=$(( (VM_MEM_MB / 1024) * 1024 ))  # round down to nearest GB
VM_CPUS=$(( TOTAL_CPUS / 2 ))
[ "$VM_CPUS" -lt 2 ] && VM_CPUS=2
HUGEPAGES=$(( VM_MEM_MB / 2 ))  # each hugepage = 2MB

# -----------------------------------------------------------------------------
# 1. Check KVM
# -----------------------------------------------------------------------------
info "Checking KVM support..."
KVM_SUPPORT=$(grep -cE '(vmx|svm)' /proc/cpuinfo || true)
if [ "$KVM_SUPPORT" -eq 0 ]; then
    echo -e "${RED}[✗]${NC} CPU does not support virtualization (vmx/svm not found)."
    echo "    Enable Intel VT-x or AMD-V in BIOS/UEFI and reboot."
    exit 1
fi
ok "KVM supported"

if ! lsmod | grep -q kvm; then
    warn "kvm module not loaded — trying to load..."
    sudo modprobe kvm-intel || sudo modprobe kvm-amd || {
        echo -e "${RED}[✗]${NC} Failed to load kvm module. Enable VT-x/AMD-V in BIOS."
        exit 1
    }
fi
ok "kvm module active"

# -----------------------------------------------------------------------------
# 2. Install dependencies
# -----------------------------------------------------------------------------
info "Installing dependencies..."
sudo apt-get update -qq
sudo apt-get install -y \
    qemu-system-x86 \
    qemu-utils \
    libvirt-daemon-system \
    libvirt-clients \
    bridge-utils \
    ovmf \
    dmg2img \
    python3 \
    python3-pip \
    git \
    curl \
    wget \
    xterm
ok "Dependencies installed"

if ! groups | grep -q libvirt; then
    sudo usermod -aG libvirt,kvm "$(whoami)"
    warn "Added to libvirt,kvm groups — re-login or run: newgrp libvirt"
fi

sudo systemctl enable --now libvirtd 2>/dev/null || true
ok "libvirtd running"

# -----------------------------------------------------------------------------
# 3. Hugepages (reduces memory latency for the VM)
# -----------------------------------------------------------------------------
info "Configuring hugepages (${VM_MEM_MB}MB of ${TOTAL_MEM_MB}MB for VM)..."
echo "$HUGEPAGES" | sudo tee /proc/sys/vm/nr_hugepages > /dev/null
echo "vm.nr_hugepages = $HUGEPAGES" | sudo tee /etc/sysctl.d/99-hugepages.conf > /dev/null
ok "Hugepages: ${HUGEPAGES} pages (${VM_MEM_MB}MB)"

# -----------------------------------------------------------------------------
# 4. Clone ultimate-macOS-KVM
# -----------------------------------------------------------------------------
info "Cloning Coopydood/ultimate-macOS-KVM..."
if [ -d "$INSTALL_DIR/.git" ]; then
    warn "$INSTALL_DIR already exists — updating..."
    git -C "$INSTALL_DIR" pull --ff-only
else
    git clone https://github.com/Coopydood/ultimate-macOS-KVM.git "$INSTALL_DIR"
fi
ok "Repository: $INSTALL_DIR"

cd "$INSTALL_DIR"

# -----------------------------------------------------------------------------
# 5. Install Python dependencies
# -----------------------------------------------------------------------------
info "Installing Python dependencies..."
if [ -f requirements.txt ]; then
    pip3 install --quiet -r requirements.txt 2>/dev/null || \
    pip3 install --quiet --break-system-packages -r requirements.txt 2>/dev/null || true
fi
ok "Python dependencies ready"

# -----------------------------------------------------------------------------
# 6. AutoPilot — interactive VM configuration
# -----------------------------------------------------------------------------
echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}  AutoPilot — macOS VM setup wizard${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "  AutoPilot will ask a few questions and generate a launch script."
echo "  Suggested values for your system (${TOTAL_MEM_MB}MB RAM, ${TOTAL_CPUS} CPUs):"
echo ""
echo -e "  ${GREEN}macOS version${NC}  Sonoma (14) stable or Sequoia (15)"
echo -e "                 Tahoe (26) — latest, may be unstable on KVM"
echo -e "  ${GREEN}RAM${NC}            ${VM_MEM_MB} MB (50% of total)"
echo -e "  ${GREEN}CPU cores${NC}      ${VM_CPUS} (50% of total)"
echo -e "  ${GREEN}Disk size${NC}      64GB (qcow2 — grows on write, starts near-empty)"
echo ""
pause "Launch AutoPilot"

python3 autopilot.py

# -----------------------------------------------------------------------------
# 7. Download macOS image
# -----------------------------------------------------------------------------
echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}  Downloading macOS image from Apple CDN (~700MB)${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
pause "Download image"

python3 fetch-macOS.py || python3 resources/dmgFromAAS.py || {
    warn "Built-in fetch script not found, falling back to OSX-KVM..."
    curl -fsSL \
      https://raw.githubusercontent.com/kholia/OSX-KVM/master/fetch-macOS-v2.py \
      -o /tmp/fetch-macOS-v2.py
    python3 /tmp/fetch-macOS-v2.py
    mv BaseSystem.dmg "$INSTALL_DIR/" 2>/dev/null || true
}

info "Converting image to QEMU format..."
dmg2img -i BaseSystem.dmg BaseSystem.img
ok "BaseSystem.img ready"

# -----------------------------------------------------------------------------
# 8. Create VM disk
# -----------------------------------------------------------------------------
if [ ! -f "$DISK" ]; then
    info "Creating 128GB VM disk..."
    qemu-img create -f qcow2 "$DISK" 64G
    ok "Disk created: $DISK"
else
    ok "Disk already exists: $DISK"
fi

# -----------------------------------------------------------------------------
# 9. Apply performance tweaks to the generated boot script
# -----------------------------------------------------------------------------
info "Applying performance tweaks..."
BOOT_SCRIPT=$(find "$INSTALL_DIR" -maxdepth 1 \( -name "boot-macOS*.sh" -o -name "OpenCore-Boot.sh" \) 2>/dev/null | head -1)

if [ -n "$BOOT_SCRIPT" ] && [ -f "$BOOT_SCRIPT" ]; then
    if ! grep -q "mem-path" "$BOOT_SCRIPT"; then
        MEM_G=$(( VM_MEM_MB / 1024 ))
        sed -i "s/-m [0-9]*G\b/-m ${MEM_G}G \\\\\n  -mem-path \/dev\/hugepages \\\\\n  -mem-prealloc/" "$BOOT_SCRIPT" 2>/dev/null || true
    fi
    ok "Hugepages wired into boot script"

    if ! grep -q "GenuineIntel" "$BOOT_SCRIPT"; then
        sed -i 's/-cpu host,kvm=on/-cpu host,kvm=on,vendor=GenuineIntel/' "$BOOT_SCRIPT" 2>/dev/null || true
    fi
    ok "CPU vendor=GenuineIntel confirmed"
else
    warn "Boot script not found — apply tweaks manually after AutoPilot"
fi

# -----------------------------------------------------------------------------
# 10. Shell alias
# -----------------------------------------------------------------------------
ALIAS_LINE="alias macos='cd $INSTALL_DIR && bash \$(ls boot-macOS*.sh OpenCore-Boot.sh 2>/dev/null | head -1)'"
if ! grep -qF "alias macos=" ~/.bashrc 2>/dev/null; then
    echo "$ALIAS_LINE" >> ~/.bashrc
    ok "Alias 'macos' added to ~/.bashrc"
else
    sed -i "/alias macos=/c\\$ALIAS_LINE" ~/.bashrc
    ok "Alias 'macos' updated in ~/.bashrc"
fi

# -----------------------------------------------------------------------------
# Done
# -----------------------------------------------------------------------------
echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}  Setup complete!${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "  ${CYAN}Start macOS installation:${NC}"
echo -e "    source ~/.bashrc && macos"
echo ""
echo -e "  ${CYAN}In the QEMU window:${NC}"
echo "    1. Select macOS version in OpenCore menu"
echo "    2. Disk Utility → erase disk as APFS → name it 'Macintosh HD'"
echo "    3. Install macOS → select 'Macintosh HD'"
echo "    4. Installation takes 20-40 min with several reboots"
echo "    5. On each reboot select 'Macintosh HD' in OpenCore"
echo ""
echo -e "  ${CYAN}Clipboard host <-> macOS:${NC}"
echo "    macOS: System Settings → Sharing → Screen Sharing → enable"
echo "    Host:  vncviewer localhost:5900"
echo ""
if ! groups | grep -q libvirt; then
    echo -e "  ${YELLOW}Re-login or run: newgrp libvirt${NC}"
    echo ""
fi
