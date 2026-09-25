#pragma once

#include "telemetry.h"

class TelemetryGenerator {
public:
    TelemetryGenerator();
    Telemetry next();

private:
    uint64_t sequence_;
    float    temperature_c_;
    float    humidity_pct_;

    float random_delta(float min_abs, float max_abs);
};
