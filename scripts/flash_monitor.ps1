# scripts/flash_monitor.ps1
# Flash the firmware and immediately open the serial monitor.
#
# Usage:
#   .\scripts\flash_monitor.ps1              # auto-detect port
#   .\scripts\flash_monitor.ps1 -Port COM3   # specify port
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
Write-Host "Flashing and monitoring on $Port  (Ctrl+] to exit)..." -ForegroundColor Cyan
idf.py -p $Port flash monitor
