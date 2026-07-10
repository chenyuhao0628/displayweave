# OpenDisplay / DisplayWeave 后续开发与验收目标

`/goal`

继续当前项目开发，不重复已经完成的 Android 60/90/120fps、HEVC、H.264 fallback、设备能力协商、动态 streamConfig、Android 高刷新显示请求、性能统计、低延迟最新帧队列和 Mac 设置界面等工作。

## 当前已验证基线

- Android 120Hz 能力协商已经完成；
- Mac 可以创建 120Hz 虚拟显示；
- ScreenCaptureKit、VideoToolbox、网络发送、Android 接收、MediaCodec 解码和 Surface 渲染已经形成完整高刷新链路；
- OnePlus OPD2413、Android SDK 36、WiFi、HEVC 环境下，当前端到端实测约为：
  - capture：110 FPS；
  - encode：109 FPS；
  - send：110 FPS；
  - receive：111 FPS；
  - decode：111 FPS；
  - render：110 FPS；
- Android 实际显示模式已经确认运行在约 120Hz；
- H.264/60fps fallback 已真机验证；
- Mac 和 Android 构建已通过；
- 当前剩余主要问题：
  1. 尚未达到长期稳定满 120 FPS；
  2. USB/ADB reverse 尚未实现；
  3. 长时间稳定性、异常恢复和多设备兼容尚未充分测试；
  4. 端到端延迟统计仍需要完善；
  5. WiFi 配对和连接安全尚未完成；
  6. iOS/iPadOS 120Hz 尚未实现；
  7. 正式发布、签名、公证和文档尚未完成。

---

# 总体目标

将当前项目从“Android WiFi 高刷新技术验证版本”完善为：

> 一个可持续维护、可测试、可发布的 macOS 跨设备扩展显示项目，支持 Android WiFi 和 USB/ADB reverse、本地 HEVC 高刷新传输、H.264 自动回退、完整性能统计、稳定恢复、多设备兼容，并为后续 iOS/iPadOS 120Hz 扩展保留清晰架构。

---

# 总体工作规则

1. 不要重新实现已经完成的功能。
2. 不要进行与当前目标无关的大规模重构。
3. 不允许破坏当前已经可用的：
   - Android WiFi；
   - HEVC；
   - H.264 fallback；
   - 60fps；
   - 90fps；
   - 120fps；
   - streamConfig；
   - 性能统计；
   - 高刷新 Surface；
   - 旧协议兼容。
4. 每个阶段必须先完成测试，再进入下一阶段。
5. 每个阶段结束时必须输出：
   - 修改文件清单；
   - 修改原因；
   - 测试结果；
   - 性能变化；
   - 回退机制；
   - 已知风险；
   - 下一阶段建议。
6. 每个阶段都必须尽量执行：
   - Android Gradle build；
   - Android unit test；
   - Mac Swift self-test；
   - macOS xcodebuild；
   - `git diff --check`。
7. 构建失败时停止新增功能，只修复当前错误。
8. 不允许通过删除测试、绕过异常或硬编码结果使测试通过。
9. 性能数据必须来源于真实统计，不允许伪造。
10. 请求 120fps 不等于达到 120fps，必须以实际 capture、encode、send、receive、decode 和 render 数据判断。
11. 如果参考或移植 SideScreen 具体代码，必须保留 MIT 许可证声明，并更新 `THIRD_PARTY_NOTICES.md`。
12. 项目整体继续遵守 GPL-3.0。
13. 每完成一个稳定阶段，建立清晰的 Git checkpoint 或提交建议，方便回退。
14. 不要一次同时修改捕获、编码、传输和解码多个核心环节，性能优化必须逐层验证。

---

# 阶段一：建立标准 Benchmark 模式

## 目标

建立固定、可重复、可比较的高刷新性能测试环境。

## 实现要求

1. 保留当前 MTKView 120fps 动态测试源。
2. 将测试源整理为独立 Debug Benchmark Mode。
3. Benchmark Mode 不得影响正式发行模式。
4. 支持固定测试配置：
   - 1920×1080；
   - 2560×1600；
   - 当前 Android 原生分辨率；
   - HEVC；
   - H.264；
   - 60fps；
   - 90fps；
   - 120fps；
   - 固定码率；
   - Auto 码率。
5. 增加性能结果导出功能。
6. 支持导出 CSV 或 JSONL。

至少记录：

