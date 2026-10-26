[English](android-thermal-power-metrics.md) | [简体中文](android-thermal-power-metrics.zh-CN.md)

# Android thermal and power metrics

## Modified files

- `AndroidPowerMetrics.java` samples platform thermal, power-saver, and sticky battery state without affecting streaming;
- receiver stats and the Mac Benchmark model carry the readings into JSON, CSV, and JSONL;
- Android and Swift standalone tests cover normalization, unavailable values, decoding, and stable export columns.

## Purpose

This measurement-only stage makes thermal and power state visible beside rendered FPS, frame age, decoder drops, and GC metrics. It does not change bitrate, frame rate, scale, codec, or recovery behavior.

## Metrics

| Field | Source | Unavailable behavior |
| --- | --- | --- |
| `thermalStatus` | `PowerManager.getCurrentThermalStatus()` on Android 10+ | `null` / `notAvailable` |
| `powerSaver` | `PowerManager.isPowerSaveMode()` | `null` / `notAvailable` |
| `batteryTemperature` | `ACTION_BATTERY_CHANGED`, tenths °C converted to °C | `null` / `notAvailable` |
| `batteryLevel` | battery level divided by scale, percent | `null` / `notAvailable` |
| `charging` | charging or full battery status | `null` / `notAvailable` |

Sampling is best effort during the existing once-per-second stats publication. Vendor/API failures are isolated from the video path. Missing data is never replaced with zero or false.

Android thermal status uses the platform integer scale: none, light, moderate, severe, critical, emergency, or shutdown. Raw values are retained so later analysis can correlate transitions without introducing an unverified automatic policy.

## Tests

- normalization proves `365` tenths °C becomes `36.5` °C and battery level is bounded to a percentage;
- unavailable inputs remain `null`;
- receiver stats JSON publishes all five canonical fields;
- Benchmark decoding, CSV headers, and JSONL preserve all five readings.

## Build result

- Android clean/test/Debug assembly passed with `61 actionable tasks: 61 executed`; all six receiver self-test groups passed.
- All 22 standalone Swift self-tests passed.
- `xcodegen generate`, unsigned macOS Debug, and generic iOS Simulator Debug builds passed.
- Production site build/prerender, 34 bilingual document pairs, release-link validation, and `git diff --check` passed.
- `adb devices -l` reported no attached device.

## Before/after metrics

Before this change, the benchmark could not distinguish thermal/power-state changes from network or decoder degradation. After it, the state is recordable, but no same-condition physical sample exists yet and no performance improvement is claimed.

## Known risks

- Thermal status requires Android 10; older supported Android versions report it unavailable.
- Sticky battery broadcasts and vendor power services can omit values.
- Battery temperature is a device sensor reading, not ambient or SoC junction temperature.
- Correlation does not prove causation; compare fixed-condition repeated runs.

## Pending physical validation

- verify real values on the available Android receiver while idle, streaming, charging, and under power saver;
- correlate transitions with rendered FPS, frame-age P50/P95/P99, decoder drops, GC, and bitrate;
- confirm unsupported/omitted vendor readings remain `notAvailable` rather than zero.

No Android device was attached while this implementation was prepared.

## Next step

Run the short WiFi/USB matrix from the recovery and benchmark guides. Do not introduce automatic `120 → 90 → 60` or scale reduction until repeatable evidence supports it.
