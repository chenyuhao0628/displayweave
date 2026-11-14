[English](protocol.md) | [简体中文](protocol.zh-CN.md)

# DisplayWeave 协议契约

规范修订版 **2**，2026-11-15。修订版 1（2026-10-16）描述了 F01–F08 之后 `v0.3.0`–`v0.3.5` 的分帧 TCP/mTLS 契约；修订版 2 新增源码分支的认证 UDP 媒体、光标与音频平面（`udpMediaV1`、`udpCursorV1`、`udpAudioV1`）、硬件门控 5K HEVC（`hevc5kV1`）、Display P3 广色域标记（`displayP3`）、`panel` 物理毫米尺寸（`millimetersWide`、`millimetersHigh`），以及复用 `pencil-v1`/`pencil-v2` 与 `mac-input-v1` 的跨平台 iPadOS/Android 手写笔和桌面输入。`v0.3.5` 之后的修订版 2 新增能力**仅在源码分支实现，尚未包含在已发布的 `v0.3.5` 下载包中**；未声明相应能力令牌时完全保留与 `v0.3.5` 及更早对端的线级兼容。下述契约由关联解析器实现，并由文末测试覆盖。硬件性能不是协议保证。

## 命名空间与兼容

| 信号 | 含义和启用条件 |
| --- | --- |
| `_opensidecar._tcp`、TCP 9000 | 保留兼容的局域网发现/服务标识。 |
| TXT `security=tls-v1` | 安全监听提示。发现信息未经认证；证书 pin 和配对历史决定信任。 |
| Mac `pv=3` | 上游继承的命名空间，独立于 Android 版本与输入扩展。 |
| `protocolVersion=2` | Android 身份/进度能力，仅在下述六项核心能力齐备时启用。 |
| `binaryFrameHeaderV2` | 独立 Android TCP 二进制视频头能力，不能仅由版本推断。 |
| `appleVideoV1` | iOS 明确的编码/FPS 能力范围；Mac 接收端身份已选择 Apple 能力路径。 |
| `hevc5kV1` | 源码分支 Mac 硬件 HEVC 接收端能力，仅将 HEVC 范围提升至最高 `5120 × 2880 @ 60`（竖屏 `2880 × 5120 @ 60`）；H.264 回退仍限制为 `4096 × 2304`。 |
| `displayP3` | 源码分支 Apple 流 Display P3 广色域信令（`P3_D65` / `sRGB` / `ITU_R_709_2`）。 |
| `udpMediaV1` | 源码分支认证 AES-128-GCM UDP 视频、奇偶校验 FEC、NACK 与延迟梯度反馈平面，经 mTLS TCP（`udpMediaConfig` / `udpMediaReady`）协商并支持自动回退 TCP。 |
| `udpCursorV1` | 源码分支在活动 `udpMediaV1` 会话上承载 `125 Hz` 归一化光标坐标数据包（`packetType = 5`）；光标 PNG 位图仍走 TCP。 |
| `udpAudioV1` | 源码分支在发送端开启后，经活动 `udpMediaV1` 会话承载可选 `48 kHz` S16LE PCM 系统音频数据包（`packetType = 6`）。 |
| `pencil-v1` / `pencil-v2` | 明确协商的基础/高级手写笔（iPadOS Apple Pencil 及源码分支 Android `TOOL_TYPE_STYLUS` / `TOOL_TYPE_ERASER`）；V2 要求已认证 TLS。 |
| `mac-input-v1` | 明确协商的桌面键盘/指针输入（Mac 接收端，以及源码分支 iPadOS/iOS 与 Android 外接实体键盘/鼠标/触控板）；要求已认证 TLS 和两端本地许可。 |

可以忽略未知可选 JSON 成员；未知控制类型不会启用功能。缺少/不完整能力声明选择已有兼容路径。未知二进制版本/标志、非法外层长度、认证失败均拒绝。不能把设备标签当作硬件类型的密码学证明。

## 传输与认证

局域网使用直连 TCP（源码分支上，Mac 发送端局域网／Bonjour TCP 连接通过 `LANProxyBypassPolicy` 设置 `NWParameters.preferNoProxies = true`，同时保留 `127.0.0.1`／`::1`／`localhost` 回环 ADB 与 usbmux 隧道不受影响）。ADB 转发及所属会话的 usbmux 中继承载同样的字节流，不改变应用协议。安全模式在任何应用帧前启动 TLS，不使用 STARTTLS、带内明文协商或自动明文重试。两端分别显式开启旧版模式；有配对历史的安装 ID 不得降级，撤销配对仍保留历史。

