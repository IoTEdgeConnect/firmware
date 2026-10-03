#include "mqtt.h"
#include "config/device_config.h"
#include "config/mqtt_config.h"

#include <cstdio>
#include <cstring>

#include "esp_log.h"
#include "mbedtls/base64.h"
#include "mqtt_client.h"

static constexpr const char* TAG = "MQTT";

extern const uint8_t DEVICE_CERT_START[] asm("_binary_device_crt_start");
extern const uint8_t DEVICE_CERT_END[]   asm("_binary_device_crt_end");
extern const uint8_t DEVICE_KEY_START[]  asm("_binary_device_key_start");
extern const uint8_t DEVICE_KEY_END[]    asm("_binary_device_key_end");
extern const uint8_t ROOT_CA_START[]     asm("_binary_root_ca_pem_start");
extern const uint8_t ROOT_CA_END[]       asm("_binary_root_ca_pem_end");

static esp_mqtt_client_handle_t s_client    = nullptr;
static volatile bool            s_connected = false;

// ---------------------------------------------------------------------------
// DER → PEM conversion
//
// PEM is base64-encoded DER wrapped with a header/footer line and line breaks
// every 64 characters. mbedTLS requires PEM for the ESP-IDF MQTT client config.
//
// Detection: DER always begins with 0x30 (ASN.1 SEQUENCE tag).
//            PEM always begins with '-' (the header line).
//
// Returns a heap-allocated NUL-terminated PEM string, or nullptr on failure.
// Returns nullptr (and sets *out_len to the original length) if already PEM —
// in that case the caller should use the original pointer directly.
// ---------------------------------------------------------------------------

static char* der_to_pem(const uint8_t* der, size_t der_len,
                        const char* header, const char* footer,
                        size_t* out_len)
{
    // Already PEM — nothing to do.
    if (der[0] == '-') {
        *out_len = der_len;
        return nullptr;
    }

    // Base64-encode the DER blob.
    size_t b64_len = 0;
    mbedtls_base64_encode(nullptr, 0, &b64_len, der, der_len); // get required size
    char* b64 = static_cast<char*>(malloc(b64_len));
    if (!b64) return nullptr;
    mbedtls_base64_encode(reinterpret_cast<uint8_t*>(b64), b64_len, &b64_len, der, der_len);

    // Build PEM: header + base64 in 64-char lines + footer + NUL.
    size_t header_len = strlen(header);
    size_t footer_len = strlen(footer);
    size_t lines      = (b64_len + 63) / 64;
    size_t pem_len    = header_len + 1          // header + \n
                      + b64_len + lines         // base64 + \n per line
                      + footer_len + 2;         // \n + footer + \n + NUL

    char* pem = static_cast<char*>(malloc(pem_len));
    if (!pem) { free(b64); return nullptr; }

    char* p = pem;
    memcpy(p, header, header_len); p += header_len; *p++ = '\n';

    for (size_t i = 0; i < b64_len; i += 64) {
        size_t chunk = (b64_len - i) < 64 ? (b64_len - i) : 64;
        memcpy(p, b64 + i, chunk); p += chunk; *p++ = '\n';
    }

    *p++ = '\n';
    memcpy(p, footer, footer_len); p += footer_len; *p++ = '\n';
    *p   = '\0';

    free(b64);
    *out_len = static_cast<size_t>(p - pem);
    return pem;
}

// ---------------------------------------------------------------------------
// Event handler
// ---------------------------------------------------------------------------

