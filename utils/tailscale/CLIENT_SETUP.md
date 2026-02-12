# Connecting devices to Tailscale VPN

## Step-by-step setup

### 1. Server setup

```bash
# Install Tailscale on the server
sudo ./install.sh

# Connect the server to the Tailscale network
sudo tailscale up

# Configure as Exit Node
sudo ./setup-exit-node.sh
```

### 2. Enable Exit Node in the admin panel

1. Open https://login.tailscale.com/admin/machines
2. Find your server in the list
3. Click the three dots next to the server
4. Select "Edit route settings..."
5. Enable "Use as exit node"
6. Click "Save"

### 3. Install on devices

#### Windows

1. Download Tailscale: https://tailscale.com/download/windows
2. Install and run it
3. Sign in with the same Tailscale account
4. Click the Tailscale icon in the tray
5. Choose "Use exit node" → your server

#### Android

1. Install from Google Play: "Tailscale"
2. Open the app and sign in
3. After connecting, open the menu (≡)
4. Tap "Use exit node"
5. Select your server from the list

#### iPhone/iPad

1. Install from the App Store: "Tailscale"
2. Open the app and sign in
3. Tap the settings icon (⚙️)
4. Choose "Exit Node"
5. Select your server

#### Linux Desktop

```bash
# Ubuntu/Debian
curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/jammy.noarmor.gpg | sudo tee /usr/share/keyrings/tailscale-archive-keyring.gpg >/dev/null
curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/jammy.tailscale-keyring.list | sudo tee /etc/apt/sources.list.d/tailscale.list
sudo apt update && sudo apt install tailscale

# Connect
sudo tailscale up

# Use exit node
sudo tailscale up --exit-node=NAME_OF_YOUR_SERVER
```

#### macOS

1. Download: https://tailscale.com/download/mac
2. Install and run it
3. Sign in to your account
4. In the Tailscale menu choose "Use exit node" → your server

### 4. Verify connectivity

After setup on any device:

1. Check your IP address:

    - Site: https://whatismyipaddress.com/
    - It should show the IP of your server

2. Check Tailscale status:

    ```bash
    tailscale status
    ```

3. Test connectivity to the server:
    ```bash
    ping IP_OF_YOUR_SERVER_IN_TAILSCALE
    ```

### 5. Useful commands

#### On the server:

```bash
# Exit Node status
tailscale status

# Show connected devices
tailscale status --peers

# Disable Exit Node
tailscale up --advertise-exit-node=false

# Restart with Exit Node
tailscale up --advertise-exit-node --accept-routes
```

#### On clients:

```bash
# Connect to exit node
tailscale up --exit-node=SERVER_NAME

# Disconnect from exit node
tailscale up --exit-node=

# List available exit nodes
tailscale exit-node list
```

### 6. Решение проблем

#### Не работает интернет через Exit Node:

1. Проверьте IP forwarding на сервере:

    ```bash
    cat /proc/sys/net/ipv4/ip_forward  # должно быть 1
    ```

2. Проверьте правила iptables:

    ```bash
    sudo iptables -t nat -L POSTROUTING -n
    ```

3. Перезапустите Tailscale на сервере:
    ```bash
    sudo systemctl restart tailscaled
    sudo tailscale up --advertise-exit-node --accept-routes
    ```

#### Exit Node не появляется в списке:

1. Убедитесь, что включили его в админ-панели
2. Подождите 1-2 минуты для синхронизации
3. Перезапустите Tailscale на клиенте

#### Медленная скорость:

1. Проверьте пропускную способность сервера
2. Выберите ближайший регион сервера
3. Проверьте нагрузку на сервер: `htop`

### 7. Автоматическое подключение

#### Android:

-   В настройках Tailscale включите "Auto-connect"
-   Включите "Always-on VPN" в настройках Android

#### iOS:

-   В настройках Tailscale включите "Auto-connect"
-   Добавьте VPN конфигурацию в настройки iOS

#### Windows:

-   Tailscale автоматически подключается при запуске системы
-   Exit node нужно выбирать вручную после каждого подключения

### 8. Сравнение производительности

Для сравнения с 3x-ui измерьте:

1. **Скорость соединения:**

    ```bash
    # Установите speedtest-cli
    pip install speedtest-cli

    # Тест без VPN
    speedtest-cli

    # Тест с Tailscale
    speedtest-cli

    # Тест с 3x-ui
    speedtest-cli
    ```

2. **Задержка (ping):**

    ```bash
    # До популярных сайтов
    ping -c 10 google.com
    ping -c 10 1.1.1.1
    ```

3. **Нагрузка на CPU сервера:**
    ```bash
    htop
    ```

### 9. Безопасность

-   Tailscale использует WireGuard протокол
-   Трафик зашифрован end-to-end
-   Автоматическая ротация ключей
-   Поддержка ACL (Access Control Lists)

### 10. Управление пользователями

В админ-панели https://login.tailscale.com/admin/:

1. **Users** - управление пользователями
2. **Machines** - управление устройствами
3. **Access Controls** - настройка прав доступа
4. **DNS** - настройка DNS
5. **Keys** - создание auth ключей для автоматической настройки
