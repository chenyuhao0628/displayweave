# DisplayWeave Preview 0.1 重连、离线分发与性能验收设计

日期：2026-07-11
状态：用户已批准方案 C 方向
范围：Android 前后台重连、ADB 物理设备去重、离线签名与三平台预览分发、跨平台并发验收、下一阶段 Benchmark 入口

## 1. 已确认约束

- Android APK 不上 Google Play，直接提供下载和侧载。
- Android 使用项目独立、长期固定的离线 release keystore；不使用 Debug key 作为公开预览身份。
- 用户没有付费 Google Play 或 Apple Developer Program 账号。
- Mac 以 ad-hoc、未公证开发预览形式分发并明确风险。
- iOS 只提供“供用户自行重签”的 device payload；不得描述为无需签名即可安装。
- 本轮不执行 30 分钟和 2 小时耐久测试，由维护者按清单后续执行。
- 当前只有一台 Android 和一台 iPhone，可用于 Android + iPhone 跨平台并发，不把它冒充“两台 Android”验证。
- 性能工作遵循《DisplayWeave 下一阶段优化计划（低延迟 + 高刷新率 + 高码率）》的顺序：先数据，再调整码率、队列和关键帧。

## 2. 已复现故障与根因

同一台 OnePlus 同时通过 USB ADB 和 Android 无线调试出现在 `adb devices -l`：

- USB serial 带 `usb:<bus-port>` 字段；
- 无线调试 serial 形如 `adb-<serial>-<service>._adb-tls-connect._tcp`；
- 两条记录的 product、model 和 device 相同。

当前 Mac 把两条 ADB endpoint 当成两台 Android，分别创建动态 forward 和 Sender。Android Receiver 的 TCP Server 同一时刻只保留一个 client，因此两条连接持续互相替换。直接日志证据包括：

- 同一设备同时出现两次 `connection ready`；
- 两个不同 ADB serial 的状态并行变化；
- 连续 `Connection reset by peer`、watchdog 重连和密集 keyframe request；
- 返回 Android 桌面再进入后竞争继续；切换扩展/镜像因重建会话而暂时改变现象。

因此，缺陷的首要根因不是单独缺少 `onResume` 回调，而是“无线 ADB endpoint 被错误纳入 Android USB transport”，造成一个物理 Receiver 被双会话争用。生命周期恢复仍需单独加固。

## 3. 方案 C：ADB 归并与前台恢复

### 3.1 ADB transport 分类

扩展 `AndroidAdbDevice`，保留 `adb devices -l` 的连接元数据，并分类为：

- `usb`：记录包含 `usb:` 字段；
- `wirelessDebugging`：mDNS/TLS serial 或不含 USB 字段的网络 ADB；
- `unknown`：保留用于错误呈现，不自动建立 USB session。

DisplayWeave 的 `AdbUsbTransport` 只消费 `usb` 设备。Android App 自身的 WiFi transport 继续使用 Bonjour/NSD + TCP，不使用无线 ADB。这样不需要猜测厂商 serial 格式，也不会把无线调试当作第二台物理 Android。

多台真正通过数据线连接的 Android 仍按各自 USB serial 分配独立本地端口和 DeviceSession。

### 3.2 Mac 会话唯一性

自动连接前以 `android-adb:<USB serial>` 为唯一 session key，并增加两道防线：

1. ADB 扫描输出只向自动连接层暴露 USB-ready 设备；
2. 建立映射前再次确认同一 USB serial 没有 active/pending/recovery session。

无线 ADB 记录可以显示为“无线调试，不作为 USB 传输”，但不得出现连接按钮或自动创建 forward。

### 3.3 Android 生命周期恢复

新增一个可独立测试的 Receiver lifecycle coordinator：

- `onResume`：Surface 有效且 server 为空时启动 server；server 已运行则保持幂等；
- `surfaceCreated`：记录 Surface 并调用同一 `ensureStarted`；
- `surfaceDestroyed`：停止当前 server、清空引用并递增 receiver generation；
- `onDestroy`：幂等停止；
- 新 server 接受连接后发送现有 `hello`，不改变协议格式。

不在 `onPause` 无条件停止 server，因为按 Home 后系统可能仍保留有效 Surface；无条件停止会制造额外断线。真正失效由 `surfaceDestroyed`、socket 错误和 `onDestroy` 驱动。

### 3.4 Mac 恢复数据流

当 Android Receiver 返回前台并重新监听：

1. 现有 Mac watchdog 或 socket failure 触发 reconnect；
2. ADB forward 保持或按现有有限退避精确重建；
3. Mac 收到新 `hello` 后重新执行现有 pipeline configure；
4. 重发 `streamConfig`，保持 codec 协商和 H.264 fallback；
5. 强制下一帧为关键帧；静态画面复用已有 last-frame keyframe 路径；
6. 不需要用户切换扩展/镜像。

如果 Receiver 在 0.5/1/2/4/8 秒恢复窗口内尚未回来，USB 模式显示明确失败；Auto 模式只有发现相同 install ID 的 App WiFi Receiver 时才回退 WiFi。

## 4. 测试设计

### 4.1 自动化

- ADB parser：USB、无线调试、unauthorized、offline、同一设备双 endpoint、两台真实 USB。
- 自动连接过滤：无线 ADB 不创建 forward；USB ADB 创建且每 serial 独立。
- session 防重：active、pending、recovery 任一存在时不重复连接。
- Android lifecycle coordinator：resume/surface 事件任意顺序都只启动一个 server；destroy 幂等停止。
- 现有协议、codec、refresh、forward ownership 和 transport policy self-tests 全部回归。

