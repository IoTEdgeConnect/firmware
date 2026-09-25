# Building, Flashing & Monitoring

## Prerequisites

| Tool | Version | Notes |
|---|---|---|
| ESP-IDF | v5.2 or later | [Installation guide](https://docs.espressif.com/projects/esp-idf/en/latest/esp32/get-started/) |
| CMake | ≥ 3.16 | Bundled with ESP-IDF |
| Python | ≥ 3.8 | Required by `idf.py` |
| USB driver | — | CP210x or CH340 depending on your dev board |

Ensure the IDF environment is activated before running any `idf.py` command:

```bash
# Linux / macOS
. $IDF_PATH/export.sh

# Windows (PowerShell)
$IDF_PATH\export.ps1
```

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

## Configuration

Default SDK options are in [`sdkconfig.defaults`](../sdkconfig.defaults).
The generated `sdkconfig` file is excluded from version control.

To open the interactive configuration menu:

```bash
idf.py menuconfig
```
