#include "time_sync.h"

#include <cstdio>
#include <ctime>

#include "esp_log.h"
#include "esp_sntp.h"

static constexpr const char* TAG      = "TIME";
static constexpr const char* NTP_HOST = "pool.ntp.org";

static void sntp_sync_cb(struct timeval* /*tv*/)
{
    char buf[21];
    time_t now = time(nullptr);
    struct tm t{};
    gmtime_r(&now, &t);
    strftime(buf, sizeof(buf), "%Y-%m-%dT%H:%M:%SZ", &t);
    ESP_LOGI(TAG, "Time synchronised");
    ESP_LOGI(TAG, "Current UTC time: %s", buf);
}

void time_sync_init()
{
    ESP_LOGI(TAG, "Starting SNTP synchronisation");
    esp_sntp_setoperatingmode(SNTP_OPMODE_POLL);
    esp_sntp_setservername(0, NTP_HOST);
    sntp_set_time_sync_notification_cb(sntp_sync_cb);
    esp_sntp_init();
}

bool time_sync_is_valid()
{
    return sntp_get_sync_status() == SNTP_SYNC_STATUS_COMPLETED;
}

bool time_sync_get_iso8601(char* buf, uint32_t buf_len)
{
    if (!time_sync_is_valid()) {
        return false;
    }
    time_t now = time(nullptr);
    struct tm t{};
    gmtime_r(&now, &t);
    strftime(buf, buf_len, "%Y-%m-%dT%H:%M:%SZ", &t);
    return true;
}