```text
timestamp
requestedFps
selectedFps
actualVirtualDisplayRefreshRate
contentProducedFps
captureFps
encodedFps
sentFps
receivedFps
decodedFps
renderedFps
codec
bitrate
averageFrameSize
encodeLatencyMs
decodeLatencyMs
endToEndLatencyMs
latestFrameAgeMs
queueDepthMac
queueDepthAndroid
droppedFramesMac
droppedFramesAndroid
androidDisplayRefreshRate
transport
Mac CPU
Mac memory
Android temperature（如可读取）
```

如果某字段无法可靠获取，使用：

```text
notAvailable
```

不得生成伪数据。

建立内部验收等级：

```text
High Refresh Passed：
10 分钟平均 renderedFps ≥ 100

Near 120：
10 分钟平均 renderedFps ≥ 115
且无持续队列积压

Stable 120：
10 分钟平均 renderedFps ≥ 117
绝大部分时间处于 115～120
且延迟和队列不持续增长
```

完成后更新：

```text
docs/benchmark-guide.md
```

---

# 阶段二：长期稳定性和异常恢复测试

## 目标

证明当前高刷新链路不仅能运行，而且可以长期使用。

建立自动或半自动测试流程。

测试时长：

```text
10 分钟
30 分钟
2 小时
```

必须观察：

```text
FPS 是否持续下降
延迟是否持续增加
Mac 内存是否持续增长
Android 内存是否持续增长
CPU 占用是否异常增加
温度是否持续升高
是否出现黑屏
是否出现花屏
是否停止更新
是否出现 codecFailure
是否出现持续 keyframe request
队列是否持续堆积
丢帧是否异常增长
```

增加异常恢复测试：

```text
Android App 关闭后重新打开
Android App 切后台后恢复
Android 锁屏后解锁
Mac 睡眠后唤醒
WiFi 断开 10 秒后恢复
Mac 更换 WiFi
Android 更换 WiFi
路由器短暂断开
强制 HEVC 初始化失败
强制切换 HEVC → H.264
重复连接和断开 50 次
Android Surface 重建
Android 横竖屏变化
Mac 虚拟显示重建
```

每种异常必须明确：

```text
自动恢复
自动重连
自动 fallback
显示错误提示
或要求用户手动重新连接
```

不得静默黑屏。

输出：

```text
docs/stability-test-report.md
```

---

# 阶段三：实现 USB/ADB reverse

## 目标

在保留 WiFiTransport 的前提下，实现 Android USB 低延迟传输。

当前已有：

```text
ReceiverTransport
└── WifiTcpReceiverTransport
```

目标结构：

```text
ReceiverTransport
├── WifiTcpReceiverTransport
└── UsbAdbReverseTransport
```

## 实现要求

1. Mac 检测 adb 是否存在。
2. 支持查找以下路径：
   - PATH 中的 adb；
   - Android Studio SDK 默认路径；
   - 用户自定义 adb 路径。
3. 执行：

```bash
adb devices
```

4. 区分：
   - device；
   - unauthorized；
   - offline；
   - multiple devices。
5. 自动建立：

```bash
adb reverse tcp:<PORT> tcp:<PORT>
```

6. Android USB 模式通过 localhost 连接现有协议。
7. 不修改：
   - streamConfig；
   - codec 协商；
   - HEVC；
   - H.264 fallback；
   - decoder；
   - metrics；
   - 视频帧协议。
8. USB 只替换 Transport。
9. USB 不可用时自动回退 WiFi。
10. USB 断开时：
    - 检测连接中断；
    - 尝试恢复 ADB reverse；
    - 恢复失败时提示用户；
    - 如 WiFi 可用，则允许回退 WiFi。
11. Mac UI 增加：
    - Auto；
    - USB；
    - WiFi。
12. Auto 默认优先 USB。
13. Android UI 显示：

```text
Transport: USB
```

或：

```text
Transport: WiFi
```

14. 增加 USB 和 WiFi 对比 Benchmark。

比较：

```text
平均 capture FPS
平均 rendered FPS
端到端延迟
帧率波动
丢帧数量
队列深度
断连恢复时间
平均码率
```

输出：

```text
docs/usb-adb-reverse.md
docs/usb-vs-wifi-benchmark.md
```

---

# 阶段四：定位并优化剩余约 10 FPS

## 目标

明确当前约 110 FPS 的限制位置，并尝试提高至稳定接近 120 FPS。

