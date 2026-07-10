# DisplayWeave Android Receiver

Android WiFi receiver for DisplayWeave.

This module lets an Android tablet or phone act as a DisplayWeave receiver for
the Mac sender. It uses a backward-compatible receiver contract: Android NSD
discovery, length-prefixed local WiFi transport, negotiated HEVC/H.264 video,
and JSON control messages for input, configuration, recovery, and liveness.

## Current Status

| Capability | Status |
| --- | --- |
| Android receiver over local WiFi | Completed |
| HEVC/H.265 with H.264 fallback | Completed and physically validated |
| Dynamic 30/60/90/120fps negotiation | Completed; high refresh remains experimental |
| OnePlus HEVC/120 WiFi result | About 109-111 FPS end to end on the tested setup |
| Android USB/ADB reverse | Planned, not implemented |
| Encrypted WiFi pairing | Planned, not implemented |
| Development download | Installable Debug APK in the preview GitHub Release |
| Signed store/release package | Not available; build from source for production trust |

## 中文说明

安卓端的定位是 DisplayWeave 的“平板接收器”，不是独立投屏软件。Mac 端负责创建镜像或扩展显示器、捕获画面、优先编码 HEVC（不可用时回退 H.264）并通过局域网发送；安卓端负责发现/监听、解码、显示画面，并把触摸和滚动事件回传给 Mac。

当前已经实现：

- Android NSD 广播 `_opensidecar._tcp`
- TCP 监听端口 `9000`
- 与 Mac 端兼容的 length-prefixed JSON 控制帧
- HEVC/H.265 与 H.264 Annex B 视频帧接收
- `MediaCodec` 硬件解码到高刷新 `SurfaceView`
- 设备刷新率、最大 FPS、codec 能力协商
- 30/60/90/120fps 动态配置和 H.264/60fps 旧协议 fallback
- 收发、解码、渲染、延迟、队列与丢帧统计
- Mac 鼠标位置绘制
- 轻点、拖拽、双指滚动输入
- 中文启动、状态和设置界面
- 延迟/FPS 状态显示开关
- 原生、均衡、流畅三档画质/分辨率配置

已在本地真机验证：

- Android 平板能出现在 Mac 端 WiFi 设备列表
- Mac 可以通过 WiFi 镜像和扩展到 Android
- HEVC/120 配置能协商并启动硬件解码，Android 物理显示切换到 120Hz
- H.264/60 fallback 能正常解码显示，Android 物理显示切换到 60Hz
- 状态浮层能显示 capture/encode/send/receive/decode/render 全链路统计
- 点击屏幕不会导致 app 退出
- 鼠标位置可以在 Android 屏幕上显示

当前测试 Mac 使用 Metal 持续动画时，真机全链路实测约 109-111 FPS，
证明 120Hz 配置链路、高刷新显示请求和 HEVC 收发解码渲染均生效；结果
仍低于持续满 120 FPS。具体数据和瓶颈记录在
`docs/120hz-migration-plan.md`。

## Receiver Contract

The Android receiver follows this contract:

```text
Android receiver
  advertise _opensidecar._tcp
  listen on TCP :9000
  send hello JSON
  receive streamConfig plus length-prefixed HEVC/H.264 Annex B frames
  render through MediaCodec
  send touch / scroll / ping / keyframe JSON messages
```

Important protocol details:

- Every payload is prefixed with a 4-byte big-endian length.
- JSON control messages and video payloads share the same stream.
- Video frames are HEVC or H.264 Annex B, selected by `streamConfig`.
- Without `streamConfig`, the receiver keeps the legacy H.264/60fps behavior.
- The receiver `hello` includes dimensions, refresh rate, codec capabilities,
  device metadata, and transport.
- Touch coordinates are normalized so the Mac can map them onto the active display.

## Module Layout

