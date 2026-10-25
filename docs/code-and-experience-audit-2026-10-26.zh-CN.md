[English](code-and-experience-audit-2026-10-26.md) | [简体中文](code-and-experience-audit-2026-10-26.zh-CN.md)

# 代码与使用体验审查 — 2026-10-26
**历史快照：** 下文的 OPEN／未修复状态和“生产代码未改动”均指审查基线。修复进度与当前验收见[可靠性与体验升级](reliability-experience-upgrade.zh-CN.md)。


## 范围与证据口径

审查源码：`01613ef9d118c16992156a8786c0f8d143dea73d`，本地 `main`；初次审查开始时已核对工作远端 `displayweave/main`，两者一致。最新批次为 `39f97a5..01613ef`，即 2026-10-23 合并的 PR #18，共 90 个改动文件；实现提交 `929eb93`，发布准备提交 `1c1c4e3` / `v0.3.0`。本次追加检查扩展到当前 Mac、共享、iOS 和 Android 源码。日期使用工作区给出的 2026-10-26 审查上下文。记录前工作区干净。

**上一轮检查的是最新改动、调用方和相关测试，并不是整个项目逐模块、逐功能的完整产品验收。** 本轮按下方功能覆盖表扩展检查，补充确定性复现及移动端运行、界面证据；仍然**不等于所有代码行、分支、设备和用户路径均已穷举验证**，不提供虚构的覆盖百分比或实机性能认证。

本轮没有修改生产行为。下列十项问题全部为 **OPEN／未修复**；新增内容仅为审查文档和隔离复现工具。复现程序通过，表示观察到了所记录的问题或限制，不代表问题已经修复。编译、既有回归测试通过，也不能排除未覆盖的状态交错。

证据等级：

- **S：** 源码、调用路径及状态检查。
- **D：** 执行真实生产策略，或明确标注的生产方法摘录；后者用替身代替系统操作。
- **R：** 隔离环境中真实运行进程、网络或模拟器中的生产代码。
- **V：** 已获取并查看界面截图；合成视频明确标注，其时延不是实机性能。
- **SKIP：** 未执行的硬件、交互或长时验证。某个模块未列出问题，不代表它已被证明没有缺陷。

## 最新批次原有四项问题

### A01 · P1 · 旧编码回调使强制关键帧状态一直占用 — S/D

**位置：** `Mac/MacSender.swift:2280–2284` 的 `handleEncodedFrame`；`Mac/FrameDropPolicy.swift` 的 `KeyframeRequestTracker`；`helloReady` 和连接替换路径。

**触发条件：** 强制关键帧尚在编码时，连接代际发生变化。重连请求已经入队，旧回调却在 `.stale` 分支提前返回，没有完成旧 `inFlightReason`。此后 `consumePendingRequest()` 因旧请求持续占用而返回 nil；新连接的普通回调又没有强制关键帧原因，不能释放它。

**证据：** [ReconnectKeyframeProbe.swift](../tools/audits/2026-10-26/ReconnectKeyframeProbe.swift) 保留前后版本的真实回调前半段，链接生产关键帧跟踪器和工作计数器。基线能够强制发出重连关键帧，当前版本不能；再追加 100 次新代际回调和请求仍无法清除占用。旧版本为适配新枚举增加的穷举分支不可达，摘录比较时已排除。

**用户影响：** 重连和解码恢复不能再主动获得关键帧，直到整个会话被替换。周期关键帧仍可能恢复画面，因此**不能据此声称必然永久黑屏**。修复方向是让关键帧请求按代际拥有并在退休时清理，同时保留旧回调隔离。真实断线时序仍为 SKIP。

### A02 · P2 · 捕获恢复把旧配置当成最新 hello 已应用 — S/D

**位置：** `Mac/MacSender.swift:900–938` 的 `recoverCapture`，重点为 919–922；恢复完成判断 961–964；hello 分发 1691–1695。

