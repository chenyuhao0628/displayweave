[English](protocol.md) | [简体中文](protocol.zh-CN.md)

# DisplayWeave 协议契约

规范修订版 **1**，2026-10-16。描述 F01–F08 之后的当前源码，不代表已发布 p8 下载包。修订版 1 标识本文和测试样本集，**不改变**任何线上版本、标识或分帧。下述契约由关联解析器实现，并由文末测试覆盖。硬件性能不是协议保证。

## 命名空间与兼容

| 信号 | 含义和启用条件 |
| --- | --- |
| `_opensidecar._tcp`、TCP 9000 | 保留兼容的局域网发现/服务标识。 |
| TXT `security=tls-v1` | 安全监听提示。发现信息未经认证；证书 pin 和配对历史决定信任。 |
| Mac `pv=3` | 上游继承的命名空间，独立于 Android 版本与输入扩展。 |
| `protocolVersion=2` | Android 身份/进度能力，仅在下述六项核心能力齐备时启用。 |
| `binaryFrameHeaderV2` | 独立 Android 二进制视频头能力，不能仅由版本推断。 |
| `appleVideoV1` | iOS 明确的编码/FPS 能力范围；Mac 接收端身份已选择 Apple 能力路径。 |
| `pencil-v1` / `pencil-v2` | 明确协商的基础/高级 Pencil；V2 要求已认证 TLS。 |
| `mac-input-v1` | 明确协商的 Mac 接收端桌面输入；要求已认证 TLS 和两端本地许可。 |

可以忽略未知可选 JSON 成员；未知控制类型不会启用功能。缺少/不完整能力声明选择已有兼容路径。未知二进制版本/标志、非法外层长度、认证失败均拒绝。不能把设备标签当作硬件类型的密码学证明。

## 传输与认证

局域网使用直连 TCP。ADB 转发及所属会话的 usbmux 中继承载同样的字节流，不改变应用协议。安全模式在任何应用帧前启动 TLS，不使用 STARTTLS、带内明文协商或自动明文重试。两端分别显式开启旧版模式；有配对历史的安装 ID 不得降级，撤销配对仍保留历史。

TLS 使用平台实现、双向证书及完整 DER 叶证书的 SHA-256 pin。传输密钥独立于应用/更新签名密钥。TLS 1.2+ 使用 ECDHE/AEAD，也支持 TLS 1.3。Apple 禁用会话票据/恢复；Android 每次连接使用新 SSLContext。当前身份有效期为 365 天，过期/密钥丢失需显式重置并重新配对。持久化、威胁模型与恢复详见[安全设计](secure-transport-design.zh-CN.md)。

认证载荷也使用下述 UInt32 外层分帧，但最大 **4 KiB**，准入绝对截止时间十秒，包含逐字节慢速输入。最多两个待准入连接。认证前不接纳 hello、视频或输入。无效新连接不能替换已认证活动会话。

| 内容 | 精确载荷，网络字节序 |
| --- | --- |
| 邀请文本，最多 2 KiB | `DW1.` + 以下数据的规范无填充 base64url：`DWP1` + UInt16 ID 字节长度 + UTF-8 接收端 ID + 32 字节 pin + 32 字节随机 token。可裁剪文本两端空白。 |
| 客户端认证 `DWA1` | 四个 ASCII 字节 + 一字节标志 + UInt16 长度 UTF-8 发送端 ID + UInt16 长度 UTF-8 发送端名称 + 可选 32 字节 token。标志位 0 表示 token 存在，其余位非法。 |
| 服务端就绪 `DWR1` | 四个 ASCII 字节 + UInt16 长度 UTF-8 接收端 ID，必须匹配发送端 pin 所属的预期身份。 |

ID 非空且最多 256 UTF-8 字节；名称可空且最多 128 字节。拒绝 ASCII 控制字符/DEL、非法 UTF-8、截断和尾随数据。配对窗口 120 秒、只允许一次成功、五次错误 token 后关闭。token 仅在内存，不写入发现信息、日志或偏好。信任记录最多 128 项，包含撤销历史。认证结果必须持久化成功后才可用。

## 外层分帧与资源上限