必须逐层测量：

```text
MTKView 内容生成
↓
虚拟显示提交
↓
ScreenCaptureKit 回调
↓
VideoToolbox 提交
↓
VideoToolbox 编码完成
↓
Socket 发送
↓
Android 接收
↓
MediaCodec 输入
↓
MediaCodec 输出
↓
Surface 实际渲染
```

增加时间点：

```text
contentProducedAt
captureCallbackAt
encoderSubmittedAt
encoderCompletedAt
socketQueuedAt
socketSentAt
androidReceivedAt
decoderSubmittedAt
decoderOutputAt
frameRenderedAt
```

使用：

```text
os_signpost
Instruments Time Profiler
Instruments System Trace
Metal System Trace
```

分析规则：

```text
content = 120
capture = 110
→ 优先检查 WindowServer、虚拟显示提交、ScreenCaptureKit

capture = 120
encode = 110
→ 优先检查 VideoToolbox、像素缓冲、编码队列

encode = 120
send = 110
→ 优先检查 Socket、背压和 Transport

receive = 120
decode = 110
→ 优先检查 MediaCodec

decode = 120
render = 110
→ 优先检查 Surface、Display Mode 和系统合成
```

当前已知：

```text
capture ≈ 110
encode ≈ 109
send ≈ 110
receive ≈ 111
decode ≈ 111
render ≈ 110
```

因此优先检查 Mac 内容生成、虚拟显示和 ScreenCaptureKit。

不要优先重写 Android decoder。

每次只修改一个可能瓶颈。

每次优化必须提供：

```text
修改前 10 分钟平均值
修改后 10 分钟平均值
FPS 改善
延迟变化
CPU 变化
内存变化
丢帧变化
```

如果优化导致：

```text
FPS 提高
但延迟明显增加
```

不得直接接受。

优先低延迟和稳定性，不为了显示 120 数字积压旧帧。

输出：

```text
docs/120fps-performance-analysis.md
```

---

# 阶段五：完善端到端延迟统计

## 目标

让 E2E latency 和 decode latency 具有可靠意义。

当前延迟依赖 Mac 和 Android 时钟偏移。

实现：

1. 建立 ping/pong 时钟偏移估计。
2. 使用多次采样。
3. 排除异常高 RTT。
4. 使用滑动平均或中位数。
5. 记录：
   - RTT；
   - clockOffset；
   - offsetConfidence；
   - sampleCount。
6. 时钟偏移不可靠时：
   - 不显示伪 E2E latency；
   - 显示 unavailable 或 estimating。
7. Android overlay 显示：

```text
RTT
Clock Offset
Frame Age
Encode Latency
Decode Latency
Estimated E2E Latency
```

输出：

```text
docs/latency-metrics.md
```

---

# 阶段六：多 Android 设备兼容测试

## 目标

确认项目不是仅在 OnePlus OPD2413 上运行。

建立：

```text
docs/android-compatibility.md
```

建议至少覆盖：

```text
高通设备 ≥ 2
联发科设备 ≥ 1
三星设备 ≥ 1
60Hz 设备 ≥ 1
90Hz 设备 ≥ 1
120Hz 设备 ≥ 2
Android 11～12 ≥ 1
Android 13～14 ≥ 1
Android 15～16 ≥ 1
```

每台设备记录：

```text
品牌
型号
SoC
GPU
Android 版本
屏幕刷新率
支持的 Display Mode
HEVC Decoder 名称
是否硬件解码
最高稳定分辨率
60fps 状态
90fps 状态
120fps 状态
平均 capture FPS
平均 render FPS
码率
是否黑屏
是否花屏
是否 fallback H.264
是否需要特殊兼容规则
```

不要根据 MediaCodec 宣称支持就直接判定可用。

必须实际初始化和运行。

将已知异常设备整理为兼容规则，但不要针对单一设备写大量散乱硬编码。

---

# 阶段七：WiFi 配对和连接安全

## 目标

避免公开发布后，同一局域网中的未知设备直接连接。

最低实现：

```text
Mac 生成随机配对 Token
↓
Android 输入或扫描二维码
↓
首次握手校验 Token
↓
保存已配对设备
↓
后续自动重连
```

二维码建议包含：

```text
Mac 地址
端口
一次性 Token
协议版本
设备 ID
```

要求：

