[English](benchmark-guide.md) | [简体中文](benchmark-guide.zh-CN.md)

# Short Benchmark Guide

DisplayWeave's Debug-only Short Benchmark records real receiver and sender samples. It does not move windows, scroll a browser, change transport, or invent missing samples. The operator performs the named scene and records every aborted or failed run.

## Run format

1. Connect exactly one receiver and let temperature and power state settle.
2. Fix the commit, Mac, receiver, resolution, scale, codec, requested FPS, target bitrate, transport, scene, and thermal starting state. Change one main variable per comparison.
3. Select a scene and duration under **Short Benchmark (Experimental)**, then start recording.
4. Keep the scene running through the 30-second `warmup` phase and the selected `run` phase.
5. Stop if frame age or queue depth grows continuously, the device throttles, the picture fails, or the test condition changes. Keep the output and annotate the reason; do not delete a bad sample.

Durations:

| Mode | Warm-up | Recorded run | Use |
| --- | ---: | ---: | --- |
| Standard | 30 s | 3 min | Required short comparison |
| Extended | 30 s | 5 min | Local engineering check |
| Optional | 30 s | 10 min | Maximum single local run |

Run each controlled combination at least twice; use a third run when conditions allow. This work does not require 30-minute or 2-hour endurance testing.

## Scenes

- **Static Desktop:** fixed desktop and windows; note that ScreenCaptureKit is content-driven and capture FPS may fall when nothing changes.
- **Text Scroll:** the same document, viewport, font size, and repeatable scroll path.
- **Browser Scroll:** a fixed local page and repeatable scroll path; avoid network-loaded content.
- **120Hz MTKView Test Pattern:** the same pattern, animation rate, window size, and display placement.
- **Rapid Window Drag:** the same window, path, pace, and duration.

## Controlled parameter matrix

- Resolution: `1920×1080`, `2560×1600`, and Android native resolution.
- Codec: HEVC and H.264.
- Requested rate: 60, 90, and 120 FPS where the receiver advertises support.
- Transport: WiFi and USB.

Not every Cartesian combination must be run on unsupported hardware. Record unsupported or unavailable combinations as such; never substitute a different condition without changing the run metadata.

## Output

Each run is written under:

`~/Library/Application Support/DisplayWeave/Benchmarks/<run-id>/`

- `benchmark.csv`: RFC 4180 fields, CRLF records, `notAvailable` for unavailable values.
- `benchmark.jsonl`: one JSON object per sample, `null` for unavailable values.

Both files identify `runId`, `sessionId`, `scene`, `phase`, wall `timestamp`, and monotonic elapsed milliseconds. The schema records:

- device model, transport, codec, width, height, requested FPS;
- actual Mac virtual-display and Android display refresh rates;
- capture, encoded, sent, received, decoded, and rendered FPS;
- target and actual wire bitrate, average encoded frame size;
- encode API latency, send-to-render estimate, RTT, clock offset, offset confidence/state;
- frame-age average/latest/P50/P95/P99 and estimated E2E;
- pending sends, Mac and Android queue depth and drops;
- input P50/P95, Mac CPU, and Mac memory.

An unavailable producer is not zero. CSV uses `notAvailable`; JSONL uses `null`. Mac CPU currently remains unavailable because the recorder does not yet have a trustworthy interval sampler. A stopped run retains the samples already flushed. A flush failure is shown with its output path and must be treated as failed evidence.

## Comparing runs

Use medians and P95 values across matched runs, not one favorable instant. Compare average/1%-low rendered FPS, frame-age distribution, RTT distribution, queue occupancy, classified drops, keyframe events, and visual stability. Target bitrate and actual bitrate are separate columns. Higher bitrate is a quality variable, not evidence of lower latency.

The physical 3-minute USB/WiFi A/B matrix is still pending until it is run on the available device. The presence of the recorder is not a benchmark result.
