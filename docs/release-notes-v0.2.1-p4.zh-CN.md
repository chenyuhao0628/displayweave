[English](https://github.com/chenyuhao0628/displayweave/blob/main/docs/release-notes-v0.2.1-p4.md) | [简体中文](https://github.com/chenyuhao0628/displayweave/blob/main/docs/release-notes-v0.2.1-p4.zh-CN.md)

# DisplayWeave `v0.2.1-p4` 发布说明

DisplayWeave 0.2.1-p4 修复 WiFi 与 Android USB 重连失败后接收端可能停留在“配置解码器中”的问题。

## 改动

- Android 每次应用串流配置后都会请求替换关键帧，包括新解码器使用默认 H.264/60 配置的情况。
- VideoToolbox 回调状态成功但没有 Sample Buffer 时，将其视为丢帧而不是编码器失败。
- 避免空成功回调触发错误的编码器降级和重连风暴。
- 为两个重连边界条件增加确定性的 Android 与 macOS 回归测试。

## 验证

- 22 套 macOS 独立 Self Test 全部通过。
- Android 单元测试与 Debug APK 构建通过。
- macOS Debug App 的 Xcode 构建通过。
- 在 OnePlus Android 真机上，中断 ADB USB Forward 后能够自动重建，串流恢复到约 57–58 渲染 FPS。
- 同一设备通过 WiFi 连接时，强制停止并重启接收端会建立新会话，完成解码器配置并恢复到约 57–58 渲染 FPS。
- 多次自适应串流重配均依次进入 `decoderReady`、`waitingFirstFrame` 和 `streaming`，不会停留在配置解码器状态。
- `git diff --check` 通过。

macOS App 仍采用 Ad-hoc 签名且未公证；Android 使用固定的 DisplayWeave Release 证书签名。

## SHA-256

- Android APK：`221dac7f6ee6e59edbf76a30c4f2a70f279ec82f4d588b5c6e24f9226b0279c4`
- macOS ZIP：`4e8e7d9bf8a72d447b4d3f9bad45df1739dbfbb7f02f114145d928e1269a9ff8`
- macOS DMG：`6013fc4c11459925591e1caec82b6702f2acd5c5a3df2ed3c0ead6a071aac8f0`
- iOS 未签名自签输入包：`10ff8351f8c553f6b06c18eed6c03b8c3fa350c5a916af24aae299901cfa5cf0`
- Sparkle Appcast：`1b295cb241576eb2eca475c1494ea89e57027f8351e377f5636db6018f7870f8`
- Android 更新清单：`1803ff3710db76afec2ff88f80151427c888c862d8e22f644bf869beada52f71`
