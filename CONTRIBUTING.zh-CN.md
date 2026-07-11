[English](CONTRIBUTING.md) | [简体中文](CONTRIBUTING.zh-CN.md)

# 参与 DisplayWeave

欢迎范围清晰的问题报告、硬件证据、文档修正和小型 Pull Request。

## 修改代码之前

1. 阅读 [ARCHITECTURE.zh-CN.md](ARCHITECTURE.zh-CN.md)、[ROADMAP.zh-CN.md](ROADMAP.zh-CN.md)及 `docs/` 下相关验收文档。
2. 保留兼容标识（`OpenSidecar.xcodeproj`、bundle/package ID、偏好键、Bonjour 服务），除非变更同时提供迁移设计与测试。
3. 不得削弱 GPL-3.0 或第三方署名。
4. 用户可见行为变更必须同时更新英文与简体中文文档。

## 构建与测试

```bash
./generate.sh
pnpm install --frozen-lockfile
pnpm build
pnpm run check:docs
pnpm run check:release
cd AndroidReceiver && ./gradlew clean test assembleDebug
```

请运行 [docs/release-checklist.zh-CN.md](docs/release-checklist.zh-CN.md) 中相关 Swift 与 Android 协议/策略自检。硬件结论需要可复现日志，包含设备型号、系统、传输、分辨率、codec、目标帧率、时长与实际渲染 FPS。

## Pull Request

- 每个变更只解决一个目的。
- 行为修复或功能先写失败测试，再证明通过。
- 运行 `git diff --check` 以及相关构建/测试。
- 明确哪些已验证、哪些是推断、缺少哪些硬件。
- 不提交签名秘密、私人截图、设备标识或生成的构建目录。

## 文档语言规则

当前用户指南使用英文主文件和 `.zh-CN.md` 中文配对，并互相链接。数字结果、命令、文件名、签名边界与安全警告必须一致。历史设计/实施记录可以保留原语言，但当前指南必须独立解释已发布行为。

## 许可证

贡献按仓库 [GPL-3.0](LICENSE) 分发。提交即表示你有权贡献，并会保留适用声明。参见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。
