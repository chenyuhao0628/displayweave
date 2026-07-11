# DisplayWeave Preview 0.1 Stability Test Report

日期：2026-07-11  
实现分支：`codex/android-adb-usb`  
状态：自动化验证通过；完成一次约 11 分钟 Android USB 真机基础观察，30 分钟与 2 小时项目仍待执行。

## 自动化验证

| 检查 | 结果 | 证据 |
| --- | --- | --- |
| Mac 既有 4 个 standalone self-tests | 通过 | RefreshRate、Encoding、Settings、DeviceCapabilities 均输出 PASS |
| AndroidAdbSelfTest | 通过 | ADB 状态、路径、参数执行、超时和 UI presentation |
| AndroidAdbForwardSelfTest | 通过 | 两 serial 独立端口、精确删除、禁止 `--remove-all` |
| TransportSelectionPolicySelfTest | 通过 | Auto/USB/WiFi、install ID 回退、0.5/1/2/4/8 秒恢复状态机 |
| macOS Debug xcodebuild | 通过 | `OpenSidecarMac` 构建退出码 0 |
| Android clean/test/assembleDebug | 通过 | 57 个 Gradle task 执行；ProtocolSelfTest 与 VideoStreamPolicySelfTest PASS；Debug APK 构建成功 |
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

本轮不能证明无黑屏/花屏、30 分钟稳定、2 小时耐久、拔插恢复、ADB server restart、多 Android 并发或 USB 性能优于 WiFi。

## 异常恢复与耐久矩阵

以下项目均按本轮直接证据标记；未执行项目不根据编译或单元测试推断通过。

| 项目 | 状态 | 通过标准 / 需记录证据 |
| --- | --- | --- |
| Android App 关闭后重新打开 | 待人工验证 | Auto/USB 恢复画面，streamConfig 重发，无长期黑屏 |
| 拔出 USB 后重新插入 | 待人工验证 | 有限退避恢复；映射无残留；记录 reconnectTime |
| USB 调试授权取消 | 待人工验证 | 显示 unauthorized 指引，不快速无限重试 |
| ADB Server 重启 | 待人工验证 | 重新探测 exact serial 并恢复映射 |
| Android 锁屏后解锁 | 待人工验证 | 解锁后关键帧恢复，无持续黑屏/花屏 |
| Android App 切后台后恢复 | 待人工验证 | Receiver 重开监听后恢复 |
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
| Android + iPhone/iPad | 待人工验证 | Apple usbmuxd/WiFi 会话不受影响 |

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

自动化证据覆盖 ADB 状态识别、安全参数执行、多设备映射隔离、选择策略、有限恢复状态机与跨启动 mapping ownership。单台 OPD2413 证明 Android USB 能建立 HEVC/120 与 H.264/60 流程，但仍不能把 Preview 0.1 的 USB/WiFi Benchmark、拔插恢复、多设备、30 分钟或 2 小时耐久标记为完成。
