[English](release-checklist.md) | [简体中文](release-checklist.zh-CN.md)

# 正式版发布检查清单

发行包：**v0.3.2 / 构建 21**，2026-10-26。[发布说明](v0.3.2.zh-CN.md)、[准确文件与哈希](current.zh-CN.md)、[本地命令](local-release.zh-CN.md)。

## 发行记录

- [x] 经维护者授权自审原生源码 `b01e132`，源码 PR #22 合并为 `1bfa1ca`。未宣称独立审批；使用现有所有者 bypass，未修改仓库规则。
- [x] 源码 CI `40263716075` 三项任务通过；本地运行结果与实机缺口见[iMac 证据](../verification/imac-resolution-performance.zh-CN.md)。
- [x] 构建 21 的 Mac universal 签名、加固运行时、与准确下载构建 20 的身份连续性、独立 Sparkle Ed25519、原 Android 证书和无签名 arm64 iOS 均已验证。
- [ ] 发行 PR CI、不可变 tag／源码归档与 main 祖先关系：验证后记录。
- [ ] 八项 GitHub 文件独立下载／哈希、正式版／Latest 及匿名访问：发布后记录。
- [ ] Pages 部署与两个在线更新源和发行文件逐字节一致：部署后记录。

Android 签名证书 SHA-256：`89805f045800ea18b56b84b32e8e31b1710a3c7bf3c85fda54d260d1fc6d589d`。Mac 沿用 Apple Development 签名且未公证，iOS 需要重签。未交互重测 20 → 21 隐私权限；双 2019 Intel iMac 缩放、延迟、适配和耐久仍待验收。

本地安装包：`artifacts/releases/v0.3.2/`；证据：`artifacts/verification/v0.3.2/` 与 `artifacts/verification/imac-resolution-2026-10-26/`。[v0.3.1 说明](v0.3.1.zh-CN.md)与[早期清单](../archive/releases/release-checklist-through-v0.3.1.zh-CN.md)保留历史验证范围。

## 后续每次发行

1. 确认授权、干净源码、`displayweave` 远端和新的纯数字正式版本／递增构建号。不发布 preview、beta、RC 或 prerelease。
2. 完成[开发门禁](../development/workflow.zh-CN.md)，审核源码／兼容／签名变化，明确记录无法完成的实机检查。
3. 使用 `tools/package-release.sh`、固定身份及上一份实际公开 Mac 应用作为比较基线，签名材料保持外置。
4. 生成两份更新源，独立核验签名／版本／身份／大小／哈希，原样写入 `public/`。同步更新当前指南、网站与发行检查。
5. 提交并标记与产物匹配的源码，归档跟踪源码、许可证和构建脚本。最终清单包含四个二进制包、两个更新源和源码；加清单共 8 个文件。
6. 以未发布 GitHub 草稿暂存，核验全部附件后直接发布正式版。禁止覆盖公开文件或 tag。下载只使用 GitHub Releases，更新元数据只使用项目 Pages。
7. 合并前要求完整 CI，保留 tag 祖先关系；验证匿名下载和实际在线更新源，再记录结果。确认新正式版可用后，本地仅保留新版本完整安装包。
