[English](README.md) | [简体中文](README.zh-CN.md)

# 工具索引

从仓库根目录运行工具。命令与证据标准见[开发流程](../docs/development/workflow.zh-CN.md)，产物规则见[目录与清理](../docs/development/repository-layout.zh-CN.md)。

| 任务 | 入口 |
| --- | --- |
| 生成／构建／启动 Mac | `generate.sh`、`run.sh` → `script/build_and_run.sh` |
| Swift 策略与生产方法夹具 | `tools/run-swift-self-tests.sh` |
| 隔离 TLS／身份／接收端运行检查 | `test-tls-interop.py`、`test-apple-keychain.py`、`test-secure-ios-receiver.py`、`test-secure-android-receiver.py`、`test-android-experience.py` |
| 打包／身份 | `package-release.sh`、`mac_signing.py`、`apple-distribution.py` |
| 更新完整性 | `generate-android-update-manifest.sh`、`verify-update-release.sh`、`check-release-links.sh` |
| 网站／文档 | `prerender.mjs`、`check-site.mjs`、`check-docs.py`；通过 `pnpm build` / `pnpm run check:docs` 执行 |
| 品牌／DMG 素材 | `export-brand-assets.py`、`create-guided-dmg.sh` |
| 清理生成文件 | `clean-workspace.py`，默认只预览 |
| 维护回归测试 | `test-workspace-cleanup.py`、`test-docs-check.py`、`test-release-packaging.py` |
| 历史探针 | `audits/2026-10-26/`，复现旧问题，不作为当前验收 |

被 CI、测试或外部自动化调用的工具保留稳定位置。历史打包名转交正式版入口，或明确限定为本地开发工具。凭据与生成的安装包始终不提交。
