@echo off
:: scripts\run.cmd
:: Launches any script in this directory with a temporary PowerShell execution
:: policy bypass (Process scope only - no permanent system change).
::
:: First time setup:
::   scripts\run.cmd setup
::
:: Usage:
::   scripts\run.cmd build
::   scripts\run.cmd flash            [-Port COMx]
::   scripts\run.cmd monitor          [-Port COMx]
::   scripts\run.cmd flash_monitor    [-Port COMx]
::   scripts\run.cmd wsl_attach       [-BusId <id>]
::   scripts\run.cmd wsl_detach       [-BusId <id>]

setlocal EnableDelayedExpansion

if "%~1"=="" (
    echo.
    echo  IoTEdgeConnect firmware scripts
    echo  --------------------------------
    echo  First time?  scripts\run.cmd setup
    echo.
    echo  Usage: scripts\run.cmd ^<script^> [args]
    echo.
    echo  Scripts:
    echo    setup                          Install all dependencies
    echo    build                          Build firmware
    echo    flash            [-Port COMx]  Flash to ESP32
    echo    monitor          [-Port COMx]  Open serial monitor
    echo    flash_monitor    [-Port COMx]  Flash then monitor
    echo    wsl_attach       [-BusId ^<id^>] Forward ESP32 USB to WSL
    echo    wsl_detach       [-BusId ^<id^>] Return ESP32 USB to Windows
    echo.
    exit /b 0
)

set SCRIPT=%~dp0%~1.ps1

if not exist "%SCRIPT%" (
    echo ERROR: Unknown command "%~1". Run scripts\run.cmd with no arguments for help.
    exit /b 1
)

:: Strip script name from args
set ARGS=
for /f "tokens=1,*" %%a in ("%*") do set ARGS=%%b

:: -----------------------------------------------------------------------
:: wsl_attach needs admin - relaunch elevated if not already
:: -----------------------------------------------------------------------
if /i "%~1"=="wsl_attach" (
    net session >nul 2>&1
    if errorlevel 1 (
        echo Relaunching as Administrator for wsl_attach...
        powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Start-Process cmd.exe -ArgumentList '/k cd /d \"%CD%\" && powershell.exe -NoProfile -ExecutionPolicy Bypass -File \"%SCRIPT%\" %ARGS%' -Verb RunAs"
        exit /b
    )
    goto :run
)

:: -----------------------------------------------------------------------
:: setup does not need IDF activated
:: -----------------------------------------------------------------------
if /i "%~1"=="setup" goto :run

:: -----------------------------------------------------------------------
:: Activate ESP-IDF if not already active.
:: Delegate path detection to _idf_env.ps1 to avoid cmd quoting issues.
:: -----------------------------------------------------------------------
if "%IDF_PATH%"=="" (
    set _ENV_FILE=%TEMP%\idf_env_vars.tmp
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0_idf_env.ps1" "!_ENV_FILE!"
    if errorlevel 1 (
        echo.
        echo ERROR: ESP-IDF is not installed or not activated.
        echo        Run setup first:  scripts\run.cmd setup
        echo.
        exit /b 1
    )
    for /f "usebackq tokens=1,* delims==" %%a in ("!_ENV_FILE!") do set %%a=%%b
    del "!_ENV_FILE!" >nul 2>&1
    echo Activating ESP-IDF from !_IDF_DIR!...
    call "!_IDF_DIR!\export.bat"
)

:run
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" %ARGS%
