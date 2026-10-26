[English](repository-layout.md) | [简体中文](repository-layout.zh-CN.md)

# 项目目录与清理

检查日期：2026-10-26。以下命令从仓库根目录执行。

| 位置 | 用途 | 保留规则 |
| --- | --- | --- |
| `Mac/`、`iOS/`、`Shared/`、`AndroidReceiver/` | 各平台应用和 Apple 共用代码 | 跟踪源码，保留平台与项目标识 |
| `MacTests/`、`tools/audits/` | 当前回归测试与历史基线探针 | 跟踪源码，基线探针仅作历史证据 |
| `src/`、`public/` | 网站源码、品牌资源和已发布更新源原文 | 跟踪源码，更新源属于发行数据 |
| `docs/` | 分类双语指南与历史记录 | 跟踪 Markdown，本地素材仍忽略 |
| `script/`、`tools/`、`.github/`、`fastlane/` | 启动、检查、打包和自动化 | 见[工具索引](../../tools/README.zh-CN.md) |
| `project.yml`、package/Gradle/Gem 清单与锁文件 | 可复现的项目和依赖输入 | 跟踪文件，Xcode 工程由配置生成 |
| `build/dev/mac/` | Mac 开发应用与启动器日志 | 可重新构建 |
| `build/verify/mac/`、`build/verify/ios/` | 不签名的编译检查 | 可重新构建 |
| `build/package/` | 正式与本地开发打包中间文件 | 可重新构建 |
| `build/site/client/`、`build/site/ssr/` | Pages 上传产物与 SSR 中间文件 | `pnpm build` 可重新生成 |
| `build/diagnostics/` | 临时测试输出 | 清理前将必要验收证据移到 `artifacts/verification/` |
| `artifacts/releases/vX.Y.Z/` | 完整本地已发布安装包集合 | 保留最新已核验正式版 |
| `artifacts/verification/` | 发行回执、选定日志与截图 | 本地忽略，分享前检查内容 |
| `node_modules/`、Android 的 `build/` 与 `.gradle/` | 工具管理的依赖和构建 | 可安装或重建，Gradle 保持原生布局 |
| `.git/` | 历史、引用和仓库元数据 | 保留 |

`build/` 与 `artifacts/` 均忽略。长期说明放在 `docs/`，不要放进可清理构建目录。凭据保留在钥匙串或原有外部签名目录，`AndroidReceiver/local.properties` 仍保留在本地。根目录保留 README、架构、贡献、安全、路线图、许可和署名等入口。

## 安全清理

```bash
python3 tools/clean-workspace.py
python3 tools/clean-workspace.py --apply
```

第一条预览准确路径和文件逻辑字节数；执行前停止本项目构建与开发服务。第二条仅删除固定清单中的生成目录，包含旧的根目录构建路径。遇到跟踪文件、根路径／父目录符号链接、误放签名密钥时拒绝执行。已安装应用、源码、Git 历史、验收记录、本地 SDK 设置及外部／全局缓存保留。

附加 `--dependencies` 可移除网站依赖，之后用 `pnpm install --frozen-lockfile` 恢复。要清理旧的本地**正式版**目录，先用 `gh release view --repo chenyuhao0628/displayweave --json tagName,isDraft,isPrerelease` 核对公开版本，再运行：

```bash
python3 tools/clean-workspace.py --keep-release v0.3.2
python3 tools/clean-workspace.py --keep-release v0.3.2 --apply
```

保留版本必须包含完整 8 个文件；清理前核验清单中全部 7 个哈希。缺失或损坏会停止清理。未知目录、预览版和更新的暂存版本不会被自动判断为过期。公开状态需独立对照 GitHub，本地校验和本身不证明已发布。在新正式版核验前保留上一版比较基线。本次先盘点再移除了历史预览产物，此单次判断不等同于通配符删除规则。

## 重建与维护

`./generate.sh` 重新生成 `OpenSidecar.xcodeproj`；`./run.sh` 转交既有签名[开发启动流程](workflow.zh-CN.md)。原生编译检查统一放在 `build/verify/`，`pnpm build` 和两个 Pages 流程统一使用 `build/site/client`。

`tools/package-release.sh` 要求明确的正式版 `X.Y.Z`、正整数构建号、固定签名身份和上一版应用比较基线。默认产物为 `artifacts/releases/vX.Y.Z/`，中间文件放在 `build/package/`。旧脚本名仅为同一正式版流程的兼容入口。`package-development-preview.sh` 仍是内部调试助手，输出到 `build/package/development/`，不作为公开发行通道。

`pnpm run check:docs` 递归发现双语指南，验证互链并检查本地／网站文档链接；`pnpm run check:release` 检查当前发行引用与已发布哈希。移动指南后同时运行两项，新使用指南保持双语。
