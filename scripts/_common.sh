#!/usr/bin/env bash
# scripts/_common.sh
# Shared helpers for IoTEdgeConnect firmware scripts.
# Source this file; do not run it directly.

# Resolve the firmware root regardless of where the script is called from.
FIRMWARE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

assert_idf_activated() {
    if [[ -z "${IDF_PATH:-}" ]]; then
        echo "ERROR: IDF_PATH is not set. Activate ESP-IDF first:" >&2
        echo "  . \$IDF_PATH/export.sh" >&2
        exit 1
    fi
}

# Ordered list of candidate device globs for ESP32 serial adapters.
# ttyUSB* = CP210x / CH340 / FT232   ttyACM* = Espressif native USB (S3/C3)
_PORT_GLOBS=(/dev/ttyUSB* /dev/ttyACM*)

find_esp_port() {
    # Returns the port in $ESP_PORT, or exits with an error.
    local candidates=()
    for glob in "${_PORT_GLOBS[@]}"; do
        # glob may be unexpanded if nothing matches
        [[ -e "$glob" ]] && candidates+=("$glob")
    done

    if [[ ${#candidates[@]} -eq 0 ]]; then
        echo "ERROR: No serial device found at /dev/ttyUSB* or /dev/ttyACM*." >&2
        echo "  - On Windows: run scripts/wsl_attach.ps1 to attach the ESP32 to WSL." >&2
        echo "  - On Linux:   check 'ls /dev/tty{USB,ACM}*' and your user is in the 'dialout' group." >&2
        exit 1
    fi

    if [[ ${#candidates[@]} -gt 1 ]]; then
        echo "Multiple serial devices found:" >&2
        for p in "${candidates[@]}"; do echo "  $p" >&2; done
        echo "Using ${candidates[0]}. Set PORT= to override." >&2
    else
        echo "Detected ESP32 on ${candidates[0]}" >&2
    fi

    ESP_PORT="${candidates[0]}"
}
