# Architecture

## Overview

IoTEdgeConnect firmware is a minimal ESP-IDF application targeting the ESP32.
Phase 1 establishes the core structure: a FreeRTOS telemetry task that generates
simulated environmental data and emits it as JSON over the serial console.

The design deliberately separates concerns so that later phases can replace the
simulated data source with real hardware sensors without restructuring the application.

---

## Module Structure

```mermaid
graph TD
    A[app_main.cpp] -->|creates task| B[telemetry_task]
    B -->|calls| C[TelemetryGenerator]
    B -->|calls| D[telemetry_to_json]
    C -->|returns| E[Telemetry struct]
    D -->|takes| E
    D -->|returns| F[JSON string → serial]

    subgraph config
        G[device_config.h]
    end

    A -.->|reads| G
    B -.->|reads| G
    D -.->|reads| G
```

---

## FreeRTOS Task Flow

```mermaid
sequenceDiagram
    participant M as app_main
    participant T as telemetry_task
    participant G as TelemetryGenerator
    participant S as telemetry_to_json

    M->>M: Log startup info
    M->>T: xTaskCreate()
    loop Every TELEMETRY_INTERVAL_MS
        T->>T: vTaskDelayUntil()
        T->>G: next()
        G-->>T: Telemetry sample
        T->>S: telemetry_to_json(sample)
        S-->>T: JSON string
        T->>T: printf + free
    end
```

---

## Data Flow

```mermaid
flowchart LR
    RNG[esp_random] --> GEN[TelemetryGenerator\nstateful drift]
    TIMER[esp_timer_get_time] --> GEN
    GEN --> STRUCT[Telemetry struct\nsequence · uptime_ms\ntemperature_c · humidity_pct]
    STRUCT --> SER[telemetry_to_json\ncJSON]
    CFG[device_config.h\ndevice_id · schema_version] --> SER
    SER --> UART[Serial console\ncompact JSON]
```

---

## Key Design Decisions

| Decision | Rationale |
|---|---|
| `Telemetry` struct is transport-agnostic | Allows the same struct to be used with MQTT, HTTP or any future transport without modification |
| `telemetry_to_json` is a free function, not a method | Keeps serialisation separate from data; the struct has no knowledge of JSON |
| `TelemetryGenerator` holds state | Produces realistic drift rather than uncorrelated random values each sample |
| `vTaskDelayUntil` rather than `vTaskDelay` | Keeps the reporting interval stable regardless of processing time |
| cJSON via ESP-IDF `json` component | Supported, well-tested, already present in the IDF; no extra dependency |
| Single FreeRTOS task | Sufficient for Phase 1; avoids premature complexity |

---

## File Layout

```
firmware/
├── .amazonq/rules/project.md   ← workspace rules
├── .github/workflows/ci.yml    ← CI build
├── CMakeLists.txt              ← top-level ESP-IDF project
├── sdkconfig.defaults          ← default SDK options
├── main/
│   ├── CMakeLists.txt
│   ├── app_main.cpp            ← entry point, task creation
│   ├── config/
│   │   └── device_config.h     ← device ID, version, interval
│   └── telemetry/
│       ├── telemetry.h         ← Telemetry struct + serialisation declaration
│       ├── telemetry.cpp       ← JSON serialisation (cJSON)
│       ├── telemetry_generator.h
│       └── telemetry_generator.cpp  ← stateful simulated data
└── tests/
    └── test_telemetry.cpp      ← host-side unit tests
```
