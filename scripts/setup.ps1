# scripts/setup.ps1
# Check and install all dependencies required to build and flash IoTEdgeConnect firmware.
# Safe to re-run at any time - each step checks before acting.
#
# Steps:
#   1. Git
#   2. Python
#   3. C++ compiler (MSYS2 + MinGW g++)
#   4. ESP-IDF source (offline installer)
#   5. ESP-IDF toolchains (install.bat esp32)
#   6. usbipd-win
#
# Run with:
#   scripts\run.cmd setup

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$IDF_SEARCH_PATHS = @(
    'C:\Espressif\frameworks\esp-idf-v*',
    "$env:USERPROFILE\esp\esp-idf",
    'C:\esp\esp-idf'
)
$IDF_INSTALLER_TMP = "$env:TEMP\esp-idf-setup.exe"

function Write-Step([string]$msg) { Write-Host ""; Write-Host "==> $msg" -ForegroundColor Cyan }
function Write-Ok([string]$msg)   { Write-Host "    OK  $msg" -ForegroundColor Green }
function Write-Warn([string]$msg) { Write-Host "    !!  $msg" -ForegroundColor Yellow }

# Find the ESP-IDF source directory by checking known install locations.
function Find-IdfInstall {
    foreach ($pattern in $IDF_SEARCH_PATHS) {
        $resolved = Resolve-Path $pattern -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($resolved -and (Test-Path "$($resolved.Path)\export.ps1")) {
            return $resolved.Path
        }
    }
    return $null
}

# Derive the tools root from the IDF source location.
# Offline installer: C:\Espressif\frameworks\esp-idf-vX.Y.Z -> C:\Espressif
# Manual install:    C:\esp\esp-idf -> C:\esp  or  ~/.espressif
function Find-IdfToolsPath([string]$idfDir) {
    $candidates = @(
        (Split-Path (Split-Path $idfDir)),
        'C:\Espressif',
        "$env:USERPROFILE\.espressif"
    )
    return $candidates | Where-Object { Test-Path (Join-Path $_ 'tools') } | Select-Object -First 1
}

# Find the Python venv created by install.bat under the tools root.
function Find-IdfVenv([string]$toolsPath) {
    $envDir = Join-Path $toolsPath 'python_env'
    if (-not (Test-Path $envDir)) { return $null }
    return Get-ChildItem $envDir -Directory |
        Where-Object { Test-Path (Join-Path $_.FullName 'Scripts\python.exe') } |
        Sort-Object Name -Descending |
        Select-Object -First 1 -ExpandProperty FullName
}

function Get-LatestGitHubRelease {
    param([string]$Repo, [string]$TagPattern, [string]$AssetPattern)
    $headers  = @{ 'User-Agent' = 'IoTEdgeConnect-setup' }
    $releases = Invoke-RestMethod -Uri "https://api.github.com/repos/$Repo/releases" -Headers $headers
    $release  = $releases | Where-Object { $_.tag_name -match $TagPattern -and -not $_.prerelease } | Select-Object -First 1
    if (-not $release) { throw "No release found in $Repo matching '$TagPattern'." }
    $asset = $release.assets | Where-Object { $_.name -match $AssetPattern } | Select-Object -First 1
    if (-not $asset) { throw "No asset found in '$($release.tag_name)' matching '$AssetPattern'." }
    return [PSCustomObject]@{ Version = $release.tag_name; Url = $asset.browser_download_url; Name = $asset.name; Size = $asset.size }
}

# ---------------------------------------------------------------------------
# 1. Git
# ---------------------------------------------------------------------------
Write-Step "Checking Git..."
if (Get-Command git -ErrorAction SilentlyContinue) {
    Write-Ok "$(git --version)"
} else {
    Write-Warn "Git not found - installing via winget..."
    winget install --id Git.Git -e --source winget --accept-package-agreements --accept-source-agreements
    Write-Ok "Git installed. You may need to restart your terminal."
}

# ---------------------------------------------------------------------------
# 2. Python
# ---------------------------------------------------------------------------
Write-Step "Checking Python..."
if (Get-Command python -ErrorAction SilentlyContinue) {
    Write-Ok "$(python --version)"
} else {
    Write-Warn "Python not found - installing via winget..."
    winget install --id Python.Python.3.11 -e --source winget --accept-package-agreements --accept-source-agreements
    Write-Ok "Python installed. You may need to restart your terminal."
}

# ---------------------------------------------------------------------------
# 3. C++ compiler (MSYS2 + MinGW g++)
# ---------------------------------------------------------------------------
Write-Step "Checking C++ compiler..."

