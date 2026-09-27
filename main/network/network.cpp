#include "network.h"
#include "config/wifi_config.h"

#include <cstdio>
#include <cstring>

#include "esp_event.h"
#include "esp_log.h"
#include "esp_netif.h"
#include "esp_wifi.h"
#include "freertos/FreeRTOS.h"
#include "freertos/event_groups.h"
#include "freertos/task.h"
#include "lwip/dns.h"
#include "lwip/ip_addr.h"
#include "nvs_flash.h"

static constexpr const char* TAG = "NETWORK";

static constexpr TickType_t RECONNECT_DELAY_TICKS   = pdMS_TO_TICKS(5000);
static constexpr TickType_t INTERNET_CHECK_INTERVAL = pdMS_TO_TICKS(30000);
static constexpr TickType_t DNS_TIMEOUT_TICKS        = pdMS_TO_TICKS(5000);

static EventGroupHandle_t s_wifi_events;
static constexpr EventBits_t BIT_CONNECTED    = BIT0;
static constexpr EventBits_t BIT_DISCONNECTED = BIT1;
static constexpr EventBits_t BIT_DNS_DONE     = BIT2;

static volatile bool s_internet = false;
static char s_ip_addr[16] = {};
static esp_netif_t* s_netif = nullptr;
static portMUX_TYPE s_state_mux = portMUX_INITIALIZER_UNLOCKED;

// ---------------------------------------------------------------------------
// DNS callback — called from the lwIP thread
// ---------------------------------------------------------------------------

static void dns_found_cb(const char* /*name*/, const ip_addr_t* addr, void* arg)
{
    auto* events = static_cast<EventGroupHandle_t>(arg);
    // addr is non-null on success, null on failure/timeout
    if (addr) {
        taskENTER_CRITICAL(&s_state_mux);
        s_internet = true;
        taskEXIT_CRITICAL(&s_state_mux);
    }
    xEventGroupSetBitsFromISR(events, BIT_DNS_DONE, nullptr);
}

// ---------------------------------------------------------------------------
// Internet check task
// ---------------------------------------------------------------------------

static bool dns_resolves(const char* server, EventGroupHandle_t events)
{
    ip_addr_t addr{};
    xEventGroupClearBits(events, BIT_DNS_DONE);
    taskENTER_CRITICAL(&s_state_mux);
    s_internet = false;
    taskEXIT_CRITICAL(&s_state_mux);

    err_t err = dns_gethostbyname(server, &addr, dns_found_cb, events);
    if (err == ERR_OK) {
        return true;
    }
    if (err != ERR_INPROGRESS) {
        return false;
    }

    EventBits_t bits = xEventGroupWaitBits(events, BIT_DNS_DONE,
                                           pdTRUE, pdFALSE, DNS_TIMEOUT_TICKS);
    taskENTER_CRITICAL(&s_state_mux);
    bool result = (bits & BIT_DNS_DONE) && s_internet;
    taskEXIT_CRITICAL(&s_state_mux);
    return result;
}

static void internet_check_task(void* /*arg*/)
{
    static constexpr const char* SERVERS[] = { "8.8.8.8", "1.1.1.1" };

    while (true) {
        xEventGroupWaitBits(s_wifi_events, BIT_CONNECTED,
                            pdFALSE, pdFALSE, portMAX_DELAY);

        bool reachable = false;
        for (const char* server : SERVERS) {
            if (dns_resolves(server, s_wifi_events)) {
                reachable = true;
                break;
            }
        }

        taskENTER_CRITICAL(&s_state_mux);
        s_internet = reachable;
        taskEXIT_CRITICAL(&s_state_mux);
        ESP_LOGI(TAG, "Internet: %s", reachable ? "reachable" : "unreachable");

        vTaskDelay(INTERNET_CHECK_INTERVAL);
    }
}

// ---------------------------------------------------------------------------
// Reconnect task
// ---------------------------------------------------------------------------

static void reconnect_task(void* /*arg*/)
{
    while (true) {
        xEventGroupWaitBits(s_wifi_events, BIT_DISCONNECTED,
                            pdTRUE /*clear*/, pdFALSE, portMAX_DELAY);
        taskENTER_CRITICAL(&s_state_mux);
        s_internet = false;
        taskEXIT_CRITICAL(&s_state_mux);
        vTaskDelay(RECONNECT_DELAY_TICKS);
        // Force a fresh DHCP lease on reconnect — prevents the driver
        // reusing a stale cached lease from NVS.
        esp_netif_dhcpc_stop(s_netif);
        esp_netif_dhcpc_start(s_netif);
        ESP_LOGI(TAG, "Reconnecting to %s", wifi_config::SSID);
        esp_wifi_connect();
    }
}

// ---------------------------------------------------------------------------
// Event handler
// ---------------------------------------------------------------------------

