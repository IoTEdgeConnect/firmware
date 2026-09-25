# scripts\_common.ps1
# Shared helpers for IoTEdgeConnect firmware scripts.
# Dot-source this file; do not run it directly.

# Known USB-to-serial VID:PID pairs used on common ESP32 dev boards.
$ESP32_VIDPIDS = @(
    '10C4:EA60',  # Silicon Labs CP210x  (most common)
    '1A86:7523',  # CH340               (cheap clones)
    '1A86:55D4',  # CH9102              (newer clones)
    '0403:6001',  # FTDI FT232RL
    '0403:6010',  # FTDI FT2232
    '303A:1001'   # Espressif USB-CDC   (ESP32-S3 / C3 native USB)
)

function Find-EspPort {
    <#
    .SYNOPSIS
        Returns the first COM port whose VID:PID matches a known ESP32 adapter.
        Falls back to prompting the user if none is found automatically.
    #>
    $ports = Get-WmiObject Win32_PnPEntity |
        Where-Object { $_.Name -match 'COM\d+' } |
        ForEach-Object {
            $name = $_.Name
            $id   = $_.DeviceID
            $com  = if ($name -match '\((COM\d+)\)') { $Matches[1] } else { $null }
            $vid  = if ($id   -match 'VID_([0-9A-F]{4})') { $Matches[1] } else { $null }
            $pid  = if ($id   -match 'PID_([0-9A-F]{4})') { $Matches[1] } else { $null }
            if ($com -and $vid -and $pid) {
                [PSCustomObject]@{ Port = $com; VidPid = "$($vid.ToUpper()):$($pid.ToUpper())"; Name = $name }
            }
        }

    $esp = $ports | Where-Object { $ESP32_VIDPIDS -contains $_.VidPid }

    if ($esp) {
        if (@($esp).Count -gt 1) {
            Write-Host "Multiple ESP32-compatible ports found:" -ForegroundColor Yellow
            $esp | ForEach-Object { Write-Host "  $($_.Port)  $($_.VidPid)  $($_.Name)" }
            Write-Host "Using $($esp[0].Port). Pass -Port to override." -ForegroundColor Yellow
            return $esp[0].Port
        }
        Write-Host "Detected ESP32 on $($esp.Port) ($($esp.VidPid))" -ForegroundColor Green
        return $esp.Port
    }

    Write-Host "No ESP32 detected automatically." -ForegroundColor Yellow
    Write-Host "Available serial ports:"
    $ports | ForEach-Object { Write-Host "  $($_.Port)  $($_.VidPid)  $($_.Name)" }
    $manual = Read-Host "Enter COM port (e.g. COM3)"
    return $manual
}

function Assert-IdfActivated {
    if (-not $env:IDF_PATH) {
        Write-Error "IDF_PATH is not set. Activate ESP-IDF first:`n  `$IDF_PATH\export.ps1"
        exit 1
    }
}
