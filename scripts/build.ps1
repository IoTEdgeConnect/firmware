# scripts/build.ps1
# Build the IoTEdgeConnect firmware.
#
# Usage:
#   .\scripts\build.ps1
#
# Requires ESP-IDF to be activated:
#   $IDF_PATH\export.ps1

[CmdletBinding()]
param()

. "$PSScriptRoot\_common.ps1"
Assert-IdfActivated

Set-Location "$PSScriptRoot\.."
Write-Host "Building firmware..." -ForegroundColor Cyan
idf.py build
