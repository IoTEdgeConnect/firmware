# scripts\_idf_env.ps1
# Called by run.cmd to detect ESP-IDF paths and write them as key=value
# pairs to a temp file. run.cmd reads the file and sets the variables.
# Not intended to be run directly.

param([string]$OutFile)

$IDF_SEARCH_PATHS = @(
    'C:\Espressif\frameworks\esp-idf-v*',
    "$env:USERPROFILE\esp\esp-idf",
    'C:\esp\esp-idf'
)

# Find IDF source dir
$idfDir = $null
foreach ($pattern in $IDF_SEARCH_PATHS) {
    $resolved = Resolve-Path $pattern -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($resolved -and (Test-Path "$($resolved.Path)\export.bat")) {
        $idfDir = $resolved.Path
        break
    }
}

if (-not $idfDir) { exit 1 }

# Derive tools root: walk up two levels from IDF dir, fall back to known locations
$candidates = @(
    (Split-Path (Split-Path $idfDir)),
    'C:\Espressif',
    "$env:USERPROFILE\.espressif"
)
$toolsPath = $candidates | Where-Object { Test-Path (Join-Path $_ 'tools') } | Select-Object -First 1

# Find Python venv under tools root
$venv = $null
if ($toolsPath) {
    $envDir = Join-Path $toolsPath 'python_env'
    if (Test-Path $envDir) {
        $venv = Get-ChildItem $envDir -Directory |
            Where-Object { Test-Path (Join-Path $_.FullName 'Scripts\python.exe') } |
            Sort-Object Name -Descending |
            Select-Object -First 1 -ExpandProperty FullName
    }
}

# Write results as key=value for run.cmd to consume
$lines = @("_IDF_DIR=$idfDir")
if ($toolsPath) { $lines += "IDF_TOOLS_PATH=$toolsPath" }
if ($venv)      { $lines += "IDF_PYTHON_ENV_PATH=$venv" }

$lines | Set-Content $OutFile -Encoding ASCII
exit 0
