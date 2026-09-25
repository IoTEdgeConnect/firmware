#!/usr/bin/env bash
# scripts/flash.sh
# Flash the IoTEdgeConnect firmware to an ESP32.
#
# Usage:
#   ./scripts/flash.sh              # auto-detect port
#   PORT=/dev/ttyUSB1 ./scripts/flash.sh
set -euo pipefail
source "$(dirname "$0")/_common.sh"
assert_idf_activated
[[ -z "${PORT:-}" ]] && find_esp_port && PORT="$ESP_PORT"
cd "$FIRMWARE_ROOT"
echo "Flashing to $PORT..."
idf.py -p "$PORT" flash
