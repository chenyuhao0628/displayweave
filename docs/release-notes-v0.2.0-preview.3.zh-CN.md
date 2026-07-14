[English](release-notes-v0.2.0-preview.3.md) | [简体中文](release-notes-v0.2.0-preview.3.zh-CN.md)

# DisplayWeave `v0.2.0-preview.3` 发布说明

[GitHub prerelease](https://github.com/chenyuhao0628/displayweave/releases/tag/v0.2.0-preview.3)

## Android 连接恢复

- 独立 Accept Loop 允许新的 WiFi 或 ADB Forward Socket 立即替换阻塞或
  Half-open 的旧连接。
- Connection Generation 隔离旧 Reader、Writer、Decoder、Error 与
  Disconnect Callback，旧连接不能停止 Current Stream。
- 启用 TCP No-delay 与 Keepalive；应用层恢复仍保持有限，并通过 Receiver
  Connection-state Model 明确可观测。
- Android 后台与 Surface 关闭继续使用既有有限重连宽限；Legacy Apple
  Receiver 正常退出仍会立即结束其 Session。

## 可协商 Android Protocol V2

- Android 将 StreamConfig Ack、Decoder Ready、First Frame Rendered、
  Session Epoch、Config Version 与 Frame Sequence 作为完整 Capability Set
  声明；Capability 不完整时安全回退 Legacy Path。
- Mac 仅在收到匹配的首帧 Render 后报告 Streaming。Ack、Decoder 和首帧
  Timeout 共用两次 Retry，跨连接最多再重试一次。
- Epoch、Version 与 Sequence Check 会在 Frame 进入 MediaCodec 或当前
  Stats 前拒绝旧 Config 与旧 Frame。
- 仅码率变化时复用兼容 MediaCodec；Codec、FPS 或尺寸变化时替换 Decoder，
  且不会阻塞 Network Event Executor。
- Negotiated Decoder Reset 会先请求 Fresh StreamConfig、再请求 IDR，保证
  重建 Decoder 使用新的 Config Version。

## Legacy 兼容

OpenDisplay iOS Receiver 继续使用现有 Length Prefix、Legacy StreamConfig、
JSON Telemetry Prefix、Annex-B H.264、Hello、Input、Ping/Pong 与 Goodbye。
只有 Android Peer 明确声明全部必需 Capability 时才启用 Protocol V2。

## 验证范围

Android 完整 61-task Build、全部 6 组 Android Self Test、Mac Protocol 与
Transport 聚焦测试、macOS Debug、未签名 iOS Simulator Debug、网站构建、
双语文档检查及 Release-link 检查均通过。

OnePlus OPD2413 的短时 ADB USB HEVC/120 检查完成 Ack、Decoder Ready、
First Frame、连续仅码率 Config 与竞争 Socket 接管。观察到的 191 ms 与
218 ms StreamConfig-to-first-frame 是恢复样本，不是同条件性能结论。WiFi
60/120、USB 60、旧 TestFlight Runtime 兼容及受控 A/B 仍待验证。

## 应用内更新

Mac build 4 通过 EdDSA 认证的 Sparkle Feed 提供；Android version code 4
通过固定证书 Update Manifest 提供。Mac 应用仍为 ad-hoc 签名且未公证；
iOS 产物仍是未签名自签输入包，不使用自动更新。

Release 提供 `DisplayWeave-macOS.dmg`、`DisplayWeave-macOS.zip`、
`DisplayWeave-Android.apk`、未签名 iOS 自签输入包、签名 Update Feed 和
`SHA256SUMS.txt`。使用前请核对 Release 中的校验和。

## SHA-256

| 产物 | SHA-256 |
| --- | --- |
| `DisplayWeave-macOS.dmg` | `68b3737f09f8d02da135aef89167896aa4057d453d65fa20861e2ae58a142a29` |
| `DisplayWeave-macOS.zip` | `32cade719d825d3f3562483cb72b9a4d65223e4b2518d54389ff2d661a1742ae` |
| `DisplayWeave-Android.apk` | `98356346793932bd494a31585ff7ca788b880bd62cd6b8e2762aadc8ff0541c1` |
| `DisplayWeave-Preview-0.1-iOS-unsigned-resigning-input.ipa` | `7eb93eedd24e44bbabccb38ab145a2e2122e4c53bd52dbe8e9d2b3d08e21eb16` |
| `appcast.xml` | `3606e4f32678319f1bcea1e94e97bcba1a1171a6810ed935be3b00264f4795c8` |
| `android-update.json` | `90adbfe6345de384c8541b986673cae28c256a6cef8017e000fb93ff7cfdbf70` |
