#!/bin/bash

set -e

echo "Updating system..."
sudo apt update && sudo apt upgrade -y

echo "Configuring Wayland for NVIDIA..."
if [ "$XDG_SESSION_TYPE" != "wayland" ]; then
    echo "WARNING: You are not in a Wayland session. Switch to Wayland to apply these settings."
fi

echo "=== Wayland optimization for Intel i7-12700H + RTX 3070 Ti + Intel Iris Xe ==="

# Optimized environment variables for a hybrid system
echo "Configuring environment variables for hybrid graphics..."
ENV_FILE="/etc/environment"

# Backup original file
sudo cp $ENV_FILE $ENV_FILE.backup.$(date +%Y%m%d_%H%M%S)
# environment.backup.20250709_132401

# NVIDIA Wayland optimizations
if ! sudo grep -q '__GLX_VENDOR_LIBRARY_NAME=nvidia' /etc/environment; then
    echo '__GLX_VENDOR_LIBRARY_NAME=nvidia' | sudo tee -a /etc/environment
fi
if ! sudo grep -q 'GBM_BACKEND=nvidia-drm' /etc/environment; then
    echo 'GBM_BACKEND=nvidia-drm' | sudo tee -a /etc/environment
fi

# Critical for hybrid systems — disable hardware cursors
if ! sudo grep -q 'WLR_NO_HARDWARE_CURSORS=1' /etc/environment; then
    echo 'WLR_NO_HARDWARE_CURSORS=1' | sudo tee -a /etc/environment
fi

# Optimization for high‑DPI displays
if ! sudo grep -q 'MUTTER_DEBUG_FORCE_KMS_MODE=simple' /etc/environment; then
    echo 'MUTTER_DEBUG_FORCE_KMS_MODE=simple' | sudo tee -a /etc/environment
fi

# Fixes for fractional scaling
if ! sudo grep -q 'GDK_SCALE=1' /etc/environment; then
    echo 'GDK_SCALE=1' | sudo tee -a /etc/environment
fi
if ! sudo grep -q 'QT_AUTO_SCREEN_SCALE_FACTOR=1' /etc/environment; then
    echo 'QT_AUTO_SCREEN_SCALE_FACTOR=1' | sudo tee -a /etc/environment
fi

echo "Enabling Wayland in GDM..."
if [ -f "/etc/gdm3/custom.conf" ]; then
    sudo sed -i '/WaylandEnable=false/s/^/#/' /etc/gdm3/custom.conf || true
    # Add explicit WaylandEnable=true if it is missing
    if ! sudo grep -q "WaylandEnable=true" /etc/gdm3/custom.conf; then
        sudo sed -i '/\[daemon\]/a WaylandEnable=true' /etc/gdm3/custom.conf
    fi
fi

# Configure GNOME for optimal Wayland performance
echo "Configuring GNOME..."
# OVERRIDE_FILE="/usr/share/glib-2.0/schemas/99-gnome-triple-buffering.gschema.override"
OVERRIDE_FILE="/usr/share/glib-2.0/schemas/99-wayland-optimizations.gschema.override"
if [ ! -f "$OVERRIDE_FILE" ]; then

  sudo tee $OVERRIDE_FILE > /dev/null <<EOF
[org.gnome.mutter]
experimental-features=['scale-monitor-framebuffer', 'rt-scheduler']

[org.gnome.desktop.interface]
font-antialiasing='rgba'
font-hinting='slight'
font-rgba-order='rgb'

[org.gnome.settings-daemon.plugins.xsettings]
antialiasing='rgba'
hinting='slight'
rgba-order='rgb'

[org.gnome.desktop.wm.preferences]
resize-with-right-button=true
mouse-button-modifier='<Super>'

[org.gnome.mutter.wayland]
xwayland-allow-grabs=true
EOF
  sudo glib-compile-schemas /usr/share/glib-2.0/schemas/
fi

# Apply settings for the current session
echo "Applying settings for current session..."

# Main experimental Mutter features
gsettings set org.gnome.mutter experimental-features "['scale-monitor-framebuffer', 'rt-scheduler']"

# Font optimization for high‑DPI displays
gsettings set org.gnome.desktop.interface font-antialiasing 'rgba'
gsettings set org.gnome.desktop.interface font-hinting 'slight'
gsettings set org.gnome.desktop.interface font-rgba-order 'rgb'

# Settings for fractional scaling
gsettings set org.gnome.desktop.interface scaling-factor 0  # Automatic detection
gsettings set org.gnome.desktop.interface text-scaling-factor 1.0

# Performance optimization
gsettings set org.gnome.shell.overrides workspaces-only-on-primary false
gsettings set org.gnome.mutter attach-modal-dialogs false
gsettings set org.gnome.mutter edge-tiling true
gsettings set org.gnome.mutter dynamic-workspaces true

