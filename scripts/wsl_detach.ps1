# scripts/wsl_detach.ps1
# Detach an ESP32 from WSL and return it to Windows.
#
# Usage:
#   .\scripts\wsl_detach.ps1              # auto-detect attached ESP32
#   .\scripts\wsl_detach.ps1 -BusId 2-3   # specify busid directly

[CmdletBinding()]
param(
    [string]$BusId
)

$ESP32_VIDPIDS = @(
    '10c4:ea60', '1a86:7523', '1a86:55d4',
    '0403:6001', '0403:6010', '303a:1001'
)

if (-not (Get-Command usbipd -ErrorAction SilentlyContinue)) {
    Write-Error "usbipd not found."
    exit 1
}

if (-not $BusId) {
    $devices = usbipd list 2>&1 | Select-String '^\d+-\d+' | ForEach-Object {
        $line = $_.Line.Trim()
        if ($line -match '^(\d+-\d+)\s+([0-9a-f]{4}:[0-9a-f]{4})\s+(.+?)\s+(Not shared|Shared|Attached)') {
            [PSCustomObject]@{ BusId = $Matches[1]; VidPid = $Matches[2]; State = $Matches[4] }
        }
    }

    $esp = $devices | Where-Object { $ESP32_VIDPIDS -contains $_.VidPid -and $_.State -eq 'Attached' }

    if (-not $esp) {
        Write-Host "No attached ESP32 found — nothing to detach." -ForegroundColor Yellow
        exit 0
    }

    $BusId = $esp[0].BusId
    Write-Host "Detaching $BusId..." -ForegroundColor Cyan
}

usbipd detach --busid $BusId

if ($LASTEXITCODE -eq 0) {
    Write-Host "Device $BusId returned to Windows." -ForegroundColor Green
} else {
    Write-Error "usbipd detach failed (exit $LASTEXITCODE)."
}
