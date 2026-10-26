[English](release-checklist.md) | [简体中文](release-checklist.zh-CN.md)

# 正式版发布检查清单

当前公开版本：**v0.3.1 / 构建 20**，2026-10-26 发布。[发布说明](v0.3.1.zh-CN.md)记录行为，[分发指南](current.zh-CN.md)列出准确文件与哈希，[本地发行](local-release.zh-CN.md)提供命令。

## 已完成的发行记录

- [x] 源码 PR #19 和发行 PR #20 已审核合并；`v0.3.1` 指向 `3255e9e1020ae3e90b73f65e16687c67d741e76a`，属于 main 祖先。
- [x] 发行 CI `40251555053` 与合并后 CI `40252277449` 通过，Pages 部署 `40252277411` 成功。
- [x] 独立下载并校验 8 个 GitHub 附件；2026-10-26 核对已发布、正式版与 Latest 状态。两个在线 Pages 更新源与发行副本逐字节一致。
- [x] 验证 Mac 通用架构、签名、hardened runtime、对比构建 19 的身份、Sparkle Ed25519、原 Android 证书及无签名 arm64 iOS 内容。
- [x] 源码／运行验收与实机缺口分别记录于[升级台账](../verification/reliability-experience-upgrade.zh-CN.md)。

Android 签名证书 SHA-256：`89805f045800ea18b56b84b32e8e31b1710a3c7bf3c85fda54d260d1fc6d589d`。Mac 仍为 Apple Development 签名且未公证；iOS 需要重签名。未交互重测 19 → 20 的隐私权限延续；采集／旋转／睡眠恢复、Intel、实机高刷／Pencil、辅助功能和耐久仍待验证。

本地产物位于 `artifacts/releases/v0.3.1/`，必要证据位于 `artifacts/verification/v0.3.1/`。[历史清单](../archive/releases/release-checklist-through-v0.3.1.zh-CN.md)保留原日期与验证范围。

## 后续每次发行

1. 确认授权、干净源码、`displayweave` 远端和新的纯数字正式版本／递增构建号。不发布 preview、beta、RC 或 prerelease。
2. 完成[开发门禁](../development/workflow.zh-CN.md)，审核源码／兼容／签名变化，明确记录无法完成的实机检查。
3. 使用 `tools/package-release.sh`、固定身份及上一份实际公开 Mac 应用作为比较基线，签名材料保持外置。
4. 生成两份更新源，独立核验签名／版本／身份／大小／哈希，原样写入 `public/`。同步更新当前指南、网站与发行检查。
5. 提交并标记与产物匹配的源码，归档跟踪源码、许可证和构建脚本。最终清单包含四个二进制包、两个更新源和源码；加清单共 8 个文件。
6. 以未发布 GitHub 草稿暂存，核验全部附件后直接发布正式版。禁止覆盖公开文件或 tag。下载只使用 GitHub Releases，更新元数据只使用项目 Pages。
7. 合并前要求完整 CI，保留 tag 祖先关系；验证匿名下载和实际在线更新源，再记录结果。确认新正式版可用后，本地仅保留新版本完整安装包。
