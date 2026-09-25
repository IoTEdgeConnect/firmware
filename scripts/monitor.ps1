# scripts/monitor.ps1
# Open the serial monitor for an ESP32.
#
# Usage:
#   .\scripts\monitor.ps1              # auto-detect port
#   .\scripts\monitor.ps1 -Port COM3   # specify port
#
# Press Ctrl+] to exit the monitor.

[CmdletBinding()]
param(
    [string]$Port
)

. "$PSScriptRoot\_common.ps1"
Assert-IdfActivated

if (-not $Port) { $Port = Find-EspPort }

Set-Location "$PSScriptRoot\.."
Write-Host "Opening monitor on $Port  (Ctrl+] to exit)..." -ForegroundColor Cyan
idf.py -p $Port monitor
