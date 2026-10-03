#pragma once

// AWS IoT Core MQTT configuration.
// Copy this file to mqtt_config.h and fill in your account-specific endpoint.
//
//   copy main\config\mqtt_config.example.h main\config\mqtt_config.h
//
// mqtt_config.h is listed in .gitignore and must never be committed.
// The endpoint is not a secret but is account-specific; keeping it out of
// the repository avoids accidentally targeting the wrong AWS account.
//
// Retrieve your endpoint:
//   aws iot describe-endpoint --endpoint-type iot:Data-ATS --region eu-west-2
//
// It will resemble:
//   xxxxxxxxxxxxx-ats.iot.eu-west-2.amazonaws.com

namespace mqtt_config {

constexpr const char* ENDPOINT       = "YOUR_ENDPOINT-ats.iot.eu-west-2.amazonaws.com";
constexpr const char* BROKER_URI     = "mqtts://YOUR_ENDPOINT-ats.iot.eu-west-2.amazonaws.com:8883";
constexpr const char* TELEMETRY_TOPIC = "devices/esp32-dev-001/telemetry";

} // namespace mqtt_config
