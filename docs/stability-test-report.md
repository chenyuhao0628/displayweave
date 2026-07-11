# DisplayWeave Preview 0.1 Stability Test Report

日期：2026-07-11  
实现分支：`codex/android-adb-usb`  
状态：自动化验证通过；完成 Android 前后台/重开、ADB 重启和当前 iPhone + Android 并发基础验证；30 分钟与 2 小时项目由用户另行执行。

## 自动化验证

| 检查 | 结果 | 证据 |
| --- | --- | --- |
| Mac 既有 4 个 standalone self-tests | 通过 | RefreshRate、Encoding、Settings、DeviceCapabilities 均输出 PASS |
| AndroidAdbSelfTest | 通过 | ADB 状态、路径、参数执行、超时和 UI presentation |
| AndroidAdbForwardSelfTest | 通过 | 两 serial 独立端口、精确删除、禁止 `--remove-all` |
| TransportSelectionPolicySelfTest | 通过 | Auto/USB/WiFi、install ID 回退、0.5/1/2/4/8 秒恢复状态机 |
| macOS Debug xcodebuild | 通过 | `OpenSidecarMac` 构建退出码 0 |
| Android clean/test/assembleDebug/Release | 通过 | Protocol、VideoStreamPolicy、ReceiverLifecycle、ReceiverConnection 四项 PASS；签名 Release APK 构建成功 |
| `git diff --check` | 通过 | 无空白错误 |
| ADB 真机探测 | 通过 | OnePlus OPD2413，ADB state `device`（serial 不在公开报告中记录） |

## Android USB 真机基础观察

2026-07-11 09:58:57–10:09:54 在 OnePlus OPD2413 上运行约 11 分钟。初始配置为 3040×1904、HEVC、120fps 请求、80 Mbps、扩展模式；后段交互切换到 1470×956、H.264/60、8 Mbps、镜像模式，因此这不是固定条件 Benchmark。

直接证据：

- ADB forward 建立成功，Mac 连接动态 loopback 端口并收到 Android `hello`；
- HEVC encoder、120Hz virtual display、`streamConfig transport=usb`、ScreenCaptureKit 与 keyframe request 均启动；
- H.264/60 USB fallback 后续启动成功，`streamConfig transport=usb`；
- 第一个约 9分50秒没有记录到连接状态事件；交互/重建阶段出现 peer reset，并在约 1 秒内重连；
- 全程 Mac 进程未崩溃；
- 静态画面期间 ScreenCaptureKit 内容驱动输出会降至低 FPS，不能用本轮数据比较 USB/WiFi；
- session 重建阶段观察到密集 keyframe request，需要在 30 分钟受控测试中复查；
- 强制终止测试暴露 mapping ownership 丢失更新，已改为原子持久 `upsert/remove` 并新增回归测试。
- 随后的强制终止与跨启动恢复验证确认：旧自有端口与持久记录一致；下一次启动精确删除旧自有端口并创建新端口；同一设备上预先存在的外部端口保持不变。测试收尾后只保留该外部端口。

后续针对原始“回桌面再进入需 Mac 切模式”的问题完成根因修复：同一设备同时出现有线与无线调试 ADB row 时只允许有线 row 建立 USB session；Receiver surface 恢复后幂等重开服务；重连先重发 codec 配置，且只有收到 peer 消息才清除断线宽限期。实测返回桌面再进入与强停重开均自动恢复，无需切换扩展/镜像；ADB daemon kill/restart 也在有限恢复流程内重新建立 HEVC/120。

当前 iPhone 上的旧 OpenDisplay 结果已排除。随后使用 Xcode Personal Team 构建、安装并启动当前 DisplayWeave 0.1.0：Android ADB USB 建立显示 79（3040×1904、HEVC、120 请求/实际刷新率 120、80 Mbps），iPhone WiFi 建立显示 80（1320×2868、H.264、60、23 Mbps，旋转后显示 81）。Android 返回桌面并进入恢复流程期间，iPhone 仍持续回传 WiFi stats，证明两个 session 的 transport、显示和统计相互独立。

物理拔插随后完成多轮验证。拔线后有线 ADB row 与旧 forward 均消失，无线调试 row 不会被当作 USB。首轮插线暴露 WiFi session 未先让位、USB 客户端反复 watchdog 的缺陷；新增 handover policy 与回归测试后重测，日志在 14:30:29 记录 `upgrading same-install-ID session from wifi:DisplayWeave Android`，约 0.33 秒后 USB 收到 hello、建立显示 88 并发送 `transport=usb` 的 HEVC/120 streamConfig。最终仅有一个 `HA2AE8R5 tcp:53341 tcp:9000` forward；iPhone WiFi 显示 86 和 stats 持续。

真正的 USB→WiFi Auto 回退也单独验证：14:33:27 USB socket reset，14:33:37 协议级 10 秒宽限结束，随后执行 0.5/1/2/4/8 秒有限恢复；14:33:53 仅连接同 install ID 的 `wifi:DisplayWeave Android`，建立显示 91 并发送 `transport=wifi` 的 HEVC/120 streamConfig，总恢复约 26 秒。回退完成后 ADB 只剩无线调试 row 且 `forward --list` 为空；iPhone WiFi 显示 90 与 stats 全程持续。

