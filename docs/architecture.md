# Architecture

## Overview

IoTEdgeConnect firmware is a minimal ESP-IDF application targeting the ESP32.
It is designed to grow incrementally — each phase adds a well-defined capability
without requiring the existing structure to be rewritten.

Phase 1 establishes the foundational layer: a FreeRTOS telemetry task that generates
simulated environmental data and emits it as JSON over the serial console. Every
subsequent phase builds on top of this layer rather than replacing it.

---

## Guiding Principles

The architecture is governed by three rules that apply across all phases:

1. **Separation of concerns** — data generation, serialisation, and transport are
   independent. Replacing one does not require touching the others.
2. **Transport agnosticism** — the `Telemetry` struct carries measurements only.
   It has no knowledge of JSON, MQTT, HTTP, or any other transport.
3. **Incremental extension** — new capabilities are added as new modules. Existing
   modules are not restructured to accommodate them.

---

## Current Module Structure (Phase 1)

```mermaid
graph TD
    subgraph entry [Entry Point]
        APP[app_main.cpp]
    end

    subgraph task [FreeRTOS Task]
        TASK[telemetry_task]
    end

    subgraph generation [Telemetry Generation]
        GEN[TelemetryGenerator\ntelemetry_generator.cpp]
        STRUCT[Telemetry struct\ntelemetry.h]
    end

    subgraph serialisation [Serialisation]
        SER[telemetry_to_json\ntelemetry.cpp]
        CJSON[cJSON\nESP-IDF component]
    end

    subgraph config [Configuration]
        CFG[device_config.h\nDEVICE_ID · VERSION · INTERVAL]
    end

    subgraph output [Output]
        UART[Serial console\nprintf]
    end

    APP -->|xTaskCreate| TASK
    TASK -->|next| GEN
    GEN -->|returns| STRUCT
    TASK -->|telemetry_to_json| SER
    STRUCT -->|passed to| SER
    SER -->|uses| CJSON
    SER -->|returns char star| TASK
    TASK -->|printf + free| UART

    APP -.->|reads| CFG
    TASK -.->|reads| CFG
    SER -.->|reads| CFG
```

---

## File Layout

```
firmware/
├── CMakeLists.txt                  Top-level ESP-IDF project
├── sdkconfig.defaults              Default SDK configuration
│
├── main/
│   ├── CMakeLists.txt              Component registration
│   ├── app_main.cpp                Entry point; creates telemetry task
│   │
│   ├── config/
│   │   └── device_config.h         Single source of truth for device identity,
│   │                               firmware version and telemetry interval
│   │
│   └── telemetry/
│       ├── telemetry.h             Telemetry struct + telemetry_to_json declaration
│       ├── telemetry.cpp           JSON serialisation via cJSON
│       ├── telemetry_generator.h   TelemetryGenerator class declaration
│       └── telemetry_generator.cpp Stateful simulated data generation
│
├── tests/
│   ├── stubs/                      Host-side ESP-IDF header stubs
│   │   ├── esp_log.h               No-op logging macros
│   │   ├── esp_random.h            Declares esp_random()
│   │   └── esp_timer.h             Declares esp_timer_get_time()
│   └── test_telemetry.cpp          Host-side unit tests (1 014 assertions)
│
├── scripts/                        Developer convenience scripts
│   └── ...                         See docs/scripts.md
│
└── .github/workflows/ci.yml        CI: host tests + firmware build
```

---

## FreeRTOS Task Flow

```mermaid
sequenceDiagram
    participant M as app_main
    participant T as telemetry_task
    participant G as TelemetryGenerator
    participant S as telemetry_to_json
    participant C as Serial console

    M->>M: Log startup info (device ID, version, interval)
    M->>T: xTaskCreate(telemetry_task, stack=4096, priority=5)

    loop Every TELEMETRY_INTERVAL_MS (5 000 ms)
        T->>T: vTaskDelayUntil() — stable interval regardless of processing time
        T->>G: next()
        G->>G: increment sequence
        G->>G: apply random delta + clamp
        G->>G: read esp_timer_get_time()
        G-->>T: Telemetry { sequence, uptime_ms, temperature_c, humidity_pct }
        T->>S: telemetry_to_json(sample)
        S->>S: cJSON_CreateObject()
        S->>S: add fields + measurements sub-object
        S->>S: cJSON_PrintUnformatted()
        S->>S: cJSON_Delete()
        S-->>T: heap-allocated JSON string
        T->>C: printf("%s\n", json)
        T->>T: free(json)
    end
```

---

## Data Flow

```mermaid
flowchart LR
    RNG([esp_random\nHW RNG]) --> DELTA[random_delta\nmin/max magnitude\nrandom sign]
    TIMER([esp_timer_get_time\nmonotonic clock]) --> UPTIME[uptime_ms\ndivide by 1000]

    DELTA --> TEMP[temperature_c\n±0.1–0.3 °C per sample\nclamped 15–35 °C]
    DELTA --> HUM[humidity_pct\n±0.2–1.0 % per sample\nclamped 20–80 %]
    UPTIME --> STRUCT

    TEMP --> STRUCT[Telemetry struct]
    HUM --> STRUCT
    SEQ([sequence\nmonotonic uint64]) --> STRUCT

    STRUCT --> ROUND[roundf × 10 ÷ 10\n1 d.p. precision]
    ROUND --> CJSON[cJSON\nPrintUnformatted]
    CFG([device_config.h\nDEVICE_ID\nschema_version=1]) --> CJSON

    CJSON --> JSON[Compact JSON string\nheap-allocated]
    JSON --> UART([Serial console\nprintf + free])
```