$gpp = Get-Command g++ -ErrorAction SilentlyContinue
if ($gpp) {
    Write-Ok "g++ found at $($gpp.Source)"
} else {
    # Check if MSYS2 is installed but g++ just isn't on PATH yet
    $msys2Root = 'C:\msys64'
    $mingwGpp  = "$msys2Root\mingw64\bin\g++.exe"

    if (-not (Test-Path $mingwGpp)) {
        Write-Warn "g++ not found - installing MSYS2 via winget..."
        winget install --id MSYS2.MSYS2 -e --source winget --accept-package-agreements --accept-source-agreements

        Write-Host "    Installing mingw-w64-x86_64-gcc via pacman..." -ForegroundColor DarkGray
        $pacman = "$msys2Root\usr\bin\pacman.exe"
        if (-not (Test-Path $pacman)) {
            Write-Error "MSYS2 installed but pacman not found at $pacman. Restart setup."
            exit 1
        }
        & $pacman -S --noconfirm mingw-w64-x86_64-gcc
    } else {
        Write-Host "    MSYS2 found but g++ not on PATH - adding MinGW to PATH..." -ForegroundColor DarkGray
    }

    # Add MinGW bin to the user PATH permanently
    $mingwBin = "$msys2Root\mingw64\bin"
    $userPath = [Environment]::GetEnvironmentVariable('PATH', 'User')
    if ($userPath -notlike "*$mingwBin*") {
        [Environment]::SetEnvironmentVariable('PATH', "$mingwBin;$userPath", 'User')
        $env:PATH = "$mingwBin;$env:PATH"
        Write-Host "    Added $mingwBin to user PATH" -ForegroundColor DarkGray
    }
    Write-Ok "g++ installed at $mingwBin\g++.exe"
    Write-Host "    NOTE: Open a new terminal for PATH changes to take effect." -ForegroundColor Yellow
}

# ---------------------------------------------------------------------------
# 4. ESP-IDF source
# ---------------------------------------------------------------------------
Write-Step "Checking ESP-IDF source..."

$idfDir = Find-IdfInstall

if ($idfDir) {
    $ver = if ($idfDir -match 'esp-idf-v([\d.]+)') { $Matches[1] } elseif (Test-Path "$idfDir\version.txt") { (Get-Content "$idfDir\version.txt" -Raw).Trim() } else { 'unknown version' }
    Write-Ok "ESP-IDF found at $idfDir ($ver)"
} else {
    Write-Warn "ESP-IDF not found - resolving latest offline installer..."
    Write-Host "    Querying GitHub releases for espressif/idf-installer..." -ForegroundColor DarkGray

    $installer = Get-LatestGitHubRelease `
        -Repo         'espressif/idf-installer' `
        -TagPattern   '^offline-' `
        -AssetPattern 'offline-\d+\.\d+\.\d+\.exe$'

    $sizeBytes = $installer.Size
    $sizeMB    = [math]::Round($sizeBytes / 1MB, 1)

    Write-Host "    Latest:   $($installer.Name) ($($installer.Version))" -ForegroundColor DarkGray
    Write-Host "    Location: C:\Espressif (bundled Python, no system dependency)" -ForegroundColor DarkGray
    Write-Host "    Size:     $sizeMB MB ($sizeBytes bytes)" -ForegroundColor DarkGray
    Write-Host "    Downloading..." -ForegroundColor DarkGray

    $wc = New-Object System.Net.WebClient
    $wc.Headers.Add('User-Agent', 'IoTEdgeConnect-setup')
    $wc.DownloadFileAsync([uri]$installer.Url, $IDF_INSTALLER_TMP)

    while ($wc.IsBusy) {
        Start-Sleep -Milliseconds 500
        if (Test-Path $IDF_INSTALLER_TMP) {
            $received = (Get-Item $IDF_INSTALLER_TMP).Length
            $pct      = [math]::Round(($received / $sizeBytes) * 100, 1)
            $recvMB   = [math]::Round($received / 1MB, 1)
            Write-Host "`r    $pct% - $recvMB MB / $sizeMB MB ($received / $sizeBytes bytes)   " -NoNewline
        }
    }
    Write-Host ""

    $actualSize = (Get-Item $IDF_INSTALLER_TMP).Length
    if ($actualSize -ne $sizeBytes) {
        Write-Error "Download size mismatch: expected $sizeBytes bytes, got $actualSize. File may be corrupt."
        Remove-Item $IDF_INSTALLER_TMP -ErrorAction SilentlyContinue
        exit 1
    }

    $sha256 = (Get-FileHash $IDF_INSTALLER_TMP -Algorithm SHA256).Hash.ToLower()
    Write-Host "    Size OK:  $sizeMB MB" -ForegroundColor DarkGray
    Write-Host "    SHA256:   $sha256" -ForegroundColor DarkGray
    Write-Host "    Starting installer - follow the wizard for progress..." -ForegroundColor DarkGray
    Write-Host ""

    $proc = Start-Process -FilePath $IDF_INSTALLER_TMP -ArgumentList '/NORESTART' -Wait -PassThru
    Remove-Item $IDF_INSTALLER_TMP -ErrorAction SilentlyContinue

    if ($proc.ExitCode -ne 0) {
        Write-Error "ESP-IDF installer exited with code $($proc.ExitCode)."
        exit 1
    }

    $idfDir = $null
    for ($i = 1; $i -le 5; $i++) {
        $idfDir = Find-IdfInstall
        if ($idfDir) { break }
        Start-Sleep -Seconds 2
    }
    if (-not $idfDir) {
        Write-Error "Installer completed but no ESP-IDF export.ps1 found. Check installer output."
        exit 1
    }
    Write-Ok "ESP-IDF installed at $idfDir"
}

