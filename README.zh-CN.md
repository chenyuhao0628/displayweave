<p align="center">
  <img src="public/logo.png" width="420" alt="DisplayWeave Logo" />
</p>

<p align="center">
  <a href="README.md">English</a> · <strong>简体中文</strong> ·
  <a href="https://chenyuhao0628.github.io/displayweave/zh.html">中文网站</a>
</p>

# DisplayWeave

**一台 Mac，连接你的每一块屏幕。**

DisplayWeave 是独立维护、开源、本地优先的 macOS 扩展显示项目，可将
iPhone、iPad 或 Android 设备作为 Mac 的第二屏。项目源自 OpenDisplay，
继续遵守 GPL-3.0，并加入 Android 接收端、中文界面、HEVC、H.264 自动
回退、动态帧率协商和实验性 Android 高刷新链路。

## 当前能力

- Apple 接收端：iPhone/iPad，支持 USB（`usbmuxd`）和局域网 WiFi。
- Android 接收端：当前使用局域网 WiFi，支持 HEVC/H.265 和 H.264 回退。
- Android 支持动态 30/60/90/120fps 协商和高刷新显示模式请求。
- 支持触摸、拖动、光标、双指滚动和运行时全链路性能统计。
- OnePlus OPD2413 在 HEVC/120 WiFi 测试中端到端约 109-111 FPS，
  Android 报告 120Hz 显示模式。

Android 高刷新仍属于实验功能。请求 120fps 或启用 120Hz 显示模式，均不
代表能够在所有硬件上稳定渲染满 120 FPS。

## 尚未完成

- Android USB/ADB reverse。
- iOS/iPadOS 120Hz。
- 加密 WiFi 配对。
- 已签名、已公证的 DisplayWeave macOS 正式包。
- 可直接安装到 iPhone/iPad 真机的通用 IPA。
- 所有硬件稳定满 120 FPS。

## 开发预览下载

预览版本：[`v0.1.0-preview.1`](https://github.com/chenyuhao0628/displayweave/releases/tag/v0.1.0-preview.1)

| 平台 | 文件 | 说明 |
| --- | --- | --- |
| macOS | `DisplayWeave-macOS-development-preview.zip` | 仅作本地测试的 ad-hoc 签名，未使用 Developer ID 且未公证 |
| iOS/iPadOS | `DisplayWeave-iOS-Simulator-development-preview.zip` | 仅供 Simulator，不能安装到 iPhone/iPad 真机 |
| Android | `DisplayWeave-Android-debug.apk` | 可安装 Debug APK；当前仅支持 WiFi 传输 |

这些文件用于开发测试，不是正式生产发布包。

## 从源码构建

Apple 工程：

```bash
./generate.sh
xcodebuild -project OpenSidecar.xcodeproj \
  -scheme OpenSidecarMac \
  -configuration Debug \
  -derivedDataPath build-run \
  -clonedSourcePackagesDirPath build-run/SourcePackages \
  build
```

Android：

```bash
cd AndroidReceiver
./gradlew clean
./gradlew assembleDebug
./gradlew test
```

Android Debug APK 输出路径：

```text
AndroidReceiver/app/build/outputs/apk/debug/app-debug.apk
```

## 文档

- [系统架构](ARCHITECTURE.md)
- [开发路线图](ROADMAP.md)
- [Android 接收端](AndroidReceiver/README.md)
- [Android 高刷新迁移与真机数据](docs/120hz-migration-plan.md)
- [开发与验收目标](docs/roadmap-and-acceptance.md)
- [品牌与文档审计](docs/branding-and-doc-audit.md)
- [第三方声明](THIRD_PARTY_NOTICES.md)
- [贡献说明](CONTRIBUTING.md)
- [安全说明](SECURITY.md)

## 来源与许可证

DisplayWeave 是源自
[OpenDisplay](https://github.com/peetzweg/opendisplay) 的独立社区项目，
保留相应 Git 历史、版权署名和 GPL-3.0 义务。高刷新、HEVC 和性能测量
思路参考过 MIT 许可的
[SideScreen](https://github.com/tranvuongquocdat/SideScreen)。详细关系见
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。

DisplayWeave 使用 [GNU GPL-3.0](LICENSE) 发布。