授权取消/重授权也完成真机验证。14:36:15 有线设备真实进入 `unauthorized usb:1-2`；保持约 20 秒期间 `forward --list` 为空，Mac 未创建 Android session 或快速无限重试，iPhone WiFi 保持。14:36:53 用户重新允许后设备变为 `device`，Mac 自动创建 mapping；因 Receiver 仍在系统设置页，socket 先被重置，返回 DisplayWeave 后 14:37:31 收到 hello，建立显示 93 并发送 `transport=usb` 的 HEVC/120 streamConfig，无需 Mac 模式切换。

USB Touch 输入用可重复的端到端方法验证：USB stream 活跃时先读取 macOS `CGEvent` 光标坐标 `(730,486)`，再通过 ADB 向 Android DisplayWeave Surface 注入触摸 `(250,300)`；约 1 秒后 Mac 光标变为 Android 虚拟显示范围内的 `(-1258,152)`。这覆盖 `MotionEvent -> touch JSON -> USB socket -> Mac InputInjector`。双指滚动的 gesture tracker 与 scroll JSON 有 ProtocolSelfTest，维护者随后在真机画面上确认双指滚动正常。

本轮仍不能证明 30 分钟稳定、2 小时耐久、两 Android 并发或 USB 性能优于 WiFi；这些项目按维护者已确认的范围保留待测。

## 异常恢复与耐久矩阵

以下项目均按本轮直接证据标记；未执行项目不根据编译或单元测试推断通过。

| 项目 | 状态 | 通过标准 / 需记录证据 |
| --- | --- | --- |
| Android App 关闭后重新打开 | 通过 | 强停/重开后约 20 秒内协议级恢复，streamConfig 重发，无 Mac 模式切换 |
| 拔出 USB 后重新插入 | 通过 | 拔线旧 mapping 消失；插回建立新动态端口；同 install ID WiFi 先结束再由 USB 收到 hello |
| USB 调试授权取消 | 通过 | 真实 unauthorized 期间无 mapping/快速重试；重新允许并返回 App 后自动收到 hello 恢复 |
| ADB Server 重启 | 通过 | daemon kill/restart 后重新探测 exact serial、结束超时 session 并建立新 peer；未错误回退 WiFi |
| Android 锁屏后解锁 | 待人工验证 | 解锁后关键帧恢复，无持续黑屏/花屏 |
| Android App 切后台后恢复 | 通过 | Home 后回 App 自动恢复；surface 就绪可能约 15 秒，无需 Mac 切模式 |
| Mac 睡眠后唤醒 | 待人工验证 | 会话恢复或显示明确失败，不残留虚拟显示 |
| WiFi 中断后恢复 | 待人工验证 | 既有 WiFi 行为无回归 |
| HEVC 初始化失败 | 待人工验证 | 自动回退 H.264 并重发 streamConfig |
| HEVC 运行中失败 | 待人工验证 | codecFailure 触发 H.264 fallback |
| H.264 fallback | 基础通过 | USB 日志确认 H.264/60 encoder、streamConfig 与 capture 启动；长时画面验收待做 |
| 重复连接和断开 50 次 | 待人工验证 | 无 ADB mapping、端口、线程或虚拟显示泄漏 |
| 连续运行 30 分钟 | 待人工验证 | 无崩溃；队列/延迟/内存不持续增加 |
| 连续运行 2 小时 | 待人工验证 | 无崩溃、黑屏、花屏、FPS 持续下降 |
| 两台 Android 同时 USB | 待人工验证 | serial、本地端口、session、显示和统计独立 |
| Android USB + Android WiFi | 待人工验证 | 同时工作，一台断开不影响另一台 |
| Android + iPhone/iPad | 通过（当前构建） | DisplayWeave iOS 0.1.0 WiFi + Android WiFi/USB 同时工作；Android transport handover 期间 iPhone stats 持续 |

## 泄漏检查清单

每轮异常测试前后记录：

- app crash 与系统 crash log；
- 黑屏、花屏和首个恢复帧时间；
- macOS 虚拟显示数量；
- `adb -s <serial> forward --list`；
- DisplayWeave 持有的 loopback 端口；
- Mac/Android 线程数和内存；
- capture/encode/send/receive/decode/render FPS；
- queueDepthMac / queueDepthAndroid；
- droppedFramesMac / droppedFramesAndroid；
- estimatedE2ELatency / latestFrameAge；
- CPU 与温度/降频迹象。

## 当前结论

自动化证据覆盖 ADB 状态识别、安全参数执行、多设备映射隔离、选择策略、同 install ID WiFi→USB handover、有限恢复状态机与跨启动 mapping ownership。单台 OPD2413 证明 Android USB 能建立 HEVC/120 与 H.264/60、Touch 与双指滚动输入有效，且物理拔插、授权取消/重授权与 App WiFi/USB 转换可恢复；仍不能把 Preview 0.1 的 USB/WiFi Benchmark、两 Android、30 分钟或 2 小时耐久标记为完成。
