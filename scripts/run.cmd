@echo off
:: scripts\run.cmd
:: Launches any script in this directory with a temporary PowerShell execution
:: policy bypass (Process scope only — no permanent system change).
::
:: Usage:
::   scripts\run.cmd wsl_attach
::   scripts\run.cmd flash_monitor
::   scripts\run.cmd flash  -Port COM3
::
:: The .ps1 extension is added automatically.

if "%~1"=="" (
    echo Usage: scripts\run.cmd ^<script-name^> [args]
    echo.
    echo Available scripts:
    echo   build
    echo   flash            [-Port COMx]
    echo   monitor          [-Port COMx]
    echo   flash_monitor    [-Port COMx]
    echo   wsl_attach       [-Distro ^<name^>] [-BusId ^<id^>]
    echo   wsl_detach       [-BusId ^<id^>]
    exit /b 1
)

set SCRIPT=%~dp0%~1.ps1

if not exist "%SCRIPT%" (
    echo ERROR: Script not found: %SCRIPT%
    exit /b 1
)

:: Shift the script name out of the argument list so %* contains only the remainder.
set ARGS=%*
:: Remove the first token (script name) from ARGS
for /f "tokens=1,*" %%a in ("%ARGS%") do set ARGS=%%b

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" %ARGS%
