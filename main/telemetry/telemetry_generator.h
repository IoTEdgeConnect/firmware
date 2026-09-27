#pragma once

#include "telemetry.h"

class TelemetryGenerator {
public:
    TelemetryGenerator();
    Telemetry next();

private:
    uint64_t sequence_;

    float temperature_c_;
    float humidity_pct_;
    float pressure_hpa_;
    float co2_ppm_;
    float light_lux_;
    float voc_index_;
    float battery_mv_;

    float random_delta(float min_abs, float max_abs);
};