**触发条件：** 捕获中断、`stream == nil` 时，接收端旋转或更改 Apple 解码能力。普通 hello 重配置被跳过；快速恢复路径继续使用旧宽高、FPS 和编码，却返回最新 hello，完成阶段因此误判为已经应用，无需重建。

**证据：** [RecoveryConfigurationProbe.swift](../tools/audits/2026-10-26/RecoveryConfigurationProbe.swift) 使用真实恢复方法、hello 比较和协调器，以替身记录显示器和捕获调用：新 hello 为 `1080×1920`，实际重挂仍是 `1920×1080`，重建次数 `0`，完成逻辑报告配置一致。

**用户影响：** 方向、尺寸可能滞后，也可能继续使用已经不适用的解码/FPS 限制。应保存真正已应用的配置，只在仍兼容时复用。实际锁屏、睡眠和旋转组合尚未测试。

### A03 · P2 · H.264 永久错误触发无限重放 — S/D

**位置：** `Mac/MacSender.swift:2337–2339` 的 `handleEncodeFailure`，以及 `scheduleDropReplay`、`armDropReplay`、`Mac/CaptureRecovery.swift`。

**触发条件：** 有缓存画面时，H.264 编码持续返回 `kVTInvalidSessionErr`。每次失败在 30 ms 后重新安排一次重放，没有重建编码器、次数上限或最终失败处理。

**证据：** [PersistentEncoderFailureProbe.swift](../tools/audits/2026-10-26/PersistentEncoderFailureProbe.swift) 运行真实错误处理、定时方法和重放策略，编码替身固定报错：1.6 秒内 47 次尝试、0 次重建、0 次最终失败，下一轮仍已安排。准确次数随调度略有变化。

**用户影响：** 画面冻结但继续做无效工作，心跳仍可维持连接。Mac 接收端已经收到过视频后，不再保留首帧超时。基线对 H.264 错误的处理也不完整；本批新增的问题是**即使没有新捕获帧，也会自主无限重试**。应区分永久错误，并限制重试、重建预算。实际编码器故障注入仍为 SKIP。

### A04 · P2 · 显示器排列把边坐标相等误判成邻接 — S/D

**位置：** `Mac/DisplayArrangement.swift:145–151` 的 `side(of:relativeTo:preferring:)`。

**触发条件：** 一条边与主屏对齐，但另一轴上完全没有重叠。主屏邻接分支提前生效，跳过了真实相邻显示器的重映射。

**证据：** [ArrangementProbe.swift](../tools/audits/2026-10-26/ArrangementProbe.swift) 直接调用生产几何函数，使用隔离后清理的偏好域：主屏 `(0,0,1920,1080)`，下方屏幕 `(0,1080,1920,1080)`，虚拟屏 `(1920,1580,1080,1920)`，新尺寸 `1920×1080`。当前恢复 y=`1080`，真实邻屏重映射保留 y=`1580`，相差 500 点。

**用户影响：** 旋转或调整尺寸后桌面突然移位。应检查另一轴重叠，并允许有意的角点接触。本复现没有改动任何实际显示器排列。

## 扩展审查新增问题

以下属于当前项目的更广范围问题，不能全部归因于 PR #18。

### A05 · P2 · 局域网自动码率把编码跳帧误当成网络拥堵 — S/D

**位置：** `Mac/AdaptiveBitrateController.swift:243–250` 的 `congestionReason`；`Mac/MacSender.swift` 的编码前丢帧统计、`schedulePing`、`bitrateTransport`、`updateAdaptiveBitrate`。

编码预算不足时的捕获跳帧、编码器无输出丢帧都计入 `dropsThisWindow`。接收端反馈驱动的自动码率只要发现局域网类别 `.wifi` 中 Mac 丢帧非零，就判定拥堵，即使发送队列和接收端队列均为空、发送/编码 FPS 相等、RTT 与帧龄稳定。Ethernet TCP 也属于这个类别。Mac 接收端使用另一套本地控制路径；此项接收端反馈路径影响发送 `stats` 的 iOS/Android 接收端。

