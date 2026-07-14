[English](android-async-decoder-audit.md) | [简体中文](android-async-decoder-audit.zh-CN.md)

# Android 异步解码器审计

基线：`79cbf90fdc61bf296a222a10750b2fa7f0a2df1f`  
真机验证：**Pending**

## 发现

### ADC-001 — P0 — 旧 Rendered Callback 可消费当前 Telemetry

- 复现：配置 Codec A，释放后配置 Codec B（时间戳从零重新开始），随后触发 A 延迟到达的 Frame Rendered 回调。
- 根因：普通 `MediaCodec.Callback` 检查 Codec 对象，但 `OnFrameRenderedListener` 没有；共享 Map 只用 presentation timestamp 作键。
- 影响：旧回调可能删除 B 的 telemetry，并通过当前 Listener 上报，污染 First Frame/Render 指标，甚至错误推进当前会话状态。
- 修复：所有回调（含 Frame Rendered）同时校验 Decoder Generation 和 Codec 对象。
- 自动证据：Android 编译、自测试、`test`、`assembleDebug` 通过；平台 Callback 注入测试仍缺失。
- 真机验证：Pending。

### ADC-002 — P0 — renderedTelemetry 可无界增长

- 复现：输出已解码但 Surface 无效、卡住或厂商未发送 Rendered Callback。
- 根因：只有 Rendered Callback 会删除条目，原 Map 无容量和淘汰策略。
- 影响：进程生命周期内存持续增长。
- 修复：改为有插入顺序的存储，最多 512 条，淘汰最旧条目，并保留 Peak/Evicted 内部计数。
- 测试：构建通过；仍需通过 Android 无关的辅助类增加确定性边界测试。

### ADC-003 — P1 — Input Buffer index 所有权无断言

- 复现：厂商或生命周期竞态在 index 被消费前重复发送同一 available-input index。
- 根因：`ArrayDeque` 可接收重复值，没有所有权 Set。
- 影响：同一 Input Buffer index 可能被选择两次。
- 修复：增加 `availableInputBufferSet`；入队只允许一次，取出时移除，Release/Configure 同步清理。

### ADC-004 — P1 — Runtime Codec Error 原来只请求关键帧而不重建

现已本地补正：Input/Output/Codec 终止错误进入单一、合并的 Server Recovery Transition。HEVC 向 Sender 报告失败并回退 H.264；H.264 在 V2 请求 Fresh StreamConfig + Keyframe，Legacy 请求 Keyframe 并从参数集重新配置。Android 自测试与 Debug 构建通过；真实厂商 Codec 故障注入仍为 Pending。

### ADC-005 — P2 — 空 Input Buffer 归还语义较弱

Input Buffer 为 null 或帧过大时，当前通过提交零长度 Buffer 归还 index；尚无证据证明所有厂商 Codec 均安全。更稳妥的后续方案是进入有限 Decoder Reset。

## Pending Frame / 参考链结论

Transport Latest Slot 和 Decoder Pending Slot 都保护 Important Frame。未提交的非关键帧被另一个非关键帧替换时，代码会丢弃新帧、进入 Awaiting Keyframe、拒绝后续依赖帧并请求关键帧。H.264 IDR（NAL 5）及 HEVC IRAP 16–23（包含 IDR 和 CRA）现已识别并由确定性测试覆盖。

| 事件 | 必需身份 | 当前结果 |
| --- | --- | --- |
| Input/Output/Error/Format Callback | Decoder Generation + Codec 对象 | 已补正 |
| Frame Rendered Callback | Decoder Generation + Codec 对象 | 已补正 |
| Listener 交付 | Connection Generation + Session Epoch + Config Version | 已存在 |
| First Frame | 当前 Epoch + Config + 正 Frame Sequence | V2 已存在；Legacy 使用零身份 |
