#!/usr/bin/env bash
# scripts/flash_monitor.sh
# Flash the firmware and immediately open the serial monitor.
#
# Usage:
#   ./scripts/flash_monitor.sh              # auto-detect port
#   PORT=/dev/ttyUSB1 ./scripts/flash_monitor.sh
#
# Press Ctrl+] to exit.
set -euo pipefail
source "$(dirname "$0")/_common.sh"
assert_idf_activated
[[ -z "${PORT:-}" ]] && find_esp_port && PORT="$ESP_PORT"
cd "$FIRMWARE_ROOT"
echo "Flashing and monitoring on $PORT  (Ctrl+] to exit)..."
idf.py -p "$PORT" flash monitor