**证据：** [ParameterPolicyProbe.swift](../tools/audits/2026-10-26/ParameterPolicyProbe.swift) 直接运行生产控制器，输入发送队列 `0`、发送/编码 `60/60`、RTT `2 ms`、帧龄 `8 ms`、接收端队列/丢帧 `0`，每个 2 秒采样窗口仅一次 Mac 丢帧。局域网经八次降档从 `40 → 8 Mbps`；相同输入下 USB 不降档。这证明在该输入下归因错误，尚未测量真实出现频率或画质评分。

**修复方向：** 区分编码忙造成的跳帧与传输、接收端压力，有明确拥堵证据再降码率。直接抬高最低码率可能反而恶化弱网体验。

### A06 · P2 · iOS 第一次短暂背压就清空参考帧链 — S/D

**位置：** `iOS/PhoneReceiver.swift:785–791` 的 `handleAnnexB` 和 `requestKeyframeIfNeeded`；可对照 `Mac/Receiver/MacVideoRenderer.swift`。

默认系统视频路径一旦发现 `isReadyForMoreMediaData == false` 就 flush，然后拒绝预测帧、等待关键帧。队列短暂满并不等于解码失败。Mac 路径已经容忍有界背压，即额外两帧且不足 50 ms；iOS 尚未采用相应策略。

**证据：** [IOSBackpressureProbe.swift](../tools/audits/2026-10-26/IOSBackpressureProbe.swift) 使用真实生产准入片段和视频层替身：一个未就绪 P 帧触发一次 flush；后续已经恢复就绪的 30 个 P 帧全部被拒绝；关键帧到达后恢复。30 帧是注入的等待序列，**不是实测卡顿持续时间**。真实关键帧可能更快到达，也可能受一秒请求节流或 A01 影响。

**修复方向：** 使用有界策略跨过短暂队列占用，持续积压时再清理并请求恢复；具体阈值需要设备测试。Apple 对 `AVQueuedSampleBufferRendering.isReadyForMoreMediaData` 的文档允许 false 时有界地提交实时媒体，不代表允许无限积压。

### A07 · P2 · Android 在源与接收端宽高比不同时拉伸画面 — S/R/V

**位置：** `AndroidReceiver/app/src/main/java/app/opendisplay/android/MainActivity.java:254–259,303–314` 的 `onStreamConfig`、`buildUi`；`H264SurfaceDecoder.configureAttempt`。

输出 `SurfaceView` 和光标层始终填满父视图；收到视频宽高后没有计算等比适配矩形。MediaCodec 的 scale-to-fit 模式填充 Surface 尺寸，因此横屏镜像、16:9 桌面预设在不同比例屏幕上会变形。

**证据：** [run-android-ux.py](../tools/audits/2026-10-26/run-android-ux.py) 扩展现有一次性 Android 测试环境，真实发送合成 H.264 `640×360` 并截图生产界面。源中的 `120×120` 黑色正方形，在 `1080×2340` 截图里成为 **200×774 像素**的黑色内部区域，测量排除了过滤后的边缘。这是真实模拟器渲染合成内容，并非伪造连接截图或实机显示测量。

**修复方向：** 视频 Surface、光标和输入共用一个等比适配矩形。只修改触摸坐标不能解决画面变形。应覆盖横竖屏、4:3/16:9、窗口变化和黑边区域输入。

### A08 · P2 · Android 关闭指标开关后旧指标仍然可见 — S/R/V

**位置：** `MainActivity.java:485–490,906–909`，指标开关回调及 `refreshStreamingStatus`。

关闭 `KEY_SHOW_METRICS` 会调用 `refreshStreamingStatus`，但后者直接返回，没有替换已经显示的指标字符串；之后每次统计也提前返回。旧数据持续显示，直到其他状态事件覆盖。另一个“状态浮层”开关可以把它整体隐藏，但那是不同的控制。