每帧为 `[UInt32BE 载荷字节数][精确载荷字节]`，长度零非法。TCP 分段无语义；读取器必须处理分片头部/载荷及多帧粘包，帧中 EOF 结束连接。检查对端长度后才允许分配或等待载荷。

| 路径 | 最大应用载荷 |
| --- | --- |
| Apple 接收视频通道 | 16 MiB；每次网络回调最多读 256 KiB。纯 JSON 控制另受 256 KiB 限制。 |
| Android 旧版接收 | 1 MiB。 |
| Android 协商接收 | 默认 8 MiB，受显式 `maxFrameBytes` 协商及绝对 16 MiB 上限限制。 |
| Mac 发送端入站控制 | 严格小于 1 MiB；桌面/Pencil 动作解析器进一步限制为 4 KiB。 |
| Apple 接收端出站输入 | 派发前准入，排队/在途最多合计 64 次写入。iOS 每批含分帧最多 64 KiB；Mac 桌面单条事件最多 4 KiB。溢出关闭所属会话。 |
| Android 出站控制 | 一个工作线程、128 个排队任务、每个控制载荷最多 64 KiB。 |

Android 接收缓冲使用显式引用租约，最多 32 MiB / 32 个缓冲，饱和等待 250 ms。容量不等于载荷有效长度。过期回调、队列替换、解码完成、失败与关闭只释放自身引用。任何使用者仍持有时不得复用缓冲，见[分配契约](android-binary-frame-header-v2.zh-CN.md)。

## Hello、就绪与视频配置

认证后，接收端发送 JSON `hello`，含 `id`、`device`、`pixelsWide`、`pixelsHigh`、`scale`，以及支持的功能和编码/显示能力范围。发送端将 `hello.id` 与已认证/pin 绑定的身份匹配后，才能视为捕获/控制就绪；仅 TCP 连接不算应用就绪。

逻辑桌面几何与编码分辨率独立。Mac `panel` 可携带逻辑点及 1×/2× 缩放。每项 `videoCaps` 同时约束编码、宽/高、帧率和可选每秒像素量；同编码多个条目属于候选范围。发送端必须满足完整范围，并保留可行 H.264 回退。源码 Apple 刷新选择受屏幕、编码和吞吐量约束，最高 120fps；这是请求值，不是实测渲染。

`streamConfig` 声明 `codec`、`width`、`height`、`fps`（Apple 也接受继承字段 `framesPerSecond`），以及适用的码率/身份/帧大小字段。Apple 尺寸须为能力内的正偶数且不超过 8192，FPS 不超过 120，每秒像素量不超过 `4096 × 2304 × 60`。HEVC 失败发送 `codecFailure`，发送端回退 H.264；Apple 接收器允许三秒回退，在该失败连接上不再升级 HEVC。

Android 核心 V2 要求 `protocolVersion >= 2`、Android 身份及以下**全部六项**：`streamConfigAck`、`decoderReady`、`firstFrameRendered`、`sessionEpoch`、`configVersion`、`frameSequence`。`maxFrameBytes` 与 `binaryFrameHeaderV2` 继续独立判定。

```text
TLS/认证 -> hello -> streamConfig -> 匹配 streamConfigAck
         -> 匹配 decoderReady -> 匹配 firstFrameRendered -> streaming
```

进程级正数 `sessionEpoch` 在每个就绪传输递增；每次配置递增正数 `configVersion` 并重置帧序号。每个提交帧递增正数 `frameSequence`，允许跳号。本地 socket generation 另行约束回调归属。过期 generation/epoch/config 或非递增帧序号不能修改解码队列或就绪状态。这些数字不是认证凭据。

Android 进度截止时间分别是 Ack 1.5 秒、解码就绪 2 秒、首帧 3 秒。握手共用两次重试预算，每次发送新配置并请求关键帧；耗尽后允许一次重连，再失败则显式结束。确认渲染首帧后重置跨连接预算。兼容的仅码率重配置可重新绑定已有解码器；编码/FPS/尺寸变化则替换。详见 [Android 协商](android-protocol-v2-negotiation.zh-CN.md)。

## 视频载荷格式

