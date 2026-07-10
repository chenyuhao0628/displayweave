# Android USB Transport 设计

状态：已批准，适用于 DisplayWeave Preview 0.1。

## 结论

DisplayWeave Android USB 采用 **ADB forward**，保持现有连接方向和应用层协议不变：

```text
Mac TCP Client
  -> 127.0.0.1:<per-device-local-port>
  -> adb -s <serial> forward tcp:<per-device-local-port> tcp:9000
  -> Android TCP Server :9000
```

Mac 为每个已授权 Android 设备建立独立的 ADB 端口映射，再使用现有 TCP Sender 连接本机映射端口。Android Receiver 继续监听 9000，不增加新的数据协议，也不改变编解码、输入或统计链路。

不采用 `adb reverse`。它要求把 Mac 改为 TCP Server、Android 改为 TCP Client，与当前架构方向相反，会扩大修改范围并给 WiFi 共存、旧版本兼容、自动重连和多设备会话引入不必要的第二套连接模型。

## 当前架构审计

### 连接角色与端口

- Mac `MacSender` 是主动连接方，`SenderTransport.tcp` 使用 `NWConnection` 连接 Receiver endpoint。
- Android `WifiTcpReceiverTransport` 是被动连接方，使用 `ServerSocket` 接受 Mac 连接。
- Android `OpenDisplayServer` 的 Receiver 端口为 TCP 9000。
- `WifiTcpReceiverTransport` 当前只保留一个活动 client；新连接会替换旧连接。因此一台 Android Receiver 对应一个 Mac `DeviceSession`。

### Transport 边界

- Android `ReceiverTransport` 封装监听、连接、收发和断开事件。
- 当前具体实现是 `WifiTcpReceiverTransport`。虽然名称包含 WiFi，其 TCP Server 同样可接收经 ADB forward 到达的连接；Android 端不需要识别 ADB 隧道。
- Mac `SenderTransport` 当前包含 WiFi TCP 与 Apple `usbmuxd` USB。Apple USB 只能服务 iPhone/iPad，不能复用于 Android ADB。
- Android ADB 是 Mac 端的设备发现、端口映射和 TCP endpoint 管理能力，不是新的 Android 视频 Transport 实现。

### 发现

- Android 使用 NSD 广播 `_opensidecar._tcp.`，TXT `id` 为持久 install ID；这仍只用于 WiFi 发现。
- Android USB 设备由 `adb devices -l` 发现，以 ADB serial 作为 USB 物理连接标识。
- USB 首次连接成功并收到 Android `hello.id` 后，Mac 记录 `serial -> install ID`，用来关联同一 Receiver 的 USB 与 WiFi 身份。
- USB 不注册伪 Bonjour 服务，也不依赖 Android 网络地址。

### 应用层协议

当前双向流使用 4 字节大端长度前缀。payload 是视频 Annex-B 数据或 JSON 控制消息，包括：

- `hello` 设备能力和 install ID；
- `streamConfig` codec、fps、尺寸、码率、profile 和 transport；
- HEVC/H.264 视频帧；
- touch、scroll、cursor 和 cursor image；
- ping、pong、stats；
- keyframe request；
- codec failure 与 H.264 fallback。

ADB forward 只改变字节流经过的路径，以上 wire format、默认值和协商规则全部保持不变。

### 多设备模型

Mac 已使用独立 `DeviceSession` 管理设备会话。Android USB 必须进一步保证每个 ADB serial 拥有：

- 独立动态本地端口；
- 独立 ADB forward 映射；
- 独立 `DeviceSession`；
- 独立 VirtualDisplay、SCStream、VTCompressionSession；
- 独立 Sender transport 和性能统计。

一个设备的断开、映射清理或重连不得取消其他设备的映射或会话。Apple USB、Apple WiFi 和 Android WiFi 会话不受影响。

## 方案比较