TLS 使用平台实现、双向证书及完整 DER 叶证书的 SHA-256 pin。传输密钥独立于应用/更新签名密钥。TLS 1.2+ 使用 ECDHE/AEAD，也支持 TLS 1.3。Apple 禁用会话票据/恢复；Android 每次连接使用新 SSLContext。当前身份有效期为 365 天，过期/密钥丢失需显式重置并重新配对。持久化、威胁模型与恢复详见[安全设计](secure-transport-design.zh-CN.md)。

认证载荷也使用下述 UInt32 外层分帧，但最大 **4 KiB**，准入绝对截止时间十秒，包含逐字节慢速输入。最多两个待准入连接。认证前不接纳 hello、视频或输入。无效新连接不能替换已认证活动会话。

| 内容 | 精确载荷，网络字节序 |
| --- | --- |
| 邀请文本，最多 2 KiB | `DW1.` + 以下数据的规范无填充 base64url：`DWP1` + UInt16 ID 字节长度 + UTF-8 接收端 ID + 32 字节 pin + 32 字节随机 token。可裁剪文本两端空白。 |
| 客户端认证 `DWA1` | 四个 ASCII 字节 + 一字节标志 + UInt16 长度 UTF-8 发送端 ID + UInt16 长度 UTF-8 发送端名称 + 可选 32 字节 token。标志位 0 表示 token 存在，其余位非法。 |
| 服务端就绪 `DWR1` | 四个 ASCII 字节 + UInt16 长度 UTF-8 接收端 ID，必须匹配发送端 pin 所属的预期身份。 |

ID 非空且最多 256 UTF-8 字节；名称可空且最多 128 字节。拒绝 ASCII 控制字符/DEL、非法 UTF-8、截断和尾随数据。配对窗口 120 秒、只允许一次成功、五次错误 token 后关闭。token 仅在内存，不写入发现信息、日志或偏好。信任记录最多 128 项，包含撤销历史。认证结果必须持久化成功后才可用。

## 外层分帧与资源上限

每条 TCP 帧为 `[UInt32BE 载荷字节数][精确载荷字节]`，长度零非法。TCP 分段无语义；读取器必须处理分片头部/载荷及多帧粘包，帧中 EOF 结束连接。检查对端长度后才允许分配或等待载荷。

| 路径 | 最大应用载荷 |
| --- | --- |
| Apple 接收 TCP 视频通道 | 16 MiB；每次网络回调最多读 256 KiB。纯 JSON 控制另受 256 KiB 限制。 |
| Android 旧版 TCP 接收 | 1 MiB。 |
| Android 协商 TCP 接收 | 默认 8 MiB，受显式 `maxFrameBytes` 协商及绝对 16 MiB 上限限制。 |
| `udpMediaV1` 数据报 | 线级总长 32…1232 字节（`16 B` AAD 头部 + `0…1200 B` 密文 + `16 B` AES-128-GCM 标签）；重组后的单帧 `videoData` 载荷最多 4 MiB、最多 2048 个分片。 |
| Mac 发送端入站控制 | 严格小于 1 MiB；桌面/Pencil 动作解析器进一步限制为 4 KiB。 |
| Apple 接收端出站输入 | 派发前准入，排队/在途最多合计 64 次写入。iOS 每批含分帧最多 64 KiB；Mac/iPadOS 桌面单条事件最多 4 KiB。溢出关闭所属会话。 |
| Android 出站控制 | 一个工作线程、128 个排队任务、每个控制载荷最多 64 KiB。 |

Android 接收缓冲使用显式引用租约，最多 32 MiB / 32 个缓冲，饱和等待 250 ms。容量不等于载荷有效长度。过期回调、队列替换、解码完成、失败与关闭只释放自身引用。任何使用者仍持有时不得复用缓冲，见[分配契约](android-binary-frame-header-v2.zh-CN.md)。

## Hello、就绪与视频配置

认证后，接收端发送 JSON `hello`，含 `id`、`device`、`pixelsWide`、`pixelsHigh`、`scale`，以及支持的功能和编码/显示能力范围。发送端将 `hello.id` 与已认证/pin 绑定的身份匹配后，才能视为捕获/控制就绪；仅 TCP 连接不算应用就绪。

