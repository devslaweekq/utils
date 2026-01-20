#!/bin/bash

# Настройка Tailscale Exit Node
# Конфигурирует сервер для использования в качестве VPN-выхода

set -e

echo "Настройка сервера как Tailscale Exit Node..."

# Проверка прав root
if [[ $EUID -ne 0 ]]; then
    echo "Ошибка: Запустите скрипт с правами root"
    echo "Используйте: sudo $0"
    exit 1
fi

# Проверка установки Tailscale
if ! command -v tailscale &> /dev/null; then
    echo "Ошибка: Tailscale не установлен"
    echo "Сначала запустите: ./install.sh"
    exit 1
fi

# Включение IP forwarding
echo "Включение IP forwarding..."
echo 'net.ipv4.ip_forward = 1' >> /etc/sysctl.conf
echo 'net.ipv6.conf.all.forwarding = 1' >> /etc/sysctl.conf
sysctl -p

# Настройка iptables для NAT
echo "Настройка NAT..."

# Определение основного интерфейса
PRIMARY_INTERFACE=$(ip route | grep default | awk '{print $5}' | head -n1)
echo "Основной интерфейс: $PRIMARY_INTERFACE"

# Добавление правил NAT
iptables -t nat -A POSTROUTING -o $PRIMARY_INTERFACE -j MASQUERADE
iptables -A FORWARD -i tailscale0 -o $PRIMARY_INTERFACE -j ACCEPT
iptables -A FORWARD -i $PRIMARY_INTERFACE -o tailscale0 -m state --state RELATED,ESTABLISHED -j ACCEPT

# Сохранение правил iptables
if command -v netfilter-persistent &> /dev/null; then
    netfilter-persistent save
elif command -v iptables-save &> /dev/null; then
    iptables-save > /etc/iptables/rules.v4 2>/dev/null || true
fi

echo "Правила iptables настроены"

# Запуск Tailscale как Exit Node
echo "Запуск Tailscale как Exit Node..."
tailscale up --advertise-exit-node --accept-routes

echo ""
echo "====================================="
echo "Exit Node настроен!"
echo "====================================="
echo ""
echo "Следующие шаги:"
echo "1. Перейдите в админ-панель: https://login.tailscale.com/admin/machines"
echo "2. Найдите ваш сервер в списке устройств"
echo "3. Включите опцию 'Exit node' для этого устройства"
echo "4. Подключите другие устройства к Tailscale"
echo "5. На устройствах выберите ваш сервер как Exit Node"
echo ""
echo "Статус: $(tailscale status --peers=false)"
echo ""