**证据：** Android UX 测试启动真实合成视频，取消“显示延迟和帧率”，确认复选框为 false，关闭设置后，界面树和截图仍保留旧统计。状态和详细指标默认都开启；竖屏截图中的长指标卡片遮挡了画面上方较大区域。

**修复方向：** 关闭详情时立即切换成简短连接状态；详细指标是否默认开启，可与始终可达的设置入口分开设计。

### A09 · P2 · 手动码率选项与真实会话限制不一致 — S/D

**位置：** `Mac/SenderSettingsView.swift:11–16,87–103`；`Mac/StreamEncodingPolicy.swift:47–60`；`Mac/MacSender.swift` 的 `bitrateTransport`、`selectedBitrate`。

设置页除非明确选 H.264，否则按 HEVC 生成选项；除非明确选局域网，否则按 USB 生成选项。编码、传输都为自动时可选 160 Mbps，但真实局域网连接会限为 100 Mbps，USB H.264 也会限为 100 Mbps。随后修改编码或传输，还可能使已保存的预设从选项中消失，而没有同步修正选择；修正逻辑只在码率模式变化时执行。`SessionRow` 会显示有效目标值，但设置页没有解释两者为何不同。

**证据：** 生产策略探针证明自动模式假设下提供 160，而实际 LAN HEVC、USB H.264 均采用 100；源码确认编码/传输变化时缺少选项修正。本轮没有实际操作 Mac 设置窗口。

**修复方向：** 区分请求值与每个会话的有效值，解释限制来源，处理无效选择。没有证据前仍保留运行时边界。

### A10 · P2 · iOS 仍读取旧的 Mac 丢帧、队列字段 — S/D

**位置：** `iOS/PhoneReceiver.swift:500–504`；`Mac/StreamEncodingPolicy.swift` 的 `StreamDebugStats.pingJson`；`iOS/ReceiverPerformanceView.swift`。

发送端已经使用 `droppedFramesMac`、`queueDepthMac`，iOS 却只读取 `drops`、`pending`。即使线路中传来非零值，新会话仍显示 Mac 丢帧为零、不显示发送队列。Android 已兼容两代字段。

**证据：** 参数探针使用真实发送端序列化 `9/2`，但 iOS 读取的 `drops/pending` 不存在，初始状态保留 `0/0`。这是字段契约不匹配，与估计精度无关。

**修复方向：** 优先读取新字段并兼容旧字段，增加发送端到 iOS 的统计契约测试。也应正确区分提交 FPS、捕获到提交时延与实际面板刷新、上屏时延。

## 参数是否过于保守、是否损害体验

下表区分可重复验证的策略效果和仍需实测的假设，不意味着应把所有安全边界一并放宽。

