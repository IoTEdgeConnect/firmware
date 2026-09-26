# Building, Flashing & Monitoring

## Prerequisites

| Tool | Version | Notes |
|---|---|---|
| Git | any | [git-scm.com](https://git-scm.com) |
| Python | ≥ 3.8 | [python.org](https://python.org) |
| ESP-IDF | v5.4 | Installed by `setup` script or manually |
| CMake + Ninja | — | Bundled with ESP-IDF installer |
| usbipd-win | ≥ 4.0 | Windows only, for WSL USB forwarding |

### First-time setup (Windows)

Run once after cloning. Installs ESP-IDF and usbipd-win automatically:

```cmd
scripts\run.cmd setup
```

This downloads the official ESP-IDF Windows installer (~5 min), installs the
toolchain, and installs usbipd-win via winget.

### Manual activation

After setup, activate ESP-IDF in each new terminal before building:

```powershell
# PowerShell
. $env:USERPROFILE\esp\esp-idf\export.ps1

# cmd.exe
%USERPROFILE%\esp\esp-idf\export.bat
```

The `run.cmd` script will attempt to activate IDF automatically if it finds
it in the default location but `IDF_PATH` is not set.

---

## Build Workflow

```mermaid
flowchart LR
    A[Set target] --> B[Configure]
    B --> C[Build]
    C --> D[Flash]
    D --> E[Monitor]
```

---

## Scripts

Convenience scripts in `scripts/` wrap the commands below and auto-detect the serial port.

| Script | Platform | Action |
|---|---|---|
| `scripts/build.ps1` | Windows PowerShell | Build |
| `scripts/flash.ps1` | Windows PowerShell | Flash |
| `scripts/monitor.ps1` | Windows PowerShell | Monitor |
| `scripts/flash_monitor.ps1` | Windows PowerShell | Flash + monitor |
| `scripts/wsl_attach.ps1` | Windows PowerShell | Forward ESP32 USB to WSL |
| `scripts/wsl_detach.ps1` | Windows PowerShell | Return ESP32 USB to Windows |

See [WSL usage](wsl.md) for the full USB forwarding workflow.

---

## Commands

### Set target

```bash
idf.py set-target esp32
```

Only required once per checkout, or after clearing the build directory.

### Build

```bash
idf.py build
```

### Flash

```bash
idf.py -p <PORT> flash
```

Replace `<PORT>` with your serial port, for example:

- Windows: `COM3`
- Linux: `/dev/ttyUSB0`
- macOS: `/dev/cu.usbserial-0001`

### Monitor

```bash
idf.py -p <PORT> monitor
```

Press `Ctrl+]` to exit the monitor.

### Flash and monitor in one step

```bash
idf.py -p <PORT> flash monitor
```

---

## Cleaning

```bash
idf.py fullclean
```

This removes the `build/` directory entirely. Re-run `set-target` afterwards.

---

## WSL

To flash and monitor from inside WSL, see [WSL usage](wsl.md).

---

## Configuration

Default SDK options are in [`sdkconfig.defaults`](../sdkconfig.defaults).
The generated `sdkconfig` file is excluded from version control.

To open the interactive configuration menu:

```bash
idf.py menuconfig
```
