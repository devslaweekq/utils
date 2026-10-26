#!/bin/bash
set -e

# chmod +x ./utils/gdrive/install.sh && ./utils/gdrive/install.sh

# Default configuration values
DEFAULT_NAME="gdrive"
DEFAULT_PATH="/mnt/d/.gdrive"
USER_NAME=$(whoami)

echo "=================================================="
echo "    Rclone Google Drive Setup Script"
echo "=================================================="

# Interactive prompt for the Rclone Remote Name
read -p "Enter Rclone remote name [$DEFAULT_NAME]: " REMOTE_NAME
REMOTE_NAME=${REMOTE_NAME:-$DEFAULT_NAME}

# Interactive prompt for the Mount Path
read -p "Enter local mount path [$DEFAULT_PATH]: " MOUNT_PATH
MOUNT_PATH=${MOUNT_PATH:-$DEFAULT_PATH}

echo "Using remote name: $REMOTE_NAME"
echo "Using mount path:  $MOUNT_PATH"
echo "--------------------------------------------------"

echo "=== 1. Installing dependencies & configuring FUSE ==="
sudo apt update
sudo apt install rclone fuse3 -y
sudo sed -i 's/#user_allow_other/user_allow_other/' /etc/fuse.conf

echo "=== 2. Creating target directories ==="
sudo mkdir -p "$MOUNT_PATH"
sudo chown -R "$USER_NAME":"$USER_NAME" "$MOUNT_PATH"
mkdir -p ~/.config/systemd/user/

echo "=== 3. Configuring Rclone Remote ==="
# Remove existing remote configuration if it already exists to prevent duplication conflicts
rclone config delete "$REMOTE_NAME" 2>/dev/null || true

# Generate new config. A web browser window will open automatically for Google OAuth verification.
rclone config create "$REMOTE_NAME" drive scope=drive --config ~/.config/rclone/rclone.conf

echo "=== 4. Generating Systemd User Service ==="
cat << EOF > ~/.config/systemd/user/rclone-gdrive.service
[Unit]
Description=Rclone Google Drive Mount ($REMOTE_NAME)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/bin/rclone mount ${REMOTE_NAME}: ${MOUNT_PATH} \\
  --vfs-cache-mode full \\
  --vfs-cache-max-age 72h \\
  --vfs-cache-max-size 100G \\
  --allow-other

ExecStop=/usr/bin/fusermount3 -u ${MOUNT_PATH}
Restart=on-failure
RestartSec=10

[Install]
WantedBy=default.target
EOF

echo "=== 5. Enabling and Activating the Service ==="
systemctl --user daemon-reload
systemctl --user enable --now rclone-gdrive.service

# Enable linger to ensure the mount initializes immediately on system boot without user login
sudo loginctl enable-linger "$USER_NAME"

echo "=== 6. Verifying Service Status ==="
sleep 2
systemctl --user status rclone-gdrive.service --no-pager
