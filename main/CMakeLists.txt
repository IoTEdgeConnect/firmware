idf_component_register(
    SRCS
        "app_main.cpp"
        "network/network.cpp"
        "time_sync/time_sync.cpp"
        "telemetry/telemetry.cpp"
        "telemetry/telemetry_generator.cpp"
        "mqtt/mqtt.cpp"
    INCLUDE_DIRS
        "."
    REQUIRES
        esp_timer
        esp_wifi
        esp_netif
        esp_event
        nvs_flash
        lwip
        json
        mqtt
        mbedtls
)

# Embed certificate material directly into the firmware binary.
# The files must exist in main/certs/ before building.
# If any file is absent CMake will fail here with a clear error.
target_add_binary_data(${COMPONENT_LIB} "certs/device.crt" TEXT)
target_add_binary_data(${COMPONENT_LIB} "certs/device.key" TEXT)
target_add_binary_data(${COMPONENT_LIB} "certs/root-ca.pem" TEXT)