逻辑桌面几何、面板物理尺寸与编码分辨率彼此独立：

- `hello.panel` 可携带逻辑 `pointsWide`/`pointsHigh`、`pixelsWide`/`pixelsHigh`、`scale`，以及可选的物理毫米尺寸 `millimetersWide`/`millimetersHigh`。
- 源码分支上，Mac 接收端仅在 `CGDisplayScreenSize` 有限、处于 `50…2000 mm` 内且未命中合成 72-DPI 回退（双轴满足 `|bounds * 25.4 / 72.0 - raw| <= 1.5 mm`）时上报 `millimetersWide`/`millimetersHigh`，而发送端接受 `10…2000 mm` 范围内的入站 `hello.panel` 毫米值；iOS/iPadOS 为已知机型上报 `50…2000 mm` 物理尺寸，并附带 Split View / 台前调度实时窗口 `pointsWide`/`pointsHigh`/`pixelsWide`/`pixelsHigh`（窗口尺寸变化后防抖重发 `hello`，使发送端无需断线即可更新虚拟显示器比例与采集配置）；Android 在 `DisplayMetrics` `xdpi`/`ydpi` 校准有效时（`50…1000` DPI 且 `10…2000 mm`）上报毫米尺寸，无论是否同时携带逻辑点尺寸均可解析。
- 鉴于 macOS 26.1+ 会拒绝面积小于约 `200 cm²`（`20,000 mm²`）的 `CGVirtualDisplayDescriptor.sizeInMillimeters`，发送端将未上报毫米尺寸的移动端虚拟显示器默认设为 `208 × 96 mm`（竖屏 `96 × 208 mm`），并对面积偏小的上报毫米值按长宽比等比放大至面积 `>= 20,000 mm²` 且单边 `<= 2,000 mm`。

每项 `videoCaps` 同时约束编码、宽/高、帧率和可选每秒像素量；同编码多个条目属于候选范围。发送端必须满足完整范围，并保留可行 H.264 回退。源码 Apple 刷新选择受屏幕、编码和吞吐量约束，最高 120fps；这是请求值，不是实测渲染。

`streamConfig` 声明 `codec`、`width`、`height`、`fps`（Apple 也接受继承字段 `framesPerSecond`），以及适用的码率/身份/帧大小字段；当 Apple 接收端启用 `udpMediaV1` 时，`streamConfig` 还会携带正数 `configVersion`，使 UDP `videoData` 帧与对应配置严格绑定。Apple 尺寸须为能力内的正偶数且不超过 8192，FPS 不超过 120。已发布 `v0.3.5` 下载包默认每秒像素预算为 `4096 × 2304 × 60`（可选 iPad 原生屏幕试验仅提高自身矩形预算）。源码分支上，具备硬件 HEVC 解码且声明 `hevc5kV1` 的 Mac 接收端在保留 `4096 × 2304` 的同时新增 `5120 × 2880 @ 60` 与 `2880 × 5120 @ 60`（`maxPixelsPerSecond = 5120 × 2880 × 60`）HEVC 能力范围；H.264 仍严格封顶 `4096 × 2304`，`codecFailure` 回退前会将 5K 分辨率钳制回 `<= 4096 × 2304` 再重建 H.264。Apple 接收端允许三秒回退，在该失败连接上不再升级 HEVC。当双端同时声明 `displayP3` 时，Apple 视频流标记 Display P3 色域参数（`P3_D65` / `sRGB` / `ITU_R_709_2`）。详见 [Apple 视频指南](../guides/apple-video.zh-CN.md)。

Android 核心 V2 要求 `protocolVersion >= 2`、Android 身份及以下**全部六项**：`streamConfigAck`、`decoderReady`、`firstFrameRendered`、`sessionEpoch`、`configVersion`、`frameSequence`。`maxFrameBytes` 与 `binaryFrameHeaderV2` 继续独立判定。

```text
TLS/认证 -> hello -> streamConfig -> 匹配 streamConfigAck
          -> 匹配 decoderReady -> 匹配 firstFrameRendered -> streaming
```

进程级正数 `sessionEpoch` 在每个就绪传输递增；每次配置递增正数 `configVersion` 并重置帧序号。每个提交帧递增正数 `frameSequence`，允许跳号。本地 socket generation 另行约束回调归属。过期 generation/epoch/config 或非递增帧序号不能修改解码队列或就绪状态。这些数字不是认证凭据。