Apple 旧版及未启用二进制头的 Android 保留 `{"cap":1000,"snd":1010}` **紧接** Annex-B NAL 字节，无分隔符，外层不变。仅核心 Android V2 添加紧凑 `se`、`cv`、`fs` JSON 前缀字段。时间戳为 Unix 毫秒。纯 JSON 控制不携带 Annex-B。H.264 使用 SPS/PPS，HEVC 使用 VPS/SPS/PPS；接收端渲染前限制 NAL 数量、参数长度及帧尺寸。

协商后的 Android 二进制载荷为以下精确头部加 Annex-B；外层长度包含头部及载荷：

| 偏移 | 字节 | 字段 |
| ---: | ---: | --- |
| 0 | 4 | ASCII `DWV2` |
| 4 | 1 | 版本 2 |
| 5 | 1 | 标志：关键帧 `0x01`、编码配置 `0x02`、HEVC `0x04`、H.264 `0x08` |
| 6 | 2 | 头部长度 52 |
| 8 | 8 | 会话 epoch |
| 16 | 8 | 配置版本 |
| 24 | 8 | 帧序号 |
| 32 | 8 | 捕获时间戳 |
| 40 | 8 | 发送时间戳 |
| 48 | 4 | Annex-B 载荷字节数 |
| 52 | 可变 | 精确 Annex-B 载荷 |

全部整数为大端序。身份数值为 1…Int64.max，时间戳为 0…Int64.max。编码标志必须恰好一个，未知位非法。载荷非空且最多 `16 MiB − 52`，头长加载荷长必须等于外层载荷长；仍适用更低的协商限制。头部编码须匹配已接受配置。绝不向 Apple 接收器发送 DWV2。

## 控制与生命周期

通用 JSON 控制包含 `ping`/`pong`、`stats`、`kf`、`codecFailure`、`cursor`/`cursorImg`、触摸/滚动以及接收端 closing/sleeping/goodbye 消息。Ping 时间戳/往返估计时钟偏移及存活，不能证明单向显示延迟。光标图片单独限制和校验。`kf` 请求关键帧；Android V2 恢复可附加 `streamConfigRequired`，保证新配置先于 IDR。

Mac 发送端每两秒检查存活，超过五秒无数据判为失联，恢复有界。iOS 同样检查五秒无数据，Mac 接收端为八秒。认证准入使用独立绝对截止时间。停止、角色切换、后台/睡眠或连接失败使所属 generation 失效，取消输入且只关闭自身资源。同一 Mac 收发角色互斥。重连重新执行认证、hello 及适用的配置/就绪流程。同 ID 接口切换见 [Mac 切换指南](mac-lan-handover.zh-CN.md)；Android ADB 恢复独立处理。

## 输入扩展

坐标为左上原点的归一化视频空间。新桌面输入按等比适配区域映射，忽略黑边，拖拽释放钳制在画面内。macOS 物理键码使用发送端键盘布局/输入法。输入功能不代表剪贴板/文件传输或全局键盘捕获。

**触摸与 Pencil V1：** 保留继承的 `touch` 阶段 `began`/`moved`/`ended`/`cancelled`、`x/y` 坐标及 `scroll.dx/dy`。`pencil-v1` 要求 hello 与 `inputConfig` 明确协商。`pencil` 包含 `phase`（`down/move/up/cancel/hover`）、[0,1] 的 x/y/pressure、[−2π,2π] 的 azimuth、[0,π/2] 的 altitude；均须有限数值，不得为 JSON 布尔值。非接触阶段强制零压力。笔画开始时固定旧触摸或原生模式。`proximity` 携带 entering 与归一化位置。

**Pencil V2：** 在已认证 TLS 上另行协商 `pencil-v2`。`pencil2` 保留 V1 字段，要求弧度制 [−2π,2π] 的 `roll` 以及 `pen` 或 `eraser` 的 `tool`。Mac 数位笔事件使用归一化角度。换工具先释放原笔画/接近状态。UIKit 双击及完成的挤压在本机映射为选工具或命名动作，见 [Pencil 高级功能](pencil-advanced.zh-CN.md)。

