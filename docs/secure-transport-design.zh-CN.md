[English](secure-transport-design.md) | [简体中文](secure-transport-design.zh-CN.md)

# 安全传输与配对设计

F03 实施设计，2026-10-16。Apple 发送/接收端与 Android 接收端已完成源码接入。已包含于 v0.3.0-preview.1。完成状态与实际验证记录见[活动清单](feature-completion.zh-CN.md)，用法见[使用指南](secure-transport.zh-CN.md)。

## 方案选择

使用平台 TLS、双向证书持有证明和通过可信外部渠道传递的邀请。Apple 使用 Security / Network.framework，Android 使用 Android Keystore / JSSE。保留原 TCP 9000 端口、Bonjour `_opensidecar._tcp`、外层长度帧及应用消息。新增 `security=tls-v1` TXT 字段描述加密监听端。TLS 位于所有应用帧之前，不使用机会式 STARTTLS，也不在失败后静默重试明文。

每次安装拥有独立的 P-256 传输密钥与自签名 X.509 证书，与应用签名、Sparkle、APK 更新及 ADB 身份分离。Apple 将私钥/证书保存在应用独立的 Keychain 项中，Android 使用 Android Keystore。macOS 显式使用登录钥匙串，因为临时签名预览版没有数据保护访问组；iOS 使用应用的数据保护钥匙串。存储错误不会启用文件回退。固定完整 SHA-256 证书指纹，证书替换必须显式重新配对。Apple 的最小 DER 构造器只编码本地证书，Security 负责签名和 TLS；通过平台证书解析器和跨语言 TLS 测试验证输出。

## 首次配对

1. 接收端主动打开两分钟配对窗口，显示可复制的 `DW1` 邀请，包含安装 ID、完整证书指纹和密码学随机的 256 位一次性密钥。请当面或通过可信渠道传递；它不是短数字验证码，也不是明文首次信任。
2. 发送端导入长度受限的邀请并选择接收端。在发送密钥或屏幕数据之前固定服务端证书，并出示自己的客户端证书。未知客户端证书只有在配对窗口开启时才允许临时完成 TLS，此时尚未准入应用会话。
3. 在 TLS 内发送一个有界 `secureAuth` 帧，包含协议版本、发送端安装 ID 与邀请 token。接收端验证 token 并持久保存信任后，才将 TLS 客户端证书绑定到该 ID。成功消耗 token；五次 token 验证失败关闭窗口。
4. 接收端发送含本机安装 ID 的 `secureReady`，发送端据此保存对等信任，之后才进入原有 hello/视频/输入协议。接收端认证前也不发送 hello、不创建解码状态或输入。待认证 socket 不会替换已认证会话。

## 重连、撤销与兼容

已配对会话在两端都必须符合保存的证书和 ID。证书不能静默替换已有 ID，也不能冒用另一个已记录身份。撤销保留有界历史记录，避免广播字段剥离或全局兼容设置将曾配对设备降级到明文。显式重新配对可以用新证书恢复已撤销身份；单纯网络请求不能触发。

默认加密监听。接收端可显式选择 **不安全旧版兼容**，明确关闭该监听端的 TLS，让旧发送端连接。新发送端也必须显式允许旧版目标，且该 ID 有任何配对历史时都拒绝明文。TLS/认证错误不触发此回退路径。旧版模式仍仅适合可信网络，不能启用新的 Mac 键鼠回传。

Wi-Fi、以太网与 Android ADB 转发使用相同的认证数据流。iOS usbmux 先建立原有设备隧道，再由会话拥有的本地回环中继将 TLS 加密字节转发进去，因为 Network.framework 无法给已完成 usbmux 协商的连接追加 TLS。中继只接纳一个本地客户端，按发送完成回调传递有界数据块，并随会话关闭。认证 hello 到达前不开始屏幕捕获。

## 资源和失败边界

