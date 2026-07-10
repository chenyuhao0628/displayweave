# DisplayWeave Preview 0.1 Stability Test Report

日期：2026-07-11  
实现分支：`codex/android-adb-usb`  
状态：自动化验证进行中；Android USB 真机项目待人工执行。

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
| ADB 真机探测 | 无设备 | `adb devices -l` 仅输出 header |

## 异常恢复与耐久矩阵

当前没有连接 Android 真机。以下项目均明确标记为“待人工验证”，不根据编译或单元测试推断通过。

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
| H.264 fallback | 待人工验证 | 画面和输入恢复，FPS 配置保持兼容 |
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

自动化证据覆盖 ADB 状态识别、安全参数执行、多设备映射隔离、选择策略和有限恢复状态机。由于本轮环境没有 Android ADB 设备，不能宣称“Android USB 真机验收通过”，也不能把 Preview 0.1 的 USB Benchmark、拔插恢复、多设备或耐久测试标记为完成。
