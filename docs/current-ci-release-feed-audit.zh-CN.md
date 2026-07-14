[English](current-ci-release-feed-audit.md) | [简体中文](current-ci-release-feed-audit.zh-CN.md)

# 当前 CI、Release 与更新 Feed 审计

审计日期：2026-07-15。远端证据来自 GitHub 与公开 Pages；全部资产下载到临时目录独立检查。

- 远端 `v0.2.0-preview.5` 精确指向 `4276c1a229f9f0b3237242d3ebbc0f29d7e244da`，是已发布、非 Draft 的 Prerelease。
- Workflow `29350612086` 在相同 SHA 成功；Build-update 与 Feed Deployment Job 均成功。
- 七个预期资产齐全；`SHA256SUMS.txt` 对六个 Payload/Feed 文件全部通过。
- Mac ZIP 为 `0.2.0-preview.5` build 6，包含正确 Sparkle URL 和 EdDSA Public Key；Appcast 引用不可变 Release ZIP 而非 DMG，Size 匹配并含 EdDSA Signature。
- APK 为 versionName `0.2.0-preview.5`、versionCode 6、单一 Signer、V2 Scheme，证书 SHA-256 与 Android Manifest 固定值一致。
- Android Manifest 的 URL、Size、SHA-256、Version 与证书均匹配 APK；公开 Pages 两个 Feed 与 Release Feed 内容一致。
- DMG Checksum 验证成功；当前环境无法 Attach（`device not configured`），因此 Mount Layout 本地复核为环境 Pending；发布 Workflow 中相同完整 Verifier 已成功。

审计前没有普通 PR/Push CI。现新增 `.github/workflows/ci.yml`：Android Test/Debug APK、22 个 Swift Standalone Suite、macOS Debug、iOS Simulator、Site、双语文档、Release Link 与 `git diff --check`。本地全部 Gate 已运行；Workflow 推送前没有远端 CI Run，因此远端状态仍为 Pending。
