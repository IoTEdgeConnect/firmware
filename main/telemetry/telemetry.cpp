#include "telemetry.h"
#include "config/device_config.h"

#include <cstdlib>
#include <cstring>

#include "cJSON.h"
#include "esp_log.h"

static constexpr const char* TAG = "TELEMETRY";

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

    cJSON* measurements = cJSON_AddObjectToObject(root, "measurements");
    if (!measurements) {
        ESP_LOGE(TAG, "Failed to allocate measurements object");
        cJSON_Delete(root);
        return nullptr;
    }

    cJSON_AddNumberToObject(measurements, "temperature_c", static_cast<double>(t.temperature_c));
    cJSON_AddNumberToObject(measurements, "humidity_pct",  static_cast<double>(t.humidity_pct));

    char* json = cJSON_PrintUnformatted(root);
    cJSON_Delete(root);

    if (!json) {
        ESP_LOGE(TAG, "Failed to serialise telemetry to JSON");
    }

    return json; // caller must free()
}
