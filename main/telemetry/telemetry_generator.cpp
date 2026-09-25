#include "telemetry_generator.h"

#include <algorithm>
#include <cmath>

#include "esp_random.h"
#include "esp_timer.h"

// Simulation parameters
static constexpr float TEMP_INITIAL   = 22.0f;
static constexpr float TEMP_MIN       = 15.0f;
static constexpr float TEMP_MAX       = 35.0f;
static constexpr float TEMP_DELTA_MIN = 0.1f;
static constexpr float TEMP_DELTA_MAX = 0.3f;

static constexpr float HUM_INITIAL    = 50.0f;
static constexpr float HUM_MIN        = 20.0f;
static constexpr float HUM_MAX        = 80.0f;
static constexpr float HUM_DELTA_MIN  = 0.2f;
static constexpr float HUM_DELTA_MAX  = 1.0f;

TelemetryGenerator::TelemetryGenerator()
    : sequence_(0), temperature_c_(TEMP_INITIAL), humidity_pct_(HUM_INITIAL)
{}

float TelemetryGenerator::random_delta(float min_abs, float max_abs)
{
    // esp_random() returns a uniform 32-bit value
    float normalised = static_cast<float>(esp_random()) / static_cast<float>(UINT32_MAX);
    float magnitude  = min_abs + normalised * (max_abs - min_abs);
    // Randomly negate to allow drift in either direction
    return (esp_random() & 1u) ? magnitude : -magnitude;
}

Telemetry TelemetryGenerator::next()
{
    ++sequence_;

    temperature_c_ += random_delta(TEMP_DELTA_MIN, TEMP_DELTA_MAX);
    temperature_c_  = std::clamp(temperature_c_, TEMP_MIN, TEMP_MAX);

    humidity_pct_  += random_delta(HUM_DELTA_MIN, HUM_DELTA_MAX);
    humidity_pct_   = std::clamp(humidity_pct_, HUM_MIN, HUM_MAX);

    return Telemetry{
        .sequence      = sequence_,
        .uptime_ms     = esp_timer_get_time() / 1000LL,
        .temperature_c = temperature_c_,
        .humidity_pct  = humidity_pct_,
    };
}