Pencil 快捷键另需默认关闭的发送端许可与辅助功能。`inputConfig.pencilActionSession` 发放新 UUID；`pencilActionStatus` 解释拒绝/就绪。接收端 `pencilAction` 携带 `inputSession`、严格递增整数 `sequence`（1…2^53−1）及 `undo`、`redo`、`shortcut1`、`shortcut2` 之一的 `action`。键码/修饰键映射由 Mac 配置，此通道不接受任意远端键码。滚动一秒内最多五次，限频拒绝也消耗序号。连接/目标/权限变化撤销授权。每次快捷键先取消数位笔输入并发送完整组合键。

**Mac 桌面输入：** 已认证 Mac hello 声明 `mac-input-v1`。发送端须开启并具辅助功能权限，接收端另行开启。`inputConfig` 发放 `inputSession` UUID、能力及 `inputStatus`。`desktopInput` 携带该 UUID、严格递增整数 `sequence`（1…2^53−1）、`kind` 和 `modifiers`。修饰位是 Shift 1、Control 2、Option 4、Command 8、Caps Lock 16，其余位拒绝。

| 类型 | 额外必需字段 |
| --- | --- |
| `move` | [0,1] 的 x/y |
| `buttonDown`、`buttonUp` | x/y、button 0/1/2（左/右/中）、clicks 1…3 |
| `scroll` | x/y、[−4096,4096] 的 dx/dy |
| `keyDown`、`keyUp` | keyCode 0…127，排除修饰键码 54…63；可选布尔 `repeat` |
| `modifiers` | 仅公共字段；modifiers 表示汇总状态 |
| `releaseAll` | 仅公共字段；释放持有的按键/鼠标键/修饰键 |

最多持有 16 个普通按键和三个鼠标键。忽略重复/旧授权序号。非法字段组合取消当前授权/状态。只采集获得焦点的接收画面；失焦、关闭开关/窗口、角色切换及断线释放输入。Control–Option–Escape 在本机关闭回传。每个事件和空闲变化后两秒内检查许可/权限。系统撤权可能阻止合成释放事件送达，但持有状态始终清空。详见 [Mac 输入](mac-receiver-input.zh-CN.md)。

## 共享样本与验证

[`wire-contract-v1.properties`](../tools/fixtures/wire-contract-v1.properties) 包含公开合成的十六进制样本：外层分帧、旧版遥测、H.264/HEVC DWV2、非法版本/标志/身份/长度，以及 Apple 输入。Swift `WireContractSelfTest` 与 Java `WireContractSelfTest` 使用同一字节集及实际生产解析器/编码器。Swift 覆盖每个分割边界和粘包，Java 覆盖单字节读取、粘包及截断 EOF。Apple 专属输入语义由 Swift 校验；Java 将其作为不透明控制字节验证分帧。

[`secure-pairing-v1.properties`](../tools/fixtures/secure-pairing-v1.properties) 为既有认证/邀请/ready 共享样本。真实 Apple↔Java TLS 和生产接收器运行套件补充字节测试。固定样本不能替代权限、角色/生命周期、原生密钥存储或硬件测试。

```sh
./tools/run-swift-self-tests.sh
(cd AndroidReceiver && ./gradlew --no-daemon test assembleDebug lintDebug)
python3 tools/test-tls-interop.py
python3 tools/test-apple-keychain.py --ios-simulator
python3 tools/test-secure-ios-receiver.py
python3 tools/test-secure-android-receiver.py
pnpm run check:docs
```

规范源码位于 `Shared/ReceiverFrameDecoder.swift`、`Shared/SecurePairingProtocol.swift`、`Mac/DeviceCapabilities.swift`、`Mac/StreamEncodingPolicy.swift`、`Mac/BinaryFrameHeaderV2.swift`、`Shared/AppleVideoPolicy.swift`、`Shared/PencilProtocol.swift`、`Shared/PencilActions.swift`、`Shared/DesktopInputProtocol.swift`，以及 Android 的 `protocol/LengthPrefixedProtocol.java`、`protocol/BinaryFrameHeaderV2.java`、`SecurePairingProtocol.java` 和 `ReceiverProtocolSession.java`。
