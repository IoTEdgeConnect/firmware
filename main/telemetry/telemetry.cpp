#include "telemetry.h"
#include "config/device_config.h"

#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>

#include "cJSON.h"
#include "esp_log.h"

static constexpr const char* TAG = "TELEMETRY";

// Format a float to a fixed number of decimal places into buf.
// Uses integer arithmetic to avoid double-precision drift.
// Assumes value * 10^dp fits within a 32-bit long (safe for all current
// sensor ranges: max is light_lux 10000 * 10^1 = 100000 < INT32_MAX).
static void fmt_dp(char* buf, size_t len, float value, int dp)
{
    int factor = 1;
    for (int i = 0; i < dp; ++i) factor *= 10;
    long rounded = static_cast<long>(roundf(value * static_cast<float>(factor)));
    if (dp == 0) {
        snprintf(buf, len, "%ld", rounded);
    } else {
        long whole = rounded / factor;
        long frac  = rounded % factor;
        if (frac < 0) frac = -frac;
        char fmt[16];
        snprintf(fmt, sizeof(fmt), "%%ld.%%0%dd", dp);
        snprintf(buf, len, fmt, whole, static_cast<int>(frac));
    }
}

// Add a float field to a cJSON object with fixed decimal places.
static void add_float(cJSON* obj, const char* key, float value, int dp)
{
    char buf[32];
    fmt_dp(buf, sizeof(buf), value, dp);
    // Add as a raw number so cJSON doesn't re-format it
    cJSON* item = cJSON_CreateRaw(buf);
    if (item) {
        cJSON_AddItemToObject(obj, key, item);
    } else {
        ESP_LOGE(TAG, "Failed to allocate JSON number for field '%s'", key);
    }
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

    // Omit timestamp entirely when not yet synchronised.
    if (t.timestamp_utc[0] != '\0') {
        cJSON_AddStringToObject(root, "timestamp", t.timestamp_utc);
    }

    cJSON_AddNumberToObject(root, "uptime_ms", static_cast<double>(t.uptime_ms));
    cJSON_AddBoolToObject  (root, "simulated", true);

    // Network object
    cJSON* net = cJSON_AddObjectToObject(root, "network");
    if (!net) {
        ESP_LOGE(TAG, "Failed to allocate network object");
        cJSON_Delete(root);
        return nullptr;
    }
    cJSON_AddBoolToObject(net, "connected", t.net_connected);
    cJSON_AddBoolToObject(net, "internet",  t.net_internet);
    if (t.net_connected) {
        cJSON_AddStringToObject(net, "ip",       t.net_ip_addr);
        cJSON_AddNumberToObject(net, "rssi_dbm", t.net_rssi_dbm);
    }

    // Measurements
    cJSON* m = cJSON_AddObjectToObject(root, "measurements");
    if (!m) {
        ESP_LOGE(TAG, "Failed to allocate measurements object");
        cJSON_Delete(root);
        return nullptr;
    }

    add_float(m, "temperature_c", t.temperature_c, 1);
    add_float(m, "humidity_pct",  t.humidity_pct,  1);
    add_float(m, "pressure_hpa",  t.pressure_hpa,  2);
    add_float(m, "co2_ppm",       t.co2_ppm,       0);
    add_float(m, "light_lux",     t.light_lux,     1);
    add_float(m, "voc_index",     t.voc_index,     0);
    add_float(m, "battery_mv",    t.battery_mv,    0);

    char* json = cJSON_PrintUnformatted(root);
    cJSON_Delete(root);

    if (!json) {
        ESP_LOGE(TAG, "Failed to serialise telemetry to JSON");
    }

    return json;
}