| 维度 | A：ADB forward | B：ADB reverse | C：独立 USB 协议 |
| --- | --- | --- | --- |
| 连接方向 | 保持 Mac Client / Android Server | 反转为 Mac Server / Android Client | 可保持方向，但需要新协议栈 |
| 改动范围 | 小，主要在 Mac 连接管理 | 大，Mac 和 Android 都需修改 | 最大，两端均需实现和维护 |
| WiFi 兼容 | 高，共用现有 Sender 和 Receiver | 低，两套角色模型并存 | 中，需维持协议等价性 |
| 多设备 | serial + 独立本地端口 | 需要独立 Mac listener 和 Android client | 需自行设计寻址与复用 |
| 自动重连 | 重建映射并重连 localhost | 两端协调 listener/client 生命周期 | 自行实现完整生命周期 |
| 端口冲突 | 动态探测本地端口 | 需管理 Mac listener 端口 | 取决于新实现 |
| 旧版本兼容 | Android Receiver 无需变更 | 旧 Receiver 不会主动连接 | 旧 Receiver 不支持 |
| 测试难度 | 最低 | 高 | 最高 |
| 长期维护 | ADB CLI + 现有 TCP | 两套连接架构 | 新 transport 和协议栈 |

选择方案 A。方案 C 中“独立 USB Transport”的会话抽象仍有价值，但其底层应是 ADB forward 加现有 TCP 协议，而不是另一套 wire protocol。

## Mac 端组件

### ADB executable 定位

按以下顺序查找第一个可执行文件：

1. 用户配置路径；
2. 当前进程 `PATH` 中的 `adb`；
3. `$ANDROID_HOME/platform-tools/adb`；
4. `$ANDROID_SDK_ROOT/platform-tools/adb`；
5. `~/Library/Android/sdk/platform-tools/adb`；
6. `/opt/homebrew/bin/adb`；
7. `/usr/local/bin/adb`。

用户无需手动修改 PATH。配置路径无效时应报告该路径的问题，并继续给出可操作的修复信息。

### 设备发现与状态

运行 `adb devices -l`，保留每行 serial、state 和描述字段。状态映射为：

- `device`：可以创建映射；
- `unauthorized`：提示用户在设备上允许当前 Mac 的 USB 调试授权；
- `offline`：提示设备离线，并允许有限次数重新探测；
- 无记录：提示未检测到 Android 设备；
- 多个 `device`：Auto 可分别建立独立会话；显式 USB 操作必须允许选择目标设备，不能任意选择第一台。

无法执行 ADB、ADB server 启动失败和命令超时是不同错误，UI 与日志应保留 stderr 摘要。

### 动态端口与映射所有权

每个 serial 分配一个当前可绑定的 loopback TCP 端口。实现不得使用全局固定的 19001。端口分配器需要避免：

- 与当前进程其他 `DeviceSession` 冲突；
- 与系统中已有 listener 冲突；
- 并发发现两台设备时重复分配。

创建命令：

```bash
adb -s <serial> forward tcp:<local-port> tcp:9000
```

随后连接 `127.0.0.1:<local-port>`。映射记录包含 serial、本地端口、远端端口和创建者 session ID。清理时只执行：

```bash
adb -s <serial> forward --remove tcp:<local-port>
```

不得使用 `adb forward --remove-all`。如果进程异常退出留下映射，下次启动可检查 `adb -s <serial> forward --list`，只回收 DisplayWeave 持久记录中属于自己的旧端口。

## Transport 模式与选择逻辑

Mac 设置提供三种模式：

- **Auto**：对可用且已授权的 Android USB 设备优先建立 ADB forward；没有 USB 或 USB 恢复失败时，连接对应 WiFi Receiver。
- **USB**：只使用 Android ADB USB 或现有 Apple USB。Android 失败时显示明确错误，不静默切换 WiFi。
- **WiFi**：保持现有 Bonjour/NSD 行为，不启动 Android ADB 映射。

USB/WiFi 去重优先使用 Receiver `hello.id` 与 NSD TXT `id`。尚未获得 install ID 时，可以把 serial 作为临时会话标识，但不得凭设备显示名永久合并设备。

Auto 回退只在能证明是同一 install ID 时自动切换；身份尚未建立时显示可选择的 WiFi Receiver，避免把虚拟显示切到另一台设备。

## 自动恢复

Android USB socket 断开后的状态机：

```text
connected
  -> socket failed
  -> inspect adb state
  -> recreate this serial's forward
  -> reconnect localhost
  -> resend streamConfig
  -> request keyframe
  -> connected
```

重试使用有上限的指数退避，例如 0.5、1、2、4、8 秒，单次恢复窗口结束后进入 `recoveryFailed`，不能无限快速重试。

Auto 模式恢复窗口失败后，若发现相同 install ID 的 WiFi Receiver，则建立 WiFi transport。切换时：