```text
app/src/main/java/app/opendisplay/android/
  MainActivity.java              Android UI and SurfaceView host
  OpenDisplayServer.java         protocol, decode queue, metrics, NSD lifecycle
  ReceiverTransport.java         receiver transport boundary
  WifiTcpReceiverTransport.java  framed TCP socket implementation
  H264SurfaceDecoder.java        AVC/HEVC MediaCodec video decode
  CursorOverlayView.java         Mac cursor drawing
  TouchGestureCoordinator.java   tap/drag gesture staging
  ScrollGestureTracker.java      two-finger scroll deltas
  DisplayProfile.java            advertised resolution profiles
  protocol/                      length-prefix, Annex B, SPS, control parsing

scripts/
  build_debug_apk.sh             legacy/manual debug APK builder
  install_debug_apk.sh           local install helper

tests/java/
  ProtocolSelfTest.java          protocol and input behavior checks
```

## Gradle Build

AndroidReceiver is now a standard Android Gradle project with a checked-in
Gradle Wrapper. Use the wrapper from this directory; a system-wide `gradle`
installation is not required.

```bash
cd AndroidReceiver
./gradlew clean
./gradlew assembleDebug
./gradlew test
```

The Gradle project preserves the existing application contract:

- application ID / namespace: `app.opendisplay.android`
- min SDK: 26
- target SDK: 36
- version: `0.1` / versionCode `1`
- manifest, Java sources, and resources stay under `app/src/main`
- the existing plain Java self-tests under `tests/java` are wired into
  `./gradlew test`

`scripts/build_debug_apk.sh` is intentionally kept. It is the original manual
SDK-tools pipeline (`aapt2` -> `javac` -> `d8` -> `apksigner`) and remains a
useful fallback/debugging path, while Gradle Wrapper is the default repeatable
build path.

## Design Notes

- **Surface-first rendering**: `MediaCodec` renders directly to `SurfaceView` to
  avoid extra frame copies.
- **Transport writes are off the UI thread**: `WifiTcpReceiverTransport` owns a
  serialized writer executor, avoiding Android's `NetworkOnMainThreadException`.
- **Transport is isolated**: `OpenDisplayServer` consumes framed payloads via
  `ReceiverTransport`; a future ADB transport can reuse the protocol/decoder.
- **Tap deferral avoids scroll mis-clicks**: single-touch begin events are held
  briefly until the gesture is known; a second finger cancels the pending tap.
- **Display profiles are receiver-driven**: Android can advertise a scaled
  display size so the Mac captures less data for lower-latency WiFi use.
- **Cursor is separate from video**: the Mac sends cursor position and image
  metadata as control messages, and Android draws it as an overlay.

## Known Limits

- Android currently ships only `WifiTcpReceiverTransport`; USB/ADB reverse is
  intentionally deferred to a later transport phase.
- The transport is local-network TCP and is not yet production-grade encrypted pairing.
- Hardware decoder behavior can vary by Android vendor.
- Multi-touch is currently mapped to practical desktop gestures, not a full macOS gesture set.
- Store distribution is not configured.
- A requested 120fps mode or active 120Hz panel does not guarantee sustained
  120 rendered FPS. The current physical validation measured about 109-111 FPS
  on one OnePlus device.

## Verification

Useful local checks:

```bash
cd AndroidReceiver
./gradlew assembleDebug
./gradlew test
AndroidReceiver/scripts/build_debug_apk.sh
```

The self-tests cover length-prefix round trips, capability/stream-config JSON,
AVC/HEVC policy, dynamic FPS, refresh-rate selection, Annex B parsing, queue
classification, telemetry, input handling, and a real loopback round trip
through `WifiTcpReceiverTransport`.

## Upstream Compatibility

This receiver intentionally preserves the inherited OpenDisplay-compatible
wire shape so the Mac sender does not need a separate Android-only streaming
protocol. `app.opendisplay.android`, `OpenDisplayServer`,
`H264SurfaceDecoder`, and `_opensidecar._tcp` are internal compatibility
identifiers, not the user-facing product name. New behavior should continue to
use optional or versioned capability negotiation.
