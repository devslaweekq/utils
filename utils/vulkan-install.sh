#!/bin/bash
set -e

# Installs the LunarG Vulkan SDK into /usr/local.
# Usage: ./vulkan-install.sh [version]   (latest version if omitted)

SDK_DIR="/tmp/VulkanSDK"
PREFIX="/usr/local"

echo "🔹 Installing Vulkan SDK..."
echo '#################################################################'

VERSION="$1"
if [ -z "$VERSION" ]; then
    echo "Looking up the latest Vulkan SDK version..."
    VERSION="$(curl -fsSL https://vulkan.lunarg.com/sdk/latest/linux.txt | tr -d '[:space:]')"
fi

if ! [[ "$VERSION" =~ ^[0-9]+(\.[0-9]+){3}$ ]]; then
    echo "Invalid version: '$VERSION'" >&2
    exit 1
fi

ARCHIVE="vulkansdk-linux-x86_64-${VERSION}.tar.xz"
URL="https://sdk.lunarg.com/sdk/download/${VERSION}/linux/${ARCHIVE}"

mkdir -p "$SDK_DIR"
cd "$SDK_DIR"

if [ ! -f "$ARCHIVE" ]; then
    echo "Downloading $URL..."
    curl -fL --retry 3 -C - -o "$ARCHIVE.part" "$URL"
    mv "$ARCHIVE.part" "$ARCHIVE"
fi

if [ ! -d "$VERSION/x86_64" ]; then
    echo "Extracting to $SDK_DIR/$VERSION..."
    tar -xJf "$ARCHIVE" -C "$SDK_DIR"
fi

echo "Copying to $PREFIX..."
sudo cp -r "$SDK_DIR/$VERSION/x86_64/"* "$PREFIX/"
sudo ldconfig

echo "Vulkan SDK $VERSION installed."
vulkaninfo --summary 2>/dev/null | head -n 5 || echo "vulkaninfo failed. Check the GPU driver."

rm -rf "$SDK_DIR"
