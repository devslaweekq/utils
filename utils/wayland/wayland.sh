#!/bin/bash

set -e

echo "Updating system..."
sudo apt update && sudo apt upgrade -y

echo "Configuring Wayland for NVIDIA..."
if [ "$XDG_SESSION_TYPE" != "wayland" ]; then
    echo "ВНИМАНИЕ: Вы не в сессии Wayland. Переключитесь на Wayland для применения настроек."
fi

echo "=== Оптимизация Wayland для Intel i7-12700H + RTX 3070 Ti + Intel Iris Xe ==="

# Оптимизированные переменные окружения для гибридной системы
echo "Настройка переменных окружения для гибридной графики..."
ENV_FILE="/etc/environment"

# Backup оригинального файла
sudo cp $ENV_FILE $ENV_FILE.backup.$(date +%Y%m%d_%H%M%S)
# environment.backup.20250709_132401

# NVIDIA Wayland оптимизации
if ! sudo grep -q '__GLX_VENDOR_LIBRARY_NAME=nvidia' /etc/environment; then
    echo '__GLX_VENDOR_LIBRARY_NAME=nvidia' | sudo tee -a /etc/environment
fi
if ! sudo grep -q 'GBM_BACKEND=nvidia-drm' /etc/environment; then
    echo 'GBM_BACKEND=nvidia-drm' | sudo tee -a /etc/environment
fi

# Критически важно для гибридных систем - отключаем аппаратные курсоры
if ! sudo grep -q 'WLR_NO_HARDWARE_CURSORS=1' /etc/environment; then
    echo 'WLR_NO_HARDWARE_CURSORS=1' | sudo tee -a /etc/environment
fi

# Оптимизация для высокоплотных дисплеев
if ! sudo grep -q 'MUTTER_DEBUG_FORCE_KMS_MODE=simple' /etc/environment; then
    echo 'MUTTER_DEBUG_FORCE_KMS_MODE=simple' | sudo tee -a /etc/environment
fi

# Фиксы для дробного масштабирования
if ! sudo grep -q 'GDK_SCALE=1' /etc/environment; then
    echo 'GDK_SCALE=1' | sudo tee -a /etc/environment
fi
if ! sudo grep -q 'QT_AUTO_SCREEN_SCALE_FACTOR=1' /etc/environment; then
    echo 'QT_AUTO_SCREEN_SCALE_FACTOR=1' | sudo tee -a /etc/environment
fi

# Enable Wayland in GDM
echo "Enabling Wayland in GDM..."
if [ -f "/etc/gdm3/custom.conf" ]; then
    sudo sed -i '/WaylandEnable=false/s/^/#/' /etc/gdm3/custom.conf || true
    # Добавляем явное включение Wayland если его нет
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

# Применяем настройки для текущей сессии
echo "Применение настроек для текущей сессии..."

# Основные экспериментальные функции Mutter
gsettings set org.gnome.mutter experimental-features "['scale-monitor-framebuffer', 'rt-scheduler']"

# Оптимизация шрифтов для высокоплотных дисплеев
gsettings set org.gnome.desktop.interface font-antialiasing 'rgba'
gsettings set org.gnome.desktop.interface font-hinting 'slight'
gsettings set org.gnome.desktop.interface font-rgba-order 'rgb'

# Настройки для дробного масштабирования
gsettings set org.gnome.desktop.interface scaling-factor 0  # Автоматическое определение
gsettings set org.gnome.desktop.interface text-scaling-factor 1.0

# Оптимизация производительности
gsettings set org.gnome.shell.overrides workspaces-only-on-primary false
gsettings set org.gnome.mutter attach-modal-dialogs false
gsettings set org.gnome.mutter edge-tiling true
gsettings set org.gnome.mutter dynamic-workspaces true

echo "Создание оптимизированной конфигурации шрифтов..."
FONTCONFIG_DIR="$HOME/.config/fontconfig"
mkdir -p $FONTCONFIG_DIR

cat > $FONTCONFIG_DIR/fonts.conf <<EOF
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "fonts.dtd">
<fontconfig>
  <!-- Оптимизация для высокоплотных дисплеев -->
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

  <!-- Специальная обработка для дробного масштабирования -->
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

echo "Оптимизация Intel Iris Xe..."
MODPROBE_CONF="/etc/modprobe.d/i915.conf"
if [ ! -f "$MODPROBE_CONF" ]; then
    sudo tee $MODPROBE_CONF > /dev/null <<EOF
# Оптимизация Intel Iris Xe для Wayland
options i915 enable_psr=1 enable_guc=2 enable_dc=1 disable_power_well=0 modeset=1
EOF
fi

echo "Создание дополнительных оптимизаций..."
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
echo "=== ИНФОРМАЦИЯ О ВАШЕМ ДИСПЛЕЕ ==="
echo "Обнаружен дисплей: 2048x1280 (QHD+, ~160 DPI)"
echo "Внешний монитор: 1920x1080 (Full HD, ~96 DPI)"
echo ""
echo "=== РЕКОМЕНДАЦИИ ДЛЯ УСТРАНЕНИЯ РАЗМЫТЫХ ШРИФТОВ ==="
echo ""
echo "1. ПЕРЕЗАГРУЗИТЕ СИСТЕМУ для применения всех настроек"
echo ""
echo "2. После перезагрузки выполните:"
echo "   gsettings set org.gnome.desktop.interface text-scaling-factor 1.25"
echo "   (это даст чистое масштабирование без размытия)"
echo ""
echo "3. Если проблема остается, попробуйте:"
echo "   gsettings set org.gnome.desktop.interface text-scaling-factor 1.0"
echo "   gsettings set org.gnome.desktop.interface scaling-factor 0"
echo ""
echo "4. Альтернативное решение - используйте целочисленное масштабирование:"
echo "   gsettings set org.gnome.desktop.interface scaling-factor 2"
echo "   gsettings set org.gnome.desktop.interface text-scaling-factor 0.8"
echo ""
echo "5. Для проверки качества шрифтов откройте текстовый редактор"
echo "   и сравните четкость с X11 сессией"
echo ""

echo "=== ТЕКУЩИЕ НАСТРОЙКИ ==="
echo "Масштаб интерфейса: $(gsettings get org.gnome.desktop.interface scaling-factor)"
echo "Масштаб текста: $(gsettings get org.gnome.desktop.interface text-scaling-factor)"
echo "Экспериментальные функции: $(gsettings get org.gnome.mutter experimental-features)"
echo "Сглаживание шрифтов: $(gsettings get org.gnome.desktop.interface font-antialiasing)"
echo ""

# === ТЕКУЩИЕ НАСТРОЙКИ ===
# Масштаб интерфейса: uint32 1
# Масштаб текста: 1.0
# Экспериментальные функции: ['scale-monitor-framebuffer', 'xwayland-native-scaling']
# Сглаживание шрифтов: 'grayscale'

# Restart system to apply settings
echo "Script completed. Restart your system to apply changes. Restart now? (y/n)"
read -r RESTART
if [[ $RESTART == "y" || $RESTART == "Y" ]]; then
    sudo reboot
else
    echo "Restart your system later to apply all settings."
fi
