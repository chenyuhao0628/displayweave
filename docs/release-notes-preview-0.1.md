# DisplayWeave Preview 0.1 Release Notes

DisplayWeave Preview 0.1 把现有 Apple 接收端与 Android 高刷新技术版本推进到更清晰的跨设备开发预览。本说明严格区分“已验证”“已实现但待真机验收”和“尚未实现”。

## 已支持并有既有验证

- iPhone/iPad receiver；
- Apple USB（macOS `usbmuxd`）与局域网 WiFi；
- Android receiver 与 Android WiFi；
- Android HEVC/H.265 硬件解码；
- H.264 自动 fallback 和旧 H.264/60fps 兼容路径；
- Android 30/60/90/120fps 动态协商；
- Android 实验性高刷新显示请求；
- Touch、drag、cursor 与双指滚动；
- capture、encode、send、receive、decode、render、queue、drop 与 latency runtime metrics。

OnePlus OPD2413 的历史 HEVC/120 WiFi 真机测试约为 109–111 FPS，Android 报告 120Hz 显示模式。该结果不代表所有设备稳定 120 FPS。

## 本轮已实现、尚待 Android 真机验收

- Android USB 使用 `adb forward`，保持 Mac TCP Client -> Android TCP Server:9000；
- ADB 自动查找自定义路径、PATH、Android SDK 环境变量、默认 macOS SDK 与 Homebrew；
- `device`、`unauthorized`、`offline`、无设备和多设备状态提示；
- 每个 ADB serial 独立动态本地端口与独立 DeviceSession；
- Transport 选择 Auto / USB / WiFi；
- Auto 优先 USB，五级有限退避恢复，失败后只回退到 install ID 相同的 WiFi Receiver；
- session 精确清理自己的 mapping，不使用 `adb forward --remove-all`；
- USB 复用现有视频、`streamConfig`、codec fallback、输入和统计协议。

本轮随后在 OnePlus OPD2413 上完成约 11 分钟基础观察，确认 HEVC/120 与 H.264/60 USB 流程可以启动；但输入、拔插恢复、多设备、受控 USB/WiFi Benchmark、30 分钟稳定性和 2 小时耐久尚未通过。邀请外部测试前请先完成 `docs/release-checklist.md` 中的真机门槛。

## 已知限制

- Android 120fps 取决于 Mac、分辨率、码率、Android SoC/decoder、面板与温度；请求 120fps 不等于稳定渲染 120 FPS。
- 当前测试设备的 WiFi HEVC/120 结果约 109–111 FPS。
- iOS/iPadOS 120Hz 尚未实现。
- Android WiFi 加密配对尚未实现；只应在可信局域网使用。
- Android USB debugging 授权是设备对整台 Mac 的广泛 ADB 信任，不只是 DisplayWeave 配对。
- Android Release APK 已能构建，但当前没有独立 release keystore，unsigned APK 不可发布或安装。
- 本地 macOS Preview 0.1 App 是 ad-hoc 签名，`TeamIdentifier` 为空，未使用 Developer ID 且未公证。
- ad-hoc Preview 使用独立 `OpenSidecarMacAdHoc.entitlements` 关闭 library validation，以允许无 Team ID 的 App 加载嵌入 Sparkle；正式 Developer ID 构建不使用该 entitlement。
- Mac 扩展显示使用私有 `CGVirtualDisplay` API，未来 macOS 版本可能改变行为。
- 当前品牌 PNG 没有透明 master 或深色背景最终版本，现有资源属于 Preview 临时衍生资产。

## 构建证据（2026-07-11）

- 7 个 Mac standalone self-tests：PASS；
- `OpenSidecarMac` Debug xcodebuild：PASS；
- `OpenSidecarMac` Release 0.1.0 universal xcodebuild：PASS；
- Android `clean test assembleRelease`：PASS；
- Android `ProtocolSelfTest` / `VideoStreamPolicySelfTest`：PASS；
- Android release signature verification：FAIL（预期阻塞，APK unsigned）；
- `git diff --check`：在最终提交前必须重跑。

## 安全与来源

DisplayWeave 是源自 OpenDisplay 的独立维护 GPL-3.0 项目，并保留相应 Git 历史、版权和许可证义务。SideScreen 仅作为 MIT 许可的技术参考；详细关系见 `THIRD_PARTY_NOTICES.md`。
