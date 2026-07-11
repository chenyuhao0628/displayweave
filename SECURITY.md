# Security

## 中文说明

DisplayWeave 不使用项目运营的云端视频中转，但当前 WiFi TCP 尚未实现
生产级加密配对，请仅在可信局域网使用。Apple 接收端支持 USB；Android
已实现通过 ADB forward 的实验性 USB，但尚待真机稳定性验证。Android USB
调试授权是设备对整台 Mac 的广泛调试信任。现有下载文件是开发预览：
macOS 仅作 ad-hoc 本地签名且未公证，iOS 仅供 Simulator，Android 为 Debug APK。

DisplayWeave is designed for local use. It captures your Mac display and sends
frames directly to a receiver on USB or the local network.

## Security Model

- No project-operated relay server is used for screen content.
- WiFi mode uses local-network discovery and a direct TCP connection.
- Apple-receiver USB mode uses local `usbmuxd` transport. Android USB uses a
  loopback-only, per-device `adb forward` mapping to the receiver's TCP port 9000.
- macOS Screen Recording permission is required for capture.
- macOS Accessibility permission is required for injected touch and scroll input.

## Current Caveats

- WiFi pairing and transport encryption are not production-grade in the current project.
- Use trusted local networks.
- Avoid exposing receiver ports outside your LAN.
- VPN TUN mode, firewall tools, and network filters can affect discovery and
  latency.
- Android receiver behavior depends on device vendor networking and decoder
  implementations.
- Enabling Android USB debugging trusts the Mac for broad ADB operations;
  DisplayWeave never bypasses the Android RSA authorization prompt.
- ADB is executed by absolute path with an argument array. DisplayWeave removes
  only mappings it owns and never invokes `adb forward --remove-all`.
- DisplayWeave does not currently provide signed and notarized release
  packages. Source builds and locally signed artifacts carry the trust of the
  local toolchain and signing identity used to produce them.

## Reporting Security Issues

If you find a security issue, avoid publishing exploit details in a public issue
first. Open a minimal private contact path if available on the repository owner
profile, or create a public issue with a high-level summary that does not
include reproduction details.

Useful security reports include:

- affected platform and OS version
- transport path: USB or WiFi
- whether the issue requires local-network access
- what permission state was active
- impact and expected mitigation

## Dependency And Build Trust

Build locally from source when evaluating DisplayWeave. Generated build output,
APK files, provisioning profiles, and signing credentials should not be
committed to the repository.
