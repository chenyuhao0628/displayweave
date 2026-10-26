[English](mac-permissions.md) | [简体中文](mac-permissions.zh-CN.md)

# Mac 签名与权限延续

从 `v0.3.0-preview.3`（18）开始，Mac 应用使用固定 Apple Development 身份。Run 和本地打包会强制验证身份并比较升级。早期 preview.2 资产仍为临时签名且保持不变；首次从临时签名迁移可能需要再授权一次，后续固定签名构建保持代码身份连续。

v0.3.2（21）打包时与实际下载的构建 20 应用比较，验证相同代码身份要求、团队、bundle 身份与 arm64/x86_64 架构。未交互重测 20 → 21 隐私权限，下方早期覆盖安装记录保留原验证范围，见[发行证据](../releases/v0.3.2.zh-CN.md)。

## 升级为什么会丢失权限

旧临时签名应用的 designated requirement（应用身份要求）包含程序哈希，每次构建可能不同，仅保留相同 bundle ID 无法维持操作系统认定的代码身份。新流程使用相同的 Apple 证书身份签署连续构建，并检查身份要求一致。Debug 保留 `app.displayweave.mac.debug`，Release 保留 `app.displayweave.mac`。偏好、配对服务、Bonjour、协议和 Sparkle 密钥保持不变。

Apple [TN3179](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy) 建议使用 Apple 颁发的代码签名身份，以可靠追踪本地网络应用身份；[TN3127](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements) 解释了 designated requirement。公证和权限延续是两件事。固定签名不能覆盖用户拒绝、macOS 策略变化或显式签名身份迁移。

## 配置已有签名身份

```bash
security find-identity -v -p codesigning
python3 tools/mac_signing.py configure --identity CERTIFICATE_SHA1
python3 tools/mac_signing.py xcode-settings
```

把占位符替换为已有 **Apple Development** 或 **Developer ID Application** 证书的 40 位 SHA-1。命令签署临时探针以取得真实团队和身份要求，不从证书显示名称猜测团队。本地自签名证书会被拒绝。不会创建、导出或上传密钥。

公开签名元数据固定保存在 Git 外的 `~/Library/Application Support/DisplayWeave/Signing/mac-signing.json`，也可通过 `DISPLAYWEAVE_MAC_SIGNING_CONFIG` 指定位置。后续构建保留这份配置和相同钥匙串身份。证书缺失或过期时，在停止运行中的开发应用之前就会中止构建，不回退临时签名，也不自动选取其他证书。续期证书只有团队和两种构建的身份要求完全一致时才可更新指纹；其他变化需要单独验证迁移。

本机已有的 Apple Development 身份支持本地未公证打包，包括 v0.3.2 正式版；它不等同于 Developer ID 分发或公证。取得发行凭据后使用[正式分发流程](../releases/apple-distribution.zh-CN.md)。GitHub 托管发行 runner 默认没有维护者身份，现会在签名预检处停止；在明确配置 runner 前使用[本地发行流程](../releases/local-release.zh-CN.md)。本次修改没有把签名凭据导出至 GitHub。

## 构建与升级比较

Run 动作和 `tools/package-release.sh` 使用固定配置。已签名 Release 应用启用 hardened runtime，并使用空的 `Mac/OpenSidecarMac.entitlements`，内嵌 Sparkle 框架也签名。验证覆盖每个架构、叶证书、团队、完整身份要求、entitlements、bundle ID、更新源和更新公钥。

```bash
python3 tools/mac_signing.py verify /path/to/new/DisplayWeave.app
python3 tools/mac_signing.py compare /path/to/new/DisplayWeave.app \
  --baseline /path/to/previous/DisplayWeave.app
```

更新打包要求 `DISPLAYWEAVE_MAC_BASELINE_APP` 指向上一份已发布应用。**第一次**从其临时签名迁移时，显式设置 `DISPLAYWEAVE_ALLOW_ADHOC_MIGRATION=1`，回执会标明需要检查重新授权。后续发行使用上一份固定签名应用比较，不再使用此开关。此开关永远不允许固定签名回退为临时签名。已有输出目录会被拒绝。始终发布新版本／构建，不替换 preview.2 文件。

## 用户权限与重复条目

使用安装在 `/Applications/DisplayWeave.app` 的应用。首次签名迁移后，检查“设置 → 权限与诊断”，必要时在 macOS 设置中授权屏幕录制、辅助功能，然后退出并重启。“本地网络：待检查”只表示尚未发现接收端，不足以证明访问被拒绝，应检查操作系统的本地网络开关。

历史构建可能留下多个同名条目。实测 macOS 26.5.2 的本地网络页面没有单条删除入口；删除旧应用副本和 Launch Services 注册并不会删除这些隐私记录。不要为隐藏条目而重置整个系统的隐私／网络数据库。

## 证据与边界

- 修复前回归：实际 Run 脚本在没有固定签名配置时仍携带 `CODE_SIGN_IDENTITY=-` 继续构建。修复后 Run 和预览打包都在编译前停止。
- 自动化：`python3 tools/test-mac-signing.py` 的 20 项全部通过，覆盖身份选择、证书缺失／过期／自签名、续期连续性、全部架构、应用／更新身份、entitlements、显式首次迁移、不可变输出及禁止回退临时签名。实际已发布 preview.2 ZIP 也被识别并拒绝作为固定签名本地应用的降级更新。
- 产物：universal 固定签名 Release 和 Debug 构建均验证通过；已安装 Release 使用正常的空 entitlements 和已签名 Sparkle 成功启动。引导式 DMG 制作、挂载及嵌套签名严格验证通过。既有 12 项正式分发测试、双语文档、发布链接和网站构建也通过。
- 真实钥匙串：`python3 tools/test-mac-signing-runtime.py` 使用生产安全存储代码编译两份不同的签名程序。身份要求一致，第二份无提示读取第一份未变的传输身份和受信任对端。只创建并删除随机测试命名空间。
- macOS 26.5.2 本机交互验收：安装固定签名 build `17`，确认屏幕录制与辅助功能已允许，然后在同一路径覆盖安装程序内容不同的固定签名 build `17.1`。两项权限仍为已允许，无需再次授权。本地网络仍为原来的三个已开启 DisplayWeave 条目。验证后已删除旧应用暂存副本。
- 随后将 `v0.3.0-preview.3` 构建 `18` 在同一路径覆盖安装到固定签名 `17.1`；屏幕录制和辅助功能再次保留，无需再授权，本地网络仍为原有三个开启条目。未保留旧应用备份。
- Build `17.1` 是 **preview.2 的本地验证重构建**，并非已发布版本。该次实验未改变公开下载；preview.3（18）是后续包含此签名修复的发行版。本次不宣称验证了证书到期、跨团队迁移、真实接收端流量、屏幕采集或虚拟显示器行为。未确认独立在线显示器，因此跳过显示／采集测试。
