#pragma once

// Wi-Fi credentials for development.
//
// Copy this file to wifi_config.h and fill in your local credentials.
// wifi_config.h is listed in .gitignore and must NEVER be committed.
//
//   copy main\config\wifi_config.example.h main\config\wifi_config.h
//
// Then edit wifi_config.h with your actual SSID and password.

namespace wifi_config {

constexpr const char* SSID     = "YOUR_SSID_HERE";
constexpr const char* PASSWORD = "YOUR_PASSWORD_HERE";

} // namespace wifi_config
