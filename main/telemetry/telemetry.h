#pragma once

#include <cstdint>

struct Telemetry {
    uint64_t sequence;
    int64_t  uptime_ms;

    // Environmental
    float    temperature_c;
    float    humidity_pct;
    float    pressure_hpa;
    float    co2_ppm;
    float    light_lux;
    float    voc_index;

    // Device health
    float    battery_mv;
    int32_t  rssi_dbm;
};

// Serialise a Telemetry sample to a compact JSON string.
// Returns a heap-allocated string; caller must free().
// Returns nullptr on allocation failure.
char* telemetry_to_json(const Telemetry& t);
