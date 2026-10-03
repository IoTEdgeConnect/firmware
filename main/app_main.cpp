#include "config/device_config.h"
#include "network/network.h"
#include "time_sync/time_sync.h"
#include "telemetry/telemetry.h"
#include "telemetry/telemetry_generator.h"
#include "mqtt/mqtt.h"

#include <cinttypes>
#include <cstdio>
#include <cstdlib>
#include <cstring>

#include "esp_log.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"

static constexpr const char* TAG = "IOTEDGE";

static void telemetry_task(void* /*arg*/)
{
    TelemetryGenerator generator;
    TickType_t last_wake = xTaskGetTickCount();
    const TickType_t interval = pdMS_TO_TICKS(config::TELEMETRY_INTERVAL_MS);

    while (true) {
        vTaskDelayUntil(&last_wake, interval);

        Telemetry sample = generator.next();

        // Populate network status
        NetworkStatus net = network_get_status();
        sample.net_connected = net.connected;
        sample.net_internet  = net.internet;
        sample.net_rssi_dbm  = net.rssi_dbm;
        static_assert(sizeof(sample.net_ip_addr) == sizeof(net.ip_addr), "IP buffer size mismatch");
        memcpy(sample.net_ip_addr, net.ip_addr, sizeof(sample.net_ip_addr));

        // Populate wall-clock timestamp if synchronised.
        if (!time_sync_get_iso8601(sample.timestamp_utc, sizeof(sample.timestamp_utc))) {
            sample.timestamp_utc[0] = '\0';
        }

        char* json = telemetry_to_json(sample);
        if (!json) {
            ESP_LOGE(TAG, "Telemetry sample %" PRIu64 " dropped — JSON serialisation failed",
                     sample.sequence);
            continue;
        }

        // Serial output — always available for debugging regardless of MQTT state.
        printf("%s\n", json);

        // MQTT publish — best-effort; telemetry continues if MQTT is unavailable.
        // Wi-Fi connected != MQTT connected; log both states on failure so the
        // developer can distinguish network issues from AWS/TLS issues.
        if (!mqtt_publish_telemetry(json, static_cast<int>(strlen(json)))) {
            ESP_LOGD(TAG, "Wi-Fi: %s  MQTT: disconnected",
                     net.connected ? "connected" : "disconnected");
        }

        free(json);
    }
}

extern "C" void app_main()
{
    ESP_LOGI(TAG, "IoTEdgeConnect firmware starting");
    ESP_LOGI(TAG, "Device: %s",            config::DEVICE_ID);
    ESP_LOGI(TAG, "Firmware: %s",          config::FIRMWARE_VERSION);
    ESP_LOGI(TAG, "Telemetry interval: %" PRIu32 " ms", config::TELEMETRY_INTERVAL_MS);

    network_init();
    time_sync_init();
    mqtt_init();

    if (xTaskCreate(telemetry_task, "telemetry", 4096, nullptr, 5, nullptr) != pdPASS) {
        ESP_LOGE(TAG, "Failed to create telemetry task — out of memory (stack: 4096 words)");
        ESP_ERROR_CHECK(ESP_ERR_NO_MEM);
    }
}