static void mqtt_event_handler(void* /*arg*/, esp_event_base_t /*base*/,
                               int32_t event_id, void* event_data)
{
    auto* data = static_cast<esp_mqtt_event_handle_t>(event_data);

    switch (static_cast<esp_mqtt_event_id_t>(event_id)) {
        case MQTT_EVENT_CONNECTED:
            s_connected = true;
            ESP_LOGI(TAG, "MQTT connected to %s", mqtt_config::ENDPOINT);
            break;

        case MQTT_EVENT_DISCONNECTED:
            s_connected = false;
            ESP_LOGW(TAG, "MQTT disconnected — will reconnect automatically");
            break;

        case MQTT_EVENT_PUBLISHED:
            ESP_LOGD(TAG, "MQTT publish acknowledged (msg_id=%d)", data->msg_id);
            break;

        case MQTT_EVENT_ERROR:
            s_connected = false;
            if (data->error_handle) {
                ESP_LOGE(TAG, "MQTT error: type=%d esp_tls_last_esp_err=0x%x",
                         data->error_handle->error_type,
                         data->error_handle->esp_tls_last_esp_err);
            }
            break;

        default:
            break;
    }
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

void mqtt_init()
{
    ESP_LOGI(TAG, "Starting MQTT client");
    ESP_LOGI(TAG, "Endpoint: %s", mqtt_config::ENDPOINT);
    ESP_LOGI(TAG, "Client ID: %s", config::DEVICE_ID);
    ESP_LOGI(TAG, "Topic: %s", mqtt_config::TELEMETRY_TOPIC);

    // Convert any DER-format credentials to PEM.
    // If already PEM, der_to_pem returns nullptr and we use the original blob.
    size_t cert_len, key_len, ca_len;

    char* cert_pem = der_to_pem(DEVICE_CERT_START,
                                static_cast<size_t>(DEVICE_CERT_END - DEVICE_CERT_START),
                                "-----BEGIN CERTIFICATE-----",
                                "-----END CERTIFICATE-----",
                                &cert_len);

    char* key_pem  = der_to_pem(DEVICE_KEY_START,
                                static_cast<size_t>(DEVICE_KEY_END - DEVICE_KEY_START),
                                "-----BEGIN PRIVATE KEY-----",
                                "-----END PRIVATE KEY-----",
                                &key_len);

    char* ca_pem   = der_to_pem(ROOT_CA_START,
                                static_cast<size_t>(ROOT_CA_END - ROOT_CA_START),
                                "-----BEGIN CERTIFICATE-----",
                                "-----END CERTIFICATE-----",
                                &ca_len);

    const char* cert = cert_pem ? cert_pem : reinterpret_cast<const char*>(DEVICE_CERT_START);
    const char* key  = key_pem  ? key_pem  : reinterpret_cast<const char*>(DEVICE_KEY_START);
    const char* ca   = ca_pem   ? ca_pem   : reinterpret_cast<const char*>(ROOT_CA_START);

    if (cert_pem) ESP_LOGI(TAG, "device.crt: converted DER → PEM");
    if (key_pem)  ESP_LOGI(TAG, "device.key: converted DER → PEM");
    if (ca_pem)   ESP_LOGI(TAG, "root-ca:    converted DER → PEM");

    esp_mqtt_client_config_t cfg{};
    cfg.broker.address.uri                         = mqtt_config::BROKER_URI;
    cfg.broker.address.port                        = 8883;
    cfg.broker.verification.certificate            = ca;
    cfg.broker.verification.certificate_len        = ca_pem  ? ca_len  : static_cast<size_t>(ROOT_CA_END  - ROOT_CA_START);
    cfg.credentials.authentication.certificate     = cert;
    cfg.credentials.authentication.certificate_len = cert_pem ? cert_len : static_cast<size_t>(DEVICE_CERT_END - DEVICE_CERT_START);
    cfg.credentials.authentication.key             = key;
    cfg.credentials.authentication.key_len         = key_pem  ? key_len  : static_cast<size_t>(DEVICE_KEY_END  - DEVICE_KEY_START);
    cfg.credentials.client_id                      = config::DEVICE_ID;

    s_client = esp_mqtt_client_init(&cfg);

    // Free conversion buffers — esp_mqtt_client_init copies the credential data.
    free(cert_pem);
    free(key_pem);
    free(ca_pem);

    if (!s_client) {
        ESP_LOGE(TAG, "Failed to initialise MQTT client — out of memory");
        return;
    }

    ESP_ERROR_CHECK(esp_mqtt_client_register_event(
        s_client, MQTT_EVENT_ANY, mqtt_event_handler, nullptr));

    ESP_ERROR_CHECK(esp_mqtt_client_start(s_client));
}

bool mqtt_publish_telemetry(const char* json, int len)
{
    if (!s_connected || !s_client) {
        ESP_LOGW(TAG, "MQTT not connected — telemetry sample dropped");
        return false;
    }

    int msg_id = esp_mqtt_client_publish(
        s_client, mqtt_config::TELEMETRY_TOPIC, json, len, /*qos=*/1, /*retain=*/0);

    if (msg_id < 0) {
        ESP_LOGW(TAG, "esp_mqtt_client_publish failed (msg_id=%d)", msg_id);
        return false;
    }

    ESP_LOGD(TAG, "Telemetry queued for publish (msg_id=%d)", msg_id);
    return true;
}

bool mqtt_is_connected()
{
    return s_connected;
}