# ---------------------------------------------------------------------------
# 5. ESP-IDF toolchains
# ---------------------------------------------------------------------------
Write-Step "Checking ESP-IDF toolchains..."

$toolsPath = Find-IdfToolsPath $idfDir
$xtensa    = if ($toolsPath) {
    Get-ChildItem (Join-Path $toolsPath 'tools\xtensa-esp-elf') -ErrorAction SilentlyContinue | Select-Object -First 1
} else { $null }

if ($xtensa) {
    Write-Ok "Toolchains found ($($xtensa.Name))"
    if ($toolsPath) { Write-Host "    Tools path: $toolsPath" -ForegroundColor DarkGray }
} else {
    Write-Warn "Toolchains not installed - running install.bat for esp32 target..."
    Write-Host "    This downloads ~500 MB of toolchain files." -ForegroundColor DarkGray
    if ($toolsPath) {
        $env:IDF_TOOLS_PATH = $toolsPath
        Write-Host "    IDF_TOOLS_PATH: $toolsPath" -ForegroundColor DarkGray
    }
    Write-Host ""
    $proc = Start-Process -FilePath "$idfDir\install.bat" -ArgumentList 'esp32' -Wait -PassThru -NoNewWindow
    if ($proc.ExitCode -ne 0) {
        Write-Error "install.bat failed (exit $($proc.ExitCode))."
        exit 1
    }
    Write-Ok "Toolchains installed"
}

# ---------------------------------------------------------------------------
# 6. usbipd-win
# ---------------------------------------------------------------------------
Write-Step "Checking usbipd-win..."
if (Get-Command usbipd -ErrorAction SilentlyContinue) {
    $ubVer = usbipd --version 2>&1 | Select-String '\d+\.\d+\.\d+' | ForEach-Object { $_.Matches[0].Value }
    Write-Ok "usbipd $ubVer"
} else {
    Write-Warn "usbipd-win not found - installing via winget..."
    winget install --id dorssel.usbipd-win -e --source winget --accept-package-agreements --accept-source-agreements
    Write-Ok "usbipd-win installed."
}

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
$idfDir    = Find-IdfInstall
$toolsPath = if ($idfDir) { Find-IdfToolsPath $idfDir } else { $null }
$venv      = if ($toolsPath) { Find-IdfVenv $toolsPath } else { $null }

Write-Host ""
Write-Host "-----------------------------------------------------------" -ForegroundColor Green
Write-Host " All dependencies are installed." -ForegroundColor Green
Write-Host "-----------------------------------------------------------" -ForegroundColor Green
Write-Host ""
Write-Host "  IDF source:  $idfDir"
Write-Host "  Tools path:  $toolsPath"
Write-Host "  Python venv: $venv"
Write-Host ""
Write-Host "Activate ESP-IDF in each new terminal before building:" -ForegroundColor Yellow
Write-Host ""
Write-Host "  PowerShell:  . $idfDir\export.ps1"
Write-Host "  cmd.exe:       $idfDir\export.bat"
Write-Host ""
Write-Host "Or just use run.cmd - it activates IDF automatically:" -ForegroundColor Yellow
Write-Host ""
Write-Host "  scripts\run.cmd build"
Write-Host "  scripts\run.cmd flash_monitor"
Write-Host ""
