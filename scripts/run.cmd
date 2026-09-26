@echo off
:: scripts\run.cmd
:: Launches any script in this directory with a temporary PowerShell execution
:: policy bypass (Process scope only - no permanent system change).
::
:: First time setup:
::   scripts\run.cmd setup

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
    echo    test                           Run host-side unit tests
    echo    build                          Build firmware ^(runs tests first^)
    echo    flash            [-Port COMx]  Flash to ESP32
    echo    monitor          [-Port COMx]  Open serial monitor
    echo    flash_monitor    [-Port COMx]  Flash then monitor
    echo    wsl_attach       [-BusId ^<id^>] Forward ESP32 USB to WSL
    echo    wsl_detach       [-BusId ^<id^>] Return ESP32 USB to Windows
    echo.
    exit /b 0
)

:: Strip script name from args
set ARGS=
for /f "tokens=1,*" %%a in ("%*") do set ARGS=%%b

:: -----------------------------------------------------------------------
:: setup - no IDF needed, no pre-checks
:: -----------------------------------------------------------------------
if /i "%~1"=="setup" (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup.ps1" %ARGS%
    exit /b %ERRORLEVEL%
)

:: -----------------------------------------------------------------------
:: test - no IDF needed
:: -----------------------------------------------------------------------
if /i "%~1"=="test" (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0test.ps1" %ARGS%
    exit /b %ERRORLEVEL%
)

:: -----------------------------------------------------------------------
:: wsl_attach - needs admin
:: -----------------------------------------------------------------------
if /i "%~1"=="wsl_attach" (
    net session >nul 2>&1
    if errorlevel 1 (
        echo Relaunching as Administrator for wsl_attach...
        powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Start-Process cmd.exe -ArgumentList '/k cd /d \"%CD%\" && powershell.exe -NoProfile -ExecutionPolicy Bypass -File \"%~dp0wsl_attach.ps1\" %ARGS%' -Verb RunAs"
        exit /b
    )
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0wsl_attach.ps1" %ARGS%
    exit /b %ERRORLEVEL%
)

:: -----------------------------------------------------------------------
:: wsl_detach
:: -----------------------------------------------------------------------
if /i "%~1"=="wsl_detach" (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0wsl_detach.ps1" %ARGS%
    exit /b %ERRORLEVEL%
)

:: -----------------------------------------------------------------------
:: build / flash / monitor / flash_monitor - all need IDF activated
:: -----------------------------------------------------------------------
set SCRIPT=%~dp0%~1.ps1
if not exist "%SCRIPT%" (
    echo ERROR: Unknown command "%~1". Run scripts\run.cmd with no arguments for help.
    exit /b 1
)

:: build runs tests first
if /i "%~1"=="build" (
    echo Running tests before build...
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0test.ps1"
    if errorlevel 1 (
        echo.
        echo Tests failed - aborting build.
        exit /b 1
    )
)

:: Activate ESP-IDF if not already active
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

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" %ARGS%