Android 进度截止时间分别是 Ack 1.5 秒、解码就绪 2 秒、首帧 3 秒。握手共用两次重试预算，每次发送新配置并请求关键帧；耗尽后允许一次重连，再失败则显式结束。确认渲染首帧后重置跨连接预算。兼容的仅码率重配置可重新绑定已有解码器；编码/FPS/尺寸变化则替换。详见 [Android 协商](android-protocol-v2-negotiation.zh-CN.md)。

## TCP 视频载荷格式

Apple 旧版及未启用二进制头的 Android 保留 `{"cap":1000,"snd":1010}` **紧接** Annex-B NAL 字节，无分隔符，外层不变。仅核心 Android V2 添加紧凑 `se`、`cv`、`fs` JSON 前缀字段。时间戳为 Unix 毫秒。纯 JSON 控制不携带 Annex-B。H.264 使用 SPS/PPS，HEVC 使用 VPS/SPS/PPS；接收端渲染前限制 NAL 数量、参数长度及帧尺寸。

协商后的 Android TCP 二进制载荷为以下精确头部加 Annex-B；外层长度包含头部及载荷：

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

## 认证 `udpMediaV1` 媒体、光标与音频平面

源码分支上，凡在已认证 mTLS TCP 会话中于 `hello.capabilities` 声明 `udpMediaV1` 的接收端，均可与既有 TCP 控制通道并行协商按会话隔离的临时 UDP 媒体平面；明文旧版连接绝不启用 UDP 媒体。

### 控制握手与 TCP 自动回退

发送 `streamConfig` 后（以及每次 `sessionEpoch` 递增时），发送端绑定本机临时 UDP 端口，通过 `SystemRandomNumberGenerator` 生成新的 32 字节随机 `rootSecret`，并经 mTLS TCP 发送 `udpMediaConfig`：

```json
{"type":"udpMediaConfig","version":1,"sessionEpoch":1,"udpPort":51234,"rootSecret":"<base64 32 bytes>","maxPayloadBytes":1200}
```

要求 `version == 1`、`sessionEpoch >= 1`、`udpPort` 处于 `1…65535`、`rootSecret` 解码后严格为 32 字节，`maxPayloadBytes` 钳制在 `512…1200`。接收端在修改活动媒体状态前先完整校验控制消息，并强制执行单调 `sessionEpoch` 判定：

- `sessionEpoch < lastAcceptedEpoch`：直接忽略，不拆除当前活动的 UDP 或音频会话。
- `sessionEpoch == lastAcceptedEpoch` 且已有活动 UDP 会话：保留既有 UDP 与音频会话，并用当前绑定的本地 `udpPort` 重发 `udpMediaReady`。
- `sessionEpoch > lastAcceptedEpoch`（或当前无活动 UDP 会话）：替换旧会话，绑定本地临时 UDP 套接字，经 mTLS TCP 回复 `{"type":"udpMediaReady","version":1,"sessionEpoch":1,"udpPort":54321}`，并以 **150 ms** 间隔连续发送最多 **6** 个认证 `probe` 数据报（`packetType = 4`，载荷 `"DWV1-RCV-PROBE"`）。

发送端校验入站 UDP 数据报源 IP 与已认证 mTLS TCP 对端一致后，回复/探测 `"DWV1-PROBE"`（`probeAck` 标志 `0x04`），仅在双向认证连通确认后才将视频、光标与音频切换至 UDP。UDP 就绪期间，TCP `AdaptiveBitrateController` 暂停主动调速，由接收端延迟梯度反馈（`UDPDelayGradientBWE`）统一驱动。若连续超过 **2.5 秒**未收到 UDP 反馈（防火墙拦截、NAT 重绑定或网卡切换），发送端无缝回退至分帧 TCP，通过 `syncCurrentBitrate` 同步当前目标码率，并立即请求关键帧。

### HKDF-SHA256 密钥派生、ROC 与 AES-128-GCM 随机计数器

每个 `sessionEpoch` 按 RFC 5869 HKDF-SHA256 确定性派生双向密钥与基础盐值：

- `hkdfSalt`：ASCII `"DisplayWeave-UDPMediaV1-Salt-2026"`
- `PRK = HMAC-SHA256(key: hkdfSalt, data: rootSecret)`
- `s2rInfo`：ASCII `"displayweave-udp-v1|s2r|<sessionEpoch>"`（`direction = 0`，发送端到接收端）
- `r2sInfo`：ASCII `"displayweave-udp-v1|r2s|<sessionEpoch>"`（`direction = 1`，接收端到发送端）
- `OKM = HKDF-Expand-SHA256(PRK, info, 28)` → 字节 `0…15` 为 16 字节 AES-128 密钥，字节 `16…27` 为 12 字节方向盐值。

