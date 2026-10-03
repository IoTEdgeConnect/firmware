#pragma once

// Initialise and start the MQTT client.
// Connects to AWS IoT Core using mTLS.
// Must be called after network_init() and time_sync_init().
// Returns immediately; the connection is established asynchronously.
void mqtt_init();

// Publish a JSON payload to the device telemetry topic.
// Safe to call from any task.
// Returns true if the message was accepted by the MQTT client queue.
// Returns false (and logs a warning) if MQTT is not connected or the
// publish call fails — the caller should not retry; the next telemetry
// sample will be published on the following interval.
bool mqtt_publish_telemetry(const char* json, int len);

// Returns true if the MQTT client is currently connected to AWS IoT Core.
bool mqtt_is_connected();
