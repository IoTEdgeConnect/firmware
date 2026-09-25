#!/usr/bin/env bash
# scripts/build.sh
# Build the IoTEdgeConnect firmware.
#
# Usage:
#   ./scripts/build.sh
set -euo pipefail
source "$(dirname "$0")/_common.sh"
assert_idf_activated
cd "$FIRMWARE_ROOT"
echo "Building firmware..."
idf.py build
