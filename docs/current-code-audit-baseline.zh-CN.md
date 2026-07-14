[English](current-code-audit-baseline.md) | [简体中文](current-code-audit-baseline.zh-CN.md)

# 当前代码审计基线

生成时间：2026-07-15 01:06:07 +0800（Asia/Shanghai）

## 实际审查对象

- 仓库：`chenyuhao0628/displayweave`
- 分支：`main`
- 审计 HEAD：`79cbf90fdc61bf296a222a10750b2fa7f0a2df1f`
- `git describe`：`v0.2.0-preview.3-18-g79cbf90`
- Preview 5 目标提交：`4276c1a229f9f0b3237242d3ebbc0f29d7e244da`
- 关系：Preview 5 目标提交是审计 HEAD 的祖先；`main` 领先两个提交。
- 目标提交之后的提交：
  - `b029fb6 docs: publish preview 5 release metadata`
  - `79cbf90 docs: persist preview 5 update feeds`
- 工作区：捕获基线时干净，没有未提交文件。

## Tag 注意事项

捕获基线时本地克隆中不存在 `v0.2.0-preview.5` tag。后续远端验证已证明公开 tag 精确指向 `4276c1a229f9f0b3237242d3ebbc0f29d7e244da`；该结论来自远端证据，而非根据提交标题推断。

## 范围规则

本轮审查以上述 HEAD 的代码和文档为准。除非存在已记录的真实设备运行证据，否则 Android/iOS 真机行为统一标记为 **Pending**。静态审查和自动测试不能替代真机验证。

## 最近提交

```text
79cbf90 (HEAD -> main, displayweave/main, displayweave/HEAD) docs: persist preview 5 update feeds
b029fb6 docs: publish preview 5 release metadata
4276c1a fix: stabilize high-refresh Android streaming
7e6214b docs: clarify preview 4 feed verification
8dbedfc docs: publish preview 4 release metadata
f300f88 feat: record Android thermal and power metrics
03e5e34 feat: add negotiated Android binary frame header
f07b3ad feat: add local fast congestion decrease
54a26c6 feat: classify Android drops for bitrate control
5ef6b61 feat: manage WiFi and Surface latency hints
3d3e323 feat: enable safe decoder low latency
a8e94e1 feat: negotiate safe Android frame sizes
c02ce4e feat: correct keyframe drop recovery policy
d878af1 fix: link localized release notes
d5deecf docs: publish preview 3 release metadata
```