1. Token 必须使用安全随机数。
2. Token 不得长期明文显示。
3. 支持取消设备授权。
4. 支持查看已配对设备。
5. 支持清除全部配对。
6. 未配对设备不得直接建立视频流。
7. 旧测试模式可保留无配对选项，但必须明确标注：

```text
Developer / Insecure Mode
```

后续评估：

```text
TLS
证书指纹固定
```

不要在未完成安全设计前自行实现不可靠加密。

输出：

```text
docs/pairing-security.md
```

---

# 阶段八：Android Preview Release

## 目标

建立可供外部用户测试的 Preview 版本。

完成：

```text
Release APK
稳定签名密钥
版本号
Release Notes
安装说明
权限说明
FAQ
问题反馈模板
性能日志导出说明
设备兼容表
```

Mac 端提供：

```text
可运行 App
权限引导
屏幕录制权限说明
辅助功能权限说明
未签名或未公证警告说明
```

README 必须准确写：

```text
Experimental 120Hz mode

120Hz display mode verified

Approximately 110 FPS end-to-end verified on tested OnePlus hardware

Actual FPS depends on Mac model, Android hardware, resolution, codec and transport
```

不得写：

```text
Stable 120 FPS on all devices
```

发布前执行：

```text
Android clean build
Android unit tests
APK signature verify
Mac xcodebuild
Swift self-tests
git diff --check
30-minute stability test
HEVC test
H.264 fallback test
WiFi test
USB test（完成后）
```

输出：

```text
docs/release-checklist.md
docs/release-notes-preview.md
```

---

# 阶段九：iOS/iPadOS 120Hz 独立评估

此阶段必须在 Android Preview 稳定后再开始。

不要直接修改现有稳定 iOS 路径。

先建立：

```text
docs/ios-120hz-migration-plan.md
```

只审计：

```text
iOS hello 能力上报
refreshRate
maxFps
HEVC capability
streamConfig
VTDecompressionSession
CADisplayLink
preferredFrameRateRange
Metal rendering
renderedFps
USB/usbmux 兼容
旧 H.264/60fps fallback
```

要求：

1. iOS 高刷新作为独立阶段。
2. 保留当前 OpenDisplay iOS 兼容路径。
3. 不允许 Android 高刷新改造破坏 iPhone/iPad。
4. 先输出计划，不直接大规模修改。

---

# 阶段十：正式发布工程

Android Preview 稳定后，完成：

Mac：

```text
Developer ID 签名
Notarization
DMG
权限引导
版本升级
自动更新评估
```

Android：

```text
Release 签名
版本升级兼容
稳定 APK
应用商店可行性评估
```

仓库：

```text
独立项目名称
README
中文 README
英文 README
演示 GIF
演示视频
架构图
安装文档
FAQ
设备兼容表
Benchmark 数据
Issue 模板
Bug Report 模板
Feature Request 模板
GPL-3.0
THIRD_PARTY_NOTICES
CHANGELOG
SECURITY.md
CONTRIBUTING.md
```

---

# 最终验收标准

Android WiFi：

```text
HEVC 正常
H.264 fallback 正常
60fps 正常
90fps 正常
120Hz 模式正常
高刷新真机验证
30 分钟无崩溃
队列不持续增长
延迟不持续增加
```

Android USB：

```text
ADB 自动检测
ADB reverse 正常
USB 视频传输正常
USB 断开可恢复
USB 失败可回退 WiFi
HEVC 正常
H.264 fallback 正常
```

性能：

```text
高刷新链路平均 render FPS ≥ 100

目标：
平均 ≥ 115

稳定 120 验收：
平均 ≥ 117
且无持续队列积压和延迟增长
```

兼容性：

```text
至少验证多种 Android SoC
至少验证 60Hz、90Hz 和 120Hz 设备
```

发布：

```text
Mac build passed
Android build passed
All tests passed
APK signature verified
Documentation completed
Release package generated
```

---

# 执行方式

按阶段顺序执行。

每一阶段完成后：

1. 运行测试；
2. 修复当前阶段问题；
3. 更新对应文档；
4. 输出阶段总结；
5. 建立 Git checkpoint；
6. 再进入下一阶段。

不要跳过稳定性测试直接增加新功能。

当前首先执行：

> 阶段一：建立标准 Benchmark 模式和可导出的性能基准。

完成阶段一前，不要开始 USB、网络安全或 iOS 120Hz。