- 邀请 ≤ 2 KiB；认证/准入控制帧 ≤ 4 KiB；最多 128 条信任记录，ID/名称有长度限制且必须是完整有效指纹。
- 每个监听端最多两个待认证 TLS/socket；握手与准入总时限十秒。准入后保持原应用帧上限。
- 一次性 token 按单调时间过期，token/私钥不进入 Bonjour、偏好设置、日志、Benchmark 文件或 Git。
- TLS 1.2+，仅使用提供前向保密的 ECDHE 与 AEAD；可用时使用 TLS 1.3。关闭早期数据和会话恢复，确保每次连接均按当前信任/撤销规则检查证书。
- 存储/身份错误关闭连接并提供可操作提示；已有身份不完整或不可读取时，不静默生成替代密钥。
- 待执行回调包含连接/角色 generation。切换角色、停止、取消、后台化和撤销均取消准入并释放输入。

## 必需证据

Swift/Java 策略向量覆盖邀请长度、准确指纹、错误 ID/token、token 过期/重用、五次失败关闭、持久化失败、撤销、拒绝降级和存储耗尽。真实平台 TLS 回环覆盖 Swift↔Swift、Swift↔Java、错误服务端/客户端证书、待认证超时、异常/认证前视频拒绝、TLS 篡改及无 token 重连。发送/接收集成测试必须证明准入前没有屏幕/输入/应用状态，旧连接无法抢占。仍须通过两端 Apple 构建和 Android 回归。实机网络性能与用户选择的邀请传递渠道是独立边界。

## 官方 API 核查

2026-10-16 已核查官方文档和本机 SDK 头文件：Apple `SecIdentityCreate`（macOS 10.12 / iOS 11.2+）、`sec_protocol_options_set_verify_block`、对端认证及 TLS 版本选项；Android SSLSocket 与 Android Keystore。参考：[Apple 身份](https://developer.apple.com/documentation/security/secidentitycreate(_:_:_:))、[Apple TLS 验证](https://developer.apple.com/documentation/security/sec_protocol_options_set_verify_block(_:_:_:))、[Android TLS socket](https://developer.android.com/reference/javax/net/ssl/SSLSocket)、[Android Keystore](https://developer.android.com/privacy-and-security/keystore)。

## 底层实现说明

应用协议之前的消息采用严格有界二进制字段，避免重复 JSON key 的不同解释：邀请为 `DWP1` + UInt16 ID 长度 + UTF-8 ID + 32 字节证书 SHA-256 + 32 字节 token，再编码为 `DW1.` 后的无填充 base64url；认证为 `DWA1` + 一个表示 token 存在的标记字节 + 带长度的 ID + 带长度的名称 + 可选 32 字节 token；确认为 `DWR1` + 带长度的接收端 ID。长度使用网络字节序，拒绝未知标记、非法 UTF-8 和尾随字节。认证/确认在 TLS 完成后使用原四字节外层长度帧传递。公开合成向量位于 `tools/fixtures/secure-pairing-v1.properties`。

传输证书在创建后 365 天过期，起始日期提供一天时钟容差。Apple SSL 策略拒绝了十年有效期的原型，因此未保留。过期/密钥丢失必须显式重置身份并重新配对，不静默旋转指纹。该寿命与应用签名证书无关。

底层测试使用临时身份和临时测试密钥库，不访问应用已保存的配对密钥。Apple→Apple 和 Apple↔Java 双向均运行真实 TLS。真实钥匙串测试使用随机命名空间，仅删除自己的记录；iOS 部分在一次性模拟器中采用 Xcode 生成的应用签名运行。源码 UI 与会话集成使用相同底层，Android Keystore/运行时与实机证据单独跟踪。

Android Keystore 按 [KeyGenParameterSpec 的 TLS 要求](https://developer.android.com/reference/android/security/keystore/KeyGenParameterSpec.Builder#setDigests(java.lang.String...)) 授权 `DIGEST_NONE`：TLS 提供者先计算握手摘要，再请求 Keystore 对摘要签名。仍授权 SHA-256/384 以签署证书。缺少 TLS 授权的旧密钥会被拒绝并要求显式重置。真实 Keystore 私钥参与 TLS 的测试先复现了该故障，并作为回归门禁；仅使用软件密钥不能覆盖此路径。
