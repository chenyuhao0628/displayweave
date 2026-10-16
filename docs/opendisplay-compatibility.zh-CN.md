[English](opendisplay-compatibility.md) | [简体中文](opendisplay-compatibility.zh-CN.md)

# OpenDisplay 与 DisplayWeave 互连

DisplayWeave 在主界面直接提供两种连接入口。已有 OpenDisplay 不需要改名或重装，即可使用其支持的串流协议。这些连接入口从 v0.3.0-preview.2（17）引入，并在 v0.3.0-preview.3（18）中保持不变。

| 发送端 → 接收端 | 如何选择 |
| --- | --- |
| DisplayWeave → DisplayWeave | 使用加密配对；接收端生成邀请，发送 Mac 导入 |
| DisplayWeave → OpenDisplay | 发送 Mac 选择 **客户端兼容 → 兼容两种客户端**，在同一设备列表中连接；OpenDisplay 不需要邀请 |
| OpenDisplay → DisplayWeave Mac/iOS/Android | 在 DisplayWeave 接收端主界面选择 **OpenDisplay 兼容**，再从 OpenDisplay 选择该设备 |
| DisplayWeave → 新旧混合接收端 | 发送端启用 **兼容两种客户端**；已配对的 DisplayWeave 继续加密，未配对的 OpenDisplay 使用旧协议 |

发送端选项允许两种协议。接收端按所选模式监听，每次只接收一个发送端；切换模式会断开当前会话。TLS 失败不会自动回退明文。旧版模式未加密，只应在可信网络使用。已知身份的连接计划不能通过移除 TLS 广播、修改或删除 hello ID 绕过信任。匿名旧版对端没有经过认证的身份。由 OpenDisplay 升级的接收端保留原安装 ID；使用加密连接时需要配对。

## 兼容边界

保持 `_opensidecar._tcp` 发现、TCP 9000 端口、四字节网络序长度 framing。Apple 保留旧 JSON/Annex-B 视频格式；只有独立协商能力后，Android 才使用 DWV2 二进制格式。早期无 `id` 的 OpenDisplay hello，只在显式允许兼容且未预期对端 ID 的连接计划中接受。已知身份与加密计划仍要求身份匹配；作废的计划也拒绝匿名对端。

既有 Mac 偏好域迁移、iOS bundle ID、Android 包名/签名身份和更新签名密钥保持不变。接入 protocol-1 对端不会启用 DisplayWeave 专有的安全桌面输入或高级 Pencil 操作。

## 证据与限制

已对照上游 OpenDisplay `origin/main` 的 `b9eec1f`（v1.25.0 appcast 提交）：`Shared/StreamReceiver.swift::sendHello`、`Shared/Protocol.swift`、`Mac/MacSender.swift::sendStreamConfiguration`。测试覆盖无 ID 的早期 Apple hello，以及当前上游新增的 `pv`、`panel`、`videoCaps`、`cursorPort`、`framesPerSecond`；可选未知字段可忽略。Mac 接收端回环测试接受上游形式的 welcome/config 与真实编码的合成 H.264 帧。安全测试保留固定身份、配对/撤销后禁止降级、重置作废约束。

这里验证的是连接/协议兼容，不代表逐项实现全部上游专有功能。上游 UDP 光标、远程电源、更新提示与专有 Pencil 扩展不宣称为 DisplayWeave 功能。实际上游二进制的 Mac/iOS USB/局域网、旋转、输入与耐久仍需执行下表；源码/fixture 检查不能写成完整硬件兼容验证。

## 实体验收矩阵

新→旧、旧→新两个方向均需测试：Mac/iPhone/iPad 接收端的局域网、支持时的 Apple USB，H.264 镜像/扩展、旋转、触摸/滚动、断开重连与休眠唤醒。Android 使用 Mac 发送端测试局域网 H.264，并在发送端支持时测试 ADB USB。记录准确版本、系统/设备、连接方式、分辨率、时长和实际画面行为。增加新旧混合多设备同时连接。虚拟显示器必须有独立在线显示器；如实记录不支持项和 SKIP。
