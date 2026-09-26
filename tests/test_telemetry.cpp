// tests/test_telemetry.cpp
//
// Host-side tests for telemetry generation and JSON serialisation.
// Compiled without ESP-IDF; stubs replace esp_random() and esp_timer_get_time().
//
// Build (from firmware root):
//   g++ -std=c++17 -I main -I tests/stubs -I $IDF_PATH/components/json/cJSON \
//       $IDF_PATH/components/json/cJSON/cJSON.c \
//       tests/test_telemetry.cpp -o tests/test_telemetry && tests/test_telemetry

#include <cassert>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <random>

// ---------------------------------------------------------------------------
// ESP-IDF stubs
// ---------------------------------------------------------------------------

static std::mt19937 rng{42};

extern "C" uint32_t esp_random()
{
    return static_cast<uint32_t>(rng());
}

static int64_t fake_uptime_us = 0;

extern "C" int64_t esp_timer_get_time()
{
    fake_uptime_us += 5'000'000LL;
    return fake_uptime_us;
}

// ---------------------------------------------------------------------------
// Pull in the implementation units under test
// ---------------------------------------------------------------------------

#include "telemetry/telemetry_generator.cpp"
#include "telemetry/telemetry.cpp"

// ---------------------------------------------------------------------------

static int passed = 0;
static int failed = 0;

#define CHECK(cond, msg)                                          \
    do {                                                          \
        if (cond) { ++passed; }                                   \
        else {                                                    \
            ++failed;                                             \
            fprintf(stderr, "FAIL [%s:%d] %s\n",                 \
                    __FILE__, __LINE__, msg);                     \
        }                                                         \
    } while (0)

int main()
{
    // --- sequence increments ------------------------------------------------
    {
        TelemetryGenerator gen;
        Telemetry a = gen.next();
        Telemetry b = gen.next();
        Telemetry c = gen.next();
        CHECK(a.sequence == 1, "first sequence == 1");
        CHECK(b.sequence == 2, "second sequence == 2");
        CHECK(c.sequence == 3, "third sequence == 3");
    }

    // --- all fields within limits over 500 samples -------------------------
    {
        TelemetryGenerator gen;
        for (int i = 0; i < 500; ++i) {
            Telemetry s = gen.next();
            CHECK(s.temperature_c >= 15.0f  && s.temperature_c <= 35.0f,   "temperature within [15, 35]");
            CHECK(s.humidity_pct  >= 20.0f  && s.humidity_pct  <= 80.0f,   "humidity within [20, 80]");
            CHECK(s.pressure_hpa  >= 970.0f && s.pressure_hpa  <= 1050.0f, "pressure within [970, 1050]");
            CHECK(s.co2_ppm       >= 350.0f && s.co2_ppm       <= 2000.0f, "co2 within [350, 2000]");
            CHECK(s.light_lux     >= 0.0f   && s.light_lux     <= 10000.0f,"light within [0, 10000]");
            CHECK(s.voc_index     >= 1.0f   && s.voc_index     <= 500.0f,  "voc within [1, 500]");
            CHECK(s.battery_mv    >= 3000.0f&& s.battery_mv    <= 4200.0f, "battery within [3000, 4200]");
            CHECK(s.rssi_dbm      >= -90    && s.rssi_dbm      <= -30,     "rssi within [-90, -30]");
        }
    }

    // --- all fields change over time ----------------------------------------
    {
        TelemetryGenerator gen;
        Telemetry first = gen.next();
        bool temp_changed  = false, hum_changed   = false;
        bool pres_changed  = false, co2_changed   = false;
        bool light_changed = false, voc_changed   = false;
        bool bat_changed   = false, rssi_changed  = false;

        for (int i = 0; i < 20; ++i) {
            Telemetry s = gen.next();
            if (s.temperature_c != first.temperature_c) temp_changed  = true;
            if (s.humidity_pct  != first.humidity_pct)  hum_changed   = true;
            if (s.pressure_hpa  != first.pressure_hpa)  pres_changed  = true;
            if (s.co2_ppm       != first.co2_ppm)       co2_changed   = true;
            if (s.light_lux     != first.light_lux)     light_changed = true;
            if (s.voc_index     != first.voc_index)     voc_changed   = true;
            if (s.battery_mv    != first.battery_mv)    bat_changed   = true;
            if (s.rssi_dbm      != first.rssi_dbm)      rssi_changed  = true;
        }

        CHECK(temp_changed,  "temperature changes over time");
        CHECK(hum_changed,   "humidity changes over time");
        CHECK(pres_changed,  "pressure changes over time");
        CHECK(co2_changed,   "co2 changes over time");
        CHECK(light_changed, "light changes over time");
        CHECK(voc_changed,   "voc changes over time");
        CHECK(bat_changed,   "battery changes over time");
        CHECK(rssi_changed,  "rssi changes over time");
    }

    // --- battery drains monotonically over many samples --------------------
    {
        TelemetryGenerator gen;
        Telemetry first = gen.next();
        for (int i = 0; i < 100; ++i) gen.next();
        Telemetry later = gen.next();
        CHECK(later.battery_mv < first.battery_mv, "battery drains over time");
    }

    // --- JSON serialisation -------------------------------------------------
    {
        Telemetry s{};
        s.sequence      = 42;
        s.uptime_ms     = 210000;
        s.temperature_c = 22.4f;
        s.humidity_pct  = 53.1f;
        s.pressure_hpa  = 1013.25f;
        s.co2_ppm       = 412.0f;
        s.light_lux     = 487.5f;
        s.voc_index     = 103.0f;
        s.battery_mv    = 4150.0f;
        s.rssi_dbm      = -67;

        char* json = telemetry_to_json(s);
        CHECK(json != nullptr, "telemetry_to_json returns non-null");

        if (json) {
            CHECK(strstr(json, "\"schema_version\":1")  != nullptr, "schema_version present");
            CHECK(strstr(json, "\"device_id\"")         != nullptr, "device_id present");
            CHECK(strstr(json, "\"sequence\":42")       != nullptr, "sequence present");
            CHECK(strstr(json, "\"uptime_ms\":210000")  != nullptr, "uptime_ms present");
            CHECK(strstr(json, "\"simulated\":true")    != nullptr, "simulated flag present");
            CHECK(strstr(json, "\"measurements\"")      != nullptr, "measurements object present");
            CHECK(strstr(json, "\"temperature_c\"")     != nullptr, "temperature_c present");
            CHECK(strstr(json, "\"humidity_pct\"")      != nullptr, "humidity_pct present");
            CHECK(strstr(json, "\"pressure_hpa\"")      != nullptr, "pressure_hpa present");
            CHECK(strstr(json, "\"co2_ppm\"")           != nullptr, "co2_ppm present");
            CHECK(strstr(json, "\"light_lux\"")         != nullptr, "light_lux present");
            CHECK(strstr(json, "\"voc_index\"")         != nullptr, "voc_index present");
            CHECK(strstr(json, "\"battery_mv\"")        != nullptr, "battery_mv present");
            CHECK(strstr(json, "\"rssi_dbm\"")          != nullptr, "rssi_dbm present");
            free(json);
        }
    }

    printf("\nResults: %d passed, %d failed\n", passed, failed);
    return failed == 0 ? 0 : 1;
}
