[English](README.md) | [简体中文](README.zh-CN.md)

# DisplayWeave Android 接收端

Android 接收端可以通过本地 WiFi 或由 Mac 管理的 ADB-forward USB 接收 DisplayWeave 视频。它协商 HEVC/H.265 或 H.264，请求兼容 30/60/90/120Hz 的模式，通过 MediaCodec/Surface 渲染，并回传触摸/输入与链路指标。

## 要求

- Android 8.0+；硬件 HEVC 支持取决于设备。
- WiFi：Mac 与 Android 位于同一可信局域网，并按系统要求授予附近 WiFi/本地网络发现权限。
- USB：支持数据传输的线缆、开发者选项、USB 调试，以及允许 Mac 的 RSA 身份。

## 安装 `v0.2.0-preview.2`

从 [`v0.2.0-preview.2`](https://github.com/chenyuhao0628/displayweave/releases/tag/v0.2.0-preview.2) 下载 `DisplayWeave-Android.apk`。它是离线 v2 签名 Release APK，无需 Google Play。先把它覆盖安装到现有 `app.opendisplay.android` 包；安装前请验证 `SHA256SUMS.txt` 与[发布检查清单](../docs/release-checklist.zh-CN.md)中的证书指纹。

## 首次安装后的更新

- 接收端回到前台时最多每 24 小时检查一次 HTTPS 更新源。
- “设置与帮助 → 检查更新”不受每日节流限制。
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

WiFi TCP 尚未生产级加密，请使用可信局域网。ADB 授权会把 Mac 作为超出本应用范围的调试主机信任。参见 [SECURITY.zh-CN.md](../SECURITY.zh-CN.md)。
