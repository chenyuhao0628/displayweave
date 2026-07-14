[English](https://github.com/chenyuhao0628/displayweave/blob/main/docs/release-notes-v0.2.0-preview.4.md) | [简体中文](https://github.com/chenyuhao0628/displayweave/blob/main/docs/release-notes-v0.2.0-preview.4.zh-CN.md)

# DisplayWeave `v0.2.0-preview.4` 发布说明

[GitHub 预发布版](https://github.com/chenyuhao0628/displayweave/releases/tag/v0.2.0-preview.4) · [Release 工作流](https://github.com/chenyuhao0628/displayweave/actions/runs/29347755688)

## Android 延迟与恢复控制

- 编码前捕获丢帧不再请求不必要的 IDR；关键帧请求会合并，并记录触发原因。
- Android 会先协商有界单帧尺寸，Mac 才能提高 Legacy Limit；无效和超限帧会在分配或进入 Decoder 前被拒绝。
- MediaCodec 低延迟参数受 Capability Gate 保护并可安全回退。WiFi 低延迟锁和 Surface 帧率提示具备前台、Transport、Surface 与销毁生命周期保护。
- Android Drop 按是否与拥塞相关分类。Mac 可以根据 Queue Age、Send Completion Delay 或 Receiver 证据快速降低本地码率，同时保留缓慢、有界的恢复。

## 二进制帧与测量

- Android 可独立声明 `binaryFrameHeaderV2`。固定网络字节序 Header 携带 Session/Config/Frame Identity、Timestamp、Payload Length、Codec、Keyframe 与 Codec-config Flag。
- Legacy OpenDisplay iOS 和未完整声明能力的 Android Peer 继续使用既有 JSON Telemetry Prefix + Annex-B Bytes。
- VideoToolbox Output 与接收它的 Ready Connection Generation 绑定；旧 Callback 会在 Framing 前丢弃。
- Android 在 Latest-frame Slot 与 MediaCodec Handoff 间保留同一个 Transport Array，使用单次 NAL Summary，并导出 Allocation、Reuse、Pool-miss 与 GC Counter。
- Benchmark CSV/JSONL 新增 Android Thermal Status、Power Saver、Battery Temperature、Battery Level 与 Charging State。平台读数缺失时保持 Unavailable，不以 0 替代。

## 构建与更新验证

手动触发的 Release 工作流把目标提交 `f300f88e84423f2a895d8b15dc3e514362e050bc` 构建为 Mac/Android build `5`。工作流完成 Mac Release Build、未签名 iOS 兼容构建、签名 Android Release Build（`72 actionable tasks`、六组 Android Self Test）、APK Signer 验证、完整更新包验证、资产上传与 Pages Feed 部署。

发布前，同一目标还通过 22 个 Swift Standalone Test、Android 61-task Debug Build、无签名 macOS/iOS Debug Build、Production Site、34 对双语文档及 Release-link Validation。

部署后已验证线上 [Sparkle Feed](https://chenyuhao0628.github.io/displayweave/appcast.xml) 和 [Android Update Feed](https://chenyuhao0628.github.io/displayweave/android-update.json)。Android Feed 与 Release 资产逐字节一致；仓库持久化的 Sparkle Feed 具有相同 Version、Build、URL、Size 与 EdDSA Enclosure Signature，唯一字节差异是提交 XML 的末尾换行。

## 分发边界

Mac 仍为 ad-hoc 签名且未公证；Android 使用项目固定证书进行 v2 签名；iOS 产物仍是未签名 arm64 自签输入包，不属于自动更新。Release 共提供七个不可变资产。

同条件 WiFi/USB 性能、完整真机恢复 V2 矩阵、旧 TestFlight Runtime 兼容、双 Android 与 30 分钟/2 小时耐久仍待完成。没有这些数据时，本版本不声称延迟已经降低。

## SHA-256

| 产物 | SHA-256 |
| --- | --- |
| `DisplayWeave-macOS.dmg` | `a41539f180a2d1854307d70cfaa7328ec14348bdee7ce242e9e478df0f265c50` |
| `DisplayWeave-macOS.zip` | `28cc452cce5168db3813834f59fbb0ad290ac7a30cba83c5f79337bb5cf36a8a` |
| `DisplayWeave-Android.apk` | `11f3b7ce1e765aced8d1dfd255edfda83641f36db0863f37c6a948305e5c7820` |
| `DisplayWeave-Preview-0.1-iOS-unsigned-resigning-input.ipa` | `a43b7b99c861f9d4f60c85f0ce0bcc57e21c428fb106317df89a42fe8966d15a` |
| `appcast.xml` | `4eedf2ce46dc4908de8b8a414f8dd860d8a09042c2cdc9c206dc360428d37049` |
| `android-update.json` | `c225d438f89c615d167a3448016626205a20bb6d12190c58b48742283b33dceb` |