每个方向各自维护严格递增的 64 位包序号（`extendedSeq >= 1`），线上 `packetSeq` 携带其低 16 位 `UInt16(extendedSeq & 0xFFFF)`。接收端解密前先核对 `epochTag == UInt8(sessionEpoch & 0xFF)`，再围绕 `highestAuthenticatedSeq` 以无状态翻转计数器（ROC）最近差值法（`delta = Int64(packetSeq) - Int64(highestAuthenticatedSeq & 0xFFFF)` 落在 `−32768…32767`，跨 `0x10000` 边界自动进退位）还原 64 位 `extendedSeq`，并通过 **1024 包**滑动防重放窗口（`UDPAntiReplayWindow`）做解密前预检。12 字节 AES-128-GCM nonce 由对应方向的 12 字节基础盐值拷贝后，将大端 64 位 `directionalSeq = ((UInt64(direction & 0x01) << 63) | (extendedSeq & 0x7FFF_FFFF_FFFF_FFFF))` 异或到字节 `4…11` 得到。防重放窗口仅在 `[16 字节 AAD 头部][密文][16 字节标签]` 通过 AES-128-GCM 认证后才提交状态；伪造或重放包在不修改任何状态的前提下静默丢弃。

### 16 字节 `udpMediaV1` AAD 头部

每个 UDP 数据报均以如下大端序 16 字节明文头部开头（整体作为 AES-128-GCM AAD 参与认证），后接 `0…1200` 字节密文与 16 字节 GCM 标签（线级总长 `32…1232` 字节）：

| 偏移 | 字节 | 字段 |
| ---: | ---: | --- |
| 0 | 1 | `((version & 0x03) << 6) \| ((packetType & 0x07) << 3) \| (flags & 0x07)`（`version = 1`） |
| 1 | 1 | `epochTag`：`UInt8(sessionEpoch & 0xFF)` |
| 2 | 2 | `packetSeq`：方向内 64 位 `extendedSeq` 的低 16 位 |
| 4 | 4 | `sendTimeUs`：单调微秒时间戳（模 `2^32`） |
| 8 | 4 | `frameId`：模 `2^32` 回绕安全的 `UInt32` 标识（`Int32(bitPattern: a &- b) > 0`） |
| 12 | 2 | `fragIndex`：数据分片下标（`videoData`）、打包 FEC 描述符（`videoParity`）或 `0`（`cursor`/`audio`） |
| 14 | 2 | `fragCount`：总分片数 `1…2048`（`videoData`）、打包 FEC 描述符（`videoParity`）或 `1`（`cursor`/`audio`） |

`flags` 位 `0`（`0x01`）为 `keyframe`，位 `1`（`0x02`）为 `endOfFrame`，位 `2`（`0x04`）在 `videoData` 上表示 `retransmit`、在 `probe` 上表示 `probeAck`。拒绝 `packetType == 7` 或 `version != 1`。

### `udpMediaV1` 解密后载荷格式（`packetType` `0…6`）