| ID | 当前参数或行为 | 证据与用户影响 | 后续判断 |
| --- | --- | --- | --- |
| T01 | Apple 统一 `4096×2304×60` 像素/秒上限，保留 H.264 回退能力，按 30/60/90/120 档选择 | D：4K/120 请求在清晰档得到 `3840×2160@60`，均衡档得到 `2880×1620@120`。FPS 设置实际是上限，并不是保证值或“优先保帧率”的优化目标。 | 展示受限原因和清晰度/刷新率取舍；提高设备上限前验证解码能力及回退。 |
| T02 | Mac 本地码率恢复每 0.2 秒采样，要求健康状态连续 5 秒且发送队列严格为 0，每次 +7%，不超过初始目标 | D：降到 35.2 Mbps 后，连续 60 秒保持队列 1/3、最老等待 2 ms、发送/编码 FPS 相等，仍不恢复；队列归零后才恢复。 | 考虑队列年龄、完成速率等健康指标；要测持续滚动场景，不能只测空闲桌面。 |
| T03 | 接收端信号每次降 20%，本地降 12%；连续健康 5 秒后每次升 7% | S/算术：理想情况下 8→40 Mbps 也约需 24 次上涨、120 秒，采样缺口和背压会更久。A05 可能无谓触发这一过程。 | 先修正归因，再比较恢复速度、振荡和文字清晰度。 |
| T04 | 手动/自动 H.264 上限 100 Mbps，HEVC LAN 100 / USB 160，测试模式上限 200 | S/D：Ethernet 也走 LAN 桶，选项还存在 A09。尚无实机证据证明用户链路调到 160/200 会改善延迟或画质。 | 解释上限及传输依据，再对 4K 细字、运动画面做 A/B。 |
| T05 | 平均码率与一秒 DataRateLimits 使用同一目标值 | S：突发帧和 IDR 共用严格的一秒预算。之前的离屏 4K 测试没有测量真实网络码率，也未证明存在欠码率。 | 测实际吞吐、帧大小分布、IDR 恢复及画质后再决定峰值余量。 |
| T06 | 发送端清晰 100%、均衡/流畅 75%、省流 50%；Android 又提供原生/75%/50% | D：2560×1600 接收端选 75%，发送端再选均衡，最终为 1440×900，每轴 56.25%，总像素仅 31.64%。默认是清晰/原生，不是默认就降成这样。 | 展示最终编码像素，解释双重缩放；桌面大小与编码分辨率分开标注。 |
| T07 | Android 传输到解码 FIFO 12 帧，解码输入 FIFO 再 12 帧，这两层策略没有帧龄期限 | S/D：**两层都满时**，24 帧相当于 60 fps 下 400 ms、120 fps 下 200 ms。这是容量换算，不是固定或已测时延。 | 测占用和帧龄尾部，考虑按时间触发恢复；不能随意覆盖依赖前帧的压缩 P 帧。 |
| T08 | Mac 编码预算低于 60 fps 为 1、60 以上为 2；发送预算流畅 1、均衡/省流 2、清晰 3；SCK 队列深度 8 | S 及此前 D/离屏测试：预算小可能导致慢编码器跳帧，预算大可能排队；本机 4K 探针中驱动不支持帧延迟参数。 | 在目标硬件 A/B 帧龄、捕获跳帧、真实上屏和 CPU，不能把容量直接当成固定时延。 |
| T09 | FPS 设置只有自动/60/90/120，没有明确的 30 fps；自动按能力选档 | S：协议支持 30，但弱网、温控、续航及静态办公用户无法直接从设置请求 30。 | 考虑 30 fps/节能选项；没有测量实际省电幅度。 |
| T10 | iOS 手指按下延迟 120 ms 或移动超过 10 pt；Android 等移动或抬手才发按下 | D：Android 生产手势状态在静止长按时不发 down，松手才同时发 down+up。iOS 延迟用于区分双指滚动，Pencil 另走独立路径。 | Android 增加明确的静止按住语义；调低手指延迟时保留防止双指误点的措施。完整桌面应用手势仍为 SKIP。 |
| T11 | hello 超时 5 秒，Android 协商阶段 1.5/2/3 秒，捕获恢复间隔 3 秒，传输退避 0.5/1/2/4/8 秒 | S：等待有上限是必要的；多阶段叠加会有等待感，但没有证据支持统一加长或缩短。 | 展示当前阶段、重试和下一步；在慢设备测冷启动、唤醒及拔插。 |
| T12 | Apple 输入预算 64 / 64 KiB；Android 写队列 128 / 64 KiB；帧绝对上限 16 MiB；Android 缓冲池 32 MiB、等待 250 ms | S 及既有边界测试：用于限制保留工作和避免按键卡住；溢出主动关闭受影响会话。 | 保留边界；若真实笔/触控板突发触顶，优先合并可合并的移动事件并保留释放、取消，不做无限队列。 |
| T13 | Android 默认开启状态和详细指标，iOS 默认关闭分析浮层 | R/V：Android 竖屏长指标卡遮挡内容，A08 又妨碍立即关闭详情。iOS 大字体等待页会换行，操作入口落到首屏以下。 | 简短状态优先，详情可选；补实机滚动、大字及读屏导航检查，不能声称无障碍全面通过。 |

