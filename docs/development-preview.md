# DisplayWeave v0.1.0-preview.1

Development preview / 开发预览版

## Downloads / 下载

| File | Purpose | Limitation |
| --- | --- | --- |
| `DisplayWeave-macOS-development-preview.zip` | macOS sender app | Ad-hoc signed for local testing; not Developer ID signed or notarized |
| `DisplayWeave-iOS-Simulator-development-preview.zip` | iOS/iPadOS receiver for Xcode Simulator | Simulator only; cannot be installed on an iPhone or iPad |
| `DisplayWeave-Android-debug.apk` | Android receiver | Installable Debug APK; local WiFi transport only |

| 文件 | 用途 | 限制 |
| --- | --- | --- |
| `DisplayWeave-macOS-development-preview.zip` | macOS 发送端 | 仅作本地测试的 ad-hoc 签名，未使用 Developer ID 且未公证 |
| `DisplayWeave-iOS-Simulator-development-preview.zip` | Xcode Simulator 的 iOS/iPadOS 接收端 | 仅支持模拟器，不能安装到 iPhone/iPad 真机 |
| `DisplayWeave-Android-debug.apk` | Android 接收端 | 可安装 Debug APK；当前仅支持局域网 WiFi |

## Current Status / 当前状态

- Android HEVC/H.265 with automatic H.264 fallback.
- Dynamic Android 30/60/90/120fps negotiation and display-mode requests.
- OnePlus OPD2413 HEVC/120 WiFi validation measured about 109-111 FPS end to end.
- Android high refresh remains experimental and does not guarantee stable 120 FPS.
- Android USB/ADB reverse, encrypted WiFi pairing, and iOS/iPadOS 120Hz are not implemented.

- Android 已支持 HEVC/H.265 和 H.264 自动回退。
- Android 已支持动态 30/60/90/120fps 协商与显示模式请求。
- OnePlus OPD2413 的 HEVC/120 WiFi 真机验证约为 109-111 FPS。
- Android 高刷新仍是实验功能，不保证稳定满 120 FPS。
- Android USB/ADB reverse、加密 WiFi 配对和 iOS/iPadOS 120Hz 尚未实现。

DisplayWeave is GPL-3.0 and independently maintained, derived from OpenDisplay.
See `THIRD_PARTY_NOTICES.md` for origin and SideScreen reference details.

## SHA-256

```text
9b7f08e25d4af48f41ecd0d432b481e72e58ce1e034557b9bb42b68a9067ef15  DisplayWeave-macOS-development-preview.zip
2833a00437ef2cd9146f837f121e624365af08e0c2ccff6b98305f1ef94fdd77  DisplayWeave-iOS-Simulator-development-preview.zip
86cf63c7af12a21a48d8c63c0b398df92a7954004a39067e9bd69db44aaba62c  DisplayWeave-Android-debug.apk
```