| `packetType` | 方向 | 精确明文载荷（大端整数） |
| ---: | --- | --- |
| `0`（`videoData`） | `s2r` | 分片满足 `fragIndex < fragCount`（`1 <= fragCount <= 2048`）。重组后的整帧载荷（`<= 4 MiB`）为 `[0…7] captureTimestampMs: Int64` + `[8…15] configVersion: Int64` + 紧接的精确 Annex-B NAL 字节。 |
| `1`（`videoParity`） | `s2r` | 基于 GF(256)（本原多项式 `0x11d`）的系统码 Cauchy/XOR 校验分片，单帧最多 `16` 个分块 × 每块 `1…64` 个数据分片与 `1…15` 个校验分片。第 `0` 行全 `1` 纯异或快速恢复单包丢失，第 `1…14` 行系数为 `inv(UInt8(p) ^ UInt8(16 + j))`。头部 `fragIndex = ((blockIndex & 0x0F) << 12) \| ((blockDataCount & 0xFF) << 4) \| (parityIndexInBlock & 0x0F)`，`fragCount = ((lastDataShardLength & 0x0FFF) << 4) \| (blockParityCount & 0x0F)`（`lastDataShardLength` 处于 `1…1200`）。 |
| `2`（`nack`） | `r2s` | **20 字节：** `[0…3] frameId: UInt32`、`[4…5] baseFragIndex: UInt16`、`[6…7] missingCount: UInt16`、`[8…15] missingBitmap: UInt64`（位 `k` 表示缺失 `baseFragIndex + k`）、`[16…19] rttEstimateUs: UInt32`。 |
| `3`（`feedback`） | `r2s` | **28 字节：** `[0…7] highestSeq: UInt64`、`[8…11] receivedCount: UInt32`、`[12…15] lostCount: UInt32`、`[16…19] arrivalGradientUs: Int32`、`[20…21] decodeQueueMs: UInt16`、`[22…23] renderFps: UInt16`、`[24…27] echoSendTimeUs: UInt32`。 |
| `4`（`probe`） | `s2r` / `r2s` | ASCII `"DWV1-RCV-PROBE"`（接收端探测）或 `"DWV1-PROBE"`（发送端探测 / `probeAck`）。 |
| `5`（`cursor`） | `s2r` | **17 字节**（`udpCursorV1`，要求 `fragIndex == 0 && fragCount == 1`）：`[0…7] sequence: UInt64`、`[8…11] normalizedX: Float32` IEEE-754 `[0, 1]` 有限浮点数（`-0.0` 规范化为 `+0.0`）、`[12…15] normalizedY: Float32` IEEE-754 `[0, 1]` 有限浮点数、`[16] visible: UInt8`（`0` 或 `1`）。接收端丢弃非递增 `sequence`。 |
| `6`（`audio`） | `s2r` | **`16 + N` 字节**（`udpAudioV1`，要求 `fragIndex == 0 && fragCount == 1`）：`[0…3] audioSeq: UInt32`（单调回绕安全）、`[4…11] captureTimestampMs: Int64`、`[12…13] sampleRate: UInt16`（`> 0`，默认 `48000`）、`[14] channels: UInt8`（`1` 或 `2`）、`[15] formatFlags: UInt8`（`0` = S16LE 交错 PCM）、`[16…16+N−1] pcmBytes`（`1 <= N <= 1152` 且 `N % (channels * 2) == 0`；发送端每 `5 ms` 发送 `240` 个立体声采样帧 = `960 B`，接收端环形缓冲上限为 `60 ms` = `2,880` 帧）。 |

FEC 冗余开销（按观测丢包率取 `5%`–`20%`，关键帧至少 `12%`）在设置编码器码率前先从网络总预算中扣除。发送端发包调度器按 `1 ms` 步进与 `1.2×` 预 FEC 速率运行（`maxQueuedPackets = 2048`、`maxQueuedAudioPackets = 16`），严格出队优先级为 `cursor > audio > retransmit > keyframe > normalVideo > fecParity`。未完成重组的 UDP 帧由 `UDPJitterBuffer`（Apple `3` 帧 / `45 ms`）与 Android `JitterBuffer`（`4` 帧 / `35 ms`）有界约束。

## 控制与生命周期

通用 JSON 控制包含 `ping`/`pong`、`stats`、`kf`、`codecFailure`、`udpMediaConfig`/`udpMediaReady`、`cursor`/`cursorImg`、触摸/滚动以及接收端 closing/sleeping/goodbye 消息。Ping 时间戳/往返估计时钟偏移及存活，不能证明单向显示延迟。即便 `udpCursorV1` 通过 UDP 传输 `125 Hz` 坐标，光标贴图本身仍经 TCP 单独限制和校验。`kf` 请求关键帧；Android V2 恢复可附加 `streamConfigRequired`，保证新配置先于 IDR。

v0.3.0 Mac 4K 延迟迭代还会约每两秒发送可选 `macReceiverStats`，包含 `videoEnqueuedFps`、`backpressureFlushes`、`backpressureToleratedFrames`、`waitingForKeyframe`、`cursorReceived`、`cursorApplied`、`cursorCoalesced` 和 `cursorDispatchMaxMs`。旧发送端忽略此类型。不改变分帧，也不提供物理屏幕实测 FPS 或同步单向延迟；与 Android/iOS 的 `stats` 及自适应码率反馈分开处理。参见[本机证据](../verification/mac-4k-latency.zh-CN.md)。