## 完整验收前还需处理的边界

- **B01 — Android 解码光标图片前未限制展开尺寸（S，P2 风险）。** `OpenDisplayServer.java:614–618` 解码 Base64 后，`MainActivity.java:233–242` 直接调用 `BitmapFactory.decodeByteArray`，没有先用 `inJustDecodeBounds` 检查尺寸。外层帧长度约束的是压缩字节，不是展开像素；Apple 端则在创建图片前检查至多 512×512。应补展开像素、几何边界。本轮没有发送耗尽内存的载荷，没有声称已复现崩溃或漏洞利用。默认认证降低了暴露面，显式兼容模式仍接受局域网发送端。
- **B02 — Android 镜像时能力声明与实际视频尺寸不是同一个操作点（S）。** `MacSender.setupMirror` 对非 Apple 接收端按源显示器尺寸捕获；Android 的 `CodecCapabilities.maxSupportedFps` 却按接收端缩放后的面板尺寸声明能力。后续 decoder-ready 可降低 FPS，但不能保证源尺寸本身可解码。应在小屏、弱解码器接收大 Mac 桌面的场景复现，再选择缩放上限或重新协商方案。
- **B03 — iOS 缺少独立首帧超时（S）。** watchdog 检查最近是否收到字节，心跳可维持没有视频的连接；Mac 已有 15 秒首帧期限。需增加“只有心跳、始终没有视频”的受控运行用例；有效首帧后的静止桌面没有新帧，不应仅凭这一点判为卡死。
- **B04 — Android 无障碍 lint 仍有待办。** 本轮 lint 为 0 错误、25 警告，包括 `ClickableViewAccessibility`、`DrawAllocation`、硬编码文案和资源警告。自定义信任管理器警告本身不能证明 TLS 绕过：生产证书固定、准入和实时撤销已通过运行测试。TalkBack、VoiceOver 和完整键盘导航没有测试。

## 逐模块、逐功能覆盖表

此表记录初次审查和本次追加实际检查的范围；测试名对应仓库已有套件，通过不意味着分支穷举覆盖。

