# scripts/wsl_attach.ps1
# Attach an ESP32 USB device to WSL using usbipd-win.
#
# Requires:
#   - usbipd-win installed on Windows  (winget install usbipd)
#   - linux-tools-generic in WSL       (sudo apt install linux-tools-generic hwdata)
#
# Usage:
#   .\scripts\wsl_attach.ps1                        # auto-detect ESP32
#   .\scripts\wsl_attach.ps1 -Distro Ubuntu-24.04   # target a specific WSL distro
#   .\scripts\wsl_attach.ps1 -BusId 2-3             # specify busid directly
#
# After running this script the device appears in WSL as /dev/ttyUSB0 or /dev/ttyACM0.
# Run .\scripts\wsl_detach.ps1 to release it back to Windows when done.

[CmdletBinding()]
param(
    [string]$Distro = 'Ubuntu-24.04',
    [string]$BusId
)

# Known ESP32 USB-serial VID:PID pairs
$ESP32_VIDPIDS = @(
    '10c4:ea60',  # CP210x
    '1a86:7523',  # CH340
    '1a86:55d4',  # CH9102
    '0403:6001',  # FT232RL
    '0403:6010',  # FT2232
    '303a:1001'   # Espressif native USB (S3/C3)
)

if (-not (Get-Command usbipd -ErrorAction SilentlyContinue)) {
    Write-Error "usbipd not found. Install it with: winget install usbipd"
    exit 1
}

if (-not $BusId) {
    Write-Host "Scanning for ESP32 USB devices..." -ForegroundColor Cyan

    $devices = usbipd list 2>&1 | Select-String '^\d+-\d+' | ForEach-Object {
        $line = $_.Line.Trim()
        if ($line -match '^(\d+-\d+)\s+([0-9a-f]{4}:[0-9a-f]{4})\s+(.+?)\s+(Not shared|Shared|Attached)') {
            [PSCustomObject]@{
                BusId  = $Matches[1]
                VidPid = $Matches[2]
                Name   = $Matches[3].Trim()
                State  = $Matches[4]
            }
        }
    }

    $esp = $devices | Where-Object { $ESP32_VIDPIDS -contains $_.VidPid }

    if (-not $esp) {
        Write-Host "No ESP32 detected. All connected USB devices:" -ForegroundColor Yellow
        $devices | ForEach-Object { Write-Host "  $($_.BusId)  $($_.VidPid)  $($_.Name)  [$($_.State)]" }
        Write-Host ""
        Write-Host "Plug in your ESP32 and try again, or pass -BusId manually." -ForegroundColor Yellow
        exit 1
    }

    if (@($esp).Count -gt 1) {
        Write-Host "Multiple ESP32-compatible devices found:" -ForegroundColor Yellow
        $esp | ForEach-Object { Write-Host "  $($_.BusId)  $($_.VidPid)  $($_.Name)" }
        Write-Host "Using $($esp[0].BusId). Pass -BusId to override." -ForegroundColor Yellow
        $esp = $esp[0]
    }

    Write-Host "Found: $($esp.BusId)  $($esp.VidPid)  $($esp.Name)  [$($esp.State)]" -ForegroundColor Green
    $BusId = $esp.BusId

    if ($esp.State -eq 'Attached') {
        Write-Host "Device is already attached to WSL." -ForegroundColor Green
        exit 0
    }
}

# Bind requires elevation. If not already elevated, spawn an elevated child
# process for the bind step only — avoids a silent hang when UAC is suppressed.
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)

if ($isAdmin) {
    Write-Host "Binding $BusId..." -ForegroundColor Cyan
    usbipd bind --busid $BusId
    if ($LASTEXITCODE -ne 0) { Write-Error "Bind failed."; exit 1 }
} else {
    Write-Host "Binding $BusId (a UAC prompt will appear)..." -ForegroundColor Cyan
    $proc = Start-Process powershell.exe `
        -ArgumentList "-NoProfile -ExecutionPolicy Bypass -Command `"usbipd bind --busid $BusId`"" `
        -Verb RunAs -Wait -PassThru
    if ($proc.ExitCode -ne 0) {
        Write-Error "Bind failed (exit $($proc.ExitCode)). Try running this script as Administrator."
        exit 1
    }
}

# Attach does not require elevation
Write-Host "Attaching $BusId to WSL distro '$Distro'..." -ForegroundColor Cyan
usbipd attach --wsl $Distro --busid $BusId

if ($LASTEXITCODE -eq 0) {
    Write-Host ""
    Write-Host "Done. In WSL, your device should appear as /dev/ttyUSB0 or /dev/ttyACM0." -ForegroundColor Green
    Write-Host "Verify with:  wsl -d $Distro -- ls /dev/ttyUSB* /dev/ttyACM* 2>/dev/null" -ForegroundColor DarkGray
    Write-Host "Detach with:  .\scripts\wsl_detach.ps1" -ForegroundColor DarkGray
} else {
    Write-Error "usbipd attach failed (exit $LASTEXITCODE)."
}
