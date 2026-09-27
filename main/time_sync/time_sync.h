#pragma once

#include <cstdint>

// Start SNTP synchronisation. Call once after network connectivity is
// established. Returns immediately; synchronisation happens asynchronously.
void time_sync_init();

// Returns true if wall-clock time has been synchronised via SNTP.
bool time_sync_is_valid();

// Writes an ISO 8601 UTC timestamp ("YYYY-MM-DDTHH:MM:SSZ") into buf.
// buf must be at least 21 bytes.
// Returns true on success; false if time is not yet synchronised.
bool time_sync_get_iso8601(char* buf, size_t buf_len);
