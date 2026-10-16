[English](README.md) | [简体中文](README.zh-CN.md)

# DisplayWeave Android 接收端

Android 接收端可以通过本地 WiFi 或由 Mac 管理的 ADB-forward USB 接收 DisplayWeave 视频。它协商 HEVC/H.265 或 H.264，请求兼容 30/60/90/120Hz 的模式，通过 MediaCodec/Surface 渲染，并回传触摸/输入与链路指标。

等待页面跟随系统明暗主题。设置在小屏上可滚动；串流时右上角设置按钮始终可用，即使已隐藏状态浮层。

v0.3.0-preview.1 包含[加密配对](../docs/secure-transport.zh-CN.md)与[仅 GitHub 更新](../docs/automatic-updates.zh-CN.md)。首次连接时，在**设置与帮助 → 安全与配对**生成邀请，导入 Mac 后再选择设备。局域网和 ADB 转发 USB 使用相同认证流。

## 要求

- Android 8.0+；硬件 HEVC 支持取决于设备。
- WiFi：Mac 与 Android 位于同一可信局域网，并按系统要求授予附近 WiFi/本地网络发现权限。
- USB：支持数据传输的线缆、开发者选项、USB 调试，以及允许 Mac 的 RSA 身份。

## 安装 `v0.3.0-preview.1`

2026-10-16：本预览版在本地构建，下载仅使用 GitHub Releases；Mac 与 Android 更新元数据使用已恢复访问的项目 GitHub Pages。构建证据及必需的配对迁移见[发布说明](../docs/release-notes-v0.3.0-preview.1.zh-CN.md)。

从 [`v0.3.0-preview.1`](https://github.com/chenyuhao0628/displayweave/releases) 下载 `DisplayWeave-Android.apk`。它是离线 v2 签名 Release APK，无需 Google Play。p5 需要手动覆盖安装一次 p6 或更新版；安装前请验证 `SHA256SUMS.txt` 与[发布检查清单](../docs/release-checklist.zh-CN.md)中的证书指纹。

## 首次安装后的更新

- 接收端回到前台时最多每 24 小时检查一次 HTTPS 更新源。
- “设置与帮助 → 检查更新”不受每日节流限制。
- p6 及以后版本从对应的 GitHub Release 获取 APK。
- 安装前会逐项核对字节数、SHA-256、包名、版本号、最低 SDK 与固定签名证书。
- Android 可能要求授予“安装未知应用”权限；最终安装始终由 Android 系统界面确认，不支持静默安装。
- 拒绝权限或安装不会停止显示接收功能。

## 连接

1. 打开 DisplayWeave Receiver，让显示 Surface 保持可见。
2. 在 Mac 选择 **Auto**（推荐）、**USB** 或 **WiFi**。
3. USB 模式连接线缆并允许 Android RSA 对话框。只有有线 ADB 行具备资格，无线调试 ADB 端点会被忽略。
4. Auto 优先 USB；真实故障后执行协议宽限与有限恢复，之后只可回退到 install ID 相同的 WiFi。线缆恢复后会重新升级 USB。
5. 从 Android 桌面返回接收端时，Surface 会重建、listener 会幂等重启；Mac 先重发 `streamConfig`，再请求关键帧。

USB 模式不会静默变成 WiFi，WiFi 模式不会创建 ADB forward。

## Decoder 低延迟

“**设置与帮助 → 解码器低延迟**”默认使用“自动”。Auto/On 只会在 API 30+ 的实际 Decoder 明确声明支持时请求 MediaCodec Low Latency；若参数被拒绝，会在同一 Decoder 上关闭 Low Latency 重试。Off 不会设置该参数。修改此设置会重建一次 Receiver Session。参见 [Decoder 低延迟策略](../docs/android-decoder-low-latency.zh-CN.md)。

## WiFi 与显示延迟提示

“**设置与帮助 → WiFi 低延迟**”默认使用“自动”。API 29+ 上，Auto/On 仅在 App 位于前台、Surface 有效、视频已进入 Streaming 且 Mac 实际 Transport 为 WiFi 时持有 `WIFI_MODE_FULL_LOW_LATENCY`；USB、断开、后台、Surface 丢失和 App 退出都会释放。Surface 帧率提示使用 Fixed-source 与 Only-if-seamless 行为，在 Surface/Config/Decoder 生命周期事件重应用，并在停止 Streaming 时清理。参见 [WiFi 低延迟与 Surface 帧率](../docs/android-wifi-low-latency-surface-frame-rate.zh-CN.md)。

## Drop 归因

Receiver Stats 保留 Android 汇总 Drop，同时发布按原因拆分的窗口/累计计数，以及最后一次 Drop 的连接/配置/帧身份。Auto Bitrate 忽略 Lifecycle、Stale、Malformed、Transport 和 Reconfiguration Drop；已分类 Decoder Throughput Pressure 必须持续两个窗口才可降低码率。参见 [Android Drop 原因策略](../docs/android-drop-reason-policy.zh-CN.md)。

## 构建与测试

```bash
cd AndroidReceiver
./gradlew clean test assembleDebug
```

Debug APK：

```text
app/build/outputs/apk/debug/app-debug.apk
```

Release 打包与签名由仓库根目录脚本协调：

```bash
./tools/package-preview-0.1.sh
```

Keystore 保存在 Git 之外，密码从 macOS Keychain 读取。除非明确接受破坏覆盖安装兼容性，否则不要为已公开包身份生成新密钥。

## 协议与生命周期

- 接收端 TCP Server：Android 端口 `9000`。
- USB：Mac `127.0.0.1:<动态端口>` → `adb forward` → Android `tcp:9000`。
- WiFi：Mac 直接连接广播的局域网地址。
- 视频：带 `streamConfig` 的长度前缀帧；支持时优先 HEVC，能力/codec 失败后回退 H.264。
- 输入：轻点、拖动、光标和双指滚动 JSON。
- 恢复：listener/Surface 操作幂等；必须收到对端协议消息才视为就绪，而不只是 TCP connect。

## Preview 2 既有验证行为

- OnePlus USB HEVC/120 与 H.264/60。
- 回到前台、强停重开、ADB Server 重启、线缆拔插及取消/恢复授权。
- Auto USB→同 install ID WiFi 在完整恢复序列后切换，该次观察约 26 秒；线缆返回后升级 USB。
- USB 触摸与双指滚动。
- 当前 iPhone WiFi 与一台 Android 会话并发。

双 Android 并发、受控 USB/WiFi Benchmark 及 30 分钟/2 小时耐久尚未完成。

## 安全

本版默认使用固定证书指纹的双向 TLS 与邀请配对；不安全的旧版兼容需要在本机显式开启。传输私钥保存在 Android Keystore，与 APK 签名独立。ADB 授权会把 Mac 作为超出本应用范围的调试主机信任。参见[配对指南](../docs/secure-transport.zh-CN.md)与 [SECURITY.zh-CN.md](../SECURITY.zh-CN.md)。
