#pragma once

#include <cstdint>

struct Telemetry {
    uint64_t sequence;
    int64_t  uptime_ms;

    // Wall-clock time — ISO 8601 UTC ("YYYY-MM-DDTHH:MM:SSZ").
    // Empty string when SNTP has not yet synchronised.
    char     timestamp_utc[21];

    // Network status
    bool     net_connected;
    bool     net_internet;  // true if DNS reachability check passed
    int8_t   net_rssi_dbm;  // valid only when net_connected == true
    char     net_ip_addr[16]; // "xxx.xxx.xxx.xxx" + NUL; empty when disconnected

    // Environmental
    float    temperature_c;
    float    humidity_pct;
    float    pressure_hpa;
    float    co2_ppm;
    float    light_lux;
    float    voc_index;

    // Device health
    float    battery_mv;
};

// Serialise a Telemetry sample to a compact JSON string.
// Returns a heap-allocated string; caller must free().
// Returns nullptr on allocation failure.
char* telemetry_to_json(const Telemetry& t);
