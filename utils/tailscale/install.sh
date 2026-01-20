#!/bin/bash

# Tailscale Installation and Configuration Script

set -e

# Проверка прав root
if [[ $EUID -ne 0 ]]; then
    echo "Ошибка: Запустите скрипт с правами root"
    echo "Используйте: sudo $0"
    exit 1
fi

echo "Начинаем установку Tailscale..."

# Определение дистрибутива
if [ -f /etc/os-release ]; then
    . /etc/os-release
    DISTRO=$ID
else
    echo "Ошибка: Не удается определить дистрибутив Linux"
    exit 1
fi

echo "Обнаружен дистрибутив: $DISTRO"

# Обновление пакетов и установка зависимостей
echo "Обновление пакетов..."
case $DISTRO in
    ubuntu|debian)
        sudo apt update -qq
        sudo apt install -y curl wget gnupg lsb-release apt-transport-https ca-certificates
        ;;
    centos|rhel|fedora|rocky|almalinux)
        if command -v dnf &> /dev/null; then
            sudo dnf install -y curl wget gnupg
        else
            sudo yum install -y curl wget gnupg
        fi
        ;;
    *)
        echo "Предупреждение: Неизвестный дистрибутив"
        ;;
esac

# Установка Tailscale
echo "Установка Tailscale..."
curl -fsSL https://tailscale.com/install.sh | sh

# Запуск сервиса
echo "Запуск сервиса tailscaled..."
# Настройка systemd сервиса
sudo systemctl enable tailscaled
sudo systemctl start tailscaled

# Проверка статуса
if systemctl is-active --quiet tailscaled; then
    echo "Сервис tailscaled успешно запущен"
else
    echo "Ошибка: Не удалось запустить сервис tailscaled"
    exit 1
fi

# Настройка брандмауэра
echo "Настройка брандмауэра..."
if command -v ufw &> /dev/null; then
    sudo ufw allow 41641/udp >/dev/null 2>&1 || true
fi

# firewalld (RHEL/CentOS/Fedora)
if command -v firewall-cmd &> /dev/null && systemctl is-active --quiet firewalld; then
    sudo firewall-cmd --permanent --add-port=41641/udp >/dev/null 2>&1 || true
    sudo firewall-cmd --reload >/dev/null 2>&1 || true
fi

# iptables (резервный вариант)
if command -v iptables &> /dev/null; then
    sudo iptables -I INPUT -p udp --dport 41641 -j ACCEPT
    # Сохранение правил (зависит от дистрибутива)
    if command -v iptables-save &> /dev/null; then
        sudo iptables-save > /etc/iptables/rules.v4 2>/dev/null || true
    fi
    echo "Правило iptables добавлено для порта 41641/udp"
fi
echo ""
echo "Установка Tailscale завершена!"
echo ""
echo "Следующие шаги:"
echo "1. Интерактивная аутентификация (рекомендуется для первой настройки): tailscale up"
echo "2. Или использование Auth Key (для автоматизации): tailscale up --authkey=YOUR_KEY"
echo "3. Настройка как Exit Node (для маршрутизации трафика): tailscale up --advertise-exit-node"
echo ""
echo "Полезные команды:"
echo "  tailscale status  - статус подключения"
echo "  tailscale ip      - ваш IP адрес"
echo "  tailscale down    - отключиться"
echo ""
echo "Админ-панель: https://login.tailscale.com/admin/"

echo ""