---

## The Telemetry Struct

```cpp
struct Telemetry {
    uint64_t sequence;       // monotonically increasing, resets on reboot
    int64_t  uptime_ms;      // milliseconds since boot (esp_timer_get_time / 1000)
    float    temperature_c;  // degrees Celsius
    float    humidity_pct;   // relative humidity percentage
};
```

The struct is deliberately transport-agnostic. It carries measurements only —
no JSON keys, no MQTT topics, no AWS shadow fields. This means the same struct
can be passed to any serialiser or transport added in future phases.

---

## JSON Schema (v1)

```json
{
  "schema_version": 1,
  "device_id":      "esp32-dev-001",
  "sequence":       42,
  "uptime_ms":      210000,
  "simulated":      true,
  "measurements": {
    "temperature_c": 22.4,
    "humidity_pct":  53.1,
    "pressure_hpa":  1013.25,
    "co2_ppm":       412,
    "light_lux":     487.5,
    "voc_index":     103,
    "battery_mv":    4150,
    "rssi_dbm":      -67
  }
}
```

| Field | Type | Precision | Notes |
|---|---|---|---|
| `schema_version` | integer | — | Always `1` in Phase 1 |
| `device_id` | string | — | From `config::DEVICE_ID` |
| `sequence` | integer | — | Resets to 1 on reboot |
| `uptime_ms` | integer | — | Milliseconds since boot |
| `simulated` | boolean | — | `true` while using `TelemetryGenerator` |
| `temperature_c` | float | 1 d.p. | Degrees Celsius, range 15–35 |
| `humidity_pct` | float | 1 d.p. | Relative humidity %, range 20–80 |
| `pressure_hpa` | float | 2 d.p. | Barometric pressure hPa, range 970–1050 |
| `co2_ppm` | float | 0 d.p. | CO₂ concentration ppm, range 350–2000 |
| `light_lux` | float | 1 d.p. | Ambient light lux, range 0–10 000 |
| `voc_index` | float | 0 d.p. | VOC index (Sensirion scale 1–500) |
| `battery_mv` | float | 0 d.p. | Battery voltage mV, drains from 4200 to 3000 |
| `rssi_dbm` | integer | — | Simulated Wi-Fi RSSI dBm, range −90 to −30 |

---

## Key Design Decisions

| Decision | Rationale |
|---|---|
| `Telemetry` struct is transport-agnostic | The same struct is passed to any serialiser or transport without modification |
| `telemetry_to_json` is a free function | Serialisation is separate from data; the struct has no knowledge of JSON |
| `TelemetryGenerator` holds state | Produces realistic drift rather than uncorrelated random values each sample |
| `vTaskDelayUntil` not `vTaskDelay` | Keeps the reporting interval stable regardless of how long serialisation takes |
| cJSON via ESP-IDF `json` component | Already present in the IDF; no extra dependency to manage |
| Single FreeRTOS task | Sufficient for Phase 1; avoids premature complexity |
| `simulated: true` flag in JSON | Allows the platform to distinguish test data from real sensor data at ingestion |
| `schema_version: 1` in JSON | Enables schema evolution without breaking consumers |
| Float rounded to 1 d.p. | cJSON's default double formatting produces excessive precision (e.g. `21.830028533935547`) |

---

## Extensibility: How Future Phases Plug In

The architecture is designed so that each new phase adds a module rather than
modifying existing ones. The diagram below shows the intended growth path.

```mermaid
flowchart TD
    subgraph phase1 [Phase 1 — Current]
        GEN[TelemetryGenerator\nsimulated]
        STRUCT[Telemetry struct]
        SER[telemetry_to_json]
        UART[Serial console]
        GEN --> STRUCT --> SER --> UART
    end

    subgraph phase2 [Phase 2 — Network and Time]
        WIFI[Wi-Fi manager]
        NTP[NTP sync\nwall-clock timestamp]
        WIFI --> NTP
    end

    subgraph phase3 [Phase 3 — Cloud Connectivity]
        MQTT[MQTT client\nAWS IoT Core]
        SHADOW[Device shadow]
        MQTT --> SHADOW
    end

    subgraph phasefuture [Future Phases]
        SENSOR[Real sensor driver\nreplaces TelemetryGenerator]
        OTA[OTA update manager]
        PROV[Device provisioning]
    end

    phase1 -->|adds timestamp field| phase2
    phase2 -->|adds transport| phase3
    phase3 -->|replaces simulated source| phasefuture
```

**Phase 2** adds a Wi-Fi manager and NTP client. The `Telemetry` struct gains a
`timestamp_utc` field. `telemetry_to_json` is updated to include it. No other
existing code changes.

**Phase 3** adds an MQTT transport. `telemetry_to_json` output is published to
AWS IoT Core instead of (or in addition to) the serial console. The generator
and struct are unchanged.

**Future phases** replace `TelemetryGenerator` with a real sensor driver. Because
the generator and the task are separate, only the generator is swapped out. The
task, serialiser, and transport are unaffected.
