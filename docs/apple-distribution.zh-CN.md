[English](apple-distribution.md) | [简体中文](apple-distribution.zh-CN.md)

# Apple 正式分发

源码新增 `tools/apple-distribution.py`，用于本地签名归档和导出。工具不上传、不创建 tag、不编辑 feed、不安装应用。今后的公开产物必须放在本项目 GitHub Releases，见[发行规则](release-downloads.zh-CN.md)。

## 就绪状态与边界

2026-10-16 本机 **Developer ID Application** 与 **Apple Distribution** 可用身份均为零；Apple Development 身份不足以完成这些导出。正式签名、公证仍**阻塞于外部凭据**。离线测试只证明校验与失败流程，不能代替已公证产物。已发布 p8 仍为 Mac ad-hoc / iOS unsigned 预览，见[预览分发](development-preview.zh-CN.md)。

原预览脚本继续可用。正式工作流不会使用预览的关闭库验证 entitlement，Mac 使用空的 `Mac/OpenSidecarMac.entitlements` 与 hardened runtime。不会生成/导出密钥、自动申请 provisioning 或上传开发者门户。

## 前提与预检

准备 Xcode、XcodeGen、包含私钥的既有分发身份，以及干净且已提交的源码。选择新的数字 `x.y.z` 版本和高于**全部**已发布版本的正整数 build；构建前在 GitHub 核对最高值，工具不能获知其他地方暂存或尚未发布的构建。

Mac 需安装 Developer ID Application 身份及同团队现有 `notarytool` Keychain profile。Sparkle 原密钥保留在 Keychain 账户 `ed25519`。找到已解析 Sparkle 的 `bin` 目录（包含 `generate_keys` 与 `sign_update`）；`generate_keys --account ed25519 -p` 只读取公钥，必须与 `project.yml` 一致。

```bash
python3 tools/apple-distribution.py preflight mac \
  --team TEAM_ID --identity CERTIFICATE_SHA1 \
  --notary-profile EXISTING_KEYCHAIN_PROFILE \
  --sparkle-bin build-verify-mac/SourcePackages/artifacts/sparkle/Sparkle/bin
```

将占位符替换为已存在的本地身份，参数不传密码。预检读取 Keychain 并运行 `notarytool history` 校验访问，不提交产物；非零退出表示前提尚未满足。

iOS 需 Apple Distribution，并通过 Xcode 安装匹配 profile。文件必须位于 `~/Library/MobileDevice/Provisioning Profiles/` 或 `~/Library/Developer/Xcode/UserData/Provisioning Profiles/`，传入绝对路径：

```bash
python3 tools/apple-distribution.py preflight ios \
  --team TEAM_ID --identity CERTIFICATE_SHA1 \
  --profile /absolute/path/to/installed.mobileprovision --method release-testing
```

`release-testing` 需要登记设备的 profile；`app-store-connect` 使用无设备列表的商店 profile。两者均为本地 `destination=export`，上传 App Store Connect 是独立操作。检查 team、到期日、准确 bundle ID、证书包含关系、UUID 与调试权限；兼容历史 application-identifier prefix，不假设其等于 team ID。

## 构建与证据

将 `preflight` 换成 `build`，保留其余参数并追加：

```text
--version 0.3.0 --build-number 16 --output build/apple-production-candidate-001
```

以上数字仅为示例，不代表预约或发行版本。输出必须是 `build/` 下的新目录，以私有权限创建并写入 `INCOMPLETE`。不会覆盖或删除既有目录。失败时保留日志和 archive，下次构建使用新目录。日志/profile 可能包含本地标识，整个目录不得提交 Git 或公开上传。

工具从 `project.yml` 生成工程，手动签名 Release archive 并本地导出，不启用自动 provisioning 或自动版本修改。校验**实际导出物**的 bundle/version/build、架构、strict/deep 签名、签名叶证书/team 和 entitlement；Mac 额外检查 feed 与 Sparkle 公钥，iOS 检查内嵌 profile 及应用/team entitlement。

Mac 同时归档 arm64 与 x86_64。提交 ZIP 到 Apple 公证服务，服务器等待上限 30 分钟，本地进程也有超时。仅 `Accepted` 可继续 staple、验证 staple 和 Gatekeeper。最终 ZIP 从已 staple 的应用生成，使用原 Sparkle 账户签名并验证。iOS 导出 arm64 并解包校验 IPA。全部成功后才删除 `INCOMPLETE`，生成 `receipt.json` 与 `SHA256SUMS.txt`。

超时后 Apple 任务可能仍运行。先查看保留的提交输出并查询状态，再决定是否重新提交；超时不等于通过。本地成功回执也不代表实机表现或已公开发行。正式工具目前为 Mac 生成 ZIP；引导式 DMG 仍属于预览工作流，不宣称已有公证生产 DMG。

## 自动验证

执行 `python3 tools/test-apple-distribution.py`。覆盖错误证书/team、到期/不匹配 profile、历史 prefix、调试权限、bundle/feed/key 替换、不可变输出与符号链接逃逸、手动导出配置、公证/stapler 失败阻断。合成流程验证必要关卡前不会生成回执或签名。本地预检按预期因缺少分发身份失败；补齐条件后仍需真实签名、导出、公证验证。
