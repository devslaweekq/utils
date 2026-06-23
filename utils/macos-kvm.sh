#!/usr/bin/env bash
# macOS on KVM/QEMU — automated setup
# Repo: https://github.com/Coopydood/ultimate-macOS-KVM
#
# Note: NVIDIA GPU passthrough is not supported in macOS (Apple dropped
# NVIDIA drivers since Mojave 2018). CPU/RAM/disk run near-native speed.
#
# Usage:
#   bash macos-kvm.sh                        — full setup (interactive AutoPilot)
#   bash macos-kvm.sh --auto                 — full autopilot: answers all questions automatically based on system resources
#   bash macos-kvm.sh --auto --os <ver>      — same but choose macOS version: 26=Tahoe 15=Sequoia 14=Sonoma 13=Ventura 12=Monterey
#   bash macos-kvm.sh --force                — re-run AutoPilot even if boot script and image already exist
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

# Parse flags
AUTO_MODE=0
FORCE_MODE=0
MACOS_VER=15   # default Sequoia
args=("$@")
i=0
while [ $i -lt ${#args[@]} ]; do
    case "${args[$i]}" in
        --auto)   AUTO_MODE=1 ;;
        --force)  FORCE_MODE=1 ;;
        --os)     i=$(( i+1 )); MACOS_VER="${args[$i]}" ;;
    esac
    i=$(( i+1 ))
done

# Map macOS version number to autopilot answer (position in the version list)
# Stage 2 custom menu: 1=Tahoe(26) 2=Sequoia(15) 3=Sonoma(14) 4=Ventura(13) 5=Monterey(12) 6=BigSur(11) 7=Catalina 8=Mojave 9=HighSierra
case "$MACOS_VER" in
    26) AP_OS_CHOICE=1 ;;
    15) AP_OS_CHOICE=2 ;;
    14) AP_OS_CHOICE=3 ;;
    13) AP_OS_CHOICE=4 ;;
    12) AP_OS_CHOICE=5 ;;
    11) AP_OS_CHOICE=6 ;;
    *)  warn "Unknown --os value '$MACOS_VER', defaulting to Sequoia (15)"; AP_OS_CHOICE=2 ; MACOS_VER=15 ;;
esac

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
    pip3 install --quiet -r requirements.txt || \
    pip3 install --quiet --break-system-packages -r requirements.txt || \
    warn "pip install failed — autopilot.py may fail if deps are missing"
fi
ok "Python dependencies ready"

# -----------------------------------------------------------------------------
# 6. AutoPilot — VM configuration
# -----------------------------------------------------------------------------
echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}  AutoPilot — macOS VM setup wizard${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

VM_MEM_GB=$(( VM_MEM_MB / 1024 ))
if [ "$VM_MEM_GB" -lt 4 ]; then
    VM_MEM_GB=4
    VM_MEM_MB=$(( VM_MEM_GB * 1024 ))
    HUGEPAGES=$(( VM_MEM_MB / 2 ))
fi

EXISTING_BOOT=$(find "$INSTALL_DIR" -maxdepth 1 \( -name "boot-macOS*.sh" -o -name "boot.sh" \) 2>/dev/null | head -1)
EXISTING_IMG=$(find "$INSTALL_DIR" -maxdepth 1 \( -name "*.img" -o -name "BaseSystem.*" -o -name "RecoveryImage.*" \) 2>/dev/null | head -1)

if [ -n "$EXISTING_BOOT" ] && [ -n "$EXISTING_IMG" ] && [ "$FORCE_MODE" -eq 0 ]; then
    ok "Boot script already exists: $(basename "$EXISTING_BOOT")"
    ok "Recovery image already exists: $(basename "$EXISTING_IMG")"
    warn "Skipping AutoPilot (use --force to re-run it)"
elif [ "$AUTO_MODE" -eq 1 ]; then
    echo -e "  ${GREEN}Mode${NC}           Full Auto (--auto)"
    echo -e "  ${GREEN}macOS version${NC}  ${MACOS_VER}"
    echo -e "  ${GREEN}RAM${NC}            ${VM_MEM_GB}G (50% of ${TOTAL_MEM_MB}MB)"
    echo -e "  ${GREEN}CPU cores${NC}      ${VM_CPUS} × 1 thread (50% of ${TOTAL_CPUS})"
    echo -e "  ${GREEN}Disk size${NC}      80G (dynamic qcow2)"
    echo -e "  ${GREEN}Network${NC}        vmxnet3 + auto MAC"
    echo -e "  ${GREEN}Image${NC}          Download from Apple CDN"
    echo ""
    ok "Launching AutoPilot in fully automated mode..."

    # Answer sequence for autopilot.py (14 stages + summary):
    #  1             = autopilot startup: Start
    #  1             = stage1:  default filename (boot.sh)
    #  2             = stage2:  "Select macOS version..."
    #  $AP_OS_CHOICE = stage2 custom: chosen version
    #  2             = stage3:  custom CPU cores
    #  $VM_CPUS      = stage3 value
    #  2             = stage4:  custom threads
    #  1             = stage4 value: 1 thread per core
    #  1             = stage5:  default CPU model (Haswell-noTSX)
    #  1             = stage6:  default CPU feature args
    #  2             = stage7:  custom RAM
    #  ${VM_MEM_GB}G = stage7 value
    #  1             = stage8:  default disk size (80G)
    #  1             = stage9:  default disk type (HDD/qcow2)
    #  1             = stage10: default network adapter
    #  2             = stage11: generate MAC address automatically
    #  1             = stage12: download recovery image from Apple
    #  1             = stage13: default resolution (1280x720)
    #  2             = stage14: skip XML generation
    #  2             = experimentalAudio: no thanks
    #  1             = stage15: start
    #  Q             = handoff menu: exit (avoids EOFError when stdin is exhausted)
    printf "1\n1\n2\n%s\n2\n%s\n2\n1\n1\n1\n2\n%sG\n1\n1\n1\n2\n1\n1\n2\n2\n1\nQ\n" \
        "$AP_OS_CHOICE" "$VM_CPUS" "$VM_MEM_GB" \
        | python3 scripts/autopilot.py --skip-notices --disable-new-dialogs
elif [ "$AUTO_MODE" -eq 0 ]; then
    echo "  AutoPilot will ask a few questions and generate a launch script."
    echo "  Suggested values for your system (${TOTAL_MEM_MB}MB RAM, ${TOTAL_CPUS} CPUs):"
    echo ""
    echo -e "  ${GREEN}macOS version${NC}  Sonoma (14) stable or Sequoia (15)"
    echo -e "                 Tahoe (26) — latest, may be unstable on KVM"
    echo -e "  ${GREEN}RAM${NC}            ${VM_MEM_GB}G (50% of total)"
    echo -e "  ${GREEN}CPU cores${NC}      ${VM_CPUS} (50% of total)"
    echo -e "  ${GREEN}Disk size${NC}      80G (qcow2 — grows on write, starts near-empty)"
    echo ""
    pause "Launch AutoPilot"
    python3 scripts/autopilot.py
fi

# -----------------------------------------------------------------------------
# 7. Apply performance tweaks to the generated boot script
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
# 8. Shell alias
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
