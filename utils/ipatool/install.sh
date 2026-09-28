#!/bin/bash

# ipatool installer for Ubuntu — downloads and installs the latest release
# https://github.com/majd/ipatool

set -e

REPO="majd/ipatool"
INSTALL_DIR="/usr/local/bin"
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

case "$(uname -m)" in
    x86_64) ARCH="amd64" ;;
    aarch64|arm64) ARCH="arm64" ;;
    *) echo "Error: unsupported architecture $(uname -m)"; exit 1 ;;
esac

sudo apt update -qq
sudo apt install -y curl tar

echo "Resolving latest ipatool release..."
LATEST_TAG=$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" | grep '"tag_name"' | head -1 | cut -d '"' -f4)
if [[ -z "$LATEST_TAG" ]]; then
    echo "Error: could not resolve latest release tag"
    exit 1
fi
VERSION="${LATEST_TAG#v}"

ASSET="ipatool-${VERSION}-linux-${ARCH}.tar.gz"
URL="https://github.com/${REPO}/releases/download/${LATEST_TAG}/${ASSET}"

echo "Downloading ${ASSET} (${LATEST_TAG})..."
curl -fsSL "$URL" -o "${TMP_DIR}/${ASSET}"
curl -fsSL "${URL}.sha256sum" -o "${TMP_DIR}/${ASSET}.sha256sum"

echo "Verifying checksum..."
EXPECTED_SHA=$(tr -d ' \n' < "${TMP_DIR}/${ASSET}.sha256sum")
ACTUAL_SHA=$(sha256sum "${TMP_DIR}/${ASSET}" | awk '{print $1}')
if [[ "$EXPECTED_SHA" != "$ACTUAL_SHA" ]]; then
    echo "Error: checksum mismatch for ${ASSET}"
    echo "  expected: $EXPECTED_SHA"
    echo "  actual:   $ACTUAL_SHA"
    exit 1
fi

echo "Extracting..."
tar -xzf "${TMP_DIR}/${ASSET}" -C "$TMP_DIR"

BIN_PATH=$(find "$TMP_DIR" -type f -name "ipatool-${VERSION}-linux-${ARCH}")
if [[ -z "$BIN_PATH" ]]; then
    echo "Error: ipatool binary not found in archive"
    exit 1
fi

echo "Installing to ${INSTALL_DIR}/ipatool..."
chmod +x "$BIN_PATH"
sudo install -m 755 "$BIN_PATH" "${INSTALL_DIR}/ipatool"

echo ""
ipatool --version
echo ""
echo "ipatool installed successfully."
echo "Usage:"
echo "  ipatool auth login -e your@appleid.com"
echo "  ipatool search -t <app-name>"
echo "  ipatool download -b <bundle-id> -o app.ipa"
