// tests/test_telemetry.cpp
//
// Host-side tests for telemetry generation and JSON serialisation.
// Compiled without ESP-IDF; stubs replace esp_random() and esp_timer_get_time().
//
// Build (from firmware root, requires a host C++ compiler):
//   g++ -std=c++17 -I main -I tests/stubs -I $IDF_PATH/components/json/cJSON \
//       main/telemetry/telemetry_generator.cpp \
//       main/telemetry/telemetry.cpp \
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
    fake_uptime_us += 5'000'000LL; // advance 5 s per call
    return fake_uptime_us;
}

// ---------------------------------------------------------------------------
// Pull in the implementation units under test
// ---------------------------------------------------------------------------

#include "telemetry/telemetry_generator.cpp"
#include "telemetry/telemetry.cpp"

// cJSON is linked separately (see build command above)
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
    TelemetryGenerator gen;

    // --- sequence increments ------------------------------------------------
    Telemetry a = gen.next();
    Telemetry b = gen.next();
    Telemetry c = gen.next();

    CHECK(a.sequence == 1, "first sequence == 1");
    CHECK(b.sequence == 2, "second sequence == 2");
    CHECK(c.sequence == 3, "third sequence == 3");

    // --- temperature within limits ------------------------------------------
    for (int i = 0; i < 500; ++i) {
        Telemetry s = gen.next();
        CHECK(s.temperature_c >= 15.0f && s.temperature_c <= 35.0f,
              "temperature within [15, 35]");
        CHECK(s.humidity_pct >= 20.0f && s.humidity_pct <= 80.0f,
              "humidity within [20, 80]");
    }

    // --- values change over time --------------------------------------------
    {
        TelemetryGenerator g2;
        Telemetry first = g2.next();
        bool temp_changed = false;
        bool hum_changed  = false;
        for (int i = 0; i < 20; ++i) {
            Telemetry s = g2.next();
            if (s.temperature_c != first.temperature_c) temp_changed = true;
            if (s.humidity_pct  != first.humidity_pct)  hum_changed  = true;
        }
        CHECK(temp_changed, "temperature changes over time");
        CHECK(hum_changed,  "humidity changes over time");
    }

    // --- JSON serialisation -------------------------------------------------
    {
        Telemetry s{};
        s.sequence      = 42;
        s.uptime_ms     = 210000;
        s.temperature_c = 22.4f;
        s.humidity_pct  = 53.1f;

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
            free(json);
        }
    }

    printf("\nResults: %d passed, %d failed\n", passed, failed);
    return failed == 0 ? 0 : 1;
}