static void wifi_event_handler(void* /*arg*/, esp_event_base_t base,
                               int32_t id, void* data)
{
    if (base == WIFI_EVENT) {
        switch (id) {
            case WIFI_EVENT_STA_START:
                ESP_LOGI(TAG, "Connecting to %s", wifi_config::SSID);
                esp_wifi_connect();
                break;

            case WIFI_EVENT_STA_CONNECTED:
                ESP_LOGI(TAG, "Wi-Fi connected");
                break;

            case WIFI_EVENT_STA_DISCONNECTED: {
                xEventGroupClearBits(s_wifi_events, BIT_CONNECTED);
                auto* ev = static_cast<wifi_event_sta_disconnected_t*>(data);
                ESP_LOGW(TAG, "Wi-Fi disconnected (reason %d)", ev->reason);
                taskENTER_CRITICAL(&s_state_mux);
                s_ip_addr[0] = '\0';
                taskEXIT_CRITICAL(&s_state_mux);
                xEventGroupSetBits(s_wifi_events, BIT_DISCONNECTED);
                break;
            }

            default:
                break;
        }
    } else if (base == IP_EVENT && id == IP_EVENT_STA_GOT_IP) {
        auto* ev = static_cast<ip_event_got_ip_t*>(data);
        taskENTER_CRITICAL(&s_state_mux);
        snprintf(s_ip_addr, sizeof(s_ip_addr), IPSTR, IP2STR(&ev->ip_info.ip));
        taskEXIT_CRITICAL(&s_state_mux);
        ESP_LOGI(TAG, "IPv4 address: %s", s_ip_addr);
        ESP_LOGI(TAG, "Gateway:      " IPSTR, IP2STR(&ev->ip_info.gw));
        ESP_LOGI(TAG, "Netmask:      " IPSTR, IP2STR(&ev->ip_info.netmask));
        xEventGroupSetBits(s_wifi_events, BIT_CONNECTED);
    }
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

void network_init()
{
    esp_err_t err = nvs_flash_init();
    if (err == ESP_ERR_NVS_NO_FREE_PAGES || err == ESP_ERR_NVS_NEW_VERSION_FOUND) {
        ESP_LOGW(TAG, "NVS partition truncated, erasing and reinitialising");
        ESP_ERROR_CHECK(nvs_flash_erase());
        err = nvs_flash_init();
    }
    ESP_ERROR_CHECK(err);

    ESP_LOGI(TAG, "Initialising Wi-Fi");

    ESP_ERROR_CHECK(esp_netif_init());
    ESP_ERROR_CHECK(esp_event_loop_create_default());
    s_netif = esp_netif_create_default_wifi_sta();
    if (!s_netif) {
        ESP_LOGE(TAG, "Failed to create default Wi-Fi STA netif — out of memory");
        ESP_ERROR_CHECK(ESP_ERR_NO_MEM);
    }

    s_wifi_events = xEventGroupCreate();
    if (!s_wifi_events) {
        ESP_LOGE(TAG, "Failed to create Wi-Fi event group — out of memory");
        ESP_ERROR_CHECK(ESP_ERR_NO_MEM);
    }

    wifi_init_config_t cfg = WIFI_INIT_CONFIG_DEFAULT();
    ESP_ERROR_CHECK(esp_wifi_init(&cfg));

    ESP_ERROR_CHECK(esp_event_handler_instance_register(
        WIFI_EVENT, ESP_EVENT_ANY_ID, wifi_event_handler, nullptr, nullptr));
    ESP_ERROR_CHECK(esp_event_handler_instance_register(
        IP_EVENT, IP_EVENT_STA_GOT_IP, wifi_event_handler, nullptr, nullptr));

    wifi_config_t wifi_cfg{};
    strncpy(reinterpret_cast<char*>(wifi_cfg.sta.ssid),
            wifi_config::SSID, sizeof(wifi_cfg.sta.ssid) - 1);
    strncpy(reinterpret_cast<char*>(wifi_cfg.sta.password),
            wifi_config::PASSWORD, sizeof(wifi_cfg.sta.password) - 1);
    // Scan all channels before associating — avoids premature association
    // attempts that trigger band-steering disassociation on dual-band APs.
    wifi_cfg.sta.scan_method = WIFI_ALL_CHANNEL_SCAN;

    ESP_ERROR_CHECK(esp_wifi_set_mode(WIFI_MODE_STA));
    ESP_ERROR_CHECK(esp_wifi_set_config(WIFI_IF_STA, &wifi_cfg));
    ESP_ERROR_CHECK(esp_wifi_start());

    if (xTaskCreate(reconnect_task, "wifi_reconnect", 2048, nullptr, 4, nullptr) != pdPASS) {
        ESP_LOGE(TAG, "Failed to create wifi_reconnect task — out of memory (stack: 2048 words)");
        ESP_ERROR_CHECK(ESP_ERR_NO_MEM);
    }
    if (xTaskCreate(internet_check_task, "internet_check", 3072, nullptr, 3, nullptr) != pdPASS) {
        ESP_LOGE(TAG, "Failed to create internet_check task — out of memory (stack: 3072 words)");
        ESP_ERROR_CHECK(ESP_ERR_NO_MEM);
    }
}

NetworkStatus network_get_status()
{
    NetworkStatus status{};

    taskENTER_CRITICAL(&s_state_mux);
    strncpy(status.ip_addr, s_ip_addr, sizeof(status.ip_addr) - 1);
    status.ip_addr[sizeof(status.ip_addr) - 1] = '\0';
    taskEXIT_CRITICAL(&s_state_mux);

    EventBits_t bits = xEventGroupGetBits(s_wifi_events);
    if (!(bits & BIT_CONNECTED)) {
        return status;  // connected/internet/rssi remain zero-initialised
    }

    wifi_ap_record_t ap{};
    if (esp_wifi_sta_get_ap_info(&ap) != ESP_OK) {
        return status;
    }

    status.connected = true;
    taskENTER_CRITICAL(&s_state_mux);
    status.internet  = s_internet;
    taskEXIT_CRITICAL(&s_state_mux);
    status.rssi_dbm  = ap.rssi;
    return status;
}