| 功能组 | 检查的源码、函数及场景 | 已验证和剩余缺口 |
| --- | --- | --- |
| Mac 角色与生命周期 | `MacRoleController.select`、`SessionLifetime.start/fail/stop`、`SenderController.replace/retry`；清理后替换、旧回调 | S/D，角色及生命周期测试；交互式快速切换 SKIP |
| 发现与路由 | `DirectCable`、`TransportSelectionPolicy`、`MacLANHandoverPolicy`、控制器发现/去重/切换；同 ID、手动退出、有限重试 | S/D，真实有线/无线切换 SKIP |
| USB 资源 | `AndroidAdb`、`AndroidAdbForward`、`Usbmux`、`UsbmuxTLSRelay`；可执行文件查找、会话映射、取消和期限 | S/D，模拟器用到独立 ADB 转发；真实 USB 吞吐/拔插 SKIP |
| 配对和准入 | 共享及 Android 身份、配对、信任代际、TLS、撤销和兼容模式切换 | S/D/R/V，iOS/Android 隔离运行；未动生产身份 |
| 扩展/虚拟显示器 | `setupExtendExclusive`、显示器协调器、拓扑、排列与位置恢复 | S/D，A02/A04；未创建虚拟显示器，实机 SKIP |
| 镜像 | `setupMirror`、主屏选择、源几何及输入目标 | S，B02；实时捕获 SKIP |
| 捕获恢复 | `startCapture`、恢复调度/重挂/重建、来源检查、缓存帧重放 | S/D，A02/A03；睡眠/锁屏/WindowServer 行为 SKIP |
| 编码/FPS/分辨率协商 | `PhoneInfo`、`MacReceiverPolicy.plan`、桌面几何、Apple 包络、Android 解码器及回退上限 | S/D/R，T01/T06/T09；厂商能力真实性及持续 90/120 SKIP |
| 编码工作所有权 | 回调策略、代际计数器、关键帧跟踪、回退工厂、码率属性 | S/D 及先前离屏 VT 探针，A01/A03；Intel 驱动运行时 SKIP |
| 发送/自动码率 | 独立工作预算、本地和接收端 ABR、分帧及超限策略 | S/D，A05、T02–T05/T08；局域网时延/画质 A/B SKIP |
| 分帧/兼容性 | Apple 有界解帧和码流，Android V1/V2 epoch/config/sequence、缓冲池租约 | S/D/R，loopback 和合成流；真实旧版应用互通 SKIP |
| Mac 接收 | 连接接管/代际、首帧超时、HEVC 回退、有界背压、光标、窗口/控制器 | S/D/R loopback；窗口/全屏及真实上屏 SKIP |
| iOS 接收 | hello/config、Annex-B 准入、AV 层/实验 Metal 所有权、存活和后台 | S/D/R，A06/B03；真实高刷/Pencil 硬件 SKIP |
| Android 解码 | 异步 codec 身份、输入索引/统计所有权、参考链恢复、双 FIFO、停滞重建、Surface/Wi-Fi 提示 | S/D/R 合成 H.264；厂商 HEVC/温控/高刷 SKIP |
| 输入 | 桌面授权/序列/释放，触摸滚动校验，Pencil 版本/动作/预算，视图所有权 | S/D/R 协议测试，T10；真实桌面应用、压感和拖动手感 SKIP |
| Mac 界面/设置 | 发送/接收/设置/会话行，重启语义、错误恢复入口、请求与有效值 | S，A09；本轮未新增 Mac 窗口截图，未全面验证键盘和无障碍 |
| iOS 界面 | 等待/引导/设置，浅深色、大字体、固定设置入口 | S/R/V，已查看联系表中的部分截图；横屏串流和 VoiceOver SKIP |
| Android 界面 | 引导/安全模式、设置、合成串流、宽高比和指标开关 | S/R/V，A07/A08；仅隔离 API 35 竖屏环境，非全部设备布局 |
| 指标/诊断 | 发送端 ping 字段、接收端统计/浮层、ABR 输入、有界日志、测试语义 | S/D，A10；区分提交/渲染/上屏，未建立物理时延证据 |
| 更新/发布/网站 | 最新批次脚本和页面、分发测试、仅 GitHub 下载规则、更新策略/签名边界、双语检查 | S/D/构建；未发布、未更新已安装应用、未重做线上发行物验签 |

## 已执行验证和复现入口

生产源码未变，因此保留初次审查的以下有效证据：

- 60 组 Swift 独立测试通过，包括真实 loopback TCP/TLS、注入背压和 Mac 首帧超时用例。
- XcodeGen 和 Mac 无签名 Debug arm64/x86_64 构建通过，工具提示跳过 App Intents 元数据提取。
- 网站 `pnpm build`、双语文档检查（当时 96 对）、发布静态检查（v0.3.0 / 8 项资源）通过。
- 12 项离线 Apple 分发测试、改动的 shell/Python 语法及批次空白检查通过。
- 请求 100 Mbps 的离屏 4K/60 VT 探针：两个策略均编码 180/180 帧，无跳过/失败，约 60 FPS。该环境中 MaxFrameDelayCount、速度优先和硬件查询返回 `-12900`。不能据此证明真实 100 Mbps 吞吐、帧延迟参数生效、Intel 性能或两设备时延。

追加验证：

