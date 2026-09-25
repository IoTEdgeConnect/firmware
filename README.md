# IoTEdgeConnect Firmware

ESP32 firmware for the IoTEdgeConnect edge device platform.

This repository contains the firmware component of IoTEdgeConnect — an incremental,
production-oriented IoT platform built on ESP-IDF and AWS IoT Core.
Phase 1 establishes the core application structure and produces observable
simulated telemetry over the serial console.

---

## Current Functionality (Phase 1)

- ESP-IDF application targeting the ESP32
- Simulated environmental telemetry (temperature & humidity) with realistic drift
- FreeRTOS telemetry task using `vTaskDelayUntil` for stable 5-second intervals
- JSON serialisation via cJSON
- Serial console output of compact JSON telemetry
- Startup logging of device ID and firmware version

---

## Quick Start

```bash
# Activate the ESP-IDF environment first
. $IDF_PATH/export.sh          # Linux / macOS
# $IDF_PATH\export.ps1         # Windows PowerShell

idf.py set-target esp32
idf.py build
idf.py -p <PORT> flash monitor
```

Replace `<PORT>` with your serial port (e.g. `COM3`, `/dev/ttyUSB0`).

---

## Example Output

```
I (...) IOTEDGE: IoTEdgeConnect firmware starting
I (...) IOTEDGE: Device: esp32-dev-001
I (...) IOTEDGE: Firmware: 0.1.0
I (...) IOTEDGE: Telemetry interval: 5000 ms

{"schema_version":1,"device_id":"esp32-dev-001","sequence":1,"uptime_ms":5032,"simulated":true,"measurements":{"temperature_c":22.1,"humidity_pct":50.4}}
{"schema_version":1,"device_id":"esp32-dev-001","sequence":2,"uptime_ms":10032,"simulated":true,"measurements":{"temperature_c":22.2,"humidity_pct":50.1}}
{"schema_version":1,"device_id":"esp32-dev-001","sequence":3,"uptime_ms":15032,"simulated":true,"measurements":{"temperature_c":22.3,"humidity_pct":50.6}}
```

---

## System Overview

```mermaid
flowchart TD
    A[app_main] -->|xTaskCreate| B[telemetry_task]
    B -->|every 5 s| C[TelemetryGenerator]
    C -->|Telemetry struct| D[telemetry_to_json]
    D -->|JSON string| E[Serial console]
```

---

## Documentation

| Document | Description |
|---|---|
| [Architecture](docs/architecture.md) | Module structure, data flow and design decisions |
| [Building, Flashing & Monitoring](docs/building.md) | Full build and flash instructions |
| [Testing](docs/testing.md) | Host-side unit tests and coverage |

---

## Current Limitations

Phase 1 does not provide:

- Wi-Fi or network connectivity
- NTP or wall-clock timestamps
- MQTT or AWS IoT Core connectivity
- Physical sensor support
- Over-the-air (OTA) updates
- Secure boot
- Automated device provisioning
- Persistent sequence numbers across reboots

---

## Roadmap

**Phase 2 — Network & Time**

Connect the device to Wi-Fi, obtain network information and synchronise
wall-clock time using NTP.

---

## Requirements

- [ESP-IDF](https://docs.espressif.com/projects/esp-idf/en/latest/esp32/get-started/) v5.2 or later
- Standard ESP32 development board (no external peripherals required)
- USB cable
