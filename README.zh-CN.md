[English](README.md) | [简体中文](README.zh-CN.md)

# DisplayWeave

**一台 Mac，织起一片可用屏幕。**

DisplayWeave 是独立维护、使用 GPL-3.0、坚持本地优先的第二屏项目，源自 [OpenDisplay](https://github.com/peetzweg/opendisplay)。它可以把 iPhone、iPad 和 Android 设备变成 Mac 的扩展或镜像显示器。

## Preview 2 当前能力

- Apple 接收端：通过 `usbmuxd` 使用 USB，或使用本地 WiFi；采用 H.264 链路。
- Android 接收端：支持本地 WiFi 或每设备动态 `adb forward` USB，支持 HEVC/H.265、H.264 回退与 30/60/90/120fps 协商。
- 传输选择：Auto、USB 或 WiFi。Auto 优先有线 USB，进行有限恢复，只回退到 install ID 相同的 WiFi，并在线缆恢复后升级回 USB。
- 输入：轻点、拖动、光标和双指滚动可回传 macOS。
- 恢复：已在现有 OnePlus Android 真机验证接收端回到前台/Surface 返回、拔插线缆、ADB 重启及取消/恢复授权。
- 混合接收端：当前 DisplayWeave iPhone WiFi 与一台 Android 可并发运行。
- 运行证据：采集、编码、发送、接收、解码、渲染、队列、丢帧和延迟指标。
- 性能控制：Auto/Manual/实验性 Benchmark 码率、受限自适应调节、按画质区分的发送队列和按传输区分的关键帧周期。

Android 高刷新仍属实验功能。一台 OnePlus 在 HEVC/120 WiFi 下实测约 109–111 渲染 FPS；这不代表其他设备或条件可以稳定满 120 FPS。

## 下载 `v0.1.0-preview.2`

[GitHub Release](https://github.com/chenyuhao0628/displayweave/releases/tag/v0.1.0-preview.2)

| 平台 | 产物 | 分发边界 |
| --- | --- | --- |
| macOS | `DisplayWeave-Preview-0.1-macOS.zip` | 通用 ad-hoc 签名，未使用 Developer ID 且未公证 |
| Android | `DisplayWeave-Preview-0.1-Android.apk` | 使用项目 Preview 密钥进行 v2 离线签名，无需 Google Play 账号 |
| iOS/iPadOS | `DisplayWeave-Preview-0.1-iOS-unsigned-resigning-input.ipa` | 未签名自签输入包，不能直接安装 |
| 验证 | `SHA256SUMS.txt` | 三个平台包的 SHA-256 |

这是开发预览版，不是生产签名的商店版本。使用前请验证校验和；Android 用户还应核对[发布检查清单](docs/release-checklist.zh-CN.md)中的证书指纹。

新版 Mac 构建使用 DisplayWeave 自有应用身份。设置会从旧 OpenDisplay/OpenSidecar 偏好域迁移，但升级后需要在 macOS 重新授予屏幕录制、辅助功能和本地网络权限。

## Android USB 快速开始

1. 在 Android 设备启用开发者选项和 USB 调试。
2. 使用支持数据传输的线缆连接，打开 DisplayWeave Receiver，并允许 Mac 的 RSA 调试身份。
3. 在 Mac 打开 DisplayWeave，选择 **Auto**（推荐）或 **USB**。
4. Auto 只使用真正带 `usb:` 元数据的 ADB 有线设备；无线调试端点不会创建 USB 会话。
5. 拔线后，Auto 会完成协议宽限与有限恢复，再回退到同一应用安装实例的 WiFi；USB 模式不会静默回退。

ADB 授权会向 Mac 提供广泛调试权限，而不只限于 DisplayWeave。不再需要时请在 Android 开发者选项中撤销。

## 从源码构建

Apple 目标：

```bash
./generate.sh
xcodebuild -project OpenSidecar.xcodeproj -scheme OpenSidecarMac \
  -configuration Debug -derivedDataPath build-run \
  -clonedSourcePackagesDirPath build-run/SourcePackages build
```

Android：

```bash
cd AndroidReceiver
./gradlew clean test assembleDebug
```

生成完整离线 Preview 产物：

```bash
./tools/package-preview-0.1.sh
```

Android Release 签名密钥库保存在仓库外。参见[开发预览分发](docs/development-preview.zh-CN.md)。

## 文档

- [文档索引](docs/README.zh-CN.md)
- [系统架构](ARCHITECTURE.zh-CN.md)
- [路线图](ROADMAP.zh-CN.md)
- [Android 接收端](AndroidReceiver/README.zh-CN.md)
- [发布检查清单](docs/release-checklist.zh-CN.md)
- [稳定性证据](docs/stability-test-report.zh-CN.md)
- [USB/WiFi Benchmark 规程](docs/usb-vs-wifi-benchmark.zh-CN.md)
- [码率模式](docs/bitrate-modes.zh-CN.md)与[自适应码率](docs/adaptive-bitrate.zh-CN.md)
- [队列分析](docs/low-latency-queue-analysis.zh-CN.md)与[关键帧策略](docs/keyframe-strategy.zh-CN.md)
- [安全说明](SECURITY.zh-CN.md)
- [贡献说明](CONTRIBUTING.zh-CN.md)
- [第三方声明](THIRD_PARTY_NOTICES.md)

## 当前限制

- iOS/iPadOS 120Hz 尚未实现。
- 当前 WiFi TCP 视频/控制流量尚未生产级加密，请仅在可信局域网使用。
- 双 Android 并发、同条件 USB/WiFi 受控 Benchmark，以及 30 分钟/2 小时耐久测试尚未完成。
- macOS 使用私有 `CGVirtualDisplay` 行为，未来 macOS 版本可能发生变化。
- 公开 macOS 与 iOS 包未使用 Developer ID/App Store 签名。

## 来源与许可证

DisplayWeave 保留适用的 OpenDisplay 历史、版权声明和 GPL-3.0 义务。部分高刷新与测量思路参考了 MIT 许可的 SideScreen。详见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。DisplayWeave 本身按 [GPL-3.0](LICENSE) 分发。
