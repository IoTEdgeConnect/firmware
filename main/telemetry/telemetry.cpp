#include "telemetry.h"
#include "config/device_config.h"

#include <cmath>
#include <cstdlib>
#include <cstring>

#include "cJSON.h"
#include "esp_log.h"

static constexpr const char* TAG = "TELEMETRY";

// Round a float to a given number of decimal places
static inline double round_dp(float value, float factor)
{
    return static_cast<double>(roundf(value * factor) / factor);
}

char* telemetry_to_json(const Telemetry& t)
{
    cJSON* root = cJSON_CreateObject();
    if (!root) {
        ESP_LOGE(TAG, "Failed to allocate JSON root object");
        return nullptr;
    }

    cJSON_AddNumberToObject(root, "schema_version", 1);
    cJSON_AddStringToObject(root, "device_id",      config::DEVICE_ID);
    cJSON_AddNumberToObject(root, "sequence",        static_cast<double>(t.sequence));
    cJSON_AddNumberToObject(root, "uptime_ms",       static_cast<double>(t.uptime_ms));
    cJSON_AddBoolToObject  (root, "simulated",       true);

    cJSON* m = cJSON_AddObjectToObject(root, "measurements");
    if (!m) {
        ESP_LOGE(TAG, "Failed to allocate measurements object");
        cJSON_Delete(root);
        return nullptr;
    }

    // Environmental — 1 d.p.
    cJSON_AddNumberToObject(m, "temperature_c", round_dp(t.temperature_c, 10.0f));
    cJSON_AddNumberToObject(m, "humidity_pct",  round_dp(t.humidity_pct,  10.0f));
    cJSON_AddNumberToObject(m, "pressure_hpa",  round_dp(t.pressure_hpa,  100.0f)); // 2 d.p.
    cJSON_AddNumberToObject(m, "co2_ppm",       round_dp(t.co2_ppm,       1.0f));   // 0 d.p.
    cJSON_AddNumberToObject(m, "light_lux",     round_dp(t.light_lux,     10.0f));  // 1 d.p.
    cJSON_AddNumberToObject(m, "voc_index",     round_dp(t.voc_index,     1.0f));   // 0 d.p.

    // Device health
    cJSON_AddNumberToObject(m, "battery_mv",    round_dp(t.battery_mv,    1.0f));   // 0 d.p.
    cJSON_AddNumberToObject(m, "rssi_dbm",      static_cast<double>(t.rssi_dbm));

    char* json = cJSON_PrintUnformatted(root);
    cJSON_Delete(root);

    if (!json) {
        ESP_LOGE(TAG, "Failed to serialise telemetry to JSON");
    }

    return json; // caller must free()
}
