[English](build-ios.md) | [简体中文](build-ios.zh-CN.md)

# 构建与安装 iOS 接收端

v0.3.1 提供 `DisplayWeave-iOS-unsigned-resigning-input.ipa` 作为设备重签名输入。这是未签名的 arm64 设备构建，不是模拟器包，也不能直接安装。源码开发者通常可用 Xcode 和自己的有效签名身份构建，参见[当前产物](../releases/current.zh-CN.md)。

## 从源码构建

1. 安装 Xcode 与所需 iOS SDK，在 Xcode 登录自己的 Apple 账户。
2. 在仓库根目录运行 `./generate.sh`（需要 XcodeGen），打开 `OpenSidecar.xcodeproj`。
3. 选择 `OpenSidecariOS`，进入 **Signing & Capabilities**，选自己的团队和匹配设备的 provisioning 配置。
4. 保留仓库原 bundle 标识。若个人团队需要唯一标识，只使用本地开发覆盖，不提交，也不要认为修改后仍与公开应用的身份／钥匙串兼容。
5. 连接设备、选择运行目标并启动应用；按设备要求完成开发与信任提示。
6. 接收端保持前台，按[配对流程](secure-transport.zh-CN.md)连接。

个人开发 provisioning 可能过期，以 Xcode 显示的有效期为准，到期后重新构建安装。重新生成 Xcode 工程可能覆盖本地工程编辑。签名材料保持在 Git 外。[不签名的模拟器编译命令](../development/workflow.zh-CN.md)用于兼容性检查，不产生可安装到设备的应用。

## 重签名已发布 IPA

需要自己的有效证书和匹配 provisioning profile，并保留符合该签名身份的应用／钥匙串 entitlements。签名或访问组身份改变可能使旧配对记录不可访问，必要时重新配对。DisplayWeave 不提供签名凭据，也不推荐第三方签名服务。[正式归档／导出工具](../releases/apple-distribution.zh-CN.md)单独说明分发前提。
