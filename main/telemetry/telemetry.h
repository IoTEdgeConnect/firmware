#pragma once

#include <cstdint>

struct Telemetry {
    uint64_t sequence;
    int64_t  uptime_ms;
    float    temperature_c;
    float    humidity_pct;
};

// Serialise a Telemetry sample to a compact JSON string.
// Returns a heap-allocated string; caller must free().
// Returns nullptr on allocation failure.
char* telemetry_to_json(const Telemetry& t);
