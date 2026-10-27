[English](README.md) | [简体中文](README.zh-CN.md)

# DisplayWeave

**一台 Mac，织起一片可用屏幕。**

DisplayWeave 是独立维护、使用 GPL-3.0、坚持本地优先的第二屏项目，源自 [OpenDisplay](https://github.com/peetzweg/opendisplay)。它可以把 iPhone、iPad 和 Android 设备变成 Mac 的扩展或镜像显示器。

## Mac 与 Mac（v0.3.3 实验功能）

同一应用可选择发送或接收，通过 Wi-Fi/以太网单向扩展或镜像。双方需 macOS 14+，
应用协商硬件 HEVC，并可回退 H.264，在屏幕/编码能力内最高协商 120fps；实体双 Mac 性能矩阵待验证。此功能已包含在下方 `v0.3.3`
发布包内。参见[使用指南](docs/guides/mac-to-mac.zh-CN.md)及[设计与上游评估](docs/reference/mac-to-mac-design.zh-CN.md)。

本版本还包含四端 UI 规范化、上游恢复改进和网络/生命周期加固；该批基线见[源码升级报告](docs/archive/audits/source-upgrade-audit-2026-10-16.zh-CN.md)。本版本包含自 p7 引入的 [Mac HEVC、绑定接口的直连发现与经协商的 Apple Pencil 输入](docs/guides/hevc-wired-pencil.zh-CN.md)；实机验收仍待完成。

本版本还包含[按设备分辨率](docs/guides/desktop-resolution.zh-CN.md)、[安全配对](docs/guides/secure-transport.zh-CN.md)、[经许可的 Mac 键鼠回传](docs/guides/mac-receiver-input.zh-CN.md)、[有线/Wi-Fi 切换](docs/guides/mac-lan-handover.zh-CN.md)与[高级 Pencil](docs/guides/pencil-advanced.zh-CN.md)。DisplayWeave 连接使用接收邀请；旧 OpenDisplay 可从主界面选择兼容连接，详见[互连指南](docs/guides/opendisplay-compatibility.zh-CN.md)。

## 当前能力

- iOS/iPadOS 接收端：通过 `usbmuxd` 使用 USB，或使用本地 WiFi；采用硬件条件下的 HEVC，并可回退 H.264。
- Android 接收端：支持本地 WiFi 或每设备动态 `adb forward` USB，支持 HEVC/H.265、H.264 回退与 30/60/90/120fps 协商。
- 传输选择：Auto、USB 或 WiFi。Auto 优先有线 USB，进行有限恢复，只回退到 install ID 相同的 WiFi，并在线缆恢复后升级回 USB。
- 输入：轻点、拖动、光标和双指滚动可回传 macOS。
- 恢复：已在现有 OnePlus Android 真机验证接收端回到前台/Surface 返回、拔插线缆、ADB 重启及取消/恢复授权。
- 混合接收端：当前 DisplayWeave iPhone WiFi 与一台 Android 可并发运行。
- 运行证据：采集、编码、发送、接收、解码、渲染、队列、丢帧和延迟指标。
- 性能控制：Auto/Manual/实验性 Benchmark 码率、受限自适应调节、按画质区分的发送队列和按传输区分的关键帧周期。

Android 高刷新仍属实验功能。一台 OnePlus 在 HEVC/120 WiFi 下实测约 109–111 渲染 FPS；这不代表其他设备或条件可以稳定满 120 FPS。

下述真机恢复与高刷新观察来自 Preview 2 验证，继续作为既有证据；本版本没有在第二台 Android 上重新执行这些项目。

## 下载 `v0.3.3`

[GitHub Release](https://github.com/chenyuhao0628/displayweave/releases)

2026-10-27：构建 22 根据可用的发送端和接收端显示器数据自动匹配 Mac 扩展桌面。已有安装保留旧设置，需选择一次“自动匹配”。目前不支持原生 5K 视频，客户双 Mac 实机验收尚未完成，见[发布说明](docs/releases/v0.3.3.zh-CN.md)。

| 平台 | 产物 | 分发边界 |
| --- | --- | --- |
| macOS | `DisplayWeave-macOS.dmg` | 推荐的引导式首次安装包；固定 Apple Development 签名，未公证 |
| macOS 更新 | `DisplayWeave-macOS.zip` | Sparkle 更新包，也可作为等价的手动安装选项 |
| Android | `DisplayWeave-Android.apk` | 离线 v2 签名 APK；后续应用内下载会先验证，再由系统确认 |
| iOS/iPadOS | `DisplayWeave-iOS-unsigned-resigning-input.ipa` | 未签名自签输入包，不能直接安装 |
| Mac 更新源 | `appcast.xml` | 由 Mac 应用内置公钥认证的 Sparkle 更新源 |
| Android 更新源 | `android-update.json` | 包含大小、哈希、版本、包名与固定证书的 HTTPS 元数据 |
| 源码 | `DisplayWeave-v0.3.3-source.tar.gz` | 对应发行 tag 的完整跟踪源码，包含 GPL-3.0 与构建脚本 |
| 验证 | `SHA256SUMS.txt` | 其余七个 Release 文件的 SHA-256 |

这是正式版；Mac 沿用 Apple Development 签名且未公证，iOS 仍需自行签名。使用前请验证校验和；Android 用户还应核对[发布检查清单](docs/releases/release-checklist.zh-CN.md)中的证书指纹。

新的 Mac 打包流程会同时生成 `DisplayWeave-macOS.dmg` 和 ZIP。DMG 是推荐的
首次安装包：把 DisplayWeave 拖入“应用程序”，并按照背景中
显示的首次运行说明操作。ZIP 继续作为 Sparkle 更新包，也可以手动解压安装。两种
容器里是同一个 `DisplayWeave.app`，放入 `/Applications` 后都能收到后续 Sparkle
更新。

Mac 保留 `app.displayweave.mac` 和既有偏好迁移。从旧临时签名版本首次升级到固定签名时，可能需要再授权一次；后续构建保持相同签名身份。本机 17 → 17.1 覆盖安装已验证屏幕录制、辅助功能权限保留，详见[权限延续](docs/guides/mac-permissions.zh-CN.md)的证据与边界。

### 一次性迁移与后续更新

- **Mac：** 手动用此版本替换 `/Applications` 中的旧应用。Gatekeeper
  可能要求按住 Control 点击并选择“打开”，或在“隐私与安全性”中选择
  “仍要打开”；不需要全局开启“任何来源”。后续版本通过 Sparkle 检查和
  验证；本版使用 Apple Development 签名，仍未公证。
- **Android：** 先把此 APK 覆盖安装到现有包。之后接收端最多每天自动
  检查一次，也可在“设置与帮助”手动检查。下载会校验大小、SHA-256、
  包名、版本、最低 SDK 和固定签名证书，再打开 Android 系统安装器。p6 及以后
  下载统一来自对应的 GitHub Release。
- **iOS/iPadOS：** 未签名自签输入包与现有 OpenDisplay 接收协议不受
  Mac/Android 更新渠道影响。

迁移与恢复说明见[自动更新](docs/releases/automatic-updates.zh-CN.md)。

## Android USB 快速开始

1. 在 Android 设备启用开发者选项和 USB 调试。
2. 使用支持数据传输的线缆连接，打开 DisplayWeave Receiver，并允许 Mac 的 RSA 调试身份。
3. 在 Mac 打开 DisplayWeave，选择 **Auto**（推荐）或 **USB**。
4. Auto 只使用真正带 `usb:` 元数据的 ADB 有线设备；无线调试端点不会创建 USB 会话。
5. 拔线后，Auto 会完成协议宽限与有限恢复，再回退到同一应用安装实例的 WiFi；USB 模式不会静默回退。

ADB 授权会向 Mac 提供广泛调试权限，而不只限于 DisplayWeave。不再需要时请在 Android 开发者选项中撤销。

## 从源码构建

Mac 开发使用明确选定的已有 Apple 身份。把占位符换成证书 SHA-1；只编译、不签名的检查命令见[开发指南](docs/development/workflow.zh-CN.md)：

```bash
security find-identity -v -p codesigning
python3 tools/mac_signing.py configure --identity CERTIFICATE_SHA1
./script/build_and_run.sh
```

Android：

```bash
cd AndroidReceiver
./gradlew clean test assembleDebug
```

使用 `tools/package-release.sh` 生成离线产物：

请按完整的[正式版打包流程](docs/releases/local-release.zh-CN.md)设置明确版本／构建号并提供上一版签名应用。

打包命令需要已配置的 Mac 身份与 Git 外的 Android keystore。正式发布新版本时，按[本地发行](docs/releases/local-release.zh-CN.md)明确设置版本／构建号并比较升级基线。

## 文档

- [目录结构与清理](docs/development/repository-layout.zh-CN.md)
- [构建／安装 iOS 接收端](docs/guides/build-ios.zh-CN.md)
- [文档索引](docs/README.zh-CN.md)
- [系统架构](ARCHITECTURE.zh-CN.md)
- [路线图](ROADMAP.zh-CN.md)
- [Android 接收端](AndroidReceiver/README.zh-CN.md)
- [发布检查清单](docs/releases/release-checklist.zh-CN.md)
- [稳定性证据](docs/archive/audits/stability-test-report.zh-CN.md)
- [USB/WiFi Benchmark 规程](docs/verification/usb-vs-wifi-benchmark.zh-CN.md)
- [码率模式](docs/reference/bitrate-modes.zh-CN.md)与[自适应码率](docs/reference/adaptive-bitrate.zh-CN.md)
- [队列分析](docs/reference/low-latency-queue-analysis.zh-CN.md)与[关键帧策略](docs/reference/keyframe-strategy.zh-CN.md)
- [安全说明](SECURITY.zh-CN.md)
- [贡献说明](CONTRIBUTING.zh-CN.md)
- [第三方声明](THIRD_PARTY_NOTICES.md)

## 当前限制

- 已包含 [Apple HEVC / 高刷协商](docs/guides/apple-video.zh-CN.md)，实机 120fps 性能尚未验证。
- 新连接需要[认证 TLS 配对](docs/guides/secure-transport.zh-CN.md)，USB 隧道也相同；旧版客户端需要在可信网络中显式启用未加密旧版兼容。
- 双 Android 并发、同条件 USB/WiFi 受控 Benchmark，以及 30 分钟/2 小时耐久测试尚未完成。
- macOS 使用私有 `CGVirtualDisplay` 行为，未来 macOS 版本可能发生变化。
- Mac 桌面自动匹配是估算；Apple 视频仍限制在 4096×2304，因此 5K 大小桌面仍可能发软。
- 公开 macOS 与 iOS 包未使用 Developer ID/App Store 签名。

## 来源与许可证

DisplayWeave 保留适用的 OpenDisplay 历史、版权声明和 GPL-3.0 义务。部分高刷新与测量思路参考了 MIT 许可的 SideScreen。详见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。DisplayWeave 本身按 [GPL-3.0](LICENSE) 分发。
