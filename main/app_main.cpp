#include "config/device_config.h"
#include "telemetry/telemetry.h"
#include "telemetry/telemetry_generator.h"

#include <cinttypes>
#include <cstdio>
#include <cstdlib>

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
        char* json = telemetry_to_json(sample);
        if (json) {
            printf("%s\n", json);
            free(json);
        }
    }
}

extern "C" void app_main()
{
    ESP_LOGI(TAG, "IoTEdgeConnect firmware starting");
    ESP_LOGI(TAG, "Device: %s",            config::DEVICE_ID);
    ESP_LOGI(TAG, "Firmware: %s",          config::FIRMWARE_VERSION);
    ESP_LOGI(TAG, "Telemetry interval: %" PRIu32 " ms", config::TELEMETRY_INTERVAL_MS);

    xTaskCreate(
        telemetry_task,
        "telemetry",
        4096,
        nullptr,
        5,
        nullptr
    );
}
