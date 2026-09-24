#!/bin/bash
set -euo pipefail

# Installer script for patched Nouveau kernel module (MCP89 HDMI Audio Fix)
echo "=== NVIDIA MCP89 / GeForce 320M Nouveau HDMI Audio Installer ==="

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGE_DIR="$(cd "${SCRIPT_DIR}/../packages" && pwd)"
KVER="$(uname -r)"

if [ "$EUID" -ne 0 ]; then
  echo "Error: Please run as root (e.g. sudo bash install_module.sh)" >&2
  exit 1
fi

TARGET_MOD="/lib/modules/${KVER}/kernel/drivers/gpu/drm/nouveau/nouveau.ko"
SOURCE_MOD="${PACKAGE_DIR}/nouveau.ko"

if [ ! -f "${SOURCE_MOD}" ]; then
  echo "Error: Precompiled module ${SOURCE_MOD} not found!" >&2
  exit 1
fi

echo "[1/4] Backing up existing nouveau.ko..."
if [ -f "${TARGET_MOD}" ]; then
  cp -v "${TARGET_MOD}" "${TARGET_MOD}.bak.$(date +%Y%m%d_%H%M%S)"
fi

echo "[2/4] Installing patched nouveau.ko..."
cp -v "${SOURCE_MOD}" "${TARGET_MOD}"
chmod 644 "${TARGET_MOD}"

echo "[3/4] Updating kernel module dependencies..."
depmod -a "${KVER}"

echo "[4/4] Updating initramfs..."
if command -v update-initramfs >/dev/null 2>&1; then
  update-initramfs -u -k "${KVER}"
elif command -v dracut >/dev/null 2>&1; then
  dracut --force "/boot/initramfs-${KVER}.img" "${KVER}"
elif command -v mkinitcpio >/dev/null 2>&1; then
  mkinitcpio -P
else
  echo "Warning: No standard initramfs tool found. Please update your initramfs manually."
fi

echo "=========================================================="
echo "Installation complete!"
echo "Please ensure your GRUB kernel command line includes:"
echo "    nouveau.modeset=1 nouveau.config=NvAudio=1"
echo "Reboot to load the new driver."
echo "=========================================================="