### 4.2 单台 Android 真机

按顺序记录时间和日志：

1. USB 串流建立；确认只有一个 Android ADB Sender 和一个 app-owned forward。
2. Home 返回桌面 10 秒，再从最近任务进入；无需 Mac 操作恢复画面。
3. 关闭 Android App，再打开；无需切换扩展/镜像恢复。
4. 拔线、等待提示、重新插线；确认有限退避恢复且无旧 mapping。
5. 取消 USB 调试授权；确认 unauthorized 指引且无快速无限重试。
6. `adb kill-server` 后重新启动；确认重新探测并恢复。
7. Auto：USB 恢复耗尽后，仅在相同 install ID 的 WiFi Receiver 可发现时回退。

### 4.3 Android + iPhone 并发

这项只证明跨平台并发兼容，不证明两台 Android USB：

- Android 使用 ADB USB，iPhone 分别验证 Apple USB 和 WiFi；
- 两端同时保持独立 VirtualDisplay、SCStream、encoder、transport 和统计；
- Android 前后台/拔线不影响 iPhone；iPhone 断开不影响 Android；
- 记录两个 session key、显示 ID、codec/FPS 和断开事件。

两台 Android USB 仍保留为待验证项目。

## 5. 离线发布与签名

### 5.1 Android

独立 keystore 存放于仓库外的：

`~/Library/Application Support/DisplayWeave/Signing/android-preview.jks`

- 私钥和密码不进入 Git、不进入 APK 附件、不写入 shell history。
- 密码存入 macOS Keychain；打包脚本在交互式本地发布时读取。
- alias 固定为 `displayweave-preview`，证书有效期覆盖长期更新周期。
- release APK 必须通过 `apksigner verify --verbose --print-certs`。
- 安装测试包含首次安装、启动、`adb install -r` 覆盖更新、签名证书 SHA-256 记录。
- Google Play 账号不是上述步骤的前提。

keystore 必须另做离线备份；丢失私钥后无法用新版本覆盖安装旧 APK。

### 5.2 macOS

- 发布 ad-hoc ZIP，保持当前 Preview 专用 entitlement。
- Release Notes 明确“未 Developer ID 签名、未公证，macOS 可能阻止首次运行”。
- 提供 SHA-256 和 `codesign --verify --deep --strict` 本地证据。
- 不宣称 Gatekeeper-ready，不指导用户关闭整个系统安全机制。

### 5.3 iOS/iPadOS

iOS 拒绝运行缺失或无效签名的 App，因此不提供“可直接安装的未签名 IPA”。提供两类产物：

1. Simulator app：仅供 iOS Simulator，不能装真机；
2. Unsigned device resigning payload：使用 `iphoneos` SDK、`CODE_SIGNING_ALLOWED=NO` 构建，打包为明确命名的重签输入，不宣称可直接安装。

用户必须用自己的 Apple Account/Personal Team 或可信重签工具生成有效签名和 provisioning。免费 Personal Team 当前有周期性重新签名限制。项目只保证 payload 架构、Info.plist、可执行文件和资源完整，不保证第三方工具兼容性，也不随包附带任何第三方证书。

## 6. 下一阶段性能与 Benchmark

遵循上传 RTF 的顺序，不直接把码率改到 120/200 Mbps：

1. 审计现有 Capture/Encode/Sent/Received/Decoded/Rendered FPS、bitrate、encode/decode latency、Frame Age、queue、drops、RTT 是否端到端可见并可导出；
2. 补齐缺失统计和可重复采样格式；
3. 增加 Manual 码率档位；
4. 在固定内容下做高码率阶梯测试；
5. 依据 RTT/Queue/FrameAge/Drops 设计“快降慢升”自适应码率；
6. USB 高码率只在证据证明队列与解码余量足够后开放；
7. 对比 maxPendingSends 1/2/3；
8. 对比 WiFi 2 秒与 USB 1 秒关键帧间隔；
9. 完成 WiFi Benchmark；
10. 完成 USB Benchmark。

固定场景为桌面动态测试图、浏览器滚动、YouTube 4K60 和游戏/高运动内容。每组固定设备、分辨率、codec、fps、码率和内容，先预热，再记录原始时间序列。当前 11 分钟混合配置日志只作为功能证据，不进入对照表。

本轮先实现与验证重连和发布链路，并把统计审计作为下一性能阶段的入口；30 分钟和 2 小时耐久由维护者按生成的清单执行。

## 7. 完成标准

- 同一物理 Android 同时开启 USB ADB 与无线调试时，DisplayWeave 只创建一个 USB Sender。
- Android Home/返回前台及关闭/重开后，无需 Mac 切换模式即可恢复画面。
- ADB mapping、session、关键帧和错误提示均有直接日志证据。
- Android release APK 使用独立离线证书，签名验证和首次/覆盖安装通过。
- Android + iPhone 并发通过；两台 Android 明确保留待验证。
- Mac ad-hoc 与 iOS 重签 payload 的限制在文件名、Release Notes 和清单中一致。
- Benchmark 文档遵循“先统计、后优化”的顺序，不伪造 30 分钟、2 小时或 USB/WiFi 对照结果。
