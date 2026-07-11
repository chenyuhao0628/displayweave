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

## 本轮已实现并完成单机基础验证

- Android USB 使用 `adb forward`，保持 Mac TCP Client -> Android TCP Server:9000；
- ADB 自动查找自定义路径、PATH、Android SDK 环境变量、默认 macOS SDK 与 Homebrew；
- `device`、`unauthorized`、`offline`、无设备和多设备状态提示；
- 每个 ADB serial 独立动态本地端口与独立 DeviceSession；
- Transport 选择 Auto / USB / WiFi；
- Auto 优先 USB，五级有限退避恢复，失败后只回退到 install ID 相同的 WiFi Receiver；
- session 精确清理自己的 mapping，不使用 `adb forward --remove-all`；
- USB 复用现有视频、`streamConfig`、codec fallback、输入和统计协议。
- 同一物理 Android 的无线调试 ADB endpoint 不再创建第二条伪 USB session；只有带 `usb:` 元数据的有线行可进入 ADB USB transport。
- Android Receiver 在 surface/前后台变化后幂等重启；Mac 重连会先重发 `streamConfig`，并以收到 peer 控制消息作为真正就绪条件。

OnePlus OPD2413 已确认 HEVC/120 与 H.264/60 USB 流程、返回桌面后重开、强停重开以及 ADB server 重启可自动恢复，无需在 Mac 上切换扩展/镜像。当前 DisplayWeave 0.1.0 iPhone WiFi 与 Android USB 也已同时建立独立 session；Android 返回桌面期间 iPhone 会话持续。输入、物理拔插、授权取消、实际 Auto WiFi 回退、两 Android、受控 Benchmark、30 分钟和 2 小时耐久仍未完成。

## 已知限制

- Android 120fps 取决于 Mac、分辨率、码率、Android SoC/decoder、面板与温度；请求 120fps 不等于稳定渲染 120 FPS。
- 当前测试设备的 WiFi HEVC/120 结果约 109–111 FPS。
- iOS/iPadOS 120Hz 尚未实现。
- Android WiFi 加密配对尚未实现；只应在可信局域网使用。
- Android USB debugging 授权是设备对整台 Mac 的广泛 ADB 信任，不只是 DisplayWeave 配对。
- Android APK 使用仓库外独立 keystore 签名，已通过 v2 签名验证和真机首次/覆盖安装；维护者必须安全备份 keystore 与 Keychain 密码。
- 本地 macOS Preview 0.1 App 是 ad-hoc 签名，`TeamIdentifier` 为空，未使用 Developer ID 且未公证。
- iOS 交付物是明确标注的 unsigned re-signing input IPA，不能直接安装。维护者本机可用免费 Personal Team 安装到已登记 iPhone，但该签名不适合公开分发；其他用户必须自行重签。
- ad-hoc Preview 使用独立 `OpenSidecarMacAdHoc.entitlements` 关闭 library validation，以允许无 Team ID 的 App 加载嵌入 Sparkle；正式 Developer ID 构建不使用该 entitlement。
- Mac 扩展显示使用私有 `CGVirtualDisplay` API，未来 macOS 版本可能改变行为。
- 当前品牌 PNG 没有透明 master 或深色背景最终版本，现有资源属于 Preview 临时衍生资产。

## 构建证据（2026-07-11）

- 7 个 Mac standalone self-tests：PASS；
- `OpenSidecarMac` Debug xcodebuild：PASS；
- `OpenSidecarMac` Release 0.1.0 universal xcodebuild：PASS；
- Android `clean test assembleRelease`：PASS；
- Android 4 个 standalone self-tests：PASS；
- Android release signature verification：PASS（APK Signature Scheme v2，证书摘要已记录）；
- `git diff --check`：在最终提交前必须重跑。

## 安全与来源

DisplayWeave 是源自 OpenDisplay 的独立维护 GPL-3.0 项目，并保留相应 Git 历史、版权和许可证义务。SideScreen 仅作为 MIT 许可的技术参考；详细关系见 `THIRD_PARTY_NOTICES.md`。