- 七个记录下来的探针程序均通过，即观察到相应问题或策略行为；生产方法摘录及 SHA-256 快照校验通过。捕获恢复替身有 Swift non-Sendable 捕获警告，它不是应用构建警告，也不作为新增生产问题。
- iOS Simulator 无签名构建通过。
- Android `./gradlew --no-daemon test assembleDebug lintDebug` 通过，执行六个已注册纯 Java 测试组，lint 0 错误/25 警告。Gradle 常规单元测试任务显示 NO-SOURCE，不将它们算成额外测试。
- iOS 隔离运行：真实 TLS hello/video、实时撤销、明文隔离、Pencil V2/V1/未授权动作、视图替换/延迟拆卸、界面截图及后台关闭监听均通过。
- Android 隔离运行：Keystore 持久化/重置/修复、Apple→Android TLS、界面撤销、显式兼容模式切换（三轮）、真实合成 H.264、A07/A08 观察及后台关闭监听均通过。这里的 FPS 是模拟器/测试环境的观察值，不是性能基准。
- 最终 `pnpm run check:docs` 通过（97 对）；已跟踪及新增文件的空白、shell 语法、Python AST、相对链接和双语问题/参数 ID 一致性检查通过。

从仓库根目录执行：

```bash
bash tools/audits/2026-10-26/run-probes.sh
python3 tools/test-secure-ios-receiver.py --screenshots build/diagnostics/code-review-2026-10-26/ios-ui
python3 tools/audits/2026-10-26/run-android-ux.py --screenshots build/diagnostics/code-review-2026-10-26/android-ui
```

探针需要审查快照及 `39f97a5` 基线、Swift/macOS 和 Java。Android UX 另需 ffmpeg 和现有脚本要求的 SDK/API 35 ARM64 镜像。移动端测试依次执行，创建并删除各自拥有的模拟器/AVD，不替换生产应用、身份和设置。相关生产文件发生变化后，哈希/摘录校验会主动停止；应更新审查或转成修复后行为的回归测试，不能继续用旧复现冒充当前证据。

原始日志、截图保留在 Git 忽略的 `build/diagnostics/code-review-2026-10-26/`。持久记录为本双语报告、[复现工具](../tools/audits/2026-10-26/)及源码快照。主要本地证据包括 `recorded-probes.log`、`android-build-tests.log`、`ios-simulator-build.log`、`ios-runtime-ui.log`、`android-runtime-ux.log`、`android-aspect-measurement.json`，以及 `android-ui/android-synthetic-aspect.png`、`android-metrics-disabled.png`；不提交私人截图。

本轮核对的一手 API 资料包括 Apple 的 `AVQueuedSampleBufferRendering.isReadyForMoreMediaData` 文档和 AOSP `MediaCodec.java` 的缩放模式说明。本地副本为 `apple-renderer-readiness.txt`、`android-codec-scaling.txt`；项目特定结论由上述源码和运行证据支撑。

## 后续验收，尚未在本轮执行

优先为 A01–A04 增加状态交错的失败回归并修复，再处理 A05/A06 的归因及恢复、A07/A08 的可见行为、A09/A10 的设置及统计契约；B01 作为解码边界待办。之后再测量 T01–T13，不把所有限制一次性改掉。

调参时使用相同桌面/视频内容，一次只改一个参数，记录请求和实际分辨率/FPS/编码/码率、渲染 FPS、帧龄 p50/p95/p99、丢帧原因、队列峰值、重连时间、CPU 和温控。覆盖 Intel/Apple silicon Mac、不同档位 iOS/Android、Ethernet/Thunderbolt/Wi-Fi/USB、1080p/1440p/4K、60/90/120、细字/滚动/视频/Pencil，以及旋转/唤醒/拔插和长时运行。阈值应从实测基线确定，本审查不杜撰时延目标。

**实机 SKIP：** 尚未建立独立在线显示器条件；未运行 Mac 交互式捕获、接收窗口或虚拟显示器测试；未验证真实双设备 LAN/USB、Intel 驱动、睡眠/锁屏、长时间温控/续航、触控笔或读屏验收。这些缺口仍然存在，因此不能称为“完整产品验收”。
