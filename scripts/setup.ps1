# scripts/setup.ps1
# Check and install all dependencies required to build and flash IoTEdgeConnect firmware.
#
# Installer URLs are resolved at runtime from GitHub releases - no hardcoded
# versions that go stale over time.
#
# Run once after cloning:
#   scripts\run.cmd setup

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# ---------------------------------------------------------------------------
# Known ESP-IDF install locations, checked in priority order.
# The offline installer (used by setup) always installs to C:\Espressif\frameworks\esp-idf-v*
# Fallback paths cover manual installs.
# ---------------------------------------------------------------------------
$IDF_SEARCH_PATHS = @(
    'C:\Espressif\frameworks\esp-idf-v*',
    "$env:USERPROFILE\esp\esp-idf",
    'C:\esp\esp-idf'
)
$IDF_INSTALLER_TMP = "$env:TEMP\esp-idf-setup.exe"

function Write-Step([string]$msg) { Write-Host ""; Write-Host "==> $msg" -ForegroundColor Cyan }
function Write-Ok([string]$msg)   { Write-Host "    OK  $msg" -ForegroundColor Green }
function Write-Warn([string]$msg) { Write-Host "    !!  $msg" -ForegroundColor Yellow }

function Find-IdfInstall {
    foreach ($pattern in $IDF_SEARCH_PATHS) {
        $resolved = Resolve-Path $pattern -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($resolved -and (Test-Path "$($resolved.Path)\export.ps1")) {
            return $resolved.Path
        }
    }
    return $null
}

function Get-LatestGitHubRelease {
    param(
        [string]$Repo,
        [string]$TagPattern,
        [string]$AssetPattern
    )
    $headers  = @{ 'User-Agent' = 'IoTEdgeConnect-setup' }
    $releases = Invoke-RestMethod -Uri "https://api.github.com/repos/$Repo/releases" -Headers $headers
    $release  = $releases | Where-Object { $_.tag_name -match $TagPattern -and -not $_.prerelease } | Select-Object -First 1
    if (-not $release) { throw "No release found in $Repo matching '$TagPattern'." }
    $asset = $release.assets | Where-Object { $_.name -match $AssetPattern } | Select-Object -First 1
    if (-not $asset)   { throw "No asset found in '$($release.tag_name)' matching '$AssetPattern'." }
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
# 3. ESP-IDF
# ---------------------------------------------------------------------------
Write-Step "Checking ESP-IDF..."

$idfDir = Find-IdfInstall

if ($idfDir) {
    $versionFile = "$idfDir\version.txt"
    $ver = if (Test-Path $versionFile) { (Get-Content $versionFile -Raw).Trim() } else { 'unknown version' }
    Write-Ok "ESP-IDF found at $idfDir ($ver)"
} else {
    Write-Warn "ESP-IDF not found - resolving latest offline installer..."
    Write-Host "    Querying GitHub releases for espressif/idf-installer..." -ForegroundColor DarkGray

    # Offline installer bundles Python 3.11 and installs to C:\Espressif.
    # No system Python dependency, no venv mismatch.
    $installer = Get-LatestGitHubRelease `
        -Repo         'espressif/idf-installer' `
        -TagPattern   '^offline-' `
        -AssetPattern 'offline-\d+\.\d+\.\d+\.exe$'

    $sizeBytes = $installer.Size
    $sizeMB    = [math]::Round($sizeBytes / 1MB, 1)

    Write-Host "    Latest:    $($installer.Name) ($($installer.Version))" -ForegroundColor DarkGray
    Write-Host "    Location:  C:\Espressif (bundled Python, no system dependency)" -ForegroundColor DarkGray
    Write-Host "    Size:      $sizeMB MB ($sizeBytes bytes)" -ForegroundColor DarkGray
    Write-Host "    Downloading..." -ForegroundColor DarkGray

    # Start async download then poll the partial file size for progress.
    # WebClient.DownloadFileAsync is much faster than Invoke-WebRequest.
    # Progress events fire in a separate runspace so we poll the file instead.
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

    # Verify downloaded size matches GitHub API value
    $actualSize = (Get-Item $IDF_INSTALLER_TMP).Length
    if ($actualSize -ne $sizeBytes) {
        Write-Error "Download size mismatch: expected $sizeBytes bytes, got $actualSize. File may be corrupt."
        Remove-Item $IDF_INSTALLER_TMP -ErrorAction SilentlyContinue
        exit 1
    }

    $sha256 = (Get-FileHash $IDF_INSTALLER_TMP -Algorithm SHA256).Hash.ToLower()
    Write-Host "    Size OK:   $sizeMB MB" -ForegroundColor DarkGray
    Write-Host "    SHA256:    $sha256" -ForegroundColor DarkGray

    # Run the installer with its GUI visible so the user gets real-time progress.
    # /NORESTART prevents an automatic reboot if one is requested.
    $logFile = "$env:TEMP\esp-idf-setup.log"
    $installerArgs = @(
        '/NORESTART',
        "/LOG=`"$logFile`""
    )

    Write-Host "    Starting installer - follow the wizard for progress..." -ForegroundColor DarkGray
    Write-Host ""

    $proc = Start-Process -FilePath $IDF_INSTALLER_TMP -ArgumentList $installerArgs -Wait -PassThru
    Remove-Item $IDF_INSTALLER_TMP -ErrorAction SilentlyContinue
    Remove-Item $logFile -ErrorAction SilentlyContinue

    if ($proc.ExitCode -ne 0) {
        Write-Error "ESP-IDF installer exited with code $($proc.ExitCode)."
        exit 1
    }

    $idfDir = $null
    for ($attempt = 1; $attempt -le 5; $attempt++) {
        $idfDir = Find-IdfInstall
        if ($idfDir) { break }
        Start-Sleep -Seconds 2
    }
    if ($idfDir) {
        Write-Ok "ESP-IDF installed at $idfDir"
    } else {
        Write-Error "Installer completed but no ESP-IDF export.ps1 found. Check installer output."
        exit 1
    }
}

# ---------------------------------------------------------------------------
# 4. usbipd-win
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
$idfDir = Find-IdfInstall

Write-Host ""
Write-Host "-----------------------------------------------------------" -ForegroundColor Green
Write-Host " All dependencies are installed." -ForegroundColor Green
Write-Host "-----------------------------------------------------------" -ForegroundColor Green
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