echo "Creating optimized font configuration..."
FONTCONFIG_DIR="$HOME/.config/fontconfig"
mkdir -p $FONTCONFIG_DIR

cat > $FONTCONFIG_DIR/fonts.conf <<EOF
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "fonts.dtd">
<fontconfig>
  <!-- Optimization for high‑DPI displays -->
  <match target="font">
    <edit mode="assign" name="antialias">
      <bool>true</bool>
    </edit>
    <edit mode="assign" name="hinting">
      <bool>true</bool>
    </edit>
    <edit mode="assign" name="hintstyle">
      <const>hintslight</const>
    </edit>
    <edit mode="assign" name="rgba">
      <const>rgb</const>
    </edit>
    <edit mode="assign" name="lcdfilter">
      <const>lcddefault</const>
    </edit>
  </match>

  <!-- Special handling for fractional scaling -->
  <match target="font">
    <test name="size" compare="less">
      <double>12</double>
    </test>
    <edit mode="assign" name="hintstyle">
      <const>hintfull</const>
    </edit>
  </match>
</fontconfig>
EOF

echo "Configuring NVIDIA Full Composition Pipeline Wayland..."
if command -v nvidia-settings &> /dev/null; then
    nvidia-settings --assign CurrentMetaMode="nvidia-auto-select +0+0 { ForceCompositionPipeline = On }" 2>/dev/null || true
fi

echo "Optimizing Intel Iris Xe..."
MODPROBE_CONF="/etc/modprobe.d/i915.conf"
if [ ! -f "$MODPROBE_CONF" ]; then
    sudo tee $MODPROBE_CONF > /dev/null <<EOF
# Intel Iris Xe optimization for Wayland
options i915 enable_psr=1 enable_guc=2 enable_dc=1 disable_power_well=0 modeset=1
EOF
fi

echo "Creating additional optimizations..."
AUTOSTART_DIR="$HOME/.config/autostart"
mkdir -p $AUTOSTART_DIR

cat > $AUTOSTART_DIR/wayland-optimizations.desktop <<EOF
[Desktop Entry]
Type=Application
Name=Wayland Optimizations
Comment=Apply Wayland optimizations for hybrid graphics
Exec=sh -c 'sleep 5 && gsettings set org.gnome.mutter experimental-features "[\"scale-monitor-framebuffer\", \"rt-scheduler\"]" && gsettings set org.gnome.desktop.interface font-antialiasing "rgba"'
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
EOF

echo ""
echo "=== DISPLAY INFORMATION ==="
echo "Built‑in display: 2048x1280 (QHD+, ~160 DPI)"
echo "External monitor: 1920x1080 (Full HD, ~96 DPI)"
echo ""
echo "=== RECOMMENDATIONS TO FIX BLURRY FONTS ==="
echo ""
echo "1. RESTART THE SYSTEM to apply all settings"
echo ""
echo "2. After reboot, run:"
echo "   gsettings set org.gnome.desktop.interface text-scaling-factor 1.25"
echo "   (this gives clean scaling without blur)"
echo ""
echo "3. If the problem remains, try:"
echo "   gsettings set org.gnome.desktop.interface text-scaling-factor 1.0"
echo "   gsettings set org.gnome.desktop.interface scaling-factor 0"
echo ""
echo "4. Alternative solution — use integer scaling:"
echo "   gsettings set org.gnome.desktop.interface scaling-factor 2"
echo "   gsettings set org.gnome.desktop.interface text-scaling-factor 0.8"
echo ""
echo "5. To check font quality, open a text editor"
echo "   and compare clarity with an X11 session"
echo ""

echo "=== CURRENT SETTINGS ==="
echo "Interface scale: $(gsettings get org.gnome.desktop.interface scaling-factor)"
echo "Text scale: $(gsettings get org.gnome.desktop.interface text-scaling-factor)"
echo "Experimental features: $(gsettings get org.gnome.mutter experimental-features)"
echo "Font antialiasing: $(gsettings get org.gnome.desktop.interface font-antialiasing)"
echo ""

# === CURRENT SETTINGS EXAMPLE ===
# Interface scale: uint32 1
# Text scale: 1.0
# Experimental features: ['scale-monitor-framebuffer', 'xwayland-native-scaling']
# Font antialiasing: 'grayscale'

# Restart system to apply settings
echo "Script completed. Restart your system to apply changes. Restart now? (y/n)"
read -r RESTART
if [[ $RESTART == "y" || $RESTART == "Y" ]]; then
    sudo reboot
else
    echo "Restart your system later to apply all settings."
fi