Mac 发送端每两秒检查存活，超过五秒无数据判为失联，恢复有界。iOS 同样检查五秒无数据，Mac 接收端为八秒。认证准入使用独立绝对截止时间。停止、角色切换、后台/睡眠或连接失败使所属 generation 失效，取消输入与音频播放，且只关闭自身资源。同一 Mac 收发角色互斥。重连重新执行认证、hello 及适用的配置/就绪流程。同 ID 接口切换见 [Mac 切换指南](../guides/mac-lan-handover.zh-CN.md)；Android ADB 恢复独立处理。

[v0.3.0 Mac 恢复迭代](../archive/audits/upstream-integration-2026-10-23.zh-CN.md)在连接就绪后，以单调时钟设置 15 秒首帧截止时间。心跳、参数集、重复配置不能满足或延长它；成功构造并提交给渲染器的样本才满足条件，此后静止桌面不受影响。编码/像素尺寸改变会开始新的等待，但不会延长已有等待。超时发送既有 `closing` 控制，最迟 250 ms 内仅取消该套接字；监听器继续可用。分帧和必选控制字段不变。

## 输入扩展

坐标为左上原点的归一化视频空间。新桌面输入按等比适配区域映射，忽略黑边，拖拽释放钳制在画面内。macOS 物理键码使用发送端键盘布局/输入法。输入功能不代表剪贴板/文件传输或全局键盘捕获。

**触摸与 Pencil V1：** 保留继承的 `touch` 阶段 `began`/`moved`/`ended`/`cancelled`、`x/y` 坐标及 `scroll.dx/dy`。`pencil-v1` 要求 hello 与 `inputConfig` 明确协商（由 iPadOS Apple Pencil 接收端以及源码分支支持 `TOOL_TYPE_STYLUS` / `TOOL_TYPE_ERASER` 的 Android 接收端声明）。`pencil` 包含 `phase`（`down/move/up/cancel/hover`）、[0,1] 的 x/y/pressure、[−2π,2π] 的 azimuth、[0,π/2] 的 altitude；均须有限数值，不得为 JSON 布尔值。非接触阶段强制零压力。笔画开始时固定旧触摸或原生模式。`proximity` 携带 entering 与归一化位置。

**Pencil V2：** 在已认证 TLS 上另行协商 `pencil-v2`。`pencil2` 保留 V1 字段，要求弧度制 [−2π,2π] 的 `roll` 以及 `pen` 或 `eraser` 的 `tool`（映射自 Apple Pencil 笔杆旋转/橡皮擦以及 Android 手写笔 `AXIS_TILT` / `TOOL_TYPE_ERASER` / 主侧键）。Mac 数位笔事件使用归一化角度。换工具先释放原笔画/接近状态。UIKit 双击/挤压完成以及 Android 副侧键（`BUTTON_STYLUS_SECONDARY`）在本机映射为选工具或命名动作，见 [Pencil 高级功能](../guides/pencil-advanced.zh-CN.md)。

Pencil 快捷键另需默认关闭的发送端许可与辅助功能。`inputConfig.pencilActionSession` 发放新 UUID；`pencilActionStatus` 解释拒绝/就绪。接收端 `pencilAction` 携带 `inputSession`、严格递增整数 `sequence`（1…2^53−1）及 `undo`、`redo`、`shortcut1`、`shortcut2` 之一的 `action`。键码/修饰键映射由 Mac 配置，此通道不接受任意远端键码。滚动一秒内最多五次，限频拒绝也消耗序号。连接/目标/权限变化撤销授权。每次快捷键先取消数位笔输入并发送完整组合键。

**桌面输入（`mac-input-v1`）：** 已认证 hello 声明 `mac-input-v1`（`v0.3.5+` 的 Mac 接收端，以及源码分支连接间接指针/硬件 `UIKey` HID 键盘的 iPadOS/iOS 接收端与连接外接 `SOURCE_MOUSE` / `SOURCE_TOUCHPAD` / `SOURCE_MOUSE_RELATIVE` 指针及物理 `KeyEvent` 键盘的 Android 接收端）。发送端须开启并具辅助功能权限，接收端另行开启。`inputConfig` 发放 `inputSession` UUID、能力及 `inputStatus`。`desktopInput` 携带该 UUID、严格递增整数 `sequence`（1…2^53−1）、`kind` 和 `modifiers`。修饰位是 Shift 1、Control 2、Option 4、Command 8、Caps Lock 16，其余位拒绝。

