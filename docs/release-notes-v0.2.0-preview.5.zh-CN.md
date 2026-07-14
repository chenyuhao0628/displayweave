[English](https://github.com/chenyuhao0628/displayweave/blob/main/docs/release-notes-v0.2.0-preview.5.md) | [简体中文](https://github.com/chenyuhao0628/displayweave/blob/main/docs/release-notes-v0.2.0-preview.5.zh-CN.md)

# DisplayWeave `v0.2.0-preview.5` 发布说明

[GitHub 预发布版](https://github.com/chenyuhao0628/displayweave/releases/tag/v0.2.0-preview.5) · [Release 工作流](https://github.com/chenyuhao0628/displayweave/actions/runs/29350612086)

## Android 高刷新串流

- Mac 现在统一统计待完成的 VideoToolbox 编码和网络发送，从端到端限制在途任务，避免过时帧在 TCP 中堆积。
- Android 改用异步回调向 MediaCodec 输入数据；解码器暂时无输入槽时，只保留最新的压缩帧。
- 解码吞吐能力来自首选硬件解码器的 Video Capability 与 Performance Point，不再仅根据屏幕刷新率推断。
- 如果编码后的参考帧被丢弃，接收端会拒绝依赖帧直到下一个关键帧，同时请求 Mac 生成该关键帧。

## 刷新率映射

- 请求帧率会优先选择完全一致的显示模式；没有一致模式时选择更高的最近模式，最后才回退到最高模式。
- 因此在支持 60/120/165 Hz 的平板上，请求 90 FPS 会选择 120 Hz，而不是 60 Hz。

## 构建与验证

Release 工作流将目标提交 `4276c1a229f9f0b3237242d3ebbc0f29d7e244da` 构建为 Mac/Android build `6`。Mac Release、未签名 iOS 兼容构建、签名 Android Release、APK 签名验证、完整更新包验证、七个不可变资产上传及 Pages 更新源部署均已通过。

发布前，本次改动还通过 Android Debug 构建与六组 Self Test、Mac 发送队列独立测试、无签名 macOS Debug 构建、双语文档检查、发布链接检查和空白检查。真机吞吐与长时间验证仍待完成，因此实际性能仍取决于硬件。

## 分发边界

Mac 仍为 ad-hoc 签名且未公证；Android 使用项目固定证书进行 v2 签名；iOS 产物仍是未签名 arm64 自签输入包，不属于自动更新。

## SHA-256

| 产物 | SHA-256 |
| --- | --- |
| `DisplayWeave-macOS.dmg` | `9142408567a5ca417c5c5547c7d8a53eb4b87765f369b4899a53444a96fe1316` |
| `DisplayWeave-macOS.zip` | `64b1bbe9c1a38434b9843c336e93fe9c0a6ebb23943a8cb5c6cbfd9ccffdfac8` |
| `DisplayWeave-Android.apk` | `adea5d92d8abd4e1fd97ea9bc5fbad50b4d475c3d5800e79dd5567a6ee153124` |
| `DisplayWeave-Preview-0.1-iOS-unsigned-resigning-input.ipa` | `e0bc60128b0c2f3910dd7bcb5f8d8bdc9fceb0de34965575da0902b78dc1fd00` |
| `appcast.xml` | `721354e100754baea15f352cafdbf4522b84d0f4c5e4451511df86ce03882c5b` |
| `android-update.json` | `1841ce9ba576de691b5405a1056b26d1a6053a1ffe39e30f1945a13f0992f3c3` |
