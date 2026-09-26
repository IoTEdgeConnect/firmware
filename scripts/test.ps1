# scripts/test.ps1
# Build and run host-side unit tests for IoTEdgeConnect firmware.
# Does not require an ESP32 or ESP-IDF to be activated.
#
# Requires a host C++ compiler:
#   - Windows: MSVC (cl.exe) via Visual Studio, or g++ via MSYS2/MinGW
#
# Usage:
#   scripts\run.cmd test

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$root     = "$PSScriptRoot\.."
$testSrc  = "$root\tests\test_telemetry.cpp"
$testBin  = "$root\tests\test_telemetry.exe"

function Find-Compiler {
    # Check PATH first
    if (Get-Command g++ -ErrorAction SilentlyContinue) {
        return [PSCustomObject]@{ Exe = (Get-Command g++).Source; Type = 'gcc' }
    }
    if (Get-Command cl -ErrorAction SilentlyContinue) {
        return [PSCustomObject]@{ Exe = (Get-Command cl).Source; Type = 'msvc' }
    }
    # Fall back to known MSYS2 install location even if not on PATH yet
    $msys2Gpp = 'C:\msys64\mingw64\bin\g++.exe'
    if (Test-Path $msys2Gpp) {
        return [PSCustomObject]@{ Exe = $msys2Gpp; Type = 'gcc' }
    }
    return $null
}

function Find-CJson {
    # Look for cJSON.c in common ESP-IDF install locations
    $candidates = @(
        'C:\Espressif\frameworks\esp-idf-v*\components\json\cJSON\cJSON.c',
        "$env:USERPROFILE\esp\esp-idf\components\json\cJSON\cJSON.c",
        'C:\esp\esp-idf\components\json\cJSON\cJSON.c'
    )
    foreach ($pattern in $candidates) {
        $resolved = Resolve-Path $pattern -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($resolved) { return $resolved.Path }
    }
    return $null
}

Write-Host ""
Write-Host "==> Running host-side unit tests" -ForegroundColor Cyan

$compiler = Find-Compiler
if (-not $compiler) {
    Write-Host "    !! No C++ compiler found." -ForegroundColor Yellow
    Write-Host "       Install g++ via MSYS2 (pacman -S mingw-w64-x86_64-gcc)" -ForegroundColor Yellow
    Write-Host "       or Visual Studio Build Tools." -ForegroundColor Yellow
    exit 1
}
Write-Host "    Compiler: $($compiler.Exe)" -ForegroundColor DarkGray

$cjson = Find-CJson
if (-not $cjson) {
    Write-Host "    !! cJSON.c not found. Run 'scripts\run.cmd setup' first." -ForegroundColor Yellow
    exit 1
}
$cjsonDir = Split-Path $cjson
Write-Host "    cJSON:    $cjson" -ForegroundColor DarkGray

# Build
Write-Host "    Compiling..." -ForegroundColor DarkGray

if ($compiler.Type -eq 'gcc') {
    $buildArgs = @(
        '-std=c++17',
        "-I$root\main",
        "-I$cjsonDir",
        "$root\main\telemetry\telemetry_generator.cpp",
        "$root\main\telemetry\telemetry.cpp",
        $cjson,
        $testSrc,
        "-o$testBin"
    )
    & $compiler.Exe @buildArgs
} else {
    # MSVC
    $buildArgs = @(
        '/std:c++17',
        '/EHsc',
        "/I$root\main",
        "/I$cjsonDir",
        "$root\main\telemetry\telemetry_generator.cpp",
        "$root\main\telemetry\telemetry.cpp",
        $cjson,
        $testSrc,
        "/Fe$testBin"
    )
    & cl @buildArgs
}

if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-Host "    FAIL: Compilation failed." -ForegroundColor Red
    exit 1
}

# Run
Write-Host "    Running tests..." -ForegroundColor DarkGray
& $testBin
$result = $LASTEXITCODE
Remove-Item $testBin -ErrorAction SilentlyContinue

if ($result -eq 0) {
    Write-Host "    PASS" -ForegroundColor Green
} else {
    Write-Host "    FAIL: Tests failed." -ForegroundColor Red
    exit 1
}
