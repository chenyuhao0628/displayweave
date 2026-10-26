[English](workflow.md) | [简体中文](workflow.zh-CN.md)

# 开发工作流

核对日期：2026-10-26。本指南针对源码开发，不代表发布新版本。

## 项目规则与官方依据

`AGENTS.md` 是简短的仓库指令入口。贡献规则放在 `CONTRIBUTING.md`，架构、UI 规范和验收证据使用链接引用，避免复制指令。本仓库不要求也不修改个人 Codex 配置。

2026-10-16 已读取以下 OpenAI 官方当前说明（原 developers.openai.com Codex 地址已跳转）：

- [Custom instructions with AGENTS.md](https://learn.chatgpt.com/docs/agent-configuration/agents-md)：先读取全局规则，再从项目根目录读取至工作目录，较近规则优先；同目录 `AGENTS.override.md` 优先于 `AGENTS.md`。规则应简短，默认合计发现预算为 32 KiB。修改发现规则后需重启会话重新加载。
- [Local environments](https://learn.chatgpt.com/docs/environments/local-environment)：通过 `.codex/` 共享项目动作与工作树初始化。现有 Run 动作调用 `script/build_and_run.sh`。
- [Build skills](https://learn.chatgpt.com/docs/build-skills)：按任务选择职责明确的技能；本仓库不强制要求安装特定插件或使用特定模型。

这些是带日期的来源记录，不保证产品文档永久不变。修改 Codex 专属行为前应重新核对官方说明。仓库规则补充用户请求，不授权无关发布或对外发消息。

## 环境与本地验证

前提：macOS 14+、包含所需 SDK 的 Xcode、XcodeGen、Swift、Node/pnpm（版本见 package.json），以及 Android 构建所需的 Java 17 / Android SDK。

```bash
xcodegen generate
pnpm install --frozen-lockfile
./script/build_and_run.sh --verify -macRole sender -autostart NO
./tools/run-swift-self-tests.sh
pnpm build
pnpm run check:docs
pnpm run check:release
(cd AndroidReceiver && ./gradlew --no-daemon test assembleDebug lintDebug)
```

Run 动作要求[配置固定的 Apple 签名身份](../guides/mac-permissions.zh-CN.md)，验证已签名开发应用后才启动，绝不回退临时签名。只编译、不签名也不启动：

```bash
xcodebuild -project OpenSidecar.xcodeproj -scheme OpenSidecarMac -configuration Debug -derivedDataPath build/verify/mac CODE_SIGNING_ALLOWED=NO ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO build
xcodebuild -project OpenSidecar.xcodeproj -scheme OpenSidecariOS -configuration Debug -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' -derivedDataPath build/verify/ios CODE_SIGNING_ALLOWED=NO build
```

## 修改与完成标准

1. 大规模重构前记录范围及可观察的验收条件，清点所有受影响界面与兼容边界。
2. 将策略、状态所有权与展示分离。行为修复先增加失败回归测试；纯展示修改用构建与视觉检查验证。
3. 运行受影响平台检查、文档检查和 `git diff --check`，每轮提交一个完整变更；进入 main 前运行完整 CI。
4. 刷新上游，记录采纳、已覆盖、延期的项目及提交来源。文本可合并不等于行为兼容。
5. 报告提交 ID、测试、远端状态和硬件缺口。编译、合成视频或模拟器检查不等于真实 LAN/USB 长时验证。

完整迭代的终点是：约定范围已实现、自动化通过、在工具允许范围内检查 UI 状态、同步远端，并为硬件缺口留下明确验收步骤。这不自动授权公开发版。

## 交互测试

仅在可用桌面会话中运行 `tools/run-mac-receiver-window-test.sh`。虚拟显示器创建和释放要求独立的在线显示器；合盖且没有独立显示器时跳过，不反复创建测试屏，也不重启 WindowServer。判断释放时使用当前在线列表，不能用已退役 ID 的状态查询作为存活证据。

截图与完整日志不进入 Git，在审计中记录可复现命令及脱敏结果。硬件证据必须包括型号、系统、连接方式、分辨率、codec、目标及实际 FPS、时长与重连行为。

## 当前验证覆盖

`tools/run-swift-self-tests.sh` 执行 63 组独立测试，以及抽取当前生产方法的捕获恢复／编码负载调参／iOS 视频准入测试；Android `test` 包含七组纯 Java 自测，并使用实际编译 SDK 的 boot classpath；`pnpm build` 执行 TypeScript、client/SSR 生产构建、双语预渲染与生成页面断言。添加共用源码后需构建两个 Apple 目标。

`python3 tools/test-apple-keychain.py --ios-simulator` 在随机测试命名空间验证真实 Mac/iOS 钥匙串身份持久化、密钥丢失恢复与显式重置。`python3 tools/test-secure-ios-receiver.py` 使用生产 PhoneReceiver/安全代码构建隔离应用，以认证 TLS 发送合成视频、检查撤销并切至后台。两者均创建/删除自己的模拟器，不改动已安装应用。后者可加 `--screenshots build/security-ui`，在测试邀请消耗后记录浅色/深色设置界面。模拟器测试需顺序运行，避免多个冷启动互相争用；不捕获用户桌面，不创建虚拟显示器。

旧版可选明文 iOS 网络冒烟测试：在隔离模拟器中以 `-insecureLegacyReceiver YES` 启动应用并保持前台，运行 `python3 tools/test-ios-receiver.py --port 9000`，测试后不带该参数重新启动。首次监听最多等待 10 秒，测试无效长度、分片控制消息、连接替换与存活。它会主动断开测试连接，不捕获桌面，也不证明视频性能。另行把应用切至后台，检查 9000 端口关闭。

实际本地 UI/构建证据及待完成硬件项见 [2026-10-16 验收报告](../archive/audits/source-upgrade-audit-2026-10-16.zh-CN.md)。

`python3 tools/test-secure-android-receiver.py --screenshots build/security-ui` 需要 SDK 命令行工具和 `system-images;android-35;default;arm64-v8a`。脚本创建/删除自己的 AVD，并用生产源码构建独立测试包。真实 Keystore 密钥参与 TLS 测试，再通过独立 ADB 转发，用 Mac 客户端检查正式配对/撤销/兼容 UI。测试身份与邀请仅留在一次性应用/容器中；截图在邀请使用后进行。

扩展 Android runtime 命令为 `python3 tools/test-android-experience.py --screenshots build/diagnostics/receiver-experience`。它复用一次性安全测试环境，额外检查合成视频比例、默认简洁状态、即时指标切换、黑边拒绝触控、中心坐标归一和静止长按，还需要 ffmpeg。iOS 安全测试现已覆盖只有心跳的首帧超时，以及首帧后的静态桌面豁免。见 [2026-10-26 升级记录](../verification/reliability-experience-upgrade.zh-CN.md)。

## 最终源码回归

运行 `python3 tools/test-tls-interop.py` 验证真实 Apple↔Java TLS。上述 Apple Keychain、安全 iOS 与安全 Android runtime 脚本须串行执行，只用独立容器。iOS fixture 同时检查视频视图替换归属、延迟销毁和回调/图层清理；Android 检查打包后的 adaptive icon。执行 `python3 tools/test-apple-distribution.py`（12 项离线检查）与 `python3 tools/export-brand-assets.py --check`（先安装 `tools/brand-requirements.txt`）。分发预检可能被外部证书阻塞，不能代替真实产物签名，见[Apple 正式打包](../releases/apple-distribution.zh-CN.md)。

## 目录维护

移除产物前阅读[目录与清理](repository-layout.zh-CN.md)。当前安装包与选定验收证据保存在忽略的 `artifacts/`，`build/` 可清理。`./run.sh` 转交 `script/build_and_run.sh`，网站输出和 Pages 上传统一为 `build/site/client/`。

CI 维护门禁还执行 `python3 tools/test-workspace-cleanup.py`、`python3 tools/test-docs-check.py` 和 `python3 tools/test-release-packaging.py`。文档检查递归发现双语对并检查链接；发行检查逐表核对已发布哈希。
