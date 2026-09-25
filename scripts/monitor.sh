#!/usr/bin/env bash
# scripts/monitor.sh
# Open the serial monitor for an ESP32.
#
# Usage:
#   ./scripts/monitor.sh              # auto-detect port
#   PORT=/dev/ttyUSB1 ./scripts/monitor.sh
#
# Press Ctrl+] to exit.
set -euo pipefail
source "$(dirname "$0")/_common.sh"
assert_idf_activated
[[ -z "${PORT:-}" ]] && find_esp_port && PORT="$ESP_PORT"
cd "$FIRMWARE_ROOT"
echo "Opening monitor on $PORT  (Ctrl+] to exit)..."
idf.py -p "$PORT" monitor
