[English](release-checklist.md) | [简体中文](release-checklist.zh-CN.md)

# 正式版发布检查清单

当前版本：**v0.3.3 / 构建 22**。[发布说明](v0.3.3.zh-CN.md)、[准确文件与哈希](current.zh-CN.md)、[本地命令](local-release.zh-CN.md)。

## 发行记录

- [x] 经维护者授权自审原生源码 `bc928c3`，源码 CI `40447026849` 三项任务通过；未宣称独立审批。
- [x] 本地自动检查和合成显示器证据见[匹配证据](../verification/automatic-desktop-matching.zh-CN.md)。首次两项 iOS 模拟器失败和隔离重跑通过均记录在[发布说明](v0.3.3.zh-CN.md)。
- [x] 构建 22 的 Mac universal 签名、加固运行时、与准确下载构建 21 的身份连续性、独立 Sparkle Ed25519、原 Android 证书和无签名 arm64 iOS 均已验证。

[发行 PR #24](https://github.com/chenyuhao0628/displayweave/pull/24)作为最终 CI、发布和 Pages 验证的合并记录。[v0.3.2 说明](v0.3.2.zh-CN.md)保留上一版本发行回执。

Android 签名证书 SHA-256：`89805f045800ea18b56b84b32e8e31b1710a3c7bf3c85fda54d260d1fc6d589d`。Mac 沿用 Apple Development 签名且未公证，iOS 需要重签。未交互重测 21 → 22 隐私权限；客户双 Mac 匹配、原生 5K 视频、Intel 运行和耐久仍待验收。

本地安装包：`artifacts/releases/v0.3.3/`。[v0.3.1 说明](v0.3.1.zh-CN.md)与[早期清单](../archive/releases/release-checklist-through-v0.3.1.zh-CN.md)保留历史验证范围。

## 后续每次发行

1. 确认授权、干净源码、`displayweave` 远端和新的纯数字正式版本／递增构建号。不发布 preview、beta、RC 或 prerelease。
2. 完成[开发门禁](../development/workflow.zh-CN.md)，审核源码／兼容／签名变化，明确记录无法完成的实机检查。
3. 使用 `tools/package-release.sh`、固定身份及上一份实际公开 Mac 应用作为比较基线，签名材料保持外置。
4. 生成两份更新源，独立核验签名／版本／身份／大小／哈希，原样写入 `public/`。同步更新当前指南、网站与发行检查。
5. 提交并标记与产物匹配的源码，归档跟踪源码、许可证和构建脚本。最终清单包含四个二进制包、两个更新源和源码；加清单共 8 个文件。
6. 以未发布 GitHub 草稿暂存，核验全部附件后直接发布正式版。禁止覆盖公开文件或 tag。下载只使用 GitHub Releases，更新元数据只使用项目 Pages。
7. 合并前要求完整 CI，保留 tag 祖先关系；验证匿名下载和实际在线更新源，再记录结果。确认新正式版可用后，本地仅保留新版本完整安装包。
