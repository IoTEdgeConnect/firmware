# scripts/test.ps1
# Build and run host-side unit tests for IoTEdgeConnect firmware.
# Does not require an ESP32 or ESP-IDF to be activated.
#
# Usage:
#   scripts\run.cmd test

[CmdletBinding()]
param()

$root    = (Get-Item "$PSScriptRoot\..").FullName
$testSrc = Join-Path $root 'tests\test_telemetry.cpp'
$testBin = Join-Path $root 'tests\test_telemetry.exe'

# Ensure MSYS2 MinGW is on PATH for this session even if setup was just run
$msys2Bin = 'C:\msys64\mingw64\bin'
if ((Test-Path $msys2Bin) -and ($env:PATH -notlike "*$msys2Bin*")) {
    $env:PATH = "$msys2Bin;$env:PATH"
}

function Find-CJson {
    $candidates = @(
        'C:\Espressif\frameworks\esp-idf-v*\components\json\cJSON\cJSON.c',
        "$env:USERPROFILE\esp\esp-idf\components\json\cJSON\cJSON.c",
        'C:\esp\esp-idf\components\json\cJSON\cJSON.c'
    )
    foreach ($p in $candidates) {
        $r = Resolve-Path $p -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($r) { return [string]$r.Path }
    }
    return $null
}

Write-Host ""
Write-Host "==> Running host-side unit tests" -ForegroundColor Cyan

if (-not (Get-Command g++ -ErrorAction SilentlyContinue)) {
    Write-Host "    !! g++ not found. Run: scripts\run.cmd setup" -ForegroundColor Yellow
    exit 1
}
Write-Host "    Compiler: $(Get-Command g++ | Select-Object -ExpandProperty Source)" -ForegroundColor DarkGray

$cjson = Find-CJson
if (-not $cjson) {
    Write-Host "    !! cJSON.c not found. Run: scripts\run.cmd setup" -ForegroundColor Yellow
    exit 1
}
Write-Host "    cJSON:    $cjson" -ForegroundColor DarkGray
$cjsonDir = Split-Path $cjson

Write-Host "    Compiling..." -ForegroundColor DarkGray

# test_telemetry.cpp includes the .cpp files directly so only pass cJSON and the test file
g++ -std=c++17 "-I$root\main" "-I$root\tests\stubs" "-I$cjsonDir" $cjson $testSrc -o $testBin

if ($LASTEXITCODE -ne 0) {
    Write-Host "    FAIL: Compilation failed." -ForegroundColor Red
    exit 1
}

Write-Host "    Running..." -ForegroundColor DarkGray
& $testBin
$result = $LASTEXITCODE
Remove-Item $testBin -ErrorAction SilentlyContinue

if ($result -eq 0) {
    Write-Host "    PASS" -ForegroundColor Green
} else {
    Write-Host "    FAIL" -ForegroundColor Red
    exit 1
}
