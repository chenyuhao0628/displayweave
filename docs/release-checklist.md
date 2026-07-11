# DisplayWeave Preview 0.1 Release Checklist

审计日期：2026-07-11
目标版本：DisplayWeave Preview 0.1
实现分支：`codex/android-adb-usb`

状态说明：`通过` 表示有本轮直接证据；`待人工验证` 表示需要真机或交互；`阻塞` 表示不能发布对应正式产物。

## Android

| 项目 | 状态 | 证据 / 下一步 |
| --- | --- | --- |
| Clean build | 通过 | `./gradlew clean test assembleRelease`，67 tasks，BUILD SUCCESSFUL |
| Unit/self tests | 通过 | `ProtocolSelfTest PASS`、`VideoStreamPolicySelfTest PASS` |
| Release APK | 通过（仅 unsigned） | `AndroidReceiver/app/build/outputs/apk/release/app-release-unsigned.apk` |
| 独立 release 签名身份 | 通过 | 仓库外 `android-preview.jks`，alias `displayweave-preview`；密码存入 macOS Keychain |
| 签名证书 SHA-256 | 已记录 | `89:80:5F:04:58:00:EA:18:B5:6B:84:B3:2E:8E:31:B1:71:0A:3C:7B:F3:C8:5F:DA:54:D2:60:D1:FC:6D:58:9D` |
| APK 签名验证 | 待重建 | 使用新身份重建 `app-release.apk` 后执行 `apksigner verify --verbose --print-certs` |
| Unsigned APK SHA-256 | 已记录 | `d9af63eb302ab2512fa907cae06e29f5e614df607bc6b7077352f8c1b84c6f73`；仅用于构建追踪，不可发布 |
| 安装测试 | 待人工验证 | 当前 `adb devices -l` 无设备；签名 APK 到位后执行 `adb install -r` |
| Android USB 视频/codec | 基础通过 | OPD2413 建立 HEVC/120 与 H.264/60 USB 流程；输入和长时画面仍待验收 |
| 两台 Android USB | 待人工验证 | 验证 serial、动态本地端口、session、VirtualDisplay 和统计隔离 |

独立 keystore 已创建在 `~/Library/Application Support/DisplayWeave/Signing/android-preview.jks`，不得移入仓库。维护者必须把 JKS 与 Keychain 密码另做离线备份；丢失后无法用新 APK 覆盖安装既有版本。Gradle 使用四个不入库的环境变量：`DISPLAYWEAVE_ANDROID_KEYSTORE`、`DISPLAYWEAVE_ANDROID_STORE_PASSWORD`、`DISPLAYWEAVE_ANDROID_KEY_ALIAS`、`DISPLAYWEAVE_ANDROID_KEY_PASSWORD`。下一步由打包脚本读取 Keychain、构建签名 APK，再执行签名验证、SHA-256 和真机首次/覆盖安装测试。

## macOS

| 项目 | 状态 | 证据 / 下一步 |
| --- | --- | --- |
| 7 个 Swift self-tests | 通过 | 既有 4 项 + AndroidAdb、Forward、TransportPolicy 全部 PASS |
| Debug xcodebuild | 通过 | `OpenSidecarMac` Debug 构建退出码 0 |
| Release xcodebuild | 通过 | Release universal app，`MARKETING_VERSION=0.1.0`，退出码 0 |
| 可运行 App | 通过（Preview entitlement） | Release 可执行文件持续运行并建立 Android USB session；默认空 entitlement 的 ad-hoc build 会被 Sparkle library validation 拒绝，已拆分专用 entitlement |
| Release ZIP | 通过 | `build/preview-0.1/DisplayWeave-Preview-0.1-macOS.zip` |
| ZIP SHA-256 | 已记录 | `fc55a9032c7f8d74e9b3a0c4ecda9b9a143f2a95cca051fe8ea671a6c73f83b1` |
| Code signature | 开发预览限制 | `Signature=adhoc`、`TeamIdentifier=not set`；仅含 preview 专用 `disable-library-validation` entitlement，未注入 `get-task-allow`；本机 `0 valid identities found` |
| Developer ID / notarization | 阻塞正式发布 | 未签名、未公证；不能描述为 Gatekeeper-ready production package |
| 权限说明 | 通过 | README/UI 说明 Screen Recording、Accessibility、Local Network 和 Android USB debugging |

Mac ZIP 只能标为本地开发预览。正式公开发行需配置 Developer ID Application、hardened runtime、notarytool 凭据、stapling，并在另一台没有开发环境的 Mac 上验证 Gatekeeper。

## Android USB / WiFi 验收

| 项目 | 状态 |
| --- | --- |
| ADB 路径查找顺序 | 自动化通过 |
| device / unauthorized / offline / no devices / multiple devices | 自动化通过 |
| 每 serial 独立动态端口 | 自动化通过 |
| 精确 mapping 删除且禁止 `--remove-all` | 自动化通过 |
| 强退后跨启动 mapping ownership 恢复 | 单设备真机通过；外部映射未被删除 |
| Auto / USB / WiFi 选择策略 | 自动化通过 |
| 0.5/1/2/4/8 秒有限恢复 | 自动化通过 |
| install ID 相同才回退 WiFi | 自动化通过 |
| USB HEVC / H.264 fallback | 单设备基础通过；长时画面待验证 |
| USB 输入 / Android FPS 统计 | 待人工验证 |
| USB 拔插与 ADB server 重启恢复 | 待人工验证 |
| 50 次连接断开 | 待人工验证 |
| 10 分钟 Benchmark | 待人工验证 |
| 30 分钟稳定性 | 待人工验证 |
| 2 小时耐久 | 待人工验证 |

详细清单见 `docs/stability-test-report.md`，性能记录见 `docs/usb-vs-wifi-benchmark.md`。在这些真机项目完成前，Release Notes 必须把 Android USB 标为“实现完成、实验性、验收待完成”，不能列为已验证支持。

## 兼容与文档

- [x] 现有长度前缀协议、`streamConfig`、HEVC/H.264 fallback、触控和滚动协议未修改。
- [x] Apple `usbmuxd` USB 与 Bonjour WiFi 路径保持独立。
- [x] 旧 Android H.264/60fps 默认兼容路径保留。
- [x] `ARCHITECTURE.md` 更新为 HEVC/H.264 与 ADB forward 架构。
- [x] `ROADMAP.md` 不再把 HEVC 或 Android USB 实现列为未来功能。
- [x] `SECURITY.md` 说明 WiFi 未加密和 ADB 广泛信任风险。
- [x] README、Android README、网站 FAQ、SEO、JSON-LD、Open Graph/Twitter 文案已统一。
- [x] DisplayWeave/OpenDisplay、SideScreen 与 GPL-3.0 关系保留。
- [x] `docs/brand-assets.md` 记录现有资源和缺失的透明/深色 master。
- [ ] 正式截图、透明 master、深色版本和 Android adaptive icon 待补。

## 最终发布门槛

当前不能把整个 Preview 0.1 标记为“发布验收完成”。至少需要：

1. Android 独立签名 APK、签名验证与真机安装；
2. Android USB 输入、拔插、Auto WiFi 回退和多设备验证；
3. 30 分钟稳定性以及 2 小时耐久测试；
4. USB/WiFi 同条件 Benchmark；
5. Mac Developer ID/公证，或在发布页醒目标明 ad-hoc 未公证并只邀请知情测试者；
6. `git diff --check`、最终 clean build 和产物 SHA-256 重跑。
