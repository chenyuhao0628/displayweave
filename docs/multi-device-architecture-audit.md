# Multi-device architecture audit

Status: code audit complete; two-Android physical verification not performed.

| Area | Evidence | Status |
| --- | --- | --- |
| ADB identity | Discovery and recovery key Android devices by serial; wireless-debugging endpoints are excluded from wired selection. | Architecture Supports |
| Forward ports | `AndroidAdbForwardManager` allocates a unique local port per session and removes only owned mappings. | Code Appears Ready |
| Install identity | Serial-to-install-ID state deduplicates the same receiver across USB and WiFi and constrains fallback. | Code Appears Ready |
| Pipelines | Each `DeviceSession` owns a `MacSender`; each sender owns its virtual display, SCStream, VTCompressionSession, transport, stats, and input injector. | Architecture Supports |
| Display/input identity | A stable per-device display serial creates a distinct virtual display; input injection uses that display ID. | Code Appears Ready |
| Disconnect isolation | Ending one session stops only its sender and owned forward; controller-wide disconnect is a separate explicit path. | Code Appears Ready |
| Stats isolation | Capture, encode, send, latency, queue, benchmark recorder, and adaptive controller state are sender-instance fields. | Architecture Supports |
| Physical concurrency | Independent rendering, touch mapping, recovery, and port cleanup with two Android devices. | Needs Physical Verification |

No fixed forward port or shared encoder/stream/input state was found. The singleton controller is an owner of the session collection, not a shared media pipeline. Remaining risk lies in physical identity changes, simultaneous ADB churn, WindowServer display behavior, and device-specific decoder performance.