| 类型 | 额外必需字段 |
| --- | --- |
| `move` | [0,1] 的 x/y |
| `buttonDown`、`buttonUp` | x/y、button 0/1/2（左/右/中）、clicks 1…3 |
| `scroll` | x/y、[−4096,4096] 的 dx/dy |
| `keyDown`、`keyUp` | keyCode 0…127，排除修饰键码 54…63；可选布尔 `repeat` |
| `modifiers` | 仅公共字段；modifiers 表示汇总状态 |
| `releaseAll` | 仅公共字段；释放持有的按键/鼠标键/修饰键 |

最多持有 16 个普通按键和三个鼠标键。忽略重复/旧授权序号。非法字段组合取消当前授权/状态。只采集获得焦点的接收画面；失焦、场景失活、关闭开关/窗口、角色切换及断线都会发送 `releaseAll` 并清空本机状态。Control–Option–Escape 在 Mac 及源码分支 iPadOS/iOS 接收端本机关闭或释放桌面输入回传。每个事件和空闲变化后两秒内检查许可/权限。系统撤权可能阻止合成释放事件送达，但持有状态始终清空。详见 [Mac 输入](../guides/mac-receiver-input.zh-CN.md)。

## 共享样本与验证

[`wire-contract-v1.properties`](../../tools/fixtures/wire-contract-v1.properties) 包含公开合成的十六进制样本：外层分帧、旧版遥测、H.264/HEVC DWV2、非法版本/标志/身份/长度、桌面与手写笔输入（`desktopPayload`、`pencilPayload`、`actionPayload`），以及 14 项修订版 2 `udpMediaV1` 确定性向量（`udpRootSecret`、`udpS2RKeyEpoch1`、`udpS2RSaltEpoch1`、`udpR2SKeyEpoch1`、`udpR2SSaltEpoch1`、`udpS2RNonceSeq1`、`udpR2SNonceSeq1`、`udpHeaderVideoData`、`udpHeaderCursor`、`udpHeaderAudio`、`udpCursorPayload`、`udpAudioPayload`、`udpCursorSealedDatagram`、`udpAudioSealedDatagram`）。Swift `WireContractSelfTest` 与 Java `WireContractSelfTest` 配合 Swift `UDPMediaProtocolSelfTest`、`UDPMediaFECSelfTest`、`UDPMediaEngineSelfTest`、`UDPMediaTransportSelfTest`、`UDPDelayGradientBWESelfTest`、`MacCoreUpgradeSelfTest` 以及 Android Java `ProtocolSelfTest` 消费同一字节集与实际生产解析器/编码器。Swift 覆盖每个分割边界和粘包，Java 覆盖单字节读取、粘包及截断 EOF。

[`secure-pairing-v1.properties`](../../tools/fixtures/secure-pairing-v1.properties) 为共享认证/邀请/ready 样本。真实 Apple↔Java TLS 和生产接收器运行套件补充字节测试。固定样本不能替代权限、角色/生命周期、原生密钥存储或硬件测试。

```sh
./tools/run-swift-self-tests.sh
(cd AndroidReceiver && ./gradlew --no-daemon test assembleDebug lintDebug)
python3 tools/test-tls-interop.py
python3 tools/test-apple-keychain.py --ios-simulator
python3 tools/test-secure-ios-receiver.py
python3 tools/test-secure-android-receiver.py
pnpm run check:docs
```

规范源码位于 `Shared/ReceiverFrameDecoder.swift`、`Shared/SecurePairingProtocol.swift`、`Shared/UDPMediaProtocol.swift`、`Shared/UDPMediaFEC.swift`、`Shared/UDPMediaEngine.swift`、`Shared/UDPMediaTransport.swift`、`Mac/DeviceCapabilities.swift`、`Mac/StreamEncodingPolicy.swift`、`Mac/BinaryFrameHeaderV2.swift`、`Shared/AppleVideoPolicy.swift`、`Shared/PencilProtocol.swift`、`Shared/PencilActions.swift`、`Shared/DesktopInputProtocol.swift`，以及 Android 的 `protocol/LengthPrefixedProtocol.java`、`protocol/BinaryFrameHeaderV2.java`、`protocol/UdpMediaProtocol.java`、`protocol/AndroidStylusInput.java`、`protocol/AndroidDesktopInput.java`、`UdpMediaReceiverSession.java`、`SecurePairingProtocol.java` 和 `ReceiverProtocolSession.java`。
