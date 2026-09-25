# scripts/flash.ps1
# Flash the IoTEdgeConnect firmware to an ESP32.
#
# Usage:
#   .\scripts\flash.ps1              # auto-detect port
#   .\scripts\flash.ps1 -Port COM3   # specify port

[CmdletBinding()]
param(
    [string]$Port
)

. "$PSScriptRoot\_common.ps1"
Assert-IdfActivated

if (-not $Port) { $Port = Find-EspPort }

Set-Location "$PSScriptRoot\.."
Write-Host "Flashing to $Port..." -ForegroundColor Cyan
idf.py -p $Port flash
