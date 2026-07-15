# Bitrate modes

Auto is the default and adapts within codec/transport bounds. Manual selects a fixed preset and clamps it to the active path. Benchmark exposes 10–200 Mbps for local experiments only and displays these warnings: Experimental; May increase latency; May cause queueing; For local benchmark only.

Bounds are HEVC WiFi 12–100, HEVC USB 20–160, H.264 WiFi 8–60, and H.264 USB 10–100 Mbps. Auto also uses a transport-aware initial estimate; for example, 3040×1904 at 120 fps with High-quality HEVC starts around 112 Mbps on USB. The settings UI filters manual presets using the selected codec and transport; the sender revalidates the value using the negotiated codec and actual transport.

Target Bitrate is encoder intent. Actual Bitrate is measured socket throughput. They are displayed and recorded separately.
