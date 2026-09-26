# scripts/setup.ps1
# Check and install all dependencies required to build and flash IoTEdgeConnect firmware.
#
# What this script does:
#   1. Verifies Git and Python are present (required before ESP-IDF install)
#   2. Installs ESP-IDF v5.4 via the official Windows installer if not found
#   3. Installs usbipd-win via winget if not found
#   4. Prints activation instructions for the current session
#
# Run once after cloning:
#   scripts\run.cmd setup

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$IDF_VERSION      = '5.4'
$IDF_INSTALL_DIR  = "$env:USERPROFILE\esp\esp-idf"
$IDF_TOOLS_DIR    = "$env:USERPROFILE\.espressif"
$IDF_INSTALLER_URL = 'https://dl.espressif.com/dl/esp-idf/esp-idf-tools-setup-online.exe'
$IDF_INSTALLER_TMP = "$env:TEMP\esp-idf-setup.exe"

function Write-Step([string]$msg) {
    Write-Host ""
    Write-Host "==> $msg" -ForegroundColor Cyan
}

function Write-Ok([string]$msg)   { Write-Host "    OK  $msg" -ForegroundColor Green }
function Write-Skip([string]$msg) { Write-Host "    --  $msg" -ForegroundColor DarkGray }
function Write-Warn([string]$msg) { Write-Host "    !!  $msg" -ForegroundColor Yellow }

# ---------------------------------------------------------------------------
# 1. Git
# ---------------------------------------------------------------------------
Write-Step "Checking Git..."
if (Get-Command git -ErrorAction SilentlyContinue) {
    Write-Ok "Git $(git --version)"
} else {
    Write-Warn "Git not found. Installing via winget..."
    winget install --id Git.Git -e --source winget --accept-package-agreements --accept-source-agreements
    Write-Ok "Git installed. You may need to restart your terminal."
}

# ---------------------------------------------------------------------------
# 2. Python
# ---------------------------------------------------------------------------
Write-Step "Checking Python..."
if (Get-Command python -ErrorAction SilentlyContinue) {
    Write-Ok "Python $(python --version)"
} else {
    Write-Warn "Python not found. Installing via winget..."
    winget install --id Python.Python.3.11 -e --source winget --accept-package-agreements --accept-source-agreements
    Write-Ok "Python installed. You may need to restart your terminal."
}

# ---------------------------------------------------------------------------
# 3. ESP-IDF
# ---------------------------------------------------------------------------
Write-Step "Checking ESP-IDF..."

$idfExport = "$IDF_INSTALL_DIR\export.ps1"

if (Test-Path $idfExport) {
    Write-Ok "ESP-IDF found at $IDF_INSTALL_DIR"
} else {
    Write-Warn "ESP-IDF not found. Downloading installer (this will take a few minutes)..."
    Write-Host "    Installing to: $IDF_INSTALL_DIR" -ForegroundColor DarkGray
    Write-Host "    Tools dir:     $IDF_TOOLS_DIR" -ForegroundColor DarkGray

    # Download the online installer
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri $IDF_INSTALLER_URL -OutFile $IDF_INSTALLER_TMP -UseBasicParsing

    # Run the installer silently
    # /IDFDIR        — where to clone the IDF repo
    # /IDFTOOLDEST   — where to install toolchains
    # /IDFVERSIONS   — which IDF version to install
    # /COMPONENTS    — esp32 target only for Phase 1
    $installerArgs = @(
        "/VERYSILENT",
        "/SUPPRESSMSGBOXES",
        "/NORESTART",
        "/IDFDIR=`"$IDF_INSTALL_DIR`"",
        "/IDFTOOLDEST=`"$IDF_TOOLS_DIR`"",
        "/IDFVERSIONS=v$IDF_VERSION",
        "/COMPONENTS=idf,tools,cmake,ninja,python"
    )

    Write-Host "    Running installer (a progress window will appear)..." -ForegroundColor DarkGray
    $proc = Start-Process -FilePath $IDF_INSTALLER_TMP -ArgumentList $installerArgs -Wait -PassThru
    Remove-Item $IDF_INSTALLER_TMP -ErrorAction SilentlyContinue

    if ($proc.ExitCode -ne 0) {
        Write-Error "ESP-IDF installer exited with code $($proc.ExitCode)."
        exit 1
    }

    if (Test-Path $idfExport) {
        Write-Ok "ESP-IDF $IDF_VERSION installed at $IDF_INSTALL_DIR"
    } else {
        Write-Error "Installer completed but export.ps1 not found at $idfExport. Check the installer output."
        exit 1
    }
}

# ---------------------------------------------------------------------------
# 4. usbipd-win
# ---------------------------------------------------------------------------
Write-Step "Checking usbipd-win..."
if (Get-Command usbipd -ErrorAction SilentlyContinue) {
    Write-Ok "usbipd $(usbipd --version 2>&1 | Select-String '\d+\.\d+\.\d+' | ForEach-Object { $_.Matches[0].Value })"
} else {
    Write-Warn "usbipd-win not found. Installing via winget..."
    winget install --id dorssel.usbipd-win -e --source winget --accept-package-agreements --accept-source-agreements
    Write-Ok "usbipd-win installed."
}

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "-----------------------------------------------------------" -ForegroundColor Green
Write-Host " All dependencies are installed." -ForegroundColor Green
Write-Host "-----------------------------------------------------------" -ForegroundColor Green
Write-Host ""
Write-Host "Before building, activate ESP-IDF in your terminal:" -ForegroundColor Yellow
Write-Host ""
Write-Host "  PowerShell:   . $IDF_INSTALL_DIR\export.ps1"
Write-Host "  cmd.exe:       $IDF_INSTALL_DIR\export.bat"
Write-Host ""
Write-Host "Then build and flash:" -ForegroundColor Yellow
Write-Host ""
Write-Host "  scripts\run.cmd build"
Write-Host "  scripts\run.cmd flash_monitor"
Write-Host ""
