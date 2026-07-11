# DisplayWeave Roadmap

## 中文摘要

- **已完成：** Android WiFi 接收端、HEVC/H.264 回退、动态
  30/60/90/120fps 协商、高刷新显示请求、队列恢复和全链路统计。
- **已验证：** OnePlus OPD2413 在 HEVC/120 WiFi 下端到端约
  109-111 FPS，Android 显示模式为 120Hz；不等于稳定满 120 FPS。
- **已实现、待真机验证：** Android ADB forward USB、每设备动态端口、
  Auto 优先 USB、有限恢复与同 install ID WiFi 回退。
- **下一步：** 长时间稳定性、异常恢复、USB/WiFi 基准、多设备测试矩阵和
  正式发布准备。
- **未来能力：** 加密 WiFi 配对、iOS/iPadOS 120Hz；这些目前都不是已支持功能。

DisplayWeave is an independently maintained, GPL-3.0, local-first second-display
project derived from OpenDisplay. This roadmap separates the verified baseline
from current priorities and future capabilities so completed work is not
mistaken for a promise or a pending feature.

## Completed Baseline

- macOS sender with mirror and virtual extended-display modes.
- iPhone and iPad H.264 receivers over USB (`usbmuxd`) or local WiFi.
- Android receiver over local WiFi with NSD discovery and framed TCP transport.
- Android USB implementation using per-serial dynamic `adb forward` mappings;
  physical-device and multi-device acceptance remain pending.
- Optional capability negotiation and backward-compatible `streamConfig`.
- Android HEVC/H.265 hardware decoding with automatic H.264 fallback.
- Dynamic Android 30/60/90/120fps selection and refresh-rate requests.
- Latest-frame-oriented queueing, keyframe recovery, and codec-failure recovery.
- Runtime capture, encode, send, receive, decode, render, queue, drop, and
  latency/frame-age telemetry.
- Physical-device validation on a OnePlus OPD2413: HEVC/120 over WiFi measured
  about 109-111 FPS end to end while Android reported an active 120Hz mode.
- Explicit H.264/60 fallback validation on the same test path.
- Standard Android Gradle Wrapper build plus retained manual SDK-tools builder.

The Android high-refresh path remains experimental. The completed baseline
does not mean stable 120 rendered FPS on every Mac, network, decoder, or panel.

## Next Priorities

### Stability And Recovery

- Run repeatable 10-minute, 30-minute, and 2-hour sessions.
- Validate reconnects after app restart, background/foreground transitions,
  screen lock, WiFi interruption, Mac sleep, and Android surface recreation.
- Track memory, CPU, temperature, queue growth, frame age, codec failures, and
  keyframe-request loops.
- Expand decoder-quirk documentation across more Android vendors and 60/90/120Hz
  hardware.

### Measurement And Diagnostics

- Add reproducible benchmark profiles and structured CSV or JSONL export.
- Distinguish requested FPS, selected FPS, physical display refresh, produced
  content FPS, and each measured pipeline stage in diagnostics and reports.
- Improve end-to-end latency correlation without fabricating unavailable data.
- Publish a multi-device test matrix before making stronger mixed-device claims.

### Release Readiness

- Complete DisplayWeave-native icon and screenshot production assets.
- Establish macOS signing, notarization, update-feed ownership, and release
  verification before publishing downloadable packages.
- Align iOS distribution metadata and signing with the DisplayWeave identity.
- Keep source builds as the documented path until signed packages exist.

## Future Capabilities

- Encrypted WiFi pairing, peer authentication, and key lifecycle management.
- Independent iOS/iPadOS high-refresh and 120Hz evaluation. This is planned and
  is not currently supported.
- Broader HEVC compatibility and fallback validation across Android devices.
- More complete gesture mapping, including platform-appropriate multi-touch.
- Better display-profile and bitrate adaptation under changing network load.
- Carefully validated simultaneous Apple and Android receiver scenarios.

## Non-Goals For Now

- Remote desktop over the public internet.
- Audio forwarding.
- Claims of stable 120 FPS across all hardware.
- Closed-source redistribution that conflicts with GPL-3.0 obligations.

Detailed acceptance criteria live in
[`docs/roadmap-and-acceptance.md`](docs/roadmap-and-acceptance.md). Historical
implementation phases and the OnePlus measurements are recorded in
[`docs/120hz-migration-plan.md`](docs/120hz-migration-plan.md).
