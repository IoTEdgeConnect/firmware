#pragma once

#include <cstdint>

// Initialise NVS, the TCP/IP stack, and Wi-Fi station mode.
// Begins an asynchronous connection attempt; returns immediately.
// Must be called once from app_main before starting the telemetry task.
void network_init();

struct NetworkStatus {
    bool   connected;
    bool   internet;        // true if at least one DNS server (8.8.8.8 / 1.1.1.1) responded
    int8_t rssi_dbm;        // valid only when connected == true
    char   ip_addr[16];     // dotted-decimal IPv4; empty string when disconnected
};

// Returns a snapshot of the current network state.
// Safe to call from any task.
NetworkStatus network_get_status();
