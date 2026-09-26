#include "telemetry_generator.h"

#include <algorithm>
#include <cmath>

#include "esp_random.h"
#include "esp_timer.h"

// ---------------------------------------------------------------------------
// Simulation parameters
// ---------------------------------------------------------------------------

// Temperature (°C)
static constexpr float TEMP_INITIAL   = 22.0f;
static constexpr float TEMP_MIN       = 15.0f;
static constexpr float TEMP_MAX       = 35.0f;
static constexpr float TEMP_DELTA_MIN = 0.1f;
static constexpr float TEMP_DELTA_MAX = 0.3f;

// Relative humidity (%)
static constexpr float HUM_INITIAL    = 50.0f;
static constexpr float HUM_MIN        = 20.0f;
static constexpr float HUM_MAX        = 80.0f;
static constexpr float HUM_DELTA_MIN  = 0.2f;
static constexpr float HUM_DELTA_MAX  = 1.0f;

// Barometric pressure (hPa)
static constexpr float PRES_INITIAL   = 1013.25f;
static constexpr float PRES_MIN       = 970.0f;
static constexpr float PRES_MAX       = 1050.0f;
static constexpr float PRES_DELTA_MIN = 0.05f;
static constexpr float PRES_DELTA_MAX = 0.2f;

// CO₂ concentration (ppm)
static constexpr float CO2_INITIAL    = 400.0f;
static constexpr float CO2_MIN        = 350.0f;
static constexpr float CO2_MAX        = 2000.0f;
static constexpr float CO2_DELTA_MIN  = 1.0f;
static constexpr float CO2_DELTA_MAX  = 8.0f;

// Ambient light (lux)
static constexpr float LIGHT_INITIAL   = 500.0f;
static constexpr float LIGHT_MIN       = 0.0f;
static constexpr float LIGHT_MAX       = 10000.0f;
static constexpr float LIGHT_DELTA_MIN = 5.0f;
static constexpr float LIGHT_DELTA_MAX = 30.0f;

// VOC index (1–500, dimensionless Sensirion scale)
static constexpr float VOC_INITIAL    = 100.0f;
static constexpr float VOC_MIN        = 1.0f;
static constexpr float VOC_MAX        = 500.0f;
static constexpr float VOC_DELTA_MIN  = 1.0f;
static constexpr float VOC_DELTA_MAX  = 5.0f;

// Battery voltage (mV) — slow monotonic drain with small noise
static constexpr float BAT_INITIAL    = 4200.0f;
static constexpr float BAT_MIN        = 3000.0f;
static constexpr float BAT_MAX        = 4200.0f;
static constexpr float BAT_DRAIN      = 0.5f;   // mV lost per sample (deterministic)
static constexpr float BAT_NOISE_MIN  = 0.0f;
static constexpr float BAT_NOISE_MAX  = 1.0f;

// RSSI (dBm) — negative, typical Wi-Fi range
static constexpr float RSSI_INITIAL   = -65.0f;
static constexpr float RSSI_MIN       = -90.0f;
static constexpr float RSSI_MAX       = -30.0f;
static constexpr float RSSI_DELTA_MIN = 0.5f;
static constexpr float RSSI_DELTA_MAX = 2.0f;

// ---------------------------------------------------------------------------

TelemetryGenerator::TelemetryGenerator()
    : sequence_(0),
      temperature_c_(TEMP_INITIAL),
      humidity_pct_(HUM_INITIAL),
      pressure_hpa_(PRES_INITIAL),
      co2_ppm_(CO2_INITIAL),
      light_lux_(LIGHT_INITIAL),
      voc_index_(VOC_INITIAL),
      battery_mv_(BAT_INITIAL),
      rssi_dbm_(RSSI_INITIAL)
{}

float TelemetryGenerator::random_delta(float min_abs, float max_abs)
{
    float normalised = static_cast<float>(esp_random()) / static_cast<float>(UINT32_MAX);
    float magnitude  = min_abs + normalised * (max_abs - min_abs);
    return (esp_random() & 1u) ? magnitude : -magnitude;
}

Telemetry TelemetryGenerator::next()
{
    ++sequence_;

    temperature_c_ += random_delta(TEMP_DELTA_MIN, TEMP_DELTA_MAX);
    temperature_c_  = std::clamp(temperature_c_, TEMP_MIN, TEMP_MAX);

    humidity_pct_  += random_delta(HUM_DELTA_MIN, HUM_DELTA_MAX);
    humidity_pct_   = std::clamp(humidity_pct_, HUM_MIN, HUM_MAX);

    pressure_hpa_  += random_delta(PRES_DELTA_MIN, PRES_DELTA_MAX);
    pressure_hpa_   = std::clamp(pressure_hpa_, PRES_MIN, PRES_MAX);

    co2_ppm_       += random_delta(CO2_DELTA_MIN, CO2_DELTA_MAX);
    co2_ppm_        = std::clamp(co2_ppm_, CO2_MIN, CO2_MAX);

    light_lux_     += random_delta(LIGHT_DELTA_MIN, LIGHT_DELTA_MAX);
    light_lux_      = std::clamp(light_lux_, LIGHT_MIN, LIGHT_MAX);

    voc_index_     += random_delta(VOC_DELTA_MIN, VOC_DELTA_MAX);
    voc_index_      = std::clamp(voc_index_, VOC_MIN, VOC_MAX);

    // Battery drains monotonically with small noise
    battery_mv_    -= BAT_DRAIN;
    battery_mv_    += random_delta(BAT_NOISE_MIN, BAT_NOISE_MAX);
    battery_mv_     = std::clamp(battery_mv_, BAT_MIN, BAT_MAX);

    rssi_dbm_      += random_delta(RSSI_DELTA_MIN, RSSI_DELTA_MAX);
    rssi_dbm_       = std::clamp(rssi_dbm_, RSSI_MIN, RSSI_MAX);

    return Telemetry{
        .sequence      = sequence_,
        .uptime_ms     = esp_timer_get_time() / 1000LL,
        .temperature_c = temperature_c_,
        .humidity_pct  = humidity_pct_,
        .pressure_hpa  = pressure_hpa_,
        .co2_ppm       = co2_ppm_,
        .light_lux     = light_lux_,
        .voc_index     = voc_index_,
        .battery_mv    = battery_mv_,
        .rssi_dbm      = static_cast<int32_t>(rssi_dbm_),
    };
}
