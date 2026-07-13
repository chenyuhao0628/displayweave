[English](release-checklist.md) | [简体中文](release-checklist.zh-CN.md)

## Automatic-update gate

- Confirm all five secret names in [Automatic updates](automatic-updates.md) exist; never print their values.
- Require a monotonically higher build number, `DisplayWeave-macOS.zip`, `DisplayWeave-Android.apk`, `appcast.xml`, and `android-update.json`.
- Run `tools/verify-update-release.sh` before upload. Upload assets without replacement or `--clobber`.
- Confirm Release assets exist before committing the two feeds, then confirm the Pages deployment succeeds.
- Build the unsigned iOS target and run the legacy iPhone hello fixture; do not couple iOS compatibility to Mac/Android publication credentials.

# DisplayWeave Preview 0.1 Release Checklist

审计日期：2026-07-11
目标版本：DisplayWeave Preview 0.1
实现分支：`codex/android-adb-usb`

状态说明：`通过` 表示有本轮直接证据；`待人工验证` 表示需要真机或交互；`阻塞` 表示不能发布对应正式产物。

## Android

| 项目 | 状态 | 证据 / 下一步 |
| --- | --- | --- |
| Clean build | 通过 | 最终打包执行 `./gradlew --no-daemon clean test assembleRelease`，70 tasks，BUILD SUCCESSFUL |
| Unit/self tests | 通过 | `ProtocolSelfTest`、`VideoStreamPolicySelfTest`、`ReceiverLifecycleSelfTest`、`ReceiverConnectionSelfTest` 全部 PASS |
| Release APK | 通过（独立离线签名） | `build/preview-0.1/DisplayWeave-Preview-0.1-Android.apk` |
| 独立 release 签名身份 | 通过 | 仓库外 `android-preview.jks`，alias `displayweave-preview`；密码存入 macOS Keychain |
| 签名证书 SHA-256 | 已记录 | `89:80:5F:04:58:00:EA:18:B5:6B:84:B3:2E:8E:31:B1:71:0A:3C:7B:F3:C8:5F:DA:54:D2:60:D1:FC:6D:58:9D` |
| APK 签名验证 | 通过 | `apksigner verify --verbose --print-certs`：v2 true、1 signer、证书摘要与记录一致 |
| APK SHA-256 | 已记录 | `1a475ba836f5e5fefee4a52cdadbc4e5b7e306abc8785297a21d7794469aed3d` |
| 安装测试 | 通过 | OPD2413 卸载旧 debug 包后首次安装成功；随后 `adb install -r` 覆盖安装成功；release 包不可 `run-as`，并能启动 Activity |
| Android USB 视频/codec | 基础通过 | OPD2413 建立 HEVC/120 与 H.264/60 USB 流程；前后台与强停重开自动恢复；输入仍待人工验收 |
| 两台 Android USB | 无设备条件 | 当前只有一台 Android，不能验证两条 ADB USB；已用当前 iPhone WiFi + Android USB 验证跨平台并发与 session 隔离 |

独立 keystore 已创建在 `~/Library/Application Support/DisplayWeave/Signing/android-preview.jks`，不得移入仓库。维护者必须把 JKS 与 Keychain 密码另做离线备份；丢失后无法用新 APK 覆盖安装既有版本。打包脚本从 Keychain 读取密码，通过不入库的环境变量传给 Gradle，并在交付前验证签名。

## macOS