- 取消旧 socket 和旧 ADB mapping；
- 保留设备的用户流设置；
- 为新连接重新发送 `streamConfig`；
- 重新执行 codec 能力协商，保留 HEVC -> H.264 fallback；
- 请求关键帧，直到首个可解码关键帧到达前显示“正在恢复”，避免把黑屏误报为成功；
- 重建会话所拥有的 VirtualDisplay、SCStream 和 VTCompressionSession，且不影响其他 session。

USB 模式恢复失败后停在明确错误状态，不回退 WiFi。WiFi 模式不触发 ADB 恢复。

## 错误提示

至少提供以下面向用户的状态：

- 未找到 ADB：显示查找过的位置和配置入口；
- 未检测到 Android 设备；
- 设备尚未授权 USB 调试，请在 Android 设备上允许当前 Mac；
- ADB 设备离线；
- 检测到多个 Android 设备，请选择目标设备；
- 无法创建 USB 端口映射；
- Android Receiver 尚未监听 9000，请先打开 DisplayWeave；
- USB 已断开，正在恢复；
- USB 恢复失败；Auto 正在尝试 WiFi；
- USB 恢复失败，且未发现同一设备的 WiFi Receiver。

日志包含 serial 的安全缩写、端口、状态转换、重试次数和 ADB 退出码，但不得记录用户目录中的敏感环境变量或完整控制 payload。

## 安全风险

- ADB USB 调试授权允许该 Mac 对设备执行广泛调试操作，UI 和文档必须说明这是 Android 系统级信任，不只是 DisplayWeave 配对。
- 映射只监听 loopback，不能绑定 `0.0.0.0` 或局域网接口。
- 当前 DisplayWeave WiFi 链路没有加密配对；USB 隧道不修复该 WiFi 限制。Preview Release Notes 必须继续披露。
- ADB executable 必须使用绝对路径和参数数组执行，不能拼接 shell 命令；serial 和端口不得进入 shell 解释上下文。
- DisplayWeave 不自动接受或绕过 Android 的 RSA 授权提示。

## 测试方案

### 自动化测试

- ADB 路径优先级、环境变量展开和不可执行文件处理；
- `adb devices -l` 对 device、unauthorized、offline、空列表和多设备的解析；
- ADB command 参数构造包含 `-s <serial>`，且不经过 shell；
- 动态端口并发分配唯一性与已占用端口跳过；
- 映射创建、精确删除和禁止 `--remove-all`；
- Auto、USB、WiFi 三种选择策略；
- USB 恢复退避、最大尝试次数和取消；
- 相同 install ID 才自动回退 WiFi；
- transport 切换后重发 streamConfig 和请求关键帧；
- 两个 serial 的映射、session 和清理互不影响；
- 现有长度前缀、HEVC/H.264 fallback、触控与滚动自测保持通过。

ADB 测试使用可注入的 process runner 和 socket/port allocator，不要求 CI 连接真机。

### 集成与真机测试

1. 单台已授权 Android：USB 视频、HEVC、H.264 fallback、输入和统计。
2. unauthorized、offline、无设备和多设备的 UI 错误。
3. 两台 Android 同时 USB：本地端口不同，会话互不影响。
4. 一台 Android USB 与另一台 Android WiFi 同时运行。
5. Android USB 与 iPhone/iPad USB/WiFi 同时运行。
6. 拔插 USB、重启 ADB server、关闭/重开 Android App、锁屏/解锁。
7. Auto 从 USB 恢复到 USB，以及恢复失败后切换同一设备 WiFi。
8. USB 显式模式失败时确认不回退 WiFi。
9. 重复连接/断开 50 次，检查端口和 mapping 残留。
10. 10 分钟基础性能测试、30 分钟稳定性测试和 2 小时人工耐久测试。

真机结果记录在 `docs/usb-vs-wifi-benchmark.md` 与 `docs/stability-test-report.md`。未执行的项目必须标记为“待人工验证”，不得写成通过。

## 兼容性边界

- Android Receiver 9000、NSD service type、长度前缀协议和所有 JSON 消息保持兼容。
- 旧 Android H.264/60fps 默认值保持可用。
- HEVC、动态帧率、高刷新请求和 Decoder 不因 USB 修改。
- Apple `usbmuxd` 代码和 iPhone/iPad 会话保持独立。
- Preview 0.1 不包含 iOS/iPadOS 120Hz、音频、Windows/Linux Sender 或互联网远程桌面。

