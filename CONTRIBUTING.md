# Contributing

## 中文说明

欢迎提交可复现的问题和范围清晰的 Pull Request。用户可见名称统一使用
DisplayWeave；`OpenSidecar` scheme、包名、Bundle ID、偏好键和
`_opensidecar._tcp` 属于兼容标识，未经迁移设计不要仅为改名而修改。
涉及协议或 Android 的改动至少运行 Gradle 构建与测试；涉及 Apple 端时
重新生成 Xcode 工程并构建对应 target。继续保留 GPL-3.0 和上游署名。

Contributions are welcome when they keep DisplayWeave focused: Android receiver
support, Chinese localization, local Mac/iOS usability, protocol clarity, and
stability fixes.

## Branch And Project Rules

- Keep work on feature branches, not directly on `main`.
- If `project.yml` changes, run `./generate.sh` before building in Xcode.
- Do not commit generated build products, APK files, DerivedData, logs, or
  local signing configuration.
- Prefer small changes that can be reviewed independently.
- Preserve GPL-3.0 license notices and upstream attribution.
- Keep DisplayWeave as the user-facing name. Treat `OpenSidecar` project/scheme
  names, `app.opendisplay.android`, bundle IDs, preference keys, and
  `_opensidecar._tcp` as compatibility identifiers unless a migration is
  explicitly designed and tested.

## Coding Guidelines

- Follow the existing Swift style for Mac and iOS code.
- Keep Android receiver classes narrow and platform-idiomatic.
- Keep protocol changes backward compatible where possible.
- Avoid blocking the Android UI thread with network writes.
- Keep user-facing copy concise, clear, and consistent across platforms.

## Documentation Guidelines

- README should explain project value and scope.
- Platform-specific details belong in the platform folder.
- Architecture and protocol decisions belong in `ARCHITECTURE.md`.
- Future work belongs in `ROADMAP.md`, not in scattered TODO comments.
- Avoid promising store releases, notarization, or encryption until they exist.

## Verification Expectations

Use the smallest checks that prove the change:

```bash
xcodebuild -project OpenSidecar.xcodeproj -scheme OpenSidecarMac -configuration Debug -derivedDataPath build-run -clonedSourcePackagesDirPath build-run/SourcePackages build
```

```bash
xcodebuild -project OpenSidecar.xcodeproj -scheme OpenSidecariOS -configuration Debug -sdk iphonesimulator -derivedDataPath build-verify-ios -clonedSourcePackagesDirPath build-verify-ios/SourcePackages build CODE_SIGNING_ALLOWED=NO
```

```bash
cd AndroidReceiver
./gradlew clean
./gradlew assembleDebug
./gradlew test
```

`AndroidReceiver/scripts/build_debug_apk.sh` remains an optional compatibility
check for the legacy manual SDK-tools build path.

## Good Issue Reports

Useful reports include:

- macOS version and Mac model
- iOS/iPadOS or Android version
- receiver device model
- mirror or extend mode
- USB or WiFi
- whether VPN TUN mode is enabled
- what permissions are granted
- relevant logs or exact error text

See [SUPPORT.md](SUPPORT.md) for more detail.