| 项目 | 状态 | 证据 / 下一步 |
| --- | --- | --- |
| 7 个 Swift self-tests | 通过 | 既有 4 项 + AndroidAdb、Forward、TransportPolicy 全部 PASS |
| Debug xcodebuild | 通过 | `OpenSidecarMac` Debug 构建退出码 0 |
| Release xcodebuild | 通过 | Release universal app，`MARKETING_VERSION=0.1.0`，退出码 0 |
| 可运行 App | 通过（Preview entitlement） | Release 可执行文件持续运行并建立 Android USB session；默认空 entitlement 的 ad-hoc build 会被 Sparkle library validation 拒绝，已拆分专用 entitlement |
| Release ZIP | 通过 | `build/preview-0.1/DisplayWeave-Preview-0.1-macOS.zip` |
| ZIP SHA-256 | 已记录 | `b26903c55a0a8649fe0a8e6d1a27cc31bf03b41b040c1f71f40a7a0706a7aa60` |
| Code signature | 开发预览限制 | `Signature=adhoc`、`TeamIdentifier=not set`；仅含 preview 专用 `disable-library-validation` entitlement，未注入 `get-task-allow`；Xcode Personal Team 仅是 Apple Development，不是 Developer ID |
| Developer ID / notarization | 阻塞正式发布 | 未签名、未公证；不能描述为 Gatekeeper-ready production package |
| 权限说明 | 通过 | README/UI 说明 Screen Recording、Accessibility、Local Network 和 Android USB debugging |

Mac ZIP 只能标为本地开发预览。正式公开发行需配置 Developer ID Application、hardened runtime、notarytool 凭据、stapling，并在另一台没有开发环境的 Mac 上验证 Gatekeeper。

## iOS / iPadOS

| 项目 | 状态 | 证据 / 下一步 |
| --- | --- | --- |
| unsigned device payload | 通过 | `DisplayWeave-Preview-0.1-iOS-unsigned-resigning-input.ipa` 仅含 `Payload/DisplayWeave.app`，无 `._`/`__MACOSX` |
| IPA SHA-256 | 已记录 | `83a5ea5f29317e7ad4084b66960f091664fa2229c5bb22d3e074e3e0716c4ccf` |
| 本机 Personal Team 真机构建 | 通过 | Team `33QY9GJ2FJ` 自动签名，DisplayWeave `0.1.0 (1)` 覆盖安装并启动于已配对 iPhone |
| 面向他人直接分发 | 不支持 | 免费 Personal Team 产物绑定登记设备且短期有效；公开 IPA 仍需用户自行重签，或使用付费 Apple Developer 分发方式 |

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
| USB Touch / 双指滚动输入 | 真机通过：ADB 注入 Surface 触摸后 Mac 光标由 `(730,486)` 移至 Android 虚拟显示 `(-1258,152)`；维护者确认双指滚动正常 |
| Android 返回桌面 / 重开 App 自动恢复 | 单设备真机通过；无需 Mac 切换扩展/镜像 |
| ADB server 重启恢复 | 单设备真机通过；协议级确认后恢复，未错误回退 WiFi |
| USB 物理拔插 / mapping 清理 | 单设备真机通过；拔线后有线 row 与旧 forward 消失，插回后新动态端口建立 |
| Auto 同设备 WiFi 回退 / USB 再优先 | 单设备真机通过；USB 断开后 10 秒协议宽限 + 0.5/1/2/4/8 秒有限恢复，约 26 秒切到同 install ID App WiFi；插线后先结束 WiFi 再建立 USB；iPhone 不受影响 |
| USB 调试授权取消 / 重授权 | 单设备真机通过；unauthorized 期间无 forward/快速重试，重新允许并返回 Receiver 后自动恢复 USB 画面 |
| 50 次连接断开 | 待人工验证 |
| 10 分钟 Benchmark | 待人工验证 |
| Android USB + 当前 iPhone WiFi 并发 | 真机通过；两独立 session/显示，Android 中断期间 iPhone stats 持续 |
| 30 分钟稳定性 | 用户明确延后自行执行 |
| 2 小时耐久 | 用户明确延后自行执行 |

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

当前可作为明确标注限制的开发预览交付，但不能写成完整发布验收完成。剩余项目：

1. 两 Android USB 并发验证（当前没有第二台 Android，已用当前 iPhone WiFi + Android USB 验证跨平台隔离）；
2. 用户执行 30 分钟稳定性及 2 小时耐久测试；
3. 按 `docs/usb-vs-wifi-benchmark.md` 执行同条件 Benchmark；
4. 发布页醒目标明 Mac ad-hoc 未公证、iOS IPA 需要用户自签；
5. 上述未执行的物理真机项目完成后，再更新验收状态；本轮最终 clean build、自测试、`git diff --check` 和三项产物校验已重跑通过。
