# Подключение устройств к Tailscale VPN

## Пошаговая настройка

### 1. Настройка сервера

```bash
# Установка Tailscale на сервер
sudo ./install.sh

# Подключение сервера к сети
sudo tailscale up

# Настройка как Exit Node
sudo ./setup-exit-node.sh
```

### 2. Активация Exit Node в админ-панели

1. Откройте https://login.tailscale.com/admin/machines
2. Найдите ваш сервер в списке
3. Нажмите на троеточие рядом с сервером
4. Выберите "Edit route settings..."
5. Включите "Use as exit node"
6. Нажмите "Save"

### 3. Установка на устройства

#### Windows

1. Скачайте Tailscale: https://tailscale.com/download/windows
2. Установите и запустите
3. Войдите в тот же аккаунт Tailscale
4. В трее нажмите на иконку Tailscale
5. Выберите "Use exit node" → ваш сервер

#### Android

1. Установите из Google Play: "Tailscale"
2. Откройте приложение и войдите в аккаунт
3. После подключения откройте меню (≡)
4. Нажмите "Use exit node"
5. Выберите ваш сервер из списка

#### iPhone/iPad

1. Установите из App Store: "Tailscale"
2. Откройте приложение и войдите в аккаунт
3. Нажмите на значок настроек (⚙️)
4. Выберите "Exit Node"
5. Выберите ваш сервер

#### Linux Desktop

```bash
# Ubuntu/Debian
curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/jammy.noarmor.gpg | sudo tee /usr/share/keyrings/tailscale-archive-keyring.gpg >/dev/null
curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/jammy.tailscale-keyring.list | sudo tee /etc/apt/sources.list.d/tailscale.list
sudo apt update && sudo apt install tailscale

# Подключение
sudo tailscale up

# Использование exit node
sudo tailscale up --exit-node=ИМЯ_ВАШЕГО_СЕРВЕРА
```

#### macOS

1. Скачайте: https://tailscale.com/download/mac
2. Установите и запустите
3. Войдите в аккаунт
4. В меню Tailscale выберите "Use exit node" → ваш сервер

### 4. Проверка подключения

После настройки на любом устройстве:

1. Проверьте IP адрес:

    - Сайт: https://whatismyipaddress.com/
    - Должен показывать IP вашего сервера

2. Проверьте статус Tailscale:

    ```bash
    tailscale status
    ```

3. Проверьте соединение с сервером:
    ```bash
    ping IP_ВАШЕГО_СЕРВЕРА_В_TAILSCALE
    ```

### 5. Полезные команды

#### На сервере:

```bash
# Статус Exit Node
tailscale status

# Просмотр подключенных устройств
tailscale status --peers

# Отключить Exit Node
tailscale up --advertise-exit-node=false

# Перезапустить с Exit Node
tailscale up --advertise-exit-node --accept-routes
```

#### На клиентах:

```bash
# Подключиться к exit node
tailscale up --exit-node=ИМЯ_СЕРВЕРА

# Отключиться от exit node
tailscale up --exit-node=

# Список доступных exit nodes
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
