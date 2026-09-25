#!/usr/bin/env bash
# scripts/wsl_setup.sh
# One-time setup: install the WSL-side tools needed to receive a USB device
# forwarded from Windows via usbipd-win.
#
# Run once inside your WSL distro:
#   bash scripts/wsl_setup.sh
#
# On Windows, usbipd-win must already be installed:
#   winget install usbipd

set -euo pipefail

echo "==> Updating package lists..."
sudo apt-get update -q

echo "==> Installing usbip client and USB ID database..."
# linux-tools-generic provides the usbip client binary.
# hwdata provides /var/lib/usbutils/usb.ids for device name resolution.
sudo apt-get install -y linux-tools-generic hwdata

echo "==> Adding $USER to the 'dialout' group (required for /dev/ttyUSB* access)..."
sudo usermod -aG dialout "$USER"

echo ""
echo "Done."
echo ""
echo "IMPORTANT: close and reopen your WSL terminal for the group change to take effect."
echo ""
echo "Workflow:"
echo "  1. Plug in your ESP32."
echo "  2. In PowerShell (Windows):  .\\scripts\\wsl_attach.ps1"
echo "  3. In WSL:                   ./scripts/flash_monitor.sh"
echo "  4. In PowerShell (Windows):  .\\scripts\\wsl_detach.ps1   (when done)"
